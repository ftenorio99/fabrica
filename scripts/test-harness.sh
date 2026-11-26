#!/usr/bin/env bash
# Testa a detecção de harness e a guarda do stage-model.sh (SPEC-200, CA1 a
# CA4 e CA8). Uso: bash scripts/test-harness.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness="$script_dir/harness.sh"
stage="$script_dir/stage-model.sh"
server="$script_dir/../opencode/server.ts"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0 total=0

# check <CA> <descrição> <esperado> <obtido>
check() {
  total=$((total + 1))
  if [[ "$4" == "$3" ]]; then
    printf 'ok      %-4s %s\n' "$1" "$2"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3" "$4"
  fi
}

# run_detect [VAR=valor...]: roda detect com as variáveis de sessão limpas e
# deixa stdout/stderr em $tmp/out e $tmp/err.
run_detect() {
  env -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID \
    -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID "$@" \
    bash "$harness" detect >"$tmp/out" 2>"$tmp/err"
}
detect_out() { run_detect "$@" || true; cat "$tmp/out"; }
detect_rc() { run_detect "$@"; local rc=$?; echo "$rc"; }

# CA1: precedência e saídas.
check CA1 "sem sinal cai no binário" "binario" "$(detect_out)"
check CA1 "CLAUDECODE sozinho é Claude Code" "claude-code" "$(detect_out CLAUDECODE=1)"
check CA1 "CLAUDECODE vence FABRICA_HARNESS e OPENCODE_SESSION_ID" "claude-code" \
  "$(detect_out CLAUDECODE=1 FABRICA_HARNESS=opencode OPENCODE_SESSION_ID=ses_123)"
check CA1 "FABRICA_HARNESS=opencode" "opencode" "$(detect_out FABRICA_HARNESS=opencode)"
check CA1 "FABRICA_HARNESS=antigravity" "antigravity" "$(detect_out FABRICA_HARNESS=antigravity)"
check CA1 "FABRICA_HARNESS=claude-code" "claude-code" "$(detect_out FABRICA_HARNESS=claude-code)"
check CA1 "FABRICA_HARNESS vence OPENCODE_SESSION_ID" "claude-code" \
  "$(detect_out FABRICA_HARNESS=claude-code OPENCODE_SESSION_ID=ses_123)"
check CA1 "OPENCODE_SESSION_ID é a reserva" "opencode" "$(detect_out OPENCODE_SESSION_ID=ses_123)"
check CA1 "ANTIGRAVITY_AGENT detecta antigravity" "antigravity" "$(detect_out ANTIGRAVITY_AGENT=1)"
check CA1 "ANTIGRAVITY_CONVERSATION_ID detecta antigravity" "antigravity" "$(detect_out ANTIGRAVITY_CONVERSATION_ID=conv_123)"
check CA1 "CLAUDECODE vence ANTIGRAVITY_*" "claude-code" \
  "$(detect_out CLAUDECODE=1 ANTIGRAVITY_AGENT=1 ANTIGRAVITY_CONVERSATION_ID=conv_123)"
check CA1 "FABRICA_HARNESS vence ANTIGRAVITY_AGENT" "claude-code" \
  "$(detect_out FABRICA_HARNESS=claude-code ANTIGRAVITY_AGENT=1)"

# CA2: vazias e valor inválido.
check CA2 "variáveis vazias contam como ausentes" "binario" \
  "$(detect_out CLAUDECODE= FABRICA_HARNESS= OPENCODE_SESSION_ID= ANTIGRAVITY_AGENT= ANTIGRAVITY_CONVERSATION_ID=)"
check CA2 "FABRICA_HARNESS inválida sai com 2" "2" "$(detect_rc FABRICA_HARNESS=OPenCode)"
check CA2 "FABRICA_HARNESS inválida não imprime harness" "" "$(detect_out FABRICA_HARNESS=OPenCode)"
check CA2 "o erro lista os valores aceitos" "sim" \
  "$(grep -q 'opencode, antigravity ou claude-code' "$tmp/err" && echo sim || echo não)"

# O claude falso registra a chamada e devolve um JSON mínimo.
fake="$tmp/claude"
calls="$tmp/claude.calls"
cat >"$fake" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$calls"
echo '{"is_error":false,"result":"ok"}'
EOF
chmod +x "$fake"

# run_stage [VAR=valor...]: roda o stage-model.sh como o runner, sem os sinais
# de sessão, e deixa a saída e o erro em $tmp/out e $tmp/err.
run_stage() {
  rm -f "$calls"
  env -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID \
    -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID "$@" \
    FABRICA_CLAUDE_BIN="$fake" bash "$stage" run triagem 12 >"$tmp/out" 2>"$tmp/err"
}
called() { [[ -f "$calls" ]] && echo sim || echo não; }

run_stage FABRICA_HARNESS=opencode
check CA3 "opencode: sai com 3" "3" "$?"
check CA3 "opencode: não chama o claude" "não" "$(called)"

run_stage FABRICA_HARNESS=antigravity
check CA3 "antigravity: sai com 3" "3" "$?"
check CA3 "antigravity: não chama o claude" "não" "$(called)"

run_stage OPENCODE_SESSION_ID=ses_123
check CA3 "OPENCODE_SESSION_ID: sai com 3" "3" "$?"
check CA3 "OPENCODE_SESSION_ID: não chama o claude" "não" "$(called)"

run_stage ANTIGRAVITY_AGENT=1
check CA3 "ANTIGRAVITY_AGENT: sai com 3" "3" "$?"
check CA3 "ANTIGRAVITY_AGENT: não chama o claude" "não" "$(called)"

run_stage CLAUDECODE=1 ANTIGRAVITY_AGENT=1
check CA3 "CLAUDECODE vence ANTIGRAVITY_AGENT e roda o Claude Code" "0 sim" "$? $(called)"

run_stage CLAUDECODE=1 FABRICA_HARNESS=opencode OPENCODE_SESSION_ID=ses_123
check CA3 "CLAUDECODE vence e roda o Claude Code" "0 sim" "$? $(called)"

run_stage
check CA3 "sem sinal mantém o caminho do binário" "0 sim" "$? $(called)"

run_stage FABRICA_HARNESS=OPenCode
check CA3 "FABRICA_HARNESS inválida sai com 1" "1" "$?"
check CA3 "FABRICA_HARNESS inválida não chama o claude" "não" "$(called)"

# CA4: o adaptador registra o hook e preserva o valor já definido.
check CA4 "server.ts registra shell.create.before" "sim" \
  "$(grep -q 'ctx.shell.hook("create.before"' "$server" && echo sim || echo não)"
check CA4 "server.ts define FABRICA_HARNESS=opencode" "sim" \
  "$(grep -q 'event.env.FABRICA_HARNESS = "opencode"' "$server" && echo sim || echo não)"
check CA4 "server.ts só define quando a variável está vazia" "sim" \
  "$(grep -q 'if (event?.env && !event.env.FABRICA_HARNESS)' "$server" && echo sim || echo não)"
check CA4 "erro do hook de harness é logado" "sim" \
  "$(grep -q 'hook shell.create.before não registrado' "$server" && echo sim || echo não)"

# CA8: a suíte do stage-model continua passando, inclusive chamada de dentro do
# OpenCode, porque as chamadas que simulam o runner limpam os sinais de sessão.
if bash "$script_dir/test-stage-model.sh" >"$tmp/stage-model.out" 2>&1; then
  stage_model="ok"
else
  stage_model="falhou"
  tail -n 10 "$tmp/stage-model.out" >&2
fi
check CA8 "test-stage-model.sh passa com os sinais de sessão limpos" "ok" "$stage_model"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
