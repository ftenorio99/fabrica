---
name: setup
description: Confere se o gh está instalado, autenticado e na versão mínima da fábrica, cria ou corrige as labels da fábrica (agente, precisa-info, spec-pronta, spec-aprovada, escalonado, pronto-revisao, licao, em-andamento) num repositório do GitHub, conforme a tabela de estados.md, instala na máquina os hooks do git que bloqueiam commit e push na main e, se o usuário quiser, a statusline da fábrica. Use num repositório que ainda não tem as labels, quando uma etapa avisar que uma label não existe ou que o gh está desatualizado, ou quando avisarem que os hooks do git não estão instalados.
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

## 4. Statusline
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
- Statusline: o estado final (`instalada`, `já estava instalada`, `não instalada, a pedido do usuário` ou o erro do script). Lembre que ela aparece na próxima sessão.

## Regras
- Não aplique nem remova labels em issues; o setup só garante que as labels existam no repositório.
- Não instale nem atualize o `gh`, e não rode `sudo`.
- Não instale os hooks do git sem a confirmação do usuário, e não edite o `~/.gitconfig` por outro caminho.
- Não instale nem troque a statusline sem a confirmação do usuário, e não edite o `statusLine` do settings por outro caminho.
