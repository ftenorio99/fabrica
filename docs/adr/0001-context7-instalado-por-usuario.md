# ADR 0001: Context7 instalado por usuário, não pelo plugin

**Status:** aceito · **Data:** 2026-10-28 · **Origem:** issue #13

## Contexto
As skills `spec` e `implementar` decidem e escrevem código contra bibliotecas que mudam rápido (ex.: Next 16, Drizzle e Postgres 18 no kairo). O Context7 entrega documentação atual e por versão via MCP (`resolve-library-id` e `query-docs`) e precisa de uma API key para ter limites maiores que o plano gratuito (1.000 chamadas por mês). A chave nunca pode entrar no repositório.

O usuário já rodou `npx ctx7 setup --claude` em modo MCP nesta máquina. O comando configurou:
- o MCP remoto `https://mcp.context7.com/mcp` em `~/.claude.json` (escopo de usuário, permissão `600`), com a chave no header `Authorization`;
- a regra global `~/.claude/rules/context7.md`;
- a skill `~/.claude/skills/context7-mcp/SKILL.md`.

## Decisão
O Context7 é um pré-requisito instalado por usuário com `npx ctx7 setup --claude` (modo MCP). O plugin `fabrica` não declara o servidor; as skills usam o Context7 quando ele estiver disponível e seguem sem ele quando não estiver.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Declarar o MCP no `.mcp.json` do plugin, lendo `${CONTEXT7_API_KEY}` | Nesta máquina criaria um segundo servidor com o mesmo nome do já instalado por usuário, e obrigaria a manter a chave também numa variável de ambiente. |
| Plugin oficial (`/plugin install context7@context7-marketplace`) | Não lê `CONTEXT7_API_KEY` (login pelo `/mcp`) e duplicaria o servidor que o `ctx7 setup` já configurou. |
| `claude mcp add --scope user` manual | Funciona, mas o `ctx7 setup` faz o mesmo e ainda gera a chave e instala a regra e a skill de uso. |

## Consequências
- A chave fica só em `~/.claude.json`, fora de qualquer repositório.
- Cada máquina que rodar a fábrica precisa do `npx ctx7 setup --claude`; o README registra isso como pré-requisito.
- As skills não podem depender do Context7: sem ele, seguem para a próxima fonte da ordem de consulta e registram que a API não foi verificada.
- A regra global manda usar o Context7 sempre; nas skills `spec` e `implementar` vale a ordem de consulta delas, que põe a documentação local do pacote instalado antes.
- Na Fase 1, o dispatcher no GitHub Actions não terá o `~/.claude.json`: o servidor terá de ser configurado no workflow, com a chave em secret do repositório. Isso exigirá um novo ADR ou a revisão deste.
