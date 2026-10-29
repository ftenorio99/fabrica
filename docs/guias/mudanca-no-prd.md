# Mudança no PRD

O produto mudou depois que o backlog foi criado: uma funcionalidade nova, uma que saiu ou uma regra diferente.

1. **Atualize o PRD:** no clone, rode `/fabrica:prd`. Ele mostra um resumo do PRD atual e pergunta o que mudou. Só as seções afetadas são alteradas, e a mudança entra no histórico.
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
   - **Issue com spec aprovada:** remova `spec-aprovada`, rode `/fabrica:spec <nº> <ajuste>` e aprove de novo.
   - **Issue já mergeada:** a mudança vira uma issue nova.

Detalhes: [`skills/prd/SKILL.md`](../../skills/prd/SKILL.md), [`skills/backlog/SKILL.md`](../../skills/backlog/SKILL.md).
