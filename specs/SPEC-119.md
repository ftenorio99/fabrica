# SPEC-119: Dispatcher e skills não colocam texto de issue ou PR no prompt

**Issue:** #119 · **PRD:** F4, F1 · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-10

## Contexto
O system card do Claude Fable 5.2 e Mythos 5.2 (9/nov/2026, §6.5.2) mostra que o modelo tende a obedecer instruções plantadas em texto que chega no turno do usuário, e trata como não confiável o que chega como resultado de ferramenta. O `docs/prd.md` lista a injeção de prompt como risco alto e responde a ele pondo a segurança antes do dispatcher (M1 antes de M2). O dispatcher da Fase 1 (#105, #107) ainda não existe; esta issue fixa a regra que ele vai seguir e corrige a única etapa que hoje espera texto de comentário no argumento, o `/fabrica:spec <nº> <ajustes>`.

## Objetivo
Nenhuma etapa de agente precisa receber texto de issue, PR ou comentário no prompt: o argumento é só o número, e o conteúdo é lido com `gh`, como resultado de ferramenta.

## Comportamento esperado
**Regra.** O prompt de uma etapa de agente, montado pelo `/fabrica:avancar` ou, na Fase 1, pelo workflow do dispatcher, leva só o comando e o número da issue. Corpo de issue, de PR ou de comentário nunca entra no prompt nem num `run:` do workflow (`${{ github.event.issue.body }}`, `${{ github.event.comment.body }}` e afins), o que também evita injeção de comando no shell.

**`/fabrica:spec`.** Os ajustes pedidos passam a vir da issue:

| Situação | O que a spec faz |
|---|---|
| Spec existente e comentários do usuário depois do último `<!-- fabrica:spec -->` | Os comentários são os ajustes pedidos. |
| Atalho, sem comentário de spec, e comentários do usuário depois do comentário de triagem mais recente | Os comentários são os ajustes pedidos, como hoje na saída do atalho. |
| Texto de ajuste também no argumento (uso manual) | Vale junto com os comentários, como ajuste digitado pelo usuário. |
| Spec existente, sem comentário novo do usuário e sem texto no argumento | Não há ajuste pedido: pare sem commit nem comentário e diga no chat que não há ajuste a fazer. |
| Issue triada, sem spec | Primeira rodada, como hoje: não há ajustes a ler. |

"Comentário do usuário" segue a definição de `skills/status/estados.md`: os comentários de lição e de recusa de par não contam.

**`/fabrica:avancar`.** No estado 6, passa só `<nº>` ao `/fabrica:spec`.

**Outras etapas.** `triagem`, `implementar` e `revisar` já recebem só o número e leem a issue e o PR com `gh issue view` e `gh pr view`. Não mudam.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/spec/SKILL.md` traz o argumento de ajustes como opcional, só para uso manual, e manda ler os ajustes nos comentários do usuário depois do último `<!-- fabrica:spec -->` ou, no atalho, do comentário de triagem, somando o texto do argumento quando houver. O comentário de spec publicado diz "Para pedir ajustes, comente aqui e rode `/fabrica:spec <nº>`". | revisão do diff |
| CA2 | `skills/spec/SKILL.md` diz que, com spec existente, sem comentário novo do usuário e sem texto no argumento, a etapa para sem commit nem comentário e avisa no chat que não há ajuste pedido. | revisão do diff |
| CA3 | `skills/avancar/SKILL.md` passa `<nº>` ao `/fabrica:spec` no estado 6, e `skills/status/estados.md` mostra `/fabrica:spec <nº>` como próximo passo do estado 6. | revisão do diff |
| CA4 | Numa issue de teste no próprio repositório, com uma spec publicada e um comentário do usuário depois do `<!-- fabrica:spec -->` pedindo um ajuste, `/fabrica:spec <nº>` sem texto no argumento aplica o ajuste na spec e publica um novo comentário de spec. Rodado de novo sem comentário novo, para sem commit. A issue e a branch de teste são fechadas e apagadas no fim, com um comentário dizendo que era teste. | manual: `claude --plugin-dir <clone>` na branch, com issue de teste |
| CA5 | `docs/adr/0008-texto-externo-fora-do-prompt.md` registra a regra, o motivo (system card, §6.5.2) e as alternativas, com status `proposto` e, no merge, `aceito`. | revisão do diff |
| CA6 | `docs/guias/isolamento-do-agente.md` ganha a seção "Texto de issue e PR fora do prompt", com a regra para o dispatcher (nada de `${{ github.event.* }}` com texto no prompt nem em `run:`), o motivo e o link para a ADR 0008. | revisão do diff |
| CA7 | O `CLAUDE.md` do repositório, em "Escrevendo skills", diz que o argumento de uma etapa de agente é só o número da issue ou do PR, e que o texto vem pelo `gh`. | revisão do diff |
| CA8 | `docs/comandos.md` descreve o `/fabrica:spec` com os ajustes lidos dos comentários e o argumento opcional; `docs/principios.md` ganha um parágrafo curto sobre a regra, com link para a ADR 0008; `.claude-plugin/plugin.json` em `0.30.0`. | revisão do diff |
| CA9 | `grep -rn 'ARGUMENTS' skills/triagem skills/implementar skills/revisar` mostra só o número da issue como argumento, e cada uma lê a issue com `gh issue view` (e o PR com `gh pr view`, no revisar). | revisão do diff (conferência, sem mudança esperada) |

## Fora de escopo
- O isolamento do job do dispatcher e as credenciais (#106, #94).
- O workflow do dispatcher em si (#105, #107), que vai seguir a regra desta issue.
- As instruções que mandam o usuário rodar `/fabrica:spec <nº> <ajuste>` à mão (`docs/guias/`, `skills/prd`, `skills/implementar`, `skills/revisar`): o texto digitado pelo usuário no chat é dele, e o argumento continua aceito.
- Os comandos que recebem texto do próprio usuário por natureza (`/fabrica:prd <ideia>`, `/fabrica:licao <nº> <texto>`), que não são etapas do dispatcher.

## Desenho técnico
**Arquivos e módulos:**
- `skills/spec/SKILL.md`: `argument-hint` e linha "Argumentos"; passo 1 (saída do atalho) e passo 3 (Ler), com a tabela de situações acima; a regra de parar sem ajuste; o texto final do comentário do passo 5.
- `skills/avancar/SKILL.md`: linha do estado 6 da tabela do passo 3.
- `skills/status/estados.md`: próximo passo do estado 6.
- `docs/adr/0008-texto-externo-fora-do-prompt.md`: novo.
- `docs/guias/isolamento-do-agente.md`: seção nova, antes de "Produção fora do alcance".
- `docs/principios.md`, `docs/comandos.md`, `CLAUDE.md`, `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:** `/fabrica:spec <número da issue> [ajustes pedidos]` continua aceitando o texto, agora opcional; a etapa lê os ajustes da issue com `gh issue view <nº> --json number,title,body,labels,comments`, que ela já usa.

**Decisões:**
- Ajustes lidos dos comentários da issue, com o argumento opcional para uso manual (recomendação da triagem) — o estado 6 de `estados.md` já define os ajustes por esses comentários, e a saída do atalho já os lê. Alternativa descartada: manter os ajustes no argumento e proibir só o dispatcher de preenchê-lo, que deixaria a etapa dependente de quem copia o texto.
- A regra entra antes do dispatcher, e as #105/#107 a seguem (recomendação da triagem) — o PRD põe a segurança antes da automação. Alternativa descartada: esperar a #105 e fazer tudo junto.
- Registro no guia `docs/guias/isolamento-do-agente.md` (recomendação da triagem) e numa ADR — a regra vale para o dispatcher e para toda skill futura, além desta issue. Alternativa descartada: um guia novo do dispatcher, que ainda não existe.
- Sem ajuste pedido, a etapa para — uma rodada sem pedido só reescreveria a spec e geraria um comentário de spec vazio, contado como rodada no `/fabrica:retro`. Alternativa descartada: reescrever a spec mesmo assim.
- Versão `0.30.0` — muda o contrato de um comando (`feat`), como a #111 (`0.28.0`). Alternativa descartada: `0.29.1`.

**Fontes da documentação:**
- gh 2.103.3 — `gh issue view --help` (campos `body` e `comments` do `--json`).
- Claude Code (argumentos de skill, `$ARGUMENTS`) — não verificada; a spec só usa o comportamento que as skills já usam.

**ADR:** `docs/adr/0008-texto-externo-fora-do-prompt.md`

## Testes
- CA1 a CA3 e CA5 a CA9: revisão do diff, com `grep` dos trechos citados.
- CA4: `claude --plugin-dir <clone>` na branch, numa issue de teste neste repositório (com `agente`, triagem e spec publicadas pela própria fábrica), comentário de ajuste do usuário e `/fabrica:spec <nº>`; depois, a segunda rodada sem comentário novo. Limpeza no fim.
- `make lint` e `make test`, se existirem; senão, os scripts de teste do `CLAUDE.md`, que não devem mudar.

## Passos de produção
nenhum

## Riscos e dúvidas
- Um comentário do usuário que não é pedido de ajuste (uma pergunta, um "ok") passa a ser lido como ajuste. Isso já vale hoje na tabela de estados (estado 6) e na saída do atalho; a spec trata o comentário como pedido e, se ele não pedir mudança, registra no comentário de spec que não houve alteração.

## Histórico
- 2026-11-10: criação.
