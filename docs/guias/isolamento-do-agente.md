# Isolamento do agente

Este guia é para quando você quer deixar os agentes rodando sozinhos num projeto, pelo `/fabrica:avancar`, sem que um comando deles alcance o resto da máquina. A fábrica usa o sandbox nativo do Claude Code. A decisão e as alternativas estão na [ADR 0005](../adr/0005-isolamento-do-agente-em-sandbox.md).

## O que o sandbox protege
O sandbox vale para os comandos Bash das sessões abertas no projeto e para os processos filhos deles:
- **Arquivos:** os comandos escrevem só no projeto, na pasta temporária e no cache do npm (`~/.npm`). O cache é compartilhado entre os projetos, e um agente enganado poderia gravar nele um pacote adulterado. O `npm ci` confere o hash de cada pacote pelo lockfile. O `.claude/settings.json` do projeto continua protegido, mesmo estando dentro do projeto. O estrago que um comando fizer dentro do projeto o git recupera.
- **Rede:** só os domínios liberados respondem. A base é a do GitHub (`github.com`, `api.github.com`, `codeload.github.com`, `uploads.github.com` e `*.githubusercontent.com`) e o `registry.npmjs.org`. O servidor local (`allowLocalBinding`) continua liberado, para o servidor de dev e o Playwright.
- **Segredos:**
  - `~/.ssh` e os `.env*` do projeto não podem ser lidos;
  - `GH_TOKEN` e `GITHUB_TOKEN` chegam vazias;
  - o token do `gh` em `~/.config/gh/hosts.yml` aparece como um marcador, e o proxy do sandbox põe o token real só nas requisições a `api.github.com` e `github.com`;
  - o cabeçalho do `git push` em `~/.config/fabrica/git-auth.gitconfig` também aparece como marcador, e o proxy põe o valor real só nas requisições a `github.com` (veja "Git push").
- **Sem saída:** o agente não pode repetir fora do sandbox um comando barrado (`allowUnsandboxedCommands: false`), e nenhum comando é exceção. O que precisa sair do sandbox você roda com `!` no prompt.

O sandbox não cobre o WebFetch, que segue as regras de permissão, nem o tráfego do próprio Claude Code com a API.

## Dependências
No Linux, o sandbox precisa do `bubblewrap` e do `socat`:

```bash
sudo apt-get install bubblewrap socat
```

No Ubuntu 24.04 ou mais novo, confira `sysctl kernel.apparmor_restrict_unprivileged_userns`. Se a resposta for `1`, o AppArmor impede o `bwrap` de criar os namespaces que o sandbox usa, e o sandbox não sobe. O sintoma é um erro como `apply-seccomp: write /proc/self/setgroups ... Permission denied` em todo comando. Crie o perfil do `bwrap`, que vale só para ele e não para os comandos que ele roda, e recarregue o AppArmor:

```bash
sudo tee /etc/apparmor.d/bwrap > /dev/null <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
EOF
sudo systemctl reload apparmor
```

No Ubuntu 26.04, o sistema já traz o `/etc/apparmor.d/bwrap-userns-restrict`. Ele define um perfil com o mesmo nome, `bwrap`, carregado depois do perfil acima. Esse perfil põe os processos filhos do `bwrap` num perfil `unpriv_bwrap`, que barra os namespaces aninhados de que o sandbox precisa, e o erro continua. Desligue-o e recarregue o perfil do Claude Code:

```bash
sudo ln -s /etc/apparmor.d/bwrap-userns-restrict /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/bwrap-userns-restrict
sudo apparmor_parser -r /etc/apparmor.d/bwrap
sudo aa-status | grep -i bwrap   # deve listar bwrap, sem unpriv_bwrap
```

Para desfazer, apague `/etc/apparmor.d/disable/bwrap-userns-restrict` e `/etc/apparmor.d/bwrap` e rode `sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict`.

O comando `/sandbox` do Claude Code mostra o estado e o que falta.

## Ligar num projeto
1. Rode `/fabrica:setup` no projeto e confirme o passo **Sandbox**. Ele grava a base no `.claude/settings.json` do projeto e o mascaramento do token no `~/.claude/settings.json`, porque o Claude Code só aceita o mascaramento nesse escopo.
2. Faça commit do `.claude/settings.json` do projeto numa branch e abra o PR, como qualquer mudança.
3. Abra uma sessão nova no projeto. O sandbox vale a partir dela.

Se a sessão em que você rodou o setup já estiver em sandbox, o script não consegue gravar o settings do usuário. Ele imprime uma linha começando com `!`: cole essa linha no prompt, para ela rodar fora do sandbox.

## Git push
O git manda o token em Basic auth, codificado em base64, e o proxy só troca um marcador que aparece literalmente na requisição. Com o token do `hosts.yml`, o marcador some dentro do base64, e o push falha com `Invalid username or token`.

Por isso, o cabeçalho vai pronto num arquivo próprio, `~/.config/fabrica/git-auth.gitconfig`, incluído no seu `~/.gitconfig`. No sandbox, o git lê o marcador e manda `Authorization: Basic <marcador>`, e o proxy troca o marcador pelo valor real. Fora do sandbox, o git usa o valor real, e o push continua funcionando como antes.

Gere o arquivo, fora do sandbox, na primeira vez e sempre que o token do `gh` mudar (depois de um `gh auth login` ou `gh auth refresh`):

```bash
bash <clone do fabrica>/scripts/setup-git-auth.sh
```

O script grava o arquivo com permissão `600` e acrescenta o `include.path` ao `~/.gitconfig`, se ainda não houver. Com um token velho no arquivo, o push falha também fora do sandbox: gere o arquivo de novo. Para tirar, apague o arquivo e rode `git config --global --unset include.path ~/.config/fabrica/git-auth.gitconfig`.

## Token fine-grained
O mascaramento impede o agente de ler o token e de mandá-lo a um host fora da lista. Ele não impede o vazamento pelo próprio GitHub. O proxy troca o marcador em qualquer parte da requisição a `api.github.com`, inclusive no corpo. Então um agente enganado pode postar o marcador num comentário, ou pedi-lo de volta (ex.: `POST /markdown`), e o GitHub grava ou devolve o token real. Com o cabeçalho do git, a rota parecida é um nome de branch no `git push`.

Por isso, o token do `gh` precisa ser **fine-grained**, com o menor estrago possível se vazar:
1. Em https://github.com/settings/personal-access-tokens/new, crie um token com:
   - **Expiração:** 90 dias ou menos;
   - **Repository access:** só os repositórios em que a fábrica trabalha (ex.: `fabrica` e `kairo`);
   - **Permissões de repositório:**
     - Contents, Issues, Pull requests e Workflows: leitura e escrita;
     - Actions e Commit statuses: leitura;
     - Metadata: leitura, que é obrigatória.
2. Troque o login do `gh` pelo token novo, guardando-o no arquivo. Faça o `logout` antes: o `gh` dá preferência ao token do chaveiro do sistema, e um login sem ele deixa o token antigo valendo fora do sandbox.

   ```bash
   gh auth logout --hostname github.com
   gh auth login --with-token --insecure-storage   # cole o token e tecle Ctrl-D
   gh auth status   # deve dizer "(.../hosts.yml)" e não "(keyring)"
   ```

   Depois, revogue o token antigo: em https://github.com/settings/applications, *Authorized OAuth Apps* → **GitHub CLI** → *Revoke*.
3. Gere de novo o cabeçalho do git: `bash <clone do fabrica>/scripts/setup-git-auth.sh`.
4. Repita os três passos quando o token expirar. O aceite confere a expiração (`token-com-expiracao`).

O aceite mostra a reflexão como `aviso reflexao-token-gh`: é o risco aceito na ADR 0005, e não uma falha. Um repositório novo na fábrica precisa entrar no acesso do token.

## Token no chaveiro
O `gh` pode guardar o token no chaveiro do sistema, e não no `hosts.yml`. Nesse caso, o sandbox não tem o que mascarar, e o `gh` falha dentro dele. Para saber, confira se o `~/.config/gh/hosts.yml` tem uma linha `oauth_token`. Sem ela, o token está no chaveiro.

Para o `gh` funcionar no sandbox, o token precisa ir para o `hosts.yml` (`gh auth login --insecure-storage`). Fora do sandbox, qualquer processo seu pode ler esse arquivo e o `git-auth.gitconfig`, como já pode ler o chaveiro da sessão. Dentro do sandbox, o agente vê só os marcadores.

## Ampliar os domínios
Quando uma etapa falhar com erro de rede para um host que o projeto usa (ex.: a API de um serviço de pagamento em modo de teste), acrescente o domínio no `.claude/settings.json` do projeto:

```json
{
  "sandbox": {
    "network": {
      "allowedDomains": ["api.stripe.com"]
    }
  }
}
```

As listas se somam entre o settings do usuário e o do projeto, e rodar o `/fabrica:setup` de novo mantém os domínios que você acrescentou. Libere só o host exato. Um curinga largo (como `*.github.com`) abre caminhos para tirar dados do projeto (como o `gist.github.com`).

## Rodar o teste de aceite
Numa sessão aberta no projeto, com o sandbox ligado e um `.env` de teste na raiz (ex.: `TESTE=1`), peça ao agente para rodar:

```bash
bash <clone do fabrica>/scripts/test-sandbox-acceptance.sh
```

Cada linha sai como `ok <verificação>` ou `falha <verificação>: <motivo>`:
- escrita fora do projeto e no `.claude/settings.json`;
- rede fora da lista;
- token, `~/.ssh` e `.env` em claro;
- `gh api user`, `npm view` e o `git push` de uma branch `test/sandbox-*`, apagada no fim. Use `--remote <nome>` para fazer o push em outro remote que não o `origin`.

Rode o teste de novo quando o Claude Code mudar o sandbox nas notas de versão, porque o `tlsTerminate`, que o mascaramento usa, ainda é experimental.

## Desligar
Para desligar num projeto, mude `sandbox.enabled` para `false` no `.claude/settings.json` dele, por um PR. O bloco do `~/.claude/settings.json` só age nos projetos com o sandbox ligado e pode ficar.
