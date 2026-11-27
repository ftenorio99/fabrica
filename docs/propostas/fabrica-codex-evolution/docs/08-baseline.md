# Baseline de caracterização A2

**Base testada:** `de4c39adae1182b4e547017922c9a389f6bfc9bb`, plugin 0.63.0. A `origin/main` do clone temporário também apontava para esse SHA.

**Ambiente:** Git 2.53.0, Bash 5.3.9, Python 3.14.4, PyYAML 6.0.3, jq 1.8.1 e Node v24.22.1. Codex CLI 0.172.0 foi observado na auditoria anterior. As CLIs de agentes ficaram fora do PATH da suíte.

## Execução

Clone local temporário sem hardlinks, com HOME e TMPDIR temporários. Executou-se `bash scripts/test-*.sh` individualmente pelo mesmo filtro do CI, em namespace de rede isolado, com ambiente reduzido e somente a área temporária gravável no sistema de arquivos. Os testes de isolamento com fakes usaram loopback. O clone e os temporários foram removidos ao fim.

**Resultado:** 27 suítes selecionadas encerraram com código 0. **1401 verificações passaram, zero falhas e três grupos de validação nativa ficaram pulados.** Duas suítes tiveram execução parcial. O coletor auxiliar de linhas de pulo tentou usar `rg`, ausente no PATH reduzido. Os totais abaixo vêm dos resumos nativos das suítes, e os motivos dos três grupos vêm das condições nos scripts.

| Suíte em `scripts/` | Verificações aprovadas | Grupos pulados |
|---|---:|---:|
| `test-acao-status.sh` | 15 | 0 |
| `test-base-drift.sh` | 41 | 0 |
| `test-check-gh.sh` | 25 | 0 |
| `test-ci-wait.sh` | 52 | 0 |
| `test-costs.sh` | 5 | 0 |
| `test-dispatch.sh` | 152 | 0 |
| `test-durations.sh` | 10 | 0 |
| `test-harness.sh` | 34 | 0 |
| `test-issue-state.sh` | 84 | 0 |
| `test-issue-worktree.sh` | 31 | 0 |
| `test-job-isolation.sh` | 164 | 0 |
| `test-migrate-native-sandbox.sh` | 109 | 0 |
| `test-protect-main.sh` | 162 | 0 |
| `test-protect-production.sh` | 28 | 0 |
| `test-publish-screenshots.sh` | 42 | 0 |
| `test-quality.sh` | 7 | 0 |
| `test-regras-etapas.sh` | 78 | 0 |
| `test-revisor-agent.sh` | 14 | 2 |
| `test-sbx-context.sh` | 27 | 0 |
| `test-session-start.sh` | 8 | 0 |
| `test-setup-ci.sh` | 90 | 0 |
| `test-setup-dispatcher.sh` | 35 | 0 |
| `test-setup-isolation.sh` | 58 | 0 |
| `test-skill-frontmatter.sh` | 34 | 1 |
| `test-stage-model.sh` | 46 | 0 |
| `test-stage-usage.sh` | 32 | 0 |
| `test-statusline.sh` | 18 | 0 |

- `test-revisor-agent.sh`: validações reais Claude e Antigravity ficaram puladas porque os binários não estavam no PATH isolado.
- `test-skill-frontmatter.sh`: validação real Claude ficou pulada. O parser OpenCode foi exercitado pelo Node com a função extraída do adaptador.

## Pendências e autorizações

| Teste ou grupo | Motivo da pendência |
|---|---|
| Validadores reais Claude/Antigravity | Exigem autorização específica para executar os binários nativos em ambiente descartável. |
| `opencode/test-adapter.sh` | Exige VM `sbx`/servidor local. A alternativa documentada pode tocar a configuração global da VM. |
| `test-job-acceptance.sh` e `test-sandbox-acceptance.sh` | Exigem runner/VM, rede, credenciais e escritas em remoto de teste. |
| `test-revisor-quality.sh` | Invoca Claude com modelo real. |
| Aceites Codex de instalação, skills, modelo e runner | Pertencem ao backlog. A validação real de modelo e os efeitos remotos exigem autorização específica. |

Este baseline cobre contratos determinísticos. A paridade ponta a ponta, autenticação real e qualidade por runtime permanecem pendentes.
