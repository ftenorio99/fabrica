#!/usr/bin/env bash
# Instala o workflow do dispatcher num projeto (SPEC-108): copia
# templates/workflows/agente.yml do plugin para .github/workflows/agente.yml
# do repositório git atual. Não faz commit, não roda git add nem gh: o
# usuário leva o arquivo à branch padrão por uma branch e um PR.
# Uso: scripts/setup-dispatcher.sh --check | --apply
#   --check  não grava nada; imprime "ausente", "ok" (igual, byte a byte, ao
#            modelo) ou "desatualizado" (difere do modelo). No desatualizado,
#            imprime em stderr "diferença: +<n> -<m> linhas": as linhas que a
#            troca traz do modelo e as do arquivo atual que ela tira.
#   --apply  grava o arquivo igual ao modelo, criando .github/workflows/.
# Saídas: 0 ok; 1 erro (nada é gravado).
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model="$script_dir/../templates/workflows/agente.yml"
rel=".github/workflows/agente.yml"

fail() {
  echo "setup-dispatcher: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail "uso: setup-dispatcher.sh --check | --apply"
case $1 in
  --check | --apply) mode="$1" ;;
  *) fail "opção desconhecida: $1. Uso: setup-dispatcher.sh --check | --apply" ;;
esac

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "não estou dentro de um repositório git."
[[ -f "$model" ]] || fail "não encontrei o modelo do workflow em $model."
dest="$root/$rel"

if [[ "$mode" == "--check" ]]; then
  if [[ ! -e "$dest" ]]; then
    echo ausente
  elif cmp -s "$model" "$dest"; then
    echo ok
  else
    diff_out="$(diff -- "$dest" "$model")"
    added="$(grep -c '^>' <<<"$diff_out")"
    removed="$(grep -c '^<' <<<"$diff_out")"
    echo desatualizado
    echo "diferença: +$added -$removed linhas" >&2
  fi
  exit 0
fi

mkdir -p "$root/.github/workflows" || fail "não consegui criar .github/workflows/."
tmp="$(mktemp "$root/.github/workflows/.agente.yml.XXXXXX")" || fail "não consegui criar um arquivo temporário em .github/workflows/."
if ! cp "$model" "$tmp" || ! chmod 0644 "$tmp" || ! mv -f "$tmp" "$dest"; then
  rm -f "$tmp"
  fail "não consegui gravar $rel."
fi
echo "instalado $rel"
