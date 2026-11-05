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
A fábrica usa o `gh` autenticado, numa versão mínima definida em `scripts/check-gh.sh`. Depois, rode `/fabrica:setup` no clone de um projeto: ele confere o `gh`, cria as labels e instala os hooks do git. Para desenvolver a própria fábrica sem instalar: `claude --plugin-dir ~/projetos/fabrica`.

## Manual
O manual de uso está em [`docs/`](docs/README.md): primeiros passos, fluxo, comandos, princípios, solução de problemas, glossário e guias.

## Conteúdo
| Caminho | O que é |
|---|---|
| `skills/` | Uma skill por etapa (`prd`, `backlog`, `setup`, `triagem`, `spec`, `implementar`, `revisar`, `status`), mais a `licao`, para registrar lições aprendidas |
| `agents/` | Subagentes usados pelas skills (`revisor`) |
| `githooks/`, `hooks/` | Proteção da `main`: hooks do git e hooks do Claude Code ([ADR 0002](docs/adr/0002-protecao-da-main-por-hooks-do-git.md)) |
| `scripts/` | Checagem do `gh`, setup das labels e dos hooks do git, e os testes |
| `templates/`, `specs/`, `docs/` | Modelos para os projetos, specs das issues desta fábrica e o manual |

A fábrica está na **Fase 0**: fluxo rodado à mão com o Claude Code local, sem GitHub Actions.
