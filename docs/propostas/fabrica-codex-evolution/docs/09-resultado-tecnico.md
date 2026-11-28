# Contrato interno de resultado técnico

**Escopo:** B1.3, normalização independente após o término. A adoção pelos coordenadores pertence a B1.4.

Rode `python3 -I scripts/claude-result.py <stdout-bruto> [--exit-code <n>] [--evidence <fato>]`. O normalizador lê o arquivo e emite um objeto JSON em stdout. Seu exit `0` indica que o objeto foi produzido, inclusive quando a execução representada falhou. Uso inválido sai com `2` e diagnóstico fixo em stderr. O arquivo bruto permanece disponível byte a byte.

## Campos comuns

| Campo | Semântica e finalidade |
|---|---|
| `version` | Inteiro `1`. Permite que um consumidor reconheça a forma do objeto separado quando o contrato evoluir. |
| `runtime` | Identificador do adaptador, hoje `claude-code`. Permite correlacionar diagnósticos sem interpretar o JSON nativo. |
| `status` | `succeeded`, `failed`, `blocked`, `cancelled` ou `timed_out`. Descreve apenas o resultado técnico. |
| `reason` | `configuration`, `execution`, `permission_denied`, `invalid_result`, `timeout` ou `cancellation`. `null` no sucesso ou quando faltam fatos para atribuir causa. |
| `exit_code` | Código observado pelo chamador, ou `null`. Quando a origem é `executor`, contém o código nativo observado. Uma cadeia pode devolver códigos da própria fachada. |
| `origin` | `pre_exec`, `executor`, `observer` ou `null`. Registra a proveniência comprovada do término. |
| `metadata` | Objeto opcional. Nesta versão, inclui apenas `duration_ms` se a fonte nativa oferecer um inteiro não negativo. Ajuda a medir a execução sem copiar campos livres. |

## Evidência de origem

O chamador fornece `--evidence` a partir de observação própria, por canal separado do stdout do agente. Use `configuration` quando uma validação anterior ao `exec` foi observada. Use `executor_exit` quando for possível atribuir ao executor o código fornecido em `--exit-code`. Use `timeout` ou `cancellation` quando um observador confiável registrar o evento de término correspondente. Essas duas últimas evidências estão representadas em fixtures. A CLI do normalizador tampouco verifica a proveniência por conta própria, portanto quem a chamar deve preservar essa fronteira.

Hoje a fachada repassa o código do `exec` ao mesmo canal usado pelas falhas de validação. O artefato legado `stage.exit` guarda esse código sem origem. Um exit `2`, `124`, `130` ou `143` por si só deixa `origin` como `null`. A presença de JSON também não comprova a origem do código. Nenhum supervisor ou novo canal de observação foi adicionado nesta fase.

## Classificação Claude

A primeira condição aplicável decide o resultado.

| Fato observado | Status | Motivo |
|---|---|---|
| Validação recusada antes do exec | `failed` | `configuration` |
| Prazo atingido ou cancelamento registrado pelo observador | `timed_out` ou `cancelled` | `timeout` ou `cancellation` |
| Exit zero e objeto com `is_error: false` booleano | `succeeded` | `null` |
| Exit não zero ou `is_error: true`, com entrada estruturada de negação de ferramenta | `blocked` | `permission_denied` |
| Exit não zero ou `is_error: true` sem essa evidência | `failed` | `execution` |
| Sem falha de execução observada e com JSON ausente, ilegível ou sem `is_error` booleano | `failed` | `invalid_result` |
| Objeto com `is_error: false` e exit ausente | `failed` | `null` |

O critério de sucesso permanece o aceito pelo dispatcher. Em caso de sucesso, a presença de uma negação de ferramenta não muda o status. Em caso de falha, uma lista `permission_denials` com pelo menos um objeto contendo `tool_name` de texto não vazio indica negação. Essa é uma regra do adaptador Claude. As heurísticas textuais do `avancar` permanecem no caminho legado.

`is_error`, `result`, `permission_denials`, `modelUsage` e detalhes de diagnóstico pertencem ao JSON nativo. Campos livres, nomes e argumentos de ferramentas, texto, identificadores de sessão e chaves de modelo ficam fora do objeto normalizado. O coordenador assistido pode continuar lendo o artefato bruto de acesso controlado para relatórios e escalonamento, como faz hoje. O contrato tampouco representa a próxima etapa ou o avanço da issue, que dependem da releitura do GitHub.
