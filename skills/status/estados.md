# Máquina de estados do fluxo

Fonte da verdade do estado de uma issue na fábrica. Não existe arquivo de estado à parte: o estado é lido das **labels**, dos **marcadores de comentário** (`<!-- fabrica:triagem -->`, `<!-- fabrica:spec -->`) e do **PR** da branch da issue. Esta tabela serve ao `/fabrica:status` hoje e ao dispatcher do GitHub Actions na Fase 1.

## Labels
| Label | Quem aplica | Significado |
|---|---|---|
| `agente` | usuário | A issue entra na fábrica. |
| `precisa-info` | triagem, spec | Há perguntas para o usuário na issue. |
| `spec-pronta` | spec | Spec na branch, aguardando aprovação. |
| `spec-aprovada` | usuário | Implementação liberada. Conta para o limite de 3 em andamento. |
| `escalonado` | implementar, revisar | O agente parou por falha e precisa do usuário. Sai quando a etapa é retomada. |
| `pronto-revisao` | revisar | PR com CI verde e revisão automática feita, aguardando o usuário. |

## Estados
Avalie de cima para baixo; vale a primeira linha cuja condição for verdadeira.

Os agentes comentam com a mesma conta do GitHub do usuário, então o autor não serve para distinguir os dois. **Comentário do agente** é o que começa com um marcador `<!-- fabrica:<etapa> -->` (`triagem`, `spec`, `implementar`, `revisar`); **comentário do usuário** é qualquer outro. "Resposta nova" é um comentário do usuário posterior ao último comentário do agente com o marcador citado.

| # | Condição | Estado | Quem age | Próximo passo |
|---|---|---|---|---|
| 1 | `escalonado` | Bloqueado | usuário | Ler o último comentário do agente na issue (ou no PR) e decidir; depois retomar a etapa que parou. |
| 2 | sem marcador de triagem | Aguardando triagem | agente | `/fabrica:triagem <nº>` |
| 3 | `precisa-info` sem resposta nova | Perguntas abertas | usuário | Responder as perguntas na issue. |
| 4 | `precisa-info` com resposta nova | Respostas recebidas | agente | `/fabrica:triagem <nº>` (ou `/fabrica:spec <nº>`, se as perguntas vieram da spec) |
| 5 | sem `spec-pronta`, sem `spec-aprovada` e sem marcador de spec | Triada | agente | `/fabrica:spec <nº>` |
| 6 | `spec-pronta` sem `spec-aprovada`, com resposta nova ao marcador de spec | Ajuste da spec pedido | agente | `/fabrica:spec <nº> <ajustes>` |
| 7 | `spec-pronta` sem `spec-aprovada` | Spec para aprovar | usuário | Revisar a spec e aplicar `spec-aprovada` ou comentar ajustes. |
| 8 | `spec-aprovada` e nenhum PR da branch | Em implementação | agente | `/fabrica:implementar <nº>` (se nenhuma sessão estiver nele) |
| 9 | PR em rascunho | Revisão automática com pendências | usuário | Ler os achados pendentes no PR e decidir. |
| 10 | PR aberto com CI falhando | CI vermelho | agente | `/fabrica:revisar <nº>` |
| 11 | PR aberto com mudanças pedidas pelo usuário (review `CHANGES_REQUESTED` ou comentário do usuário depois de `pronto-revisao`) | Ajustes do PR pedidos | agente | Corrigir na branch e rodar `/fabrica:revisar <nº>` |
| 12 | PR aberto sem `pronto-revisao` | Em revisão automática | agente | `/fabrica:revisar <nº>` (se nenhuma sessão estiver nele) |
| 13 | PR aberto com `pronto-revisao` | PR para revisar | usuário | Revisar o PR e fazer o merge com squash. |

## Inconsistências
Sinalize como alerta, sem tentar corrigir:
- `spec-aprovada` sem marcador de spec, ou marcador de spec sem a branch que ele cita.
- `pronto-revisao` sem PR aberto.
- `spec-pronta` e `spec-aprovada` ao mesmo tempo é normal (a spec skill não remove a primeira); não é inconsistência.
- PR fechado sem merge com a issue ainda aberta.
