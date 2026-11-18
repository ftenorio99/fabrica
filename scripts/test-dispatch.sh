#!/usr/bin/env bash
# Testa o workflow templates/workflows/agente.yml e o scripts/dispatch.sh
# (SPEC-105, CA1 a CA11) com `gh` e `claude` falsos.
# Uso: bash scripts/test-dispatch.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/dispatch.sh"
workflow="$script_dir/../templates/workflows/agente.yml"

python3 -c 'import yaml' 2>/dev/null || { echo "test-dispatch: falta o PyYAML (pip install pyyaml ou apt install python3-yaml)." >&2; exit 1; }

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

# wf <expressão python sobre w (o YAML) e steps (os passos do job)>
wf() {
  python3 -I -c '
import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
job = w["jobs"]["etapa"]
steps = job["steps"]
def step(name):
    return next(s for s in steps if s.get("name") == name)
print(eval(sys.argv[2]))
' "$workflow" "$1"
}

# CA1: gatilho e filtro do job. O PyYAML lê a chave "on" como True.
check CA1 "dispara só em issues" "['issues']" "$(wf 'list(w[True].keys())')"
check CA1 "só no tipo labeled" "['labeled']" "$(wf 'w[True]["issues"]["types"]')"
check CA1 "job exige a label agente" "True" "$(wf '"github.event.label.name == '"'"'agente'"'"'" in job["if"]')"
check CA1 "job exige a issue aberta" "True" "$(wf '"github.event.issue.state == '"'"'open'"'"'" in job["if"]')"

# CA2: concorrência, runner e tempos.
check CA2 "grupo de concorrência por issue" "True" "$(wf '"github.event.issue.number" in w["concurrency"]["group"]')"
check CA2 "sem cancelar a execução em curso" "False" "$(wf 'w["concurrency"]["cancel-in-progress"]')"
check CA2 "roda em ubuntu-latest" "ubuntu-latest" "$(wf 'job["runs-on"]')"
check CA2 "40 min no job" "40" "$(wf 'job["timeout-minutes"]')"
check CA2 "30 min no passo do despacho" "30" "$(wf 'step("Roda a etapa")["timeout-minutes"]')"

# CA3: permissões.
check CA3 "permissões exatas" "{'contents': 'read', 'issues': 'write'}" "$(wf 'w["permissions"]')"
check CA3 "o job não amplia as permissões" "False" "$(wf '"permissions" in job')"

# CA4: nada de ${{ em run:, cada secret só no passo dele.
check CA4 "nenhum run: com \${{" "[]" "$(wf '[s["name"] for s in steps if "${{" in s.get("run", "")]')"
check CA4 "FABRICA_PLUGIN_TOKEN só no passo de instalação" "['Instala o plugin da fábrica']" \
  "$(wf '[s["name"] for s in steps if "FABRICA_PLUGIN_TOKEN" in yaml.safe_dump(s)]')"
check CA4 "CLAUDE_CODE_OAUTH_TOKEN só no passo do despacho" "['Roda a etapa']" \
  "$(wf '[s["name"] for s in steps if "CLAUDE_CODE_OAUTH_TOKEN" in yaml.safe_dump(s)]')"
check CA4 "os secrets ficam no env do passo" "True" \
  "$(wf '"secrets." in step("Instala o plugin da fábrica")["env"]["GH_TOKEN"] and "secrets." in step("Roda a etapa")["env"]["CLAUDE_CODE_OAUTH_TOKEN"]')"
check CA4 "nenhum secret fora de env" "True" \
  "$(wf 'all("secrets." not in yaml.safe_dump({k: v for k, v in s.items() if k != "env"}) for s in steps)')"

# CA5: checkout sem guardar credenciais.
check CA5 "checkout com persist-credentials: false" "False" \
  "$(wf 'next(s for s in steps if s.get("uses", "").startswith("actions/checkout@"))["with"]["persist-credentials"]')"

# --- dispatch.sh com gh e claude falsos ---
bin="$tmp/bin"
mkdir -p "$bin" "$tmp/home"
calls="$tmp/calls.log"
cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$calls"
case "\$1 \$2" in
  "issue view") cat "$tmp/view.json" ;;
  "api repos/"*) cat "$tmp/timeline.json" ;;
  "issue edit") ;;
  "issue comment")
    while [[ \$# -gt 0 ]]; do [[ \$1 == --body-file ]] && cp "\$2" "$tmp/comment.txt"; shift; done ;;
  *) exit 9 ;;
esac
EOF
cat > "$bin/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$tmp/claude.args"
cat "$tmp/claude.json"
exit "\$(cat "$tmp/claude.exit")"
EOF
chmod +x "$bin/gh" "$bin/claude"

now="$(date -u -d 2026-11-18T12:00:00Z +%s)"
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# setup <estado> <labels separadas por vírgula> [comentário]: prepara a issue falsa e limpa o registro.
setup() {
  python3 -I -c '
import json, sys
labels = [{"name": l} for l in sys.argv[2].split(",") if l]
comments = [{"body": sys.argv[3]}] if len(sys.argv) > 3 else []
print(json.dumps({"state": sys.argv[1], "labels": labels, "comments": comments}))
' "$@" > "$tmp/view.json"
  echo '[[]]' > "$tmp/timeline.json"
  echo '{"type":"result","is_error":false,"result":"texto secreto do result"}' > "$tmp/claude.json"
  echo 0 > "$tmp/claude.exit"
  rm -rf "$calls" "$tmp/claude.args" "$tmp/comment.txt" "$tmp/runner"
  mkdir -p "$tmp/runner"
}

# timeline <segundos atrás>: um evento labeled em-andamento
timeline() {
  printf '[[{"event":"labeled","label":{"name":"em-andamento"},"created_at":"%s"},{"event":"labeled","label":{"name":"agente"},"created_at":"%s"}]]\n' \
    "$(iso $((now - $1)))" "$(iso $((now - 1)))" > "$tmp/timeline.json"
}

# dispatch <subcomando> [nº]: roda o script e imprime o código de saída na última linha
dispatch() {
  env -u PROXY_CA_CERT_B64 PATH="$bin:$PATH" HOME="$tmp/home" FABRICA_SBX_PERSISTENT_FILE="$tmp/ausente.sh" \
    GITHUB_REPOSITORY=dono/projeto RUNNER_TEMP="$tmp/runner" GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=4242 \
    FABRICA_CLAUDE_BIN="$bin/claude" FABRICA_NOW="$now" CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-valor-do-teste \
    bash "$script" "$1" "${2:-7}" > "$tmp/out.txt" 2> "$tmp/err.txt"
  echo $?
}
called_claude() { [[ -f "$tmp/claude.args" ]] && echo sim || echo não; }
edits() { grep -c '^issue edit' "$calls" 2>/dev/null || true; }
comments() { grep -c '^issue comment' "$calls" 2>/dev/null || true; }

# CA6: pulos sem efeito.
skip_case() { # skip_case <descrição> <argumentos do setup...>
  local label="$1"
  shift
  setup "$@"
  check CA6 "$label: sai com 0" "0" "$(dispatch run)"
  check CA6 "$label: imprime o pulo" "sim" "$(grep -q '^pulo: ' "$tmp/out.txt" && echo sim || echo não)"
  check CA6 "$label: não chama o claude" "não" "$(called_claude)"
  check CA6 "$label: não mexe em label nem comenta" "0 0" "$(edits) $(comments)"
}
skip_case "issue fechada" CLOSED agente
skip_case "sem a label agente" OPEN bug
skip_case "já triada" OPEN agente,em-andamento $'<!-- fabrica:triagem -->\n## Triagem'

# CA7: em-andamento recente e esquecida.
setup OPEN agente,em-andamento
timeline 7140
check CA7 "1 h 59 min: sai com 0" "0" "$(dispatch run)"
check CA7 "1 h 59 min: não chama o claude" "não" "$(called_claude)"
check CA7 "1 h 59 min: não mexe na label" "0" "$(edits)"
check CA10 "unmark depois do pulo não chama gh issue edit" "0 0" "$(dispatch unmark) $(edits)"

setup OPEN agente,em-andamento
timeline 7200
check CA7 "2 h 00 min: sai com 0" "0" "$(dispatch run)"
check CA7 "2 h 00 min: remove e aplica de novo" \
  "issue edit 7 --repo dono/projeto --remove-label em-andamento|issue edit 7 --repo dono/projeto --add-label em-andamento" \
  "$(grep '^issue edit' "$calls" | paste -sd '|')"
check CA7 "2 h 00 min: roda a etapa" "sim" "$(called_claude)"

setup OPEN agente,em-andamento
timeline 90000
check CA7 "25 h: roda a etapa" "0 sim" "$(dispatch run) $(called_claude)"

# CA8: caminho feliz e filtro das labels.
setup OPEN 'agente,bug,modelo:opus,modelo:x;rm -rf ~,modelo:$(id)'
check CA8 "sai com 0" "0" "$(dispatch run)"
check CA8 "aplica em-andamento antes do claude" "issue edit 7 --repo dono/projeto --add-label em-andamento" \
  "$(grep '^issue edit' "$calls")"
check CA8 "chama a triagem do número da issue" "/fabrica:triagem 7" "$(tail -n 1 "$tmp/claude.args")"
check CA8 "usa o modelo da triagem (sonnet)" "sim" "$(grep -qx 'claude-sonnet-5-5' "$tmp/claude.args" && echo sim || echo não)"
# O claude falso não vê as labels; o stage-model.sh recebe só as modelo:* seguras.
# Com duas modelo:* ele sairia com 2, então só modelo:opus chegou.
check CA8 "nenhuma label insegura chega ao comando" "não" \
  "$(grep -qE 'bug|rm -rf|\$\(id\)' "$tmp/claude.args" && echo sim || echo não)"
check CA10 "unmark remove a label que o job aplicou" "0" "$(dispatch unmark)"
check CA10 "unmark chama gh issue edit --remove-label" "issue edit 7 --repo dono/projeto --remove-label em-andamento" \
  "$(grep '^issue edit' "$calls" | tail -n 1)"

setup OPEN agente,modelo:opus,modelo:haiku
check CA8 "duas modelo:* seguras saem com 2" "2" "$(dispatch run)"

# CA9: falhas da etapa.
setup OPEN agente; echo 1 > "$tmp/claude.exit"
check CA9 "claude com erro sai com 1" "1" "$(dispatch run)"
setup OPEN agente; echo 'não é json' > "$tmp/claude.json"
check CA9 "JSON ilegível sai com 1" "1" "$(dispatch run)"
setup OPEN agente; echo '{"is_error":true,"result":"x"}' > "$tmp/claude.json"
check CA9 "is_error verdadeiro sai com 1" "1" "$(dispatch run)"
setup OPEN agente; echo '{"result":"x"}' > "$tmp/claude.json"
check CA9 "is_error ausente sai com 1" "1" "$(dispatch run)"

# CA11: comentário de falha.
body() { cat "$tmp/comment.txt" 2>/dev/null; }
reason() { grep -o '^\*\*Motivo:\*\* `[a-z-]*`' "$tmp/comment.txt" 2>/dev/null | sed 's/.*`\(.*\)`/\1/'; }
no_leak() {
  if grep -q 'texto secreto do result\|sk-ant-oat-valor-do-teste\|rm -rf' "$tmp/comment.txt"; then echo vazou; else echo limpo; fi
}

setup OPEN agente
echo '{"is_error":true,"result":"texto secreto do result","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}},{"tool_name":"Write","tool_input":{}},{"tool_name":"Bash","tool_input":{}}]}' > "$tmp/claude.json"
dispatch run >/dev/null
check CA11 "permissao: sai com 0" "0" "$(dispatch fail)"
check CA11 "permissao: comenta por --body-file" "1" "$(grep -c -- '^issue comment 7 --repo dono/projeto --body-file ' "$calls")"
check CA11 "permissao: marcador na primeira linha" "<!-- fabrica:dispatcher -->" "$(body | head -n 1)"
check CA11 "permissao: motivo" "permissao" "$(reason)"
check CA11 "permissao: lista as ferramentas sem repetir" "**Ferramentas negadas:** \`Bash\`, \`Write\`" "$(grep '^\*\*Ferramentas negadas' "$tmp/comment.txt")"
check CA11 "permissao: etapa" "**Etapa:** triagem" "$(grep '^\*\*Etapa' "$tmp/comment.txt")"
check CA11 "permissao: link do run" "**Run:** https://github.com/dono/projeto/actions/runs/4242" "$(grep '^\*\*Run' "$tmp/comment.txt")"
check CA11 "permissao: sem result, argumentos nem secret" "limpo" "$(no_leak)"

setup OPEN agente; echo 1 > "$tmp/claude.exit"
dispatch run >/dev/null; dispatch fail >/dev/null
check CA11 "erro: motivo" "erro" "$(reason)"
check CA11 "erro: código de saída" "**Saída do processo da etapa:** 1" "$(grep '^\*\*Saída' "$tmp/comment.txt")"
check CA11 "erro: sem result nem secret" "limpo" "$(no_leak)"

setup OPEN agente; echo 'lixo' > "$tmp/claude.json"
dispatch run >/dev/null; dispatch fail >/dev/null
check CA11 "JSON ilegível: motivo erro" "erro" "$(reason)"

setup OPEN agente,modelo:opus,modelo:haiku
dispatch run >/dev/null; dispatch fail >/dev/null
check CA11 "labels: motivo" "labels" "$(reason)"

setup OPEN agente
dispatch fail >/dev/null
check CA11 "sem-resultado: motivo" "sem-resultado" "$(reason)"
check CA11 "sem-resultado: sem código de saída" "0" "$(grep -c '^\*\*Saída' "$tmp/comment.txt")"
check CA11 "sem-resultado: marcador na primeira linha" "<!-- fabrica:dispatcher -->" "$(body | head -n 1)"

# Uso inválido.
check uso "número inválido sai com 1" "1" "$(dispatch run 'abc')"
check uso "subcomando desconhecido sai com 1" "1" "$(dispatch deploy)"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
