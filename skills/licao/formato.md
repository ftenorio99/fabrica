# Formato da lição

Contrato entre as etapas que registram lições (`/fabrica:triagem`, `/fabrica:implementar`, `/fabrica:revisar`, `/fabrica:licao`) e o `/fabrica:status`, que as conta. Uma lição é um fato do fluxo que vale lembrar na retrospectiva, registrado na hora, junto da evidência.

## Comentário
Um comentário por issue (ou PR) e por gatilho. A primeira linha é o marcador, com o gatilho, e cada lição é um bloco que começa com a data:

```markdown
<!-- fabrica:licao gatilho=<gatilho> -->
**Lição · <AAAA-MM-DD>**
- **O que aconteceu:** <fato, com a evidência: comando, achado, link>
- **Causa provável:** <por que aconteceu>
- **Ação sugerida:** <o que mudar, ou "nenhuma, só registro">
- **Origem:** <usuario | triagem | implementar | revisar>
```

- **Gatilho:** um de `precisa-info`, `escalonado`, `rodadas`, `desvio`, `achado-pendente` ou `usuario`.
- **Marcador próprio:** este comentário começa com `<!-- fabrica:licao`, não com o marcador da etapa que o publica. Ele não conta como comentário do agente nem do usuário em nenhuma regra de estado (veja [estados.md](../status/estados.md)).

## Gatilhos automáticos
| Etapa | Quando | Gatilho |
|---|---|---|
| `triagem` | aplica `precisa-info`; a lição resume as lacunas | `precisa-info` |
| `implementar` | aplica `escalonado` por desvio relevante | `escalonado` |
| `implementar` | precisou de 2 ou mais rodadas de correção em `make lint`/`make test`, tenha passado ou escalado | `rodadas` |
| `implementar` | um desvio que vai para "Desvios da spec" mudou o desenho técnico (arquivo, interface ou decisão) ou veio de erro ou lacuna da spec; um bloco por desvio | `desvio` |
| `revisar` | aplica `escalonado` por um pedido no PR que muda a spec | `escalonado` |
| `revisar` | precisou de 2 ou mais correções por CI vermelho | `rodadas` |
| `revisar` | um achado `bloqueante` ou `importante` ficou sem corrigir, por discordância ou por pendência; um bloco por achado | `achado-pendente` |

- **Sem lição:** sugestões do revisor e desvios cosméticos (texto, nome, uma linha a mais num arquivo previsto) não geram lição.
- **Um evento, uma lição:** quando um evento cai em dois gatilhos, use o mais específico. Escalonamento por rodadas de correção registra `rodadas`; escalonamento por achados pendentes registra `achado-pendente`. Os demais escalonamentos registram `escalonado`.
- **Onde:** as lições automáticas vão sempre na issue, mesmo quando o evento aconteceu no PR. Cite o PR na evidência.

## Publicar
1. Escreva o bloco com a ferramenta Write na pasta temporária da sessão.
2. Procure um comentário da issue que comece com `<!-- fabrica:licao gatilho=<gatilho> -->`, com o mesmo gatilho: `gh api repos/<dono>/<repo>/issues/<nº>/comments --paginate -q '.[] | select(.body | startswith("<!-- fabrica:licao gatilho=<gatilho> -->")) | .id'`.
   - **Sem comentário:** publique o marcador e o bloco num comentário novo (`gh issue comment <nº> --body-file <arquivo>`).
   - **Com comentário:** é a mesma causa. Não crie outro; monte num arquivo o corpo atual, uma linha `---` e o bloco novo, e edite o comentário existente com `gh api -X PATCH repos/<dono>/<repo>/issues/comments/<id> -F body=@<arquivo>`.
   - **Exceção:** as lições do usuário (`gatilho=usuario`) sempre criam comentário novo.
3. Aplique a label: `gh issue edit <nº> --add-label licao`. Num PR, use `gh api -X POST repos/<dono>/<repo>/issues/<nº>/labels -f 'labels[]=licao'`, porque o `gh pr edit` pode falhar com o aviso de "Projects (classic)".

## Sem efeito no fluxo
Registrar uma lição não aplica nem remove outra label, não interrompe a etapa e não muda o estado da issue. Se o registro falhar, inclusive porque a label `licao` não existe, avise no chat ("não consegui registrar a lição: <motivo>; rode `/fabrica:setup` se faltar a label") e siga a etapa. A regra das skills de parar quando falta uma label não vale para `licao`.
