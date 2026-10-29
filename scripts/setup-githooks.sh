#!/usr/bin/env bash
# Instala os hooks globais do git da fábrica, que recusam commit e push na
# main. Copia githooks/ para uma pasta estável do usuário e aponta o
# core.hooksPath global para ela.
# Uso: scripts/setup-githooks.sh [--check] [--force]
#   --check  não muda a configuração do git; imprime "ok", "ausente" ou
#            "atualizado <versão>" (neste caso, os arquivos foram copiados).
#   --force  sobrescreve um core.hooksPath global de outra ferramenta.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$script_dir/../githooks"
plugin_json="$script_dir/../.claude-plugin/plugin.json"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks"

fail() {
  echo "setup-githooks: $*" >&2
  exit 1
}

check=false
force=false
for arg in "$@"; do
  case $arg in
    --check) check=true ;;
    --force) force=true ;;
    *) fail "opção desconhecida: $arg. Uso: setup-githooks.sh [--check] [--force]" ;;
  esac
done

[[ -d "$source_dir" ]] || fail "não encontrei a pasta $source_dir."
version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$plugin_json")"
[[ -n "$version" ]] || fail "não encontrei a version em $plugin_json."

# Troca o conteúdo do destino pelo de githooks/, sem deixar entradas antigas.
copy_hooks() {
  mkdir -p "$dest"
  rm -f "$dest"/*
  cp "$source_dir"/* "$dest"/
  chmod +x "$dest"/*
  echo "$version" >"$dest/VERSION"
}

current="$(git config --global --get core.hooksPath || true)"

if $check; then
  if [[ "$current" != "$dest" ]]; then
    echo ausente
  elif [[ "$(cat "$dest/VERSION" 2>/dev/null)" != "$version" ]]; then
    copy_hooks
    echo "atualizado $version"
  else
    echo ok
  fi
  exit 0
fi

if [[ -n "$current" && "$current" != "$dest" ]] && ! $force; then
  fail "o core.hooksPath global já aponta para \"$current\", de outra ferramenta. Nada foi alterado. Para trocar pelos hooks da fábrica, rode de novo com --force."
fi

copy_hooks
git config --global core.hooksPath "$dest"
echo "Hooks do git da fábrica $version instalados em $dest (core.hooksPath global)."
