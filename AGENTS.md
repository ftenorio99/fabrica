# AGENTS.md

Este repositório é a fábrica de software pessoal, empacotada como plugin do Claude Code. Mudar a fábrica é abrir um PR aqui.

As regras de git, idioma e segredos do projeto estão em `templates/AGENTS.md` e valem aqui também.

## Estrutura
- `.claude-plugin/plugin.json`: identidade do plugin. Suba a `version` a cada mudança que altere comportamento.
- `.claude-plugin/marketplace.json`: permite instalar o plugin com `/plugin marketplace add ftenorio99/fabrica`.
- `skills/<nome>/SKILL.md`: uma skill por etapa do fluxo. No uso, são chamadas como `/fabrica:<nome>`.
- `agents/`: subagentes usados pelas skills (ex.: revisor).
- `githooks/`: hooks globais do git que recusam commit e push na `main`, instalados por `scripts/setup-githooks.sh` (ADR 0002).
- `hooks/`: hooks do Claude Code que valem onde o plugin estiver instalado (ex.: `protect-main.sh`, que impede o Claude de desligar os hooks do git, e `protect-production.sh`, que recusa comandos com padrões de produção). Esses dois também aceitam a entrada do `PreToolUse` do Antigravity e respondem no formato dele, para a conversão do `agy plugin install` não deixá-los sem efeito. O `session-start.sh`, que avisa quando os hooks do git não estão instalados, faz o mesmo com o `SessionStart` (texto puro no Claude Code, `injectSteps` no Antigravity).
- `scripts/`: scripts chamados pelas skills (ex.: `setup-labels.sh`, `setup-githooks.sh`). Os testes da proteção da main rodam com `bash scripts/test-protect-main.sh`, os da statusline com `bash scripts/test-statusline.sh`, os do modo de isolamento com `bash scripts/test-setup-isolation.sh`, os do contexto do checklist do `sbx` com `bash scripts/test-sbx-context.sh`, os do bloqueio de produção com `bash scripts/test-protect-production.sh`, os do aviso do `SessionStart` com `bash scripts/test-session-start.sh`, os do `acao-status.py`, que lê a checklist da ação externa, com `bash scripts/test-acao-status.sh`, os do `stage-model.sh`, que escolhe o modelo de cada etapa e roda o `claude -p`, com `bash scripts/test-stage-model.sh`, e os do `issue-worktree.sh`, que cria, reusa e limpa a worktree de cada issue em `<clone>/.worktrees/<nº>` ([ADR 0014](docs/adr/0014-uma-worktree-por-issue.md)), com `bash scripts/test-issue-worktree.sh`. O `migrate-native-sandbox.sh` remove os restos do sandbox nativo, que saiu da fábrica ([ADR 0010](docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)), e os testes dele rodam com `bash scripts/test-migrate-native-sandbox.sh`. O `scripts/test-sandbox-acceptance.sh` é o teste de aceite do isolamento e roda dentro da VM do `sbx`.
- `opencode/`: adaptador da fábrica para o OpenCode, com as skills, os comandos `/fabrica:*`, o subagente `fabrica/revisor` e os hooks de proteção; a instalação e os limites estão em `opencode/README.md`. O teste de aceite roda com `bash opencode/test-adapter.sh`, dentro da VM do `sbx` com o agente `opencode`.
- `docs/`: manual de uso da fábrica (`docs/README.md` é o índice) e ADRs em `docs/adr/`.
- `templates/`: arquivos copiados para os projetos (`AGENTS.md`, com as regras do projeto, `CLAUDE.md`, que importa o `AGENTS.md`, `design.md`, issue, spec). O `design.md` é o formato do design system de um projeto com interface, copiado pela primeira spec com interface.

## Escrevendo skills
- O texto da skill é instrução para o Claude: imperativo, direto, em português.
- O `description` do frontmatter diz o que a skill faz e quando usar; é ele que decide quando a skill é acionada.
- Material de apoio (templates, exemplos) fica ao lado do `SKILL.md`, na pasta da skill, e é referenciado pelo caminho relativo.
- Cada skill aplica e remove as labels da sua etapa, conforme a tabela de labels em `skills/status/estados.md`. Ao mudar o fluxo (labels, marcadores, etapas), atualize essa máquina de estados no mesmo PR.
- O argumento de uma etapa de agente é só o número da issue ou do PR. O texto da issue, do PR e dos comentários a etapa lê com `gh`, nunca pelo argumento ([ADR 0008](docs/adr/0008-texto-externo-fora-do-prompt.md)).
- PR que muda comportamento de uma skill, label, estado ou comando atualiza o manual em `docs/` no mesmo PR. O manual explica e remete às skills; não copie regras nem tabelas delas.
