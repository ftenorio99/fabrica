# ADR 0005: Isolamento do agente local pelo sandbox nativo do Claude Code

**Status:** proposto · **Data:** 2026-11-09 · **Origem:** issue #93

## Contexto
A F1 do PRD pede que o agente rode em sandbox, com o sistema de arquivos e a rede restritos e sem ler segredos em claro, antes de o fluxo andar sozinho (F4). Na máquina do usuário, as etapas leem o token do `gh` em `~/.config/gh/hosts.yml`, as chaves em `~/.ssh` e os `.env`, e alcançam qualquer host. Os hooks do git da ADR 0002 protegem só a `main`.

O Claude Code tem um sandbox nativo para os comandos Bash, com lista de domínios, restrição de escrita e proteção de credenciais (`deny` e `mask`). Pela documentação, o `mask` e o `tlsTerminate`, que ele exige, só são aceitos no settings do usuário, no gerenciado ou no `--settings`, e nunca no de um repositório.

## Decisão
O `/fabrica:setup` liga o sandbox nativo por projeto e grava as configurações em dois lugares:
- **`.claude/settings.json` do projeto:**
  - `enabled` e `allowUnsandboxedCommands: false`;
  - os domínios de base;
  - `deny` em `~/.ssh`, nos `.env*` e em `GH_TOKEN` e `GITHUB_TOKEN`.
- **`~/.claude/settings.json` do usuário:** o `tlsTerminate` e o `mask` do token do `gh`, posto pelo proxy só em `api.github.com` e `github.com`.

O que precisa sair do sandbox o usuário roda com `!` no prompt.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Docker Sandboxes ou microVM por etapa | Isola mais, mas exige outra execução das skills e do `gh`. Fica para o runner da Fase 1 (#106), se o nativo não bastar. |
| `gh` em `excludedCommands` | O `gh` sai do sandbox, e `gh auth token` devolve o token em claro. |
| Token fine-grained em claro no sandbox | O agente ainda lê o token, o que contraria a F1. |
| Tudo no settings do usuário | Liga o sandbox em todas as sessões da máquina, inclusive fora dos projetos da fábrica. |
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
