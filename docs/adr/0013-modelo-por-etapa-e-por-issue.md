# ADR 0013: Modelo por etapa e por issue

**Status:** aceito · **Data:** 2026-11-18 · **Origem:** issue #179

## Contexto
Todas as etapas da fábrica rodavam no modelo da sessão. O usuário trabalha com três modelos do Claude Code (Opus 5.5, Sonnet 5.5 e Haiku 5.5) e quer o mais caro só onde o julgamento compensa. Dois critérios pesam:
- **Capacidade e custo** (#98): SWE-bench Pro 64,8 (Haiku 5.5), 81,3 (Sonnet 5.5), 89,9 (Opus 5.5); a fábrica roda na assinatura, então o ganho é em limite de uso e latência.
- **Robustez a injeção** (#120): no teste de coding da Gray Swan, o ataque teve sucesso em 54,6% das vezes no Opus 5.5, 3,0% no Sonnet 5.5 e 0,08% no Haiku 5.5, sem probes.

O frontmatter das skills fixa o modelo por etapa, mas não deixa a issue decidir. Um subagente com `model` não serve para o `implementar`, que já chama o subagente `revisor`.

## Decisão
- A etapa que lê texto de issue primeiro (`triagem`) roda no Sonnet. A `spec` roda no Opus em esforço médio. `implementar` e `revisar` seguem a label `modelo:haiku|sonnet|opus` da issue, que a triagem sugere e o usuário pode trocar até a `spec-aprovada`.
- O `/fabrica:avancar` executa cada etapa num processo `claude -p --model <id>` próprio, com o prompt só com o comando e o número ([ADR 0008](0008-texto-externo-fora-do-prompt.md)).
- A tabela etapa → modelo e os IDs ficam num arquivo só, `skills/avancar/modelos.md`.
- Uma falha de qualidade sobe o modelo: Haiku → Sonnet na primeira, Sonnet → Opus na segunda.
- O processo `claude -p` roda em `bypassPermissions` só dentro da VM do sbx (`sbx-context.sh` diz `onde vm` e `setup-isolation.sh --check` diz `sbx`) e em `auto` nos outros casos. O `auto` bloqueou a etapa `spec` no `-p`, no host, em 3 de 3 execuções.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Uma VM por modelo | O modelo é argumento do `claude`; a VM isola o projeto (ADR 0010), não o modelo. |
| Modelo no frontmatter de cada skill (#98) | Fixa por etapa; a issue mecânica e a de risco gastariam o mesmo modelo no `implementar`. |
| Subagente com `model` em cada etapa | O `implementar` já chama o subagente `revisor`, e subagente não cria subagente. |
| `auto` em todos os casos | Bloqueou a gravação da spec no `claude -p` do host em 3 de 3 execuções; a causa não foi achada. |
| `bypassPermissions` fora da VM | Sem a camada de isolamento do sbx, nada pergunta antes de um comando. |
| Opus na triagem | A triagem é a primeira a ler texto que pode vir de terceiros, e o Opus 5.5 segue instrução plantada bem mais que o Sonnet 5.5. |

## Consequências
- Trocar a versão dos modelos é editar `skills/avancar/modelos.md`.
- O `avancar` depende do binário `claude`; sem ele (OpenCode, Antigravity), executa a etapa na sessão, como antes.
- As etapas precisam continuar rodando sozinhas, sem depender do que foi dito antes na sessão do `avancar`.
- O dispatcher da Fase 1 (#99) pode reaproveitar o `stage-model.sh run` para escolher o modelo do job.
- Etapa nova que entra no `avancar` precisa de uma linha na tabela.
- O `-p` em `bypassPermissions` depende dos hooks `protect-main` e `protect-production` e da VM; o CA14 da spec confere que o hook ainda barra nesse modo.
