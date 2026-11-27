#!/usr/bin/env bash
# Testes dos campos de frontmatter das skills (SPEC-98): disallowed-tools no
# avancar, context: fork e effort: medium no status e no metricas, effort: medium
# no setup, nada disso nas etapas de julgamento, o claude plugin validate, a
# leitura pelo parseFrontmatter do adaptador do OpenCode e a versão do plugin.
# Sem o binário (claude, node ≥ 22.6) ou sem a origin/main, o caso sai como pulado.
# Uso: scripts/test-skill-frontmatter.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
skills="$root/skills"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0 total=0 skipped=0
check() { # check <CA> <descrição> <esperado> <obtido>
  total=$((total + 1))
  if [[ "$4" == "$3" ]]; then
    printf 'ok      %-4s %s\n' "$1" "$2"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3" "$4"
  fi
}
skip() { # skip <CA> <descrição> <motivo>
  skipped=$((skipped + 1))
  printf 'pulado  %-4s %s (%s)\n' "$1" "$2" "$3"
}
yesno() { if "$@"; then echo sim; else echo não; fi; }

# frontmatter <arquivo>: as linhas entre o primeiro e o segundo `---`.
frontmatter() { awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside' "$1"; }
# has_line <skill> <linha>: o frontmatter da skill tem a linha exata.
has_line() { frontmatter "$skills/$1/SKILL.md" | grep -qxF "$2"; }
# has_key <skill> <campo>: o frontmatter da skill tem alguma linha `<campo>:`.
has_key() { frontmatter "$skills/$1/SKILL.md" | grep -q "^$2:"; }

# --- CA1: avancar com disallowed-tools, sem effort nem model ---
check CA1 "avancar: disallowed-tools: AskUserQuestion" sim "$(yesno has_line avancar 'disallowed-tools: AskUserQuestion')"
check CA1 "avancar: sem effort" não "$(yesno has_key avancar effort)"
check CA1 "avancar: sem model" não "$(yesno has_key avancar model)"

# --- CA2: status e metricas em fork, general-purpose, primeiro plano e esforço médio ---
for s in status metricas; do
  for line in 'context: fork' 'agent: general-purpose' 'background: false' 'effort: medium'; do
    check CA2 "$s: $line" sim "$(yesno has_line "$s" "$line")"
  done
  check CA2 "$s: sem model" não "$(yesno has_key "$s" model)"
done

# --- CA3: setup em esforço médio, sem fork nem model ---
check CA3 "setup: effort: medium" sim "$(yesno has_line setup 'effort: medium')"
check CA3 "setup: sem context" não "$(yesno has_key setup context)"
check CA3 "setup: sem model" não "$(yesno has_key setup model)"

# --- CA4: etapas de julgamento sem effort, model nem context ---
for s in triagem spec implementar revisar; do
  for key in effort model context; do
    check CA4 "$s: sem $key" não "$(yesno has_key "$s" "$key")"
  done
done

# --- CA6: o Claude Code aceita o plugin sem aviso sobre as skills alteradas ---
if command -v claude >/dev/null 2>&1; then
  out="$(claude plugin validate "$root" 2>&1)"
  code=$?
  check CA6 "claude plugin validate passa" 0 "$code"
  for s in avancar status metricas setup; do
    check CA6 "nenhum aviso sobre skills/$s" não "$(yesno grep -q "skills/$s" <<<"$out")"
  done
else
  skip CA6 "claude plugin validate" "claude ausente"
fi

# --- CA7: o parseFrontmatter do OpenCode lê os quatro arquivos como antes ---
node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a===22&&b>=6)?0:1)'
}
if ! node_ok; then
  skip CA7 "parseFrontmatter do OpenCode" "node ≥ 22.6 ausente"
elif ! git -C "$root" rev-parse --verify -q origin/main >/dev/null; then
  skip CA7 "parseFrontmatter do OpenCode" "origin/main ausente"
else
  # A função sai do server.ts tal como está; o resto do arquivo importa o
  # @opencode/plugin, que não está instalado fora do OpenCode.
  awk '/^export function parseFrontmatter\(/ { inside = 1 } inside { print } inside && /^}$/ { exit }' \
    "$root/opencode/server.ts" > "$tmp/parse.ts"
  cat >> "$tmp/parse.ts" <<'EOF'
import { readFileSync } from "node:fs"
const parsed = parseFrontmatter(readFileSync(process.argv[2], "utf8"))
if (!parsed) { console.log("sem frontmatter"); process.exit(0) }
const f = parsed.fields
console.log(JSON.stringify({ name: f["name"], description: f["description"], autoinvoke: f["disable-model-invocation"] !== "true" }))
EOF
  parse() { node --experimental-strip-types --no-warnings "$tmp/parse.ts" "$1" 2>&1; }
  for s in status metricas setup avancar; do
    git -C "$root" show "origin/main:skills/$s/SKILL.md" > "$tmp/$s-main.md"
    check CA7 "$s: name, description e autoinvoke iguais aos da origin/main" \
      "$(parse "$tmp/$s-main.md")" "$(parse "$skills/$s/SKILL.md")"
  done
fi

# --- CA13: a versão do plugin é ao menos 0.60.0 e não é menor que a da origin/main ---
# Comparação por ordem de versão, para o teste seguir verde na main depois do
# merge e nas versões seguintes.
version() { python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])'; }
at_least() { # at_least <versão> <mínimo>
  python3 -c 'import sys; v=lambda s: tuple(map(int, s.split("."))); sys.exit(0 if v(sys.argv[1]) >= v(sys.argv[2]) else 1)' "$1" "$2"
}
if main_version="$(git -C "$root" show origin/main:.claude-plugin/plugin.json 2>/dev/null | version)"; then
  current="$(version < "$root/.claude-plugin/plugin.json")"
  check CA13 "versão do plugin ($current) é ao menos 0.60.0" sim "$(yesno at_least "$current" 0.60.0)"
  check CA13 "versão do plugin ($current) não é menor que a da origin/main ($main_version)" sim \
    "$(yesno at_least "$current" "$main_version")"
else
  skip CA13 "versão do plugin" "origin/main ausente"
fi

echo
echo "$((total - failures))/$total ok, $skipped pulado(s)"
[[ $failures -eq 0 ]]
