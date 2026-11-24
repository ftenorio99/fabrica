# ADR 0019: CI do PR pelo modelo da fábrica, com o `make e2e` como contrato

**Status:** aceito · **Data:** 2026-11-23 · **Origem:** issue #128

## Contexto
A F6 do [PRD](../prd.md) pede que o CI do PR suba o app e o banco no próprio job e rode o Playwright. A [ADR 0011](0011-verificacao-de-integracao-na-etapa.md) já exige um CI em `pull_request` em todo projeto, como reserva e conferência da verificação que a etapa roda, mas a fábrica não entrega esse CI: cada projeto escreveu o seu, de um jeito (o `kairo` chama `make e2e`; o `ankyra` sobe o Postgres por `services:`; o `mnemo` e o `skopia` não têm CI).

## Decisão
A fábrica tem um modelo de CI, `templates/workflows/ci.yml`, que roda `make lint`, `make test` e `make e2e` e que o `/fabrica:setup` copia para um projeto sem CI em `pull_request`, sem nunca sobrescrever. O contrato entre o CI e o projeto é o `Makefile`: o `make e2e` sobe sozinho o banco (pelo Docker Compose) e o app e roda o Playwright, igual à etapa local; os valores de teste vêm do `.env.example`.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Workflow reutilizável chamado de dentro da fábrica | Acopla o CI do projeto a um repositório externo e a um token para lê-lo. |
| Passos do Playwright e `services:` do banco escritos no modelo | Duplica o comando de cada projeto, e o CI deixa de ser igual à etapa local. |
| Gerenciar a cópia byte a byte, como o `agente.yml` | Cada projeto tem variáveis e passos próprios no CI; a atualização os apagaria. |
| Bloco `env:` a preencher no modelo | O CI recém-instalado nasceria vermelho até o usuário preencher. |

## Consequências
- Projeto novo ganha um CI que roda o Playwright sem escrever workflow.
- O `make e2e` de todo projeto precisa ser autossuficiente (subir banco e app), e o `.env.example` precisa ter valores locais que bastem para os testes.
- A cópia do `ci.yml` é do projeto: uma melhoria no modelo não chega sozinha aos projetos que já o copiaram.
- O modelo cobre Node com npm ou pnpm (e `make install` como saída genérica); outra stack adapta a cópia.
