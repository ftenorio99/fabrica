# SPEC-247 — Separa a execução Claude da coordenação

**Issue:** [#247](https://github.com/ftenorio99/fabrica/issues/247) · **Interface:** não

## Contexto

Registro do trabalho B1 previamente desenvolvido e validado. A base é `de4c39adae11`, o checkpoint funcional é `7d28c7c` e o candidato validado localmente é `3a7b5023ecb69e7c0c356e808728a890eb4443bc`, plugin 0.64.0.

## Desenho técnico

`stage-model.sh` conserva o contrato público e a política de seleção. Carrega `claude-exec.sh` como módulo interno no mesmo Bash. O módulo mantém as funções de preparação e execução originais, com o `exec` final do binário delegado. `claude-result.py` classifica o resultado técnico no Execution Result v1, com proveniência desconhecida na falta de evidência. O dispatcher usa a classificação e mantém os artefatos, códigos e decisões de workflow legados. O avanço da issue depende do estado observado no GitHub.

Referências: [arquitetura multi-runtime](../docs/propostas/fabrica-codex-evolution/docs/02-adr-multi-runtime.md), [resultado técnico](../docs/propostas/fabrica-codex-evolution/docs/09-resultado-tecnico.md) e [consolidação B1](../docs/propostas/fabrica-codex-evolution/docs/10-consolidacao-b1.md).

## Critérios de aceite

| ID | Critério | Verificação |
|---|---|---|
| CA1 | Preservar argumentos, permissões, ambiente, diretório, canais, status, identidade do processo e delegação por `FABRICA_CLAUDE_BIN`. | `test-stage-model.sh` e `test-harness.sh`. |
| CA2 | Classificar o resultado conforme v1, conservar artefatos brutos, distinguir configuração, execução, permissão e resultado inválido quando comprovados, e manter a origem desconhecida quando faltarem evidências. | `test-claude-result.sh`. |
| CA3 | Preservar a projeção legada, releitura do GitHub, gates, isolamento e execução assistida. | `test-dispatch.sh`, `test-job-isolation.sh` e inspeção da skill `avancar`. |
| CA4 | Instalar, atualizar e reverter o pacote Claude completo, com manifesto válido e arquivos do executor e normalizador íntegros. | N0 e N1 com Claude CLI 2.1.332. |
| CA5 | Manter diff independente e versão 0.64.0 sobre a base 0.63.0. | Inspeção do diff, dos caminhos excluídos e dos manifestos. |

## Fora de escopo

Empacotamento, configuração e execução Codex, #245, #246, mudanças de isolamento, hooks, máquina de estados e futuros workers. N2 a N6 constam no plano de aceites nativos.

## Rollback

Restaurar o pacote inteiro 0.63.0 para instalações. No código, a integração do dispatcher pode ser revertida antes de retirar executor e normalizador. Workflows instalados continuam usando os mesmos comandos e artefatos.
