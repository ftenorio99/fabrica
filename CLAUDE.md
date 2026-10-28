# CLAUDE.md

Este repositório é a fábrica de software pessoal, empacotada como plugin do Claude Code. Mudar a fábrica é abrir um PR aqui.

## Estrutura
- `.claude-plugin/plugin.json`: identidade do plugin. Suba a `version` a cada mudança que altere comportamento.
- `.claude-plugin/marketplace.json`: permite instalar o plugin com `/plugin marketplace add ftenorio99/fabrica`.
- `skills/<nome>/SKILL.md`: uma skill por etapa do fluxo. No uso, são chamadas como `/fabrica:<nome>`.
- `agents/`: subagentes usados pelas skills (ex.: revisor).
- `hooks/`: hooks que valem onde o plugin estiver instalado (ex.: `protect-main.sh`).
- `scripts/`: scripts chamados pelas skills (ex.: `setup-labels.sh`).
- `templates/`: arquivos copiados para os projetos (`CLAUDE.md`, issue, spec).

## Escrevendo skills
- O texto da skill é instrução para o Claude: imperativo, direto, em português.
- O `description` do frontmatter diz o que a skill faz e quando usar; é ele que decide quando a skill é acionada.
- Material de apoio (templates, exemplos) fica ao lado do `SKILL.md`, na pasta da skill, e é referenciado pelo caminho relativo.
- Cada skill aplica e remove as labels da sua etapa, conforme a tabela de labels em `skills/status/estados.md`. Ao mudar o fluxo (labels, marcadores, etapas), atualize essa máquina de estados no mesmo PR.

## Testando localmente
`claude --plugin-dir ~/projetos/fabrica` carrega o plugin direto desta pasta, sem instalar.

As regras de git, idioma e segredos do projeto estão em `templates/CLAUDE.md` e valem aqui também.
