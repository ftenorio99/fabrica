#!/usr/bin/env bash
# Lê e grava o modo de isolamento do projeto (ADR 0010) em
# .fabrica/isolamento.txt: "sbx" (VM do Docker Sandboxes) ou "sem-sandbox"
# (direto na máquina). No arquivo, linhas vazias e começadas com # são
# ignoradas, e vale a primeira linha restante, sem os espaços das pontas.
# Uso: scripts/setup-isolation.sh [--check] [--set sbx|sem-sandbox] [--project <dir>]
#   --check  (padrão) não grava nada; imprime "ausente", "inválido", "sbx" ou
#            "sem-sandbox".
#   --set    grava o modo; imprime "gravado <modo>" ou, se o arquivo já estava
#            nesse modo, "ok <modo>".
# Avisa em stderr quando o .claude/settings.json do projeto ainda tem o sandbox
# nativo ligado (sandbox.enabled: true). Nunca altera esse arquivo.
# Saída: 0 sucesso; 1 uso inválido ou projeto não encontrado.
set -euo pipefail

usage="Uso: setup-isolation.sh [--check] [--set sbx|sem-sandbox] [--project <dir>]"

fail() {
  echo "setup-isolation: $*" >&2
  exit 1
}

check=false
mode=""
set_given=false
project=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) check=true ;;
    --set)
      [[ $# -ge 2 ]] || fail "--set precisa de um modo: sbx ou sem-sandbox."
      mode="$2"
      set_given=true
      shift
      ;;
    --project)
      [[ $# -ge 2 ]] || fail "--project precisa de um diretório."
      project="$2"
      shift
      ;;
    *) fail "opção desconhecida: $1. $usage" ;;
  esac
  shift
done

if $check && $set_given; then
  fail "--check e --set não vão juntos. $usage"
fi
if $set_given && [[ "$mode" != "sbx" && "$mode" != "sem-sandbox" ]]; then
  fail "modo inválido: $mode. Os modos aceitos são sbx e sem-sandbox."
fi

if [[ -z "$project" ]]; then
  project="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "não estou num repositório git. Use --project <dir>."
fi
[[ -d "$project" ]] || fail "o diretório $project não existe."

file="$project/.fabrica/isolamento.txt"

# Imprime o modo gravado: "ausente", "inválido", "sbx" ou "sem-sandbox".
current_mode() {
  [[ -f "$file" ]] || { echo "ausente"; return; }
  local line value=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    value="$line"
    break
  done <"$file"
  case $value in
    sbx | sem-sandbox) echo "$value" ;;
    *) echo "inválido" ;;
  esac
}

# O bloco sandbox do settings do projeto é do sandbox nativo, que saiu da
# fábrica; dentro da VM do sbx, ele esconde o GH_TOKEN.
warn_native_sandbox() {
  local settings="$project/.claude/settings.json"
  [[ -f "$settings" ]] || return 0
  command -v jq >/dev/null || return 0
  if [[ "$(jq -r 'try (.sandbox.enabled == true) catch false' "$settings" 2>/dev/null)" == "true" ]]; then
    echo "setup-isolation: sandbox nativo ligado em .claude/settings.json" >&2
  fi
}

warn_native_sandbox

if ! $set_given; then
  current_mode
  exit 0
fi

if [[ "$(current_mode)" == "$mode" ]]; then
  echo "ok $mode"
  exit 0
fi

mkdir -p "$project/.fabrica"
printf '%s\n' "$mode" >"$file"
echo "gravado $mode"
