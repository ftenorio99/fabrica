# CLAUDE.md

Este repositório é a fábrica de software pessoal, empacotada como plugin do Claude Code. Mudar a fábrica é abrir um PR aqui.

## Estrutura
- `.claude-plugin/plugin.json`: identidade do plugin. Suba a `version` a cada mudança que altere comportamento.
- `.claude-plugin/marketplace.json`: permite instalar o plugin com `/plugin marketplace add ftenorio99/fabrica`.
- `skills/<nome>/SKILL.md`: uma skill por etapa do fluxo. No uso, são chamadas como `/fabrica:<nome>`.
- `agents/`: subagentes usados pelas skills (ex.: revisor).
- `githooks/`: hooks globais do git que recusam commit e push na `main`, instalados por `scripts/setup-githooks.sh` (ADR 0002).
- `hooks/`: hooks do Claude Code que valem onde o plugin estiver instalado (ex.: `protect-main.sh`, que impede o Claude de desligar os hooks do git, e `protect-production.sh`, que recusa comandos com padrões de produção).
- `scripts/`: scripts chamados pelas skills (ex.: `setup-labels.sh`, `setup-githooks.sh`). Os testes da proteção da main rodam com `bash scripts/test-protect-main.sh`, os da statusline com `bash scripts/test-statusline.sh`, os do modo de isolamento com `bash scripts/test-setup-isolation.sh`, e os do bloqueio de produção com `bash scripts/test-protect-production.sh`. O `migrate-native-sandbox.sh` remove os restos do sandbox nativo, que saiu da fábrica ([ADR 0010](docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)), e os testes dele rodam com `bash scripts/test-migrate-native-sandbox.sh`. O `scripts/test-sandbox-acceptance.sh` é o teste de aceite do isolamento e roda dentro da VM do `sbx`.
- `docs/`: manual de uso da fábrica (`docs/README.md` é o índice) e ADRs em `docs/adr/`.
- `templates/`: arquivos copiados para os projetos (`CLAUDE.md`, `design.md`, issue, spec). O `design.md` é o formato do design system de um projeto com interface, copiado pela primeira spec com interface.

## Escrevendo skills
- O texto da skill é instrução para o Claude: imperativo, direto, em português.
- O `description` do frontmatter diz o que a skill faz e quando usar; é ele que decide quando a skill é acionada.
- Material de apoio (templates, exemplos) fica ao lado do `SKILL.md`, na pasta da skill, e é referenciado pelo caminho relativo.
- Cada skill aplica e remove as labels da sua etapa, conforme a tabela de labels em `skills/status/estados.md`. Ao mudar o fluxo (labels, marcadores, etapas), atualize essa máquina de estados no mesmo PR.
- O argumento de uma etapa de agente é só o número da issue ou do PR. O texto da issue, do PR e dos comentários a etapa lê com `gh`, nunca pelo argumento ([ADR 0008](docs/adr/0008-texto-externo-fora-do-prompt.md)).
- PR que muda comportamento de uma skill, label, estado ou comando atualiza o manual em `docs/` no mesmo PR. O manual explica e remete às skills; não copie regras nem tabelas delas.

## Testando localmente
`claude --plugin-dir ~/projetos/fabrica` carrega o plugin direto desta pasta, sem instalar.

As regras de git, idioma e segredos do projeto estão em `templates/CLAUDE.md` e valem aqui também.
