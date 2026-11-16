# SPEC-142: Remover o sandbox nativo do plugin e migrar os projetos já instalados

**Issue:** #142 · **PRD:** F1 · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-15

## Contexto
A F1 do PRD pede que o agente rode isolado. A [ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) trocou o sandbox nativo do Claude Code pelo `sbx`, e a #141 (parte A) fez o `/fabrica:setup` perguntar o modo de isolamento. Ficaram para esta issue (parte B) os restos do sandbox nativo: os scripts e os templates, que continuam no plugin sem uso; o bloco `sandbox` no `.claude/settings.json` dos projetos que passaram pelo setup antigo (`kairo` e `ancora`), que esconde o `GH_TOKEN` dentro da VM; o que o setup antigo gravou na máquina, incluindo um arquivo com credencial; e o teste de aceite, que ainda testa o sandbox nativo.

## Objetivo
O plugin deixa de ter os arquivos do sandbox nativo, o `/fabrica:setup` remove o que o setup antigo gravou no projeto e, com confirmação e backup, na máquina, e o `scripts/test-sandbox-acceptance.sh` passa a conferir o isolamento de dentro da VM do `sbx`.

## Comportamento esperado

### Arquivos que saem do plugin
`templates/sandbox-project.json`, `templates/sandbox-user.json`, `scripts/setup-sandbox.sh`, `scripts/setup-git-auth.sh` e `scripts/test-setup-sandbox.sh` são apagados. Nenhum outro arquivo do repositório cita esses nomes, fora de `specs/` e de `docs/adr/`, que guardam o histórico.

### O script `scripts/migrate-native-sandbox.sh`
Uso: `migrate-native-sandbox.sh [--check] [--apply projeto|maquina] [--project <dir>]`. Sem `--check` nem `--apply`, vale `--check`. Sem `--project`, o projeto é a raiz do repositório git do diretório atual; fora de um repositório git e sem `--project`, o script trata só a máquina.

**O que é resto do sandbox nativo:**

| Item | Onde | Condição para ser resto |
|---|---|---|
| `projeto:sandbox` | `.claude/settings.json` do projeto | O arquivo tem a chave `sandbox`, com qualquer conteúdo, inclusive `enabled: false`. |
| `maquina:tlsTerminate` | `settings.json` do usuário (`$CLAUDE_CONFIG_DIR` ou `~/.claude`) | `sandbox.network.tlsTerminate` existe e é `{}`. Com outro valor, não é da fábrica e fica. |
| `maquina:mask:~/.config/gh/hosts.yml` | `settings.json` do usuário | `sandbox.credentials.files` tem uma entrada idêntica, chave por chave, à que a fábrica gravava (abaixo). A ordem das chaves não importa. |
| `maquina:mask:~/.config/fabrica/git-auth.gitconfig` | `settings.json` do usuário | Idem, com a segunda entrada. |
| `maquina:gitconfig-include` | configuração global do git | `include.path` tem o valor exato `~/.config/fabrica/git-auth.gitconfig`. |
| `maquina:git-auth` | `~/.config/fabrica/git-auth.gitconfig` | O arquivo existe. |

As duas entradas de `mask` que a fábrica gravava, hoje em `templates/sandbox-user.json`, passam a ser constantes do script:

```json
{"path": "~/.config/gh/hosts.yml", "mode": "mask", "extract": "oauth_token:\\s*(\\S+)", "maskDuplicates": true, "onExtractNoMatch": "deny", "injectHosts": ["api.github.com", "github.com"]}
{"path": "~/.config/fabrica/git-auth.gitconfig", "mode": "mask", "extract": "Basic\\s+(\\S+)", "maskDuplicates": true, "onExtractNoMatch": "deny", "injectHosts": ["github.com"]}
```

Uma entrada com o mesmo `path` e qualquer campo diferente não é idêntica: fica no arquivo e não vira item.

**Saídas:**

| Situação | Saída (stdout) | Código |
|---|---|---|
| `--check`, sem nenhum resto | `ok` | 0 |
| `--check`, com restos | `pendente <itens>`, com os itens separados por espaço, na ordem da tabela acima | 0 |
| `--apply projeto`, com `projeto:sandbox` | remove o item; imprime `removido projeto:sandbox` | 0 |
| `--apply maquina`, com itens `maquina:*` | remove os itens; imprime `removido <itens>` | 0 |
| `--apply <alvo>`, sem resto nesse alvo | não grava nada; imprime `ok` | 0 |
| `--apply projeto` fora de um repositório git e sem `--project` | erro em stderr | 1 |
| `--apply` com outro valor ou sem valor, `--check` e `--apply` juntos, opção desconhecida, ou `--project` num diretório que não existe | erro em stderr com o uso | 1 |
| Um `settings.json` que o comando leria tem JSON inválido ou não é um objeto | `migrate-native-sandbox: JSON inválido em <caminho>` em stderr; nada é gravado | 1 |
| Falha de escrita num arquivo | `migrate-native-sandbox: não consegui gravar <caminho>: <motivo>` em stderr | 1 |

O `--check` nunca grava nada. Um arquivo que não existe não tem resto e não é erro. Rodar o mesmo `--apply` duas vezes dá `removido …` e depois `ok`.

**`--apply projeto`:**
- Remove a chave `sandbox` inteira do `.claude/settings.json` do projeto e deixa as outras chaves como estão. Se `sandbox` era a única chave, o arquivo fica com `{}`: o script não apaga o arquivo.
- Grava com `indent=2`, sem escapar acentos, com quebra de linha no fim. Se o projeto tiver `node_modules/.bin/prettier` executável, roda `prettier --write` no arquivo, como o `setup-sandbox.sh` fazia (#112); se o Prettier falhar, avisa em stderr `migrate-native-sandbox: não consegui formatar .claude/settings.json; rode o prettier do projeto nele.` e sai com 0.
- Sem backup: o arquivo é versionado, e o `git diff` mostra e desfaz a mudança.
- Não mexe no `.prettierignore`, no `.fabrica/` nem em `permissions`.

**`--apply maquina`:**
- **`settings.json` do usuário:** antes de gravar, copia o arquivo para `settings.json.bak-fabrica-sandbox`, na mesma pasta, sobrescrevendo um backup anterior de mesmo nome. Remove só os itens da tabela. Depois, remove os contêineres que ficaram vazios, de dentro para fora: `sandbox.credentials.files` se virou `[]`, `sandbox.credentials` e `sandbox.network` se viraram `{}`, e `sandbox` se virou `{}`. Um contêiner que já estava vazio antes e não continha item da fábrica não é tocado. As outras chaves do arquivo ficam como estão.
- **Configuração global do git:** antes de alterar, copia o arquivo de onde o valor vem (o que `git config --global --show-origin --get-all include.path` aponta para esse valor) para `<arquivo>.bak-fabrica-sandbox`. Remove só o valor `~/.config/fabrica/git-auth.gitconfig` de `include.path`; os outros `include.path` ficam.
- **`~/.config/fabrica/git-auth.gitconfig`:** apaga o arquivo, sem backup, porque ele guarda uma credencial. O script nunca imprime o conteúdo dele.
- A ordem é: `settings.json`, depois a inclusão do git, depois o arquivo da credencial. Uma falha interrompe o script, e a mensagem diz o que já foi removido.

### O `/fabrica:setup`
O passo 1, "Modo de isolamento", ganha no começo a migração, antes de ler o modo:

| Situação | O que o setup faz |
|---|---|
| `migrate-native-sandbox.sh --check` imprime `ok` | Nada. A migração não aparece no resumo. |
| O `--check` lista `projeto:sandbox` | Roda `--apply projeto`, sem perguntar. No resumo, diz que o bloco `sandbox` do `.claude/settings.json` era do sandbox nativo, que saiu da fábrica, que ele foi removido na cópia de trabalho e que o usuário leva a mudança por uma branch e um PR. Não faz o commit. |
| O `--check` lista itens `maquina:*` | Mostra os itens, um por linha, com o que cada um é, e diz onde ficam os backups e que o `git-auth.gitconfig` é apagado sem backup por guardar uma credencial. Pergunta com o AskUserQuestion se remove. Com um sim, roda `--apply maquina`. Com um não, não remove nada e registra no resumo "restos do sandbox nativo na máquina: mantidos, a pedido do usuário". |
| O script sai com código 1 | Leva a mensagem de erro para o resumo e segue para a leitura do modo. |
| Fora de um repositório git | A migração roda só para a máquina; a leitura do modo continua pulada, como hoje. |

- A migração vale nos dois modos de isolamento e também antes de o modo ser escolhido.
- O aviso `sandbox nativo ligado em .claude/settings.json` do `setup-isolation.sh` continua existindo. Como a migração roda antes, ele só aparece quando ela falhou; nesse caso, o setup leva o aviso para o resumo com o erro da migração.
- Sai da skill a regra "Não altere o bloco `sandbox` do `.claude/settings.json` do projeto" e a frase "Não remova o bloco". Entra a regra: "Não remova os restos do sandbox nativo da máquina sem a confirmação do usuário, e não edite o `~/.claude/settings.json` nem o `~/.gitconfig` por outro caminho."
- O resumo (seção "Responder") ganha, na linha "Isolamento", o que a migração fez: nada a dizer, bloco do projeto removido, restos da máquina removidos (com o caminho dos backups) ou mantidos.

### O teste de aceite `scripts/test-sandbox-acceptance.sh`
Reescrito para rodar pelo Bash do agente, dentro da VM do `sbx` de um projeto preparado pelo checklist do setup. Uso: `test-sandbox-acceptance.sh [--remote <nome>]` (padrão `origin`). Imprime uma linha por verificação, `ok <verificação>` ou `falha <verificação>: <motivo>`, e sai com 1 se alguma falhar. Fora de um repositório git ou com opção desconhecida, erro em stderr e código 1, sem rodar verificação nenhuma.

| Verificação | Passa quando |
|---|---|
| `token-marcador` | `GH_TOKEN` não está vazia e o valor não tem o formato de um token real do GitHub (`gh[opsu]_` seguido de 30 ou mais letras e dígitos, ou `github_pat_`). |
| `home-isolado` | Nenhum arquivo legível em `~/.ssh` e nenhum `oauth_token` em `~/.config/gh/hosts.yml`. A falta da pasta ou do arquivo passa. |
| `gh-api-user` | `gh api user -q .login` devolve um login. |
| `dominio-liberado` | `curl -s --max-time 10 https://api.github.com/zen` sai com 0 e devolve um corpo não vazio. |
| `dominio-fora-da-lista` | `curl -s --max-time 10 https://example.com` não devolve um corpo com `Example Domain`. A verificação olha o corpo, e não o código HTTP, porque o proxy do `sbx` responde 200 ao CONNECT de um host bloqueado. |
| `hooks-do-git` | O `core.hooksPath` global aponta para uma pasta com um `pre-push` executável. |
| `push-na-main-recusado` | `git push --dry-run <remote> <sha>:refs/heads/main` sai com código diferente de 0 e a mensagem tem `Push para a main bloqueado`. O `<sha>` é um commit solto, criado com `git commit-tree` sobre o `HEAD`, para o push ter o que mandar mesmo com o `HEAD` igual à `main`. Com `--dry-run`, nada chega ao remoto se o hook faltar. |
| `git-push` | `git push` de uma branch `test/sandbox-<AAAAMMDDHHMMSS>` funciona; a branch é apagada em seguida. Se apagar falhar, sai `falha git-push-limpeza: apague a branch <nome> em <remote>`. |

- Se `push-na-main-recusado` falhar porque o push de teste passou (código 0), o motivo é `os hooks do git não estão instalados nesta VM; rode /fabrica:setup`.
- No fim, com tudo `ok`, o script imprime `confira no host: sbx policy log <pasta do repositório>`, porque só o log do proxy mostra o que foi bloqueado.
- Saem do teste as verificações do sandbox nativo: escrita fora do projeto, `.claude/settings.json` protegido, `.env.production` ilegível, reflexão do marcador, `token-no-git-auth`, `token-com-expiracao` e `npm-view`.
- Docker e Compose dentro da VM não entram neste aceite: são da #143.

### Documentação
- **Guia `docs/guias/isolamento-do-agente.md`:**
  - "Projetos com o sandbox nativo" passa a descrever a migração pelo `/fabrica:setup`: o que ele remove do projeto sem perguntar, o que ele remove da máquina com confirmação, onde ficam os backups (`settings.json.bak-fabrica-sandbox` e `<gitconfig>.bak-fabrica-sandbox`) e que o `git-auth.gitconfig` é apagado. Saem a frase "Até a issue que faz essa migração (#142)" e o contorno com `--settings`. Entra uma frase dizendo que as linhas do `.prettierignore` gravadas pelo setup antigo (abaixo do comentário `fabrica#116`) não fazem mal e podem ser apagadas à mão.
  - "Modo `sbx`" ganha a subseção "Teste de aceite": quando rodar (VM nova, troca de versão do `sbx`, mudança na política), o comando, dentro da VM, e o que cada verificação confere.
- **`docs/comandos.md`**, seção do `/fabrica:setup`: "O que faz" e "Lê" passam a dizer que o setup remove os restos do sandbox nativo, do projeto sem perguntar e da máquina com confirmação, no lugar de "só para avisar".
- **`CLAUDE.md`:** a lista de scripts troca a frase dos scripts do sandbox nativo ("não são mais usados… saem na #142") pelo `migrate-native-sandbox.sh`, com o teste `bash scripts/test-migrate-native-sandbox.sh`, e pelo aceite `scripts/test-sandbox-acceptance.sh`, que roda dentro da VM do `sbx`.
- **ADR 0010:** a última consequência ("Um aceite novo fica para a issue que remove o sandbox nativo do plugin") ganha a referência a esta issue: o aceite é o `scripts/test-sandbox-acceptance.sh` reescrito na #142. As ADRs 0005 e 0006 não mudam: a nota da 0006 sobre o `deniedDomains` já está na `main`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `templates/sandbox-project.json`, `templates/sandbox-user.json`, `scripts/setup-sandbox.sh`, `scripts/setup-git-auth.sh` e `scripts/test-setup-sandbox.sh` não existem, e `grep -rnE 'setup-sandbox|setup-git-auth|sandbox-user\.json|sandbox-project\.json' . --exclude-dir=.git --exclude-dir=specs --exclude-dir=adr` não devolve nada. | manual — `ls` dos cinco caminhos e o `grep` |
| CA2 | Num projeto e num `HOME` sem resto nenhum (sem os arquivos, ou com um `settings.json` sem `sandbox`), `migrate-native-sandbox.sh --check` imprime `ok`, sai com 0 e não cria nem altera arquivo. Sem opção nenhuma, o script se comporta como `--check`. | unitário (`scripts/test-migrate-native-sandbox.sh`) |
| CA3 | Com o bloco `sandbox` no projeto e os quatro restos na máquina, `--check` imprime `pendente projeto:sandbox maquina:tlsTerminate maquina:mask:~/.config/gh/hosts.yml maquina:mask:~/.config/fabrica/git-auth.gitconfig maquina:gitconfig-include maquina:git-auth`, nessa ordem, e todos os arquivos ficam idênticos. | unitário |
| CA4 | `--apply projeto` remove a chave `sandbox` e mantém as outras chaves com os mesmos valores (ex.: `permissions` e `hooks`); imprime `removido projeto:sandbox`; nenhum arquivo de backup é criado no projeto, e os arquivos da máquina ficam idênticos. Rodado de novo, imprime `ok` e não regrava o arquivo (mesma data de modificação). | unitário |
| CA5 | `--apply projeto` num `settings.json` em que `sandbox` é a única chave deixa o arquivo com `{}`, sem apagá-lo. Um bloco com `"enabled": false` também é removido. | unitário |
| CA6 | `--apply maquina` remove do `settings.json` do usuário o `tlsTerminate: {}` e as duas entradas de `mask` idênticas às da fábrica, mesmo com as chaves em outra ordem; as outras chaves do arquivo (ex.: `statusLine`, `permissions`) ficam com os mesmos valores; o `settings.json.bak-fabrica-sandbox` tem o conteúdo de antes, byte a byte. | unitário |
| CA7 | Depois do `--apply maquina`, os contêineres que ficaram vazios somem: com só os itens da fábrica, o arquivo fica sem a chave `sandbox`. Com uma entrada a mais do usuário em `credentials.files` e um `allowedDomains` em `network`, essas duas ficam, com `sandbox`, `credentials` e `network` preservados. | unitário |
| CA8 | Uma entrada de `mask` com o mesmo `path` da fábrica e um campo diferente (ex.: outro `extract`) não aparece no `--check` e continua no arquivo depois do `--apply maquina`. Um `tlsTerminate` com conteúdo (ex.: `{"x": 1}`) também. | unitário |
| CA9 | `--apply maquina` remove de `include.path` só o valor `~/.config/fabrica/git-auth.gitconfig`: um segundo `include.path` do usuário continua, e o `.gitconfig.bak-fabrica-sandbox` tem o conteúdo de antes. O `~/.config/fabrica/git-auth.gitconfig` deixa de existir, não há cópia dele em lugar nenhum do `HOME` de teste, e o valor que ele guardava não aparece no stdout nem no stderr do script. | unitário |
| CA10 | `--apply maquina` com só parte dos restos (ex.: só o `git-auth.gitconfig`, sem `settings.json`) remove o que há, imprime `removido maquina:git-auth` e sai com 0. Sem resto nenhum, imprime `ok` e não cria backup. | unitário |
| CA11 | Com JSON inválido no `settings.json` do projeto, `--check` e `--apply projeto` saem com 1 e `migrate-native-sandbox: JSON inválido em <caminho>` em stderr; com JSON inválido no do usuário, o mesmo vale para `--check` e `--apply maquina`. Em todos os casos, nenhum arquivo muda e nenhum backup é criado. | unitário |
| CA12 | `--apply docker`, `--apply` sem valor, `--check --apply projeto`, uma opção desconhecida e `--project` num diretório que não existe saem com 1, com mensagem em stderr, sem alterar arquivo. Fora de um repositório git e sem `--project`, `--check` lista só os itens `maquina:*`, e `--apply projeto` sai com 1. | unitário |
| CA13 | Com `node_modules/.bin/prettier` executável no projeto, `--apply projeto` o chama com `--write .claude/settings.json`; se ele falhar, o script avisa em stderr e sai com 0, com o bloco removido. | unitário, com um `prettier` falso |
| CA14 | O `skills/setup/SKILL.md` descreve a migração no começo do passo 1, com as cinco situações da tabela desta spec; não tem mais a regra "Não altere o bloco `sandbox`…" nem "Não remova o bloco"; tem a regra da confirmação para a máquina; e a seção "Responder" inclui o resultado da migração. | manual — leitura do arquivo |
| CA15 | Num projeto com o bloco `sandbox` (ex.: o `kairo`), numa máquina com os restos, o `/fabrica:setup` remove o bloco do projeto sem perguntar, pergunta antes de mexer na máquina e, com um sim, deixa o `~/.claude/settings.json` sem os itens da fábrica, o `~/.gitconfig` sem a inclusão e a máquina sem o `git-auth.gitconfig`, com os dois backups criados. Rodado de novo, não fala da migração. | depois do merge — depende de responder à pergunta do `/fabrica:setup` |
| CA16 | `bash -n scripts/test-sandbox-acceptance.sh` passa; o script não cita `git-auth`, `hosts.yml` com `mask`, `tlsTerminate`, `.env.production` nem `setup-git-auth`; com uma opção desconhecida, e fora de um repositório git, sai com 1 e mensagem em stderr, sem imprimir nenhuma linha `ok` ou `falha`. | unitário (bloco no `scripts/test-migrate-native-sandbox.sh`) e `grep` |
| CA17 | O `scripts/test-sandbox-acceptance.sh` tem as oito verificações da tabela desta spec, com os nomes dela, e o push de teste na `main` usa `--dry-run`. | manual — leitura do arquivo |
| CA18 | Dentro da VM do `sbx` de um projeto preparado pelo checklist, o aceite imprime `ok` nas oito verificações e sai com 0. Numa VM sem os hooks do git, `push-na-main-recusado` falha com o motivo que manda rodar o `/fabrica:setup`, e a `main` do remoto não muda. | depois do merge — depende de uma VM do `sbx`, que o usuário cria no host com a política de rede e o secret |
| CA19 | O guia tem a seção "Projetos com o sandbox nativo" reescrita, sem `#142` e sem o contorno com `--settings`, e a subseção "Teste de aceite" em "Modo `sbx`"; `docs/comandos.md` e `CLAUDE.md` descrevem a migração e não dizem que o setup "só avisa" nem que os scripts "saem na #142"; a ADR 0010 cita o aceite reescrito. | manual — leitura dos quatro arquivos |
| CA20 | `bash scripts/test-migrate-native-sandbox.sh` passa, e os testes existentes continuam passando: `test-setup-isolation.sh`, `test-protect-main.sh`, `test-statusline.sh`, `test-protect-production.sh`, `test-check-gh.sh`, `test-stage-usage.sh`, `test-costs.sh` e `test-durations.sh`. | unitário |
| CA21 | A `version` do `.claude-plugin/plugin.json` sobe para a próxima versão menor a partir da que estiver na `main` no momento da implementação (hoje `0.33.0`, então `0.34.0`). | manual — `git diff origin/main -- .claude-plugin/plugin.json` |

## Fora de escopo
- Verificação de integração (Docker, banco, `make e2e`) dentro da VM, e o texto da ADR 0007: #143.
- `status`, `metricas` e o dispatcher não leem o modo de isolamento nesta issue. A #106 não é editada.
- O `docs/prd.md` não é editado: a métrica "teste de aceite do isolamento (F1) passando" mantém o texto e passa a ser medida pelo aceite reescrito.
- O PR desta issue não altera o `kairo` nem o `ancora`: a migração acontece quando o usuário roda o `/fabrica:setup` em cada um e leva a mudança por PR.
- O `.prettierignore` dos projetos: as linhas gravadas pelo setup antigo (#116) ficam.
- Os backups antigos e os novos (`*.bak-fabrica-sandbox`) não são apagados pelo script.
- O setup continua sem rodar comando `sbx`; o aceite também não roda.
- A máquina de estados (`skills/status/estados.md`) não muda: não há label, marcador nem etapa nova.

## Desenho técnico
**Arquivos e módulos:**
- Apagados: `templates/sandbox-project.json`, `templates/sandbox-user.json`, `scripts/setup-sandbox.sh`, `scripts/setup-git-auth.sh`, `scripts/test-setup-sandbox.sh`.
- `scripts/migrate-native-sandbox.sh` (novo): no padrão dos outros scripts (`set -euo pipefail`, `fail()`, `--project` como no `setup-isolation.sh`), com a parte de JSON em `python3 -I`, como o `setup-sandbox.sh` fazia.
- `scripts/test-migrate-native-sandbox.sh` (novo): no padrão do `scripts/test-setup-isolation.sh` (projeto, `HOME` e `CLAUDE_CONFIG_DIR` temporários, função `check "<CA> <descrição>" "<esperado>" "<obtido>"`).
- `scripts/test-sandbox-acceptance.sh` (reescrito).
- `skills/setup/SKILL.md`, `docs/guias/isolamento-do-agente.md`, `docs/comandos.md`, `CLAUDE.md`, `docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md`, `.claude-plugin/plugin.json`.
- `scripts/setup-isolation.sh` não muda.

**Dados:** nenhum arquivo novo nos projetos. Na máquina, os backups `settings.json.bak-fabrica-sandbox` e `<gitconfig>.bak-fabrica-sandbox`.

**Interfaces:** `migrate-native-sandbox.sh [--check] [--apply projeto|maquina] [--project <dir>]` e `test-sandbox-acceptance.sh [--remote <nome>]`, com as saídas de "Comportamento esperado". No primeiro, stdout tem sempre uma linha só; os avisos e os erros vão em stderr, com o prefixo `migrate-native-sandbox:`.

**Decisões:**
- O bloco `sandbox` do projeto sai inteiro (recomendação da triagem) — a ADR 0010 diz que "o `.claude/settings.json` dos projetos deixa de ter o bloco `sandbox`" e que o bloco "esconde o `GH_TOKEN` dentro da VM até ser removido", e a issue pede "remove o bloco". Alternativa descartada: tirar só as chaves que a fábrica gravou e deixar as que o usuário acrescentou.
- O setup altera o `.claude/settings.json` do projeto na cópia de trabalho, sem pedir confirmação, e o usuário leva a mudança por branch e PR (recomendação da triagem) — a SPEC-141 já trata assim o `.fabrica/isolamento.txt`, e o arquivo é versionado, então o `git diff` mostra e desfaz a mudança. A confirmação e o backup ficam para a máquina, onde a issue os pede. Alternativa descartada: perguntar também antes de mexer no projeto.
- A remoção vale nos dois modos, `sbx` e `sem-sandbox` (recomendação da triagem) — a ADR 0010 decide que "o sandbox nativo do Claude Code sai da fábrica", sem exceção por modo. Alternativa descartada: manter o bloco nos projetos em `sem-sandbox`.
- Na máquina, o script lista os itens no `--check` e só remove a entrada idêntica à que a fábrica gravava, com backup `.bak-fabrica-sandbox` (recomendação da triagem) — é o padrão que a issue cita, o dos itens `remover:` da ADR 0006 em `scripts/setup-sandbox.sh`, e o backup segue o que o mesmo script já fazia do `settings.json` do usuário. Alternativa descartada: apagar o bloco `sandbox` inteiro do `settings.json` do usuário.
- O `~/.config/fabrica/git-auth.gitconfig` é apagado na mesma confirmação que tira a inclusão do `~/.gitconfig`, sem backup dele (recomendação da triagem) — a issue diz que ele "guarda uma credencial" e a ADR 0010 diz que ele deixou de ser dependência; um backup manteria a credencial em disco. Alternativa descartada: tirar só a inclusão e deixar o arquivo.
- O aviso `sandbox nativo ligado` do `setup-isolation.sh` continua no `--check`, e o setup passa a remover o bloco em vez de só avisar; a seção do guia passa a descrever a migração (recomendação da triagem) — a issue diz "o setup remove o bloco (hoje a #141 só avisa)". Alternativa descartada: tirar o aviso do `setup-isolation.sh`, o que muda o CA9 da SPEC-141 sem ganho.
- O PR não edita o `docs/prd.md` (recomendação da triagem) — a SPEC-141 decidiu que "o PRD só muda pelo `/fabrica:prd`". Alternativa descartada: editar a métrica no PR.
- Sem ADR nova (recomendação da triagem) — a decisão é a da ADR 0010, que já prevê a remoção e o aceite novo nesta issue. Alternativa descartada: um ADR só para a migração.
- O aceite mantém o nome `scripts/test-sandbox-acceptance.sh` (recomendação da triagem) — a issue pede "reescrever" o arquivo, e o `sbx` também é um sandbox. Alternativa descartada: renomear para `test-sbx-acceptance.sh`.
- Um script novo para a migração, separado do `setup-isolation.sh` — o `setup-isolation.sh` "nunca altera" o `.claude/settings.json` (SPEC-141, CA9) e trata só do projeto; a migração mexe na máquina e sai do plugin um dia. Alternativa descartada: opções `--migrate` no `setup-isolation.sh`.
- `--apply projeto` e `--apply maquina` separados — o projeto vai sem confirmação e a máquina, com; um alvo por chamada deixa a pergunta do setup entre as duas. Alternativa descartada: um `--apply` único, que obrigaria a perguntar antes de tudo.
- O script não mexe no `.prettierignore` — a issue pede só o bloco, e as linhas do #116 são inofensivas sem o sandbox nativo. Alternativa descartada: apagar as linhas abaixo do comentário `fabrica#116`, com o risco de tirar uma linha que o usuário quer.
- O push de teste na `main` usa `--dry-run` e um commit solto de `git commit-tree` — o hook `pre-push` roda com `--dry-run` (conferido com o git 2.53.0 e o `githooks/fabrica-hook`: o push foi recusado e o remoto não mudou), então o teste nunca empurra nada para a `main`, mesmo numa VM sem os hooks. Alternativa descartada: um push de verdade, que mudaria a `main` justamente no caso que o teste quer pegar.
- A verificação de rede olha o corpo da resposta, e não o código HTTP — o proxy do `sbx` responde 200 ao CONNECT de um host bloqueado (SPEC-141). Alternativa descartada: rodar `sbx policy log` pelo script, que é comando do host e não existe na VM; ele fica como lembrete na última linha.
- O aceite não tenta detectar se está numa VM — a ajuda do `sbx` não documenta um sinal para isso (SPEC-141). Fora da VM, `token-marcador` e `home-isolado` falham, como devem.

**Fontes da documentação:**
- sbx v0.51.0 — ajuda local: `sbx secret --help` e `sbx secret set --help` ("the proxy uses stored secrets to authenticate API requests on behalf of the agent. The secret is never exposed directly"). A ajuda não descreve o valor que o `GH_TOKEN` tem dentro da VM.
- git 2.53.0 — `git push --dry-run` com o hook `pre-push`, conferido num repositório temporário; `git config --global --show-origin --get-all include.path`, conferido na máquina.
- gh 2.103.3 — `gh api --help` (`-q, --jq`).

**ADR:** nenhum novo. Vale a [ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md).

## Testes
- `bash scripts/test-migrate-native-sandbox.sh`: um bloco por critério, de CA2 a CA13, com projeto temporário (`git init`), `HOME` e `CLAUDE_CONFIG_DIR` temporários e `--project`. Os arquivos são comparados antes e depois com `cmp`. O CA9 grava no `git-auth.gitconfig` de teste um valor conhecido e confere que ele não aparece nas saídas nem em outro arquivo do `HOME`. O CA13 usa um `prettier` falso em `node_modules/.bin/`. O bloco do CA16 roda o aceite com uma opção desconhecida e fora de um repositório git.
- CA20: rodar cada `scripts/test-*.sh` da lista. O repositório não tem `Makefile` nem CI; os testes rodam direto com `bash`.
- CA1, CA14, CA17, CA19 e CA21: verificação manual por leitura e pelos `grep` indicados.
- CA15 e CA18: depois do merge. O usuário roda o `/fabrica:setup` no `kairo` e no `ancora`, no host, e o aceite dentro da VM de um deles.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Formato do marcador:** a spec assume que o `GH_TOKEN` da VM não tem o formato de um token real (`ghp_…`, `github_pat_…`). A ajuda do `sbx` não diz qual é o valor. Se o marcador tiver esse formato, `token-marcador` falha na VM e a verificação precisa de outro critério; o usuário vê isso no CA18.
- **Rede vista de dentro da VM:** a verificação pelo corpo da resposta não foi testada numa VM. Se o proxy devolver para o host bloqueado algo que o `curl` trate como sucesso com outro corpo, ela passa; se a VM tiver outra saída de rede, ela falha, como deve. O `sbx policy log`, no host, continua sendo a conferência final.
- **Arquivos fora do repositório:** o script altera o `~/.claude/settings.json` e o `~/.gitconfig` e apaga um arquivo com credencial. Os testes usam sempre `HOME` e `CLAUDE_CONFIG_DIR` temporários; nenhum teste toca a máquina de verdade. A revisão humana é obrigatória.
- **Setup dentro da VM:** lá, o `~/.claude` e o `~/.gitconfig` são os da VM, sem restos, e a migração da máquina dá `ok`. Os restos do host só saem quando o setup roda no host.
- **Sessão ainda no sandbox nativo:** se o setup rodar numa sessão com o sandbox nativo ligado, a escrita no `settings.json` do usuário pode ser negada. O script sai com 1 e a mensagem de escrita, e o setup a leva para o resumo; o usuário roda de novo fora do sandbox.
- **Backup sobrescrito:** um `settings.json.bak-fabrica-sandbox` antigo, do setup que instalou o sandbox, é sobrescrito pelo backup novo.

## Histórico
- 2026-11-12: criação.
- 2026-11-15: aprovada.
