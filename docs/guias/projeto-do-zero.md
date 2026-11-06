# Projeto do zero

Da ideia à primeira issue no fluxo.

1. **Crie o repositório**, privado, e clone-o em `~/projetos/<nome>`. O `--clone` clona na pasta atual, então rode a partir de `~/projetos`:
   ```
   cd ~/projetos
   gh repo create <nome> --private --clone
   ```
   O primeiro commit leva o `README.md` e o `.gitignore` da stack. Os hooks do git deixam passar o commit inicial e o primeiro push de um repositório novo. O projeto nasce na LTS mais recente do runtime, conferida na fonte oficial, como manda o [`CLAUDE.md` do projeto](../../templates/CLAUDE.md).
2. **Configure**, se for a primeira vez nesta máquina: rode `/fabrica:setup` para instalar os hooks do git. Veja [Primeiros passos](../primeiros-passos.md).
3. **Escreva o PRD:** no clone, rode `/fabrica:prd <ideia em uma frase>`.
   - **Entrevista:** responda em rodadas. O agente propõe opções, com a recomendação dele primeiro.
   - **Revisão:** revise o PRD inteiro que ele mostra, até aprovar.
   - **Entrega:** aceite o PR na branch `docs/prd` e faça o merge. As labels do fluxo são criadas ao final.
4. **Crie o backlog:** rode `/fabrica:backlog`.
   - **Plano:** confira o plano, com as milestones de todos os marcos e as issues só do marco atual e do seguinte.
   - **Aplicação:** confirme com "Aplicar tudo".
   - **Entrega:** faça o merge do PR `docs/backlog`, que anota no PRD o número de cada issue.
5. **Puxe a primeira issue:** rode `/fabrica:status`. Ele indica a issue de backlog liberada, a de menor número no marco atual com as dependências fechadas. Aplique a label `agente` nela.
6. **Siga o ciclo:** `/fabrica:triagem <nº>`, depois `/fabrica:spec <nº>`, aprove a spec e rode `/fabrica:implementar <nº>`. Veja [Fluxo](../fluxo.md).

Detalhes de cada etapa: [`prd`](../../skills/prd/SKILL.md), [`backlog`](../../skills/backlog/SKILL.md).
