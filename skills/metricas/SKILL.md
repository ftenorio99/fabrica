---
name: metricas
description: Mede o desempenho da fábrica a partir dos eventos do GitHub - por issue entregue, por marco e por repositório - com o tempo da abertura ao merge, o tempo esperando o usuário e o tempo com o agente, dividido em fila e trabalho, os tokens gastos, as rodadas de triagem e de spec, as respostas no PR, os escalonamentos e as lições. Compara dois períodos para medir o efeito de uma mudança na fábrica. Só lê, não altera nada. Use quando o usuário perguntar como a fábrica está indo, quanto tempo as issues levam ou se uma mudança melhorou o fluxo.
argument-hint: "[repositório] [AAAA-MM-DD..AAAA-MM-DD] [AAAA-MM-DD..AAAA-MM-DD]"
---

# Métricas da fábrica

Argumentos: $ARGUMENTS

Esta skill só lê. Ela não aplica labels, não comenta e não cria arquivo no repositório. Os tempos saem da timeline de cada issue e são calculados pelo script [durations.py](durations.py). Os tokens e o trabalho do agente saem das linhas de custo dos comentários e são somados pelo script [costs.py](costs.py). Nada disso é calculado de cabeça.

## 1. Argumentos
- Um argumento com `..` é período (`AAAA-MM-DD..AAAA-MM-DD`, com as datas inclusivas). Qualquer outro é o repositório.
- **Sem período:** os últimos 30 dias até hoje (`date -u +%F`).
- **Um período:** só ele. **Dois períodos:** o segundo é comparado ao primeiro.
- **Validação:** antes de qualquer consulta, cada ponta do período precisa casar com `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`, e `date -d <data> +%F` precisa devolver exatamente a mesma string. Só o `date -d` não basta, porque ele aceita `x`, `tomorrow` e `2026-1-5`. O início também não pode ser posterior ao fim. Se algo falhar, pare e mostre o formato esperado: `AAAA-MM-DD..AAAA-MM-DD`.

## 2. Coletar
- Dono: `gh api user -q .login`.
- **Issues entregues** em cada período: `gh search issues --owner <dono> --state closed --label agente --closed <desde>..<até> --sort updated --order desc --json repository,number,title,createdAt,closedAt,url --limit 100 -- reason:completed`. Com repositório, use `--repo <dono>/<repositório>` no lugar de `--owner`. Ponha toda opção do `gh` antes do `--`. Uma issue fechada como "not planned" não entra.
- **Limite de 100 por repositório:** sem repositório, o `--limit 100` vale para todos somados. Se a busca por `--owner` trouxer 100 issues, liste os repositórios do dono (`gh repo list <dono> --no-archived --limit 1000 --json nameWithOwner`) e repita a busca com `--repo` para cada um, inclusive os que não apareceram no corte. Um repositório que trouxer 100 issues na própria busca foi cortado nas 100 de atualização mais recente: anote o nome para as notas.
- Para cada issue, numa pasta temporária da sessão:
  - **Issue:** `gh api repos/<repo>/issues/<nº>` → `created_at`, `closed_at` e `milestone.title`.
  - **Timeline:** `gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp > <pasta>/tl-<nº>.json`. Confira que há um evento `labeled` com a label `agente`; sem ele, a issue não entra.
  - **Comentários:** `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp > <pasta>/ci-<nº>.json`.
  - **PR:** a branch está no comentário `<!-- fabrica:spec -->` mais recente (`**Branch:**`). Com ela, `gh pr list -R <repo> --head <branch> --state merged --json number` e os comentários do PR com `gh api repos/<repo>/issues/<nº do PR>/comments --paginate --slurp > <pasta>/cp-<nº>.json`.

Rode as consultas independentes em paralelo.

## 3. Calcular por issue
- **Tempos:** `python3 <pasta desta skill>/durations.py <created_at> <closed_at> <pasta>/tl-<nº>.json`. O script devolve, em minutos:
  - `abertura_ao_merge`;
  - `antes_do_fluxo`, da criação até o primeiro `labeled agente`;
  - `esperando_voce`, o tempo em que valia um portão do usuário: `precisa-info`, `escalonado` ou `pronto-revisao` na issue, ou `spec-pronta` sem `spec-aprovada`. Os intervalos são unidos, então o mesmo minuto não conta duas vezes;
  - `com_o_agente`, do primeiro `agente` ao fechamento, menos `esperando_voce`;
  - `escalonamentos`, os eventos `labeled escalonado`.
- **Tokens e trabalho:** `python3 <pasta desta skill>/costs.py <pasta>/ci-<nº>.json <pasta>/cp-<nº>.json` (sem PR, `-` no lugar do segundo arquivo). O script lê as linhas `<!-- fabrica:custo ... -->` que as etapas deixam no fim dos seus comentários e devolve:
  - `medida`: se cada comentário de triagem e de spec da issue e cada resposta `<!-- fabrica:revisar -->` do PR tem a linha da própria etapa, sem nenhuma linha `tokens=nao-medido` nem `parcial=sim`;
  - `tokens`: a soma de entrada, saída e cache das linhas;
  - `trabalho_min`: a soma de `fim − inicio` das linhas.

  Numa issue não medida, `tokens` e `trabalho_min` vêm `null`.
- **Fila:** `com_o_agente` menos `trabalho_min`, só numa issue medida. Se der negativo, o que acontece quando uma etapa roda com um portão do usuário aplicado (como o `revisar` tratando pedidos com `pronto-revisao`), mostre `0min`.
- **Contagens nos comentários:**
  - **Rodadas de triagem:** comentários da issue que começam com `<!-- fabrica:triagem -->`.
  - **Rodadas de spec:** comentários da issue que começam com `<!-- fabrica:spec -->`.
  - **Respostas no PR:** comentários do PR que começam com `<!-- fabrica:revisar -->`.
  - **Lições:** blocos `**Lição · ` nos comentários que começam com `<!-- fabrica:licao`, na issue e no PR.
- **Dado ausente** (sem comentário de spec, PR não encontrado, campo `null` do `durations.py`): mostre `—`, nunca zero.
- **Issue não medida:** Tokens, Trabalho e Fila mostram "não medido".
- **Formato dos tokens:** a partir de 1 milhão, `1,2M`; a partir de mil, `850k`; abaixo disso, o número.
- **Formato dos tempos:** abaixo de 60 min, `12min`; a partir daí, `1h05`; a partir de 24 h, `3d04h`.

## 4. Agregar
Para cada repositório e cada marco (a milestone da issue; sem milestone, "sem marco"):
- **Entregues:** quantas issues.
- **Medianas:** de "Abertura ao merge", "Esperando você" e "Com o agente", com `python3 -c 'import statistics,sys; print(statistics.median(map(float, sys.argv[1:])))' <valores>`. Ignore os `—`.
- **Lições por issue:** total de lições dividido pelas entregues, com uma casa decimal.
- **Medidas:** quantas issues entregues são medidas. Só elas entram nas três colunas seguintes.
- **Tokens:** a soma das issues medidas.
- **Trabalho e Fila:** as medianas das issues medidas, com o mesmo comando de mediana. Sem nenhuma issue medida, as três colunas mostram "não medido".

Com dois períodos, calcule tudo para cada um. A diferença é a mediana do segundo menos a do primeiro (ex.: `−12min`), e a dos tokens é a soma do segundo menos a do primeiro. Um período sem issue entregue mostra `—`.

## 5. Responder
No chat, neste formato, omitindo as seções vazias:

```markdown
**Período:** 2026-11-01..2026-11-04 · **Repositórios:** fabrica

## Por repositório
| Repositório | Entregues | Abertura ao merge | Esperando você | Com o agente | Lições/issue | Medidas | Tokens | Trabalho | Fila |
|---|---|---|---|---|---|---|---|---|---|
| fabrica | 3 | 37min | 6min | 6min | 0,0 | 1 | 2,4M | 18min | 9min |

## Comparação
| Repositório | Métrica | 2026-10-01..2026-10-31 | 2026-11-01..2026-11-30 | Diferença |
|---|---|---|---|---|
| fabrica | Esperando você | 18min | 6min | −12min |
| fabrica | Trabalho | não medido | 18min | — |
| fabrica | Tokens | não medido | 2,4M | — |

## Por marco
| Repositório | Marco | Entregues | Abertura ao merge | Esperando você | Com o agente | Lições/issue | Medidas | Tokens | Trabalho | Fila |
|---|---|---|---|---|---|---|---|---|---|---|
| fabrica | sem marco | 3 | 37min | 6min | 6min | 0,0 | 1 | 2,4M | 18min | 9min |

## Por issue
| Issue | Abertura ao merge | Antes do fluxo | Esperando você | Com o agente | Trabalho | Fila | Triagem | Spec | Respostas no PR | Escalonamentos | Lições | Tokens |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [fabrica#58](url) | 1h10 | 5min | 38min | 27min | 18min | 9min | 1 | 1 | 1 | 0 | 0 | 2,4M |
| [fabrica#50](url) | 37min | 26min | 5min | 6min | não medido | não medido | 1 | 1 | 2 | 0 | 0 | não medido |

## Notas
- "Com o agente" inclui a espera até o comando ser rodado. Numa issue medida, ele se divide em Trabalho, o tempo das etapas, e Fila, o resto.
- Tokens e trabalho só contam as issues medidas: as etapas registradas a partir da versão 0.13.0 da fábrica, rodadas no terminal, sem linha `parcial=sim`, que marca uma soma feita antes de o log da sessão terminar de ser gravado. Etapas no GitHub Actions ainda não são medidas.
- A leitura vai até 100 issues por repositório, as de atualização mais recente. <"Nenhum repositório chegou ao limite." ou "Cortados no limite: <repos>.">
```

As três notas aparecem sempre. Ordene a tabela por issue da mais recente para a mais antiga, pelo fechamento.

## Regras
- **Só leitura:** nenhum comando que altere o GitHub ou o repositório. Os arquivos de timeline ficam na pasta temporária da sessão.
- Calcule os tempos com o script e as medianas com `python3`, nunca de cabeça.
- Não invente dados: um campo sem fonte no histórico é `—`.
