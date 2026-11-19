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
| [Comandos](comandos.md) | O que cada uma das 13 skills faz, o que lê, o que cria e quais labels aplica. |
| [Princípios](principios.md) | Por que a fábrica funciona assim: `main` protegida, limite de 3 em andamento, marcos, idioma e outras decisões. |
| [Solução de problemas](solucao-de-problemas.md) | Os problemas que já apareceram no uso e como resolver cada um. |
| [Glossário](glossario.md) | Os termos usados nas skills e neste manual. |

## Guias
| Guia | Situação |
|---|---|
| [Projeto do zero](guias/projeto-do-zero.md) | Da ideia à primeira issue no fluxo. |
| [Mudança no PRD](guias/mudanca-no-prd.md) | O produto mudou depois do backlog criado. |
| [Issue escalonada](guias/issue-escalonada.md) | Um agente parou e pediu a sua decisão. |
| [Ação externa](guias/acao-externa.md) | Um agente parou e pediu uma ação sua fora do GitHub, numa checklist. |
| [Revisar um PR da fábrica](guias/revisar-pr.md) | O PR chegou com `pronto-revisao`. |
| [Lançamento](guias/lancamento.md) | O projeto vai para produção pela primeira vez. |
| [Fechar um marco](guias/fechar-marco.md) | O marco atual está acabando e é hora de puxar o próximo. |
| [Isolamento do agente](guias/isolamento-do-agente.md) | Escolher entre a VM do `sbx` e o modo sem sandbox, preparar a VM, ampliar os domínios e listar os padrões de produção. |
| [Migrar para o AGENTS.md](guias/migrar-para-agents-md.md) | O projeto tem as regras só no `CLAUDE.md`, ou tem os dois arquivos sem o import. |
| [Antigravity](guias/antigravity.md) | Usar a fábrica pelo Antigravity CLI (`agy`): o que funciona, o que não funciona e as issues que acompanham os consertos. |
| [Dispatcher no GitHub Actions](guias/dispatcher.md) | Ligar o piloto do workflow que roda a triagem quando a label `agente` é aplicada, com os três secrets, o isolamento do job (proxy, lista de domínios e teste de aceite), o comentário de falha e os limites. |

## Fontes da verdade
Este manual explica e remete. As regras ficam em:
- `skills/<etapa>/SKILL.md`, as instruções de cada etapa;
- [`skills/status/estados.md`](../skills/status/estados.md), as labels, os estados e o backlog;
- [`docs/adr/`](adr/), as decisões de arquitetura.

Se o manual e uma skill discordarem, vale a skill, e o manual precisa de correção.
