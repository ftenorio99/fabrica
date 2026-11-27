# Revisar um PR da fábrica

O PR chegou com `pronto-revisao`: a revisão automática passou e o CI está verde. Falta você.

## Por onde começar
Leia as seções do corpo do PR nesta ordem, que não é a ordem em que elas aparecem:
1. **Para a sua revisão:** onde o agente pede atenção, como arquivos sensíveis, decisões e riscos.
2. **Desvios da spec:** o que mudou em relação ao desenho aprovado, e por quê.
3. **Revisão automática:** os achados que foram corrigidos e as **sugestões não aplicadas**, que são para você decidir.
4. **Critérios de aceite:** a evidência de cada critério. O detalhe, com o arquivo e a linha ou o teste e o comando de cada um e o que o revisor não conseguiu provar ("Não encontrado"), está na seção "Evidência por critério" do último comentário da revisão no PR. "Implementado" sem teste ou comando não conta. Um CA com ⏳ foi marcado na spec como verificação depois do merge, com o motivo: ele não bloqueia o PR, e você o confere depois do merge, como diz "Para a sua revisão".

Num PR de `fix`, a evidência dos critérios que descrevem o bug mostra a reprodução antes e depois da correção ([prova do bug](../fluxo.md#prova-do-bug)). "Pela anotação do implementar, não reproduzida" quer dizer que o revisor não repetiu a falha por conta própria. Se o bug não pôde ser reproduzido, o motivo está em "Para a sua revisão": confira se ele convence antes do merge.

O `/fabrica:status` já resume esses pontos para cada PR que espera você.

## Antes do merge
Outro PR pode ter entrado na `main` depois da revisão, e o CI verde vale para a base antiga. Confira no `/fabrica:status` se o PR tem o alerta de `main` avançada ou de conflito:
- **Com o alerta:** rode `/fabrica:revisar <nº>` no clone. A revisão atualiza a branch com a `main`, verifica de novo e devolve o PR com `pronto-revisao`, ou escala se não conseguir.
- **Sem o alerta:** siga para a decisão. Um PR atrás só em arquivos que ele não toca pode ser mergeado.

A conferência é por arquivo: ela não pega um conflito de comportamento entre arquivos diferentes.

## Decidir
- **Aprovar:** faça o merge com squash (`gh pr merge <nº> --squash --delete-branch`), ou peça ao Claude, que confirma antes de fazer. A issue fecha sozinha pelo `Fixes #<nº>`.
- **Pedir mudanças:** comente no PR, na conversa ou nas linhas do diff, e rode `/fabrica:revisar <nº>` no clone. Os agentes usam a sua conta, então o PR é seu, e o GitHub não deixa o autor pedir mudanças com uma review; por isso o caminho é o comentário. O `/fabrica:status` mostra a issue como "Ajustes do PR pedidos" até a revisão responder. A revisão corrige o que cabe na spec, responde no PR com o que fez em cada pedido e devolve o PR para você. Só contam os comentários feitos depois do início da última revisão; os que chegam enquanto ela roda são citados na resposta e ficam para a próxima.
- **Mudança de escopo:** se o que você quer muda um critério de aceite, a revisão não corrige: ela aplica `escalonado` e indica o caminho. Remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>`, aprove de novo e retome com `/fabrica:implementar <nº>`. Se já sabe que é mudança de escopo, pode ir direto por esse caminho, sem comentar no PR.
- **Sugestões:** as não aplicadas podem virar ajustes neste PR ou uma issue nova.

## Depois do merge na própria fábrica
Se o PR era da fábrica, atualize o plugin: `/plugin marketplace update fabrica` e `/reload-plugins`. Em seguida, confira os CAs ⏳ do PR com o plugin atualizado.
