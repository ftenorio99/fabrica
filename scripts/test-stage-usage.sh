#!/usr/bin/env bash
# Testa scripts/stage-usage.py (SPEC-58, CA1 e CA2) com um HOME temporário e
# logs de sessão de exemplo, sem tocar nos logs reais do Claude Code.
# Uso: bash scripts/test-stage-usage.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/stage-usage.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
sid="11111111-2222-3333-4444-555555555555"
project="$HOME/.claude/projects/-tmp-projeto"
mkdir -p "$project/$sid/subagents"

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

# Só os contadores da linha de custo, sem início e fim, que mudam a cada execução.
counters() { sed -E 's/.* fim=[^ ]+ (.*) -->$/\1/'; }

# Sessão principal: a resposta msg_a repetida em 3 linhas, a msg_b, uma
# resposta antes do intervalo, uma linha sem usage e uma linha inválida.
cat > "$project/$sid.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-11-04T09:00:00.000Z","message":{"id":"msg_old","usage":{"input_tokens":1000,"output_tokens":1000,"cache_creation_input_tokens":1000,"cache_read_input_tokens":1000}}}
{"type":"user","timestamp":"2026-11-04T10:00:01.000Z","message":{"role":"user","content":"oi"}}
{"type":"assistant","timestamp":"2026-11-04T10:00:02.000Z","message":{"id":"msg_a","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
{"type":"assistant","timestamp":"2026-11-04T10:00:02.100Z","message":{"id":"msg_a","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
{"type":"assistant","timestamp":"2026-11-04T10:00:02.200Z","message":{"id":"msg_a","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
isto não é json
{"type":"assistant","timestamp":"2026-11-04T10:05:00.000Z","message":{"id":"msg_b","usage":{"input_tokens":1,"output_tokens":2}}}
EOF

# Subagente com 2 respostas no intervalo.
cat > "$project/$sid/subagents/agent-x.jsonl" <<'EOF'
{"type":"assistant","isSidechain":true,"timestamp":"2026-11-04T10:01:00.000Z","message":{"id":"msg_s1","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":300,"cache_read_input_tokens":400}}}
{"type":"assistant","isSidechain":true,"timestamp":"2026-11-04T10:02:00.000Z","message":{"id":"msg_s2","usage":{"input_tokens":1000,"output_tokens":2000,"cache_creation_input_tokens":3000,"cache_read_input_tokens":4000}}}
EOF

since="2026-11-04T10:00:00Z"

# CA1: soma deduplicada, com subagente, sem a resposta fora do intervalo.
out="$(CLAUDE_CODE_SESSION_ID="$sid" python3 "$script" --stage triagem --since "$since")"; code=$?
check CA1 "código de saída 0" 0 "$code"
check CA1 "formato da linha de custo" 1 \
  "$(grep -cE '^<!-- fabrica:custo etapa=triagem inicio=2026-11-04T10:00:00Z fim=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z entrada=[0-9]+ saida=[0-9]+ cache_escrita=[0-9]+ cache_leitura=[0-9]+ -->$' <<<"$out")"
check CA1 "cada message.id conta uma vez, subagente incluído, msg_old excluída" \
  "entrada=1111 saida=2222 cache_escrita=3330 cache_leitura=4440" "$(counters <<<"$out")"

# CA2: sem variável de sessão.
out="$(env -u CLAUDE_CODE_SESSION_ID python3 "$script" --stage spec --since "$since")"; code=$?
check CA2 "sem CLAUDE_CODE_SESSION_ID: código 0" 0 "$code"
check CA2 "sem CLAUDE_CODE_SESSION_ID: nao-medido" "tokens=nao-medido" "$(counters <<<"$out")"

# CA2: arquivo da sessão ausente.
out="$(CLAUDE_CODE_SESSION_ID="99999999-0000-0000-0000-000000000000" python3 "$script" --stage revisar --since "$since")"; code=$?
check CA2 "sessão sem arquivo: código 0" 0 "$code"
check CA2 "sessão sem arquivo: nao-medido" "tokens=nao-medido" "$(counters <<<"$out")"

# CA2: nenhuma resposta no intervalo.
out="$(CLAUDE_CODE_SESSION_ID="$sid" python3 "$script" --stage implementar --since "2030-01-01T00:00:00Z")"; code=$?
check CA2 "intervalo vazio: código 0" 0 "$code"
check CA2 "intervalo vazio: nao-medido" "tokens=nao-medido" "$(counters <<<"$out")"

# CA2: só linhas inválidas.
bad="22222222-2222-2222-2222-222222222222"
printf 'lixo\n{"timestamp":"não é data","message":{"usage":{}}}\n' > "$project/$bad.jsonl"
out="$(CLAUDE_CODE_SESSION_ID="$bad" python3 "$script" --stage triagem --since "$since")"; code=$?
check CA2 "log só com linhas inválidas: código 0" 0 "$code"
check CA2 "log só com linhas inválidas: nao-medido" "tokens=nao-medido" "$(counters <<<"$out")"

echo
echo "$((total - failures))/$total ok"
(( failures == 0 ))
