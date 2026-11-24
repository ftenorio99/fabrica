#!/usr/bin/env bash
# Confere e instala o CI do PR num projeto (SPEC-128, ADR 0019): copia
# templates/workflows/ci.yml do plugin para .github/workflows/ci.yml do
# repositório git atual. Não faz commit, não roda git add nem gh: o usuário
# leva o arquivo à branch padrão por uma branch e um PR. A cópia é do projeto:
# o script nunca a sobrescreve nem a compara com o modelo.
# Uso: scripts/setup-ci.sh --check | --apply
#   --check  não grava nada; imprime:
#            "ausente"  nenhum workflow de .github/workflows/ dispara em
#                       pull_request (o agente.yml do dispatcher não conta);
#            "sem-e2e"  há workflow em pull_request, o Makefile tem o alvo
#                       e2e: e nenhum workflow contém "make e2e";
#            "ok"       nos outros casos.
#   --apply  grava .github/workflows/ci.yml igual ao modelo, criando a pasta;
#            sai com 1, sem gravar, se o arquivo já existe.
# Saídas: 0 ok; 1 erro (nada é gravado).
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model="$script_dir/../templates/workflows/ci.yml"
rel=".github/workflows/ci.yml"

fail() {
  echo "setup-ci: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail "uso: setup-ci.sh --check | --apply"
case $1 in
  --check | --apply) mode="$1" ;;
  *) fail "opção desconhecida: $1. Uso: setup-ci.sh --check | --apply" ;;
esac

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "não estou dentro de um repositório git."
[[ -f "$model" ]] || fail "não encontrei o modelo do CI em $model."
dest="$root/$rel"

# triggers_pull_request <arquivo>: sai com 0 se o workflow tem a chave
# pull_request dentro de on: (valor único, lista ou mapa).
triggers_pull_request() {
  local file="$1"
  if python3 -I -c 'import yaml' 2>/dev/null; then
    # O PyYAML lê a chave "on" como True; as duas grafias são aceitas.
    python3 -I -c '
import sys, yaml
try:
    w = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
if not isinstance(w, dict):
    sys.exit(1)
on = w.get("on", w.get(True))
if isinstance(on, str):
    sys.exit(0 if on == "pull_request" else 1)
if isinstance(on, (list, dict)):
    sys.exit(0 if "pull_request" in on else 1)
sys.exit(1)
' "$file"
    return
  fi
  # Sem PyYAML: as formas "on: pull_request", "on: [.., pull_request, ..]" e
  # "on:" em mapa, com "pull_request:" ou "- pull_request" logo abaixo.
  awk '
    function strip(s) { sub(/[[:space:]]+#.*$/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    {
      line = strip($0)
      if (match(line, /^["'\'']?on["'\'']?:/)) {
        rest = substr(line, RLENGTH + 1)
        sub(/^[[:space:]]+/, "", rest)
        if (rest == "") { inon = 1; next }
        inon = 0
        if (rest == "pull_request") { found = 1 }
        if (rest ~ /^\[/) {
          gsub(/[][[:space:]"'\'']/, "", rest)
          n = split(rest, parts, ",")
          for (i = 1; i <= n; i++) if (parts[i] == "pull_request") found = 1
        }
        next
      }
      if (inon) {
        if (line == "") next
        if (line !~ /^[[:space:]]/) { inon = 0; next }
        if (line ~ /^[[:space:]]+["'\'']?pull_request["'\'']?:/) found = 1
        if (line ~ /^[[:space:]]+-[[:space:]]*["'\'']?pull_request["'\'']?$/) found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

if [[ "$mode" == "--check" ]]; then
  has_pr=0 has_make_e2e=0
  shopt -s nullglob
  for f in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue
    # O workflow do dispatcher não é CI.
    [[ "$(basename "$f")" == "agente.yml" ]] && continue
    if triggers_pull_request "$f"; then
      has_pr=1
    fi
    if grep -Eq 'make[[:space:]]+e2e([^[:alnum:]_-]|$)' "$f"; then
      has_make_e2e=1
    fi
  done
  shopt -u nullglob
  has_e2e_target=0
  [[ -f "$root/Makefile" ]] && grep -q '^e2e:' "$root/Makefile" && has_e2e_target=1

  if [[ $has_pr -eq 0 ]]; then
    echo ausente
  elif [[ $has_e2e_target -eq 1 && $has_make_e2e -eq 0 ]]; then
    echo sem-e2e
  else
    echo ok
  fi
  exit 0
fi

if [[ -e "$dest" || -L "$dest" ]]; then
  fail "$rel já existe; a cópia é do projeto e o setup não a sobrescreve."
fi
mkdir -p "$root/.github/workflows" || fail "não consegui criar .github/workflows/."
tmp="$(mktemp "$root/.github/workflows/.ci.yml.XXXXXX")" || fail "não consegui criar um arquivo temporário em .github/workflows/."
if ! cp "$model" "$tmp" || ! chmod 0644 "$tmp" || ! mv -n "$tmp" "$dest" || [[ -e "$tmp" ]]; then
  rm -f "$tmp"
  fail "não consegui gravar $rel."
fi
echo "instalado $rel"
