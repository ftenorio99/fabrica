# Issue escalonada

Um agente parou e aplicou a label `escalonado`. O `/fabrica:status` mostra a issue como "Bloqueado", esperando você.

## Por que um agente para
| Situação | Onde está a explicação |
|---|---|
| A implementação encontrou um desvio relevante da spec: mudança de comportamento, de critério ou de escopo | Comentário `<!-- fabrica:implementar -->` na issue, com as opções e uma recomendação |
| `make lint` ou `make test` falharam depois de duas rodadas de correção | Comentário `<!-- fabrica:implementar -->` com o comando, o erro e o que já foi tentado |
| A revisão terminou com achados bloqueantes depois de duas rodadas de correção | PR em rascunho com os achados pendentes |
| Um pedido seu no PR mudaria um critério de aceite ou entraria no "Fora de escopo" da spec | Comentário `<!-- fabrica:revisar -->` no PR, com o que foi feito em cada pedido |

## O que fazer
1. **Leia o último comentário do agente,** na issue ou no PR.
2. **Decida e responda na issue.** Os caminhos mais comuns:
   - **Ajustar a spec:** remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>` e aprove de novo.
   - **Seguir com a spec como está:** diga isso na issue.
   - **Resolver você mesmo:** corrija o ambiente ou a dependência que faltava.
3. **Retome a etapa que parou:**
   - **Se a implementação parou:** rode `/fabrica:implementar <nº>`. Ela lê a sua resposta, remove `escalonado` e continua dos commits que já existem.
   - **Se a revisão parou:** rode `/fabrica:revisar <nº>`.

O `escalonado` sai sozinho quando a etapa é retomada. Detalhes em [`skills/implementar/SKILL.md`](../../skills/implementar/SKILL.md) e [`skills/revisar/SKILL.md`](../../skills/revisar/SKILL.md).
