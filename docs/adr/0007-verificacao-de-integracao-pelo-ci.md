# ADR 0007: Verificação de integração pelo CI do PR

**Status:** substituído por ADR 0011 · **Data:** 2026-11-10 · **Origem:** issue #116

> A [ADR 0010](0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) retirou o sandbox nativo, cujo limite é o descrito aqui. A [ADR 0011](0011-verificacao-de-integracao-na-etapa.md) substitui esta: a verificação de integração passa a rodar na própria etapa, e o CI vira reserva e conferência.

## Contexto
O sandbox da [ADR 0005](0005-isolamento-do-agente-em-sandbox.md) isola os comandos Bash do agente. No Linux, segundo a documentação do sandbox do Claude Code:
- todo socket Unix fica bloqueado, inclusive o do Docker;
- o `localhost` de cada comando é privado;
- nenhuma configuração libera o Docker ou o banco da máquina sem desmontar o isolamento. O socket do Docker dá controle do daemon, e um comando em `excludedCommands` roda fora do sandbox com o que o agente puser no `Makefile`.

Por isso, o `make test` com banco e o `make e2e` não rodam nas etapas de agente. Os projetos da fábrica já têm CI que roda a verificação completa num ambiente descartável.

## Decisão
- **No sandbox:** o agente roda a verificação que cabe nele: lint, typecheck e testes sem banco.
- **Pelo CI:** a verificação que falha só por limite do sandbox (assinaturas fixas do erro, listadas no `/fabrica:implementar`) fica para o CI. O `/fabrica:revisar` abre o PR em rascunho, espera o CI do head pela API do Actions e passa o resultado ao revisor como evidência dos CAs de integração. Só com o CI verde ele tira o rascunho e aplica `pronto-revisao`.
- **Sem CI que dispare em `pull_request`:** a etapa escalona e pede a verificação ao usuário.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Liberar o socket do Docker (`allowAllUnixSockets`) | O socket dá controle da máquina inteira (`docker run -v /:/host`). |
| `make test` ou `docker *` em `excludedCommands` | Roda fora do sandbox o que o agente puser no `Makefile`. |
| Testes de integração rodados pelo usuário com `!` | Para o fluxo automático a cada issue. |
| Banco embutido nos testes (ex.: PGlite) | Mudaria cada projeto e não cobre o `make e2e`. |
| `gh pr checks` com a permissão de checks no token | Amplia o que o token fine-grained alcança. A API do Actions basta. |

## Consequências
- Todo projeto da fábrica precisa de um CI que rode a verificação completa em `pull_request`. Sem ele, as etapas escalonam.
- O PR passa a nascer em rascunho quando há verificação pendente, e a revisão automática fica mais longa, pelo tempo do CI.
- Uma falha real confundida com limite do sandbox só aparece no CI e custa uma rodada.
