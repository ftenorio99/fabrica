# fabrica

Fábrica de software pessoal: eu entro com requisitos e revisão; agentes de IA fazem triagem, especificação, implementação e verificação. Empacotada como plugin do Claude Code.

```
prd → backlog → [aplico agente] → triagem → spec → [aprovo a spec] → implementação → revisão → PR → [aprovo o PR] → merge
```

## Instalação
No Claude Code:
```
/plugin marketplace add ftenorio99/fabrica
/plugin install fabrica@fabrica
```
Depois, rode `/fabrica:setup` no clone de um projeto. Para desenvolver a própria fábrica sem instalar: `claude --plugin-dir ~/projetos/fabrica`.

## Manual
O manual de uso está em [`docs/`](docs/README.md): primeiros passos, fluxo, comandos, princípios, solução de problemas, glossário e guias.

## Conteúdo
| Caminho | O que é |
|---|---|
| `skills/` | Uma skill por etapa (`prd`, `backlog`, `setup`, `triagem`, `spec`, `implementar`, `revisar`, `status`) |
| `agents/` | Subagentes usados pelas skills (`revisor`) |
| `githooks/`, `hooks/` | Proteção da `main`: hooks do git e hooks do Claude Code ([ADR 0002](docs/adr/0002-protecao-da-main-por-hooks-do-git.md)) |
| `scripts/` | Setup das labels e dos hooks do git, testes da proteção da `main` |
| `templates/`, `specs/`, `docs/` | Modelos para os projetos, specs das issues desta fábrica e o manual |

A fábrica está na **Fase 0**: fluxo rodado à mão com o Claude Code local, sem GitHub Actions.
