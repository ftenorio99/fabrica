#!/usr/bin/env bash
# PreToolUse (Bash): impede o agente de desligar os hooks do git da fábrica.
# Quem recusa commit e push na main/master são os hooks globais do git
# (githooks/, instalados por scripts/setup-githooks.sh). Este hook só faz
# checagens de texto sobre o comando inteiro, sem separar aspas, contra o
# que desligaria esses hooks, no núcleo do ADR 0002. Falsos positivos raros
# são aceitos (ex.: um corpo de PR que cita --no-verify); o contorno é
# escrever o texto num arquivo e passar --body-file ao gh.
#
# Aceita dois contratos de entrada e responde no de quem chamou:
#   Claude Code:  .tool_input.command          -> hookSpecificOutput
#   Antigravity:  .toolCall.args.CommandLine   -> {decision, reason}

input=$(cat)
cmd=$(jq -r '.tool_input.command // .toolCall.args.CommandLine // ""' <<<"$input")
[[ -n $cmd ]] || exit 0

deny() {
  if jq -e 'has("toolCall")' <<<"$input" >/dev/null 2>&1; then
    jq -n --arg r "$1" '{decision: "deny", reason: $r}'
  else
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  fi
  exit 0
}

disable() {
  deny "Este comando desligaria os hooks do git que protegem a main ($1). Se for intencional, rode você mesmo no terminal."
}

# Mesmo destino de scripts/setup-githooks.sh. Sem os hooks instalados, a
# main fica sem proteção: bloqueia na dúvida.
dest="${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks"
if [[ "$(git config --global --get core.hooksPath 2>/dev/null)" != "$dest" && $cmd =~ commit|push ]]; then
  deny "Os hooks do git que protegem a main não estão instalados. Rode /fabrica:setup e repita o comando."
fi

# Linhas continuadas com \ contam como uma só.
flat=${cmd//$'\\\n'/ }

# O git aceita prefixos de opção longa; abaixo de --no-veri, há ambiguidade
# com --no-verbose.
[[ $cmd == *--no-veri* ]] && disable "--no-verify"
# commit seguido de uma opção curta com n (-n, -nm, -an) no mesmo trecho,
# até ; & | ou o fim da linha.
grep -Eq 'commit[^;&|]*[[:space:]]-[[:alnum:]]*n' <<<"$flat" && disable "commit -n"
[[ ${cmd,,} == *hookspath* ]] && disable "core.hooksPath"
[[ $cmd == *GIT_CONFIG* ]] && disable "variável GIT_CONFIG*"
[[ $cmd =~ (^|[^[:alnum:]_])(HOME|XDG_CONFIG_HOME)= ]] && disable "troca do ${BASH_REMATCH[2]}"
[[ $cmd == *fabrica/githooks* ]] && disable "mexe na pasta dos hooks"
exit 0
