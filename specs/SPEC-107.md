# SPEC-107: Retomada por evento: resposta, `spec-aprovada`, comentário no PR e checklist concluída disparam a etapa seguinte, sem cascata

**Issue:** #107 · **PRD:** F5 (item 7 do fatiamento, M2) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-22

## Contexto
A F5 do [PRD](../docs/prd.md) pede que cada gesto do usuário (resposta a perguntas, `spec-aprovada`, comentário no PR e checklist de ação externa concluída) dispare a etapa seguinte, até o próximo portão. Hoje o dispatcher ([SPEC-105](SPEC-105.md), [ADR 0015](../docs/adr/0015-dispatcher-no-github-actions.md)) só roda a triagem quando `agente` é aplicada, e o resto do fluxo depende do `/fabrica:avancar` na máquina do usuário. Depois da [SPEC-106](SPEC-106.md) ([ADR 0016](../docs/adr/0016-isolamento-do-job-do-dispatcher.md)), as escritas do job saem com o `FABRICA_GH_TOKEN`, cujos eventos disparam workflows: o filtro do workflow virou a única trava contra cascata, e agente e usuário usam a mesma conta do GitHub.

## Objetivo
O workflow `agente.yml` acorda com os gestos do usuário na issue e no PR, ignora os eventos que o próprio agente gera, e o `dispatch.sh` relê o estado da issue pela tabela de [estados.md](../skills/status/estados.md) e roda as etapas de agente em sequência, até um portão do usuário ou o teto de 4 etapas, com isso provado num repositório de teste.

## Comportamento esperado

### 1. Eventos que acordam o workflow
| Evento | Tipos | Passa no filtro quando |
|---|---|---|
| `issues` | `labeled` | a issue está aberta e a label é `agente` ou `spec-aprovada` |
| `issue_comment` | `created` | o PR está aberto e o corpo do comentário **não** começa com `<!-- fabrica:`; ou a issue está aberta, tem a label `agente` e o corpo não começa com `<!-- fabrica:` |
| `issue_comment` | `edited` | é uma issue (não um PR), está aberta, tem a label `acao-externa` e o corpo começa com `<!-- fabrica:acao` |
| `pull_request_review` | `submitted` | o PR está aberto e o corpo da review não começa com `<!-- fabrica:` (corpo vazio passa) |
| `pull_request_review_comment` | `created` | o PR está aberto e o corpo do comentário não começa com `<!-- fabrica:` |

O filtro é uma única expressão, usada no `if` do job e no grupo de concorrência (seção 2). O `startsWith` das expressões do GitHub não diferencia maiúsculas. Um evento barrado gera um run com o job `skipped`, que não entra no grupo de nenhuma issue.

O filtro é a primeira trava. A segunda é a releitura do estado: um evento que passou no filtro mas não muda o estado (por exemplo, uma review `APPROVED` de corpo vazio, que [estados.md](../skills/status/estados.md) não conta como comentário do usuário, ou a edição de uma checklist que ainda tem item desmarcado) termina num pulo, sem chamar o `claude`.

### 2. Concorrência e tempo
- **Grupo:** `fabrica-<nº do evento>` quando o filtro passa, onde o número é o da issue ou o do PR. Quando o filtro não passa, o grupo é `fabrica-ignorado-<run_id>`, único por run, para o run pulado nunca esperar nem substituir o de um gesto.
- `cancel-in-progress: false`. O GitHub mantém no máximo um run pendente por grupo e substitui o pendente pelo mais novo; isso não perde gesto, porque o run que fica relê o estado.
- Um evento do PR e um da issue correm em grupos diferentes. A trava entre eles é a `em-andamento` na issue (seção 4).
- **Tempo:** o passo do despacho tem `timeout-minutes: 100` e o job, `timeout-minutes: 110`, abaixo das 2 h da `em-andamento`, para caber o laço de até 4 etapas (o `implementar` com o `revisar` encadeado pode passar de 30 min).

### 3. Qual issue o evento acorda
| Evento | Issue |
|---|---|
| `issues`, ou `issue_comment` numa issue | a própria issue |
| `issue_comment` num PR, `pull_request_review` ou `pull_request_review_comment` | a issue resolvida a partir do PR, como abaixo |

**Resolução do PR:** `gh pr view <nº do PR> --json state,headRefName,closingIssuesReferences`.
- O PR precisa estar aberto e citar **exatamente uma** issue em `closingIssuesReferences` (o `Fixes #<nº>` do corpo, regra global de PR). Zero ou mais de uma: pulo `pulo: PR #<nº> sem uma issue única`.
- A branch da issue resolvida, pela regra da "spec da issue" de [estados.md](../skills/status/estados.md) (comentário de spec mais recente, ou a spec curta do atalho), precisa ser igual ao `headRefName` do PR. Diferente, ou sem branch: pulo `pulo: PR #<nº> não é da branch da issue #<nº>`.
- A issue resolvida fechada ou sem `agente` também é pulo. Isso vale para a issue de runbook do `/fabrica:lancamento`, que não tem `agente`.

### 4. Despacho (`dispatch.sh run <issue|pr> <nº>`)
1. Resolve a issue (seção 3).
2. **Freio de cascata:** lê a timeline da issue (`gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp`). Se há **8 ou mais** eventos `labeled em-andamento` com idade de até 3.600 s (inclusive), não roda nada e comenta na issue com `<!-- fabrica:dispatcher -->`, motivo `freio`, o número de execuções na última hora e a orientação de rodar `/fabrica:avancar <nº>` na máquina depois de conferir os comentários. Sai com 0. Com 7 ou menos nessa janela, segue.
3. **`em-andamento`:** mesma regra da SPEC-105, sobre a issue resolvida: recente (menos de 2 h) é pulo sem mexer na label; esquecida (2 h ou mais) é removida e aplicada de novo.
4. **Estado inicial:** coleta os dados da seção 5 e lê o estado com `issue-state.py`. Inconsistência: pulo `pulo: issue #<nº> com inconsistência <código>`, sem comentar e sem mexer em label (o `/fabrica:status` mostra o alerta). Estado em que o usuário age (1, 1a, 3, 7, 9, 13): pulo `pulo: issue #<nº> em <estado> (portão do usuário)`, sem aplicar `em-andamento`.
5. **Marca** `em-andamento` uma vez, antes da primeira etapa, e grava o número da issue no estado do job (`$RUNNER_TEMP/fabrica-dispatch/issue`).
6. **Laço**, com no máximo **4 etapas por run**:
   1. grava a etapa em `$RUNNER_TEMP/fabrica-dispatch/stage` e roda `bash <plugin>/scripts/stage-model.sh run <etapa> <nº da issue> <labels modelo:*>`, com as labels relidas antes de cada etapa;
   2. falha (saída diferente de 0, JSON ilegível ou `is_error` verdadeiro): para o laço e sai com 1 (ou 2, labels `modelo:*`), como na SPEC-105;
   3. relê o estado e para quando: o estado é de usuário (**portão**, fim normal); tem inconsistência; é o **mesmo estado** de antes da etapa (**sem avanço**, como o limite de 3 em andamento); ou o teto foi atingido;
   4. **teto:** depois da 4ª etapa, se o estado ainda é de agente, não começa outra e comenta na issue com `<!-- fabrica:dispatcher -->`, motivo `teto`, o estado em que ela ficou e a orientação de rodar `/fabrica:avancar <nº>` ou fazer um novo gesto.
7. O `implementar` encadeia o `revisar` no mesmo processo e conta como **uma** etapa, como no `/fabrica:avancar`.
8. O dispatcher não aplica o escalonamento de modelo do `/fabrica:avancar` (lição `modelo` e troca da `modelo:*`).

A etapa de cada estado é a da tabela do passo 3 do [`/fabrica:avancar`](../skills/avancar/SKILL.md): 1b → a etapa do marcador do comentário de ação; 2 → `triagem`; 4 → `spec` se o comentário do agente mais recente entre triagem e spec é de spec, senão `triagem`; 5 e 6 → `spec`; 8 → `implementar`; 10, 11 e 12 → `revisar`.

### 5. Leitor de estado (`scripts/issue-state.py`)
Código puro, sem rede: recebe JSON e imprime uma linha. A coleta é do `dispatch.sh`, com `gh`:

| Dado | Comando | Quando |
|---|---|---|
| issue | `gh issue view <nº> --json state,labels,comments` | sempre |
| comentários no formato do `acao-status.py` | `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` | só com `acao-externa` |
| PRs da branch | `gh pr list --head <branch> --state all --json number,state,isDraft,mergedAt,statusCheckRollup,reviewDecision,reviews,comments,updatedAt` | quando a issue tem branch |

Subcomandos:
- `issue-state.py branch <issue.json>` → imprime a branch da issue (regra da "spec da issue" de estados.md) ou nada.
- `issue-state.py state <pacote.json>` → `linha=<1|1a|1b|2…13> etapa=<triagem|spec|implementar|revisar|-> quem=<agente|usuario> inconsistencia=<código|->`. O pacote tem `issue`, `acao` (a linha do `acao-status.py`, ou `null`) e `prs` (a lista do `gh pr list`, ou `[]`).

Regras, iguais às de estados.md:
- **Comentário do agente:** na primeira linha, depois de tirar espaços do começo, começa com `<!-- fabrica:<etapa>` seguido de espaço ou `-->`, com `<etapa>` em `triagem`, `spec`, `implementar`, `revisar`, `backlog`, `lancamento`, ou com `<!-- fabrica:acao`. **Ignorados** (não são do agente nem do usuário): `<!-- fabrica:licao`, `<!-- fabrica:dispatcher`, `<!-- fabrica:backlog par-recusado`. **Do usuário:** qualquer outro.
- **Resposta nova** a um marcador: comentário do usuário com `createdAt` **estritamente** posterior ao do último comentário com aquele marcador. No mesmo segundo não conta.
- **Linhas 3 e 4:** o marcador é o do comentário do agente mais recente entre `triagem` e `spec`.
- **PR da branch:** entre os PRs do `gh pr list`, vale o aberto; sem aberto, o mais recente por `updatedAt`. Sem PR, a linha 8 vale para `spec-aprovada`.
- **CI falhando (linha 10):** algum item do `statusCheckRollup` com `conclusion` em `FAILURE`, `TIMED_OUT`, `CANCELLED`, `ACTION_REQUIRED` ou `STARTUP_FAILURE`, ou com `state` em `FAILURE` ou `ERROR`. Item pendente ou sem conclusão não é falha.
- **Pedido novo no PR (linha 11):** comentário do usuário na conversa do PR ou review do usuário com instante estritamente posterior à referência. A referência é o instante da linha `**Pedidos lidos até:** <instante>` do último comentário `<!-- fabrica:revisar -->` da conversa do PR, ou a data dele quando a linha falta; sem esse comentário, tudo conta. Review `APPROVED` de corpo vazio não conta; com corpo, conta; `COMMENTED` de corpo vazio conta. `reviewDecision` igual a `CHANGES_REQUESTED` também leva à linha 11.
- **Ação externa:** `estado=pendente` é 1a, `estado=concluida` é 1b; `sem-comentario`, `sem-itens` e `etapa-invalida` viram inconsistências (`acao-sem-comentario`, `acao-sem-itens`, `acao-etapa-invalida`). `escalonado` tem precedência sobre 1a e 1b.
- **Inconsistências** (códigos): `spec-aprovada-sem-spec`, `pronto-revisao-sem-pr`, `acao-sem-comentario`, `acao-sem-itens`, `acao-etapa-invalida`, `pr-fechado-sem-merge`. A `em-andamento` esquecida é do `dispatch.sh`, e as labels `modelo:*` duplicadas continuam no código 2 do `stage-model.sh`. "Marcador de spec sem a branch" fica de fora (ver Decisões).

### 6. Falha e comentários do dispatcher
- O comentário de falha (`dispatch.sh fail`) passa a dizer a **etapa que falhou** (lida de `stage`; `não decidida` quando a falha foi antes da primeira etapa) e a orientação "rode `/fabrica:<etapa> <nº>` ou `/fabrica:avancar <nº>` na sua máquina, ou repita o gesto". Vai para a issue resolvida; sem issue resolvida (falha do `gh` ao ler o PR), vai para o PR com `gh pr comment <nº> --body-file`.
- O passo de reserva da falha de instalação usa `**Etapa:** não decidida` e comenta no PR com `gh pr comment` quando o evento é de PR.
- Os comentários `freio` e `teto` usam o mesmo marcador `<!-- fabrica:dispatcher -->`, que o filtro barra e o leitor ignora.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `templates/workflows/agente.yml` dispara exatamente em `issues: [labeled]`, `issue_comment: [created, edited]`, `pull_request_review: [submitted]` e `pull_request_review_comment: [created]`. | unitário — `scripts/test-dispatch.sh`, lendo o YAML com PyYAML |
| CA2 | O `if` do job é a expressão de filtro da seção 1, com as cláusulas de nome do evento, tipo, estado aberto, labels `agente`/`spec-aprovada`, `!startsWith(<corpo>, '<!-- fabrica:')`, a exceção `<!-- fabrica:acao` com `acao-externa` e sem PR no `edited`, e, no `created` de issue (não de PR), a label `agente` com `contains(github.event.issue.labels.*.name, 'agente')`; o teste compara com a expressão esperada, ignorando espaços. | unitário — `scripts/test-dispatch.sh` |
| CA3 | O `concurrency.group` usa a mesma expressão do `if` para escolher entre `fabrica-<nº da issue ou do PR>` e `fabrica-ignorado-<run_id>`; `cancel-in-progress: false`; job com `timeout-minutes: 110` e passo do despacho com `100`. | unitário — `scripts/test-dispatch.sh` |
| CA4 | Continuam valendo os CAs de workflow da SPEC-106 (`permissions` só `contents: read`, `GH_TOKEN` só do `FABRICA_GH_TOKEN`, nenhum `${{` em `run:`); o checkout usa `ref` da branch padrão do repositório; os passos `run`, `unmark` e `fail` recebem o tipo (`issue` ou `pr`) e o número do evento só por `env`. | unitário — `scripts/test-dispatch.sh` |
| CA5 | O passo de reserva da falha de instalação escreve `**Etapa:** não decidida` e usa `gh pr comment` quando o tipo é `pr` e `gh issue comment` quando é `issue`. | unitário — `scripts/test-dispatch.sh`, lendo o `run:` do passo |
| CA6 | `issue-state.py state` devolve a linha certa para um pacote de cada estado 1, 1a, 1b, 2, 3, 4, 5, 6 (com spec e no atalho), 7, 8, 9, 10, 11 (por pedido novo e por `CHANGES_REQUESTED`), 12 e 13, com a etapa e o `quem` da seção 4; e a precedência de cima para baixo (por exemplo, `escalonado` com `acao-externa` concluída é 1). | unitário — `scripts/test-issue-state.sh`, com pacotes JSON fixos |
| CA7 | Classificação de comentários: os ignorados (`licao`, `dispatcher`, `backlog par-recusado`) e a linha de custo no fim não viram resposta nova; marcador com espaços antes não conta como do agente, porque o filtro do GitHub também não tira os espaços (o leitor não os tira mais); comentário do usuário no mesmo segundo do marcador não é resposta nova e um segundo depois é; na linha 4, a etapa é `spec` quando o último marcador entre triagem e spec é de spec e `triagem` no outro caso. | unitário — `scripts/test-issue-state.sh` |
| CA8 | Regras do PR: comentário no mesmo instante da referência `**Pedidos lidos até:**` não é pedido novo e um segundo depois é; sem a linha, a referência é a data do comentário `revisar`; sem comentário `revisar`, todo comentário do usuário conta; `APPROVED` vazia não conta e com corpo conta; `COMMENTED` vazia conta; CI com `FAILURE` ou `TIMED_OUT` é linha 10, e com item pendente não é; entre um PR fechado e um aberto vale o aberto. | unitário — `scripts/test-issue-state.sh` |
| CA9 | `issue-state.py` devolve cada código de inconsistência da seção 5, e `issue-state.py branch` devolve a branch do comentário de spec mais recente, a do atalho sem comentário de spec, e nada numa issue triada sem atalho e sem spec. | unitário — `scripts/test-issue-state.sh` |
| CA10 | `dispatch.sh run pr <nº>` resolve a issue só com exatamente uma issue em `closingIssuesReferences` e a branch dela igual ao `headRefName`; com zero, duas, branch diferente ou PR fechado, sai com 0 e `pulo:`, sem chamar o `claude`, sem aplicar label e sem comentar. A `em-andamento` e o comentário de falha vão para a issue resolvida, nunca para o PR. | unitário — `scripts/test-dispatch.sh`, com `gh` falso |
| CA11 | Laço: numa issue em 5, roda `spec` e para quando o estado relido é 7 (2 chamadas ao `issue-state.py state`, 1 ao `claude`); para em "sem avanço" quando o estado relido é igual; para na primeira falha, sai com 1 e grava a etapa que falhou; com estados de agente sem fim, roda exatamente 4 etapas, não roda a 5ª e publica o comentário `teto`; aplica a `em-andamento` uma vez só, antes da primeira etapa; num portão inicial ou numa inconsistência, não chama o `claude`, não mexe em label e não comenta. | unitário — `scripts/test-dispatch.sh`, com `gh`, `claude` e estados falsos em sequência |
| CA12 | A regra da `em-andamento` da SPEC-105 vale na issue resolvida: 1 h 59 min é pulo sem mexer na label; 2 h 00 min ou mais remove, aplica de novo e roda. | unitário — `scripts/test-dispatch.sh` |
| CA13 | Freio: 8 eventos `labeled em-andamento` com idade de até 3.600 s (um deles com exatamente 3.600 s) geram pulo e o comentário `freio`, sem chamar o `claude`; 7 eventos nessa janela, mais um com 3.601 s, rodam a etapa. | unitário — `scripts/test-dispatch.sh`, com `FABRICA_NOW` e timeline falsa |
| CA14 | `dispatch.sh fail` escreve a etapa gravada em `stage` (ou `não decidida` sem o arquivo) e a orientação da seção 6, na issue resolvida; sem issue resolvida num evento de PR, comenta no PR com `gh pr comment --body-file`. Os motivos e o sigilo da SPEC-105 continuam (sem `result`, sem valor de secret). | unitário — `scripts/test-dispatch.sh` |
| CA15 | **Ponta a ponta, resposta e laço:** no `ftenorio99/fabrica-teste`, aplicar `agente` numa issue nova, sem atalho, roda a triagem e a spec num run só e para em "Spec para aprovar"; um comentário do usuário pedindo um ajuste roda a `spec` de novo e volta a "Spec para aprovar". | e2e — repositório de teste, com os links dos runs no PR |
| CA16 | **`spec-aprovada`:** aplicar `spec-aprovada` numa issue com spec (pode ser de atalho) roda o `implementar` com o `revisar` encadeado, abre o PR e deixa a issue em 9 ou 13, sem `em-andamento`. | e2e — repositório de teste |
| CA17 | **Comentário no PR:** um comentário na conversa do PR roda o `revisar`; um comentário em linha, que gera um evento `pull_request_review` e um `pull_request_review_comment`, resulta em uma única execução do `revisar` (o outro run termina em pulo ou é substituído na fila). | e2e — repositório de teste, com a saída do `gh run list --workflow agente.yml` |
| CA18 | **Checklist:** com um comentário `<!-- fabrica:acao etapa=revisar -->` de 2 itens e a label `acao-externa` postados à mão na issue do CA16, marcar 1 item gera run com pulo; marcar o 2º roda o `revisar`, que remove a `acao-externa`. | e2e — repositório de teste |
| CA19 | **Sem cascata:** nos testes do CA15 ao CA18, todo run gerado por comentário ou label do agente (inclusive `fabrica:dispatcher`) termina `skipped`, nenhum run `skipped` aparece como `cancelled`, e o número de runs que chamaram o `claude` é igual ao número de gestos feitos. | e2e — repositório de teste, com a saída do `gh run list --workflow agente.yml --json event,conclusion,createdAt` |
| CA20 | **Modo `auto` no runner:** os testes do CA15 ao CA18 dizem se o `auto` deixou `spec`, `implementar` e `revisar` terminarem. Se alguma falhar por `permissao`, o CA correspondente fica reprovado, e a implementação para com `escalonado` e registra o resultado na issue, sem contornar o modo de permissão. | e2e — repositório de teste |
| CA22 | `job-isolation.sh prepare` copia `githooks/` do plugin para `/opt/fabrica-githooks`, com dono `runner` e sem escrita para `fabrica-agent`, e grava ali um arquivo de configuração do git, também sem escrita para o agente, com a pasta de hooks como `core.hooksPath`. O `job-isolation.sh lock` grava no `agent.env` a variável que faz o git do agente ler só esse arquivo, e não o `~/.gitconfig` dele. Os caminhos de destino são configuráveis por variável, para o teste. | unitário — `scripts/test-job-isolation.sh`, com os destinos numa pasta temporária |
| CA23 | Com a configuração do CA22 ativa, um commit feito pelo usuário `fabrica-agent` numa branch `main` é recusado pelo hook, e um commit numa branch de feature passa. Um `git config --global` do agente não muda a pasta de hooks em uso. | unitário — `scripts/test-job-isolation.sh`, com git real num repositório temporário |
| CA24 | `agente.yml` envia o `stage.json` de `$RUNNER_TEMP/fabrica-dispatch/` como artifact do run, em todo run que chega ao passo do despacho, com `if: always()` e `retention-days: 3`. O passo não pode ler nem imprimir o valor de nenhum secret. | unitário — `scripts/test-dispatch.sh`, lendo o YAML com PyYAML; e2e — repositório de teste, com o artifact no run do CA15 |
| CA25 | `hooks/protect-main.sh` usa a variável `FABRICA_GITHOOKS_DEST` como destino dos hooks quando ela existe e não é vazia; sem ela, o destino é `$HOME/.config/fabrica/githooks`, como hoje. Um commit ou push cujo `core.hooksPath` global é igual ao destino passa; diferente, sai com `deny`. Um comando do Bash que cita `FABRICA_GITHOOKS_DEST` é negado, como os que citam `GIT_CONFIG`. | unitário — `scripts/test-protect-main.sh`, com a variável definida e sem ela |
| CA26 | `job-isolation.sh lock` grava `FABRICA_GITHOOKS_DEST=<pasta dos hooks>` no `agent.env`, com o mesmo caminho que o `prepare` usa para a pasta dos hooks. | unitário — `scripts/test-job-isolation.sh` |
| CA27 | No ponta a ponta com esta versão do plugin, uma etapa de ajuste de spec faz commit e push na branch da issue e publica o comentário `<!-- fabrica:spec -->`. O bloqueio do `protect-main` não aparece no `stage.json` do run. O aviso do `session-start.sh` sobre os hooks, que confere `$HOME/.config/fabrica/githooks`, pode aparecer; esta spec não o altera. | e2e — `ftenorio99/fabrica-teste`, com o `git log` da branch de teste e o artifact do run |
| CA28 | O `dispatch.sh` não pede `statusCheckRollup` (nem outro campo de checks) ao `gh pr list` nem ao `gh pr view`; a coleta do PR da issue roda com o `FABRICA_GH_TOKEN` do job sem o erro de permissão de checks. | unitário — `scripts/test-dispatch.sh`, com um `gh` falso que falha se o `--json` pedir o campo |
| CA29 | `issue-state.py state` não aplica a linha 10 (CI vermelho) quando o pacote não traz o campo `statusCheckRollup`: um PR aberto sem `pronto-revisao` vai à linha 12, e um PR com `pronto-revisao` vai à 13. Quando o campo vem, a regra da linha 10 continua a mesma do CA8. | unitário — `scripts/test-issue-state.sh` |
| CA30 | `skills/status/estados.md` diz que, no dispatcher, a linha 10 não vale (o CI é lido só pelo `/fabrica:status`), e o `docs/guias/dispatcher.md` diz o mesmo para o gesto no PR. `estados.md` também diz que uma issue com `agente` fora de todas as linhas (PR da branch mergeado com a issue aberta, ou PR fechado sem merge) é estado do usuário (linha `-`), como o `issue-state.py` já faz. | manual — leitura do diff na revisão |
| CA31 | As actions do workflow estão nas últimas versões confirmadas pela API de releases em 2026-11-22: `actions/upload-artifact` na v7 (última `v7.0.2`) e `actions/checkout` na v7 (última `v7.0.1`). | unitário — `scripts/test-dispatch.sh` (YAML com `@v7`) e a consulta à API registrada na revisão |
| CA21 | `docs/guias/dispatcher.md` explica os gestos que acordam o workflow, o laço até o portão e o teto, o freio, a resolução do PR, o tempo de 110 min e os limites (gesto feito com outra execução em curso, hosts de dependências do `implementar`); `skills/status/estados.md` diz que o `issue-state.py` implementa a tabela de estados e precisa mudar no mesmo PR; `AGENTS.md` cita o `issue-state.py` e o `bash scripts/test-issue-state.sh`; `docs/README.md` atualiza a linha do guia; a [ADR 0017](../docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md) passa a `aceito`; a `version` do `plugin.json` vai de 0.45.0 para 0.46.3, porque os CA2, CA7, CA25 e CA28 mudam o comportamento do `protect-main` e do dispatcher. | manual — leitura do diff na revisão |

## Fora de escopo
- Escalonamento de modelo do `/fabrica:avancar` no dispatcher (lição `modelo` e troca da `modelo:*`).
- Hosts de dependências do projeto para o `implementar` (npm, Docker Hub etc.) na lista de domínios: #108. O teste usa uma issue que não baixa dependências.
- Instalação do workflow pelo `/fabrica:setup` e ligar no kairo: #108.
- Rodar o gesto que chegou com outra execução em curso depois que ela termina (fila por issue). Hoje ele vira pulo; o laço da execução em curso relê o estado e costuma pegá-lo (ver Riscos).
- Mudar o texto do comentário de ação ("rode `/fabrica:avancar`"), que vale também para projetos sem o dispatcher.

## Desenho técnico
**Arquivos e módulos:**
- `templates/workflows/agente.yml`: `on` com os cinco eventos; `if` do job com a expressão de filtro; `concurrency.group` com a mesma expressão; checkout com `ref: ${{ github.event.repository.default_branch }}`; `env` dos passos com `EVENT_KIND` (`${{ (github.event.pull_request || github.event.issue.pull_request) && 'pr' || 'issue' }}`) e `EVENT_NUMBER` (`${{ github.event.issue.number || github.event.pull_request.number }}`); passos chamando `dispatch.sh run|unmark|fail "$EVENT_KIND" "$EVENT_NUMBER"`; timeouts 110 e 100; passo de reserva com `gh pr comment` ou `gh issue comment` pelo `EVENT_KIND`.
- `scripts/dispatch.sh`: subcomandos `run|unmark|fail <issue|pr> <nº>`; resolução do PR; freio; laço; estado do job em `$RUNNER_TEMP/fabrica-dispatch/` (`issue`, `stage`, `marked`, `stage.json`, `stage.exit`); `unmark` e `fail` usam o `issue` gravado. Remove a regra "já triada = pulo" da SPEC-105, que passa a ser decidida pelo leitor.
- `scripts/issue-state.py` (novo): subcomandos `branch` e `state` da seção 5. Ajuste de 2026-11-22: deixa de tirar espaços do começo da primeira linha (CA7).
- `scripts/test-issue-state.sh` (novo): CA6 a CA9, no estilo do `scripts/test-acao-status.sh`.
- `scripts/test-dispatch.sh`: CA1 a CA5 e CA10 a CA14; os casos da SPEC-105 e da SPEC-106 que mudam (pulo de issue triada, timeouts, grupo de concorrência, assinatura `run <nº>`) são ajustados, com a mudança registrada no PR.
- `hooks/protect-main.sh`: lê `FABRICA_GITHOOKS_DEST` como destino dos hooks quando a variável existe (CA25).
- `scripts/job-isolation.sh`: `lock` também grava `FABRICA_GITHOOKS_DEST` no `agent.env` (CA26).
- `scripts/test-protect-main.sh`: CA25. `scripts/test-job-isolation.sh`: CA26.
- `scripts/job-isolation.sh`: `prepare` copia `githooks/` para `/opt/fabrica-githooks` e grava o arquivo de configuração do git do agente (CA22); `lock` grava `GIT_CONFIG_GLOBAL` no `agent.env`, que o `run-as-agent.sh` passa ao agente, porque ele roda com ambiente fechado (`env -i`).
- `templates/workflows/agente.yml`: passo de upload do `stage.json` como artifact (CA24).
- `scripts/test-job-isolation.sh`: CA22 e CA23. `scripts/test-dispatch.sh`: CA24.
- `docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md` (novo, `proposto`).
- `skills/status/estados.md` (ajuste de 2026-11-22: parágrafo sobre a linha `-`, CA30), `docs/guias/dispatcher.md`, `docs/README.md`, `AGENTS.md`, `.claude-plugin/plugin.json` (0.45.0 → 0.46.3).
- `templates/workflows/agente.yml` (ajuste de 2026-11-22): label `agente` no `created` de issue (CA2) e versões das actions (CA31).

**Dados:** nenhum.

**Interfaces:**
- `dispatch.sh run <issue|pr> <nº>` → 0 (etapas ok, pulo, freio ou teto), 1 (falha ou uso inválido), 2 (labels `modelo:*`).
- `unmark` e `fail` com os mesmos argumentos e as mesmas saídas da SPEC-105.
- `issue-state.py branch <issue.json>` → a branch ou nada; `issue-state.py state <pacote.json>` → a linha da seção 5. JSON inválido sai com 2, como o `acao-status.py`.

**Decisões:**
- Eventos: `issues: labeled` (só `agente` e `spec-aprovada`), `issue_comment: created` (issue e PR), `issue_comment: edited` (checklist de ação), `pull_request_review: submitted` e `pull_request_review_comment: created`, porque são os quatro gestos da F5 e estados.md conta review e comentário em linha como pedido do usuário no PR. Alternativa descartada: só `issue_comment`, que perde a review e o comentário em linha. (recomendação da triagem)
- O evento só acorda; quem decide a etapa é o `dispatch.sh`, relendo o estado pela tabela de estados.md, porque é o que a #105 já faz na triagem e o que o `/fabrica:avancar` faz (um fluxo só, PRD). Alternativa descartada: mapear evento para etapa no workflow, que duplicaria a tabela de estados. (recomendação da triagem)
- Filtro anticascata no `if` do job: ignora comentário que começa com `<!-- fabrica:` e labels que não sejam `agente` ou `spec-aprovada`, com a exceção da edição de um comentário `<!-- fabrica:acao`, confirmada depois pelo `acao-status.py`, porque a ADR 0015 e a tabela de riscos do PRD mandam o filtro por marcador e por nome de label. Alternativa descartada: filtrar pelo autor, porque agente e usuário são a mesma conta. (recomendação da triagem)
- Teto de 4 etapas por disparo, parando nos portões do usuário e no `escalonado`, porque é o teto do `/fabrica:avancar` e o que a tabela de riscos do PRD pede. Alternativa descartada: uma etapa por disparo, que obrigaria o usuário a gesticular de novo no meio do fluxo. (recomendação da triagem)
- Concorrência: grupo por número do evento (issue ou PR) e a `em-andamento` como trava real, resolvida no `dispatch.sh` pela issue, porque a expressão do workflow não resolve PR para issue. Alternativa descartada: grupo só por issue, que não funciona para eventos de PR. (recomendação da triagem)
- Leitor de estado em código (`scripts/issue-state.py`), puro e testado com JSON fixo, com a coleta no `dispatch.sh`, porque o dispatcher precisa da tabela inteira (o `spec-aprovada` leva ao PR, e o PR aos estados 9 a 13) de forma determinística e barata, sem um `claude -p` só para decidir. Alternativa descartada: um `claude -p` com o `/fabrica:status` para escolher a etapa, que gasta assinatura a cada evento e não se testa. Detalhes e a obrigação de manter a tabela e o código juntos na [ADR 0017](../docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md).
- Grupo de concorrência condicional (`fabrica-ignorado-<run_id>` para o evento barrado), porque, com um grupo só por número, os runs pulados dos comentários do agente substituiriam na fila o run pendente de um gesto. Alternativa descartada: concorrência no nível do job, cujo comportamento com o job `skipped` a documentação não descreve.
- Resolução do PR por `closingIssuesReferences`, conferida pela branch da issue, porque o campo existe no `gh pr view` e reflete o `Fixes #<nº>` que a regra global exige, e a conferência da branch impede que um PR qualquer que cite a issue acorde etapas nela. Alternativa descartada: só o número no nome da branch, que aceitaria uma branch criada à mão fora da fábrica.
- Freio de cascata de 8 execuções por hora na issue, porque o filtro por marcador vira a única trava com o token novo e um comentário do agente sem marcador (erro de uma etapa) faria cada run disparar o seguinte; 8 em 60 min está muito acima do ritmo de gestos humanos com etapas de vários minutos. Alternativa descartada: confiar só no filtro e no teto, que limitam cada run, mas não a corrente de runs.
- Tempo de 100 min no passo e 110 no job, porque o laço pode ter `implementar` e `revisar` e precisa terminar antes das 2 h da `em-andamento`. Alternativa descartada: manter 30 e 40 min, que derrubariam o `implementar` no meio.
- Checkout da branch padrão, porque o `pull_request_review` traz como `GITHUB_REF` o merge do PR, e as etapas criam a própria worktree a partir da `origin`. Alternativa descartada: o checkout padrão do evento, que deixaria a cópia de trabalho num commit de merge temporário.
- O dispatcher não confere "marcador de spec sem a branch", porque distinguir 404 de erro de rede no `gh api` complica o script, e a etapa que precisa da branch já para nesse caso ("sem avanço"). Alternativa descartada: conferir com `gh api repos/<repo>/branches/<branch>`.
- Destino dos hooks no `protect-main` (ajuste de 2026-11-22, escolha do usuário na issue, opção 1): o `lock` grava `FABRICA_GITHOOKS_DEST=/opt/fabrica-githooks` no `agent.env`, e o `protect-main` compara o `core.hooksPath` global com essa variável quando ela existe, em vez de `$HOME/.config/fabrica/githooks`. Alternativa descartada: gravar a configuração na pasta do usuário do agente, que ele pode alterar. A variável vem do ambiente do processo do agente, montado pelo `run-as-agent.sh` com `env -i`, então um comando do agente não a altera. Sem a variável, vale o caminho de hoje.
- Leitura do CI no dispatcher (ajuste de 2026-11-22, escolha do usuário na issue, opção 2): o `dispatch.sh` e o `issue-state.py` deixam de pedir e de aplicar `statusCheckRollup` no job. Alternativa descartada: dar ao `FABRICA_GH_TOKEN` a permissão de checks, que o token fine-grained não oferece. Outra alternativa, um GitHub App para o job, foi descartada na ADR 0016 por custo de manutenção.
- Hooks do git no job (ajuste de 2026-11-22): o `fabrica-agent` precisa de commit e push nas etapas de ajuste, então os hooks da `main` ficam ativos para ele, e não se declara que o agente não usa git. Os hooks ficam em `/opt/fabrica-githooks`, dono `runner`, sem escrita para o agente, porque uma pasta que ele escreve pode ser editada por ele mesmo. A configuração que aponta para essa pasta é um arquivo root-owned, passado ao agente por `GIT_CONFIG_GLOBAL` no `agent.env`: ele é o único arquivo de configuração global que o git do agente lê, então o `~/.gitconfig` dele não sobrescreve a pasta. Alternativa descartada: `git config --system` em `/etc/gitconfig`, que a configuração global do agente (`~/.gitconfig`) sobrescreve. Alternativa descartada: instalar com `setup-githooks.sh` no home do agente, que ele pode alterar. Não se cria ADR nova: é aplicação do isolamento da ADR 0016. (decisão do usuário no comentário de 2026-11-22, com a forma refinada aqui)
- Artifact do `stage.json` (ajuste de 2026-11-22): o arquivo fica como artifact do run por 3 dias, para a causa de uma etapa que sai sem publicar ficar visível. Alternativa descartada: colar o conteúdo no comentário de falha, que é público no repositório e pode ser longo.
- Limite dos hooks no job, aceito pelo usuário em 2026-11-22: o `protect-main` só inspeciona comandos Bash. O agente pode gravar o `.git/config` da própria worktree com Edit ou Write e definir o `core.hooksPath` ali, e a opção `-c` do git também escapa. Não há mitigação no código para Edit e Write; o CA23 testa só a configuração do job. Registrado como risco.
- Alinhamento do filtro e do leitor (ajuste de 2026-11-22, sugestões do revisor): o leitor deixa de tirar espaços do começo do corpo, como o filtro do GitHub, e o filtro de `issue_comment: created` exige a label `agente` nas issues, para o job não rodar o `lock` com segredos em comentário de issue sem a label. Os comentários do agente começam pelo marcador na primeira posição, como já dizem as skills. Alternativa descartada: o filtro ignorar espaços, que a expressão do GitHub não faz sem `trim`. A expressão `labels.*.name` não foi confirmada na documentação; o CA19 do ponta a ponta confirma.
- Destino dos hooks no `protect-main` (ajuste de 2026-11-22, escolha do usuário na issue, opção 1): o `lock` grava `FABRICA_GITHOOKS_DEST=/opt/fabrica-githooks` no `agent.env`, e o `protect-main` compara o `core.hooksPath` global com essa variável quando ela existe, em vez de `$HOME/.config/fabrica/githooks`. Alternativa descartada: gravar a configuração na pasta do usuário do agente, que ele pode alterar. A variável vem do ambiente do processo do agente, montado pelo `run-as-agent.sh` com `env -i`, então um comando do agente não a altera. Sem a variável, vale o caminho de hoje.

**Fontes da documentação:**
- GitHub Actions — documentação consultada em 2026-11-19: [eventos que disparam workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) (`issues`, `issue_comment` em issue ou PR, `pull_request_review` e `pull_request_review_comment`; o workflow tem de existir na branch padrão), [concorrência](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency) (um pendente por grupo, `cancel-in-progress: false`, grupo com contexto `github`) e [expressões](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions) (`startsWith` não diferencia maiúsculas, `!`, `||`, `&&`). Versão não confirmada: a documentação do site não é versionada.
- gh 2.104.0 — `gh pr view --help` (campos `state`, `headRefName`, `closingIssuesReferences`, `statusCheckRollup`, `reviewDecision`, `reviews`, `comments`, `updatedAt`), `gh pr list --help` (`--head`, `--state`, os mesmos campos), `gh issue view --help` (`state`, `labels`, `comments`), `gh api --help` (`--paginate`, `--slurp`), `gh pr comment --help` (`--body-file`).
- git — variável `GIT_CONFIG_GLOBAL` e `core.hooksPath`: **não verificada**. A consulta a `git help config` foi barrada pelo hook `protect-main` nesta etapa; confirmar com `git help config` no CA22 antes de implementar.
- actions/upload-artifact e `retention-days`: **não verificada**; confirmar no CA24.

**ADR:** [docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md](../docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md) (proposto).

## Testes
- `bash scripts/test-issue-state.sh`: CA6 a CA9, com um pacote JSON por caso numa pasta temporária.
- `bash scripts/test-dispatch.sh`: CA1 a CA5 leem o YAML com PyYAML; CA10 a CA14 rodam o `dispatch.sh` com um `gh` falso que responde a `issue view`, `pr view`, `pr list`, `api .../timeline`, `api .../comments`, `issue edit`, `issue comment` e `pr comment` a partir de arquivos, uma resposta por chamada quando o caso precisa de estados em sequência, e com `FABRICA_CLAUDE_BIN` falso.
- `bash scripts/test-stage-model.sh`, `bash scripts/test-acao-status.sh` e `bash scripts/test-job-isolation.sh` continuam passando.
- CA15 a CA20: no `ftenorio99/fabrica-teste`, com o workflow copiado da branch e os secrets já cadastrados; issues e PRs de teste fechados no fim com um comentário dizendo que eram teste.
- CA22 a CA24: `bash scripts/test-job-isolation.sh` e `bash scripts/test-dispatch.sh`, como acima.
- CA25: `bash scripts/test-protect-main.sh`. CA26: `bash scripts/test-job-isolation.sh`. CA27: o CA15 de novo no `ftenorio99/fabrica-teste`, com o plugin desta branch.
- CA28: `bash scripts/test-dispatch.sh`. CA29: `bash scripts/test-issue-state.sh`. CA30: leitura do diff. Depois, o CA17 de novo no `ftenorio99/fabrica-teste`.
- Ajuste de 2026-11-22: CA2 e CA31 em `bash scripts/test-dispatch.sh`; CA7 em `bash scripts/test-issue-state.sh`. Ponta a ponta: CA2 e CA19 de novo no `ftenorio99/fabrica-teste`, com a cópia do workflow desta branch (a cópia precisa de um PR e de um merge no repositório de teste, com confirmação do usuário).

## Passos de produção
nenhum

## Riscos e dúvidas
- **Filtro errado vira laço de jobs.** O freio, o teto e a releitura do estado limitam o estrago; o CA19 prova a ausência de cascata no repositório de teste.
- **`auto` no runner:** bloqueou a `spec` no `-p` do host em 3 de 3 execuções (ADR 0013). O CA20 registra o resultado de cada etapa; se bloquear, a issue para com `escalonado` e o caminho é decidido com o usuário.
- **Gesto com outra execução em curso:** um comentário no PR enquanto o run da issue roda vira pulo por `em-andamento` recente. Se o laço em curso já passou do ponto de reler, o gesto fica sem execução até o próximo gesto ou o `/fabrica:avancar`. O guia registra isso.
- **Eventos duplicados do comentário em linha** (review e comentário de review) gastam um run a mais, que termina em pulo depois da instalação (cerca de 2 a 3 min de runner).
- **Workflow do PR:** no `pull_request_review`, o GitHub usa o workflow da ref de merge do PR. O PR do agente não altera workflows, porque o `FABRICA_GH_TOKEN` não tem a permissão Workflows (SPEC-106).
- **Tabela duplicada:** o `issue-state.py` repete a lógica de estados.md; a ADR 0017 obriga mudar os dois no mesmo PR.
- **Tamanho:** se a implementação passar de 2 dias, o corte é eventos de issue (resposta, `spec-aprovada`, checklist) numa issue e eventos de PR (resolução do PR, comentário e review) noutra.
- **Variável no ambiente do agente:** `FABRICA_GITHOOKS_DEST` só enfraquece a conferência se o agente conseguir alterá-la. O `run-as-agent.sh` monta o ambiente com `env -i` e a lista fechada do `agent.env`, então não consegue; o CA25 nega o comando que cita a variável.
- **Hooks no job, limite aceito:** o `protect-main` não cobre Edit nem Write, e o agente pode gravar o `.git/config` da worktree para definir o `core.hooksPath` ali (ver Decisões). Aceito pelo usuário em 2026-11-22; o CA23 prova só a configuração do job.
- **Artifact com a saída do Claude:** o `stage.json` pode trazer trechos da saída da etapa, visíveis a quem lê o repositório por 3 dias. Por isso a retenção é curta e o CA24 exige que o passo não imprima secret.
- **Versão do upload de artifact:** a versão foi confirmada pela API de releases (CA31), não pela documentação do site; o CA24 (e2e) confirma o comportamento.
- **CI no job:** com a opção 2 escolhida pelo usuário, o dispatcher não vê PR com CI vermelho. Um PR assim aparece como `pronto-revisao` (13) no job, e o usuário confere o CI na revisão. O `/fabrica:status` local continua lendo o CI.

## Histórico
- 2026-11-19: criação.
- 2026-11-19: aprovada.
- 2026-11-22: mudança (incluir) — ajuste dos hooks do git no job, que o `fabrica-agent` precisa para commit e push nas etapas de ajuste (ver Decisões). CAs: incluídos CA22 a CA24; removidos nenhum; alterados nenhum.
- 2026-11-22: aprovada.
- 2026-11-22: mudança (incluir) — destino dos hooks no `protect-main` do job, escolha do usuário na issue (opção 1). CAs: incluídos CA25 a CA27; removidos nenhum; alterados CA21 (a versão final vai a 0.46.1).
- 2026-11-22: mudança (alterar) — o CA27 deixa de exigir a ausência do aviso do `session-start.sh`, escolha do usuário na issue (opção b). CAs: incluídos nenhum; removidos nenhum; alterados CA27.
- 2026-11-22: aprovada.
- 2026-11-22: mudança (incluir) — o dispatcher deixa de ler o CI do PR, porque o token do job não tem a permissão de checks, escolha do usuário na issue (opção 2). CAs: incluídos CA28 a CA30; removidos nenhum; alterados CA21 (a versão final vai a 0.46.2).
- 2026-11-22: aprovada.
- 2026-11-22: mudança (alterar) — aceite do risco do `protect-main` com o texto corrigido, e as sugestões do revisor: alinhamento do leitor ao filtro (CA7), label `agente` no `issue_comment` de issue (CA2), `estados.md` para a linha `-` (CA30) e versões das actions (CA31). CAs: incluídos CA31; removidos nenhum; alterados CA2, CA7, CA21 (versão final 0.46.3) e CA30.
