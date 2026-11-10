# ADR 0008: Texto de issue e PR fora do prompt

**Status:** aceito · **Data:** 2026-11-10 · **Origem:** issue #119

## Contexto
O system card do Claude Fable 5.2 e Mythos 5.2 (9/nov/2026, §6.5.2) mostra que o modelo tende a obedecer instruções plantadas em texto que chega no turno do usuário, porque o trata como vindo do usuário. O conteúdo que chega como resultado de ferramenta é tratado como não confiável (0 de 105 tentativas na avaliação).

Na fábrica, o texto de issues, PRs e comentários pode vir de terceiros. O dispatcher da Fase 1 (#105, #107) vai disparar etapas por eventos do GitHub, e um workflow que interpole o corpo do evento no prompt (`claude -p "$BODY"`) poria esse texto no turno do usuário. O `docs/prd.md` lista a injeção de prompt como risco alto.

Hoje só o `/fabrica:spec <nº> <ajustes>` espera texto de comentário no argumento, e o `/fabrica:avancar` o preenche com os comentários do usuário.

## Decisão
- O prompt de uma etapa de agente leva só o comando e o número da issue ou do PR. A etapa lê o conteúdo com `gh`, que chega como resultado de ferramenta.
- O workflow do dispatcher não usa `${{ github.event.* }}` com texto (corpo, título, comentário) no prompt nem em `run:`.
- O `/fabrica:spec` lê os ajustes nos comentários da issue. O texto no argumento continua aceito no uso manual, digitado pelo usuário.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Manter os ajustes no argumento e proibir só o dispatcher de preenchê-lo | A etapa continuaria dependendo de quem copia o texto, e o `/fabrica:avancar` já o copiava. |
| Passar o texto no prompt dentro de delimitadores ou com aviso de "não confiável" | O texto continua no turno do usuário, onde o modelo o trata como do usuário. |
| Esperar o dispatcher (#105) para decidir | O PRD põe a segurança antes da automação. |

## Consequências
- Toda skill nova que é etapa de agente recebe só o número, como diz o `CLAUDE.md`.
- O workflow do dispatcher tem uma regra a conferir na revisão: nenhum texto do evento no prompt nem em `run:`.
- O `/fabrica:spec` sem comentário novo nem texto no argumento não tem ajuste a fazer e para.
