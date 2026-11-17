#!/usr/bin/env bash
# Testa scripts/acao-status.py (SPEC-95, CA2 a CA4) com comentários de exemplo.
# Uso: bash scripts/test-acao-status.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/acao-status.py"

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

# run <arquivo>: saída do script
run() { python3 "$script" "$1" 2>/dev/null; }

U=https://github.com/o/r/issues/1

# CA2: um item marcado e um desmarcado, entrada paginada (--slurp).
cat > "$tmp/pendente.json" <<'EOF'
[[
 {"body": "<!-- fabrica:triagem -->\n- [ ] não conta", "created_at": "2026-11-17T09:00:00Z", "html_url": "https://github.com/o/r/issues/1#t"},
 {"body": "<!-- fabrica:acao etapa=implementar -->\n## Ação externa pendente\n- [x] Criar o projeto\n- [ ] Cadastrar o secret `VERCEL_TOKEN`", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#a"}
]]
EOF
check CA2 "pendente, entrada paginada" \
  "estado=pendente etapa=implementar marcados=1 total=2 url=$U#a" "$(run "$tmp/pendente.json")"

# CA3: [x] e [X] marcados, com * e indentação, entrada simples.
cat > "$tmp/concluida.json" <<'EOF'
[
 {"body": "<!-- fabrica:acao etapa=revisar -->\n- [x] Passo 1\n  * [X] Passo 2", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#a"}
]
EOF
check CA3 "concluída com [x], [X], * e indentação, entrada simples" \
  "estado=concluida etapa=revisar marcados=2 total=2 url=$U#a" "$(run "$tmp/concluida.json")"

# CA3: item dentro de bloco de código não conta.
cat > "$tmp/bloco.json" <<'EOF'
[
 {"body": "<!-- fabrica:acao etapa=implementar -->\n- [x] Passo real\n```markdown\n- [ ] exemplo dentro do bloco\n```", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#a"}
]
EOF
check CA3 "item em bloco de código é ignorado" \
  "estado=concluida etapa=implementar marcados=1 total=1 url=$U#a" "$(run "$tmp/bloco.json")"

# CA3: sem itens.
cat > "$tmp/sem-itens.json" <<'EOF'
[
 {"body": "<!-- fabrica:acao etapa=implementar -->\nSó texto, sem checklist.\n- item sem caixa", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#a"}
]
EOF
check CA3 "comentário sem itens" \
  "estado=sem-itens etapa=implementar marcados=0 total=0 url=$U#a" "$(run "$tmp/sem-itens.json")"

# CA4: vale o comentário de ação mais recente, mesmo fora de ordem na lista.
cat > "$tmp/dois.json" <<'EOF'
[
 {"body": "<!-- fabrica:acao etapa=implementar -->\n- [ ] Passo que faltou", "created_at": "2026-11-17T12:00:00Z", "html_url": "https://github.com/o/r/issues/1#novo"},
 {"body": "<!-- fabrica:acao etapa=implementar -->\n- [x] Passo 1\n- [x] Passo 2", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#antigo"}
]
EOF
check CA4 "dois comentários de ação: vale o mais recente" \
  "estado=pendente etapa=implementar marcados=0 total=1 url=$U#novo" "$(run "$tmp/dois.json")"

# CA4: sem comentário de ação (a lição e outros marcadores não contam).
cat > "$tmp/sem-comentario.json" <<'EOF'
[[
 {"body": "<!-- fabrica:licao gatilho=escalonado -->\n- [ ] x", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#l"},
 {"body": "texto do usuário citando <!-- fabrica:acao etapa=implementar -->", "created_at": "2026-11-17T11:00:00Z", "html_url": "https://github.com/o/r/issues/1#u"}
], []]
EOF
check CA4 "sem comentário de ação" \
  "estado=sem-comentario etapa=- marcados=0 total=0 url=-" "$(run "$tmp/sem-comentario.json")"

# CA4: etapa fora de implementar e revisar.
cat > "$tmp/etapa.json" <<'EOF'
[
 {"body": "<!-- fabrica:acao etapa=spec -->\n- [ ] Passo", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#a"}
]
EOF
check CA4 "etapa inválida" \
  "estado=etapa-invalida etapa=spec marcados=0 total=1 url=$U#a" "$(run "$tmp/etapa.json")"

# CA4: marcador sem etapa.
cat > "$tmp/sem-etapa.json" <<'EOF'
[
 {"body": "<!-- fabrica:acao -->\n- [ ] Passo", "created_at": "2026-11-17T10:00:00Z", "html_url": "https://github.com/o/r/issues/1#a"}
]
EOF
check CA4 "marcador sem etapa" \
  "estado=etapa-invalida etapa=- marcados=0 total=1 url=$U#a" "$(run "$tmp/sem-etapa.json")"

# CA4: arquivo ausente e JSON inválido saem com código 2.
python3 "$script" "$tmp/nao-existe.json" >/dev/null 2>&1
check CA4 "arquivo ausente sai com código 2" "2" "$?"
printf 'isto não é json' > "$tmp/invalido.json"
python3 "$script" "$tmp/invalido.json" >/dev/null 2>&1
check CA4 "JSON inválido sai com código 2" "2" "$?"

echo
if [[ $failures -eq 0 ]]; then
  echo "$total testes passaram"
else
  echo "$failures de $total testes falharam"
  exit 1
fi
