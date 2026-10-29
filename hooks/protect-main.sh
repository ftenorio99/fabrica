#!/usr/bin/env bash
# PreToolUse (Bash): impede o Claude de desligar os hooks do git da fábrica.
# Quem recusa commit e push na main/master são os hooks globais do git
# (githooks/, instalados por scripts/setup-githooks.sh). Este hook só faz
# checagens de texto sobre o comando inteiro, sem separar aspas, contra o
# que desligaria esses hooks. Falsos positivos raros são aceitos (ex.: um
# corpo de PR que cita --no-verify); basta reescrever o texto.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
[[ -n $cmd ]] || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
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
# Sem HOME ou XDG_CONFIG_HOME, o git não acha o core.hooksPath global.
unset_re='(^|[^[:alnum:]_.-])unset([[:blank:]]+[^;&|[:space:]]+)*[[:blank:]]+["'"'"']?(HOME|XDG_CONFIG_HOME)([^[:alnum:]_]|$)'
[[ $flat =~ $unset_re ]] && disable "unset do ${BASH_REMATCH[3]}"
# env com opções que limpam ou tiram variáveis: -i, -, -u e -S (opções
# dentro de uma string), combinadas (-iu) ou abreviadas (--u, --ignore-e).
# Palavras sem = entre o env e a opção contam como argumentos (-C dir).
env_re='(^|[^[:alnum:]_.-])env([[:blank:]]+[^=;&|[:space:]]+)*[[:blank:]]+(-|--ignore-e[^;&|[:space:]]*|--u[^;&|[:space:]]*|--sp[^;&|[:space:]]*|-[[:alnum:]]*[iuS][^;&|[:space:]]*)([[:blank:]]|$)'
[[ $flat =~ $env_re ]] && disable "env sem o ambiente"
# Subcomandos remove-section/rename-section e as opções antigas, inclusive
# abreviadas (--rem, --ren).
[[ $cmd =~ (remove|rename)-section ]] && disable "remove ou renomeia seção da configuração do git"
grep -Eq 'config[^;&|]*[[:blank:]]--re[mn]' <<<"$flat" && disable "remove ou renomeia seção da configuração do git"
[[ ${cmd,,} == *hookspath* ]] && disable "core.hooksPath"
[[ $cmd == *GIT_CONFIG* ]] && disable "variável GIT_CONFIG*"
[[ $cmd =~ (^|[^[:alnum:]_])(HOME|XDG_CONFIG_HOME)= ]] && disable "troca do ${BASH_REMATCH[2]}"
[[ $cmd == *fabrica/githooks* ]] && disable "mexe na pasta dos hooks"
exit 0
