# Isolamento do agente

Este guia é para quando você quer deixar os agentes rodando sozinhos num projeto, pelo `/fabrica:avancar`, sem que um comando deles alcance o resto da máquina. A fábrica usa o sandbox nativo do Claude Code. A decisão e as alternativas estão na [ADR 0005](../adr/0005-isolamento-do-agente-em-sandbox.md).

## O que o sandbox protege
O sandbox vale para os comandos Bash das sessões abertas no projeto e para os processos filhos deles:
- **Arquivos:** os comandos escrevem só no projeto e na pasta temporária. O `.claude/settings.json` do projeto continua protegido, mesmo estando dentro do projeto. O estrago que um comando fizer dentro do projeto o git recupera.
- **Rede:** só os domínios liberados respondem. A base é a do GitHub (`github.com`, `api.github.com`, `codeload.github.com`, `uploads.github.com` e `*.githubusercontent.com`) e o `registry.npmjs.org`. O servidor local (`allowLocalBinding`) continua liberado, para o servidor de dev e o Playwright.
- **Segredos:**
  - `~/.ssh` e os `.env*` do projeto não podem ser lidos;
  - `GH_TOKEN` e `GITHUB_TOKEN` chegam vazias;
  - o token do `gh` em `~/.config/gh/hosts.yml` aparece como um marcador, e o proxy do sandbox põe o token real só nas requisições a `api.github.com` e `github.com`.
- **Sem saída:** o agente não pode repetir fora do sandbox um comando barrado (`allowUnsandboxedCommands: false`). O que precisa sair dele você roda com `!` no prompt.

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

O comando `/sandbox` do Claude Code mostra o estado e o que falta.

## Ligar num projeto
1. Rode `/fabrica:setup` no projeto e confirme o passo **Sandbox**. Ele grava a base no `.claude/settings.json` do projeto e o mascaramento do token no `~/.claude/settings.json`, porque o Claude Code só aceita o mascaramento nesse escopo.
2. Faça commit do `.claude/settings.json` do projeto numa branch e abra o PR, como qualquer mudança.
3. Abra uma sessão nova no projeto. O sandbox vale a partir dela.

Se a sessão em que você rodou o setup já estiver em sandbox, o script não consegue gravar o settings do usuário. Ele imprime uma linha começando com `!`: cole essa linha no prompt, para ela rodar fora do sandbox.

## Token no chaveiro
O `gh` pode guardar o token no chaveiro do sistema, e não no `hosts.yml`. Nesse caso, o sandbox não tem o que mascarar, e o `gh` falha dentro dele. Para saber, confira se o `~/.config/gh/hosts.yml` tem uma linha `oauth_token`. Sem ela, o token está no chaveiro.

Para o `gh` funcionar no sandbox, o token precisa ir para o `hosts.yml` (`gh auth login --insecure-storage`). Fora do sandbox, qualquer processo seu pode ler esse arquivo, como já pode ler o chaveiro da sessão. Dentro do sandbox, o agente vê só o marcador.

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
- `gh api user`, `git push` (de uma branch `test/sandbox-*`, apagada no fim) e `npm view`.

Rode o teste de novo quando o Claude Code mudar o sandbox nas notas de versão, porque o `tlsTerminate`, que o mascaramento usa, ainda é experimental.

## Desligar
Para desligar num projeto, mude `sandbox.enabled` para `false` no `.claude/settings.json` dele, por um PR. O bloco do `~/.claude/settings.json` só age nos projetos com o sandbox ligado e pode ficar.
