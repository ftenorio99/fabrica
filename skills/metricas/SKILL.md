---
name: metricas
description: Mede o desempenho da fábrica a partir dos eventos do GitHub - por issue entregue, por marco e por repositório - com o tempo da abertura ao merge, o tempo esperando o usuário e o tempo com o agente, as rodadas de triagem e de spec, as respostas no PR, os escalonamentos e as lições. Compara dois períodos para medir o efeito de uma mudança na fábrica. Só lê, não altera nada. Use quando o usuário perguntar como a fábrica está indo, quanto tempo as issues levam ou se uma mudança melhorou o fluxo.
argument-hint: "[repositório] [AAAA-MM-DD..AAAA-MM-DD] [AAAA-MM-DD..AAAA-MM-DD]"
---

# Métricas da fábrica

Argumentos: $ARGUMENTS

Esta skill só lê. Ela não aplica labels, não comenta e não cria arquivo no repositório. Os tempos saem da timeline de cada issue e são calculados pelo script [durations.py](durations.py), nunca de cabeça.

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
  - **Comentários:** `gh api repos/<repo>/issues/<nº>/comments --paginate`.
  - **PR:** a branch está no comentário `<!-- fabrica:spec -->` mais recente (`**Branch:**`). Com ela, `gh pr list -R <repo> --head <branch> --state merged --json number` e os comentários do PR com `gh api repos/<repo>/issues/<nº do PR>/comments --paginate`.

Rode as consultas independentes em paralelo.

## 3. Calcular por issue
- **Tempos:** `python3 <pasta desta skill>/durations.py <created_at> <closed_at> <pasta>/tl-<nº>.json`. O script devolve, em minutos:
  - `abertura_ao_merge`;
  - `antes_do_fluxo`, da criação até o primeiro `labeled agente`;
  - `esperando_voce`, o tempo em que valia um portão do usuário: `precisa-info`, `escalonado` ou `pronto-revisao` na issue, ou `spec-pronta` sem `spec-aprovada`. Os intervalos são unidos, então o mesmo minuto não conta duas vezes;
  - `com_o_agente`, do primeiro `agente` ao fechamento, menos `esperando_voce`;
  - `escalonamentos`, os eventos `labeled escalonado`.
- **Contagens nos comentários:**
  - **Rodadas de triagem:** comentários da issue que começam com `<!-- fabrica:triagem -->`.
  - **Rodadas de spec:** comentários da issue que começam com `<!-- fabrica:spec -->`.
  - **Respostas no PR:** comentários do PR que começam com `<!-- fabrica:revisar -->`.
  - **Lições:** blocos `**Lição · ` nos comentários que começam com `<!-- fabrica:licao`, na issue e no PR.
- **Dado ausente** (sem comentário de spec, PR não encontrado, campo `null` do script): mostre `—`, nunca zero.
- **Tokens:** sempre "não medido".
- **Formato dos tempos:** abaixo de 60 min, `12min`; a partir daí, `1h05`; a partir de 24 h, `3d04h`.

## 4. Agregar
Para cada repositório e cada marco (a milestone da issue; sem milestone, "sem marco"):
- **Entregues:** quantas issues.
- **Medianas:** de "Abertura ao merge", "Esperando você" e "Com o agente", com `python3 -c 'import statistics,sys; print(statistics.median(map(float, sys.argv[1:])))' <valores>`. Ignore os `—`.
- **Lições por issue:** total de lições dividido pelas entregues, com uma casa decimal.

Com dois períodos, calcule tudo para cada um. A diferença é a mediana do segundo menos a do primeiro (ex.: `−12min`). Um período sem issue entregue mostra `—`.

## 5. Responder
No chat, neste formato, omitindo as seções vazias:

```markdown
**Período:** 2026-11-01..2026-11-04 · **Repositórios:** fabrica

## Por repositório
| Repositório | Entregues | Abertura ao merge | Esperando você | Com o agente | Lições/issue |
|---|---|---|---|---|---|
| fabrica | 3 | 37min | 6min | 6min | 0,0 |

## Comparação
| Repositório | Métrica | 2026-10-01..2026-10-31 | 2026-11-01..2026-11-30 | Diferença |
|---|---|---|---|---|
| fabrica | Esperando você | 18min | 6min | −12min |

## Por marco
| Repositório | Marco | Entregues | Abertura ao merge | Esperando você | Com o agente | Lições/issue |
|---|---|---|---|---|---|---|
| fabrica | sem marco | 3 | 37min | 6min | 6min | 0,0 |

## Por issue
| Issue | Abertura ao merge | Antes do fluxo | Esperando você | Com o agente | Triagem | Spec | Respostas no PR | Escalonamentos | Lições | Tokens |
|---|---|---|---|---|---|---|---|---|---|---|
| [fabrica#50](url) | 37min | 26min | 5min | 6min | 1 | 1 | 2 | 0 | 0 | não medido |

## Notas
- "Com o agente" inclui a espera até o comando ser rodado.
- Tokens não são medidos ainda: o custo por etapa fica para a [#58](https://github.com/ftenorio99/fabrica/issues/58).
- A leitura vai até 100 issues por repositório, as de atualização mais recente. <"Nenhum repositório chegou ao limite." ou "Cortados no limite: <repos>.">
```

As três notas aparecem sempre. Ordene a tabela por issue da mais recente para a mais antiga, pelo fechamento.

## Regras
- **Só leitura:** nenhum comando que altere o GitHub ou o repositório. Os arquivos de timeline ficam na pasta temporária da sessão.
- Calcule os tempos com o script e as medianas com `python3`, nunca de cabeça.
- Não invente dados: um campo sem fonte no histórico é `—`.
