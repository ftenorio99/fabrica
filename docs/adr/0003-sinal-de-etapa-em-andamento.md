# ADR 0003: Etapa em andamento sinalizada pela label em-andamento, com validade de 2 h

**Status:** proposto · **Data:** 2026-11-04 · **Origem:** issue #55

## Contexto
O `/fabrica:avancar` (#55) executa etapas sem que o usuário digite cada comando, e o GitHub Actions da Fase 1 fará o mesmo. Duas execuções não podem pegar a mesma issue ao mesmo tempo. A tabela de `estados.md` já previa isso nos estados 8 e 12 ("se nenhuma sessão estiver nele"), mas não havia como saber se uma sessão estava neles. O estado da fábrica fica todo no GitHub, sem arquivo de estado à parte, e uma sessão pode morrer no meio sem limpar nada.

## Decisão
Quem executa uma etapa de forma automática aplica a label `em-andamento` na issue ao começar e a remove ao terminar, com sucesso ou falha. A label vale por 2 h, contadas pelo horário do último evento `labeled em-andamento` da timeline. Depois disso, ela é considerada esquecida: outra execução pode pegar a issue, e o `/fabrica:status` alerta.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Comentário de início com marcador | Entraria nas regras de "último comentário do agente" e de "resposta nova" de `estados.md`, e cada etapa publicaria um comentário a mais. |
| Lock na branch, como um arquivo ou uma tag | A branch só existe depois da spec, e a triagem também precisa do sinal. |
| Sem validade | Uma sessão morta deixaria a issue travada até alguém remover a label à mão. |

## Consequências
- O `/fabrica:status` e o futuro dispatcher do Actions leem o sinal com a mesma consulta que já fazem das labels.
- Os comandos manuais não aplicam nem conferem a label. A proteção vale entre execuções automáticas.
- Uma etapa automática que passe de 2 h pode ser pega por outra execução. O teto de etapas do `avancar` mantém as execuções curtas.
- O `/fabrica:setup` passa a criar a label nos repositórios.
