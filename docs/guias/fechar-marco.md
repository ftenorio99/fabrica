# Fechar um marco

As issues do marco atual estão acabando, e é hora de preparar o próximo.

1. **Acompanhe pelo `/fabrica:status`.** A seção "Marcos" mostra o marco atual e o próximo com `fechadas/total`. A seção "Backlog" mostra a próxima issue a puxar.
2. **Espere o alerta "backlog acabando".** Ele aparece quando duas coisas acontecem juntas:
   - o marco atual está perto de fechar, com pelo menos 1 issue fechada e no máximo 2 abertas;
   - o marco depois do próximo ainda não tem issues.
3. **Rode `/fabrica:backlog`.** A janela avança um marco, e o marco depois do próximo ganha as issues dele. Confira o plano, confirme e faça o merge do PR `docs/backlog`.
4. **Puxe a próxima issue.** Quando todas as issues do marco atual fecharem, o próximo marco passa a ser o atual. O `/fabrica:status` sugere a issue de backlog liberada dele: aplique `agente`.
5. **Faça a retrospectiva.** Com o marco fechado, rode `/fabrica:retro <repositório>`. Ele mostra os padrões do que deu errado no marco, com as evidências e uma proposta de mudança no fabrica para cada um. Escolha quais viram issue no fabrica; elas entram no fluxo quando você aplicar `agente`.
6. **Marco bloqueado:** se todas as issues do marco dependerem de issues abertas, o `/fabrica:status` diz qual issue bloqueia. Termine essa primeiro.

As regras exatas, como marco atual, perto de fechar, janela e ordem de sugestão, estão na seção "Backlog" de [`skills/status/estados.md`](../../skills/status/estados.md).

A milestone no GitHub não precisa ser fechada à mão. O marco atual é calculado pelas issues, não pelo estado da milestone.
