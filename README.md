# fabrica

Fábrica de software pessoal: eu entro com requisitos e revisão; agentes de IA fazem triagem, especificação, implementação e verificação. Empacotada como plugin do Claude Code.

## Fluxo
```
prd → backlog (milestones e issues) → [aplico agente] → triagem → spec (spec-pronta) → [aprovo a spec] → implementação + testes
→ revisão automática → PR (pronto-revisao) → [aprovo o PR] → merge
```

Para saber o que falta em cada issue e quem age, rode `/fabrica:status` em qualquer diretório. As regras de estado ficam em `skills/status/estados.md`.

## Backlog
O `/fabrica:backlog` transforma o fatiamento do `docs/prd.md` em milestones e issues no GitHub. O planejamento é em ondas:
- **Marcos:** o fatiamento agrupa os itens em marcos `### M<n> · <nome> (<F>)`, sem sprints nem datas. Cada item tem número fixo e `depende de` explícito. Todas as milestones são criadas de uma vez, com a lista dos itens na descrição.
- **Janela:** só o marco atual e o seguinte ganham issues. Quando o atual estiver perto de fechar (pelo menos 1 issue fechada e no máximo 2 abertas), o `/fabrica:status` avisa para rodar `/fabrica:backlog` de novo, e o marco seguinte ganha as suas.
- **Issue enxuta:** título, funcionalidade, número do item, marco, link para o PRD e `Depende de #x`. O detalhe vem na triagem e na spec. O número de cada issue é anotado no PRD num PR `docs/backlog`.
- **Puxar:** backlog é issue aberta sem `agente`. Aplicar `agente` puxa a issue para o fluxo; o `/fabrica:status` sugere qual, pela ordem do marco e pelas dependências fechadas.
- **PRD alterado:** rodar de novo atualiza as issues de backlog e só lista as que já estão no fluxo. Nada é criado, alterado ou fechado sem a sua confirmação, e rodar de novo sem mudanças não cria nada.

## Pré-requisitos
- [Context7](https://context7.com), para as skills `spec` e `implementar` consultarem a documentação atual das bibliotecas. Instale por usuário, uma vez por máquina:
  ```
  npx ctx7 setup --claude
  ```
  Escolha o modo MCP. O comando faz login por OAuth, gera uma API key e configura o MCP remoto em `~/.claude.json`, com a chave no header `Authorization`, além de uma regra em `~/.claude/rules/context7.md` e uma skill em `~/.claude/skills/context7-mcp/`. A chave fica só em `~/.claude.json`, nunca neste repositório nem nos projetos. O motivo de não declarar o servidor no plugin está no [ADR 0001](docs/adr/0001-context7-instalado-por-usuario.md).

  Sem o Context7, as skills continuam funcionando: usam a documentação local do pacote ou o conhecimento do modelo e registram a API como não verificada.

## Labels
O fluxo usa seis labels (`agente`, `precisa-info`, `spec-pronta`, `spec-aprovada`, `escalonado`, `pronto-revisao`). Nome, cor e descrição ficam na tabela "Labels" de `skills/status/estados.md`, e `scripts/setup-labels.sh` cria ou corrige as seis num repositório sem tocar nas demais.
- **Projeto novo:** a skill `prd` roda o setup sozinha ao terminar. Se o repositório ainda não existir no GitHub, ela avisa, e você roda `/fabrica:setup` depois do `gh repo create`.
- **Repositório que já existe:** rode `/fabrica:setup` no clone, ou `/fabrica:setup <dono>/<repo>` de qualquer diretório. Rodar de novo é seguro.
- Se uma etapa avisar que uma label não existe, rode `/fabrica:setup` e repita a etapa.

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
| `skills/` | Uma skill por etapa: `prd`, `backlog`, `triagem`, `spec`, `implementar`, `revisar`; `status`, o quadro do fluxo em todos os repositórios; e `setup`, que cria as labels num repositório |
| `agents/` | Subagentes usados pelas skills |
| `hooks/` | `protect-main.sh`: bloqueia commit e push direto na `main` |
| `scripts/` | `setup-labels.sh`: cria ou corrige as labels da fábrica num repositório |
| `templates/` | `CLAUDE.md` base dos projetos, template de issue e de spec |

## Fases
A fábrica segue o plano em cinco fases (0 · Preparação → 4 · Melhoria). Este repositório está na **Fase 0**: fluxo rodado à mão com o Claude Code local, sem GitHub Actions.
