# SPEC-75: Métricas distorcem tempos e contagens em issues reabertas, escalonamentos tardios e repositórios arquivados

**Issue:** #75 · **PRD:** — (o fabrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-06

## Contexto
O `/fabrica:metricas` (SPEC-58 e anteriores) é o instrumento para comparar mudanças na fábrica. A revisão automática do PR #57 deixou sugestões não aplicadas que continuam valendo na `main` e distorcem os números. Uma issue reaberta conta o tempo em que ficou fechada. Um escalonamento posterior ao fechamento entra na contagem. Com dois períodos, as tabelas não dizem de qual período é cada linha. Quando a busca passa de 100 issues, os repositórios arquivados ficam de fora. E a repetição da busca em paralelo pode estourar o limite da busca do GitHub.

## Objetivo
O `/fabrica:metricas` mede só o tempo em que a issue esteve aberta, conta só os escalonamentos até o fechamento, identifica o período de cada linha numa comparação, inclui os repositórios arquivados no corte de 100 e não estoura o limite de taxa da busca.

## Comportamento esperado
**Issue reaberta.** Na timeline, cada par de eventos `closed` → `reopened` anterior ao `closed_at` final é um **intervalo fechado**. O `durations.py` desconta os intervalos fechados de todos os tempos:

| Métrica | Com intervalos fechados |
|---|---|
| `abertura_ao_merge` | `closed_at − created_at` menos todos os intervalos fechados |
| `antes_do_fluxo` | menos os intervalos fechados anteriores ao primeiro `labeled agente` |
| `esperando_voce` | não conta minuto dentro de um intervalo fechado, mesmo com um portão do usuário aplicado |
| `com_o_agente` | tempo em fluxo, do primeiro `agente` ao `closed_at`, menos os intervalos fechados e menos `esperando_voce` |

Assim, `antes_do_fluxo + esperando_voce + com_o_agente = abertura_ao_merge`, a menos do arredondamento, também numa issue reaberta. Uma issue sem `reopened` dá exatamente os mesmos números de hoje.

**Escalonamentos.** Só contam os eventos `labeled escalonado` com `created_at` até o `closed_at`.

**Dois períodos.** As tabelas "Por marco" e "Por issue" ganham a coluna `Período`, a primeira, com o período da linha no formato `AAAA-MM-DD..AAAA-MM-DD`. Com um período só, a coluna não aparece. A tabela "Por issue" é ordenada por período, o primeiro antes, e dentro dele do fechamento mais recente para o mais antigo.

**Repositórios arquivados.** No corte de 100, a lista de repositórios vem de `gh repo list <dono> --limit 1000 --json nameWithOwner`, sem `--no-archived`. Um repositório arquivado com issue entregue no período entra no relatório. Um arquivado sem issue entregue não aparece, como qualquer repositório sem issue.

**Limite de taxa.** A busca do GitHub permite 30 requisições por minuto, num limite separado da API REST. Por isso, as buscas repetidas por repositório rodam em sequência, e não em paralelo. As outras consultas, como timeline, comentários e PR, continuam em paralelo. Se uma busca falhar por limite de taxa:
1. leia `gh api rate_limit -q .resources.search.reset`, um horário em segundos Unix;
2. espere até esse horário;
3. repita a busca uma vez.

Se a repetição falhar de novo, siga sem esse repositório e acrescente às Notas: "Não lidos por limite de taxa: <repos>."

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Uma issue criada às 10:00, fechada às 11:00, reaberta às 13:00 e fechada de novo às 14:00, sem `agente`, dá `abertura_ao_merge` = 120. Sem o `reopened` e com o mesmo `closed_at` final, o resultado continua igual ao de hoje (240). | unitário (`scripts/test-durations.sh`) |
| CA2 | Numa issue reaberta com `agente`, com `precisa-info` aplicada antes do primeiro fechamento e retirada depois da reabertura, `esperando_voce` não conta o intervalo fechado, e `antes_do_fluxo + esperando_voce + com_o_agente` difere de `abertura_ao_merge` em no máximo 1 minuto. | unitário (`scripts/test-durations.sh`) |
| CA3 | Um `labeled escalonado` com `created_at` posterior ao `closed_at` não entra em `escalonamentos`, e um anterior entra. | unitário (`scripts/test-durations.sh`) |
| CA4 | As timelines de exemplo sem `reopened` e sem escalonamento tardio, inclusive uma issue sem `agente` e outra com `spec-pronta` sem `spec-aprovada`, dão os mesmos números que o `durations.py` da `main` dá hoje. | unitário (`scripts/test-durations.sh`) |
| CA5 | `skills/metricas/SKILL.md` descreve os intervalos fechados e o corte dos escalonamentos no passo 3, e a coluna `Período` das tabelas "Por marco" e "Por issue" com dois períodos no passo 5. O passo 5 também traz a ordenação por período, com um exemplo de comparação. | manual: leitura do diff |
| CA6 | No passo 2 de `skills/metricas/SKILL.md`, o corte de 100 usa `gh repo list <dono> --limit 1000 --json nameWithOwner`, sem `--no-archived`. As buscas por repositório rodam em sequência, com a espera única até `resources.search.reset` e a nota "Não lidos por limite de taxa" descritas em "Comportamento esperado". A regra "Rode as consultas independentes em paralelo" passa a excluir essas buscas. | manual: leitura do diff |
| CA7 | `docs/comandos.md`, na entrada do `/fabrica:metricas`, diz que o tempo em que uma issue reaberta ficou fechada não conta. A `version` em `.claude-plugin/plugin.json` sobe para `0.18.0`, e `bash scripts/test-durations.sh`, `bash scripts/test-costs.sh`, `bash scripts/test-stage-usage.sh`, `bash scripts/test-protect-main.sh` e `bash scripts/test-check-gh.sh` passam. | manual: rodar os scripts |

## Fora de escopo
- Mudar as métricas medidas ou o formato do relatório além da coluna `Período`.
- Mudar o `costs.py` ou a linha de custo.
- Tratar o limite de taxa das outras consultas (REST), que não se repetem por repositório.

## Desenho técnico
**Arquivos e módulos:**
- `skills/metricas/durations.py`:
  - ler também os eventos `closed` e `reopened` da timeline;
  - montar os intervalos fechados, de cada `closed` até o `reopened` seguinte, ignorando o que vier depois do `closed_at` final;
  - descontá-los nos quatro tempos;
  - limitar a contagem de `escalonado` ao `closed_at`.

  A interface de linha de comando e as chaves do JSON de saída não mudam.
- `scripts/test-durations.sh` (novo), no padrão de `scripts/test-costs.sh`: timelines de exemplo num `mktemp -d`, a função `check` e saída com código diferente de zero se algum caso falhar. Cobre do CA1 ao CA4.
- `skills/metricas/SKILL.md`: passo 2 (lista de repositórios, buscas em sequência, limite de taxa), passo 3 (intervalos fechados e escalonamentos) e passo 5 (coluna `Período`, ordenação e a nota de limite de taxa).
- `docs/comandos.md`: entrada do `/fabrica:metricas`.
- `CLAUDE.md`: a linha de `scripts/` cita os testes; acrescente `test-durations.sh` se a linha listar os scripts de teste.
- `.claude-plugin/plugin.json`: `version` para `0.18.0`.

**Dados:** nenhum.

**Interfaces:**
- `python3 durations.py <created_at> <closed_at> <timeline.json>`: mesma entrada e mesmas chaves de saída (`abertura_ao_merge`, `antes_do_fluxo`, `esperando_voce`, `com_o_agente`, `escalonamentos`).
- Relatório: coluna `Período` nas tabelas "Por marco" e "Por issue", só com dois períodos.

**Decisões:**
- Descontar os intervalos fechados de todos os tempos, e não só da abertura ao merge — assim as partes continuam somando o total. Alternativa descartada: medir a partir da última reabertura, o que apagaria o trabalho feito antes do primeiro fechamento.
- Limitar os escalonamentos ao `closed_at` final, e não excluir também os dos intervalos fechados — a issue pede só os posteriores ao fechamento, e um escalonamento numa issue fechada é raro. Alternativa descartada: excluir também os dos intervalos fechados, além do que a issue pede.
- Coluna `Período` nas tabelas, e não uma seção por período — mantém uma tabela só, fácil de comparar linha a linha. Alternativa descartada: repetir "Por marco" e "Por issue" sob um título por período, o que dobra as tabelas.
- Buscas em sequência, com uma espera única até o `reset` em caso de erro — a fábrica tem poucos repositórios, então a sequência custa segundos, e a espera usa o horário que o GitHub informa. Alternativa descartada: uma pausa fixa entre buscas, que atrasa todas as execuções e ainda pode falhar.

**Fontes da documentação:**
- gh 2.103.3: `gh repo list --help` (tem `--archived`, `--no-archived` e `--limit`), `gh search issues --help` (`--state {open|closed}`, `--closed`, `--limit`) e `gh api rate_limit` (campo `.resources.search` com `limit`, `remaining` e `reset`), conferidos nesta máquina.
- Eventos `closed` e `reopened` da timeline: API REST de timeline do GitHub, conferida pela saída de `gh api repos/ftenorio99/fabrica/issues/52/timeline`, que traz `closed`. O `reopened` não foi visto numa issue real, então é "não verificada" (nome do evento segundo a documentação da API).

**ADR:** nenhum.

## Testes
- `scripts/test-durations.sh`: cobre do CA1 ao CA4. A referência do CA4 são os números do `durations.py` da `main`, calculados uma vez e gravados como esperados no teste.
- CA5 e CA6: leitura do diff.
- CA7: rodar os cinco scripts de teste.

## Riscos e dúvidas
- **Nome do evento `reopened`:** se a timeline real usar outro nome, o desconto não acontece. Na implementação, confira numa issue reaberta de verdade, ou reabra e feche uma issue de teste, e anote o resultado no PR.
- **Conflito de versão:** a #69, a #70, a #71 e a #79 também sobem a versão. A que entrar depois ajusta o número no rebase.

## Histórico
- 2026-11-06: criação.
