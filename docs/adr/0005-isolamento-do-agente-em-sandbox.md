# ADR 0005: Isolamento do agente local pelo sandbox nativo do Claude Code

**Status:** aceito · **Data:** 2026-11-09 · **Origem:** issue #93

## Contexto
A F1 do PRD pede que o agente rode em sandbox, com o sistema de arquivos e a rede restritos e sem ler segredos em claro, antes de o fluxo andar sozinho (F4). Na máquina do usuário, as etapas leem o token do `gh` em `~/.config/gh/hosts.yml`, as chaves em `~/.ssh` e os `.env`, e alcançam qualquer host. Os hooks do git da ADR 0002 protegem só a `main`.

O Claude Code tem um sandbox nativo para os comandos Bash, com lista de domínios, restrição de escrita e proteção de credenciais (`deny` e `mask`). Pela documentação, o `mask` e o `tlsTerminate`, que ele exige, só são aceitos no settings do usuário, no gerenciado ou no `--settings`, e nunca no de um repositório.

## Decisão
O `/fabrica:setup` liga o sandbox nativo por projeto e grava as configurações em dois lugares:
- **`.claude/settings.json` do projeto:**
  - `enabled` e `allowUnsandboxedCommands: false`;
  - a escrita no cache do npm (`~/.npm`);
  - os domínios de base;
  - `deny` em `~/.ssh`, nos `.env*` e em `GH_TOKEN` e `GITHUB_TOKEN`.
- **`~/.claude/settings.json` do usuário:** o `tlsTerminate` e dois `mask`:
  - o do token do `gh`, posto pelo proxy só em `api.github.com` e `github.com`;
  - o do cabeçalho `Authorization: Basic` do git, posto só em `github.com`.

O proxy só troca um marcador que aparece literalmente na requisição. Por isso, o git não usa o token do `hosts.yml`, que ele codificaria em base64, e sim um cabeçalho já codificado. Esse cabeçalho fica em `~/.config/fabrica/git-auth.gitconfig`, incluído no `~/.gitconfig` e gerado pelo `scripts/setup-git-auth.sh`, que o usuário roda fora do sandbox. Assim, o `git push` roda dentro do sandbox, sem exceção.

O que precisa sair do sandbox o usuário roda com `!` no prompt.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Docker Sandboxes ou microVM por etapa | Isola mais, mas exige outra execução das skills e do `gh`. Fica para o runner da Fase 1 (#106), se o nativo não bastar. |
| `gh` em `excludedCommands` | O `gh` sai do sandbox, e `gh auth token` devolve o token em claro. |
| Token fine-grained em claro no sandbox | O agente ainda lê o token, o que contraria a F1. |
| Tudo no settings do usuário | Liga o sandbox em todas as sessões da máquina, inclusive fora dos projetos da fábrica. |
| `git push` em `excludedCommands` | O `git push` executa comandos locais (`--receive-pack`), e fora do sandbox eles leriam os segredos. Testado e descartado na implementação. |
| Cabeçalho do git por variável de ambiente no `env` do settings | O `protect-main.sh` barra as variáveis de configuração do git, porque elas podem desligar os hooks do git. |
| `git push` pelo usuário, com `!` | Seguro, mas o `/fabrica:avancar` deixa de andar sozinho: spec, implementação e revisão fazem push. |
| `git push` só no dispatcher | Deixa o fluxo local sem push no sandbox até o runner (#106). |
| `claude --settings` só no `/fabrica:avancar` | Depende de lembrar da flag e deixa sem proteção a sessão interativa no mesmo projeto. |

## Consequências
- **Comandos Bash nos projetos instalados:**
  - não escrevem fora do projeto e da pasta temporária;
  - alcançam só os domínios da lista;
  - veem um marcador no lugar do token do `gh`.
- **Domínio novo:** o repositório amplia a lista no próprio `.claude/settings.json`, e as listas se somam entre os escopos.
- **Mudanças fora do projeto** (settings do usuário, hooks do git, statusline): o usuário as roda com `!` no prompt, porque o agente não sai do sandbox.
- **Token no chaveiro do sistema:** o `gh` não funciona no sandbox enquanto o token estiver lá. O guia mostra como guardá-lo no `hosts.yml`.
- **Dependências:** o `bubblewrap` e o `socat` passam a ser dependências da fábrica no Linux, e o `tlsTerminate`, experimental, passa a ser uma dependência do fluxo. O aceite (`scripts/test-sandbox-acceptance.sh`) roda de novo quando o Claude Code muda o sandbox.
- **WebFetch:** continua fora do sandbox e é controlado só pelas regras de permissão.
- **Risco residual aceito (decisão do usuário, 2026-11-10):** o proxy troca o marcador em toda a requisição aos hosts do `injectHosts`, inclusive no corpo, e a documentação não oferece troca só nos cabeçalhos. Um agente enganado pode, então, obter o token pelo próprio GitHub, postando o marcador ou pedindo-o de volta (`POST /markdown`). O aceite comprovou isso. A mitigação é o token do `gh` ser fine-grained, restrito aos repositórios da fábrica e com expiração, para que um vazamento atinja só esses repositórios. O isolamento sem esse risco fica para o runner da Fase 1 (#106), onde a credencial pode ficar fora da máquina do agente.
- **Token do `gh` novo:** o usuário precisa gerar de novo o `git-auth.gitconfig`. Enquanto o arquivo tiver o valor velho, o push falha, dentro e fora do sandbox.
- **Cache do npm:** o `~/.npm` fica gravável e é compartilhado entre os projetos. O `npm ci` confere o hash dos pacotes pelo lockfile.
