# SPEC-247 — Separa a execução Claude da coordenação

**Issue:** [#247](https://github.com/ftenorio99/fabrica/issues/247) · **Interface:** não

## Contexto

Registro do trabalho B1 previamente desenvolvido e validado. A base é `de4c39adae11`, o checkpoint funcional é `7d28c7c` e o candidato validado localmente é `3a7b5023ecb69e7c0c356e808728a890eb4443bc`, plugin 0.64.0.

## Desenho técnico

`stage-model.sh` conserva integralmente o conteúdo e o modo da base `de4c39adae11` (blob `94423eef97c9b44eb92c31a2c8d79104cedbacaf`, modo Git `100755`). A tentativa com Bash intermediário foi rejeitada por regressões de ambiente. O módulo carregado com `source` resolveu as diferenças de ambiente reproduzidas, mas mudou os diagnósticos nativos de falha de `exec`. A extração física do executor Claude fica adiada até existir uma necessidade funcional concreta.

A separação lógica permanece. A fachada seleciona e executa. `claude-result.py` classifica o resultado técnico no Execution Result v1, com proveniência desconhecida na falta de evidência. O dispatcher usa essa classificação, preserva os artefatos, códigos e decisões legadas e determina o avanço pelo estado observado no GitHub.

Referências: [arquitetura multi-runtime](../docs/propostas/fabrica-codex-evolution/docs/02-adr-multi-runtime.md), [resultado técnico](../docs/propostas/fabrica-codex-evolution/docs/09-resultado-tecnico.md) e [consolidação B1](../docs/propostas/fabrica-codex-evolution/docs/10-consolidacao-b1.md).

## Critérios de aceite

| ID | Critério | Verificação |
|---|---|---|
| CA1 | Preservar argumentos, permissões, ambiente, diretório, canais, status, identidade do processo e delegação por `FABRICA_CLAUDE_BIN`. | `test-stage-model.sh` e `test-harness.sh`. |
| CA2 | Classificar o resultado conforme v1, conservar artefatos brutos, distinguir configuração, execução, permissão e resultado inválido quando comprovados, e manter a origem desconhecida quando faltarem evidências. | `test-claude-result.sh`. |
| CA3 | Preservar a projeção legada, releitura do GitHub, gates, isolamento e execução assistida. | `test-dispatch.sh`, `test-job-isolation.sh` e inspeção da skill `avancar`. |
| CA4 | Instalar, atualizar e reverter o pacote Claude completo, com manifesto válido, fachada original e normalizador íntegros. | N0 e N1 com Claude CLI 2.1.332. |
| CA5 | Manter diff independente e versão 0.64.0 sobre a base 0.63.0. | Inspeção do diff, dos caminhos excluídos e dos manifestos. |

## Fora de escopo

Empacotamento, configuração e execução Codex, #245, #246, mudanças de isolamento, hooks, máquina de estados e futuros workers. N2 a N6 constam no plano de aceites nativos.

## Rollback

Restaurar o pacote inteiro 0.63.0 para instalações. No código, a integração do dispatcher pode ser revertida antes de retirar o normalizador. Workflows instalados continuam usando os mesmos comandos e artefatos.
