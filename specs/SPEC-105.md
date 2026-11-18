# SPEC-105: Workflow que roda a etapa de agente quando a label `agente` é aplicada, validado num repositório de teste

**Issue:** #105 · **PRD:** F4 (item 5 do fatiamento, M2) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-18

## Contexto
A F4 do [PRD](../docs/prd.md) pede que aplicar `agente` numa issue dispare a etapa de agente no GitHub Actions, com o plugin instalado no job e sem sessão local. A [ADR 0015](../docs/adr/0015-dispatcher-no-github-actions.md) (#99) decidiu o caminho: o CLI direto no job, chamando o mesmo `scripts/stage-model.sh run` do `/fabrica:avancar`, em `ubuntu-latest`, com a assinatura (`CLAUDE_CODE_OAUTH_TOKEN`) e disparo por `issues: labeled` filtrado pela label `agente`. A ADR deixou para esta issue o passo de falha, o caminho do CI do PR do agente e a conferência, no runner, de que o modo `auto` deixa a etapa terminar. A #106 (isolamento do job), a #107 (retomada por evento) e a #108 (instalação pelo `/fabrica:setup`) partem do que esta issue entregar. A #94 está fechada e a #99 entrou no PR #194.

## Objetivo
Existe um workflow do GitHub Actions no plugin (`templates/workflows/agente.yml`) que, quando o usuário aplica `agente` numa issue em estado "Aguardando triagem", roda o `/fabrica:triagem` no runner com o plugin instalado, e esse workflow foi validado de ponta a ponta num repositório de teste privado.

## Comportamento esperado
O usuário aplica a label `agente` numa issue aberta de um repositório com o workflow em `.github/workflows/agente.yml`. O workflow:

1. **Filtra o evento.** Só roda em `issues` `labeled` com `github.event.label.name == 'agente'` e a issue aberta. Qualquer outra label, inclusive as que as etapas aplicam (`modelo:*`, `precisa-info`, `spec-pronta`, `em-andamento`), não roda o job.
2. **Serializa por issue.** Grupo de concorrência `fabrica-<nº da issue>`, sem cancelar a execução em curso.
3. **Prepara o runner:** faz o checkout do repositório do projeto sem guardar credenciais, instala o CLI do Claude Code e instala o plugin `fabrica@fabrica` a partir do marketplace `ftenorio99/fabrica`, que é privado (ver Decisões).
4. **Roda o despacho** (`scripts/dispatch.sh run <nº>` do plugin instalado), que relê a issue e decide:

   | Situação da issue no momento do despacho | O que acontece | Resultado do job |
   |---|---|---|
   | fechada, ou sem a label `agente` (removida depois do evento) | não executa nada; imprime o motivo no log | sucesso |
   | já tem comentário `<!-- fabrica:triagem -->` (não está em "Aguardando triagem") | não executa nada e não comenta; imprime o estado no log. As etapas seguintes são da #107 | sucesso |
   | `em-andamento` recente (último `labeled em-andamento` da timeline há menos de 2 h, regra de [estados.md](../skills/status/estados.md#etapa-em-andamento)) | não executa nada e não mexe na label: outra execução (o `avancar` local, por exemplo) está nela | sucesso |
   | `em-andamento` aplicada há 2 h ou mais (esquecida) | remove e aplica de novo a `em-andamento` e segue como na linha abaixo | conforme a etapa |
   | sem marcador de triagem e sem `em-andamento` | aplica `em-andamento`, roda `bash <plugin>/scripts/stage-model.sh run triagem <nº> <labels modelo:* da issue>` e grava o JSON do `claude -p` em `$RUNNER_TEMP` | sucesso se o `claude` saiu com 0, o JSON é legível e `is_error` é falso; senão, falha |

5. **Desmarca sempre.** Um passo `if: always()` (`dispatch.sh unmark <nº>`) remove a `em-andamento`, mas só se foi este job que a aplicou. Numa issue pulada por `em-andamento` recente de outra execução, a label fica.
6. **Publica a falha.** Um passo `if: failure()` (`dispatch.sh fail <nº>`) comenta na issue com o marcador `<!-- fabrica:dispatcher -->` na primeira linha, a etapa, o motivo e o link do run. Motivos possíveis:

   | Motivo | Quando |
   |---|---|
   | `permissao` | o JSON tem `permission_denials` não vazio; o comentário lista os nomes das ferramentas negadas, sem os argumentos |
   | `erro` | saída do `claude` diferente de 0, `is_error` verdadeiro ou JSON ilegível, sem negação de permissão |
   | `labels` | o `stage-model.sh` saiu com 2 (duas ou mais `modelo:*`) |
   | `sem-resultado` | o passo do despacho falhou sem gravar o JSON: tempo do passo esgotado ou erro antes do `claude` (instalação, `gh`) |

   O comentário nunca traz o texto de `result`, o conteúdo de variáveis de ambiente nem valores de secrets: só o motivo, a lista do caso `permissao`, o código de saída e o link do run (`$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID`). A issue continua em "Aguardando triagem", e o usuário pode reaplicar `agente` ou rodar `/fabrica:triagem <nº>` local.
7. **Tempo:** o passo do despacho tem `timeout-minutes: 30` e o job `timeout-minutes: 40`, para que o tempo esgotado no passo vire falha do passo e o passo `if: failure()` ainda rode.

O comentário `<!-- fabrica:dispatcher -->` é registrado em [estados.md](../skills/status/estados.md) como o comentário de lição: não é do agente nem do usuário, não é resposta nova e não muda o estado. A tabela de labels passa a dizer que a `em-andamento` é aplicada pelo `avancar` e pelo dispatcher.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `templates/workflows/agente.yml` dispara só em `issues` com `types: [labeled]`, e o job tem `if` exigindo `github.event.label.name == 'agente'` e `github.event.issue.state == 'open'`. | unitário — `scripts/test-dispatch.sh` lê o YAML com PyYAML e confere `on`, `types` e o `if` do job |
| CA2 | O workflow tem `concurrency.group` com `github.event.issue.number` e `cancel-in-progress: false`, `runs-on: ubuntu-latest`, `timeout-minutes: 40` no job e `timeout-minutes: 30` no passo do despacho. | unitário — `scripts/test-dispatch.sh` |
| CA3 | `permissions` do workflow tem exatamente `contents: read` e `issues: write`. | unitário — `scripts/test-dispatch.sh` |
| CA4 | Nenhuma linha de `run:` do workflow contém `${{`: os valores do evento e os secrets chegam aos passos só por `env:`. O `FABRICA_PLUGIN_TOKEN` aparece só no `env` do passo de instalação do plugin, e o `CLAUDE_CODE_OAUTH_TOKEN` só no `env` do passo do despacho. | unitário — `scripts/test-dispatch.sh` |
| CA5 | O checkout do projeto usa `persist-credentials: false`. | unitário — `scripts/test-dispatch.sh` |
| CA6 | `dispatch.sh run` numa issue fechada, ou sem `agente`, ou com comentário `<!-- fabrica:triagem -->` sai com 0 sem chamar o `claude`, sem aplicar label e sem comentar. | unitário — `scripts/test-dispatch.sh`, com `gh` e `claude` falsos que registram as chamadas |
| CA7 | `dispatch.sh run` com `em-andamento` cujo último `labeled` tem 1 h 59 min sai com 0 sem chamar o `claude` e sem mexer na label; com exatamente 2 h 00 min ou mais, remove e aplica de novo a label e roda a etapa (o limite de 2 h conta como esquecida, como em estados.md). | unitário — `scripts/test-dispatch.sh`, com a timeline falsa |
| CA8 | `dispatch.sh run` numa issue em "Aguardando triagem" aplica `em-andamento` antes de chamar o `claude`, chama o `stage-model.sh run triagem <nº>` passando só as labels `modelo:*` da issue (uma label `bug` ou um nome com `;` ou `$(...)` não chega ao comando) e sai com 0 quando o JSON tem `is_error: false`. | unitário — `scripts/test-dispatch.sh`, com `FABRICA_CLAUDE_BIN` falso que registra os argumentos |
| CA9 | `dispatch.sh run` sai com código diferente de 0 quando o `claude` sai com erro, quando o JSON é ilegível ou quando `is_error` é verdadeiro. | unitário — `scripts/test-dispatch.sh` |
| CA10 | `dispatch.sh unmark` remove a `em-andamento` só quando o `run` do mesmo job a aplicou; depois de um `run` que pulou por `em-andamento` recente, ele não chama `gh issue edit`. | unitário — `scripts/test-dispatch.sh` |
| CA11 | `dispatch.sh fail` comenta com `--body-file`, primeira linha `<!-- fabrica:dispatcher -->`, a etapa, o link do run e o motivo certo em cada caso da tabela (`permissao` com os nomes das ferramentas, `erro`, `labels`, `sem-resultado`); o corpo não contém o texto de `result` do JSON falso nem o valor de uma variável `CLAUDE_CODE_OAUTH_TOKEN` definida no teste. | unitário — `scripts/test-dispatch.sh` |
| CA12 | `skills/status/estados.md` registra o comentário `<!-- fabrica:dispatcher -->` como ignorado nas regras de estado e a `em-andamento` aplicada também pelo dispatcher; um comentário desses depois do marcador de triagem não conta como resposta nova. | manual — leitura do diff na revisão |
| CA13 | **Ponta a ponta, caminho feliz:** no repositório de teste, aplicar `agente` numa issue nova gera um run que termina verde, publica o comentário `<!-- fabrica:triagem -->` com a linha de custo, deixa a issue sem `em-andamento` e aplica as labels da triagem. | e2e — repositório de teste `ftenorio99/fabrica-teste`, com o link do run no PR |
| CA14 | **Sem cascata:** no mesmo teste do CA13, as labels aplicadas pela triagem (`modelo:*`, `precisa-info` ou `spec-pronta`) não geram run novo, e aplicar uma label qualquer (ex.: `bug`) gera no máximo um run com o job pulado. `gh run list --workflow agente.yml` mostra isso. | e2e — repositório de teste, com a saída do `gh run list` no PR |
| CA15 | **Reaplicação:** remover e reaplicar `agente` na issue já triada do CA13 gera um run verde que não chama o `claude` e não comenta na issue. | e2e — repositório de teste |
| CA16 | **Modo `auto` no runner:** o resultado do CA13 diz se o `auto` deixou a triagem terminar. Se o run falhar por `permissao`, o comentário `<!-- fabrica:dispatcher -->` lista as ferramentas negadas, o CA13 fica reprovado e a implementação para com `escalonado`, registrando o resultado na issue em vez de contornar o modo de permissão. | e2e — repositório de teste |
| CA17 | `docs/guias/dispatcher.md` explica o piloto: o que o workflow faz (só a triagem), os dois secrets (`CLAUDE_CODE_OAUTH_TOKEN` por `claude setup-token`; `FABRICA_PLUGIN_TOKEN` fine-grained, só `contents: read` no `ftenorio99/fabrica`), como copiar o arquivo à mão, o comentário de falha e os limites (sem isolamento até a #106, CI do PR na aprovação manual); o índice `docs/README.md` cita o guia e o `AGENTS.md` cita `templates/workflows/` e o `scripts/test-dispatch.sh`. | manual — leitura do diff na revisão |

## Fora de escopo
- Encadear as etapas seguintes (`spec`, `implementar`, `revisar`) e reagir a resposta, `spec-aprovada`, comentário no PR ou checklist: #107.
- Restringir a rede do runner, trocar o `GITHUB_TOKEN` pelo token fine-grained e esconder o secret do agente: #106.
- Copiar o workflow pelo `/fabrica:setup` e ligar no kairo: #108. Aqui a cópia para o repositório de teste é manual.
- Disparar o CI do PR do agente por `workflow_dispatch` (ver Decisões).
- Runner self-hosted e API key (plano B da ADR 0015).

## Desenho técnico
**Arquivos e módulos:**
- `templates/workflows/agente.yml` (novo): o workflow descrito em "Comportamento esperado". Passos: `actions/checkout@v7` do projeto (`persist-credentials: false`); instalação do CLI (`npm install -g @anthropic-ai/claude-code` e `claude --version` no log); instalação do plugin com `GH_TOKEN: ${{ secrets.FABRICA_PLUGIN_TOKEN }}` e `CLAUDE_CODE_PLUGIN_PREFER_HTTPS: 1` no `env` do passo, rodando `gh auth setup-git`, `claude plugin marketplace add ftenorio99/fabrica`, `claude plugin install fabrica@fabrica` e gravando o `installPath` de `claude plugin list --json` em `$GITHUB_OUTPUT`; despacho com `GH_TOKEN: ${{ github.token }}`, `CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` e `ISSUE_NUMBER: ${{ github.event.issue.number }}` no `env`; `unmark` (`if: always()`) e `fail` (`if: failure()`), também só com `GH_TOKEN` e `ISSUE_NUMBER`.
- `scripts/dispatch.sh` (novo): subcomandos `run <nº>`, `unmark <nº>` e `fail <nº>`. O repositório vem de `GITHUB_REPOSITORY`. O estado entre os passos fica em `$RUNNER_TEMP/fabrica-dispatch/` (`marked`, `stage.json`, `stage.exit`). Usa `gh issue view <nº> --json state,labels,comments`, `gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp` (horário do último `labeled em-andamento`), `gh issue edit <nº> --add-label|--remove-label em-andamento` e `gh issue comment <nº> --body-file <arquivo>`. Chama o `stage-model.sh run` do mesmo diretório; o `FABRICA_CLAUDE_BIN` continua valendo para os testes. Saídas: 0 sucesso ou pulo; 1 uso inválido ou falha da etapa; 2 inconsistência de labels.
- `scripts/test-dispatch.sh` (novo): CA1 a CA11, no estilo de `scripts/test-stage-model.sh` (função `check`, `gh` e `claude` falsos no `PATH` de uma pasta temporária, `RUNNER_TEMP` temporário).
- `skills/status/estados.md`: o comentário `<!-- fabrica:dispatcher -->` junto do comentário de lição e a coluna "Aplicada por" da `em-andamento` com "avancar, dispatcher".
- `docs/guias/dispatcher.md` (novo), `docs/README.md` (linha do guia), `AGENTS.md` (estrutura e comando do teste), `.claude-plugin/plugin.json` (sobe a `version`, de 0.42.0 para 0.43.0).
- Repositório de teste `ftenorio99/fabrica-teste` (novo, fora deste repo): criado privado com `gh repo create ftenorio99/fabrica-teste --private`, com `README.md` e `.gitignore` no primeiro commit, mais `AGENTS.md` e `docs/prd.md` mínimos para a triagem ter o que ler e o workflow copiado para `.github/workflows/agente.yml` (o workflow de `issues` só roda a partir da branch padrão). Labels com `bash scripts/setup-labels.sh ftenorio99/fabrica-teste`. Os dois secrets são ação externa do usuário ([ADR 0012](../docs/adr/0012-acao-externa-com-checklist.md)): o implementador abre a checklist na #105 com `claude setup-token` e `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo ftenorio99/fabrica-teste`, e com a criação do token fine-grained e `gh secret set FABRICA_PLUGIN_TOKEN --repo ftenorio99/fabrica-teste`.

**Dados:** nenhum.

**Interfaces:**
- `dispatch.sh run <nº>` → 0 (etapa ok ou pulo, com o motivo do pulo numa linha `pulo: <motivo>` na saída padrão), 1 (falha da etapa ou uso inválido), 2 (labels `modelo:*` inconsistentes).
- `dispatch.sh unmark <nº>` → 0 sempre que o `gh` responder; não falha o job por label já removida.
- `dispatch.sh fail <nº>` → publica o comentário e sai com 0.
- Secrets do repositório: `CLAUDE_CODE_OAUTH_TOKEN` e `FABRICA_PLUGIN_TOKEN`.

**Decisões:**
- Etapa disparada pela label `agente`: só a `triagem`, porque a tabela de estados faz "sem marcador de triagem" ser o estado "Aguardando triagem" depois de `agente` e o PRD deixa as etapas seguintes para a retomada por evento (F5, #107). Alternativa descartada: rodar o `avancar` e encadear as etapas, o que invade a #107. (recomendação da triagem)
- Onde o workflow mora: `templates/workflows/agente.yml` no plugin, copiado à mão para o repositório de teste, porque a ADR 0015 diz que a #108 copia o workflow pelo `/fabrica:setup`. Alternativa descartada: escrevê-lo só no repositório de teste, o que obrigaria a #108 a recriá-lo. (recomendação da triagem)
- Repositório de teste: `ftenorio99/fabrica-teste`, novo e privado, porque o PRD manda validar num repositório de teste antes do kairo (#108) e as regras globais mandam criar repositórios novos como privados. Alternativa descartada: o kairo, que contraria a ordem do PRD. (recomendação da triagem)
- CI do PR do agente: aceitar a aprovação manual do run no piloto, porque a ADR 0015 aponta isso como uma das duas saídas e a #106 troca o token logo depois. Nesta issue o job só roda a triagem e não abre PR, então a decisão vale para a #107 e fica registrada no guia. Alternativa descartada: `workflow_dispatch` do CI depois do push, que exige mudar o CI do projeto. (recomendação da triagem)
- Plugin privado: o passo de instalação usa um secret `FABRICA_PLUGIN_TOKEN` (token fine-grained com `contents: read` só no `ftenorio99/fabrica`) como `GH_TOKEN` e `gh auth setup-git`, que é o caminho da documentação do Claude Code para marketplace privado no Actions; o `GITHUB_TOKEN` do job só alcança o próprio repositório. O token fica só no `env` desse passo, então o passo da etapa não o vê. Alternativa descartada: tornar o `fabrica` público, que é decisão do usuário e muda a visibilidade do repositório; e clonar o plugin com `actions/checkout` + `--plugin-dir`, que foge da instalação da D1 da ADR 0015.
- Lógica num script do plugin (`scripts/dispatch.sh`), com o YAML só chamando os subcomandos, porque assim os pulos, a marcação e a falha ganham testes com `gh` e `claude` falsos, e a #107 reusa o script. Alternativa descartada: a lógica em `run:` no YAML, que só se testa no Actions.
- Comentário de falha com marcador próprio `<!-- fabrica:dispatcher -->`, ignorado pelas regras de estado como a lição, porque sem marcador ele contaria como comentário do usuário, e com o marcador `triagem` faria a issue parecer triada. Alternativa descartada: não comentar e deixar a falha só no log do Actions, que a ADR 0015 descarta ("publicar o motivo na issue").
- `em-andamento` removida no fim de toda execução que a aplicou (`if: always()`), como o passo 4 do laço do `avancar`. Alternativa descartada: deixá-la expirar em 2 h, como a ADR 0015 descreve para a falha, o que trava a reaplicação de `agente` por 2 h sem ganho.
- Tempo do passo (30 min) menor que o do job (40 min), para o tempo esgotado ainda cair no `if: failure()`. Alternativa descartada: só o `timeout-minutes` do job, que cancela o job e não garante o passo de falha.
- CLI instalado por `npm install -g @anthropic-ai/claude-code`, sem fixar versão, com a versão impressa no log. Alternativa descartada: o instalador nativo (`curl … | bash`), que funciona igual mas executa um script baixado no runner sem o registro de versão do npm.
- `actions/checkout@v7`, a versão maior atual. Alternativa descartada: fixar por SHA, que a #106 pode adotar junto com o resto do endurecimento do job.

**Fontes da documentação:**
- Claude Code 2.1.327 — `claude --help`, `claude plugin list --help` (`--json`, campo `installPath` conferido na saída local), `claude plugin marketplace add --help`, `claude plugin install --help`; Context7 `/websites/code_claude` (instalação por npm e instalador nativo; marketplace privado no GitHub Actions com `GH_TOKEN` e `gh auth setup-git`; `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`). Versão do Context7 não confirmada: a doc do site não é versionada.
- actions/checkout v7.0.1 — Context7 `/actions/checkout/v7.0.1` (`README.md`: `repository`, `token`, `persist-credentials`, `path`).
- GitHub Actions (`GITHUB_TOKEN` não dispara workflows, `issues: labeled`) — fatos da ADR 0015, conferidos em 2026-11-18; o implementador reconfere ao escrever o workflow.
- gh 2.104.0 — `gh issue view --help` (campos `state`, `labels`, `comments`), `gh issue edit --help` (`--add-label`, `--remove-label`), `gh issue comment --help` (`--body-file`), `gh auth setup-git --help`, `gh repo create --help` (`--private`), `gh secret set --help` (`--repo`), `gh run list --help` (`--workflow`).

**ADR:** nenhum novo; segue a [ADR 0015](../docs/adr/0015-dispatcher-no-github-actions.md). O tratamento do repositório privado do plugin é um detalhe da instalação da D1, registrado no guia.

## Testes
- `bash scripts/test-dispatch.sh`: CA1 a CA5 leem `templates/workflows/agente.yml` com `python3 -c 'import yaml'` (falha com mensagem clara se o PyYAML faltar); CA6 a CA11 rodam o `dispatch.sh` com um `gh` falso que responde a `issue view`, `api .../timeline`, `issue edit` e `issue comment` a partir de arquivos da pasta temporária e registra as chamadas, e com `FABRICA_CLAUDE_BIN` apontando para um `claude` falso que imprime um JSON escolhido pelo caso e sai com o código escolhido.
- `bash scripts/test-stage-model.sh` continua passando (o `stage-model.sh` não muda).
- CA13 a CA16: no `ftenorio99/fabrica-teste`, com os secrets cadastrados; os links dos runs e a saída do `gh run list` vão no PR. As issues de teste ficam fechadas no fim, com um comentário dizendo que eram teste.

## Passos de produção
nenhum

## Riscos e dúvidas
- O `auto` pode bloquear a triagem no runner, como bloqueou a `spec` no `-p` local (ADR 0013). O CA16 registra o resultado; se bloquear, a issue para com `escalonado` e o próximo passo é decidido com o usuário (regra de permissão do projeto, ou a #106 rodar o job no `sbx` com `bypassPermissions`).
- Até a #106, o job roda sem restrição de rede e com o `GITHUB_TOKEN` (issues: write) ao alcance do agente. O piloto fica só no repositório de teste, com issues escritas pelo próprio usuário.
- O `gh auth setup-git` grava o `gh` como helper do git no runner; no passo da etapa, o helper usa o `GH_TOKEN` daquele passo (o `GITHUB_TOKEN`), não o `FABRICA_PLUGIN_TOKEN`. O implementador confere isso no CA13.
- A linha de custo depende do log da sessão no runner; se faltar, sai `tokens=nao-medido` e o CA13 ainda passa.
- Os fatos da ADR 0015 mudam rápido (flags do CLI, termos); o implementador reconfere ao escrever o workflow.

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
