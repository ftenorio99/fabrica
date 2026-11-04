# SPEC-50: Aplicar os Termos do passo 2 na segunda coleta do /fabrica:revisar

**Issue:** #50 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-04

## Contexto
A SPEC-41 (PR #47) criou uma segunda coleta no passo 6 do `skills/revisar/SKILL.md`, feita antes de publicar a âncora. Os pedidos que chegam durante a rodada vão para a seção "Chegaram durante esta rodada". O texto diz "colete de novo pelos mesmos caminhos do passo 2", mas não diz que o filtro dos "Termos" do passo 2 também vale. Sem isso, a seção pode citar como pedido comentários com marcador do agente, comentários de lição ou reviews sem corpo. A sugestão veio da revisão automática do PR #47.

## Objetivo
A seção "Chegaram durante esta rodada" cita só comentários do usuário no PR, pela mesma definição do passo 2, posteriores ao instante da coleta.

## Comportamento esperado
O item "chegaram durante esta rodada" do passo 6 passa a dizer que a segunda coleta aplica os "Termos" do passo 2. Entra na seção só o **comentário do usuário no PR**, como o passo 2 o define, posterior ao instante da coleta. Ficam de fora:

| Item coletado | Entra na seção? |
|---|---|
| Comentário do usuário (conversa, review com corpo ou comentário em linha) depois do instante da coleta | sim |
| Comentário com marcador `<!-- fabrica:<etapa> -->` | não |
| Comentário de lição (`<!-- fabrica:licao`) | não |
| Review sem corpo, inclusive `APPROVED` | não |
| Comentário do usuário anterior ao instante da coleta | não (já foi tratado no passo 2) |

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O item "chegaram durante esta rodada" do passo 6 de `skills/revisar/SKILL.md` diz que a segunda coleta aplica os "Termos" do passo 2 e que só conta comentário do usuário no PR posterior ao instante da coleta. | manual (leitura) |
| CA2 | O texto não repete a definição de "comentário do usuário no PR": ele remete aos "Termos" do passo 2, para a regra ficar num lugar só. | manual (leitura) |
| CA3 | `.claude-plugin/plugin.json` sobe para `0.11.4`. | manual (leitura) |

## Fora de escopo
- Mudar os "Termos" do passo 2, a regra do `estados.md` ou a coleta do `/fabrica:status`.
- Tratar na mesma execução os pedidos que chegam durante a rodada.
- Mudar o manual em `docs/`, que não descreve a segunda coleta em detalhe.

## Desenho técnico
**Arquivos e módulos:**
- `skills/revisar/SKILL.md`: item "chegaram durante esta rodada" do passo 6.
- `.claude-plugin/plugin.json`: `version`.

**Dados:** nenhum.

**Interfaces:** nenhuma.

**Decisões:**
- **Remeter aos "Termos" em vez de repetir a definição:** uma regra num lugar só evita que as duas cópias se afastem com o tempo. Alternativa descartada: listar de novo as exclusões no passo 6, que duplica o texto do passo 2.

**Fontes da documentação:** nenhuma biblioteca envolvida.

**ADR:** nenhum.

## Testes
O repositório não tem `make test`: a mudança é texto de skill. A evidência é a leitura do CA1 ao CA3.

## Riscos e dúvidas
- Nenhum relevante.

## Histórico
- 2026-11-04: criação.
