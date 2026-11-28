# Fabrica multi-runtime

**Estado:** planejamento aprovado para documentação e caracterização (A1 e A2).
**Base de referência:** `de4c39adae1182b4e547017922c9a389f6bfc9bb`, plugin 0.63.0.

A Fabrica mantém um processo de engenharia compartilhado e oferece integração nativa com Claude Code, OpenCode, Antigravity e Codex CLI. Cada runtime deve poder operar sozinho dentro das capacidades declaradas. Claude Code segue como padrão do dispatcher por compatibilidade. Codex começa com adoção explícita no ambiente local.

| Documento | Conteúdo |
|---|---|
| [01 — Análise](docs/01-analise-arquitetural.md) | Base, inventário e fronteiras |
| [02 — ADR](docs/02-adr-multi-runtime.md) | Decisão multi-runtime e ADRs relacionados |
| [03 — Spec](docs/03-spec-codex-runtime.md) | Contrato mínimo e aceite Codex |
| [04 — Backlog](docs/04-plano-de-implementacao.md) | Épicos A a E e dependências |
| [05 — Testes](docs/05-estrategia-de-testes.md) | Caracterização e permissões de execução |
| [06 — Instruções de trabalho](docs/06-prompt-para-codex.md) | Como retomar o trabalho pelo fluxo da Fabrica |
| [07 — Inventário](docs/07-inventario-e-premissas.md) | Referências e decisões abertas |
| [08 — Baseline](docs/08-baseline.md) | Resultados na base aprovada |
