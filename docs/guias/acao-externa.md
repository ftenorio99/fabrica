# Ação externa

Um agente parou porque precisa que você faça algo fora do GitHub: criar uma conta ou um projeto num serviço, cadastrar um secret ou uma variável no repositório, gerar uma chave de API. A issue tem a label `acao-externa`, e o `/fabrica:status` a mostra na seção "Ações externas", com quantos passos você já marcou.

## O que fazer
1. **Abra o comentário de ação** na issue. Ele começa com "Ação externa pendente", diz por que a etapa precisa da ação e traz uma checklist de passos, com onde fazer cada um.
2. **Faça cada passo** no serviço ou nas configurações do repositório. O comentário cita só o nome do secret ou da variável e onde cadastrar. O valor fica com você: não o cole na issue.
3. **Marque cada item** na própria checklist, editando o comentário. Não é preciso comentar.
4. **Com todos marcados, retome:** rode `/fabrica:avancar <nº>`, ou o comando da etapa que parou (`/fabrica:implementar <nº>` ou `/fabrica:revisar <nº>`). A etapa confere o que dá para conferir sem ler valores, como o nome do secret em `gh secret list`, tira a `acao-externa` e continua de onde parou.

## Se um passo não der para fazer
Comente na issue o que aconteceu e rode a etapa. Ela lê o seu comentário e publica uma checklist nova, por outro caminho, ou escala com as opções e uma recomendação, como numa [issue escalonada](issue-escalonada.md).

## Diferença para as outras esperas
| Situação | Label | Como você responde |
|---|---|---|
| A triagem ou a spec têm perguntas | `precisa-info` | Comentando na issue |
| O agente parou por falha ou desvio da spec | `escalonado` | Decidindo e comentando; veja [Issue escalonada](issue-escalonada.md) |
| O agente precisa de uma ação sua fora do GitHub | `acao-externa` | Fazendo os passos e marcando a checklist |

O formato do comentário e a retomada estão em [`skills/status/acao-externa.md`](../../skills/status/acao-externa.md), e os estados, em [`estados.md`](../../skills/status/estados.md#ação-externa). A decisão está no [ADR 0012](../adr/0012-acao-externa-com-checklist.md).
