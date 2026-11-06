# SPEC-71: Critério de aceite diz como verificar antes do merge ou fica marcado para depois

**Issue:** #71 · **PRD:** — (o fabrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-06

## Contexto
Na retrospectiva de 2026-11-05, dois PRs chegaram ao usuário com critérios de aceite sem evidência, porque só dava para verificá-los com o plugin instalado ou publicando no GitHub. Na #58, o CA4 pedia uma triagem real com a versão nova e virou achado bloqueante pendente. Na #54 (PR #68), os CA3 a CA10 dependiam de rodar o `/fabrica:retro` de forma interativa. Hoje a coluna "Verificação" de um CA aceita só "unitário / e2e / manual", e o `/fabrica:revisar` exige evidência para todo CA. Um CA que não dá para verificar antes do merge acaba bloqueando o PR ou chegando ao usuário sem aviso.

## Objetivo
Todo critério de aceite diz como é verificado antes do merge ou vem marcado, desde a spec, como verificação depois do merge, com o motivo. A revisão trata esse CA como pendente para o usuário, e não como bloqueante.

## Comportamento esperado
**Na spec.** Ao escrever um CA que depende do plugin instalado, de uma execução interativa ou de publicar no GitHub, a spec diz na coluna "Verificação" o caminho antes do merge:

| Depende de | Caminho antes do merge |
|---|---|
| plugin instalado | `claude --plugin-dir <clone>` na branch |
| publicar no GitHub (issue, comentário, label, PR) | issue ou PR de teste no próprio repositório, fechado no fim com um comentário dizendo que era teste, ou um repositório de teste |
| execução interativa com o usuário | sem caminho: os agentes não rodam etapas interativas sem o usuário |

Sem caminho antes do merge, a verificação é `depois do merge — <motivo>`, com o motivo dizendo por que não há caminho antes, por exemplo "depende de responder às perguntas do `/fabrica:retro`". A spec curta do atalho segue a mesma regra na coluna "Verificação".

**Na implementação.** O `/fabrica:implementar` não executa os CAs marcados "depois do merge". Ele os anota para o PR, como faz com as verificações manuais.

**Na revisão.**

| CA | O revisor | No PR |
|---|---|---|
| Verificação antes do merge, com evidência | `sim`, como hoje | ✅ com a evidência |
| Verificação antes do merge, sem evidência | `não` e achado `bloqueante`, como hoje | não chega com `pronto-revisao` |
| `depois do merge` com motivo | `depois do merge`, sem achado | ⏳ com o que você confere depois do merge, e o CA citado em "Para a sua revisão" |
| `depois do merge` sem motivo, ou com um caminho antes do merge da tabela acima que caberia | achado `importante`: a marcação não se justifica | segue as regras de achado do `/fabrica:revisar` |

Um PR cujos CAs pendentes são todos "depois do merge" recebe `pronto-revisao` com CI verde.

**No manual.** O guia de revisão de PR diz que os CAs ⏳ são conferidos por você depois do merge, junto com a atualização do plugin quando o PR é da fábrica.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | No passo 4 de `skills/spec/SKILL.md`, a regra dos critérios de aceite traz a tabela "Depende de / Caminho antes do merge" e a forma `depois do merge — <motivo>` para o CA sem caminho. `skills/spec/template.md` e o formato da spec curta em `skills/triagem/SKILL.md` mostram "depois do merge" entre as opções da coluna "Verificação". | manual: leitura do diff |
| CA2 | `skills/implementar/SKILL.md` diz que os CAs "depois do merge" não são executados nem testados, e que vão anotados para o PR. | manual: leitura do diff |
| CA3 | `agents/revisor.md` aceita `depois do merge` na coluna "Atendido" para um CA marcado com motivo, sem achado. Uma marcação sem motivo, ou em CA com um caminho antes do merge que caberia, vira achado `importante`. | manual: leitura do diff |
| CA4 | Em `skills/revisar/SKILL.md`, a tabela de CAs do corpo do PR usa ⏳ e "confere depois do merge: <o quê>" para esses CAs, que também aparecem em "Para a sua revisão". A regra "o status de cada CA no PR precisa ter evidência" abre a exceção para eles, e um CA "depois do merge" não impede `pronto-revisao`. | manual: leitura do diff |
| CA5 | `docs/guias/revisar-pr.md` explica os CAs ⏳ e quando conferi-los. `docs/comandos.md` (spec e revisar) e o verbete "Critério de aceite" de `docs/glossario.md` citam a marcação "depois do merge", remetendo às skills sem copiar as regras. | manual: leitura do diff |
| CA6 | A `version` de `.claude-plugin/plugin.json` sobe para `0.18.0`, e `bash scripts/test-protect-main.sh`, `bash scripts/test-stage-usage.sh`, `bash scripts/test-costs.sh` e `bash scripts/test-check-gh.sh` continuam passando. | manual: rodar os scripts |
| CA7 | Ponta a ponta: com o plugin carregado da branch (`claude --plugin-dir ~/projetos/fabrica`), o subagente revisor é chamado sobre uma spec de teste com um CA `depois do merge — <motivo>` e outro marcado sem motivo. O primeiro volta como `depois do merge`, sem achado, e o segundo como achado `importante`. A spec de teste fica fora do commit. | manual: execução na branch |

## Fora de escopo
- Criar repositórios de teste automaticamente.
- Rodar etapas interativas sem o usuário.
- Acompanhar os CAs "depois do merge" depois do merge, com issue, label ou alerta no `/fabrica:status`.
- Mudar a tabela de estados: não há label nem estado novo.

## Desenho técnico
**Arquivos e módulos:**
- `skills/spec/SKILL.md`, passo 4, "Critérios de aceite": a tabela de caminhos antes do merge e a forma `depois do merge — <motivo>`.
- `skills/spec/template.md`: a coluna "Verificação" do exemplo passa a `unitário / e2e / manual / depois do merge — <motivo>`.
- `skills/triagem/SKILL.md`, formato da `### Spec curta`: a mesma coluna.
- `skills/implementar/SKILL.md`, passos 3 e 4: os CAs "depois do merge" não ganham teste nem execução, e vão para as anotações levadas à revisão.
- `agents/revisor.md`, passo 4 de "O que fazer" e formato da resposta: o valor `depois do merge` e o achado da marcação sem motivo.
- `skills/revisar/SKILL.md`:
  - passo 4: um CA `depois do merge` do revisor não é achado nem pendência;
  - passo 5: no corpo do PR, a linha ⏳ na tabela de CAs e o CA em "Para a sua revisão";
  - passo 6, labels: a condição de `pronto-revisao`;
  - regras: a exceção da evidência.
- `docs/guias/revisar-pr.md`: o item "Critérios de aceite" em "Por onde começar" e a seção "Depois do merge na própria fábrica".
- `docs/comandos.md`: as entradas `/fabrica:spec` e `/fabrica:revisar`.
- `docs/glossario.md`: o verbete "Critério de aceite".
- `.claude-plugin/plugin.json`: `version` para `0.18.0`.

**Dados:** nenhum.

**Interfaces:**
- Coluna "Verificação" da spec: `depois do merge — <motivo>`.
- Coluna "Atendido" do revisor: `sim`, `não`, `parcial` ou `depois do merge`.
- Coluna "Status" do PR: ✅, ❌ ou ⏳. Com ⏳, a evidência é "confere depois do merge: <o quê>".

**Decisões:**
- O motivo é obrigatório na marcação e conferido pelo revisor — é o que impede "depois do merge" de virar jeito de escapar de um teste que dava para fazer. Alternativa descartada: aceitar a marcação sem motivo, o que reabriria o problema da #58 sem ninguém notar.
- A marcação sem motivo é achado `importante`, não `bloqueante` — o código pode estar certo, e o problema é a spec deixar de provar o CA. Assim, o `revisar` corrige a marcação ou registra a discordância, sem travar o PR. Alternativa descartada: `bloqueante`, que poria em rascunho um PR correto por um detalhe da spec.
- Status ⏳ no PR, e não ✅ — o usuário vê na tabela o que ainda falta conferir. Alternativa descartada: ✅ com uma nota, que esconderia a pendência.
- Sem acompanhamento depois do merge — a issue pede só que o CA chegue ao PR marcado. Uma issue ou label de acompanhamento cabe numa issue própria, se a retrospectiva mostrar CAs esquecidos.
- Sem ADR — a mudança refina as regras de CA da spec e da revisão, sem princípio, label ou estado novo.

**Fontes da documentação:** nenhuma biblioteca envolvida. O `claude --plugin-dir` é o mesmo já usado no `CLAUDE.md` do fabrica.

**ADR:** nenhum.

## Testes
- CA1 a CA5: leitura do diff, conferindo cada trecho citado no desenho técnico.
- CA6: os quatro scripts de teste.
- CA7: chamada real do subagente `fabrica:revisor` com o plugin da branch, numa spec de teste temporária fora do commit.

## Riscos e dúvidas
- **Conflito com #69, #70 e #79:** as três mudam `skills/spec/SKILL.md` ou o formato da spec curta. A que entrar depois resolve o conflito com rebase.
- **CA esquecido depois do merge:** sem acompanhamento, um CA ⏳ depende de o usuário conferi-lo. O guia de revisão e a seção "Para a sua revisão" do PR deixam a pendência visível, e a retrospectiva mostra se isso falhar.

## Histórico
- 2026-11-06: criação.
- 2026-11-06: aprovada.
