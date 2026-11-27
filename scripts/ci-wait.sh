#!/usr/bin/env bash
# Espera o CI de um commit pelos runs do GitHub Actions (SPEC-136). Lê a API do
# Actions, e não os checks, que o token fine-grained não lê.
#
# Uso: ci-wait.sh <dono>/<repo> <sha> <desde>
#   <desde> é o início da espera em UTC (AAAA-MM-DDTHH:MM:SSZ). Cada chamada roda
#   no máximo uma fatia; com o código 6, chame de novo com os mesmos argumentos.
#
# Imprime uma linha por mudança de estado de cada run e termina com
# "resultado: <nome>" e o código:
#   0  verde           todos os runs terminaram em success, skipped ou neutral
#   1  vermelho        todos terminaram e algum falhou (linhas "falhou:")
#   2  uso inválido    sem consultar a API
#   3  sem-ci          nenhum run 10 minutos depois do <desde>
#   4  tempo-esgotado  60 minutos depois do <desde> sem o CI terminar
#   5  erro-leitura    5 falhas seguidas da consulta, ou falha no tempo máximo
#   6  continua        a fatia acabou sem resultado
#
# Os testes trocam os prazos, em segundos, pelas variáveis FABRICA_CI_WAIT_INTERVAL
# (30), FABRICA_CI_WAIT_SLICE (100), FABRICA_CI_WAIT_NO_CI (600) e
# FABRICA_CI_WAIT_MAX (3600).
set -uo pipefail

max_failures=5
# Teto de uma consulta, para um gh pendurado não estourar o tempo do comando.
query_timeout=15
filter='.workflow_runs[] | [.name, .status, .conclusion, .html_url] | @tsv'
tab=$'\t'

usage() {
  echo "ci-wait: $1" >&2
  echo "uso: ci-wait.sh <dono>/<repo> <sha> <AAAA-MM-DDTHH:MM:SSZ>" >&2
  exit 2
}

(($# == 3)) || usage "são 3 argumentos"
repo=$1 sha=$2 since=$3
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage "repositório inválido"
[[ "$sha" =~ ^[0-9a-f]{7,64}$ ]] || usage "SHA inválido"
[[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || usage "<desde> fora do formato"
since_s=$(date -u -d "$since" +%s 2>/dev/null) || usage "<desde> não é uma data"
((since_s <= $(date +%s))) || usage "<desde> no futuro"

interval=${FABRICA_CI_WAIT_INTERVAL-30}
slice=${FABRICA_CI_WAIT_SLICE-100}
no_ci=${FABRICA_CI_WAIT_NO_CI-600}
max=${FABRICA_CI_WAIT_MAX-3600}
for value in "$interval" "$slice" "$no_ci" "$max"; do
  [[ "$value" =~ ^[0-9]+$ ]] || usage "as variáveis FABRICA_CI_WAIT_* são segundos inteiros"
done
interval=$((10#$interval)) slice=$((10#$slice)) no_ci=$((10#$no_ci)) max=$((10#$max))

err_file=$(mktemp) || exit 5
trap 'rm -f "$err_file"' EXIT

limit=()
command -v timeout >/dev/null 2>&1 && limit=(timeout "$query_timeout")

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

finish() { # finish <resultado> <código>
  echo "resultado: $1"
  exit "$2"
}

declare -A seen=()
failures=0 first=1
slice_end=$(($(date +%s) + slice))
max_end=$((since_s + max))

while true; do
  query_start=$(date +%s)
  if runs=$("${limit[@]}" gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=100" --jq "$filter" 2>"$err_file"); then
    failures=0
    total=0 pending=0 failed=()
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      # Separa à mão: o read com IFS de tab juntaria uma conclusion vazia.
      name=${line%%"$tab"*} rest=${line#*"$tab"}
      status=${rest%%"$tab"*} rest=${rest#*"$tab"}
      conclusion=${rest%%"$tab"*} url=${rest#*"$tab"}
      total=$((total + 1))
      state="$status$tab$conclusion"
      if [[ "${seen[$url]-}" != "$state" ]]; then
        printf '%s %s\t%s\t%s\t%s\n' "$(now_utc)" "$name" "$status" "$conclusion" "$url"
        seen[$url]=$state
      fi
      if [[ "$status" != completed ]]; then
        pending=$((pending + 1))
      elif [[ ! "$conclusion" =~ ^(success|skipped|neutral)$ ]]; then
        failed+=("$name$tab$conclusion$tab$url")
      fi
    done <<<"$runs"
    if ((first && total == 0)); then
      echo "$(now_utc) nenhum run do head"
    fi
    first=0

    now=$(date +%s)
    if ((total > 0 && pending == 0)); then
      ((${#failed[@]} == 0)) && finish verde 0
      printf 'falhou: %s\n' "${failed[@]}"
      finish vermelho 1
    fi
    ((total == 0 && now - since_s >= no_ci)) && finish sem-ci 3
    ((now >= max_end)) && finish tempo-esgotado 4
  else
    code=$?
    message=$(head -n 1 "$err_file")
    ((code == 124)) && message="a consulta passou de $query_timeout s"
    echo "$(now_utc) falha ao ler os runs: ${message:-código $code}"
    failures=$((failures + 1))
    now=$(date +%s)
    # No tempo máximo não há mais o que esperar: sem isso, consultas lentas que
    # falham não juntariam 5 numa fatia, e a etapa chamaria o script sem fim.
    ((failures >= max_failures || now >= max_end)) && finish erro-leitura 5
  fi

  ((now >= slice_end)) && finish continua 6

  # O intervalo conta do início da consulta, sem passar do fim da fatia nem do
  # tempo máximo.
  next=$((query_start + interval))
  ((next > slice_end)) && next=$slice_end
  ((next > max_end)) && next=$max_end
  ((next > now)) && sleep $((next - now))
done
