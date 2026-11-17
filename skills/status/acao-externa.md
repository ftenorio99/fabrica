# Ação externa

Contrato entre as etapas que param por uma ação do usuário fora do GitHub (`/fabrica:implementar` e `/fabrica:revisar`) e quem lê o estado (`/fabrica:status`, `/fabrica:avancar` e a própria etapa na retomada). O estado está em [estados.md](estados.md#ação-externa), e a decisão, no [ADR 0012](../../docs/adr/0012-acao-externa-com-checklist.md).

## Quando usar
A etapa só consegue seguir depois de uma ação que o usuário faz fora do GitHub e que o agente não pode nem deve fazer: criar uma conta ou um projeto num serviço, cadastrar um secret ou uma variável no repositório, gerar uma chave de API, ligar uma integração.

Não é ação externa:
- uma pergunta ou uma decisão: vale o `escalonado` (desvio relevante) ou, antes da spec, o `precisa-info`;
- a saída de um comando que o usuário roda e cola na issue: vale a "verificação pedida ao usuário" do `revisar`;
- uma falha que o agente pode corrigir.

## Comentário de ação
Publique na issue (`gh issue comment <nº> --body-file <arquivo>`), neste formato:

```markdown
<!-- fabrica:acao etapa=<implementar|revisar> -->
## Ação externa pendente

**Por que:** <o que a etapa precisa, para qual CA, e o que acontece depois>

**Passos:**
- [ ] <o que fazer, onde fazer (com link), com o nome do secret, da variável ou do recurso>
- [ ] <...>

Marque cada item aqui mesmo quando concluir, editando este comentário. Com todos marcados, rode `/fabrica:avancar <nº>` (ou `/fabrica:<etapa> <nº>`). Se um passo não der para fazer como está descrito, comente na issue e rode a etapa: ela propõe outro caminho ou escala.
```

- **Marcador:** a primeira linha, com a etapa que vai retomar. Só `implementar` e `revisar` valem.
- **Itens:** pelo menos um, cada um com uma ação só, na ordem em que o usuário faz. O `acao-status.py` conta as linhas `- [ ]`, `- [x]` e `- [X]` (também com `*` e com indentação) e ignora as que estão dentro de blocos de código. Não ponha um exemplo de checklist fora de bloco de código.
- **Linha de custo:** logo antes de publicar, acrescente ao fim do arquivo a linha de custo da etapa, como num escalonamento.
- **Segredos:** nenhum item, motivo ou comentário de retomada traz o valor de um segredo. Cite só o nome (ex.: `VERCEL_TOKEN`) e onde cadastrar (ex.: Settings › Secrets and variables › Actions). Se o usuário colar um valor num comentário, não o repita em comentário, commit nem log.

## Parar
1. Faça commit e push do que já existe na branch.
2. Publique o comentário de ação.
3. Aplique a label: `gh issue edit <nº> --add-label acao-externa`.
4. Pare e diga no chat que a checklist está na issue.

A ação externa não gera lição e não conta como rodada de correção.

## Retomar
Quando a etapa começa com `acao-externa` na issue, leia o estado com `gh api repos/<dono>/<repo>/issues/<nº>/comments --paginate --slurp > <arquivo>` e `python3 <diretório base da skill>/../../scripts/acao-status.py <arquivo>`:

| Situação | O que fazer |
|---|---|
| `estado=concluida` | Confira o que dá para conferir sem ler valores (ex.: o nome em `gh secret list` ou `gh variable list`). Se a conferência passar, ou se não houver o que conferir, remova a label (`gh issue edit <nº> --remove-label acao-externa`) e siga do ponto em que a etapa parou |
| `estado=concluida`, mas a conferência falha | Publique um novo comentário de ação só com os passos que faltam, mantenha `acao-externa` e pare |
| `estado=pendente`, sem comentário do usuário depois do comentário de ação | Não faça nada na issue: diga no chat que a ação está pendente e pare |
| `estado=pendente`, com comentário do usuário depois do comentário de ação | Leia o comentário. Se der para seguir por outro caminho, publique um novo comentário de ação. Se não der, é desvio relevante: remova `acao-externa`, aplique `escalonado` e comente as opções, com uma recomendação |
| `sem-comentario`, `sem-itens` ou `etapa-invalida` | Inconsistência: não siga a etapa. Diga no chat o que o script devolveu e pare |

"Comentário do usuário" segue a definição de [estados.md](estados.md): os comentários de lição e de recusa de par não contam.
