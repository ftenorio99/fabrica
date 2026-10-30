# Máquina de estados do fluxo

Fonte da verdade do estado de uma issue na fábrica. Não existe arquivo de estado à parte: o estado é lido das **labels**, dos **marcadores de comentário** (`<!-- fabrica:triagem -->`, `<!-- fabrica:spec -->`), do marcador de backlog no corpo da issue (`<!-- fabrica:backlog item=<n> -->`), das **milestones** e do **PR** da branch da issue. Esta tabela serve ao `/fabrica:status` hoje e ao dispatcher do GitHub Actions na Fase 1.

## Labels
Esta tabela é lida por `scripts/setup-labels.sh`, que cria ou corrige as labels num repositório (`/fabrica:setup`). O `Significado` vira a descrição da label no GitHub, com no máximo 100 caracteres, e a `Cor` vai em hexadecimal sem `#`.

| Label | Quem aplica | Cor | Significado |
|---|---|---|---|
| `agente` | usuário | `5319e7` | A issue entra na fábrica. |
| `precisa-info` | triagem, spec | `fbca04` | Há perguntas para o usuário na issue. |
| `spec-pronta` | spec | `0e8a16` | Spec na branch, aguardando aprovação. |
| `spec-aprovada` | usuário | `1d76db` | Implementação liberada. Conta para o limite de 3 em andamento. |
| `escalonado` | implementar, revisar | `d93f0b` | O agente parou por falha e precisa do usuário. Sai quando a etapa é retomada. |
| `pronto-revisao` | revisar | `c2e0c6` | PR com CI verde e revisão automática feita, aguardando o usuário. |

## Estados
Avalie de cima para baixo; vale a primeira linha cuja condição for verdadeira.

Os agentes comentam com a mesma conta do GitHub do usuário, então o autor não serve para distinguir os dois. **Comentário do agente** é o que começa com um marcador `<!-- fabrica:<etapa> -->` (`triagem`, `spec`, `implementar`, `revisar`, `backlog`); **comentário do usuário** é qualquer outro. A regra vale na issue e no PR, onde contam os comentários da conversa, as reviews e os comentários em linha. Toda review do usuário conta, mesmo sem corpo: um comentário em linha avulso cria uma review `COMMENTED` de corpo vazio, e é por ela que o `/fabrica:status` o enxerga. "Resposta nova" é um comentário do usuário posterior ao último comentário do agente com o marcador citado. "Pedido novo no PR" é um comentário ou review do usuário no PR posterior ao último comentário `<!-- fabrica:revisar -->` da conversa do PR; sem esse comentário, todo comentário do usuário no PR conta.

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
| 11 | PR aberto com review `CHANGES_REQUESTED` ou com pedido novo no PR. Com a conta do usuário, o caminho é o comentário: o GitHub não deixa o autor pedir mudanças no próprio PR; a review vale para PR aberto por outra conta, como um bot | Ajustes do PR pedidos | agente | `/fabrica:revisar <nº>` |
| 12 | PR aberto sem `pronto-revisao` | Em revisão automática | agente | `/fabrica:revisar <nº>` (se nenhuma sessão estiver nele) |
| 13 | PR aberto com `pronto-revisao` | PR para revisar | usuário | Revisar o PR e fazer o merge com squash. |

## Backlog
Issue aberta **sem `agente`**, com milestone e com o marcador `<!-- fabrica:backlog item=<n> -->` no corpo, criada por `/fabrica:backlog` a partir do fatiamento do `docs/prd.md`. Ela fica fora da tabela de estados acima, que vale só para issues com `agente`.

| Estado | Quem age | Próximo passo |
|---|---|---|
| Backlog | usuário | Aplicar `agente` para puxar a issue para o fluxo. |

**Marcador:** `<!-- fabrica:backlog item=<n> -->` no corpo identifica o item `<n>` do fatiamento. Fica na primeira linha das issues criadas pelo backlog e no fim do corpo das issues antigas vinculadas a um item. Ele vale mesmo antes do merge do PR `docs/backlog`, que anota o número da issue no PRD.

**Termos:**
- **Marco:** grupo de itens do fatiamento, com título `M<n> · <nome>`, que é também o título da milestone no GitHub. O prefixo `M<n>` dá a ordem.
- **Item com issue:** item que tem uma issue com o marcador, ou cujo número está anotado no PRD (` · #<nº>`).
- **Marco atual:** o primeiro marco, na ordem `M<n>`, que tem issue aberta ou item sem issue.
- **Perto de fechar:** o marco atual não tem item sem issue, tem pelo menos 1 issue fechada e tem no máximo 2 issues abertas. A issue fechada evita que um marco pequeno, recém-criado, já avance a janela.
- **Janela:** o marco atual e o seguinte. Quando o atual está perto de fechar, a janela avança um marco: o seguinte e o depois dele. Só os itens da janela ganham issue.

**Ordem de sugestão:** sem issue com `agente` aberta no repositório, a próxima a puxar é a issue de backlog do marco atual com o menor número de item cujas issues do `Depende de` estão todas fechadas.

## Inconsistências
Sinalize como alerta, sem tentar corrigir:
- `spec-aprovada` sem marcador de spec, ou marcador de spec sem a branch que ele cita.
- `pronto-revisao` sem PR aberto.
- `spec-pronta` e `spec-aprovada` ao mesmo tempo é normal (a spec skill não remove a primeira); não é inconsistência.
- PR fechado sem merge com a issue ainda aberta.
