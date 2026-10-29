# Revisar um PR da fábrica

O PR chegou com `pronto-revisao`: a revisão automática passou e o CI está verde. Falta você.

## Por onde começar
O corpo do PR segue sempre a mesma ordem. Leia as seções nesta ordem:
1. **Para a sua revisão:** onde o agente pede atenção, como arquivos sensíveis, decisões e riscos.
2. **Desvios da spec:** o que mudou em relação ao desenho aprovado, e por quê.
3. **Revisão automática:** os achados que foram corrigidos e as **sugestões não aplicadas**, que são para você decidir.
4. **Critérios de aceite:** a evidência de cada critério. "Implementado" sem teste ou comando não conta.

O `/fabrica:status` já resume esses pontos para cada PR que espera você.

## Decidir
- **Aprovar:** faça o merge com squash (`gh pr merge <nº> --squash --delete-branch`), ou peça ao Claude, que confirma antes de fazer. A issue fecha sozinha pelo `Fixes #<nº>`.
- **Pedir mudanças:** comente no PR. Os agentes usam a sua conta, então o PR é seu, e o GitHub não deixa o autor pedir mudanças com uma review. O `/fabrica:status` passa a mostrar a issue como "Ajustes do PR pedidos". Peça ao Claude, no clone, para corrigir na branch o que você comentou e depois rode `/fabrica:revisar <nº>`. A revisão confere a branch contra a spec, mas não lê os comentários do PR.
- **Mudança de escopo:** se o que você quer muda a spec, não peça no PR. Remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>` e aprove de novo.
- **Sugestões:** as não aplicadas podem virar ajustes neste PR ou uma issue nova.

## Depois do merge na própria fábrica
Se o PR era da fábrica, atualize o plugin: `/plugin marketplace update fabrica` e `/reload-plugins`.
