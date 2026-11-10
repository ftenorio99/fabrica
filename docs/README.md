# Manual da fábrica

A fábrica é um fluxo de desenvolvimento em que você entra com os requisitos e as decisões, e agentes de IA fazem triagem, especificação, implementação e revisão. Ela vem como plugin do Claude Code, e as etapas são comandos `/fabrica:<etapa>`.

Tudo acontece no GitHub do próprio projeto: as tarefas são issues, o estado de cada uma está nas labels e nos comentários dos agentes, e toda mudança entra por PR. Você age em três momentos:
- quando puxa uma issue para o fluxo, aplicando a label `agente`;
- quando aprova a spec;
- quando faz o merge do PR.

## Páginas
| Página | Para quê |
|---|---|
| [Primeiros passos](primeiros-passos.md) | Instalar, configurar uma máquina e um repositório, atualizar o plugin e saber onde rodar cada comando. |
| [Fluxo](fluxo.md) | O caminho de uma ideia até o merge, quem age em cada etapa e onde estão os portões humanos. |
| [Comandos](comandos.md) | O que cada uma das 12 skills faz, o que lê, o que cria e quais labels aplica. |
| [Princípios](principios.md) | Por que a fábrica funciona assim: `main` protegida, limite de 3 em andamento, marcos, idioma e outras decisões. |
| [Solução de problemas](solucao-de-problemas.md) | Os problemas que já apareceram no uso e como resolver cada um. |
| [Glossário](glossario.md) | Os termos usados nas skills e neste manual. |

## Guias
| Guia | Situação |
|---|---|
| [Projeto do zero](guias/projeto-do-zero.md) | Da ideia à primeira issue no fluxo. |
| [Mudança no PRD](guias/mudanca-no-prd.md) | O produto mudou depois do backlog criado. |
| [Issue escalonada](guias/issue-escalonada.md) | Um agente parou e pediu a sua decisão. |
| [Revisar um PR da fábrica](guias/revisar-pr.md) | O PR chegou com `pronto-revisao`. |
| [Fechar um marco](guias/fechar-marco.md) | O marco atual está acabando e é hora de puxar o próximo. |
| [Isolamento do agente](guias/isolamento-do-agente.md) | Ligar o sandbox num projeto, ampliar os domínios, listar os padrões de produção e rodar o teste de aceite. |

## Fontes da verdade
Este manual explica e remete. As regras ficam em:
- `skills/<etapa>/SKILL.md`, as instruções de cada etapa;
- [`skills/status/estados.md`](../skills/status/estados.md), as labels, os estados e o backlog;
- [`docs/adr/`](adr/), as decisões de arquitetura.

Se o manual e uma skill discordarem, vale a skill, e o manual precisa de correção.
