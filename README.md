# fabrica

Fábrica de software pessoal: eu entro com requisitos e revisão; agentes de IA fazem triagem, especificação, implementação e verificação. Empacotada como plugin do Claude Code.

## Fluxo
```
issue (agente) → triagem → spec (spec-pronta) → [aprovo a spec] → implementação + testes
→ revisão automática → PR (pronto-revisao) → [aprovo o PR] → merge
```

Para saber o que falta em cada issue e quem age, rode `/fabrica:status` em qualquer diretório. As regras de estado ficam em `skills/status/estados.md`.

## Pré-requisitos
- [Context7](https://context7.com), para as skills `spec` e `implementar` consultarem a documentação atual das bibliotecas. Instale por usuário, uma vez por máquina:
  ```
  npx ctx7 setup --claude
  ```
  Escolha o modo MCP. O comando faz login por OAuth, gera uma API key e configura o MCP remoto em `~/.claude.json`, com a chave no header `Authorization`, além de uma regra em `~/.claude/rules/context7.md` e uma skill em `~/.claude/skills/context7-mcp/`. A chave fica só em `~/.claude.json`, nunca neste repositório nem nos projetos. O motivo de não declarar o servidor no plugin está no [ADR 0001](docs/adr/0001-context7-instalado-por-usuario.md).

  Sem o Context7, as skills continuam funcionando: usam a documentação local do pacote ou o conhecimento do modelo e registram a API como não verificada.

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
| `skills/` | Uma skill por etapa: `prd`, `triagem`, `spec`, `implementar`, `revisar`; e `status`, o quadro do fluxo em todos os repositórios |
| `agents/` | Subagentes usados pelas skills |
| `hooks/` | `protect-main.sh`: bloqueia commit e push direto na `main` |
| `templates/` | `CLAUDE.md` base dos projetos, template de issue e de spec |

## Fases
A fábrica segue o plano em cinco fases (0 · Preparação → 4 · Melhoria). Este repositório está na **Fase 0**: fluxo rodado à mão com o Claude Code local, sem GitHub Actions.
