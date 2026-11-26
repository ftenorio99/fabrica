#!/usr/bin/env bash
# PreToolUse (Bash, Edit, Write e MultiEdit): impede o agente de desligar os
# hooks do git da fábrica.
# Quem recusa commit e push na main/master são os hooks globais do git
# (githooks/, instalados por scripts/setup-githooks.sh). Este hook só faz
# checagens de texto sobre o comando inteiro, sem separar aspas, contra o
# que desligaria esses hooks, no núcleo do ADR 0002. Falsos positivos raros
# são aceitos (ex.: um corpo de PR que cita --no-verify); o contorno é
# escrever o texto num arquivo e passar --body-file ao gh.
# Nas ferramentas de arquivo, recusa os arquivos de configuração do git e a
# pasta dos hooks pelo caminho resolvido, nunca pelo conteúdo (SPEC-204).
#
# Aceita dois contratos de entrada e responde no de quem chamou:
#   Claude Code:  .tool_input.command          -> hookSpecificOutput
#                 .tool_input.file_path        -> hookSpecificOutput
#   Antigravity:  .toolCall.args.CommandLine   -> {decision, reason}

input=$(cat)

deny() {
  if jq -e 'has("toolCall")' <<<"$input" >/dev/null 2>&1; then
    jq -n --arg r "$1" '{decision: "deny", reason: $r}'
  else
    jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  fi
  exit 0
}

# Mesmo destino de scripts/setup-githooks.sh, ou o que o job grava em
# FABRICA_GITHOOKS_DEST (SPEC-107, CA25).
dest="${FABRICA_GITHOOKS_DEST:-${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks}"

# Edit, Write e MultiEdit: o caminho é resolvido a partir do cwd da entrada
# (relativo, .. e links simbólicos; o trecho que não existe fica como está) e
# comparado com os arquivos que o git lê como configuração e com a pasta dos
# hooks. A checagem de "hooks não instalados", mais abaixo, só vale no Bash.
file=$(jq -r '.tool_input.file_path // ""' <<<"$input")
if [[ -n $file ]]; then
  if [[ $file != /* ]]; then
    cwd=$(jq -r '.cwd // ""' <<<"$input")
    file="${cwd:-$PWD}/$file"
  fi
  path=$(realpath -m -- "$file" 2>/dev/null) || path=$file
  config_msg="Este arquivo é a configuração do git; editá-lo pode desligar os hooks que protegem a main. Se for intencional, edite você mesmo no terminal."
  case $path in
    */.git/config | */.git/config.worktree | */.git/worktrees/*/config.worktree | */.git/modules/*/config)
      deny "$config_msg" ;;
  esac
  protected=("$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config")
  [[ -n ${GIT_CONFIG_GLOBAL:-} ]] && protected+=("$GIT_CONFIG_GLOBAL")
  for p in "${protected[@]}"; do
    [[ $path == "$(realpath -m -- "$p" 2>/dev/null)" ]] && deny "$config_msg"
  done
  rdest=$(realpath -m -- "$dest" 2>/dev/null) || rdest=$dest
  [[ $path == "$rdest" || $path == "$rdest"/* ]] && deny "$config_msg"
  exit 0
fi

cmd=$(jq -r '.tool_input.command // .toolCall.args.CommandLine // ""' <<<"$input")
[[ -n $cmd ]] || exit 0

disable() {
  deny "Este comando desligaria os hooks do git que protegem a main ($1). Se for intencional, rode você mesmo no terminal."
}

# Sem os hooks instalados, a main fica sem proteção: bloqueia na dúvida.
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
[[ $cmd == *FABRICA_GITHOOKS_DEST* ]] && disable "variável FABRICA_GITHOOKS_DEST"
exit 0
