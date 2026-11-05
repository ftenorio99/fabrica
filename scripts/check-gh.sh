#!/usr/bin/env bash
# Confere se o gh está instalado, na versão mínima da fábrica e autenticado.
# Uso: scripts/check-gh.sh
# Imprime uma linha e sai com 0 só no "ok" (SPEC-39):
#   ausente | desatualizado <versão> <mínima> | sem-login <versão> | ok <versão>
set -uo pipefail

# Versão mínima do gh, definida só aqui. Abaixo dela, o `gh pr edit` falha com
# o erro de descontinuação dos Projects clássicos (cli/cli#11983). A 2.82.1 é a
# primeira release com a correção do PR cli/cli#11987.
MIN_GH_VERSION="2.82.1"

# version_ge <a> <b>: verdadeiro se a >= b, comparando campo a campo como números.
version_ge() {
  local IFS=.
  local -a a=($1) b=($2)
  local i x y
  for i in 0 1 2; do
    x=$((10#${a[i]:-0})) y=$((10#${b[i]:-0}))
    ((x > y)) && return 0
    ((x < y)) && return 1
  done
  return 0
}

if ! command -v gh >/dev/null 2>&1; then
  echo "ausente"
  exit 1
fi

first_line="$(gh --version 2>/dev/null | head -n 1)"
if [[ $first_line =~ ^gh\ version\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
  version="${BASH_REMATCH[1]}"
else
  echo "desatualizado desconhecida $MIN_GH_VERSION"
  exit 1
fi

if ! version_ge "$version" "$MIN_GH_VERSION"; then
  echo "desatualizado $version $MIN_GH_VERSION"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "sem-login $version"
  exit 1
fi

echo "ok $version"
