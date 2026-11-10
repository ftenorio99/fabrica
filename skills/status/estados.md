# Máquina de estados do fluxo

Fonte da verdade do estado de uma issue na fábrica. Não existe arquivo de estado à parte: o estado é lido das **labels**, dos **marcadores de comentário** (`<!-- fabrica:triagem -->`, `<!-- fabrica:spec -->`), do marcador de backlog no corpo da issue (`<!-- fabrica:backlog item=<n> -->`), das **milestones** e do **PR** da branch da issue. Esta tabela serve ao `/fabrica:status` hoje e ao dispatcher do GitHub Actions na Fase 1.

O marcador `<!-- fabrica:retro -->` na primeira linha do corpo identifica a issue que o `/fabrica:retro` criou no fabrica com uma proposta de melhoria. Ele não muda o estado: a issue nasce sem `agente`, fora do fluxo, e segue a tabela abaixo quando o usuário aplicar `agente`.

## Labels
Esta tabela é lida por `scripts/setup-labels.sh`, que cria ou corrige as labels num repositório (`/fabrica:setup`). O `Significado` vira a descrição da label no GitHub, com no máximo 100 caracteres, e a `Cor` vai em hexadecimal sem `#`.

| Label | Quem aplica | Cor | Significado |
|---|---|---|---|
| `agente` | usuário | `5319e7` | A issue entra na fábrica. |
| `precisa-info` | triagem, spec | `fbca04` | Há perguntas para o usuário na issue. |
| `spec-pronta` | triagem, spec | `0e8a16` | Spec na branch, ou spec curta na triagem, aguardando aprovação. |
| `spec-aprovada` | usuário | `1d76db` | Implementação liberada. Conta para o limite de 3 em andamento. |
| `escalonado` | implementar, revisar | `d93f0b` | O agente parou por falha e precisa do usuário. Sai quando a etapa é retomada. |
| `pronto-revisao` | revisar | `c2e0c6` | PR com CI verde e revisão automática feita, aguardando o usuário. |
| `licao` | triagem, implementar, revisar, licao | `f9d0c4` | Lição aprendida registrada num comentário fabrica:licao. |
| `em-andamento` | avancar | `bfdadc` | Uma execução automática está rodando uma etapa nesta issue. Vale por 2 h. |

## Estados
Avalie de cima para baixo; vale a primeira linha cuja condição for verdadeira.

Os agentes comentam com a mesma conta do GitHub do usuário, então o autor não serve para distinguir os dois. **Comentário do agente** é o que começa com um marcador `<!-- fabrica:<etapa> -->` (`triagem`, `spec`, `implementar`, `revisar`, `backlog`); **comentário do usuário** é qualquer outro, exceto o comentário de lição e o de [recusa de par](#backlog), que não são de nenhum dos dois. A regra vale na issue e no PR, onde contam os comentários da conversa, as reviews e os comentários em linha. Toda review do usuário conta, mesmo sem corpo: um comentário em linha avulso cria uma review `COMMENTED` de corpo vazio, e é por ela que o `/fabrica:status` o enxerga. A exceção é a review `APPROVED` de corpo vazio, que não é comentário do usuário; com corpo, ela conta. "Resposta nova" é um comentário do usuário posterior ao último comentário do agente com o marcador citado. "Pedido novo no PR" é um comentário ou review do usuário no PR posterior à referência do último comentário `<!-- fabrica:revisar -->` da conversa do PR. A referência é o instante da linha `**Pedidos lidos até:**` desse comentário, ou a data dele quando a linha falta. Sem esse comentário, todo comentário do usuário no PR conta. O **comentário de lição** começa com `<!-- fabrica:licao` ([formato](../licao/formato.md)) e é ignorado em todas as regras de estado: não é comentário do agente nem do usuário, não é resposta nova, não é o último comentário do agente e não é pedido novo no PR. A label `licao` também não entra em nenhuma condição da tabela. A **linha de custo** `<!-- fabrica:custo ... -->`, que as etapas acrescentam no fim dos seus comentários com o início, o fim e os tokens da execução, só serve ao `/fabrica:metricas`: ela não muda o estado da issue nem o tipo do comentário, que continua sendo decidido pelo marcador da primeira linha.

A **spec da issue** e a **branch da issue** vêm de um destes comentários, nesta ordem:
- o comentário `<!-- fabrica:spec -->` mais recente: a spec é o arquivo que ele cita, e a branch é o `**Branch:**` dele;
- sem comentário de spec, o comentário de triagem mais recente, quando ele tem `**Atalho:** sim`: a spec é a seção `### Spec curta` dele, e a branch é o `**Branch:**` dela ([Atalho](#atalho)).

Toda etapa e todo comando que lê a spec, a branch ou o PR de uma issue usa esta regra.

| # | Condição | Estado | Quem age | Próximo passo |
|---|---|---|---|---|
| 1 | `escalonado` | Bloqueado | usuário | Ler o último comentário do agente na issue (ou no PR) e decidir; depois retomar a etapa que parou. |
| 2 | sem marcador de triagem | Aguardando triagem | agente | `/fabrica:triagem <nº>` |
| 3 | `precisa-info` sem resposta nova | Perguntas abertas | usuário | Responder as perguntas na issue. |
| 4 | `precisa-info` com resposta nova | Respostas recebidas | agente | `/fabrica:triagem <nº>` (ou `/fabrica:spec <nº>`, se as perguntas vieram da spec) |
| 5 | sem `spec-pronta`, sem `spec-aprovada` e sem marcador de spec | Triada | agente | `/fabrica:spec <nº>` |
| 6 | `spec-pronta` sem `spec-aprovada`, com resposta nova ao marcador de spec ou, no atalho, sem comentário de spec, com resposta nova ao marcador de triagem | Ajuste da spec pedido | agente | `/fabrica:spec <nº> <ajustes>` |
| 7 | `spec-pronta` sem `spec-aprovada` | Spec para aprovar | usuário | Revisar a spec e aplicar `spec-aprovada` ou comentar ajustes. No atalho, a spec é a spec curta da triagem, e comentar pede a spec completa. |
| 8 | `spec-aprovada` e nenhum PR da branch | Em implementação | agente | `/fabrica:implementar <nº>` (se não houver `em-andamento` recente) |
| 9 | PR em rascunho | Revisão automática com pendências | usuário | Ler os achados pendentes no PR e decidir. Se o PR não lista achados pendentes e tem CAs com ⏳ "aguardando o CI", o `/fabrica:revisar` parou enquanto esperava o CI ([ADR 0007](../../docs/adr/0007-verificacao-de-integracao-pelo-ci.md)): retome com `/fabrica:revisar <nº>`. |
| 10 | PR aberto com CI falhando | CI vermelho | agente | `/fabrica:revisar <nº>` |
| 11 | PR aberto com review `CHANGES_REQUESTED` ou com pedido novo no PR. Com a conta do usuário, o caminho é o comentário: o GitHub não deixa o autor pedir mudanças no próprio PR; a review vale para PR aberto por outra conta, como um bot | Ajustes do PR pedidos | agente | `/fabrica:revisar <nº>` |
| 12 | PR aberto sem `pronto-revisao` | Em revisão automática | agente | `/fabrica:revisar <nº>` (se não houver `em-andamento` recente) |
| 13 | PR aberto com `pronto-revisao` | PR para revisar | usuário | Revisar o PR e fazer o merge com squash. |

## Etapa em andamento
A label `em-andamento` não é um estado: a issue continua no estado da tabela acima, e a label só diz que uma execução automática, como o `/fabrica:avancar`, está rodando uma etapa nela ([ADR 0003](../../docs/adr/0003-sinal-de-etapa-em-andamento.md)).
- **Recente:** o último evento `labeled em-andamento` da timeline da issue tem menos de 2 h. Outra execução automática não pega a issue, e o `/fabrica:status` mostra "Em andamento" no lugar do comando.
- **Esquecida:** o último evento tem 2 h ou mais, por exemplo numa sessão que morreu no meio. Outra execução pode pegar a issue, e o `/fabrica:status` alerta.
- Os comandos manuais (`/fabrica:triagem` etc.) não aplicam nem conferem a label.

## Atalho
Uma issue pequena e sem ambiguidade pode pular a etapa `/fabrica:spec` ([ADR 0004](../../docs/adr/0004-atalho-da-triagem-com-spec-curta.md)). O critério e o formato estão na [triagem](../triagem/SKILL.md).
- **Entrada:** a triagem registra `**Atalho:** sim`, publica a `### Spec curta` no próprio comentário e aplica `spec-pronta`. A issue vai direto para a linha 7, Spec para aprovar.
- **Aprovação:** a mesma label `spec-aprovada`, que conta para o limite de 3 em andamento. A partir daí, o fluxo é o de sempre.
- **Saída:** uma resposta nova ao comentário de triagem, antes de `spec-aprovada`, leva à linha 6. O `/fabrica:spec` escreve a spec completa, e o comentário de spec passa a valer como spec da issue. A spec curta nunca é editada.

## Backlog
Issue aberta **sem `agente`**, com milestone e com o marcador `<!-- fabrica:backlog item=<n> -->` no corpo, criada por `/fabrica:backlog` a partir do fatiamento do `docs/prd.md`. Ela fica fora da tabela de estados acima, que vale só para issues com `agente`.

| Estado | Quem age | Próximo passo |
|---|---|---|
| Backlog | usuário | Aplicar `agente` para puxar a issue para o fluxo. |

**Marcador:** `<!-- fabrica:backlog item=<n> -->` no corpo identifica o item `<n>` do fatiamento. Fica na primeira linha das issues criadas pelo backlog e no fim do corpo das issues antigas vinculadas a um item. Ele vale mesmo antes do merge do PR `docs/backlog`, que anota o número da issue no PRD, e vale também com a issue fechada.

**Recusa de par:** o comentário `<!-- fabrica:backlog par-recusado item=<n> -->` numa issue registra que ela não é o item `<n>`, recusada como possível par no `/fabrica:backlog` ([backlog](../backlog/SKILL.md)). Ele só serve ao backlog: não muda o estado da issue e não conta como comentário do agente nem do usuário nas regras da tabela de estados, como o comentário de lição.

**Termos:**
- **Marco:** grupo de itens do fatiamento, com título `M<n> · <nome>`, que é também o título da milestone no GitHub. O prefixo `M<n>` dá a ordem.
- **Item com issue:** item que tem uma issue com o marcador, aberta ou fechada, ou cujo número está anotado no PRD (` · #<nº>`).
- **Marco atual:** o primeiro marco, na ordem `M<n>`, que tem issue aberta ou item sem issue.
- **Perto de fechar:** o marco atual não tem item sem issue, tem pelo menos 1 issue fechada e tem no máximo 2 issues abertas. A issue fechada evita que um marco pequeno, recém-criado, já avance a janela.
- **Janela:** o marco atual e o seguinte. Quando o atual está perto de fechar, a janela avança um marco: o seguinte e o depois dele. Só os itens da janela ganham issue.

**Ordem de sugestão:** sem issue com `agente` aberta no repositório, a próxima a puxar é a issue de backlog do marco atual com o menor número de item cujas issues do `Depende de` estão todas fechadas.

## Inconsistências
Sinalize como alerta, sem tentar corrigir:
- `spec-aprovada` sem spec da issue (nem comentário de spec, nem triagem com atalho), ou marcador de spec sem a branch que ele cita. No atalho, a branch só nasce no `/fabrica:implementar`, e a falta dela antes disso não é inconsistência.
- `pronto-revisao` sem PR aberto.
- `spec-pronta` e `spec-aprovada` ao mesmo tempo é normal (nem a spec nem a triagem do atalho removem a primeira); não é inconsistência.
- PR fechado sem merge com a issue ainda aberta.
- `em-andamento` aplicada há 2 h ou mais (label esquecida). Ao contrário das outras, esta não tira a issue do fluxo: uma execução automática pode retomá-la ([Etapa em andamento](#etapa-em-andamento)).
