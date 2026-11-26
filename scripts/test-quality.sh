#!/usr/bin/env bash
# Testa skills/metricas/quality.py (SPEC-231, CA2 a CA4) com fixtures JSON.
# Uso: bash scripts/test-quality.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/../skills/metricas/quality.py"

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

# CA2: PRs revertidos pelo título e pelo corpo, além de PR comum.
cat > "$tmp/prs-revert.json" <<'EOF'
[
 {"number": 10, "title": "Revert \"feat: algo\"", "body": ""},
 {"number": 11, "title": "revert: desfaz ajuste", "body": null},
 {"number": 12, "title": "fix: corrige", "body": "Reverts owner/repo#9"},
 {"number": 13, "title": "chore: rollback", "body": "This reverts commit abc1234."},
 {"number": 14, "title": "feat: nova funcionalidade", "body": "Sem reversão aqui."}
]
EOF
cat > "$tmp/vazio.json" <<'EOF'
[]
EOF
out="$(python3 "$script" "$tmp/prs-revert.json" "$tmp/vazio.json")"
check CA2 "conta PRs revertidos por título e corpo" \
  '{"revertidos": 4, "bugs_pos_merge": 0}' "$out"

# CA2: quando nenhum PR casa, devolve 0.
cat > "$tmp/prs-comuns.json" <<'EOF'
[
 {"number": 20, "title": "feat: adiciona métrica", "body": "Não é revert."}
]
EOF
out="$(python3 "$script" "$tmp/prs-comuns.json" "$tmp/vazio.json")"
check CA2 "nenhum PR revertido devolve 0" \
  '{"revertidos": 0, "bugs_pos_merge": 0}' "$out"

# CA3: issues bug citando PR entregue por #nº ou /pull/nº no título ou corpo.
cat > "$tmp/bugs-citacoes.json" <<'EOF'
[
 {"number": 101, "title": "bug: erro após #50", "body": ""},
 {"number": 102, "title": "bug: regressão", "body": "Causado por https://github.com/owner/repo/pull/51."},
 {"number": 103, "title": "bug: outro", "body": "Relacionado ao PR #52."}
]
EOF
out="$(python3 "$script" "$tmp/vazio.json" "$tmp/bugs-citacoes.json" --prs-entregues 50 51 52)"
check CA3 "conta bugs citando PR entregue via #nº ou /pull/nº" \
  '{"revertidos": 0, "bugs_pos_merge": 3}' "$out"

# CA4: citação duplicada na mesma issue ou dois PRs entregues na mesma issue contam 1.
cat > "$tmp/bugs-duplicados.json" <<'EOF'
[
 {"number": 201, "title": "bug: falha no #50", "body": "Repete #50 e também https://github.com/owner/repo/pull/50."},
 {"number": 202, "title": "bug: conflito entre #50 e #51", "body": "Ambos quebraram."}
]
EOF
out="$(python3 "$script" "$tmp/vazio.json" "$tmp/bugs-duplicados.json" --prs-entregues 50 51)"
check CA4 "múltiplas citações na mesma issue contam apenas 1" \
  '{"revertidos": 0, "bugs_pos_merge": 2}' "$out"

# CA4: PR fora de --prs-entregues, número sem # nem /pull/, ou issue #500 não casam com 50.
cat > "$tmp/bugs-nao-contam.json" <<'EOF'
[
 {"number": 301, "title": "bug: PR fora da lista #99", "body": "https://github.com/owner/repo/pull/99"},
 {"number": 302, "title": "bug: erro 50 sem prefixo", "body": "Código 50 e path a/50"},
 {"number": 303, "title": "bug: prefixo diferente #500", "body": "https://github.com/owner/repo/pull/500"}
]
EOF
out="$(python3 "$script" "$tmp/vazio.json" "$tmp/bugs-nao-contam.json" --prs-entregues 50)"
check CA4 "PR fora da lista ou sem # /pull/ não conta" \
  '{"revertidos": 0, "bugs_pos_merge": 0}' "$out"

# CA4: entradas vazias devolvem 0 (nunca null) e aceita entrada paginada.
out="$(python3 "$script" "$tmp/vazio.json" "$tmp/vazio.json")"
check CA4 "entradas vazias devolvem 0" \
  '{"revertidos": 0, "bugs_pos_merge": 0}' "$out"

cat > "$tmp/prs-paginado.json" <<'EOF'
[[{"number": 30, "title": "Revert: algo", "body": ""}], []]
EOF
cat > "$tmp/bugs-paginado.json" <<'EOF'
[[{"number": 401, "title": "bug #50", "body": ""}]]
EOF
out="$(python3 "$script" "$tmp/prs-paginado.json" "$tmp/bugs-paginado.json" --prs-entregues 50)"
check CA4 "aceita listas paginadas (--slurp)" \
  '{"revertidos": 1, "bugs_pos_merge": 1}' "$out"

echo
echo "$((total - failures))/$total ok"
(( failures == 0 ))
