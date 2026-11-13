# SPEC-141: Adotar o sbx como sandbox padrão, com opção sem sandbox, e retirar o sandbox nativo

**Issue:** #141 · **PRD:** F1 · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-12

## Contexto
A F1 do PRD pede que o agente rode em sandbox. A [ADR 0005](../docs/adr/0005-isolamento-do-agente-em-sandbox.md) fez isso com o sandbox nativo do Claude Code, que ficou frágil no uso (token no chaveiro, expressão do `mask`, Docker bloqueado). Em 2026-11-12, o Docker Sandboxes (`sbx` 0.51.0) passou no teste feito no `ancora` e no `kairo`, e a issue decidiu trocar: o `sbx` vira o modo padrão, com a opção de rodar sem sandbox.

Na triagem, a issue foi dividida em três partes. **Esta spec cobre só a parte A:** o `/fabrica:setup` com os dois modos, o ADR novo e o guia. A remoção dos scripts e templates do sandbox nativo, com a migração dos projetos já instalados (parte B), e a verificação de integração dentro da VM (parte C) ficam para issues próprias.

## Objetivo
O `/fabrica:setup` pergunta o modo de isolamento do projeto (`sbx` ou sem sandbox), grava a escolha em `.fabrica/isolamento.txt`, deixa de ligar o sandbox nativo e orienta o usuário em cada modo; o ADR 0010 e o guia de isolamento registram a decisão.

## Comportamento esperado

### O arquivo do modo
`.fabrica/isolamento.txt`, versionado na raiz do repositório, com o modo numa linha: `sbx` ou `sem-sandbox`.
- Linhas vazias e linhas começadas com `#` (depois dos espaços) são ignoradas. Vale a primeira linha restante, sem os espaços das pontas.
- A comparação é exata, com diferença entre maiúsculas e minúsculas: `SBX` é inválido.
- O setup grava o arquivo na cópia de trabalho. O commit entra por uma branch e um PR, feitos pelo usuário, como o `.fabrica/producao.txt`.

### O script `scripts/setup-isolation.sh`
Uso: `setup-isolation.sh [--check] [--set sbx|sem-sandbox] [--project <dir>]`. Sem `--project`, usa a raiz do repositório git do diretório atual. Sem `--check` nem `--set`, vale `--check`.

| Situação | Saída (stdout) | Código |
|---|---|---|
| `--check`, sem o arquivo | `ausente` | 0 |
| `--check`, arquivo válido | `sbx` ou `sem-sandbox` | 0 |
| `--check`, arquivo sem linha de modo ou com outro valor | `inválido` | 0 |
| `--set <modo>`, sem o arquivo, ou com o arquivo em outro modo ou inválido | grava o arquivo com `<modo>` e uma quebra de linha, criando `.fabrica/` se faltar; imprime `gravado <modo>` | 0 |
| `--set <modo>`, arquivo já nesse modo | não regrava; imprime `ok <modo>` | 0 |
| `--set` com outro valor, ou sem valor | nada gravado; erro em stderr com os valores aceitos | 1 |
| `--check` e `--set` juntos, ou opção desconhecida | erro em stderr com o uso | 1 |
| Fora de um repositório git e sem `--project`, ou `--project` num diretório que não existe | erro em stderr | 1 |

**Aviso do sandbox nativo:** em `--check` e em `--set`, se o `.claude/settings.json` do projeto tiver `sandbox.enabled` igual a `true`, o script imprime em stderr `setup-isolation: sandbox nativo ligado em .claude/settings.json`. O aviso não muda a saída nem o código. Sem o arquivo, com JSON inválido ou com `enabled` diferente de `true`, não há aviso nem erro. O script nunca altera o `.claude/settings.json`.

### O `/fabrica:setup`
A ordem dos passos passa a ser: **1. Modo de isolamento**, 2. `gh`, 3. Labels, 4. Hooks do git, 5. Statusline. O passo "Sandbox" de hoje sai inteiro.

**Passo 1, Modo de isolamento:**

| Situação | O que o setup faz |
|---|---|
| Fora de um repositório git | Pula o passo, diz no resumo que o modo é por projeto e segue. |
| `--check` devolve `sbx` ou `sem-sandbox` | Não pergunta. Mostra o modo e diz que, para trocar, o usuário edita `.fabrica/isolamento.txt` por um PR. |
| `--check` devolve `ausente` ou `inválido` | Explica os dois modos e pergunta com o AskUserQuestion, com `sbx (Recomendado)` como primeira opção e "sem sandbox" como segunda. Grava a resposta com `--set`. Em `inválido`, mostra antes o conteúdo do arquivo. |
| O script imprime o aviso do sandbox nativo | Leva o aviso para o resumo: o bloco `sandbox` do `.claude/settings.json` é do sandbox nativo, que saiu da fábrica; dentro da VM do `sbx`, ele esconde o `GH_TOKEN`. Remete à seção "Projetos com o sandbox nativo" do guia. Não remove o bloco. |

Os passos `gh`, Labels, Hooks do git e Statusline rodam como hoje, nos dois modos. O argumento `<dono>/<repo>` continua valendo só para as labels; o modo é sempre o do projeto do diretório atual.

**Modo `sbx`:** depois dos passos, o setup imprime o checklist abaixo, com `<projeto>` trocado pelo nome da pasta do repositório. Ele não roda nenhum comando `sbx`, não confere se o `sbx` está instalado e não pede o `setup-git-auth.sh`.

1. **No host, uma vez por máquina:** fechar a rede padrão do `sbx`, que nasce aberta. Conferir com `sbx policy ls`; se a política global liberar tudo, `sbx policy reset` e `sbx policy init deny-all`.
2. **No host:** criar a VM do projeto, na pasta dele: `sbx create --name <projeto> claude .`
3. **No host:** liberar a rede só para a VM: `sbx policy allow network --sandbox <projeto> github.com,api.github.com,codeload.github.com,uploads.github.com,*.githubusercontent.com,registry.npmjs.org,registry-1.docker.io,auth.docker.io,production.cloudflare.docker.com`
4. **No host:** entregar o token do GitHub ao proxy, sem ele entrar na VM: `sbx secret set github --command 'gh auth token'`
5. **Dentro da VM** (`sbx run --name <projeto>`): instalar o plugin com `/plugin marketplace add ftenorio99/fabrica` e `/plugin install fabrica@fabrica`, e rodar `/fabrica:setup` para instalar os hooks do git. Repetir este item depois de um `sbx rm`: sem os hooks, o push na `main` passa.
6. **No host:** conferir a rede com `sbx policy log <projeto>`, e não com `curl` de dentro da VM, porque o proxy responde 200 ao CONNECT mesmo para um host bloqueado.

Quando o `--check` do passo "Hooks do git" já devolve `ok`, o item 5 sai marcado como feito nesta máquina ou VM.

**Modo `sem-sandbox`:** depois dos passos, o setup avisa, no resumo, que não há isolamento: os comandos do agente leem o token do `gh`, as chaves SSH e os `.env` da máquina e alcançam qualquer host; ficam só os hooks do git, que protegem a `main`, e o hook de produção, que barra o comando que cita um padrão de `.fabrica/producao.txt`. Sem checklist.

**Resumo final (seção "Responder" da skill):** a linha "Sandbox" de hoje vira "Isolamento": o modo (`sbx`, `sem sandbox`, ou `não definido: fora de um repositório git`), se foi gravado agora ou já estava, o lembrete de fazer commit do arquivo por PR quando ele foi gravado agora, o aviso do sandbox nativo, se houver, e o checklist ou o aviso do modo.

### Documentação
- **ADR 0010** (`docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md`, já na branch como `proposto`): passa a `aceito`.
- **ADR 0005:** o status passa a `substituído por ADR 0010`. O texto fica como está.
- **ADR 0006 e ADR 0007:** ganham uma nota de uma linha, logo abaixo do status, remetendo à ADR 0010 (na 0006, o bloqueio de rede por `deniedDomains` deixou de existir; na 0007, o limite descrito é o do sandbox nativo, e a revisão fica para uma issue própria).
- **Guia `docs/guias/isolamento-do-agente.md`**, reescrito com estas seções:
  1. Os dois modos, o que cada um protege e o que não protege, e como escolher e trocar (`.fabrica/isolamento.txt`).
  2. Modo `sbx`: o checklist do setup, explicado, e como ampliar os domínios (`sbx policy allow network --sandbox <projeto> <host>`), liberando só o host exato.
  3. Modo sem sandbox: o que fica exposto e o que continua valendo.
  4. Token fine-grained: continua recomendado nos dois modos, com os passos de criação e a troca do login do `gh`, sem as partes do `mask`, do `hosts.yml` e do `git-auth.gitconfig`.
  5. Projetos com o sandbox nativo: o bloco `sandbox` do `.claude/settings.json` esconde o `GH_TOKEN` dentro da VM. Até a issue da migração, o usuário remove o bloco por um PR ou abre a sessão com `sbx run claude <projeto> -- --settings '{"sandbox":{"enabled":false}}'`.
  6. Verificação de integração: as etapas continuam mandando para o CI o comando que falhar com as assinaturas de limite do sandbox ([ADR 0007](../docs/adr/0007-verificacao-de-integracao-pelo-ci.md)); dentro da VM do `sbx`, Docker e Compose funcionam, e essas falhas não devem aparecer.
  7. Texto de issue e PR fora do prompt: como está hoje.
  8. Produção fora do alcance: como está hoje, trocando o `deniedDomains` pelo que vale em cada modo (política escopada no `sbx`; só o hook sem sandbox).

  Saem do guia: "Dependências" (`bwrap`, `socat`, AppArmor), "Git push", "Token no chaveiro", "Rodar o teste de aceite", "Desligar" e o trecho do Prettier.
- **Manual e textos que citam o sandbox nativo:** `docs/comandos.md` (seção do `/fabrica:setup`), `docs/principios.md` ("Produção fora do alcance do agente"), `docs/README.md` (linha do guia), `templates/CLAUDE.md` (linha do `.fabrica/producao.txt`), `CLAUDE.md` (lista de scripts e testes) e o comentário da linha 11 de `hooks/protect-production.sh`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Num projeto sem `.fabrica/isolamento.txt`, `setup-isolation.sh --check` imprime `ausente` e sai com 0. Sem opção nenhuma, o script se comporta como `--check`. | unitário (`scripts/test-setup-isolation.sh`) |
| CA2 | `--set sbx` num projeto sem `.fabrica/` cria a pasta, grava o arquivo com o conteúdo exato `sbx` mais uma quebra de linha, imprime `gravado sbx` e sai com 0; em seguida, `--check` imprime `sbx`. O mesmo vale para `sem-sandbox`. | unitário |
| CA3 | `--set` com o arquivo já no mesmo modo imprime `ok <modo>` e não altera o arquivo (mesmo conteúdo e mesma data de modificação). | unitário |
| CA4 | `--set sem-sandbox` com o arquivo em `sbx`, e `--set sbx` com o arquivo inválido, sobrescrevem o arquivo e imprimem `gravado <modo>`. | unitário |
| CA5 | `--check` ignora linhas vazias e comentários `#` e tira os espaços das pontas: um arquivo com um comentário, uma linha vazia e `  sbx  ` devolve `sbx`. | unitário |
| CA6 | `--check` imprime `inválido`, com código 0, para um arquivo vazio, só com comentários, com `SBX` ou com `docker`. | unitário |
| CA7 | `--set docker`, `--set` sem valor, `--check --set sbx` e uma opção desconhecida saem com código 1, com mensagem em stderr, sem criar nem alterar o arquivo. | unitário |
| CA8 | Fora de um repositório git e sem `--project`, e com `--project` num diretório que não existe, o script sai com código 1 e mensagem em stderr. | unitário |
| CA9 | Com `sandbox.enabled: true` no `.claude/settings.json` do projeto, `--check` e `--set` imprimem em stderr `setup-isolation: sandbox nativo ligado em .claude/settings.json`, sem mudar a saída nem o código. Sem o arquivo, com JSON inválido ou com `enabled: false`, não há aviso nem erro. O `.claude/settings.json` fica idêntico em todos os casos. | unitário |
| CA10 | `bash scripts/test-setup-isolation.sh` passa, e os testes existentes continuam passando: `test-protect-main.sh`, `test-statusline.sh`, `test-setup-sandbox.sh`, `test-protect-production.sh`, `test-check-gh.sh`, `test-stage-usage.sh`, `test-costs.sh` e `test-durations.sh`. | unitário |
| CA11 | O `skills/setup/SKILL.md` tem o passo "Modo de isolamento" como primeiro passo, com as quatro situações da tabela, e não cita `bwrap`, `socat`, `apparmor`, `setup-sandbox.sh`, `setup-git-auth.sh`, `tlsTerminate` nem `chaveiro`. O `description` do frontmatter fala do modo de isolamento, e não do sandbox nativo. | manual — leitura do arquivo e `grep -inE 'bwrap|socat|apparmor|setup-sandbox|setup-git-auth|tlsTerminate|chaveiro' skills/setup/SKILL.md` sem resultado |
| CA12 | O checklist do modo `sbx` no `SKILL.md` tem os 6 itens desta spec, com os comandos escritos como aqui, e cada comando `sbx` citado existe na ajuda do `sbx` instalado. | manual — conferir cada comando com `sbx <comando> --help` |
| CA13 | Num projeto sem o arquivo, o `/fabrica:setup` pergunta o modo antes de qualquer outro passo, com `sbx (Recomendado)` como primeira opção, grava a resposta e, no modo `sbx`, termina com o checklist, sem oferecer o sandbox nativo nem pedir o `setup-git-auth.sh`. | depois do merge — depende de responder à pergunta do `/fabrica:setup` |
| CA14 | Com a resposta "sem sandbox", o resumo traz o aviso de que não há isolamento e não traz o checklist. Rodado de novo no mesmo projeto, o setup não pergunta o modo e mostra o que está gravado. | depois do merge — depende de responder à pergunta do `/fabrica:setup` |
| CA15 | A ADR 0010 está com status `aceito`, a ADR 0005 com `substituído por ADR 0010`, e as ADRs 0006 e 0007 têm a nota de uma linha que remete à 0010. | manual — leitura dos quatro arquivos |
| CA16 | O guia `docs/guias/isolamento-do-agente.md` tem as 8 seções desta spec e não cita `bwrap`, `socat`, `AppArmor`, `mask`, `tlsTerminate`, `git-auth`, `chaveiro`, `deniedDomains` nem `test-sandbox-acceptance`. Os links internos de `docs/` e de `skills/` para âncoras do guia apontam para seções que existem. | manual — leitura, `grep -inE` dos termos sem resultado e `grep -rn 'isolamento-do-agente.md#' docs skills templates` conferido contra os títulos |
| CA17 | `docs/comandos.md`, `docs/principios.md`, `docs/README.md`, `templates/CLAUDE.md` e `CLAUDE.md` descrevem os dois modos no lugar do sandbox nativo: nenhum deles diz que o setup liga o sandbox do Claude Code nem que o sandbox bloqueia os hosts de produção na rede. O `CLAUDE.md` lista o `scripts/test-setup-isolation.sh`. | manual — leitura dos cinco arquivos |
| CA18 | A `version` do `.claude-plugin/plugin.json` sobe para a próxima versão menor a partir da que estiver na `main` no momento da implementação (hoje `0.32.0`, então `0.33.0`). | manual — `git diff origin/main -- .claude-plugin/plugin.json` |

## Fora de escopo
- **Parte B (issue própria):** apagar `templates/sandbox-project.json`, `templates/sandbox-user.json`, `scripts/setup-sandbox.sh`, `scripts/setup-git-auth.sh` e os testes deles; remover o bloco `sandbox` dos projetos já instalados e o `mask`, o `tlsTerminate` e o `git-auth.gitconfig` da máquina; reescrever o `scripts/test-sandbox-acceptance.sh` para o `sbx`. Nesta issue, esses arquivos ficam no plugin, sem uso pelo setup.
- **Parte C (issue própria):** `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md`, `agents/revisor.md` e o texto da ADR 0007 não mudam. As assinaturas de limite do sandbox continuam nas etapas.
- `status`, `metricas` e o dispatcher não leem o `.fabrica/isolamento.txt` nesta issue.
- O `docs/prd.md` não é editado: a F1 é ajustada pelo usuário com `/fabrica:prd`.
- A #106 não é editada: o usuário revisa o escopo dela depois do ADR.
- O setup não instala o `sbx`, não cria a VM, não aplica a política de rede e não grava o secret.
- A máquina de estados (`skills/status/estados.md`) não muda: não há label, marcador nem etapa nova.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/setup-isolation.sh` (novo): lê e grava o modo, no padrão dos outros `setup-*.sh` (`set -euo pipefail`, `fail()`, `--project` como no `setup-sandbox.sh`).
- `scripts/test-setup-isolation.sh` (novo): no padrão do `scripts/test-setup-sandbox.sh` (projeto e `HOME` temporários, função `check "<CA> <descrição>" "<esperado>" "<obtido>"`).
- `skills/setup/SKILL.md`: passo novo "Modo de isolamento", passo "Sandbox" removido, seções "Responder" e "Regras" e o `description` ajustados.
- `docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md` (status), `docs/adr/0005-isolamento-do-agente-em-sandbox.md` (status), `docs/adr/0006-producao-fora-do-alcance-do-agente.md` e `docs/adr/0007-verificacao-de-integracao-pelo-ci.md` (nota).
- `docs/guias/isolamento-do-agente.md` (reescrito), `docs/comandos.md`, `docs/principios.md`, `docs/README.md`, `templates/CLAUDE.md`, `CLAUDE.md`, `hooks/protect-production.sh` (só o comentário), `.claude-plugin/plugin.json`.

**Dados:** `.fabrica/isolamento.txt` no projeto, com uma linha: `sbx` ou `sem-sandbox`.

**Interfaces:** `setup-isolation.sh [--check] [--set sbx|sem-sandbox] [--project <dir>]`, com as saídas da tabela de "Comportamento esperado". Stdout tem sempre uma linha só; os avisos e os erros vão em stderr, com o prefixo `setup-isolation:`.

**Decisões:**
- O modo fica em `.fabrica/isolamento.txt`, versionado, com uma linha (`sbx` ou `sem-sandbox`) (recomendação da triagem) — a issue sugere esse caminho e o projeto já guarda a configuração da fábrica em `.fabrica/` (`.fabrica/producao.txt`, ADR 0006). Alternativa descartada: uma chave no `.claude/settings.json`.
- Bloqueio de rede dos hosts de produção: no modo `sbx`, vale a política de rede escopada do checklist, que não lista os hosts de produção; no modo sem sandbox, fica só o hook `protect-production.sh`, e o setup diz isso (recomendação da triagem) — a issue pede os allows escopados e define o modo sem sandbox como "sem isolamento, por decisão explícita". Alternativa descartada: manter um bloqueio de rede próprio no modo sem sandbox.
- PRD: a ADR 0010 registra o modo sem sandbox como exceção explícita à F1, e o PR não edita o `docs/prd.md`; o usuário ajusta a F1 com `/fabrica:prd` quando quiser (recomendação da triagem) — a seção "Decisão" da issue define os dois modos, e o PRD só muda pelo `/fabrica:prd`, que mantém a tabela `### Mudanças`. Alternativa descartada: esperar o ajuste do PRD antes de implementar.
- O setup só imprime o checklist do `sbx`, sem rodar comando `sbx` — a VM, a política e o secret são do host, e o setup também roda dentro da VM, onde o `sbx` não existe; mexer em política de rede e em credencial é gesto do usuário, como o `setup-git-auth.sh` era. Alternativa descartada: o setup rodar os comandos quando achar o `sbx` no `PATH`.
- O setup não tenta detectar se está no host ou dentro da VM — o checklist marca cada item como "no host" ou "dentro da VM", e o arquivo do modo chega à VM pela pasta do projeto, então lá o setup não pergunta de novo. Alternativa descartada: detectar a VM por variável de ambiente ou usuário `agent`, que a ajuda do `sbx` não documenta.
- Fechar a rede padrão com `sbx policy reset` e `sbx policy init deny-all` (item 1 do checklist) — a ajuda do `sbx policy init` diz que a inicialização é única e que o `reset` permite refazê-la, e traz "deny-all e depois `sbx policy allow network`" como exemplo. A issue só diz que é preciso trocar o `default-allow-all`; se no teste o caminho foi outro, vale o do teste. Alternativa descartada: `sbx policy init balanced`, que libera serviços de IA e registros de pacote além da lista da issue.
- Com o modo já gravado, o setup não pergunta de novo, e a troca é pela edição do arquivo num PR — o arquivo é versionado, e uma troca de modo é uma mudança do projeto, que entra por PR. Alternativa descartada: perguntar a cada execução.
- O script avisa do bloco `sandbox` nativo, mas não o remove — a remoção é a migração da parte B, e afrouxar ou mudar permissões do projeto é gesto do usuário (regra já usada no aviso `permissions.deny nega <regra>`). Alternativa descartada: remover o bloco já nesta issue.
- Os scripts e os templates do sandbox nativo ficam no plugin, sem uso, até a parte B — apagar e migrar juntos evita um plugin sem o script que o guia de migração citaria. Alternativa descartada: apagar tudo aqui, o que passa do tamanho `G`.

**Fontes da documentação:**
- sbx v0.51.0 — ajuda local: `sbx --help`, `sbx policy --help`, `sbx policy init --help`, `sbx policy reset --help`, `sbx policy allow network --help`, `sbx policy ls --help`, `sbx policy log --help`, `sbx secret set --help`, `sbx create --help`, `sbx run --help`.
- gh 2.103.3 — a spec não cita flag nem campo `--json` do `gh` no desenho técnico.

**ADR:** [docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)

## Testes
- `bash scripts/test-setup-isolation.sh`: um bloco por critério, de CA1 a CA9, com projeto temporário (`git init`) e `--project`. O CA3 compara o conteúdo e a data de modificação do arquivo antes e depois. O CA8 roda o script num diretório temporário fora de repositório git. O CA9 compara o `.claude/settings.json` antes e depois com `cmp`.
- CA10: rodar cada `scripts/test-*.sh` da lista. O repositório não tem `Makefile` nem CI; os testes rodam direto com `bash`.
- CA11, CA12, CA15, CA16, CA17 e CA18: verificação manual por leitura e pelos `grep` indicados. O CA12 precisa do `sbx` instalado; sem ele na máquina da etapa, o revisor confere os comandos contra a seção "Fontes da documentação" e anota isso.
- CA13 e CA14: depois do merge, o usuário roda o `/fabrica:setup` num projeto sem o arquivo (ex.: o `kairo`), uma vez em cada modo.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Rede do `sbx`:** a lista de hosts da issue não tem `api.anthropic.com`. Com a rede padrão fechada (`deny-all`), o próprio Claude Code pode ficar sem a API se o `sbx` não a liberar por conta própria. O item 6 do checklist (conferir com `sbx policy log`) existe para isso, e o guia diz para liberar o host que aparecer bloqueado e for necessário. O usuário confirma no teste do CA13.
- **Comandos do `sbx`:** a versão 0.51.0 é recente, e a ajuda marca comandos como experimentais ou obsoletos (`policy set-default` já virou `policy init`). O guia cita a versão em que o checklist foi conferido.
- **Período entre a parte A e a parte B:** o `kairo` e o `ancora` continuam com o bloco `sandbox` no `.claude/settings.json`, e a máquina, com o `mask` e o `git-auth.gitconfig`. O setup avisa, e o guia traz o contorno.
- **PRD:** a F1 continua dizendo "o agente roda em sandbox" até o usuário ajustá-la. A ADR 0010 é o registro da exceção.
- **Arquivo sensível:** a issue mexe no isolamento e na orientação sobre credenciais. A revisão humana é obrigatória.

## Histórico
- 2026-11-12: criação.
