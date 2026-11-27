---
name: setup
description: Define o modo de isolamento do projeto (VM do Docker Sandboxes, o sbx, ou sem sandbox) e grava a escolha em .fabrica/isolamento.txt, remove os restos do sandbox nativo antigo do projeto e, com confirmação, da máquina, confere se o gh está instalado, autenticado e na versão mínima da fábrica, cria ou corrige as labels da fábrica (agente, precisa-info, spec-pronta, spec-aprovada, escalonado, acao-externa, pronto-revisao, licao, em-andamento) num repositório do GitHub, conforme a tabela de estados.md, instala na máquina os hooks do git que bloqueiam commit e push na main, se o usuário quiser, instala a statusline da fábrica e, com confirmação, instala ou atualiza no projeto o workflow do dispatcher (.github/workflows/agente.yml), terminando com o checklist dos três secrets dele, e confere o CI do PR do projeto, instalando com confirmação o modelo .github/workflows/ci.yml (make lint, make test e make e2e) quando não há CI em pull_request e avisando quando o CI existente não roda o make e2e. No modo sbx, termina com o checklist da VM. Use num repositório que ainda não tem as labels, para ligar o dispatcher num projeto ou atualizar o workflow dele, para instalar o CI do PR num projeto sem CI, quando uma etapa avisar que uma label não existe ou que o gh está desatualizado, quando avisarem que os hooks do git não estão instalados, dentro de uma VM nova do sbx ou para escolher como isolar os agentes num projeto.
argument-hint: "[<dono>/<repo>]"
disable-model-invocation: true
effort: medium
---

# Setup da fábrica

Repositório: $ARGUMENTS (vazio = o repositório do diretório atual)

## 1. Modo de isolamento
Cada projeto roda os agentes num de dois modos, gravado em `.fabrica/isolamento.txt` ([ADR 0010](../../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)):
- **`sbx`:** o agente roda numa VM do Docker Sandboxes, com a rede liberada só para os hosts de uma política da VM e sem o token do GitHub dentro dela.
- **`sem-sandbox`:** o agente roda direto na máquina, sem isolamento, por decisão explícita do usuário.

O modo é sempre o do projeto do diretório atual, mesmo com um `<dono>/<repo>` no argumento, que vale só para as labels.

### Restos do sandbox nativo
Antes de ler o modo, remova o que o setup antigo gravou para o sandbox nativo do Claude Code, que saiu da fábrica. A migração vale nos dois modos e também antes de o modo ser escolhido. Rode `bash <diretório base>/../../scripts/migrate-native-sandbox.sh --check` e siga a saída:

| Situação | O que fazer |
|---|---|
| O `--check` imprime `ok` | Nada. A migração não aparece no resumo. |
| O `--check` lista `projeto:sandbox` | Rode `bash <diretório base>/../../scripts/migrate-native-sandbox.sh --apply projeto`, sem perguntar. No resumo, diga que o bloco `sandbox` do `.claude/settings.json` era do sandbox nativo, que saiu da fábrica, que ele foi removido na cópia de trabalho e que o usuário leva a mudança por uma branch e um PR. Não faça o commit. |
| O `--check` lista itens `maquina:*` | Mostre os itens, um por linha, com o que cada um é (lista abaixo). Diga onde ficam os backups e que o `git-auth.gitconfig` é apagado sem backup, por guardar uma credencial. Pergunte com o AskUserQuestion se remove. Com um sim, rode `bash <diretório base>/../../scripts/migrate-native-sandbox.sh --apply maquina`. Com um não, não remova nada e registre no resumo "restos do sandbox nativo na máquina: mantidos, a pedido do usuário". |
| O script sai com código 1 | Leve a mensagem de erro para o resumo e siga para a leitura do modo. |
| Fora de um repositório git | A migração roda só para a máquina. A leitura do modo continua pulada. |

O `--check` pode listar o item do projeto e os da máquina de uma vez: trate os dois, o projeto primeiro.

**Itens da máquina:**
- `maquina:tlsTerminate`: o `tlsTerminate` do bloco `sandbox` do `settings.json` do usuário (`~/.claude/settings.json`);
- `maquina:mask:<arquivo>`: a entrada de `mask` desse arquivo no mesmo `settings.json`;
- `maquina:gitconfig-include`: a inclusão do `git-auth.gitconfig` na configuração global do git (`~/.gitconfig`);
- `maquina:git-auth`: o arquivo `~/.config/fabrica/git-auth.gitconfig`, com o cabeçalho de autenticação do GitHub.

**Backups:** o script copia o `settings.json` do usuário para `settings.json.bak-fabrica-sandbox`, na mesma pasta, e o arquivo de configuração do git para `<arquivo>.bak-fabrica-sandbox`. Nunca mostre o conteúdo do `git-auth.gitconfig`.

### Modo
Rode `git rev-parse --show-toplevel`. Depois, conforme a situação:

| Situação | O que fazer |
|---|---|
| O `git rev-parse` falha: fora de um repositório git | Pule a leitura do modo. No resumo, diga que o modo de isolamento é por projeto e não foi definido. |
| `bash <diretório base>/../../scripts/setup-isolation.sh --check` imprime `sbx` ou `sem-sandbox` | Não pergunte nada. Mostre o modo e diga que, para trocar, o usuário edita `.fabrica/isolamento.txt` por um PR. |
| O `--check` imprime `ausente` ou `inválido` | Em `inválido`, mostre antes o conteúdo do arquivo. Explique os dois modos e pergunte com o AskUserQuestion qual usar, com `sbx (Recomendado)` como primeira opção e "sem sandbox" como segunda. Grave a resposta com `bash <diretório base>/../../scripts/setup-isolation.sh --set <sbx\|sem-sandbox>`. |
| O script imprime em stderr `sandbox nativo ligado em .claude/settings.json` | Como a migração roda antes, o aviso só aparece quando ela falhou. Leve-o para o resumo, com o erro da migração, como abaixo. |

- **Arquivo gravado agora:** o script grava na cópia de trabalho. Diga ao usuário para fazer o commit de `.fabrica/isolamento.txt` numa branch e abrir o PR. Não faça o commit você.
- **Aviso do sandbox nativo:** o bloco `sandbox` do `.claude/settings.json` é do sandbox nativo do Claude Code, que saiu da fábrica. Dentro da VM do `sbx`, ele esconde o `GH_TOKEN` dos comandos do agente. Remeta à seção "Projetos com o sandbox nativo" do [guia](../../docs/guias/isolamento-do-agente.md#projetos-com-o-sandbox-nativo).

Os passos seguintes rodam do mesmo jeito nos dois modos. O que muda é o fim do resumo: o [checklist do modo `sbx`](#checklist-do-modo-sbx) ou o [aviso do modo sem sandbox](#aviso-do-modo-sem-sandbox).

## 2. `gh`
Rode `bash <diretório base>/../../scripts/check-gh.sh` e siga a linha que ele imprime:
- **`ok <versão>`:** siga para o passo 3.
- **`desatualizado <versão> <mínima>`, com uma versão lida:** explique que, abaixo da mínima, o `gh pr edit` falha com o erro de descontinuação dos Projects clássicos (cli/cli#11983), e mostre a versão atual e a mínima. Mostre também o comando para instalar pelo repositório oficial no Debian/Ubuntu, que atualiza o `gh` do repositório do Ubuntu:

  ```bash
  (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
  	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
  	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
  	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  	&& sudo apt update \
  	&& sudo apt install gh -y
  ```

  Para as outras plataformas, indique https://github.com/cli/cli#installation. Não rode esse comando nem `sudo`: quem atualiza é o usuário. Depois, siga para o passo 3, porque as labels e os hooks funcionam com o `gh` antigo.
- **`desatualizado desconhecida <mínima>`:** o script não conseguiu ler a versão. Pare o setup, mostre a primeira linha de `gh --version` e diga para reinstalar o `gh` pelo repositório oficial, com o comando acima ou pelas instruções de https://github.com/cli/cli#installation.
- **`sem-login <versão>`:** pare o setup e diga para rodar `gh auth login` e repetir o `/fabrica:setup`.
- **`ausente`:** pare o setup e indique a instalação em https://github.com/cli/cli#installation.

## 3. Labels
- Rode o script do plugin a partir do diretório base desta skill: `bash <diretório base>/../../scripts/setup-labels.sh $ARGUMENTS`.
- O script é idempotente: cria as labels que faltam, corrige cor e descrição das que divergem da tabela em [estados.md](../status/estados.md) e não toca em outras labels.
- Se falhar, anote o erro e siga para o passo 4: os hooks do git não dependem do repositório.

## 4. Hooks do git
- Confira com `bash <diretório base>/../../scripts/setup-githooks.sh --check`:
  - `ok` ou `atualizado <versão>`: já estão instalados. Não pergunte nada.
  - `ausente`: explique ao usuário que o script copia os hooks para `~/.config/fabrica/githooks/` e define o `core.hooksPath` no `~/.gitconfig`, o que passa a recusar commit e push na `main`/`master` em todos os repositórios da máquina, inclusive os feitos à mão (no terminal, `--no-verify` passa por cima). Os hooks de cada repositório (`.git/hooks`) continuam rodando, encadeados. Peça confirmação com o AskUserQuestion antes de instalar.
- Com a confirmação, rode `bash <diretório base>/../../scripts/setup-githooks.sh`.
- Se o script disser que já existe outro `core.hooksPath` global, mostre o valor e pergunte, com o AskUserQuestion, se o usuário quer trocar. Só com um sim rode de novo com `--force`.

## 5. Statusline
- Confira com `bash <diretório base>/../../scripts/setup-statusline.sh --check`:
  - `ok` ou `atualizado <versão>`: já está instalada. Não pergunte nada.
  - `ausente`: explique que a statusline mostra no rodapé do Claude Code o repositório, a branch com o número da issue, o PR, quantas issues esperam o usuário (contagem aproximada pelas labels; o quadro exato é o `/fabrica:status`), o backlog, o contexto usado e os limites de 5 h e de 7 dias da assinatura. Diga que o script grava `statusLine` no `~/.claude/settings.json` e copia o script para `~/.config/fabrica/statusline.sh`. Pergunte com o AskUserQuestion se o usuário quer instalar.
  - `outra <comando>`: já existe uma statusline de outra origem. Mostre o comando e pergunte, com o AskUserQuestion, se o usuário quer trocar pela da fábrica.
- Com a confirmação, rode `bash <diretório base>/../../scripts/setup-statusline.sh` (com `--force` se a resposta foi trocar a de outra origem). O script guarda o settings anterior em `~/.claude/settings.json.bak-fabrica`.
- Se o script falhar porque falta o `jq`, diga para instalá-lo e siga: a statusline é opcional.

## 6. Dispatcher
O dispatcher roda as etapas de agente no GitHub Actions a cada gesto do usuário na issue ou no PR ([guia](../../docs/guias/dispatcher.md)). O workflow é por projeto: este passo roda só dentro de um repositório git. Fora dele, pule o passo e registre no resumo "dispatcher: por projeto, não instalado fora de um repositório git".

Rode `bash <diretório base>/../../scripts/setup-dispatcher.sh --check` e siga a linha impressa:

| Saída do `--check` | O que fazer |
|---|---|
| `ausente` | Explique o dispatcher: a cada gesto na issue ou no PR, um workflow do GitHub Actions roda as etapas de agente até o próximo portão, gastando a assinatura do Claude do usuário e minutos de Actions, e precisa de três secrets, cadastrados pelo usuário. Pergunte com o AskUserQuestion se instala, com "Não instalar" como primeira opção. Com um sim, rode `bash <diretório base>/../../scripts/setup-dispatcher.sh --apply` (estado `instalado agora`). Com um não, não grave nada (estado `não instalado, a pedido do usuário`). |
| `ok` | Não pergunte nada (estado `já estava instalado`). |
| `desatualizado` | Mostre o resumo da diferença que o script imprime em stderr (`diferença: +<n> -<m> linhas`: as linhas que a troca traz do modelo e as que ela tira do arquivo atual) e avise que uma edição local do workflow também aparece como diferença e se perde na troca. Pergunte com o AskUserQuestion se substitui, com "Manter o atual" como primeira opção. Com um sim, rode `bash <diretório base>/../../scripts/setup-dispatcher.sh --apply` (estado `instalado agora`). Com um não, não grave nada (estado `desatualizado, mantido a pedido do usuário`). |
| Saída 1 | Leve a mensagem de erro para o resumo e siga. |

- **Arquivo gravado agora:** o `--apply` grava `.github/workflows/agente.yml` na cópia de trabalho. Diga ao usuário para levar o arquivo por uma branch e um PR, porque o GitHub só roda o workflow a partir da branch padrão. Não faça o commit nem abra o PR você.

### Checklist dos secrets
Monte este checklist quando o workflow ficou instalado: `instalado agora`, `já estava instalado` ou `desatualizado, mantido a pedido do usuário`. Com `não instalado`, não mostre checklist.

- O repositório é o do argumento ou, vazio, o do diretório atual (`gh repo view --json nameWithOwner,defaultBranchRef`). Rode `gh secret list --repo <dono>/<repo> --json name`: ele devolve só os nomes. Cada item de secret aparece como feito quando o nome está na lista e como pendente quando não está. Se o `gh secret list` falhar (sem permissão, sem remoto), mostre os três como pendentes, com a mensagem de erro.
- O item 4 é feito quando o `--check` deu `ok` e o arquivo da branch padrão é igual ao da cópia de trabalho: depois de `git fetch origin <branch padrão>`, `git show origin/<branch padrão>:.github/workflows/agente.yml | cmp -s - .github/workflows/agente.yml` sai com 0. Senão, pendente.

1. `CLAUDE_CODE_OAUTH_TOKEN`: gerar com `claude setup-token` e cadastrar com `gh secret set` a partir de uma variável do terminal, sem colar o valor no chat.
2. `FABRICA_PLUGIN_TOKEN`: token fine-grained só para `ftenorio99/fabrica`, só `Contents: read`.
3. `FABRICA_GH_TOKEN`: token fine-grained só para o repositório do projeto, com as permissões e a expiração do guia, sem `Workflows`.
4. Levar `.github/workflows/agente.yml` à branch padrão por um PR.

Feche o checklist remetendo à seção [Como ligar num repositório](../../docs/guias/dispatcher.md#como-ligar-num-repositório) do guia, que tem o detalhe de cada item; não copie as permissões dos tokens para o resumo. Se o projeto precisa de hosts além da API da Anthropic e do GitHub (o registro de pacotes do `implementar`, por exemplo), lembre do `.fabrica/dominios.txt`, descrito na seção [Hosts do projeto](../../docs/guias/dispatcher.md#hosts-do-projeto) do guia.

## 7. CI do PR
A [ADR 0011](../../docs/adr/0011-verificacao-de-integracao-na-etapa.md) exige em todo projeto um CI em `pull_request`, que repete a verificação da etapa; o modelo da fábrica roda `make lint`, `make test` e `make e2e` num job descartável ([guia](../../docs/guias/ci-do-pr.md), [ADR 0019](../../docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md)). O CI é por projeto: este passo roda só dentro de um repositório git. Fora dele, pule o passo e registre no resumo "CI do PR: por projeto, não conferido fora de um repositório git".

Rode `bash <diretório base>/../../scripts/setup-ci.sh --check` e siga a linha impressa:

| Saída do `--check` | O que fazer |
|---|---|
| `ausente` | Nenhum workflow de `.github/workflows/` dispara em `pull_request` (o `agente.yml` do dispatcher não conta). Explique que a ADR 0011 exige um CI em `pull_request` e o que o modelo roda: `make lint` e `make test` num job e, em paralelo, `make e2e` (Playwright), que sobe sozinho o banco e o app, com os valores de teste do `.env.example` e sem secrets. Pergunte com o AskUserQuestion se instala, com "Não instalar" como primeira opção. Com um sim, rode `bash <diretório base>/../../scripts/setup-ci.sh --apply` (estado `instalado agora`). Com um não, não grave nada (estado `ausente, não instalado a pedido do usuário`). |
| `sem-e2e` | Há CI em `pull_request`, o `Makefile` tem o alvo `e2e:` e nenhum workflow roda `make e2e`. Não grave nada. Avise que o CI não roda o Playwright e remeta à seção [Projeto que já tem CI](../../docs/guias/ci-do-pr.md#projeto-que-já-tem-ci) do guia (estado `existe, sem make e2e`). |
| `ok` | Não pergunte nada (estado `já existe`). |
| Saída 1 | Leve a mensagem de erro para o resumo e siga. |

- **Arquivo gravado agora:** o `--apply` grava `.github/workflows/ci.yml` na cópia de trabalho. Diga ao usuário para levar o arquivo por uma branch e um PR, e que o `.env.example` precisa ter valores locais que bastem para o `make test` e o `make e2e`. Não faça o commit nem abra o PR você.
- **A cópia é do projeto:** diferente do `agente.yml`, o setup não compara o `ci.yml` com o modelo nem oferece atualização.

## Checklist do modo `sbx`
No modo `sbx`, termine o resumo com este checklist. A VM, a política de rede e o secret são do usuário, no host: não rode nenhum comando `sbx`, nem para conferir se ele está instalado.

Antes de montar o checklist, rode `bash <diretório base>/../../scripts/sbx-context.sh`. Ele imprime quatro linhas, sem rodar `sbx` e sem gravar nada:
- `onde vm` ou `onde host`: se o setup roda dentro da VM do `sbx` ou na máquina;
- `nome <vm>`: o nome padrão do `sbx` para a pasta do projeto, `claude-<pasta>`. Troque `<vm>` por ele em todo comando abaixo;
- `token marcador`, `token ausente` ou `token real`: o formato do `GH_TOKEN`;
- `e2e sim` ou `e2e não`: se o `Makefile` do projeto tem o alvo `e2e:` (Playwright).

Se o script sair com código diferente de 0, mostre o erro, use `onde host`, `claude-<pasta do repositório>` como `<vm>` e mostre a linha do Playwright como condicional ("projeto com `make e2e`").

Monte os itens conforme a linha `onde`. Item feito aparece marcado como feito, com o motivo: não o tire do checklist.

| Item | `onde host` | `onde vm` |
|---|---|---|
| 1 | Pendente (texto abaixo) | Feito: o setup roda dentro da VM. O item 6 confere |
| 2 | Pendente | Feito: o setup roda dentro da VM, que já existe. Não mande criá-la |
| 3, rede base | Pendente | Feito: o setup roda dentro da VM. O item 6 confere |
| 3, Playwright | Com `e2e sim`, pendente. Com `e2e não`, não mostre a linha | Igual ao host |
| 4 | Pendente | Com `token marcador`, feito: o `GH_TOKEN` da VM é o marcador do proxy. Com `token ausente`, pendente. Com `token real`, pendente, com o aviso de que o `GH_TOKEN` da VM tem formato de token real e deveria ser o marcador do proxy |
| 5 | Feito se o `--check` do passo 4 imprimiu `ok` ou `atualizado <versão>`, ou se os hooks foram instalados nesta execução; senão, pendente | Igual ao host |
| 6 | Pendente | Pendente, dizendo que ele também confere os itens 1 e 3, que não dá para provar de dentro da VM |

1. **No host, uma vez por máquina:** fechar a rede padrão do `sbx`, que nasce aberta. Conferir com `sbx policy ls`; se a política global liberar tudo, `sbx policy reset` e `sbx policy init deny-all`.
2. **No host:** criar a VM do projeto, na pasta dele: `sbx create --name <vm> claude .`
3. **No host:** liberar a rede só para a VM: `sbx policy allow network --sandbox <vm> github.com,api.github.com,codeload.github.com,uploads.github.com,*.githubusercontent.com,registry.npmjs.org,registry-1.docker.io,auth.docker.io,production.cloudflare.docker.com`
   - **Este projeto tem `make e2e` (Playwright):** liberar também os navegadores: `sbx policy allow network --sandbox <vm> cdn.playwright.dev,playwright.download.prss.microsoft.com`
4. **No host:** entregar o token do GitHub ao proxy, sem ele entrar na VM: `sbx secret set github --command 'gh auth token'`
5. **Dentro da VM** (`sbx run --name <vm>`): instalar o plugin com `/plugin marketplace add ftenorio99/fabrica` e `/plugin install fabrica@fabrica`, e rodar `/fabrica:setup` para instalar os hooks do git. Repetir este item depois de um `sbx rm`: sem os hooks, o push na `main` passa.
6. **No host:** conferir a rede com `sbx policy log <vm>`, e não com `curl` de dentro da VM, porque o proxy responde 200 ao CONNECT mesmo para um host bloqueado.

Feche o checklist com esta linha, nos dois casos: "`<vm>` é o nome padrão do `sbx` para esta pasta. Se a VM do projeto tem outro nome, confira na coluna SANDBOX do `sbx ls`, no host, e use esse nome nos comandos." O detalhe de cada item está no [guia](../../docs/guias/isolamento-do-agente.md#modo-sbx).

## Aviso do modo sem sandbox
No modo `sem-sandbox`, termine o resumo com este aviso, sem checklist: não há isolamento. Os comandos do agente leem o token do `gh`, as chaves SSH e os `.env` da máquina e alcançam qualquer host. Ficam só os hooks do git, que protegem a `main`, e o hook de produção, que barra o comando que cita um padrão de `.fabrica/producao.txt` ([ADR 0006](../../docs/adr/0006-producao-fora-do-alcance-do-agente.md)).

## Responder
- Isolamento: o modo (`sbx`, `sem sandbox` ou `não definido: fora de um repositório git`) e se foi gravado agora ou já estava. Se foi gravado agora, o lembrete de fazer o commit de `.fabrica/isolamento.txt` por um PR. Depois, o que a migração dos restos do sandbox nativo fez: nada a dizer quando o `--check` deu `ok`; bloco `sandbox` do projeto removido, com o lembrete do PR; restos da máquina removidos, com o caminho dos backups; restos da máquina mantidos, a pedido do usuário; ou o erro do script. Com o aviso do sandbox nativo, o que ele significa, o erro da migração e o link do guia.
- `gh`: a linha do `check-gh.sh` (`ok 2.103.3`, `desatualizado 2.46.0 <mínima>` etc.) e, se não for `ok`, o que fazer.
- Labels: o repositório alvo e a linha `ok <label>` de cada uma. Com erro, a mensagem do script e o que fazer (autenticar o `gh`, criar o repositório com `gh repo create`, passar `<dono>/<repo>`). Não tente criar as labels por outro caminho.
- Hooks do git: o estado final (`instalados`, `já estavam instalados` ou `não instalados, a pedido do usuário`).
- Statusline: o estado final (`instalada`, `já estava instalada`, `não instalada, a pedido do usuário` ou o erro do script). Lembre que ela aparece na próxima sessão.
- Dispatcher: o estado final (`instalado agora`, `já estava instalado`, `desatualizado, mantido a pedido do usuário`, `não instalado, a pedido do usuário`, `não instalado fora de um repositório git` ou o erro do script). Com `instalado agora`, o lembrete de levar o workflow por um PR. Com o workflow instalado, o checklist dos secrets.
- CI do PR: o estado final (`instalado agora`, `já existe`, `existe, sem make e2e`, `ausente, não instalado a pedido do usuário`, `não conferido fora de um repositório git` ou o erro do script). Com `instalado agora`, o lembrete de levar o `ci.yml` por um PR e de conferir o `.env.example`. Com `existe, sem make e2e`, o link do guia.
- Por último, no modo `sbx`, o checklist; no modo `sem-sandbox`, o aviso.

## Regras
- Não aplique nem remova labels em issues; o setup só garante que as labels existam no repositório.
- Não instale nem atualize o `gh`, e não rode `sudo`.
- Não instale os hooks do git sem a confirmação do usuário, e não edite o `~/.gitconfig` por outro caminho.
- Não instale nem troque a statusline sem a confirmação do usuário, e não edite o `statusLine` do settings por outro caminho.
- Não rode comandos `sbx`, não crie a VM, não mexa na política de rede e não grave o secret: o checklist é do usuário.
- Não grave o modo de isolamento sem a resposta do usuário, não troque um modo já gravado e não edite `.fabrica/isolamento.txt` por outro caminho.
- Não remova os restos do sandbox nativo da máquina sem a confirmação do usuário, e não edite o `~/.claude/settings.json` nem o `~/.gitconfig` por outro caminho.
- Não grave nem substitua o workflow do dispatcher sem a confirmação do usuário, e não edite `.github/workflows/agente.yml` por outro caminho.
- Não faça o commit do workflow nem abra o PR dele: quem leva o arquivo à branch padrão é o usuário.
- Não grave o `ci.yml` sem a confirmação do usuário, não o sobrescreva e não edite nenhum workflow de CI do projeto por outro caminho.
- Não faça o commit do `ci.yml` nem abra o PR dele.
- Não rode `gh secret set`, não leia valor de secret e não peça valor de token: o checklist dos secrets é do usuário.
