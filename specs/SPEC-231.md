# SPEC-231: adiciona taxa de reversão e reabertura pós-merge no /fabrica:metricas

**Issue:** #231 · **PRD:** — (suporte ao objetivo de qualidade do `/fabrica:metricas` em `docs/prd.md`) · **Fonte do escopo:** — · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-26

## Contexto
O `/fabrica:metricas` já mede tempo da abertura ao merge, espera do usuário, trabalho do agente, rodadas de revisão, escalonamentos e lições (citado em `docs/prd.md` nos objetivos de fila e qualidade). Porém, ele não mede o que acontece depois do merge, o que impede saber se mudanças no fluxo mantêm a qualidade ou geram retrabalho. Esta issue adiciona ao relatório os indicadores pós-merge do período analisado.

## Objetivo
O relatório do `/fabrica:metricas` passa a contabilizar e exibir, por repositório e na comparação entre períodos, os PRs revertidos no período, as issues reabertas após fechamento e as issues de bug abertas citando um PR entregue no período.

## Comportamento esperado
1. **Coleta por repositório com entrega:** no passo de coleta de `skills/metricas/SKILL.md`, apenas para repositórios que tiveram ao menos uma issue entregue no período, a skill executa duas buscas sequenciais na API de busca do GitHub (seguindo a mesma regra de limite de taxa de 30 req/min já existente):
   - PRs merged no período: `gh search prs --repo <repo> --merged --merged-at <desde>..<até> --limit 100 --json number,title,body,url` → salvo em `<pasta>/prs-merged-<repo>.json`.
   - Issues com label `bug` abertas no período: `gh search issues --repo <repo> --label bug --created <desde>..<até> --limit 100 --json number,title,body,createdAt,url` → salvo em `<pasta>/bugs-<repo>.json`.
2. **Issues reabertas após fechamento:** `skills/metricas/durations.py` passa a retornar `"reaberta": true` quando houver ao menos um par `closed` → `reopened` anterior ao `closed_at` final na timeline da issue, e `"reaberta": false` caso contrário. O total de `Reabertas` do repositório é a soma de issues entregues no período com `"reaberta": true`.
3. **PRs revertidos e bugs pós-merge:** `skills/metricas/quality.py` recebe `<pasta>/prs-merged-<repo>.json`, `<pasta>/bugs-<repo>.json` e os números dos PRs das issues entregues no período (`--prs-entregues`), e devolve `{"revertidos": <int>, "bugs_pos_merge": <int>}`:
   - Um PR merged no período conta em `revertidos` se `title` casar com `(?i)^revert\b` ou se `body` contiver `(?i)\breverts\s+(?:[a-z0-9._-]+/[a-z0-9._-]+)?#\d+` ou `(?i)\bthis reverts commit\b`.
   - Uma issue em `<pasta>/bugs-<repo>.json` conta em `bugs_pos_merge` se `title` ou `body` citar ao menos um número presente em `--prs-entregues` no formato `#<nº>` (`(?<![0-9/])#<nº>\b`) ou URL `.../pull/<nº>\b`. Cada issue conta no máximo 1 vez, mesmo citando múltiplos PRs ou o mesmo PR mais de uma vez.
4. **Exibição no relatório:**
   - A tabela `## Por repositório` ganha as colunas `Revertidos`, `Reabertas` e `Bugs pós-merge` logo após `Entregues`, exibindo `0` quando não houver ocorrência (nunca `—` para contagem zero).
   - Com dois períodos, a tabela `## Comparação` inclui as linhas `Revertidos`, `Reabertas` e `Bugs pós-merge` por repositório com a diferença (`segundo − primeiro`, ex.: `+1`, `−1`, `0`), ou `—` se um dos períodos não tiver nenhuma issue entregue no repositório.
   - Repositórios sem nenhuma issue entregue no período continuam fora do relatório; se uma busca falhar duas vezes por limite de taxa, o repositório segue sem esses dois campos (`—`) e entra na nota de limite de taxa.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/metricas/durations.py` inclui `"reaberta": true` no JSON de saída quando há ao menos um par `closed` → `reopened` antes do `closed_at` final, e `"reaberta": false` caso contrário. | unitário — `bash scripts/test-durations.sh` |
| CA2 | `skills/metricas/quality.py` conta em `revertidos` os PRs merged cujo `title` casa com `(?i)^revert\b` ou cujo `body` contém `(?i)\breverts\s+(?:[a-z0-9._-]+/[a-z0-9._-]+)?#\d+` ou `(?i)\bthis reverts commit\b`, devolvendo `0` quando nenhum casa. | unitário — `bash scripts/test-quality.sh` |
| CA3 | `skills/metricas/quality.py` conta em `bugs_pos_merge` as issues de `<bugs.json>` cujo `title` ou `body` cita ao menos um PR de `--prs-entregues` via `#<nº>` (`(?<![0-9/])#<nº>\b`) ou `.../pull/<nº>\b`. | unitário — `bash scripts/test-quality.sh` |
| CA4 | Uma issue de bug que cita o mesmo PR duas vezes ou cita dois PRs entregues no período conta apenas `1` vez em `bugs_pos_merge`; citações a PRs fora de `--prs-entregues` ou números sem `#` nem `/pull/` não contam (`0`); entradas vazias devolvem `0` (nunca `null`). | unitário — `bash scripts/test-quality.sh` |
| CA5 | `skills/metricas/SKILL.md` coleta os PRs merged e as issues `bug` apenas para repositórios com entregas, respeitando o limite de taxa sequencial, e exibe `Revertidos`, `Reabertas` e `Bugs pós-merge` na tabela `## Por repositório` logo após `Entregues`. | manual antes do merge — `claude --plugin-dir <clone>` na branch rodando `/fabrica:metricas fabrica` |
| CA6 | Com dois períodos, `skills/metricas/SKILL.md` inclui `Revertidos`, `Reabertas` e `Bugs pós-merge` na tabela `## Comparação` com a diferença (`segundo − primeiro`), ou `—` sem entregas em um período; e `docs/comandos.md` documenta os indicadores pós-merge no `/fabrica:metricas`. | manual antes do merge — `claude --plugin-dir <clone>` na branch rodando `/fabrica:metricas fabrica <p1> <p2>` |

## Fora de escopo
- Divisão de tokens entre criação e verificação (depende de decidir antes se a etapa `implementar` passa a registrar `fabrica:custo`).
- Busca de bugs abertos *fora* do período analisado (`--created` sem limite superior), para evitar que comparações entre períodos passados mudem retroativamente.

## Desenho técnico
**Arquivos e módulos:**
- `skills/metricas/durations.py` (alterado): adiciona `"reaberta": bool(paused)` no JSON de saída.
- `skills/metricas/quality.py` (novo): script Python CLI que calcula `revertidos` e `bugs_pos_merge` a partir dos JSONs salvos pelo `gh search`.
- `skills/metricas/SKILL.md` (alterado): adiciona as duas buscas no passo 2, a chamada a `quality.py` no passo 3/4, e as colunas/linhas nas tabelas `## Por repositório` e `## Comparação` no passo 5.
- `scripts/test-durations.sh` (alterado): atualiza as asserções JSON existentes para incluir `"reaberta"` e adiciona caso específico para CA1.
- `scripts/test-quality.sh` (novo): suíte unitária com fixtures JSON cobrindo CA2, CA3 e CA4 (executada automaticamente pelo `.github/workflows/ci.yml` via `scripts/test-*.sh`).
- `docs/comandos.md` (alterado): atualiza a descrição do `/fabrica:metricas` citando os indicadores pós-merge.

**Dados:** nenhum arquivo de estado persistido; os arquivos JSON intermediários ficam apenas na pasta temporária da sessão.

**Interfaces:**
- `python3 skills/metricas/durations.py <created_at> <closed_at> <timeline.json>` → JSON existente acrescido de `"reaberta": true | false`.
- `python3 skills/metricas/quality.py <prs-merged.json> <bugs.json> [--prs-entregues <n1> <n2> ...]` → imprime JSON `{"revertidos": <int>, "bugs_pos_merge": <int>}`. Aceita tanto lista simples quanto saída paginada (lista de listas), como `durations.py` e `costs.py`.

**Decisões:**
- **Detecção de issues reabertas após fechamento** (recomendação da triagem): estender `skills/metricas/durations.py` (que já lê os eventos `closed` e `reopened` da timeline de cada issue) para expor `"reaberta": bool(paused)`, porque evita chamadas extras à API e mantém a regra testável em Python. Alternativa descartada: fazer uma busca separada na API do GitHub.
- **Posição no relatório e comparação entre períodos** (recomendação da triagem): exibir `Revertidos`, `Reabertas` e `Bugs pós-merge` na tabela `## Por repositório` logo após `Entregues` e refletir na `## Comparação` de `skills/metricas/SKILL.md`, porque mantém o formato tabular existente e atende diretamente à comparação entre períodos. Alternativa descartada: adicionar uma seção separada fora das tabelas.
- **Estrutura dos testes unitários** (recomendação da triagem): estender `scripts/test-durations.sh` e criar `scripts/test-quality.sh` com fixtures JSON, seguindo a convenção de `scripts/test-durations.sh` e `scripts/test-costs.sh` (capturados automaticamente pelo `ci.yml`). Alternativa descartada: validar apenas manualmente.
- **Script dedicado `skills/metricas/quality.py`**: isolar a detecção de reversões e bugs pós-merge em um script Python próprio em vez de regras inline no markdown, porque segue o mesmo padrão de `durations.py` e `costs.py` e permite cobertura unitária determinística. Alternativa descartada: filtrar com `jq` inline no `SKILL.md`, que não seria coberto por testes unitários dos scripts da skill.

**Fontes da documentação:**
- Python 3.14.4 (stdlib: `argparse`, `json`, `re`, `sys`) — documentação padrão da biblioteca.
- gh 2.105.0 — `gh search prs --help`, `gh search issues --help`, `gh pr list --help`.

**ADR:** nenhum

## Testes
- **Unitários (`scripts/test-durations.sh` e `scripts/test-quality.sh`):**
  - `bash scripts/test-durations.sh`: valida CA1 (`"reaberta": true` com `closed` → `reopened` antes do `closed_at` final e `"reaberta": false` sem reabertura) e garante que os 9 casos existentes continuam passando com o novo campo.
  - `bash scripts/test-quality.sh`: valida CA2 (título `Revert "..."`, `revert: ...`, corpo `Reverts owner/repo#123`, `This reverts commit ...`, e PR comum que não casa), CA3 (issue com label `bug` citando `#123` ou `https://github.com/owner/repo/pull/123` no título ou corpo) e CA4 (issue citando 2 PRs ou mesmo PR 2 vezes conta 1; citação a PR fora da lista ou número sem `#`/`/pull/` conta 0; listas vazias devolvem `0`).
- **Manuais antes do merge:**
  - `claude --plugin-dir <clone>` na branch rodando `/fabrica:metricas fabrica` e `/fabrica:metricas fabrica <p1> <p2>` para conferir CA5 e CA6 no relatório final.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Limite de taxa da API de busca do GitHub (30 req/min):** cada repositório com entregas passa a fazer +2 chamadas de busca (`gh search prs` e `gh search issues`). Executar em sequência e apenas para repositórios com entregas no período mitiga o risco, e o tratamento de `rate_limit` já previsto no `SKILL.md` cobre eventual esgotamento.
- **Mais de 100 PRs merged ou 100 issues de bug em um único repositório no período:** o `--limit 100` mantém consistência com o limite já adotado na coleta de issues entregues; se ocorrer, segue o mesmo padrão de corte nas 100 mais recentes.

## Histórico
- 2026-11-26: criação.
- 2026-11-26: aprovada para implementação.
