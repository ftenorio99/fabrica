# ADR 0017: Leitor de estado em código para o dispatcher

**Status:** proposto · **Data:** 2026-11-19 · **Origem:** issue #107

## Contexto
A retomada por evento do dispatcher (#107) faz o workflow acordar a cada gesto do usuário na issue ou no PR e precisa decidir qual etapa rodar. A fonte da verdade do estado é a tabela de [estados.md](../../skills/status/estados.md), hoje interpretada pelos agentes e pelo `/fabrica:status` a partir das labels, dos marcadores de comentário e do PR da branch.

A decisão tem de ser determinística e barata, porque acontece a cada evento, e tem de cobrir a tabela inteira: o estado 4 distingue triagem de spec pelo último comentário do agente, os estados 8 a 13 dependem do PR, e as linhas 1a e 1b dependem da checklist de ação externa. A tabela muda com o fluxo; a [#105](../../specs/SPEC-105.md) e a [#106](../../specs/SPEC-106.md) já entregaram o workflow e o isolamento do job, e esta é a primeira etapa que precisa decidir entre todas as etapas.

## Decisão
O dispatcher lê o estado com um programa puro, `scripts/issue-state.py`, que recebe o JSON já coletado pelo `scripts/dispatch.sh` e imprime `linha`, `etapa`, `quem` e `inconsistencia`. O programa reproduz as regras da tabela de estados.md, inclusive a precedência de cima para baixo, e tem testes unitários com pacotes JSON fixos (`scripts/test-issue-state.sh`). O `dispatch.sh` faz a coleta com `gh issue view`, `gh api .../comments` e `gh pr list`, porque é ele que tem o token e o repositório; o programa não faz rede.

A tabela de estados.md e o `issue-state.py` passam a ter de mudar no mesmo PR. O programa não confere a existência da branch citada por um comentário de spec: a etapa que precisa dela para no caso "sem avanço", e essa diferença fica registrada na spec da #107.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Chamar `/fabrica:status` num `claude -p` a cada evento e interpretar a resposta | Gasta assinatura e tempo a cada gesto, depende de um modelo para uma decisão determinística e não tem teste unitário barato. |
| Repetir as regras em `if:` do workflow, por evento | Duplicaria a tabela de estados no YAML e não cobriria os estados que dependem do conteúdo do PR e dos comentários. |
| Usar a API GraphQL e resolver tudo em `jq` no workflow | Espalha a lógica por expressões do YAML, difíceis de testar, e mistura coleta e decisão. |
| Manter o estado numa label ou num arquivo do projeto | Contraria a fonte da verdade de estados.md: o estado é derivado das labels, dos marcadores e do PR. |

## Consequências
- A decisão do dispatcher fica testável sem rede e sem `claude`, e o `dispatch.sh` fica responsável só pela coleta e pelas ações (labels, comentários e etapas).
- Toda mudança na tabela de estados passa a exigir a mudança correspondente no `issue-state.py` e no `scripts/test-issue-state.sh`, sob pena de o dispatcher divergir do `/fabrica:status`. O teste da tabela e o código precisam entrar no mesmo PR.
- O leitor cobre as linhas 1 a 13, com a precedência de `escalonado`, mas não confere a existência da branch citada pela spec; essa verificação continua sendo da etapa que usa a branch.
- A coleta de PRs inclui `statusCheckRollup`, `reviews`, `comments`, `reviewDecision`, `isDraft` e `updatedAt`; os campos têm de continuar existindo na ajuda do `gh` da versão usada no runner.
