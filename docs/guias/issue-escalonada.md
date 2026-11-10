# Issue escalonada

Um agente parou e aplicou a label `escalonado`. O `/fabrica:status` mostra a issue como "Bloqueado", esperando você.

## Por que um agente para
| Situação | Onde está a explicação |
|---|---|
| A implementação encontrou um desvio relevante da spec: mudança de comportamento, de critério ou de escopo | Comentário `<!-- fabrica:implementar -->` na issue, com as opções e uma recomendação |
| `make lint` ou `make test` falharam depois de duas rodadas de correção | Comentário `<!-- fabrica:implementar -->` com o comando, o erro e o que já foi tentado |
| A revisão terminou com achados bloqueantes depois de duas rodadas de correção | PR em rascunho com os achados pendentes |
| A verificação de integração não roda no sandbox e o projeto não tem CI em `pull_request` ([ADR 0007](../adr/0007-verificacao-de-integracao-pelo-ci.md)) | Comentário `<!-- fabrica:revisar -->` na issue, com os comandos que você roda com `!` |
| Verificação manual pedida a você: um critério de aceite pede uma verificação que não roda no sandbox, como um comando com o app rodando e o banco | Comentário `<!-- fabrica:revisar -->` na issue, com o critério, o comando que você roda com `!` e o que conferir; o PR fica em rascunho |
| Um pedido seu no PR mudaria um critério de aceite ou entraria no "Fora de escopo" da spec | Comentário `<!-- fabrica:revisar -->` no PR, com o que foi feito em cada pedido |

## O que fazer
1. **Leia o último comentário do agente,** na issue ou no PR.
2. **Decida e responda na issue.** Os caminhos mais comuns:
   - **Ajustar a spec:** remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>` e aprove de novo.
   - **Seguir com a spec como está:** diga isso na issue.
   - **Resolver você mesmo:** corrija o ambiente ou a dependência que faltava.
3. **Retome a etapa que parou:**
   - **Se a implementação parou:** rode `/fabrica:implementar <nº>`. Ela lê a sua resposta, remove `escalonado` e continua dos commits que já existem.
   - **Se a revisão parou por achados pendentes:** rode `/fabrica:revisar <nº>`.
   - **Se a revisão pediu a verificação de integração:** rode os comandos do comentário com `!`, responda na issue com o resultado e rode `/fabrica:revisar <nº>`. Ele usa a sua resposta como verificação manual.
   - **Se a revisão pediu uma verificação manual:** rode o comando do comentário com `!`, responda na issue com o comando e a saída e rode `/fabrica:revisar <nº>`, sem tirar o `escalonado`. A revisão usa a sua resposta como evidência do critério; se a saída mostra falha, a correção volta para o `/fabrica:implementar`.
   - **Se a revisão parou porque um pedido seu no PR muda a spec:** remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>`, aprove de novo e retome com `/fabrica:implementar <nº>`.

O `escalonado` sai sozinho quando a etapa é retomada. Detalhes em [`skills/implementar/SKILL.md`](../../skills/implementar/SKILL.md) e [`skills/revisar/SKILL.md`](../../skills/revisar/SKILL.md).
