#!/usr/bin/env bash
# Testa o hook SessionStart (hooks/session-start.sh) nos dois contratos, com um
# HOME temporário e sem rede: com e sem os hooks do git da fábrica instalados.
# Também roda o segundo comando do SessionStart, de hooks/hooks.json.
# Uso: scripts/test-session-start.sh [caminho do hook SessionStart]
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(realpath "$script_dir/..")"
hook="$(realpath "${1:-$plugin_root/hooks/session-start.sh}")"
[[ -f "$hook" ]] || { echo "test-session-start: hook não encontrado em $hook" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Isola a configuração global do git no HOME de teste.
unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 CLAUDE_PLUGIN_ROOT="$plugin_root"
mkdir -p "$HOME"

msg='Os hooks do git da fábrica não estão instalados nesta máquina. Rode /fabrica:setup.'
claude_in='{"session_id":"abc","hook_event_name":"SessionStart","source":"startup","cwd":"/tmp"}'
agy_in='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","modelName":"m"}'

failures=0 total=0

# result <ok: 0|1> <CA> <descrição>
result() {
  total=$((total + 1))
  if (( $1 == 0 )); then
    printf 'ok      %-4s %s\n' "$2" "$3"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n' "$2" "$3"
  fi
}

run() { printf '%s' "$1" | bash "$hook" 2>"$tmp/stderr"; }

# Segundo comando do SessionStart, como está em hooks/hooks.json.
statusline_cmd=$(jq -r '.hooks.SessionStart[0].hooks[1].command' "$plugin_root/hooks/hooks.json")
statusline() { printf '%s' "$1" | bash -c "$statusline_cmd" 2>"$tmp/stderr"; }

# Hooks do git ausentes
out=$(run "$claude_in")
[[ $out == "$msg" && ! -s $tmp/stderr ]]
result $? CA1 "ausente, Claude Code: texto puro idêntico ao de antes"

out=$(run "$agy_in")
jq -e --arg m "$msg" '.injectSteps | length == 1 and .[0].systemMessage.systemMessage == $m' <<<"$out" >/dev/null
result $? CA2 "ausente, Antigravity: JSON injectSteps com o texto do aviso"

out=$(run "")
[[ $out == "$msg" ]]
result $? CA1 "ausente, sem entrada: texto puro (padrão do Claude Code)"

# Hooks do git da fábrica instalados
bash "$plugin_root/scripts/setup-githooks.sh" >/dev/null
[[ $(bash "$plugin_root/scripts/setup-githooks.sh" --check) == ok ]]
result $? CA3 "instalação de teste ficou ok"

out=$(run "$claude_in")
[[ -z $out ]]
result $? CA3 "instalado, Claude Code: sem saída"

out=$(run "$agy_in")
[[ -z $out ]]
result $? CA3 "instalado, Antigravity: sem saída"

# Segundo comando
for contract in claude agy; do
  input=$claude_in; [[ $contract == agy ]] && input=$agy_in
  out=$(statusline "$input"); rc=$?
  [[ $rc -eq 0 && -z $out && ! -s $tmp/stderr ]]
  result $? CA5 "statusline --check, $contract: sem saída e sem erro"
done

# CA11 (SPEC-246): cada saída do --check, com um setup-githooks.sh falso.
fake_root="$tmp/fake-root"
mkdir -p "$fake_root/scripts"
cat >"$fake_root/scripts/setup-githooks.sh" <<'EOF'
printf '%s\n' "$FAKE_LINE"
exit "$FAKE_RC"
EOF
# check <silencioso|mensagem> <código de saída> <linha> [trecho esperado]
check() {
  local kind=$1 rc=$2 line=$3 want=${4-} c a ok=0
  c=$(printf '%s' "$claude_in" | FAKE_LINE=$line FAKE_RC=$rc CLAUDE_PLUGIN_ROOT=$fake_root bash "$hook" 2>/dev/null)
  a=$(printf '%s' "$agy_in" | FAKE_LINE=$line FAKE_RC=$rc CLAUDE_PLUGIN_ROOT=$fake_root bash "$hook" 2>/dev/null)
  if [[ $kind == silencioso ]]; then
    [[ -z $c && -z $a ]] || ok=1
  else
    [[ -n $c && $c != *$'\n'* && $c == *"$want"* ]] || ok=1
    jq -e --arg m "$c" '.injectSteps | length == 1 and .[0].systemMessage.systemMessage == $m' <<<"$a" >/dev/null || ok=1
  fi
  result $ok CA11 "'$line' (saída $rc): $kind${want:+, com \"$want\"}"
}
check silencioso 0 ok
check silencioso 0 'atualizado 1.2.3'
check silencioso 0 'mais-novo 1.2.3'
check silencioso 0 'ocupado integra'
check mensagem 0 'reparado 1.2.3' 'recuperados na versão 1.2.3'
check mensagem 0 'mais-novo 1.2.3 incerta' 'Não houve downgrade'
check mensagem 0 'ocupado incerta' 'recuperação manual da trava'
check mensagem 0 'divergente 1.2.3' 'conteúdo diferente'
check mensagem 0 'divergente 1.2.3 incerta' 'integridade deles não está comprovada'
check mensagem 0 ausente "$msg"
for code in origem-invalida destino-invalido preparacao publicacao interrompida rollback-interrompido danificada versao-desconhecida trava; do
  check mensagem 1 "falha $code" "falhou ($code)"
done
check mensagem 3 ok 'não respondeu como esperado'
check mensagem 0 'falha danificada' 'não respondeu como esperado'
check mensagem 1 'falha inventada' 'não respondeu como esperado'
check mensagem 0 'atualizado 01.2.3' 'não respondeu como esperado'
check mensagem 0 'qualquer coisa' 'não respondeu como esperado'
out=$(printf '%s' "$claude_in" | FAKE_LINE='divergente 1.2.3 $(touch x)' FAKE_RC=0 CLAUDE_PLUGIN_ROOT=$fake_root bash "$hook" 2>/dev/null)
[[ $out != *touch* ]]
result $? CA11 "linha não reconhecida não é repetida na mensagem"

echo
if (( failures )); then
  echo "$failures de $total casos falharam."
  exit 1
fi
echo "Todos os $total casos passaram."
