#!/usr/bin/env bash
# Cria ou corrige as labels da fábrica num repositório do GitHub.
# A fonte da verdade é a tabela "Labels" de skills/status/estados.md.
# Uso: scripts/setup-labels.sh [<dono>/<repo>]
set -euo pipefail
export LC_ALL=C.UTF-8

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
states_file="$script_dir/../skills/status/estados.md"

fail() {
  echo "setup-labels: $*" >&2
  exit 1
}

[[ -f "$states_file" ]] || fail "não encontrei a tabela de labels em $states_file."

# Extrai "nome<TAB>cor<TAB>descrição" das linhas da tabela "Labels".
rows="$(awk -F'|' '
  /^## / { in_labels = ($0 == "## Labels"); next }
  in_labels && /^\| *`/ {
    for (i = 2; i <= 5; i++) { gsub(/^ +| +$/, "", $i); gsub(/`/, "", $i) }
    print $2 "\t" $4 "\t" $5
  }
' "$states_file")"

[[ -n "$rows" ]] || fail "a tabela \"Labels\" de $states_file está vazia ou não foi encontrada."

# Valida tudo antes de chamar o GitHub.
while IFS=$'\t' read -r name color description; do
  [[ -n "$name" ]] || fail "linha da tabela \"Labels\" sem nome."
  [[ "$color" =~ ^[0-9a-fA-F]{6}$ ]] || fail "label \`$name\`: cor \"$color\" fora do formato RRGGBB."
  [[ -n "$description" ]] || fail "label \`$name\`: descrição vazia."
  (( ${#description} <= 100 )) || fail "label \`$name\`: descrição com ${#description} caracteres (máximo 100)."
done <<< "$rows"

gh auth status >/dev/null 2>&1 || fail "o gh não está autenticado. Rode \`gh auth login\`."

if [[ $# -ge 1 ]]; then
  repo="$1"
  gh repo view "$repo" --json nameWithOwner >/dev/null 2>&1 \
    || fail "o repositório $repo não existe ou não está acessível."
else
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
    || fail "sem argumento, rode dentro de um clone com remote no GitHub ou passe <dono>/<repo>."
fi

echo "Repositório: $repo"
while IFS=$'\t' read -r name color description; do
  gh label create "$name" --color "$color" --description "$description" --force -R "$repo" >/dev/null \
    || fail "falhou ao criar ou atualizar a label \`$name\` em $repo; as anteriores já foram aplicadas."
  echo "ok $name"
done <<< "$rows"
