# ADR 0004: atalho da triagem com spec curta

**Status:** proposto · **Data:** 2026-11-05 · **Origem:** issue #52

## Contexto
Toda issue passa por triagem, spec, aprovação da spec, implementação, revisão e merge, qualquer que seja o tamanho. Ajustar um texto custa a mesma etapa de spec, com branch, arquivo `specs/SPEC-<nº>.md` e commit, que uma mudança de arquitetura. A triagem já sabe quando uma issue é pequena e sem ambiguidade: ela classifica o tamanho e a classe e procura lacunas.

A fábrica tem três gestos do usuário: puxar a issue, aprovar a spec e fazer o merge ([Princípios](../principios.md#você-decide-os-agentes-executam)). Várias peças dependem da label `spec-aprovada`: o pré-requisito do `/fabrica:implementar`, o limite de 3 em andamento, as paradas do `/fabrica:avancar` e o tempo "esperando você" do `/fabrica:metricas`.

## Decisão
Quando a issue cabe no atalho (tamanho `P`, classe `implementacao-simples` ou `documentacao`, sem lacunas e sem arquivos sensíveis), a própria triagem publica uma spec curta no comentário dela, só com objetivo e critérios de aceite, e aplica `spec-pronta`. O usuário aprova com a mesma label `spec-aprovada`, e a etapa `/fabrica:spec` não roda. Qualquer comentário do usuário depois dessa triagem tira a issue do atalho: o `/fabrica:spec` escreve a spec completa e a issue segue o caminho de sempre.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Pular o portão da spec e levar os CAs direto para o PR, com o merge como único portão | Tira um dos três gestos do usuário, deixa a issue sem `spec-aprovada` e obriga a criar outra regra para o limite de 3 em andamento, para o `/fabrica:implementar` e para as métricas. O usuário só veria os CAs depois do código pronto, quando um CA errado custa uma rodada de implementação. |
| Uma label `sem-atalho` para recusar o atalho | Cria uma label a mais para um gesto que o comentário já cobre. Quem discorda da spec curta quase sempre tem algo a dizer, e esse comentário já é o pedido de ajuste. |
| A triagem criar a branch do atalho | A triagem não mexe no repositório. A branch nasce no `/fabrica:implementar`, e a triagem só anuncia o nome dela. |

## Consequências
- Uma issue no atalho tem uma etapa de agente a menos (`/fabrica:spec`) e nenhum arquivo `specs/SPEC-<nº>.md`. Os mesmos dois portões continuam: aprovar a spec e fazer o merge.
- A spec de uma issue passa a ter duas fontes: o arquivo citado no último comentário `<!-- fabrica:spec -->` ou, sem ele, a spec curta do último comentário de triagem com `**Atalho:** sim`. As etapas e o `/fabrica:status` leem a spec e a branch por essa regra, definida em `skills/status/estados.md`.
- Ajustar uma spec curta não existe: o ajuste vira a spec completa. Assim, a spec curta nunca é editada, e uma issue que gerou discussão perde o atalho.
