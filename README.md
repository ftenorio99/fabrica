# fabrica

Fábrica de software pessoal: eu entro com requisitos e revisão; agentes de IA fazem triagem, especificação, implementação e verificação. Empacotada como plugin do Claude Code.

## Fluxo
```
issue (agente) → triagem → spec (spec-pronta) → [aprovo a spec] → implementação + testes
→ revisão automática → PR (pronto-revisao) → [aprovo o PR] → merge
```

## Instalação
No Claude Code:
```
/plugin marketplace add ftenorio99/fabrica
/plugin install fabrica@fabrica
```
Para desenvolver a própria fábrica sem instalar: `claude --plugin-dir ~/projetos/fabrica`.

## Conteúdo
| Caminho | O que é |
|---|---|
| `skills/` | Uma skill por etapa: `prd`, `triagem`, `spec`, `implementar`, `revisar` |
| `agents/` | Subagentes usados pelas skills |
| `hooks/` | `protect-main.sh`: bloqueia commit e push direto na `main` |
| `templates/` | `CLAUDE.md` base dos projetos, template de issue e de spec |

## Fases
A fábrica segue o plano em cinco fases (0 · Preparação → 4 · Melhoria). Este repositório está na **Fase 0**: fluxo rodado à mão com o Claude Code local, sem GitHub Actions.
