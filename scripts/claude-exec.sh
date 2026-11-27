#!/usr/bin/env bash
# Executor interno do stage-model.sh. Recebe a seleção já resolvida.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage="$1" number="$2" model="$3" effort="$4"
if [[ -n "$5" ]]; then
  export BASH_ENV="$6"
else
  unset BASH_ENV
fi

# bypassPermissions só dentro da VM do sbx com o projeto em modo sbx
# (SPEC-179, ADR 0013). Uma falha nas sondas também cai em auto.
permission_mode() {
  local where mode
  where="$(bash "$script_dir/sbx-context.sh" --project "$PWD" 2>/dev/null | awk '$1 == "onde" { print $2 }')" || where=""
  mode="$(bash "$script_dir/setup-isolation.sh" --check --project "$PWD" 2>/dev/null)" || mode=""
  if [[ "$where" == "vm" && "$mode" == "sbx" ]]; then
    echo bypassPermissions
  else
    echo auto
  fi
}

args=(-p --model "$model")
[[ "$effort" == "padrao" ]] || args+=(--effort "$effort")
args+=(--permission-mode "$(permission_mode)" --output-format json)
# Fora do cache, o processo precisa carregar o clone de onde a fachada roda.
plugin_root="$(cd "$script_dir/.." && pwd -P)"
plugins_dir="${HOME:-}/.claude/plugins"
case $plugin_root in
  "$plugins_dir"/*) ;;
  *) args+=(--plugin-dir "$plugin_root") ;;
esac
args+=("/fabrica:$stage $number")

exec "${FABRICA_CLAUDE_BIN:-claude}" "${args[@]}"
