#!/usr/bin/env bash
# Testes dos dois arquivos do revisor (SPEC-177): agents/revisor.md, lido pelo
# Claude Code e pelo OpenCode, e agy-agents/revisor.md, declarado no agents.json
# e lido pelo Antigravity (agy). Os dois têm o mesmo corpo. Usa só
# `agy plugin validate` e `claude plugin validate`, que não instalam nada nem
# mexem em ~/.gemini ou ~/.claude. Sem o binário no PATH, o caso sai como pulado.
# Uso: scripts/test-revisor-agent.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
agent="$root/agents/revisor.md"
agy_agent="$root/agy-agents/revisor.md"
agents_json="$root/agents.json"

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
# body <arquivo>: tudo depois do segundo `---`.
body() { awk 'count >= 2 { print; next } $0 == "---" { count++ }' "$1"; }
# field <arquivo> <campo>: a linha `<campo>: ...` do frontmatter.
field() { frontmatter "$1" | grep -m 1 "^$2: "; }

# --- CA1: frontmatter de agents/revisor.md igual ao da main; agy-agents/revisor.md com o mesmo corpo ---
if git -C "$root" show origin/main:agents/revisor.md > "$tmp/revisor-main.md" 2>/dev/null; then
  # SPEC-98: o único campo novo é o maxTurns. Tirado das duas versões, para o
  # teste seguir verde na main depois do merge.
  check CA1 "frontmatter de agents/revisor.md igual ao da origin/main, fora o maxTurns" sim \
    "$(yesno diff -q <(frontmatter "$tmp/revisor-main.md" | grep -v '^maxTurns:') \
      <(frontmatter "$agent" | grep -v '^maxTurns:'))"
  check CA1 "agents/revisor.md com maxTurns: 80" "maxTurns: 80" "$(field "$agent" maxTurns)"
  check CA1 "agy-agents/revisor.md sem maxTurns" "" "$(field "$agy_agent" maxTurns)"
else
  skip CA1 "frontmatter de agents/revisor.md igual ao da origin/main" "origin/main ausente"
fi

if [[ -f "$agy_agent" ]]; then
  fm="$(frontmatter "$agy_agent")"
  has() { grep -qxF "$1" <<<"$fm"; }
  check CA1 "agy: tools com os nomes do agy" sim "$(yesno has 'tools: [read_file, run_command, manage_task]')"
  check CA1 "agy: subagent: true" sim "$(yesno has 'subagent: true')"
  check CA1 "agy: mainAgent: false" sim "$(yesno has 'mainAgent: false')"
  check CA1 "agy: sem edit_file nem write_file" não "$(yesno grep -qE 'edit_file|write_file' <<<"$fm")"
  check CA1 "agy: mesmo name" "$(field "$agent" name)" "$(field "$agy_agent" name)"
  check CA1 "agy: mesma description" "$(field "$agent" description)" "$(field "$agy_agent" description)"
  check CA1 "agy: corpo igual ao do agents/revisor.md" sim \
    "$(yesno diff -q <(body "$agent") <(body "$agy_agent"))"
else
  check CA1 "agy-agents/revisor.md existe" sim não
fi

# --- CA2: agents.json declara apenas o revisor do agy, sem subagentes de etapa ---
check CA2 "agents.json declara apenas o revisor do agy" \
  '{"entries":[{"path":"agy-agents/revisor.md"}]}' \
  "$(tr -d ' \n' < "$agents_json" 2>/dev/null)"

for stage_agent in triador especificador implementador; do
  check CA2 "agy-agents/$stage_agent.md removido" não "$(yesno test -e "$root/agy-agents/$stage_agent.md")"
done

# validate_agy [--agents-json] [--agents] [--agy-agents]: monta um plugin mínimo
# do agy com as peças pedidas e imprime a saída de `agy plugin validate --strict`
# seguida de `exit=<código>`.
validate_agy() {
  local dir
  dir="$(mktemp -d "$tmp/agy.XXXXXX")"
  mkdir -p "$dir/.antigravity-plugin"
  printf '{"name":"fabrica-revisor-test","version":"0.0.0"}\n' > "$dir/.antigravity-plugin/plugin.json"
  for part in "$@"; do
    case "$part" in
      --agents-json) cp "$agents_json" "$dir/agents.json" ;;
      --agents) mkdir -p "$dir/agents" && cp "$agent" "$dir/agents/revisor.md" ;;
      --agy-agents) mkdir -p "$dir/agy-agents" && cp "$root"/agy-agents/*.md "$dir/agy-agents/" ;;
    esac
  done
  agy plugin validate "$dir" --strict 2>&1
  echo "exit=$?"
}
count_agents() { grep -o 'agents [0-9]*' <<<"$1" | head -n 1; }
errors() { grep -c '✗' <<<"$1"; }

if ! command -v agy >/dev/null 2>&1; then
  skip CA2 "agy plugin validate" "agy ausente"
elif [[ ! -f "$agy_agent" || ! -f "$agents_json" ]]; then
  check CA2 "agy-agents/revisor.md e agents.json existem" sim não
else
  # Só o revisor do agy: o validate estrito passa com agents 1.
  out="$(validate_agy --agents-json --agy-agents)"
  check CA2 "agy: agents.json com o revisor passa no --strict" exit=0 "$(tail -n 1 <<<"$out")"
  check CA2 "agy: agents.json com o revisor conta agents 1" "agents 1" "$(count_agents "$out")"

  # O plugin como a fábrica o entrega: o agy carrega o revisor do agents.json e
  # só reclama do agents/revisor.md, que ele pula por causa do tools em string.
  out="$(validate_agy --agents-json --agents --agy-agents)"
  check CA2 "agy: plugin completo conta agents 1" "agents 1" "$(count_agents "$out")"
  check CA2 "agy: plugin completo sai com 1" "exit=1" "$(tail -n 1 <<<"$out")"
  check CA2 "agy: o único erro é o agents/revisor.md pulado" 1 "$(errors "$out")"
  check CA2 "agy: o erro é sobre o agents/revisor.md" sim "$(yesno grep -q '✗ agents/revisor.md' <<<"$out")"
  check CA2 "agy: nenhum erro sobre agy-agents/" não "$(yesno grep -q '✗ agy-agents/' <<<"$out")"

  # Regressão: sem o agents.json, o agy não carrega nenhum agente.
  out="$(validate_agy --agents --agy-agents)"
  check CA2 "regressão: sem agents.json, agents 0" "agents 0" "$(count_agents "$out")"
  check CA2 "regressão: sem agents.json, agy avisa que pula o agente" sim \
    "$(yesno grep -q 'The loader skips this agent' <<<"$out")"
fi

# --- CA3: o Claude Code aceita o plugin e lista o fabrica:revisor ---
if command -v claude >/dev/null 2>&1; then
  out="$(claude plugin validate "$root" 2>&1)"
  code=$?
  check CA3 "claude plugin validate passa" 0 "$code"
  check CA3 "claude lista agents: fabrica:revisor" sim "$(yesno grep -q 'agents: fabrica:revisor' <<<"$out")"
  check CA3 "claude lista um só agente" 1 "$(grep -c 'agents: ' <<<"$out")"
  check CA3 "nenhum aviso sobre agents/revisor.md" não "$(yesno grep -q 'agents/revisor.md' <<<"$out")"
  check CA3 "nenhum aviso sobre agy-agents/ nem agents.json" não \
    "$(yesno grep -qE 'agy-agents|agents\.json' <<<"$out")"
else
  skip CA3 "claude plugin validate" "claude ausente"
fi

echo
echo "$((total - failures))/$total ok, $skipped pulado(s)"
[[ $failures -eq 0 ]]
