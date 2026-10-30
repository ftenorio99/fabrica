# Mudança no PRD

O produto mudou depois que o backlog foi criado: uma funcionalidade nova, uma que saiu ou uma regra diferente.

1. **Atualize o PRD:** no clone, rode `/fabrica:prd`. Ele mostra um resumo do PRD atual e pergunta o que mudou e por quê.
   - **Impacto:** antes de escrever, ele mostra um relatório com cada item afetado, a issue dele, o estado e a ação indicada, além das issues no fluxo que não estão ligadas a nenhum item.
   - **Decisão:** você aceita, rejeita ou adia cada mudança. Só as aceitas alteram o PRD, e todas ficam na tabela "Mudanças" do histórico, com o motivo.
   - **Item novo:** recebe o próximo número livre do fatiamento.
   - **Item removido:** o número dele não volta a ser usado.
   - **Itens com issue:** a anotação ` · #<nº>` continua no PRD.
2. **Faça o merge** do PR `docs/prd`.
3. **Sincronize o backlog:** rode `/fabrica:backlog`. O plano mostra:
   - issues de backlog a atualizar (título, funcionalidade, dependências ou marco);
   - issues novas, se a mudança caiu na janela;
   - issues de itens removidos, com proposta de fechamento, que só fecham com a sua confirmação;
   - **divergências no fluxo:** issues que já têm `agente` e não batem mais com o PRD. Essas não são alteradas: só aparecem para você decidir.
4. **Trate as divergências:**
   - **Issue sem spec aprovada:** rode `/fabrica:spec <nº> <ajuste>`.
   - **Issue com spec aprovada:** remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>` e aprove de novo. A spec registra o tipo e o motivo da mudança e os CAs alterados.
   - **Issue com PR aberto:** decida entre parar (fechar o PR ou pedir ajuste) e seguir, tratando a mudança numa issue nova.
   - **Issue já fechada:** a mudança vira uma issue nova.

Se o `/fabrica:status` avisar que um F mudou 3 ou mais vezes, vale revisitar esse requisito com `/fabrica:prd` antes de mexer nele de novo.

Detalhes: [`skills/prd/SKILL.md`](../../skills/prd/SKILL.md), [`skills/backlog/SKILL.md`](../../skills/backlog/SKILL.md).
