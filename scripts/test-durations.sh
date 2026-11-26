#!/usr/bin/env bash
# Testa skills/metricas/durations.py (SPEC-75, CA1 a CA4) com timelines de exemplo.
# Uso: bash scripts/test-durations.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/../skills/metricas/durations.py"

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

# CA1: sem agente, fechada às 11:00, reaberta às 13:00 e fechada às 14:00.
cat > "$tmp/reaberta.json" <<'EOF'
[
 {"event": "closed", "created_at": "2026-11-04T11:00:00Z"},
 {"event": "reopened", "created_at": "2026-11-04T13:00:00Z"},
 {"event": "closed", "created_at": "2026-11-04T14:00:00Z"}
]
EOF
out="$(python3 "$script" 2026-11-04T10:00:00Z 2026-11-04T14:00:00Z "$tmp/reaberta.json")"
check CA1 "issue reaberta: desconta as 2 h fechada" \
  '{"abertura_ao_merge": 120, "antes_do_fluxo": null, "esperando_voce": null, "com_o_agente": null, "escalonamentos": 0, "reaberta": true}' "$out"

# CA1: o mesmo closed_at final sem o reopened dá o número de hoje.
cat > "$tmp/sem-reopened.json" <<'EOF'
[
 {"event": "closed", "created_at": "2026-11-04T11:00:00Z"},
 {"event": "closed", "created_at": "2026-11-04T14:00:00Z"}
]
EOF
out="$(python3 "$script" 2026-11-04T10:00:00Z 2026-11-04T14:00:00Z "$tmp/sem-reopened.json")"
check CA1 "sem reopened: nada a descontar" \
  '{"abertura_ao_merge": 240, "antes_do_fluxo": null, "esperando_voce": null, "com_o_agente": null, "escalonamentos": 0, "reaberta": false}' "$out"

# SPEC-231, CA1: reaberta depois do closed_at final não marca reaberta=true.
cat > "$tmp/reaberta-tardia.json" <<'EOF'
[
 {"event": "closed", "created_at": "2026-11-04T14:00:00Z"},
 {"event": "reopened", "created_at": "2026-11-04T15:00:00Z"}
]
EOF
out="$(python3 "$script" 2026-11-04T10:00:00Z 2026-11-04T14:00:00Z "$tmp/reaberta-tardia.json")"
check CA1 "reaberta depois do closed_at final: reaberta=false" \
  '{"abertura_ao_merge": 240, "antes_do_fluxo": null, "esperando_voce": null, "com_o_agente": null, "escalonamentos": 0, "reaberta": false}' "$out"

# CA2: precisa-info aplicada antes do primeiro fechamento e retirada depois
# da reabertura. Criada 09:00, agente 09:30, precisa-info 10:30, fechada
# 11:00, reaberta 13:00, precisa-info sai 13:30, fechada 15:00.
cat > "$tmp/reaberta-agente.json" <<'EOF'
[[
 {"event": "labeled", "created_at": "2026-11-04T09:30:00Z", "label": {"name": "agente"}},
 {"event": "labeled", "created_at": "2026-11-04T10:30:00Z", "label": {"name": "precisa-info"}},
 {"event": "closed", "created_at": "2026-11-04T11:00:00Z"}
],[
 {"event": "reopened", "created_at": "2026-11-04T13:00:00Z"},
 {"event": "unlabeled", "created_at": "2026-11-04T13:30:00Z", "label": {"name": "precisa-info"}},
 {"event": "closed", "created_at": "2026-11-04T15:00:00Z"}
]]
EOF
out="$(python3 "$script" 2026-11-04T09:00:00Z 2026-11-04T15:00:00Z "$tmp/reaberta-agente.json")"
check CA2 "reaberta com agente: o intervalo fechado sai de todos os tempos" \
  '{"abertura_ao_merge": 240, "antes_do_fluxo": 30, "esperando_voce": 60, "com_o_agente": 150, "escalonamentos": 0, "reaberta": true}' "$out"
soma="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(abs(d["antes_do_fluxo"]+d["esperando_voce"]+d["com_o_agente"]-d["abertura_ao_merge"]) <= 1)' "$out")"
check CA2 "as partes somam a abertura ao merge" "True" "$soma"

# CA3: um escalonado antes do fechamento conta, um depois não.
cat > "$tmp/escalonado-tardio.json" <<'EOF'
[
 {"event": "labeled", "created_at": "2026-11-04T09:00:00Z", "label": {"name": "agente"}},
 {"event": "labeled", "created_at": "2026-11-04T10:00:00Z", "label": {"name": "escalonado"}},
 {"event": "unlabeled", "created_at": "2026-11-04T11:00:00Z", "label": {"name": "escalonado"}},
 {"event": "closed", "created_at": "2026-11-04T12:00:00Z"},
 {"event": "labeled", "created_at": "2026-11-04T12:30:00Z", "label": {"name": "escalonado"}}
]
EOF
out="$(python3 "$script" 2026-11-04T08:00:00Z 2026-11-04T12:00:00Z "$tmp/escalonado-tardio.json")"
check CA3 "escalonamento depois do closed_at não conta" \
  '{"abertura_ao_merge": 240, "antes_do_fluxo": 60, "esperando_voce": 60, "com_o_agente": 120, "escalonamentos": 1, "reaberta": false}' "$out"

# SPEC-95, CA9: acao-externa conta como espera do usuário. Criada 08:00,
# agente 09:00, acao-externa 10:00 a 11:30, fechada 12:00.
cat > "$tmp/acao-externa.json" <<'EOF'
[
 {"event": "labeled", "created_at": "2026-11-04T09:00:00Z", "label": {"name": "agente"}},
 {"event": "labeled", "created_at": "2026-11-04T10:00:00Z", "label": {"name": "acao-externa"}},
 {"event": "unlabeled", "created_at": "2026-11-04T11:30:00Z", "label": {"name": "acao-externa"}},
 {"event": "closed", "created_at": "2026-11-04T12:00:00Z"}
]
EOF
out="$(python3 "$script" 2026-11-04T08:00:00Z 2026-11-04T12:00:00Z "$tmp/acao-externa.json")"
check CA9 "acao-externa conta em esperando_voce" \
  '{"abertura_ao_merge": 240, "antes_do_fluxo": 60, "esperando_voce": 90, "com_o_agente": 90, "escalonamentos": 0, "reaberta": false}' "$out"

# CA4: timelines sem reabertura nem escalonamento tardio. Os esperados são
# a saída do durations.py da main antes da SPEC-75.
cat > "$tmp/sem-agente.json" <<'EOF'
[{"event": "labeled", "created_at": "2026-11-04T10:00:00Z", "label": {"name": "bug"}}]
EOF
out="$(python3 "$script" 2026-11-04T08:00:00Z 2026-11-04T10:30:00Z "$tmp/sem-agente.json")"
check CA4 "sem agente: igual à main" \
  '{"abertura_ao_merge": 150, "antes_do_fluxo": null, "esperando_voce": null, "com_o_agente": null, "escalonamentos": 0, "reaberta": false}' "$out"

cat > "$tmp/fluxo-completo.json" <<'EOF'
[[
 {"event": "labeled", "created_at": "2026-11-04T08:10:00Z", "label": {"name": "agente"}},
 {"event": "commented", "created_at": "2026-11-04T08:20:00Z"},
 {"event": "labeled", "created_at": "2026-11-04T08:30:00Z", "label": {"name": "spec-pronta"}},
 {"event": "labeled", "created_at": "2026-11-04T09:10:00Z", "label": {"name": "spec-aprovada"}}
],[
 {"event": "labeled", "created_at": "2026-11-04T09:40:00Z", "label": {"name": "pronto-revisao"}},
 {"event": "labeled", "created_at": "2026-11-04T09:50:00Z", "label": {"name": "escalonado"}},
 {"event": "unlabeled", "created_at": "2026-11-04T10:05:00Z", "label": {"name": "escalonado"}},
 {"event": "closed", "created_at": "2026-11-04T10:30:00Z"}
]]
EOF
out="$(python3 "$script" 2026-11-04T08:00:00Z 2026-11-04T10:30:00Z "$tmp/fluxo-completo.json")"
check CA4 "fluxo completo em páginas: igual à main" \
  '{"abertura_ao_merge": 150, "antes_do_fluxo": 10, "esperando_voce": 90, "com_o_agente": 50, "escalonamentos": 1, "reaberta": false}' "$out"

cat > "$tmp/spec-pronta.json" <<'EOF'
[
 {"event": "labeled", "created_at": "2026-11-04T08:10:00Z", "label": {"name": "agente"}},
 {"event": "labeled", "created_at": "2026-11-04T08:30:00Z", "label": {"name": "spec-pronta"}}
]
EOF
out="$(python3 "$script" 2026-11-04T08:00:00Z 2026-11-04T10:30:00Z "$tmp/spec-pronta.json")"
check CA4 "spec-pronta sem spec-aprovada: igual à main" \
  '{"abertura_ao_merge": 150, "antes_do_fluxo": 10, "esperando_voce": 120, "com_o_agente": 20, "escalonamentos": 0, "reaberta": false}' "$out"

echo
echo "$((total - failures))/$total ok"
(( failures == 0 ))
