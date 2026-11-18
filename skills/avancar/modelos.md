# Modelo por etapa

Fonte da verdade do modelo de cada etapa do `/fabrica:avancar` ([ADR 0013](../../docs/adr/0013-modelo-por-etapa-e-por-issue.md)). O `scripts/stage-model.sh` lê as duas tabelas abaixo; para trocar a versão de um modelo ou a regra de uma etapa, edite só este arquivo.

## Modelos
| Apelido | ID |
|---|---|
| `haiku` | `claude-haiku-5-5` |
| `sonnet` | `claude-sonnet-5-5` |
| `opus` | `claude-opus-5-5` |

## Etapas
A coluna `Regra` vale `fixo` (o modelo da coluna `Modelo`) ou `label` (o da label `modelo:*` da issue, `sonnet` quando não há). A coluna `Opus se` só vale para a regra `label` e diz se a etapa sobe para `opus` quando a label é `modelo:opus` (`sim`) ou se segue sempre o `Modelo` da coluna (`-`).

| Etapa | Regra | Modelo | Esforço | Opus se |
|---|---|---|---|---|
| `triagem` | fixo | `sonnet` | `padrao` | - |
| `spec` | fixo | `opus` | `medium` | - |
| `implementar` | label | `sonnet` | `padrao` | - |
| `revisar` | label | `sonnet` | `padrao` | sim |

Na regra `label`, `implementar` usa o modelo da label. O `revisar` usa `sonnet`, e `opus` só quando a label é `modelo:opus`: `haiku` na implementação não rebaixa a revisão.

## Escalonamento
`haiku` sobe para `sonnet` na 1ª falha de qualidade; `sonnet` sobe para `opus` na 2ª; `opus` não sobe.

| Apelido | Falhas para subir | Sobe para |
|---|---|---|
| `haiku` | 1 | `sonnet` |
| `sonnet` | 2 | `opus` |
