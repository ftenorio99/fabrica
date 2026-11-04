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

# Desde a #62 o script espera o log ter uma entrada recente. Uma entrada sem
# usage com o horário de agora deixa os casos acima responderem na hora, e o
# limite curto acelera os casos sem log aproveitável.
call_entry() { # call_entry <horário>: a resposta que chama o script, ainda sem usage
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"msg_call_%s","content":[{"type":"tool_use","name":"Bash","input":{"command":"python3 scripts/stage-usage.py --stage triagem --since x"}}]}}\n' "$1" "$RANDOM"
}
call_entry "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" >> "$project/$sid.jsonl"
export FABRICA_STAGE_USAGE_TIMEOUT=1

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

# --- SPEC-62 ---------------------------------------------------------------
# at <segundos em relação a agora>: horário ISO UTC com milissegundos.
at() { date -u -d "@$(( $(date +%s) + $1 ))" +%Y-%m-%dT%H:%M:%S.000Z; }
at_s() { date -u -d "@$(( $(date +%s) + $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
reply() { # reply <id> <horário> <entrada>
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","usage":{"input_tokens":%s,"output_tokens":0}}}\n' "$2" "$1" "$3"
}
prompt() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"/fabrica:triagem 1"}}\n' "$1"; }
meta() { printf '{"type":"user","isMeta":true,"timestamp":"%s","message":{"role":"user","content":"texto da skill"}}\n' "$1"; }
tool_result() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}\n' "$1"; }
inputs() { sed -E 's/.* entrada=([0-9]+) .*/\1/'; }
start_of() { sed -E 's/.* inicio=([^ ]+) .*/\1/'; }

# CA1: as últimas entradas chegam ao log 2 s depois de o script começar.
s1="33333333-3333-3333-3333-333333333333"
{ prompt "$(at -60)"; reply r1 "$(at -50)" 10; } > "$project/$s1.jsonl"
# A resposta tem o horário de quando foi gerada, mas só chega ao arquivo 2 s depois.
r2_at="$(at -1)"
( sleep 2; { reply r2 "$r2_at" 5; call_entry "$r2_at"; } >> "$project/$s1.jsonl" ) &
out="$(CLAUDE_CODE_SESSION_ID="$s1" FABRICA_STAGE_USAGE_TIMEOUT=10 python3 "$script" --stage triagem --since "$(at_s -55)")"
wait
check CA1 "log gravado com atraso: espera e soma tudo" 15 "$(inputs <<<"$out")"
check CA1 "log gravado com atraso: sem parcial" 0 "$(grep -c 'parcial=sim' <<<"$out")"

# CA2: nenhuma entrada recente até o limite.
s2="44444444-4444-4444-4444-444444444444"
{ prompt "$(at -300)"; reply r1 "$(at -290)" 7; } > "$project/$s2.jsonl"
t0=$(date +%s%N)
out="$(CLAUDE_CODE_SESSION_ID="$s2" FABRICA_STAGE_USAGE_TIMEOUT=1 python3 "$script" --stage spec --since "$(at_s -295)")"; code=$?
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check CA2 "limite estourado: código 0" 0 "$code"
check CA2 "limite estourado: soma o que há" 7 "$(inputs <<<"$out")"
check CA2 "limite estourado: parcial=sim" 1 "$(grep -c 'parcial=sim -->$' <<<"$out")"
check CA2 "limite estourado: termina em até 3 s" 1 "$(( ms <= 3000 ))"

# CA2: uma entrada recente que não é a chamada do script não encerra a espera.
s2b="45454545-4545-4545-4545-454545454545"
{ prompt "$(at -300)"; reply r1 "$(at -290)" 7; printf '{"type":"api-request","timestamp":"%s"}\n' "$(at 0)"; tool_result "$(at 0)"; } > "$project/$s2b.jsonl"
out="$(CLAUDE_CODE_SESSION_ID="$s2b" FABRICA_STAGE_USAGE_TIMEOUT=1 python3 "$script" --stage spec --since "$(at_s -295)")"
check CA2 "entrada recente de outro tipo: continua parcial" 1 "$(grep -c 'parcial=sim -->$' <<<"$out")"
t0=$(date +%s%N)
CLAUDE_CODE_SESSION_ID="$s2b" FABRICA_STAGE_USAGE_TIMEOUT=nan python3 "$script" --stage spec --since "$(at_s -295)" >/dev/null &
pid=$!
( sleep 40; kill "$pid" 2>/dev/null ) & guard=$!
wait "$pid"; kill "$guard" 2>/dev/null
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check CA2 "limite nan: cai nos 30 s e termina" 1 "$(( ms < 35000 ))"

# CA3: sem sessão ou sem arquivo, responde sem esperar.
t0=$(date +%s%N)
env -u CLAUDE_CODE_SESSION_ID FABRICA_STAGE_USAGE_TIMEOUT=30 python3 "$script" --stage spec --since "$since" >/dev/null
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check CA3 "sem sessão: responde em menos de 1 s" 1 "$(( ms < 1000 ))"
t0=$(date +%s%N)
CLAUDE_CODE_SESSION_ID="55555555-0000-0000-0000-000000000000" FABRICA_STAGE_USAGE_TIMEOUT=30 python3 "$script" --stage spec --since "$since" >/dev/null
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
check CA3 "sem arquivo: responde em menos de 1 s" 1 "$(( ms < 1000 ))"

# CA4: a primeira resposta da etapa vem antes do --since e entra na soma.
s4="66666666-6666-6666-6666-666666666666"
p4="$(at -120)"
{ reply antes "$(at -200)" 1000; prompt "$p4"; meta "$(at -115)"; reply primeira "$(at -110)" 20; tool_result "$(at -105)"; reply segunda "$(at -90)" 3; call_entry "$(at 0)"; } > "$project/$s4.jsonl"
out="$(CLAUDE_CODE_SESSION_ID="$s4" python3 "$script" --stage triagem --since "$(at_s -100)")"
check CA4 "a primeira resposta entra na soma" 23 "$(inputs <<<"$out")"
check CA4 "o início é o da mensagem do usuário" "${p4%.000Z}Z" "$(start_of <<<"$out")"

# CA5: o recuo para na chamada anterior do script.
s5="77777777-7777-7777-7777-777777777777"
c5="$(at -200)"
{
  prompt "$(at -300)"
  reply anterior "$(at -290)" 1000
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"chamada","usage":{"input_tokens":500,"output_tokens":0},"content":[{"type":"tool_use","name":"Bash","input":{"command":"python3 scripts/stage-usage.py --stage implementar --since x"}}]}}\n' "$c5"
  tool_result "$(at -199)"
  reply depois "$(at -150)" 30
  reply atual "$(at -90)" 4
  call_entry "$(at 0)"
} > "$project/$s5.jsonl"
out="$(CLAUDE_CODE_SESSION_ID="$s5" python3 "$script" --stage revisar --since "$(at_s -100)")"
check CA5 "a etapa anterior fica de fora" 34 "$(inputs <<<"$out")"
check CA5 "o início é o da chamada anterior" "${c5%.000Z}Z" "$(start_of <<<"$out")"
out="$(CLAUDE_CODE_SESSION_ID="$s5" python3 "$script" --stage revisar --since "$(at_s -100)" --exact)"
check CA5 "--exact: sem recuo" 4 "$(inputs <<<"$out")"

echo
echo "$((total - failures))/$total ok"
(( failures == 0 ))
