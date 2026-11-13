---
name: setup
description: Define o modo de isolamento do projeto (VM do Docker Sandboxes, o sbx, ou sem sandbox) e grava a escolha em .fabrica/isolamento.txt, confere se o gh está instalado, autenticado e na versão mínima da fábrica, cria ou corrige as labels da fábrica (agente, precisa-info, spec-pronta, spec-aprovada, escalonado, pronto-revisao, licao, em-andamento) num repositório do GitHub, conforme a tabela de estados.md, instala na máquina os hooks do git que bloqueiam commit e push na main e, se o usuário quiser, instala a statusline da fábrica. No modo sbx, termina com o checklist da VM. Use num repositório que ainda não tem as labels, quando uma etapa avisar que uma label não existe ou que o gh está desatualizado, quando avisarem que os hooks do git não estão instalados, dentro de uma VM nova do sbx ou para escolher como isolar os agentes num projeto.
argument-hint: "[<dono>/<repo>]"
disable-model-invocation: true
---

# Setup da fábrica

Repositório: $ARGUMENTS (vazio = o repositório do diretório atual)

## 1. Modo de isolamento
Cada projeto roda os agentes num de dois modos, gravado em `.fabrica/isolamento.txt` ([ADR 0010](../../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)):
- **`sbx`:** o agente roda numa VM do Docker Sandboxes, com a rede liberada só para os hosts de uma política da VM e sem o token do GitHub dentro dela.
- **`sem-sandbox`:** o agente roda direto na máquina, sem isolamento, por decisão explícita do usuário.

O modo é sempre o do projeto do diretório atual, mesmo com um `<dono>/<repo>` no argumento, que vale só para as labels.

Rode `git rev-parse --show-toplevel`. Depois, conforme a situação:

| Situação | O que fazer |
|---|---|
| O `git rev-parse` falha: fora de um repositório git | Pule este passo. No resumo, diga que o modo de isolamento é por projeto e não foi definido. |
| `bash <diretório base>/../../scripts/setup-isolation.sh --check` imprime `sbx` ou `sem-sandbox` | Não pergunte nada. Mostre o modo e diga que, para trocar, o usuário edita `.fabrica/isolamento.txt` por um PR. |
| O `--check` imprime `ausente` ou `inválido` | Em `inválido`, mostre antes o conteúdo do arquivo. Explique os dois modos e pergunte com o AskUserQuestion qual usar, com `sbx (Recomendado)` como primeira opção e "sem sandbox" como segunda. Grave a resposta com `bash <diretório base>/../../scripts/setup-isolation.sh --set <sbx\|sem-sandbox>`. |
| O script imprime em stderr `sandbox nativo ligado em .claude/settings.json` | Leve o aviso para o resumo, como abaixo. |

- **Arquivo gravado agora:** o script grava na cópia de trabalho. Diga ao usuário para fazer o commit de `.fabrica/isolamento.txt` numa branch e abrir o PR. Não faça o commit você.
- **Aviso do sandbox nativo:** o bloco `sandbox` do `.claude/settings.json` é do sandbox nativo do Claude Code, que saiu da fábrica. Dentro da VM do `sbx`, ele esconde o `GH_TOKEN` dos comandos do agente. Remeta à seção "Projetos com o sandbox nativo" do [guia](../../docs/guias/isolamento-do-agente.md#projetos-com-o-sandbox-nativo). Não remova o bloco: mudar as permissões do projeto é gesto do usuário.

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

## Checklist do modo `sbx`
No modo `sbx`, termine o resumo com este checklist, trocando `<projeto>` pelo nome da pasta do repositório. A VM, a política de rede e o secret são do usuário, no host: não rode nenhum comando `sbx`, nem para conferir se ele está instalado.

1. **No host, uma vez por máquina:** fechar a rede padrão do `sbx`, que nasce aberta. Conferir com `sbx policy ls`; se a política global liberar tudo, `sbx policy reset` e `sbx policy init deny-all`.
2. **No host:** criar a VM do projeto, na pasta dele: `sbx create --name <projeto> claude .`
3. **No host:** liberar a rede só para a VM: `sbx policy allow network --sandbox <projeto> github.com,api.github.com,codeload.github.com,uploads.github.com,*.githubusercontent.com,registry.npmjs.org,registry-1.docker.io,auth.docker.io,production.cloudflare.docker.com`
4. **No host:** entregar o token do GitHub ao proxy, sem ele entrar na VM: `sbx secret set github --command 'gh auth token'`
5. **Dentro da VM** (`sbx run --name <projeto>`): instalar o plugin com `/plugin marketplace add ftenorio99/fabrica` e `/plugin install fabrica@fabrica`, e rodar `/fabrica:setup` para instalar os hooks do git. Repetir este item depois de um `sbx rm`: sem os hooks, o push na `main` passa.
6. **No host:** conferir a rede com `sbx policy log <projeto>`, e não com `curl` de dentro da VM, porque o proxy responde 200 ao CONNECT mesmo para um host bloqueado.

Se o `--check` do passo 4 imprimiu `ok` ou `atualizado <versão>`, ou se os hooks foram instalados nesta execução, marque o item 5 como feito nesta máquina ou VM. O detalhe de cada item está no [guia](../../docs/guias/isolamento-do-agente.md#modo-sbx).

## Aviso do modo sem sandbox
No modo `sem-sandbox`, termine o resumo com este aviso, sem checklist: não há isolamento. Os comandos do agente leem o token do `gh`, as chaves SSH e os `.env` da máquina e alcançam qualquer host. Ficam só os hooks do git, que protegem a `main`, e o hook de produção, que barra o comando que cita um padrão de `.fabrica/producao.txt` ([ADR 0006](../../docs/adr/0006-producao-fora-do-alcance-do-agente.md)).

## Responder
- Isolamento: o modo (`sbx`, `sem sandbox` ou `não definido: fora de um repositório git`) e se foi gravado agora ou já estava. Se foi gravado agora, o lembrete de fazer o commit de `.fabrica/isolamento.txt` por um PR. Com o aviso do sandbox nativo, o que ele significa e o link do guia.
- `gh`: a linha do `check-gh.sh` (`ok 2.103.3`, `desatualizado 2.46.0 <mínima>` etc.) e, se não for `ok`, o que fazer.
- Labels: o repositório alvo e a linha `ok <label>` de cada uma. Com erro, a mensagem do script e o que fazer (autenticar o `gh`, criar o repositório com `gh repo create`, passar `<dono>/<repo>`). Não tente criar as labels por outro caminho.
- Hooks do git: o estado final (`instalados`, `já estavam instalados` ou `não instalados, a pedido do usuário`).
- Statusline: o estado final (`instalada`, `já estava instalada`, `não instalada, a pedido do usuário` ou o erro do script). Lembre que ela aparece na próxima sessão.
- Por último, no modo `sbx`, o checklist; no modo `sem-sandbox`, o aviso.

## Regras
- Não aplique nem remova labels em issues; o setup só garante que as labels existam no repositório.
- Não instale nem atualize o `gh`, e não rode `sudo`.
- Não instale os hooks do git sem a confirmação do usuário, e não edite o `~/.gitconfig` por outro caminho.
- Não instale nem troque a statusline sem a confirmação do usuário, e não edite o `statusLine` do settings por outro caminho.
- Não rode comandos `sbx`, não crie a VM, não mexa na política de rede e não grave o secret: o checklist é do usuário.
- Não grave o modo de isolamento sem a resposta do usuário, não troque um modo já gravado e não edite `.fabrica/isolamento.txt` por outro caminho.
- Não altere o bloco `sandbox` do `.claude/settings.json` do projeto.
