# Máquina de estados do fluxo

Fonte da verdade do estado de uma issue na fábrica. Não existe arquivo de estado à parte: o estado é lido das **labels**, dos **marcadores de comentário** (`<!-- fabrica:triagem -->`, `<!-- fabrica:spec -->`, `<!-- fabrica:acao etapa=<etapa> -->`), do marcador de backlog no corpo da issue (`<!-- fabrica:backlog item=<n> -->`), das **milestones** e do **PR** da branch da issue. Esta tabela serve ao `/fabrica:status`, ao `/fabrica:avancar` e ao dispatcher do GitHub Actions, que a lê pelo `scripts/issue-state.py` ([ADR 0017](../../docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md)). O `issue-state.py` implementa as regras deste arquivo (a tabela de estados, os comentários do agente e do usuário, a spec e a branch da issue, o PR da branch e as inconsistências): quem muda uma delas muda o programa e os testes dele (`bash scripts/test-issue-state.sh`) no mesmo PR.

O marcador `<!-- fabrica:retro -->` na primeira linha do corpo identifica a issue que o `/fabrica:retro` criou no fabrica com uma proposta de melhoria. Ele não muda o estado: a issue nasce sem `agente`, fora do fluxo, e segue a tabela abaixo quando o usuário aplicar `agente`.

O marcador `<!-- fabrica:lancamento -->` na primeira linha do corpo identifica a issue de runbook que o `/fabrica:lancamento` criou. Ela também nasce sem `agente` e tem estados próprios, na seção [Lançamento](#lançamento).

## Labels
Esta tabela é lida por `scripts/setup-labels.sh`, que cria ou corrige as labels num repositório (`/fabrica:setup`). O `Significado` vira a descrição da label no GitHub, com no máximo 100 caracteres, e a `Cor` vai em hexadecimal sem `#`.

| Label | Quem aplica | Cor | Significado |
|---|---|---|---|
| `agente` | usuário | `5319e7` | A issue entra na fábrica. |
| `precisa-info` | triagem, spec | `fbca04` | Há perguntas para o usuário na issue. |
| `spec-pronta` | triagem, spec | `0e8a16` | Spec na branch, ou spec curta na triagem, aguardando aprovação. |
| `spec-aprovada` | usuário | `1d76db` | Implementação liberada. Conta para o limite de 3 em andamento. |
| `escalonado` | implementar, revisar | `d93f0b` | O agente parou por falha e precisa do usuário. Sai quando a etapa é retomada. |
| `acao-externa` | implementar, revisar, lancamento | `e99695` | O agente espera uma ação do usuário fora do GitHub, numa checklist na issue. Sai na retomada. |
| `pronto-revisao` | revisar | `c2e0c6` | PR com CI verde e revisão automática feita, aguardando o usuário. |
| `licao` | triagem, implementar, revisar, licao | `f9d0c4` | Lição aprendida registrada num comentário fabrica:licao. |
| `em-andamento` | avancar, dispatcher | `bfdadc` | Uma execução automática está rodando uma etapa nesta issue. Vale por 2 h. |
| `modelo:haiku` | triagem, usuário, avancar | `c5def5` | Modelo da implementação: Haiku 5.5, para issue mecânica (docs, chore, teste simples). |
| `modelo:sonnet` | triagem, usuário, avancar | `5ebeef` | Modelo da implementação: Sonnet 5.5, o padrão quando a issue não tem label de modelo. |
| `modelo:opus` | triagem, usuário, avancar | `0b3d91` | Modelo da implementação e da revisão: Opus 5.5, para issue de risco ou arquitetura. |

As labels `modelo:*` escolhem o modelo da implementação e da revisão ([ADR 0013](../../docs/adr/0013-modelo-por-etapa-e-por-issue.md), tabela em [`skills/avancar/modelos.md`](../avancar/modelos.md)). Elas **não mudam o estado** da issue e não entram em nenhuma condição da tabela de estados. A triagem aplica uma; o usuário pode trocá-la até aplicar `spec-aprovada`; o `avancar` a troca quando uma falha de qualidade sobe o modelo. Sem label de modelo, vale `sonnet`.

## Estados
Avalie de cima para baixo; vale a primeira linha cuja condição for verdadeira.

Os agentes comentam com a mesma conta do GitHub do usuário, então o autor não serve para distinguir os dois. **Comentário do agente** é o que começa com um marcador `<!-- fabrica:<etapa> -->` (`triagem`, `spec`, `implementar`, `revisar`, `backlog`, `lancamento`) ou com o marcador de ação externa `<!-- fabrica:acao` ([Ação externa](#ação-externa)); **comentário do usuário** é qualquer outro, exceto o comentário de lição e o de [recusa de par](#backlog), que não são de nenhum dos dois. A regra vale na issue e no PR, onde contam os comentários da conversa, as reviews e os comentários em linha. Toda review do usuário conta, mesmo sem corpo: um comentário em linha avulso cria uma review `COMMENTED` de corpo vazio, e é por ela que o `/fabrica:status` o enxerga. A exceção é a review `APPROVED` de corpo vazio, que não é comentário do usuário; com corpo, ela conta. "Resposta nova" é um comentário do usuário posterior ao último comentário do agente com o marcador citado. "Pedido novo no PR" é um comentário ou review do usuário no PR posterior à referência do último comentário `<!-- fabrica:revisar -->` da conversa do PR. A referência é o instante da linha `**Pedidos lidos até:**` desse comentário, ou a data dele quando a linha falta. Sem esse comentário, todo comentário do usuário no PR conta. O **comentário de lição** começa com `<!-- fabrica:licao` ([formato](../licao/formato.md)) e é ignorado em todas as regras de estado: não é comentário do agente nem do usuário, não é resposta nova, não é o último comentário do agente e não é pedido novo no PR. A label `licao` também não entra em nenhuma condição da tabela. O **comentário do dispatcher**, que começa com `<!-- fabrica:dispatcher -->` e registra uma falha do workflow do GitHub Actions ([guia](../../docs/guias/dispatcher.md)), é ignorado do mesmo jeito: não é comentário do agente nem do usuário e não é resposta nova, então não muda o estado da issue. A **linha de custo** `<!-- fabrica:custo ... -->`, que as etapas acrescentam no fim dos seus comentários com o início, o fim e os tokens da execução, só serve ao `/fabrica:metricas`: ela não muda o estado da issue nem o tipo do comentário, que continua sendo decidido pelo marcador da primeira linha.

A **spec da issue** e a **branch da issue** vêm de um destes comentários, nesta ordem:
- o comentário `<!-- fabrica:spec -->` mais recente: a spec é o arquivo que ele cita, e a branch é o `**Branch:**` dele;
- sem comentário de spec, o comentário de triagem mais recente, quando ele tem `**Atalho:** sim`: a spec é a seção `### Spec curta` dele, e a branch é o `**Branch:**` dela ([Atalho](#atalho)).

Toda etapa e todo comando que lê a spec, a branch ou o PR de uma issue usa esta regra.

A branch da issue vive na **worktree da issue**, `<clone>/.worktrees/<nº>`, criada pela primeira etapa que precisa dela e removida depois do PR fechado pelo `scripts/issue-worktree.sh` ([ADR 0014](../../docs/adr/0014-uma-worktree-por-issue.md)). As etapas trabalham nela e nunca trocam a branch do clone principal.

| # | Condição | Estado | Quem age | Próximo passo |
|---|---|---|---|---|
| 1 | `escalonado` | Bloqueado | usuário | Ler o último comentário do agente na issue (ou no PR) e decidir; depois retomar a etapa que parou. |
| 1a | `acao-externa` com item desmarcado no comentário de ação | Ação externa pendente | usuário | Fazer os passos da checklist do comentário de ação e marcar cada item. |
| 1b | `acao-externa` com todos os itens do comentário de ação marcados | Ação concluída | agente | `/fabrica:<etapa do marcador> <nº>` |
| 2 | sem marcador de triagem | Aguardando triagem | agente | `/fabrica:triagem <nº>` |
| 3 | `precisa-info` sem resposta nova | Perguntas abertas | usuário | Responder as perguntas na issue. |
| 4 | `precisa-info` com resposta nova | Respostas recebidas | agente | `/fabrica:triagem <nº>` (ou `/fabrica:spec <nº>`, se as perguntas vieram da spec) |
| 5 | sem `spec-pronta`, sem `spec-aprovada` e sem marcador de spec | Triada | agente | `/fabrica:spec <nº>` |
| 6 | `spec-pronta` sem `spec-aprovada`, com resposta nova ao marcador de spec ou, no atalho, sem comentário de spec, com resposta nova ao marcador de triagem | Ajuste da spec pedido | agente | `/fabrica:spec <nº>` |
| 7 | `spec-pronta` sem `spec-aprovada` | Spec para aprovar | usuário | Revisar a spec e aplicar `spec-aprovada` ou comentar ajustes. No atalho, a spec é a spec curta da triagem, e comentar pede a spec completa. |
| 8 | `spec-aprovada` e nenhum PR da branch | Em implementação | agente | `/fabrica:implementar <nº>` (se não houver `em-andamento` recente) |
| 9 | PR em rascunho | Revisão automática com pendências | usuário | Ler os achados pendentes no PR e decidir. Se o PR não lista achados pendentes e tem CAs com ⏳ "aguardando o CI", o `/fabrica:revisar` parou enquanto esperava o CI, que é a reserva quando o ambiente da etapa não roda a verificação de integração ([ADR 0011](../../docs/adr/0011-verificacao-de-integracao-na-etapa.md)): retome com `/fabrica:revisar <nº>`. |
| 10 | PR aberto com CI falhando | CI vermelho | agente | `/fabrica:revisar <nº>` |
| 11 | PR aberto com review `CHANGES_REQUESTED` ou com pedido novo no PR. Com a conta do usuário, o caminho é o comentário: o GitHub não deixa o autor pedir mudanças no próprio PR; a review vale para PR aberto por outra conta, como um bot | Ajustes do PR pedidos | agente | `/fabrica:revisar <nº>` |
| 12 | PR aberto sem `pronto-revisao` | Em revisão automática | agente | `/fabrica:revisar <nº>` (se não houver `em-andamento` recente) |
| 13 | PR aberto com `pronto-revisao` | PR para revisar | usuário | Revisar o PR e fazer o merge com squash. |

## Ação externa
Quando o `implementar` ou o `revisar` depende de uma ação do usuário fora do GitHub (criar conta ou projeto, cadastrar secret, gerar chave), a etapa publica na issue um **comentário de ação**, com o marcador `<!-- fabrica:acao etapa=<implementar|revisar> -->` e uma checklist, aplica `acao-externa` e para ([ADR 0012](../../docs/adr/0012-acao-externa-com-checklist.md)). O formato do comentário e a retomada estão em [acao-externa.md](acao-externa.md).
- **Leitura:** as linhas 1a e 1b usam o comentário de ação mais recente, lido por `python3 <diretório base da skill>/../../scripts/acao-status.py <comentários.json>`, com os comentários de `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp`. A saída `estado=pendente` é a linha 1a, e `estado=concluida` é a 1b. As saídas `sem-comentario`, `sem-itens` e `etapa-invalida` são [inconsistências](#inconsistências).
- **Gesto do usuário:** marcar os itens na própria checklist, editando o comentário. Não é preciso comentar.
- **Precedência:** com `escalonado` e `acao-externa` ao mesmo tempo, vale o `escalonado` (linha 1).
- A label `acao-externa` sai na retomada, pela etapa do marcador. Até lá, o `/fabrica:metricas` conta o tempo como espera do usuário.
- Fora das issues com `agente`, a issue de runbook do `/fabrica:lancamento` também usa o comentário de ação, com `etapa=lancamento`, lido com `acao-status.py --lancamento` ([Lançamento](#lançamento)). Numa issue com `agente`, `etapa=lancamento` continua sendo `etapa-invalida`.

## Etapa em andamento
A label `em-andamento` não é um estado: a issue continua no estado da tabela acima, e a label só diz que uma execução automática, como o `/fabrica:avancar` ou o dispatcher do GitHub Actions, está rodando uma etapa nela ([ADR 0003](../../docs/adr/0003-sinal-de-etapa-em-andamento.md)).
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

## Lançamento
Issue aberta **sem `agente`**, com o marcador `<!-- fabrica:lancamento -->` na primeira linha do corpo e a label `acao-externa`, criada por `/fabrica:lancamento` antes da primeira ida do projeto para produção ([lancamento](../lancamento/SKILL.md)). Ela fica fora da tabela de estados acima, que vale só para issues com `agente`, e fora do `/fabrica:avancar`: só o usuário dispara a etapa.

O estado sai do comentário de ação `<!-- fabrica:acao etapa=lancamento -->` mais recente, lido por `python3 <diretório base da skill>/../../scripts/acao-status.py --lancamento <comentários.json>`:

| Estado | Condição | Quem age | Próximo passo |
|---|---|---|---|
| Runbook pendente | `acao-externa` e `estado=pendente` | usuário | Fazer os passos da checklist em produção e marcar cada item. |
| Runbook concluído | `acao-externa` e `estado=concluida` | agente | `/fabrica:lancamento <nº>` |

- **Fim:** a retomada com a checklist concluída remove `acao-externa`, comenta "Lançamento concluído" e fecha a issue como `completed`. Uma issue de runbook fechada como `completed` marca o primeiro lançamento como feito, e a etapa não gera outro runbook. Fechada como `not planned`, a issue foi descartada e não bloqueia um runbook novo.
- **Comentários:** os da etapa começam com `<!-- fabrica:lancamento -->`, e o de ação, com `<!-- fabrica:acao etapa=lancamento -->`.
- **Inconsistências:** issue de runbook aberta sem `acao-externa`, ou com as saídas `sem-comentario`, `sem-itens` ou `etapa-invalida` do `acao-status.py --lancamento`.

## Inconsistências
Sinalize como alerta, sem tentar corrigir:
- `spec-aprovada` sem spec da issue (nem comentário de spec, nem triagem com atalho), ou marcador de spec sem a branch que ele cita. No atalho, a branch só nasce no `/fabrica:implementar`, e a falta dela antes disso não é inconsistência.
- `pronto-revisao` sem PR aberto.
- `acao-externa` sem comentário de ação, com um comentário de ação sem itens de checklist ou com uma etapa no marcador fora de `implementar` e `revisar` (saídas `sem-comentario`, `sem-itens` e `etapa-invalida` do `acao-status.py`). Na issue de runbook, valem as inconsistências da seção [Lançamento](#lançamento).
- `spec-pronta` e `spec-aprovada` ao mesmo tempo é normal (nem a spec nem a triagem do atalho removem a primeira); não é inconsistência.
- PR fechado sem merge com a issue ainda aberta.
- Duas ou mais labels `modelo:*` na mesma issue (o `stage-model.sh` sai com código 2). O usuário remove a que não vale.
- `em-andamento` aplicada há 2 h ou mais (label esquecida). Ao contrário das outras, esta não tira a issue do fluxo: uma execução automática pode retomá-la ([Etapa em andamento](#etapa-em-andamento)).
