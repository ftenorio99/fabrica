# Inventário e premissas verificadas

| Estado observado | SHA | Conteúdo |
|---|---|---|
| Checkout da auditoria | `a93db2f0f9a6d4b1f207dadf1e9e4a03f77d8db8` | 0.59.1, com pipeline Antigravity e seleção por tier. |
| Referência da proposta original | `3c634cc6561e143d75ebc6846c114ca04e93ff26` | 0.62.0, quatro commits adiante. Inclui frontmatter, reprodução de correções, espera do CI e SPEC-241. |
| Base A1/A2 | `de4c39adae1182b4e547017922c9a389f6bfc9bb` | 0.63.0. Inclui SPEC-135. A ponta remota foi reconfirmada antes do fast-forward local. |

A [issue #241](https://github.com/ftenorio99/fabrica/issues/241) foi encerrada como concluída e o [PR #244](https://github.com/ftenorio99/fabrica/pull/244) integra a base. A [SPEC-241](../../../../specs/SPEC-241.md) preserva os hooks, a detecção, o revisor e a execução Antigravity no modelo da sessão. A [SPEC-135](../../../../specs/SPEC-135.md) acrescenta a verificação da base antes de `pronto-revisao`. O [delta da referência original à base](https://github.com/ftenorio99/fabrica/compare/3c634cc6561e...de4c39adae11) é um commit.

## Contratos inventariados

- `harness.sh detect` preserva a precedência de `CLAUDECODE`, `FABRICA_HARNESS`, sinais OpenCode e Antigravity e fallback `binario`.
- `stage-model.sh model|next|run` e `FABRICA_CLAUDE_BIN` compõem o caminho legado. A SPEC-241 retirou `agy-tier`. A saída 3 de `run` ainda indica harness de sessão.
- `dispatch.sh run|unmark|fail` usa estado temporário e consome o JSON Claude. `issue-state.py` e `acao-status.py` interpretam fatos do GitHub.
- `issue-worktree.sh ensure|list|clean` mantém worktree por issue. `stage-usage.py` preserva a linha de custo e a indicação de ausência de dados.
- `ci-wait.sh` e `base-drift.sh` são contratos da revisão da base aprovada.
- As credenciais do runner, o usuário agente e o proxy formam fronteiras distintas de autenticação e execução. OpenCode e Antigravity têm envelopes próprios para hooks. A equivalência de permissões deve ser comprovada por capacidade e versão.

## Questões abertas

- Forma de empacotar Codex e faixa de versões mantidas.
- Nomes e precedência da configuração explícita do executor e dos parâmetros nativos.
- Fronteira operacional entre julgador, verificador e publicador.
- Autenticação, rede e política de retenção no runner Codex.
- Mecanismo de posse, renovação e recuperação para workers. A escolha depende de prova das garantias e de necessidade observada.
