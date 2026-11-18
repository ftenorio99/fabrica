#!/usr/bin/env bash
# Testes do frontmatter de agents/revisor.md (SPEC-177): o mesmo arquivo serve ao
# Claude Code, ao Antigravity (agy) e ao OpenCode. Usa só `agy plugin validate` e
# `claude plugin validate`, que não instalam nada nem mexem em ~/.gemini ou
# ~/.claude. Sem o binário no PATH, o caso sai como pulado.
# Uso: scripts/test-revisor-agent.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
agent="$root/agents/revisor.md"

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

# frontmatter <arquivo>: as linhas entre o primeiro e o segundo `---`.
frontmatter() { awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside' "$1"; }
# body <arquivo>: tudo depois do segundo `---`.
body() { awk 'count >= 2 { print; next } $0 == "---" { count++ }' "$1"; }

# --- CA1: frontmatter novo e corpo igual ao da main ---
fm="$(frontmatter "$agent")"
has() { grep -qxF "$1" <<<"$fm" && echo sim || echo não; }
check CA1 "tools em lista com os nomes do Claude Code e do agy" sim \
  "$(has 'tools: [Read, Grep, Glob, Bash, read_file, run_command, manage_task]')"
check CA1 "subagent: true" sim "$(has 'subagent: true')"
check CA1 "mainAgent: false" sim "$(has 'mainAgent: false')"
check CA1 "name continua revisor" sim "$(has 'name: revisor')"

if base="$(git -C "$root" show origin/main:agents/revisor.md 2>/dev/null)"; then
  printf '%s\n' "$base" > "$tmp/revisor-main.md"
  if diff -q <(body "$tmp/revisor-main.md") <(body "$agent") >/dev/null; then same=sim; else same=não; fi
  check CA1 "corpo igual ao da origin/main" sim "$same"
else
  skip CA1 "corpo igual ao da origin/main" "origin/main ausente"
fi

# --- CA2: o carregador do agy aceita o agente; o tools antigo é recusado ---
# validate_agy <arquivo do agente>: monta um plugin mínimo do agy com o agente e
# imprime a saída de `agy plugin validate --strict` seguida de `exit=<código>`.
validate_agy() {
  local dir
  dir="$(mktemp -d "$tmp/agy.XXXXXX")"
  mkdir -p "$dir/.antigravity-plugin" "$dir/agents"
  printf '{"name":"fabrica-revisor-test","version":"0.0.0"}\n' > "$dir/.antigravity-plugin/plugin.json"
  cp "$1" "$dir/agents/revisor.md"
  agy plugin validate "$dir" --strict 2>&1
  echo "exit=$?"
}

if command -v agy >/dev/null 2>&1; then
  out="$(validate_agy "$agent")"
  check CA2 "agy plugin validate --strict passa" exit=0 "$(tail -n 1 <<<"$out")"
  if grep -q 'agents 1 ' <<<"$out"; then n=sim; else n=não; fi
  check CA2 "agy conta agents 1" sim "$n"

  sed 's/^tools: \[.*\]$/tools: Read, Grep, Glob, Bash/' "$agent" > "$tmp/revisor-old.md"
  out="$(validate_agy "$tmp/revisor-old.md")"
  check CA2 "regressão: tools em string falha no agy" exit=1 "$(tail -n 1 <<<"$out")"
  if grep -q 'The loader skips this agent' <<<"$out"; then n=sim; else n=não; fi
  check CA2 "regressão: agy avisa que pula o agente" sim "$n"
else
  skip CA2 "agy plugin validate" "agy ausente"
fi

# --- CA3: o Claude Code aceita o plugin e lista o fabrica:revisor ---
if command -v claude >/dev/null 2>&1; then
  out="$(claude plugin validate "$root" 2>&1)"
  code=$?
  check CA3 "claude plugin validate passa" 0 "$code"
  if grep -q 'agents: fabrica:revisor' <<<"$out"; then n=sim; else n=não; fi
  check CA3 "claude lista agents: fabrica:revisor" sim "$n"
  if grep -q 'agents/revisor.md' <<<"$out"; then n=sim; else n=não; fi
  check CA3 "nenhum aviso sobre agents/revisor.md" não "$n"
else
  skip CA3 "claude plugin validate" "claude ausente"
fi

echo
echo "$((total - failures))/$total ok, $skipped pulado(s)"
[[ $failures -eq 0 ]]
