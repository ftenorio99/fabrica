#!/usr/bin/env bash
# Testa skills/metricas/costs.py (SPEC-58, CA5) com comentários de exemplo.
# Uso: bash scripts/test-costs.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/../skills/metricas/costs.py"

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

# Issue medida: triagem (10 min) e spec (5 min) na issue, e no PR a resposta
# do implementar encadeado com duas linhas (20 + 15 min). Na issue, o aviso
# do revisar e a lição não precisam de linha. Em páginas, como no --slurp.
cat > "$tmp/issue-ok.json" <<'EOF'
[[
 {"body": "<!-- fabrica:triagem -->\n## Triagem\n\n<!-- fabrica:custo etapa=triagem inicio=2026-11-04T10:00:00Z fim=2026-11-04T10:10:00Z entrada=10 saida=20 cache_escrita=30 cache_leitura=40 -->"},
 {"body": "Resposta do usuário."},
 {"body": "<!-- fabrica:licao gatilho=desvio -->\n**Lição · 2026-11-04**"}
],[
 {"body": "<!-- fabrica:spec -->\n## Spec\n\n<!-- fabrica:custo etapa=spec inicio=2026-11-04T11:00:00Z fim=2026-11-04T11:05:00Z entrada=1 saida=2 cache_escrita=3 cache_leitura=4 -->"},
 {"body": "<!-- fabrica:revisar -->\nPR aberto e pronto para revisão: #9."}
]]
EOF
cat > "$tmp/pr-ok.json" <<'EOF'
[
 {"body": "<!-- fabrica:revisar -->\n**Pedidos lidos até:** 2026-11-04T12:20:00Z\n\nPronto.\n\n<!-- fabrica:custo etapa=implementar inicio=2026-11-04T12:00:00Z fim=2026-11-04T12:20:00Z entrada=100 saida=200 cache_escrita=300 cache_leitura=400 -->\n<!-- fabrica:custo etapa=revisar inicio=2026-11-04T12:20:00Z fim=2026-11-04T12:35:00Z entrada=1000 saida=2000 cache_escrita=3000 cache_leitura=4000 -->"}
]
EOF
out="$(python3 "$script" "$tmp/issue-ok.json" "$tmp/pr-ok.json")"
check CA5 "issue medida: tokens e trabalho somados" \
  '{"medida": true, "tokens": 11110, "trabalho_min": 50}' "$out"

# Issue antiga: comentários sem linha de custo.
cat > "$tmp/issue-old.json" <<'EOF'
[{"body": "<!-- fabrica:triagem -->\n## Triagem"}, {"body": "<!-- fabrica:spec -->\n## Spec"}]
EOF
out="$(python3 "$script" "$tmp/issue-old.json" -)"
check CA5 "issue sem linhas: não medida" '{"medida": false, "tokens": null, "trabalho_min": null}' "$out"

# Uma linha nao-medido derruba a medição da issue.
cat > "$tmp/issue-partial.json" <<'EOF'
[
 {"body": "<!-- fabrica:triagem -->\n<!-- fabrica:custo etapa=triagem inicio=2026-11-04T10:00:00Z fim=2026-11-04T10:10:00Z tokens=nao-medido -->"},
 {"body": "<!-- fabrica:spec -->\n<!-- fabrica:custo etapa=spec inicio=2026-11-04T11:00:00Z fim=2026-11-04T11:05:00Z entrada=1 saida=2 cache_escrita=3 cache_leitura=4 -->"}
]
EOF
out="$(python3 "$script" "$tmp/issue-partial.json" "$tmp/pr-ok.json")"
check CA5 "linha nao-medido: não medida" '{"medida": false, "tokens": null, "trabalho_min": null}' "$out"

# Uma resposta do revisar no PR sem linha também derruba.
cat > "$tmp/pr-missing.json" <<'EOF'
[{"body": "<!-- fabrica:revisar -->\n**Pedidos lidos até:** 2026-11-04T12:20:00Z"}]
EOF
out="$(python3 "$script" "$tmp/issue-ok.json" "$tmp/pr-missing.json")"
check CA5 "revisar no PR sem linha: não medida" '{"medida": false, "tokens": null, "trabalho_min": null}' "$out"

# SPEC-62: uma linha parcial=sim também derruba a medição.
cat > "$tmp/issue-parcial.json" <<'EOF'
[
 {"body": "<!-- fabrica:triagem -->\n<!-- fabrica:custo etapa=triagem inicio=2026-11-04T10:00:00Z fim=2026-11-04T10:10:00Z entrada=10 saida=20 cache_escrita=30 cache_leitura=40 parcial=sim -->"},
 {"body": "<!-- fabrica:spec -->\n<!-- fabrica:custo etapa=spec inicio=2026-11-04T11:00:00Z fim=2026-11-04T11:05:00Z entrada=1 saida=2 cache_escrita=3 cache_leitura=4 -->"}
]
EOF
out="$(python3 "$script" "$tmp/issue-parcial.json" "$tmp/pr-ok.json")"
check CA6 "linha parcial=sim: não medida" '{"medida": false, "tokens": null, "trabalho_min": null}' "$out"

echo
echo "$((total - failures))/$total ok"
(( failures == 0 ))
