# SPEC-76: Casos-limite no status, no backlog e no PRD com issues fechadas e pares recusados

**Issue:** #76 · **PRD:** — (o fabrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-06

## Contexto
As revisões automáticas dos PRs #21 (backlog) e #36 (mudanças de requisitos) deixaram cinco sugestões não aplicadas que continuam valendo na `main`. São casos raros, mas cada um leva a uma leitura errada do estado ou a trabalho repetido:
- o `/fabrica:status` não enxerga uma issue de backlog já fechada;
- o `/fabrica:backlog` esquece um possível par recusado e não prevê o `--force-with-lease` depois de um PR fechado sem merge;
- o `/fabrica:prd` não separa a issue fechada como concluída da fechada como "not planned", e corta a lista de PRs em 200.

## Objetivo
O status reconhece como "item com issue" o item cuja issue de backlog já foi fechada. O backlog lembra os possíveis pares recusados e recomeça a branch `docs/backlog` depois de qualquer PR que não esteja aberto. O PRD indica a ação certa para a issue fechada como "not planned" e lê os PRs sem corte em 200.

## Comportamento esperado
**1. Status: item com issue fechada.** Hoje o `/fabrica:status` só busca issues de backlog abertas. Um item cuja issue foi fechada antes do merge do PR `docs/backlog`, ainda sem ` · #<nº>` no PRD da `main`, aparece como "sem issue". Isso adia o alerta de backlog acabando e trava o marco atual. Para cada repositório com PRD, o status passa a ler todas as issues com o marcador, abertas e fechadas, com `gh issue list -R <repo> --state all --limit 1000 --json number,state,body`, filtrando pelo marcador `<!-- fabrica:backlog item=<n> -->`. Um item é "com issue" se tem uma issue com o marcador, aberta ou fechada, ou a anotação ` · #<nº>` no PRD, como já define `estados.md`. A busca de backlog atual, que procura as issues a puxar, não muda.

**2. Backlog: possível par recusado.** Quando o usuário escolhe "Aplicar sem os possíveis pares", o backlog comenta em cada issue de possível par recusado:

```markdown
<!-- fabrica:backlog par-recusado item=<n> -->
Esta issue não é o item <n> do fatiamento ("<título do item>"): o par foi recusado no `/fabrica:backlog`. Para desfazer, apague este comentário.
```

No passo 2, uma issue com esse comentário, para o mesmo `<n>`, não vira possível par desse item. O par exato, de título igual, continua valendo mesmo com o comentário: ele não passa pela confirmação de possível par.

| Situação | Resultado |
|---|---|
| Possível par sem comentário de recusa | Entra no plano, como hoje. |
| Possível par recusado nesta execução | Ganha o comentário de recusa e não volta nas execuções seguintes. |
| Comentário de recusa apagado pelo usuário | O possível par volta ao plano. |
| Issue recusada para o item 5 e parecida com o item 7 | Pode virar possível par do item 7, porque a recusa vale por item. |

**3. Backlog: `--force-with-lease`.** No passo 5.6, sem PR aberto de `docs/backlog`, a branch recomeça da `main`. Se já existir uma branch `docs/backlog` remota, por PR mergeado, por PR fechado sem merge ou sem PR nenhum, o push é feito com `--force-with-lease`.

**4. PRD: issue fechada.** A tabela de ações do passo 2 do `/fabrica:prd` separa a issue fechada pelo `stateReason`, lido na consulta de issues, que passa a pedir esse campo:

| Situação da issue do item | Ação indicada |
|---|---|
| Fechada como concluída (`COMPLETED`) | Abrir uma issue nova de `feat` ou `fix`; nunca alterar a anterior (como hoje). |
| Fechada como "not planned" (`NOT_PLANNED`) | Se o item continua no PRD, reabrir a issue (`gh issue reopen <nº>`), que mantém o marcador e volta ao backlog. Se o item sai, só ajustar o PRD. |

A reabertura é uma ação indicada no relatório, para o usuário decidir: o `/fabrica:prd` não reabre nada sozinho. Um `stateReason` vazio ou desconhecido conta como concluída.

**5. PRD: lista de PRs.** A consulta passa de `gh pr list --state all --limit 200` para `--limit 1000`, como a de issues. Se vierem 1000 PRs, o relatório avisa que a lista pode ter sido cortada.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O passo 1 de `skills/status/SKILL.md` lê, para cada repositório com PRD, as issues com o marcador em qualquer estado (`gh issue list -R <repo> --state all --limit 1000 --json number,state,body`). O passo 2 usa essa lista para decidir "item com issue". | manual: leitura do diff |
| CA2 | Ponta a ponta: no kairo, o `/fabrica:status` carregado da branch (`claude --plugin-dir ~/projetos/fabrica`) mostra o marco M4 sem item sem issue. O resultado tem de ser igual ao de hoje, porque todos os itens do M4 têm ` · #<nº>` no PRD: não há regressão. | manual: execução na branch |
| CA3 | Em `skills/backlog/SKILL.md`, a escolha "Aplicar sem os possíveis pares" publica, em cada possível par, o comentário de recusa no formato acima, pelo `gh issue comment --body-file`. O passo 2 lê os comentários das issues candidatas a possível par e descarta as que têm a recusa para o mesmo item. O par exato não é afetado. | manual: leitura do diff |
| CA4 | O passo 5.6 de `skills/backlog/SKILL.md` usa `--force-with-lease` sempre que existe uma branch `docs/backlog` remota sem PR aberto. | manual: leitura do diff |
| CA5 | Em `skills/prd/SKILL.md`, a consulta de issues pede `stateReason`. A tabela de ações tem as linhas "Fechada como concluída" e "Fechada como not planned" com as ações acima, e o `stateReason` vazio conta como concluída. | manual: leitura do diff |
| CA6 | Em `skills/prd/SKILL.md`, a consulta de PRs usa `--limit 1000`, com o aviso de corte quando vierem 1000. | manual: leitura do diff |
| CA7 | `skills/status/estados.md` cita o comentário `<!-- fabrica:backlog par-recusado item=<n> -->` e diz que ele não muda o estado da issue nem conta como comentário do agente para as regras da tabela de estados. `docs/comandos.md` explica a recusa no `/fabrica:backlog` e a reabertura indicada no `/fabrica:prd`, remetendo às skills. | manual: leitura do diff |
| CA8 | A `version` de `.claude-plugin/plugin.json` sobe para `0.18.0`, e `bash scripts/test-protect-main.sh`, `bash scripts/test-stage-usage.sh`, `bash scripts/test-costs.sh` e `bash scripts/test-check-gh.sh` passam. | manual: rodar os scripts |

## Fora de escopo
- Mudar o formato do PRD ou do plano do backlog.
- Reabrir issues automaticamente no `/fabrica:prd`.
- Recusar pares exatos: eles continuam sendo vinculados como hoje.

## Desenho técnico
**Arquivos e módulos:**
- `skills/status/SKILL.md`: no passo 1, a consulta das issues com marcador em qualquer estado; no passo 2, a decisão de "item com issue" a partir dela.
- `skills/backlog/SKILL.md`:
  - passo 2: o descarte dos possíveis pares com recusa;
  - passo 4: a escolha "Aplicar sem os possíveis pares" passa a gravar a recusa;
  - passo 5: um passo novo, logo depois dos pares confirmados, publica os comentários de recusa;
  - passo 5.6: a regra do `--force-with-lease`.
- `skills/prd/SKILL.md`: no passo 2, o `stateReason` na consulta, as duas linhas de "Fechada" e o `--limit 1000` dos PRs.
- `skills/status/estados.md`: na seção "Backlog", o comentário de recusa e a regra de que ele não muda o estado.
- `docs/comandos.md`: as entradas `/fabrica:backlog` e `/fabrica:prd`.
- `.claude-plugin/plugin.json`: `version` para `0.18.0`.

**Dados:** nenhum. Não há label nova.

**Interfaces:** o comentário `<!-- fabrica:backlog par-recusado item=<n> -->`, no formato de "Comportamento esperado".

**Decisões:**
- A recusa fica num comentário com marcador na issue recusada. Ela não muda o PRD, que o backlog só altera nas anotações, e o usuário a desfaz apagando o comentário. Alternativa descartada: anotar a recusa no PRD, o que quebraria a regra "Não mude nenhuma outra linha do PRD".
- A recusa vale por item, não por issue: uma issue pode não ser o item 5 e ainda ser o item 7. Alternativa descartada: excluir a issue de todo pareamento, o que esconderia um par legítimo.
- Recusa só pela escolha "Aplicar sem os possíveis pares", que já existe. Alternativa descartada: perguntar par a par, o que mudaria o formato do plano e da confirmação (fora do escopo).
- "Not planned" indica reabrir a issue, e não abrir uma nova. A issue reaberta mantém o marcador `item=<n>`, e duas issues com o mesmo marcador confundiriam o backlog e o status. Alternativa descartada: abrir uma issue nova, como na concluída.
- `--force-with-lease` para qualquer branch remota sem PR aberto: cobre o PR mergeado, o fechado sem merge e a branch órfã com uma regra só. Alternativa descartada: listar só o caso do PR fechado, que deixaria a branch órfã de fora.
- `--limit 1000` nos PRs, igual ao das issues, com aviso de corte. Alternativa descartada: `gh api --paginate`, que pagina sem limite mas troca o formato dos campos (`head.ref` no lugar de `headRefName`) só nesta consulta.

**Fontes da documentação:**
- gh 2.103.3: `gh issue list --help` (`--state {open|closed|all}`, `--limit`, campo `stateReason` no `--json`) e `gh pr list --help` (`--state {open|closed|merged|all}`, `--limit`), conferidos nesta máquina.
- Valores `COMPLETED` e `NOT_PLANNED` do `stateReason`: não verificados numa issue real nesta etapa. Na implementação, confira com `gh issue list --state closed --json stateReason` numa issue fechada como "not planned".

**ADR:** nenhum.

## Testes
- CA1 e CA3 a CA7: leitura do diff, conferindo cada trecho citado no desenho técnico.
- CA2: `/fabrica:status` real no kairo com o plugin da branch.
- CA8: os quatro scripts de teste.

## Riscos e dúvidas
- **Comentário de recusa numa issue do fluxo:** um possível par pode ser uma issue com `agente`. O comentário começa com `<!-- fabrica:backlog`, que hoje é um marcador de agente em `estados.md`. O CA7 o exclui das regras de estado, para ele não virar o "último comentário do agente" de uma etapa.
- **Custo da leitura de comentários:** o passo 2 do backlog passa a ler os comentários das issues candidatas a possível par, só delas, que são poucas.
- **Conflito de versão:** a #69, a #70, a #71, a #75 e a #79 também sobem a versão. A que entrar depois ajusta o número no rebase.

## Histórico
- 2026-11-06: criação.
- 2026-11-06: aprovada.
