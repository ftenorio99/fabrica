# ADR 0012: Ação externa com checklist no comentário e label acao-externa

**Status:** aceito · **Data:** 2026-11-17 · **Origem:** issue #95

## Contexto
A F3 do PRD pede um bloqueio próprio para quando o agente depende de uma ação do usuário fora do GitHub: criar conta ou projeto, cadastrar secret, gerar chave. O `precisa-info` serve a perguntas, e a retomada dele depende de um comentário novo do usuário. O `escalonado` serve a falhas e decisões. Nenhum dos dois descreve uma ação que se conclui fora do GitHub e que o usuário só precisa marcar como feita. O estado da fábrica fica todo no GitHub (labels, marcadores e PR), e o dispatcher da F5 vai ler o mesmo estado para saber quando retomar.

## Decisão
A etapa que precisa da ação, o `implementar` ou o `revisar`, publica na issue um comentário com o marcador `<!-- fabrica:acao etapa=<etapa> -->` e uma checklist de passos, que leva nomes e lugares, nunca valores de segredo, e aplica a label `acao-externa`. A issue fica no estado "Ação externa pendente", do usuário, enquanto houver item desmarcado no comentário de ação mais recente, e passa a "Ação concluída", do agente, quando todos estão marcados. A etapa do marcador retoma, confere o que dá para conferir sem ler valores e remove a label. Os dois estados ficam logo depois do `escalonado`, como linhas 1a e 1b, e um script (`scripts/acao-status.py`) faz a contagem para todas as skills.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Reusar o `precisa-info`, diferenciado pelo marcador | As linhas 3 e 4 dependem de "resposta nova", que marcar a checklist não produz, e o `/fabrica:metricas` e a statusline teriam que ler comentários para separar os casos. |
| Usar o `escalonado` | Mistura uma espera prevista com falhas, e o `/fabrica:retro` passaria a contar a ação como escalonamento. |
| Retomar por um comentário do usuário ("feito") | Duplica o gesto: o usuário já marcou os itens. A F5 lista a checklist concluída como o gesto. |
| Renumerar a tabela de estados | Muda os números citados no `avancar`, no `status` e nas specs anteriores, sem ganho. |

## Consequências
- O comentário de ação conta como comentário do agente nas regras de estado.
- O `/fabrica:setup` cria a label pela tabela de `estados.md`, sem passo novo.
- O tempo entre o último item marcado e a retomada conta como espera do usuário, como no `precisa-info`.
- O dispatcher (#107) precisa tratar a edição do comentário de ação (`issue_comment.edited`) como gesto do usuário, apesar do marcador `<!-- fabrica:`, quando a checklist ficar completa.
- Nenhum comentário da fábrica pode trazer o valor de um segredo: a checklist cita só o nome e onde cadastrar.
