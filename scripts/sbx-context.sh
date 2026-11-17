#!/usr/bin/env bash
# Diz ao /fabrica:setup onde ele roda e os dados do checklist do modo sbx
# (SPEC-147). Não roda nenhum comando sbx e não grava nada.
# Uso: scripts/sbx-context.sh [--project <dir>]
# Imprime sempre quatro linhas, nesta ordem:
#   onde vm|host          vm quando o arquivo de sinal existe ou o
#                         PROXY_CA_CERT_B64 não está vazio
#   nome claude-<pasta>   o nome padrão do sbx (<agente>-<pasta>) para o projeto
#   token marcador|ausente|real   o formato do GH_TOKEN
#   e2e sim|não           o Makefile do projeto tem um alvo e2e:
# O arquivo de sinal é o /etc/sandbox-persistent.sh, que o Bash lê dentro da
# sandbox; FABRICA_SBX_PERSISTENT_FILE troca o caminho, para os testes.
# Saída: 0 sucesso; 1 uso inválido ou projeto não encontrado.
set -euo pipefail

usage="Uso: sbx-context.sh [--project <dir>]"

fail() {
  echo "sbx-context: $*" >&2
  exit 1
}

project=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      [[ $# -ge 2 ]] || fail "--project precisa de um diretório."
      project="$2"
      shift
      ;;
    *) fail "opção desconhecida: $1. $usage" ;;
  esac
  shift
done

if [[ -z "$project" ]]; then
  project="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "não estou num repositório git. Use --project <dir>."
fi
[[ -d "$project" ]] || fail "o diretório $project não existe."
# Com --project numa subpasta, o nome continua sendo o da pasta do topo.
top="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null)" || top="$project"
top="$(cd "$top" && pwd)"

signal_file="${FABRICA_SBX_PERSISTENT_FILE:-/etc/sandbox-persistent.sh}"
if [[ -e "$signal_file" || -n "${PROXY_CA_CERT_B64:-}" ]]; then
  echo "onde vm"
else
  echo "onde host"
fi

echo "nome claude-$(basename "$top")"

# A mesma expressão do token-marcador do test-sandbox-acceptance.sh.
real_token='gh[opsu]_[A-Za-z0-9]{30,}|github_pat_'
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "token ausente"
elif [[ "$GH_TOKEN" =~ $real_token ]]; then
  echo "token real"
else
  echo "token marcador"
fi

if [[ -f "$top/Makefile" ]] && grep -q '^e2e:' "$top/Makefile"; then
  echo "e2e sim"
else
  echo "e2e não"
fi
