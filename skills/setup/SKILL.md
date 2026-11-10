---
name: setup
description: Confere se o gh está instalado, autenticado e na versão mínima da fábrica, cria ou corrige as labels da fábrica (agente, precisa-info, spec-pronta, spec-aprovada, escalonado, pronto-revisao, licao, em-andamento) num repositório do GitHub, conforme a tabela de estados.md, instala na máquina os hooks do git que bloqueiam commit e push na main e, se o usuário quiser, liga o sandbox nativo do Claude Code no projeto e instala a statusline da fábrica. Use num repositório que ainda não tem as labels, quando uma etapa avisar que uma label não existe ou que o gh está desatualizado, quando avisarem que os hooks do git não estão instalados ou para isolar os agentes em sandbox num projeto.
argument-hint: "[<dono>/<repo>]"
disable-model-invocation: true
---

# Setup da fábrica

Repositório: $ARGUMENTS (vazio = o repositório do diretório atual)

## 1. `gh`
Rode `bash <diretório base>/../../scripts/check-gh.sh` e siga a linha que ele imprime:
- **`ok <versão>`:** siga para o passo 2.
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

  Para as outras plataformas, indique https://github.com/cli/cli#installation. Não rode esse comando nem `sudo`: quem atualiza é o usuário. Depois, siga para o passo 2, porque as labels e os hooks funcionam com o `gh` antigo.
- **`desatualizado desconhecida <mínima>`:** o script não conseguiu ler a versão. Pare o setup, mostre a primeira linha de `gh --version` e diga para reinstalar o `gh` pelo repositório oficial, com o comando acima ou pelas instruções de https://github.com/cli/cli#installation.
- **`sem-login <versão>`:** pare o setup e diga para rodar `gh auth login` e repetir o `/fabrica:setup`.
- **`ausente`:** pare o setup e indique a instalação em https://github.com/cli/cli#installation.

## 2. Labels
- Rode o script do plugin a partir do diretório base desta skill: `bash <diretório base>/../../scripts/setup-labels.sh $ARGUMENTS`.
- O script é idempotente: cria as labels que faltam, corrige cor e descrição das que divergem da tabela em [estados.md](../status/estados.md) e não toca em outras labels.
- Se falhar, anote o erro e siga para o passo 3: os hooks do git não dependem do repositório.

## 3. Hooks do git
- Confira com `bash <diretório base>/../../scripts/setup-githooks.sh --check`:
  - `ok` ou `atualizado <versão>`: já estão instalados. Não pergunte nada.
  - `ausente`: explique ao usuário que o script copia os hooks para `~/.config/fabrica/githooks/` e define o `core.hooksPath` no `~/.gitconfig`, o que passa a recusar commit e push na `main`/`master` em todos os repositórios da máquina, inclusive os feitos à mão (no terminal, `--no-verify` passa por cima). Os hooks de cada repositório (`.git/hooks`) continuam rodando, encadeados. Peça confirmação com o AskUserQuestion antes de instalar.
- Com a confirmação, rode `bash <diretório base>/../../scripts/setup-githooks.sh`.
- Se o script disser que já existe outro `core.hooksPath` global, mostre o valor e pergunte, com o AskUserQuestion, se o usuário quer trocar. Só com um sim rode de novo com `--force`.

## 4. Sandbox
O sandbox nativo do Claude Code isola os comandos Bash das sessões no projeto ([ADR 0005](../../docs/adr/0005-isolamento-do-agente-em-sandbox.md)): eles não escrevem fora do projeto, só alcançam os domínios liberados e não leem em claro o token do `gh`, as chaves SSH nem os `.env`.
- **Dependências (Linux):**
  - **`bwrap` e `socat`:** confira com `command -v bwrap socat`. Se faltar algum, mostre `sudo apt-get install bubblewrap socat` (ou `sudo dnf install bubblewrap socat`).
  - **AppArmor:** se `sysctl -n kernel.apparmor_restrict_unprivileged_userns` imprimir `1` (Ubuntu 24.04 ou mais novo), o sandbox não sobe sem um perfil AppArmor que libere o `bwrap`. A dependência falta quando `/etc/apparmor.d/bwrap` não existe ou quando `/etc/apparmor.d/bwrap-userns-restrict` existe sem um link em `/etc/apparmor.d/disable/`. O perfil do Ubuntu tem o mesmo nome e vale no lugar do perfil do Claude Code. Nesses casos, mostre os comandos da seção "Dependências" do [guia](../../docs/guias/isolamento-do-agente.md#dependências).

  Não rode `sudo`. Com alguma dependência faltando, não instale o sandbox, relate `faltam dependências: <lista>` e siga para o passo 5.
- **Estado:** confira com `bash <diretório base>/../../scripts/setup-sandbox.sh --check`:
  - `ok`: já está instalado. Não pergunte nada.
  - `ausente` ou `incompleto <itens>`: explique o que muda.
    - **`.claude/settings.json` do projeto:**
      - liga o sandbox, sem saída para fora dele (`allowUnsandboxedCommands: false`), exceto o `git push`;
      - libera a escrita no cache do npm (`~/.npm`);
      - libera os domínios do GitHub e do npm;
      - nega `~/.ssh`, os `.env*`, `GH_TOKEN` e `GITHUB_TOKEN`.
    - **`~/.claude/settings.json`:** liga o `tlsTerminate` e mascara o token do `hosts.yml`, que o proxy põe só nas requisições ao GitHub. O settings anterior fica em `~/.claude/settings.json.bak-fabrica`.

    Diga que a mudança vale na próxima sessão aberta no projeto e que o que precisar sair do sandbox o usuário roda com `!` no prompt. Pergunte com o AskUserQuestion se ele quer instalar.
- Com a confirmação, rode `bash <diretório base>/../../scripts/setup-sandbox.sh`. Se ele sair com código 2, a sessão já roda em sandbox: mostre a linha com `!` que o script imprimiu, para o usuário rodar no prompt.
- **Token no chaveiro:** se `~/.config/gh/hosts.yml` não tiver `oauth_token`, o token do `gh` está no chaveiro do sistema, e o `gh` não vai funcionar no sandbox. Avise e remeta à seção "Token no chaveiro" do [guia](../../docs/guias/isolamento-do-agente.md#token-no-chaveiro).

## 5. Statusline
- Confira com `bash <diretório base>/../../scripts/setup-statusline.sh --check`:
  - `ok` ou `atualizado <versão>`: já está instalada. Não pergunte nada.
  - `ausente`: explique que a statusline mostra no rodapé do Claude Code o repositório, a branch com o número da issue, o PR, quantas issues esperam o usuário (contagem aproximada pelas labels; o quadro exato é o `/fabrica:status`), o backlog, o contexto usado e os limites de 5 h e de 7 dias da assinatura. Diga que o script grava `statusLine` no `~/.claude/settings.json` e copia o script para `~/.config/fabrica/statusline.sh`. Pergunte com o AskUserQuestion se o usuário quer instalar.
  - `outra <comando>`: já existe uma statusline de outra origem. Mostre o comando e pergunte, com o AskUserQuestion, se o usuário quer trocar pela da fábrica.
- Com a confirmação, rode `bash <diretório base>/../../scripts/setup-statusline.sh` (com `--force` se a resposta foi trocar a de outra origem). O script guarda o settings anterior em `~/.claude/settings.json.bak-fabrica`.
- Se o script falhar porque falta o `jq`, diga para instalá-lo e siga: a statusline é opcional.

## Responder
- `gh`: a linha do `check-gh.sh` (`ok 2.103.3`, `desatualizado 2.46.0 <mínima>` etc.) e, se não for `ok`, o que fazer.
- Labels: o repositório alvo e a linha `ok <label>` de cada uma. Com erro, a mensagem do script e o que fazer (autenticar o `gh`, criar o repositório com `gh repo create`, passar `<dono>/<repo>`). Não tente criar as labels por outro caminho.
- Hooks do git: o estado final (`instalados`, `já estavam instalados` ou `não instalados, a pedido do usuário`).
- Sandbox: o estado final (`instalado`, `já estava instalado`, `não instalado, a pedido do usuário`, `faltam dependências: <lista>` ou a linha com `!` para o usuário rodar) e o aviso do token no chaveiro, se houver. Lembre que ele vale na próxima sessão aberta no projeto.
- Statusline: o estado final (`instalada`, `já estava instalada`, `não instalada, a pedido do usuário` ou o erro do script). Lembre que ela aparece na próxima sessão.

## Regras
- Não aplique nem remova labels em issues; o setup só garante que as labels existam no repositório.
- Não instale nem atualize o `gh`, e não rode `sudo`.
- Não instale os hooks do git sem a confirmação do usuário, e não edite o `~/.gitconfig` por outro caminho.
- Não instale o sandbox sem a confirmação do usuário, e não edite o bloco `sandbox` dos settings por outro caminho.
- Não instale nem troque a statusline sem a confirmação do usuário, e não edite o `statusLine` do settings por outro caminho.
