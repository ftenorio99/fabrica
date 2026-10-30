# SPEC-38: Tratar no fluxo os ajustes pedidos pelo usuário no PR

**Issue:** #38 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-10-30

## Contexto
Quando o usuário revisa um PR da fábrica e quer mudanças, o ciclo não fecha:
- **Estado 11 de `skills/status/estados.md` ("Ajustes do PR pedidos"):** conta com uma review `CHANGES_REQUESTED`, que o dono do PR não consegue fazer no próprio PR. Os agentes usam a conta do usuário.
- **Comentários no PR:** a outra condição do estado é "comentário do usuário depois de `pronto-revisao`", mas o `/fabrica:status` não lê os comentários do PR (só `gh pr list ... reviewDecision`). Por isso, ele não detecta o estado.
- **`description` do `/fabrica:revisar`:** promete "revisar de novo depois de mudanças pedidas no PR", mas a skill não lê os comentários do PR.
- **Manual:** o guia `docs/guias/revisar-pr.md` contorna isso e manda o usuário pedir a correção ao Claude na sessão.

Na triagem, o usuário escolheu que o `/fabrica:revisar` passa a tratar os comentários (opção a) e que `CHANGES_REQUESTED` fica na condição do estado 11.

## Objetivo
O usuário comenta no PR e roda `/fabrica:revisar <nº>`. A skill corrige o que cabe na spec, escala o que muda a spec e responde no PR, e o `/fabrica:status` mostra o estado certo antes e depois.

## Comportamento esperado

### Termos
- **Comentário do usuário no PR:** um comentário da conversa do PR, uma review com corpo ou um comentário em linha (inline) que não começa com um marcador `<!-- fabrica:<etapa> -->`. Vale a mesma regra do `estados.md` para issues.
- **Âncora:** o último comentário com `<!-- fabrica:revisar -->` na conversa do PR.
- **Pedido novo:** comentário do usuário no PR posterior à âncora. Sem âncora (PR anterior a esta mudança), todo comentário do usuário no PR conta. A data usada é a de criação do comentário e, na review, a de envio (`submittedAt`).
- **Ajuste:** pedido que se resolve sem incluir, remover ou alterar um CA nem um item de "Fora de escopo" da spec. Exemplos: bug, caso-limite que um CA já cobre, nome, mensagem, teste faltando, documentação, estilo.
- **Mudança de escopo:** pedido que exige incluir, remover ou alterar um CA, ou fazer algo listado em "Fora de escopo". Na dúvida, é mudança de escopo.

### `/fabrica:revisar` com PR aberto
1. **Coletar pedidos novos:** antes da rodada de revisão, se já existir PR da branch, leia os comentários da conversa e as reviews (`gh pr view <nº> --json comments,reviews`) e os comentários em linha (`gh api repos/<dono>/<repo>/pulls/<nº>/comments`). Fique com os pedidos novos.
2. **Classificar:** cada pedido novo é ajuste ou mudança de escopo, com a regra de "Termos".
3. **Ajustes:** corrija na branch, com commit (`fix: ...` ou o tipo adequado) e push. Essas correções não contam como rodada de revisão. Depois, siga a revisão normal (passos 2 a 5 de hoje), que confere tudo contra a spec.
4. **Mudanças de escopo:** não altere o código para elas e não edite a spec. Aplique `escalonado` na issue e indique o caminho: remover `spec-aprovada`, rodar `/fabrica:spec <nº> <ajuste>`, aprovar de novo e retomar. Os ajustes do mesmo lote continuam sendo corrigidos.
5. **Responder no PR:** ao terminar, publique um comentário no PR com `<!-- fabrica:revisar -->`, que vira a nova âncora. Ele traz uma linha por pedido, com um trecho do pedido e o que foi feito: o commit da correção, "mudança de escopo, escalado" com o motivo, ou "não procede" com o motivo.
6. **Primeira vez que o PR fica pronto:** quando a skill aplica `pronto-revisao`, também comenta no PR com `<!-- fabrica:revisar -->`, num resumo de uma linha. Assim a âncora existe desde o início, e os comentários do usuário depois dela contam como pedidos novos.

Sem pedido novo, a skill segue como hoje.

### `estados.md`, linha 11
- **Condição:** PR aberto com review `CHANGES_REQUESTED` ou com pedido novo do usuário no PR (comentário posterior ao último `<!-- fabrica:revisar -->` do PR).
- **Nota:** com a conta do usuário, o caminho é o comentário. O `CHANGES_REQUESTED` vale quando o PR é aberto por outra conta, como um bot no GitHub Actions.
- **Próximo passo:** `/fabrica:revisar <nº>`.
- A definição de comentário de agente e de usuário passa a valer também para os comentários e reviews do PR.

### `/fabrica:status`
Para cada PR aberto de uma issue do fluxo, a coleta lê também `comments` e `reviews` (`gh pr view <nº> -R <repo> --json comments,reviews`) para aplicar a linha 11.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/revisar/SKILL.md` tem um passo, antes da rodada de revisão, que coleta os pedidos novos do PR pelos três caminhos (conversa, reviews e comentários em linha), com os comandos `gh` e a definição de âncora e de pedido novo de "Termos". | manual (leitura) |
| CA2 | A skill classifica cada pedido em ajuste ou mudança de escopo, com a regra de "Termos" e "na dúvida, mudança de escopo". Ajuste é corrigido com commit e push, sem contar como rodada. Mudança de escopo não altera código nem spec, aplica `escalonado` e indica o caminho pelo `/fabrica:spec`. | manual (leitura) |
| CA3 | A skill publica no PR um comentário com `<!-- fabrica:revisar -->` ao aplicar `pronto-revisao` e ao terminar de tratar pedidos, com uma linha por pedido e o que foi feito (commit, escalado ou não procede, com o motivo). | manual (leitura) |
| CA4 | A `description` do `/fabrica:revisar` diz que a skill trata os comentários do usuário no PR. | manual (leitura) |
| CA5 | A linha 11 do `estados.md` tem a condição, a nota e o próximo passo de "Comportamento esperado", e a definição de comentário de agente e de usuário cobre os comentários e reviews do PR. | manual (leitura) |
| CA6 | A coleta do `skills/status/SKILL.md` lê `comments` e `reviews` dos PRs abertos do fluxo, e o comando funciona num PR real. | manual: rodar `gh pr view <nº> --json comments,reviews` num PR da fábrica e conferir os campos `createdAt`/`submittedAt` e `body` |
| CA7 | O manual descreve o ciclo novo (comentar no PR e rodar `/fabrica:revisar`, com mudança de escopo escalada), sem copiar regras nem tabelas da skill: `docs/comandos.md` (seção `revisar`) e `docs/guias/revisar-pr.md` ("Pedir mudanças"). Não sobra frase dizendo que a revisão não lê os comentários do PR. | manual: leitura e `grep -rn "não lê os comentários" docs/` sem resultado |
| CA8 | `.claude-plugin/plugin.json` sobe para `0.10.1`. | manual (leitura) |

## Fora de escopo
- Responder a cada comentário em linha na própria thread. A resposta é um comentário só, na conversa do PR.
- Resolver threads de review (`resolveReviewThread`).
- Disparar o `/fabrica:revisar` automaticamente ao chegar um comentário. Isso é do dispatcher da Fase 1.
- Mudar o `/fabrica:implementar` ou o subagente `revisor`.

## Desenho técnico
**Arquivos e módulos:**
- `skills/revisar/SKILL.md`: `description`, nova seção "Pedidos no PR" antes do passo 2, comentário-âncora no passo 5 e regra nova em "Regras" (não editar a spec por pedido do PR).
- `skills/status/estados.md`: parágrafo da definição de comentário e linha 11.
- `skills/status/SKILL.md`: um item na coleta do passo 1.
- `docs/comandos.md` e `docs/guias/revisar-pr.md`.
- `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:** o comentário-âncora `<!-- fabrica:revisar -->` na conversa do PR passa a fazer parte do contrato entre o `/fabrica:revisar` e o `/fabrica:status`.

**Decisões:**
- **Âncora no último comentário do revisar no PR:** um marcador já é o que separa agente de usuário no resto do fluxo. Alternativa descartada: usar a data em que `pronto-revisao` foi aplicada, que exige ler a timeline da issue (`gh api .../timeline`) e não muda quando a skill responde aos pedidos.
- **Inline lido pela API REST** (`pulls/<nº>/comments`): o `gh pr view --json reviews` traz só o corpo da review, sem os comentários em linha. Para o `/fabrica:status`, basta a review, porque todo comentário em linha cria uma review com `submittedAt`.
- **Resposta num comentário só, na conversa:** é mais simples e serve de âncora. Alternativa descartada: responder em cada thread, que espalha a âncora.

**Fontes da documentação:**
- GitHub CLI (`gh pr view --json comments,reviews`): versão instalada, campos conferidos na execução contra o PR #37. API REST `pulls/{n}/comments`: não verificada no Context7, conferida na execução (devolve a lista).

**ADR:** nenhum.

## Testes
O repositório não tem `make test`: a mudança é texto de skill e manual. A evidência é a leitura de cada CA e os comandos do CA6 e do CA7. A primeira revisão de PR depois do merge serve de teste real do ciclo.

## Riscos e dúvidas
- **Classificação errada:** um pedido de escopo pode ser tratado como ajuste. O "na dúvida, mudança de escopo" e a revisão contra a spec reduzem o risco.
- **PRs antigos sem âncora:** todo comentário do usuário conta como pedido novo, inclusive os já tratados à mão. É aceitável, porque só há PRs assim enquanto a mudança é nova, e a resposta da skill cria a âncora.

## Histórico
- 2026-10-30: criação.
- 2026-10-30: aprovada.
