#!/usr/bin/env bash
# Instala a statusline da fábrica. Copia scripts/statusline.sh para uma pasta
# estável do usuário e aponta o statusLine do settings.json do Claude Code para
# ela. Plugins não podem definir statusLine, por isso a instalação é por máquina.
# Uso: scripts/setup-statusline.sh [--check] [--force]
#   --check  não muda o settings.json; imprime "ok", "ausente", "outra <comando>"
#            ou "atualizado <versão>" (neste caso, a cópia foi atualizada).
#   --force  substitui uma statusLine de outra origem.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/statusline.sh"
plugin_json="$script_dir/../.claude-plugin/plugin.json"
dest_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fabrica"
dest="$dest_dir/statusline.sh"
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

fail() {
  echo "setup-statusline: $*" >&2
  exit 1
}

check=false
force=false
for arg in "$@"; do
  case $arg in
    --check) check=true ;;
    --force) force=true ;;
    *) fail "opção desconhecida: $arg. Uso: setup-statusline.sh [--check] [--force]" ;;
  esac
done

command -v jq >/dev/null || fail "o jq não está instalado. A statusline e este script precisam dele."
[[ -f "$source_file" ]] || fail "não encontrei $source_file."
version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$plugin_json")"
[[ -n "$version" ]] || fail "não encontrei a version em $plugin_json."

copy_script() {
  mkdir -p "$dest_dir"
  cp "$source_file" "$dest"
  chmod +x "$dest"
  echo "$version" >"$dest_dir/statusline.VERSION"
}

current=""
if [[ -f "$settings" ]]; then
  current="$(jq -r '.statusLine.command // ""' "$settings")" || fail "o $settings não é um JSON válido. Nada foi alterado."
fi

if $check; then
  if [[ -z "$current" ]]; then
    echo ausente
  elif [[ "$current" != "$dest" ]]; then
    echo "outra $current"
  elif [[ "$(cat "$dest_dir/statusline.VERSION" 2>/dev/null)" != "$version" || ! -f "$dest" ]]; then
    copy_script
    echo "atualizado $version"
  else
    echo ok
  fi
  exit 0
fi

if [[ -n "$current" && "$current" != "$dest" ]] && ! $force; then
  fail "o statusLine do $settings já aponta para \"$current\". Nada foi alterado. Para trocar pela statusline da fábrica, rode de novo com --force."
fi

copy_script
mkdir -p "$(dirname "$settings")"
[[ -f "$settings" ]] || echo '{}' >"$settings"
cp "$settings" "$settings.bak-fabrica"
tmp="$(mktemp "$settings.XXXXXX")"
jq --arg cmd "$dest" '.statusLine = {type: "command", command: $cmd, refreshInterval: 60}' "$settings" >"$tmp"
mv "$tmp" "$settings"
echo "instalada $version"
