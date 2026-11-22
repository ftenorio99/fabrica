#!/usr/bin/env bash
# Testa o workflow templates/workflows/agente.yml e o scripts/dispatch.sh
# (SPEC-105, SPEC-106 e SPEC-107, CA1 a CA5 e CA10 a CA14) com `gh`, `claude` e
# estados falsos.
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
import re, sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
job = w["jobs"]["etapa"]
steps = job["steps"]
def step(name):
    return next(s for s in steps if s.get("name") == name)
def nows(text):
    return re.sub(r"\s+", "", str(text))
print(eval(sys.argv[2]))
' "$workflow" "$1"
}

# --- Workflow ---
# CA1: gatilhos. O PyYAML lê a chave "on" como True.
check CA1 "dispara nos quatro eventos" "['issues', 'issue_comment', 'pull_request_review', 'pull_request_review_comment']" "$(wf 'list(w[True].keys())')"
check CA1 "issues: só labeled" "['labeled']" "$(wf 'w[True]["issues"]["types"]')"
check CA1 "issue_comment: created e edited" "['created', 'edited']" "$(wf 'w[True]["issue_comment"]["types"]')"
check CA1 "pull_request_review: submitted" "['submitted']" "$(wf 'w[True]["pull_request_review"]["types"]')"
check CA1 "pull_request_review_comment: created" "['created']" "$(wf 'w[True]["pull_request_review_comment"]["types"]')"

# CA2: a expressão de filtro da seção 1 da SPEC-107.
filter="(github.event_name == 'issues' && github.event.action == 'labeled' && github.event.issue.state == 'open'
  && (github.event.label.name == 'agente' || github.event.label.name == 'spec-aprovada'))
|| (github.event_name == 'issue_comment' && github.event.action == 'created' && github.event.issue.state == 'open'
  && !startsWith(github.event.comment.body, '<!-- fabrica:'))
|| (github.event_name == 'issue_comment' && github.event.action == 'edited' && !github.event.issue.pull_request
  && github.event.issue.state == 'open' && contains(github.event.issue.labels.*.name, 'acao-externa')
  && startsWith(github.event.comment.body, '<!-- fabrica:acao'))
|| (github.event_name == 'pull_request_review' && github.event.action == 'submitted' && github.event.pull_request.state == 'open'
  && !startsWith(github.event.review.body, '<!-- fabrica:'))
|| (github.event_name == 'pull_request_review_comment' && github.event.action == 'created' && github.event.pull_request.state == 'open'
  && !startsWith(github.event.comment.body, '<!-- fabrica:'))"
nows() { tr -d ' \n\t' <<< "$1"; }
check CA2 "o if do job é a expressão de filtro (sem espaços)" "$(nows "$filter")" "$(wf 'nows(job["if"])')"

# CA3: concorrência e tempos.
group="fabrica-\${{ ($filter) && (github.event.issue.number || github.event.pull_request.number) || format('ignorado-{0}', github.run_id) }}"
check CA3 "o grupo usa a mesma expressão do if" "$(nows "$group")" "$(wf 'nows(w["concurrency"]["group"])')"
check CA3 "sem cancelar a execução em curso" "False" "$(wf 'w["concurrency"]["cancel-in-progress"]')"
check CA3 "roda em ubuntu-latest" "ubuntu-latest" "$(wf 'job["runs-on"]')"
check CA3 "110 min no job" "110" "$(wf 'job["timeout-minutes"]')"
check CA3 "100 min no passo do despacho" "100" "$(wf 'step("Roda a etapa")["timeout-minutes"]')"

# CA4: permissões, secrets e argumentos (SPEC-106 CA9 continua).
check CA4 "permissões exatas: só contents: read" "{'contents': 'read'}" "$(wf 'w["permissions"]')"
check CA4 "o job não amplia as permissões" "False" "$(wf '"permissions" in job')"
check CA4 "nenhum run: com \${{" "[]" "$(wf '[s["name"] for s in steps if "${{" in s.get("run", "")]')"
check CA4 "FABRICA_PLUGIN_TOKEN só no passo de instalação" "['Instala o plugin da fábrica']" \
  "$(wf '[s["name"] for s in steps if "FABRICA_PLUGIN_TOKEN" in yaml.safe_dump(s)]')"
check CA4 "CLAUDE_CODE_OAUTH_TOKEN só no passo que trava os segredos" "['Trava a rede e os segredos']" \
  "$(wf '[s["name"] for s in steps if "CLAUDE_CODE_OAUTH_TOKEN" in yaml.safe_dump(s)]')"
check CA4 "nenhum secret fora de env" "True" \
  "$(wf 'all("secrets." not in yaml.safe_dump({k: v for k, v in s.items() if k != "env"}) for s in steps)')"
check CA4 "github.token só aparece no checkout (que usa o padrão dele)" "[]" \
  "$(wf '[s["name"] for s in steps if "github.token" in yaml.safe_dump(s)]')"
check CA4 "todo GH_TOKEN dos passos vem do FABRICA_GH_TOKEN" "True" \
  "$(wf 'all(s["env"]["GH_TOKEN"] == "${{ secrets.FABRICA_GH_TOKEN }}" for s in steps if "GH_TOKEN" in s.get("env", {}) and s["name"] != "Instala o plugin da fábrica")')"
check CA4 "FABRICA_GH_TOKEN só nos passos que escrevem no GitHub ou travam os segredos" \
  "['Trava a rede e os segredos', 'Roda a etapa', 'Desmarca a issue', 'Publica a falha', 'Publica a falha da instalação']" \
  "$(wf '[s["name"] for s in steps if "FABRICA_GH_TOKEN" in yaml.safe_dump(s)]')"
check CA4 "a ordem: plugin, mitmproxy, prepara, trava, etapa" "['Instala o plugin da fábrica', 'Instala o mitmproxy', 'Prepara o isolamento', 'Trava a rede e os segredos', 'Roda a etapa']" \
  "$(wf '[s["name"] for s in steps if s["name"] in ("Instala o plugin da fábrica", "Instala o mitmproxy", "Prepara o isolamento", "Trava a rede e os segredos", "Roda a etapa")]')"
check CA4 "o despacho roda o claude pelo run-as-agent.sh" "True" \
  "$(wf 'step("Roda a etapa")["env"]["FABRICA_CLAUDE_BIN"].endswith("/scripts/run-as-agent.sh")')"
check CA4 "o despacho não recebe o CLAUDE_CODE_OAUTH_TOKEN" "False" \
  "$(wf '"CLAUDE_CODE_OAUTH_TOKEN" in step("Roda a etapa")["env"]')"
check CA4 "o passo que trava usa o sudo com os dois tokens preservados" "True" \
  "$(wf '"--preserve-env=CLAUDE_CODE_OAUTH_TOKEN,FABRICA_GH_TOKEN" in step("Trava a rede e os segredos")["run"]')"
check CA4 "o mitmproxy vem com versão fixa" "True" "$(wf '"mitmproxy==" in step("Instala o mitmproxy")["run"]')"
check CA4 "checkout da branch padrão, sem guardar credenciais" "\${{ github.event.repository.default_branch }} False" \
  "$(wf '" ".join(str(next(s for s in steps if s.get("uses", "").startswith("actions/checkout@"))["with"][k]) for k in ("ref", "persist-credentials"))')"
kind_expr="\${{ (github.event.pull_request || github.event.issue.pull_request) && 'pr' || 'issue' }}"
number_expr="\${{ github.event.issue.number || github.event.pull_request.number }}"
for pair in "Roda a etapa:run" "Desmarca a issue:unmark" "Publica a falha:fail"; do
  name="${pair%%:*}" sub="${pair##*:}"
  check CA4 "$name: tipo e número do evento só por env" "$kind_expr|$number_expr" \
    "$(wf 'step("'"$name"'")["env"]["EVENT_KIND"] + "|" + step("'"$name"'")["env"]["EVENT_NUMBER"]')"
  check CA4 "$name: chama dispatch.sh $sub com \"\$EVENT_KIND\" \"\$EVENT_NUMBER\"" \
    "bash \"\$FABRICA_PLUGIN_DIR/scripts/dispatch.sh\" $sub \"\$EVENT_KIND\" \"\$EVENT_NUMBER\"" \
    "$(wf 'step("'"$name"'")["run"].strip()')"
done
check CA4 "nenhum passo usa mais o ISSUE_NUMBER" "[]" "$(wf '[s["name"] for s in steps if "ISSUE_NUMBER" in yaml.safe_dump(s)]')"
# SPEC-107, CA24: o stage.json vai como artifact do run, por 3 dias, sem secret.
check CA24 "o artifact do stage.json roda sempre, com retenção de 3 dias, do caminho do despacho" "always()|3|True" \
  "$(wf '"|".join([step("Guarda o stage.json da execução")["if"], str(step("Guarda o stage.json da execução")["with"]["retention-days"]), str(step("Guarda o stage.json da execução")["with"]["path"].endswith("/fabrica-dispatch/stage.json"))])')"
check CA24 "o passo de artifact usa actions/upload-artifact e não tem run nem secret" "True" \
  "$(wf 'step("Guarda o stage.json da execução")["uses"].startswith("actions/upload-artifact@") and "run" not in step("Guarda o stage.json da execução") and "secrets." not in yaml.safe_dump(step("Guarda o stage.json da execução"))')"

# CA5: passo de reserva da falha de instalação.
check CA5 "reserva roda quando o plugin não foi instalado" "failure() && steps.plugin.outputs.path == ''" \
  "$(wf 'step("Publica a falha da instalação")["if"]')"
check CA5 "reserva: só o token das escritas, o tipo, o número e o link" "['EVENT_KIND', 'EVENT_NUMBER', 'GH_TOKEN', 'RUN_URL']" \
  "$(wf 'sorted(step("Publica a falha da instalação")["env"])')"
check CA5 "reserva: não lê nenhum JSON da etapa" "False" \
  "$(wf 'any(t in step("Publica a falha da instalação")["run"] for t in ("stage.json", "jq ", ".json"))')"
wf 'step("Publica a falha da instalação")["run"]' > "$tmp/reserva.sh"
mkdir -p "$tmp/rbin" "$tmp/rrun"
cat > "$tmp/rbin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/reserva.calls"
while [[ \$# -gt 0 ]]; do [[ \$1 == --body-file ]] && cp "\$2" "$tmp/reserva.body"; shift; done
EOF
chmod +x "$tmp/rbin/gh"
reserve() { # reserve <tipo>: roda o run: do passo com um gh falso
  rm -f "$tmp/reserva.calls" "$tmp/reserva.body"
  PATH="$tmp/rbin:$PATH" RUNNER_TEMP="$tmp/rrun" EVENT_KIND="$1" EVENT_NUMBER=30 RUN_URL=https://github.com/dono/projeto/actions/runs/1 \
    bash "$tmp/reserva.sh" >/dev/null 2>&1
  sed 's/ --body-file .*//' "$tmp/reserva.calls"
}
check CA5 "reserva num evento de PR: gh pr comment" "pr comment 30" "$(reserve pr)"
check CA5 "reserva: marcador, etapa não decidida, motivo e link" "<!-- fabrica:dispatcher -->|**Etapa:** não decidida|sim|sim" \
  "$(head -n 1 "$tmp/reserva.body")|$(grep '^\*\*Etapa' "$tmp/reserva.body")|$(grep -q 'sem-resultado' "$tmp/reserva.body" && echo sim)|$(grep -q 'actions/runs/1' "$tmp/reserva.body" && echo sim)"
check CA5 "reserva num evento de issue: gh issue comment" "issue comment 30" "$(reserve issue)"

# SPEC-106 CA11: o workflow do teste de aceite.
accept="$script_dir/../templates/workflows/isolamento-aceite.yml"
check CA11 "isolamento-aceite.yml dispara só por workflow_dispatch" "['workflow_dispatch']" \
  "$(python3 -I -c 'import sys, yaml; print(list(yaml.safe_load(open(sys.argv[1]))[True].keys()))' "$accept")"
check CA11 "isolamento-aceite.yml roda o teste de aceite depois de travar" "True" \
  "$(python3 -I -c 'import sys, yaml; n = [s["name"] for s in yaml.safe_load(open(sys.argv[1]))["jobs"]["aceite"]["steps"]]; print(n.index("Trava a rede e os segredos") < n.index("Teste de aceite"))' "$accept")"

# --- dispatch.sh com gh, claude e estados falsos ---
bin="$tmp/bin"
mkdir -p "$bin"
calls="$tmp/calls.log"
cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$calls"
case "\$1 \$2" in
  "issue view") cat "$tmp/view.json" ;;
  "pr view") [[ -f "$tmp/prview.json" ]] || exit 1; cat "$tmp/prview.json" ;;
  "pr list") cat "$tmp/prlist.json" ;;
  "api repos/"*/timeline) cat "$tmp/timeline.json" ;;
  "api repos/"*/comments) cat "$tmp/comments.json" ;;
  "issue edit") ;;
  "issue comment"|"pr comment")
    while [[ \$# -gt 0 ]]; do [[ \$1 == --body-file ]] && cp "\$2" "$tmp/comment.txt"; shift; done ;;
  *) exit 9 ;;
esac
EOF
cat > "$bin/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$tmp/claude.args"
tail -n 1 "$tmp/claude.args" >> "$tmp/claude.log"
cat "$tmp/claude.json"
exit "\$(cat "$tmp/claude.exit")"
EOF
# Estados falsos em sequência: cada "state" lê a próxima linha de states.txt
# (a última se repete); "branch" usa o leitor real.
cat > "$bin/state" <<EOF
#!/usr/bin/env bash
if [[ \$1 == branch ]]; then exec python3 "$script_dir/issue-state.py" "\$@"; fi
n=\$(( \$(cat "$tmp/state.count" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "$tmp/state.count"
total=\$(wc -l < "$tmp/states.txt")
sed -n "\$(( n < total ? n : total ))p" "$tmp/states.txt"
EOF
chmod +x "$bin/gh" "$bin/claude" "$bin/state"

now="$(date -u -d 2026-11-18T12:00:00Z +%s)"

TRI=$'<!-- fabrica:triagem -->\n## Triagem\n**Atalho:** não'
SPEC=$'<!-- fabrica:spec -->\n## Spec pronta\n**Branch:** `feat/7-coisa`'

# setup <estado> <labels separadas por vírgula> [comentário...]: prepara a issue
# falsa (comentários em minutos sucessivos) e limpa o registro.
setup() {
  python3 -I -c '
import json, sys
labels = [{"name": l} for l in sys.argv[2].split(",") if l]
comments = [{"body": b, "createdAt": "2026-11-18T10:%02d:00Z" % i} for i, b in enumerate(sys.argv[3:])]
print(json.dumps({"state": sys.argv[1], "labels": labels, "comments": comments}))
' "$@" > "$tmp/view.json"
  echo '[[]]' > "$tmp/timeline.json"
  echo '[[]]' > "$tmp/comments.json"
  echo '[]' > "$tmp/prlist.json"
  echo '{"type":"result","is_error":false,"result":"texto secreto do result"}' > "$tmp/claude.json"
  echo 0 > "$tmp/claude.exit"
  rm -rf "$calls" "$tmp/claude.args" "$tmp/claude.log" "$tmp/comment.txt" "$tmp/runner" "$tmp/prview.json" "$tmp/state.count" "$tmp/states.txt"
  mkdir -p "$tmp/runner"
  fake_states=""
}
# states <linha>...: usa o leitor falso com estas linhas em sequência
states() { printf '%s\n' "$@" > "$tmp/states.txt"; fake_states="$bin/state"; }

# timeline <idade em segundos>...: um evento labeled em-andamento por idade
timeline() {
  python3 -I -c '
import json, sys
from datetime import datetime, timezone
now = int(sys.argv[1])
def at(age):
    return datetime.fromtimestamp(now - int(age), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
ev = [{"event": "labeled", "label": {"name": "em-andamento"}, "created_at": at(a)} for a in sys.argv[2:]]
ev.append({"event": "labeled", "label": {"name": "agente"}, "created_at": at(1)})
print(json.dumps([ev]))
' "$now" "$@" > "$tmp/timeline.json"
}

# dispatch <subcomando> [tipo] [nº]: roda o script e imprime o código de saída.
# O claude falso ignora os argumentos fora do prompt, então o --plugin-dir que
# o stage-model.sh acrescenta fora de ~/.claude/plugins não muda o teste.
dispatch() {
  env -u PROXY_CA_CERT_B64 PATH="$bin:$PATH" FABRICA_SBX_PERSISTENT_FILE="$tmp/ausente.sh" \
    GITHUB_REPOSITORY=dono/projeto RUNNER_TEMP="$tmp/runner" GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=4242 \
    FABRICA_CLAUDE_BIN="$bin/claude" FABRICA_NOW="$now" CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-valor-do-teste \
    FABRICA_STATE_BIN="$fake_states" \
    bash "$script" "$1" "${2:-issue}" "${3:-7}" > "$tmp/out.txt" 2> "$tmp/err.txt"
  echo $?
}
called_claude() { [[ -f "$tmp/claude.args" ]] && echo sim || echo não; }
claude_runs() { if [[ -f "$tmp/claude.log" ]]; then wc -l < "$tmp/claude.log" | tr -d ' '; else echo 0; fi; }
state_calls() { cat "$tmp/state.count" 2>/dev/null || echo 0; }
edits() { grep -c '^issue edit' "$calls" 2>/dev/null || true; }
adds() { grep -c '^issue edit .*--add-label em-andamento' "$calls" 2>/dev/null || true; }
comments() { grep -c '^issue comment\|^pr comment' "$calls" 2>/dev/null || true; }
out_has() { grep -q "$1" "$tmp/out.txt" && echo sim || echo não; }

# skip_case <CA> <descrição> [tipo nº]: confere um pulo sem efeito
skip_case() {
  check "$1" "$2: sai com 0" "0" "$(dispatch run "${3:-issue}" "${4:-7}")"
  check "$1" "$2: imprime o pulo" "sim" "$(out_has '^pulo: ')"
  check "$1" "$2: não chama o claude, não mexe em label nem comenta" "não 0 0" "$(called_claude) $(edits) $(comments)"
}

# Pulos da SPEC-105 que continuam valendo.
setup CLOSED agente; skip_case CA11 "issue fechada"
setup OPEN bug; skip_case CA11 "sem a label agente"

# CA10: evento de PR resolve a issue.
prview() { # prview <estado> <head> <números das issues, separados por vírgula> [dono/repo das referências]
  python3 -I -c '
import json, sys
owner, name = (sys.argv[4] if len(sys.argv) > 4 else "dono/projeto").split("/")
refs = [{"number": int(n), "repository": {"name": name, "owner": {"login": owner}}} for n in sys.argv[3].split(",") if n]
print(json.dumps({"state": sys.argv[1], "headRefName": sys.argv[2], "closingIssuesReferences": refs}))
' "$@" > "$tmp/prview.json"
}
open_pr='[{"number":30,"state":"OPEN","isDraft":false,"mergedAt":null,"statusCheckRollup":[],"reviewDecision":"","reviews":[],"comments":[],"updatedAt":"2026-11-18T11:00:00Z"}]'
pr_setup() { setup OPEN agente,spec-pronta,spec-aprovada "$TRI" "$SPEC"; echo "$open_pr" > "$tmp/prlist.json"; }

pr_setup; prview OPEN feat/7-coisa 7
check CA10 "PR com uma issue e a branch dela: sai com 0" "0" "$(dispatch run pr 30)"
check CA10 "PR: roda o revisar da issue resolvida" "/fabrica:revisar 7" "$(tail -n 1 "$tmp/claude.args" 2>/dev/null)"
check CA10 "PR: a em-andamento vai para a issue, não para o PR" "issue edit 7 --repo dono/projeto --add-label em-andamento" "$(grep '^issue edit' "$calls" | head -n 1)"
check CA10 "PR: lista os PRs pela branch da issue, antes e depois da etapa" "2" "$(grep -c -- '^pr list --repo dono/projeto --head feat/7-coisa --state all' "$calls")"
check CA10 "PR: unmark remove a label da issue resolvida" "0|issue edit 7 --repo dono/projeto --remove-label em-andamento" \
  "$(dispatch unmark pr 30)|$(grep '^issue edit' "$calls" | tail -n 1)"

pr_setup; prview OPEN feat/7-coisa 7; echo 1 > "$tmp/claude.exit"
dispatch run pr 30 >/dev/null; dispatch fail pr 30 >/dev/null
check CA10 "PR: a falha vai para a issue resolvida" "1 0" \
  "$(grep -c '^issue comment 7 --repo dono/projeto --body-file' "$calls") $(grep -c '^pr comment' "$calls")"

pr_setup; prview OPEN feat/7-coisa ''; skip_case CA10 "PR sem issue em closingIssuesReferences" pr 30
check CA10 "PR sem issue: motivo" "pulo: PR #30 sem uma issue única" "$(cat "$tmp/out.txt")"
pr_setup; prview OPEN feat/7-coisa 7,8; skip_case CA10 "PR com duas issues" pr 30
pr_setup; prview OPEN feat/7-coisa 7 outro/repo; skip_case CA10 "PR que cita issue de outro repositório" pr 30
pr_setup; prview OPEN feat/7-outra 7; skip_case CA10 "PR de outra branch" pr 30
check CA10 "PR de outra branch: motivo" "pulo: PR #30 não é da branch da issue #7" "$(cat "$tmp/out.txt")"
pr_setup; prview CLOSED feat/7-coisa 7; skip_case CA10 "PR fechado" pr 30
setup OPEN agente,spec-aprovada "$TRI"; prview OPEN feat/7-coisa 7; skip_case CA10 "issue sem branch" pr 30
setup OPEN spec-aprovada "$TRI" "$SPEC"; prview OPEN feat/7-coisa 7; skip_case CA10 "issue resolvida sem agente" pr 30

# CA11: laço.
setup OPEN agente; states "linha=5 etapa=spec quem=agente inconsistencia=-" "linha=7 etapa=- quem=usuario inconsistencia=-"
check CA11 "5 → 7: sai com 0" "0" "$(dispatch run)"
check CA11 "5 → 7: 2 leituras de estado e 1 claude, o da spec" "2 1 /fabrica:spec 7" "$(state_calls) $(claude_runs) $(cat "$tmp/claude.log")"
check CA11 "5 → 7: para no portão" "sim" "$(out_has 'portão do usuário')"
check CA11 "aplica a em-andamento uma vez" "1" "$(adds)"

setup OPEN agente; states "linha=5 etapa=spec quem=agente inconsistencia=-"
check CA11 "sem avanço: sai com 0 depois de 1 etapa" "0 1" "$(dispatch run) $(claude_runs)"
check CA11 "sem avanço: avisa" "sim" "$(out_has 'sem avanço')"

setup OPEN agente; states "linha=5 etapa=spec quem=agente inconsistencia=-" "linha=7 etapa=- quem=usuario inconsistencia=-"; echo 1 > "$tmp/claude.exit"
check CA11 "falha: sai com 1 e grava a etapa" "1 spec" "$(dispatch run) $(cat "$tmp/runner/fabrica-dispatch/stage")"
check CA11 "falha: para na primeira etapa" "1 1" "$(claude_runs) $(state_calls)"

setup OPEN agente; states "linha=2 etapa=triagem quem=agente inconsistencia=-" "linha=5 etapa=spec quem=agente inconsistencia=-" \
  "linha=6 etapa=spec quem=agente inconsistencia=-" "linha=8 etapa=implementar quem=agente inconsistencia=-" "linha=12 etapa=revisar quem=agente inconsistencia=-"
check CA11 "teto: sai com 0" "0" "$(dispatch run)"
check CA11 "teto: roda exatamente 4 etapas, sem a 5ª" "triagem spec spec implementar" "$(sed 's#/fabrica:\([a-z]*\) 7#\1#' "$tmp/claude.log" | paste -sd ' ')"
check CA11 "teto: publica o comentário teto na issue" "1|<!-- fabrica:dispatcher -->|sim" \
  "$(grep -c '^issue comment 7 --repo dono/projeto --body-file' "$calls")|$(head -n 1 "$tmp/comment.txt")|$(grep -q '^\*\*Motivo:\*\* `teto`' "$tmp/comment.txt" && echo sim)"
check CA11 "teto: o comentário diz o estado e a orientação" "sim sim" \
  "$(grep -q 'linha 12' "$tmp/comment.txt" && echo sim) $(grep -q '/fabrica:avancar 7' "$tmp/comment.txt" && echo sim)"
check CA11 "teto: em-andamento aplicada uma vez" "1" "$(adds)"

setup OPEN agente; states "linha=7 etapa=- quem=usuario inconsistencia=-"; skip_case CA11 "portão inicial"
check CA11 "portão inicial: motivo" "pulo: issue #7 em 7 (portão do usuário)" "$(cat "$tmp/out.txt")"
setup OPEN agente; states "linha=8 etapa=- quem=usuario inconsistencia=spec-aprovada-sem-spec"; skip_case CA11 "inconsistência inicial"
check CA11 "inconsistência: motivo" "pulo: issue #7 com inconsistência spec-aprovada-sem-spec" "$(cat "$tmp/out.txt")"
setup OPEN agente; states "linha=5 etapa=spec quem=agente inconsistencia=-" "linha=- etapa=- quem=usuario inconsistencia=pr-fechado-sem-merge"
check CA11 "inconsistência depois da etapa: para" "0 1 sim" "$(dispatch run) $(claude_runs) $(out_has 'inconsistência')"

# Com o leitor real: issue já triada não é mais pulo, vai para a spec.
setup OPEN agente "$TRI"
check CA11 "leitor real: issue triada roda a spec" "0 /fabrica:spec 7" "$(dispatch run) $(tail -n 1 "$tmp/claude.args")"
setup OPEN agente,acao-externa "$TRI"
echo '[[{"body":"<!-- fabrica:acao etapa=revisar -->\n- [x] a\n- [ ] b","created_at":"2026-11-18T11:00:00Z","html_url":"u"}]]' > "$tmp/comments.json"
skip_case CA11 "leitor real: checklist com item desmarcado"
check CA11 "checklist pendente: lê os comentários pela API" "1" "$(grep -c '^api repos/dono/projeto/issues/7/comments --paginate --slurp' "$calls")"

# CA12: em-andamento recente e esquecida, na issue resolvida.
setup OPEN agente,em-andamento; timeline 7140
skip_case CA12 "1 h 59 min"
check CA12 "unmark depois do pulo não chama gh issue edit" "0 0" "$(dispatch unmark) $(edits)"

setup OPEN agente,em-andamento; timeline 7200
check CA12 "2 h 00 min: sai com 0" "0" "$(dispatch run)"
check CA12 "2 h 00 min: remove e aplica de novo" \
  "issue edit 7 --repo dono/projeto --remove-label em-andamento|issue edit 7 --repo dono/projeto --add-label em-andamento" \
  "$(grep '^issue edit' "$calls" | paste -sd '|')"
check CA12 "2 h 00 min: roda a etapa" "sim" "$(called_claude)"

pr_setup; prview OPEN feat/7-coisa 7
python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); d["labels"].append({"name": "em-andamento"}); json.dump(d, open(sys.argv[1], "w"))' "$tmp/view.json"
timeline 600
skip_case CA12 "evento de PR com em-andamento recente na issue" pr 30

# CA13: freio.
setup OPEN agente; timeline 3600 3000 2500 2000 1500 1000 500 100
check CA13 "8 em até 3.600 s: sai com 0" "0" "$(dispatch run)"
check CA13 "8 em até 3.600 s: não chama o claude nem aplica label" "não 0" "$(called_claude) $(edits)"
check CA13 "freio: comenta na issue com o marcador e o motivo" "1|<!-- fabrica:dispatcher -->|sim" \
  "$(grep -c '^issue comment 7 --repo dono/projeto --body-file' "$calls")|$(head -n 1 "$tmp/comment.txt")|$(grep -q '^\*\*Motivo:\*\* `freio`' "$tmp/comment.txt" && echo sim)"
check CA13 "freio: o número de execuções e a orientação" "sim sim" \
  "$(grep -q '^\*\*Execuções na última hora:\*\* 8$' "$tmp/comment.txt" && echo sim) $(grep -q '/fabrica:avancar 7' "$tmp/comment.txt" && echo sim)"
check CA13 "freio: imprime o pulo" "sim" "$(out_has '^pulo: .*freio')"

setup OPEN agente; timeline 3601 3000 2500 2000 1500 1000 500 100
check CA13 "7 na janela e 1 com 3.601 s: roda a etapa, sem freio" "0 sim 0" "$(dispatch run) $(called_claude) $(comments)"

# SPEC-105: filtro das labels de modelo.
setup OPEN 'agente,bug,modelo:opus,modelo:x;rm -rf ~,modelo:$(id)'
check CA11 "labels: chama a triagem do número da issue" "0 /fabrica:triagem 7" "$(dispatch run) $(tail -n 1 "$tmp/claude.args")"
check CA11 "labels: nenhuma label insegura chega ao comando" "não" \
  "$(grep -qE 'bug|rm -rf|\$\(id\)' "$tmp/claude.args" && echo sim || echo não)"
setup OPEN agente,modelo:opus,modelo:haiku
check CA11 "duas modelo:* seguras saem com 2" "2" "$(dispatch run)"

# Falhas da etapa (SPEC-105).
setup OPEN agente; echo 'não é json' > "$tmp/claude.json"
check CA11 "JSON ilegível sai com 1" "1" "$(dispatch run)"
setup OPEN agente; echo '{"is_error":true,"result":"x"}' > "$tmp/claude.json"
check CA11 "is_error verdadeiro sai com 1" "1" "$(dispatch run)"
setup OPEN agente; echo '{"result":"x"}' > "$tmp/claude.json"
check CA11 "is_error ausente sai com 1" "1" "$(dispatch run)"
setup OPEN agente; echo '{"is_error":true,"subtype":"success","api_error_status":401,"num_turns":1,"result":"texto secreto do result"}' > "$tmp/claude.json"; echo 1 > "$tmp/claude.exit"
dispatch run >/dev/null
check CA14 "falha registra no log o resumo seguro" "1" "$(grep -c 'resumo da saída: subtype=success is_error=True api_error_status=401 num_turns=1' "$tmp/err.txt")"
check CA14 "o resumo do log não traz result nem secret" "0" "$(grep -c 'texto secreto do result\|sk-ant-oat-valor-do-teste' "$tmp/err.txt" "$tmp/out.txt" | awk -F: '{ s += $NF } END { print s }')"

# CA14: comentário de falha.
body() { cat "$tmp/comment.txt" 2>/dev/null; }
reason() { grep -o '^\*\*Motivo:\*\* `[a-z-]*`' "$tmp/comment.txt" 2>/dev/null | sed 's/.*`\(.*\)`/\1/'; }
no_leak() {
  if grep -q 'texto secreto do result\|sk-ant-oat-valor-do-teste\|rm -rf' "$tmp/comment.txt"; then echo vazou; else echo limpo; fi
}

setup OPEN agente
echo '{"is_error":true,"result":"texto secreto do result","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}},{"tool_name":"Write","tool_input":{}},{"tool_name":"Bash","tool_input":{}}]}' > "$tmp/claude.json"
dispatch run >/dev/null
check CA14 "permissao: sai com 0" "0" "$(dispatch fail)"
check CA14 "permissao: comenta na issue por --body-file" "1" "$(grep -c -- '^issue comment 7 --repo dono/projeto --body-file ' "$calls")"
check CA14 "permissao: marcador na primeira linha" "<!-- fabrica:dispatcher -->" "$(body | head -n 1)"
check CA14 "permissao: motivo" "permissao" "$(reason)"
check CA14 "permissao: lista as ferramentas sem repetir" "**Ferramentas negadas:** \`Bash\`, \`Write\`" "$(grep '^\*\*Ferramentas negadas' "$tmp/comment.txt")"
check CA14 "permissao: a etapa que falhou" "**Etapa:** triagem" "$(grep '^\*\*Etapa' "$tmp/comment.txt")"
check CA14 "permissao: orientação com a etapa" "Rode \`/fabrica:triagem 7\` ou \`/fabrica:avancar 7\` na sua máquina, ou repita o gesto." "$(body | tail -n 1)"
check CA14 "permissao: link do run" "**Run:** https://github.com/dono/projeto/actions/runs/4242" "$(grep '^\*\*Run' "$tmp/comment.txt")"
check CA14 "permissao: sem result, argumentos nem secret" "limpo" "$(no_leak)"

setup OPEN agente; states "linha=8 etapa=implementar quem=agente inconsistencia=-"; echo 1 > "$tmp/claude.exit"
dispatch run >/dev/null; dispatch fail >/dev/null
check CA14 "erro: motivo, código e etapa gravada" "erro|**Saída do processo da etapa:** 1|**Etapa:** implementar" \
  "$(reason)|$(grep '^\*\*Saída' "$tmp/comment.txt")|$(grep '^\*\*Etapa' "$tmp/comment.txt")"
check CA14 "erro: sem result nem secret" "limpo" "$(no_leak)"

setup OPEN agente,modelo:opus,modelo:haiku
dispatch run >/dev/null; dispatch fail >/dev/null
check CA14 "labels: motivo" "labels" "$(reason)"

setup OPEN agente
dispatch fail >/dev/null
check CA14 "sem-resultado: motivo e etapa não decidida" "sem-resultado|**Etapa:** não decidida" "$(reason)|$(grep '^\*\*Etapa' "$tmp/comment.txt")"
check CA14 "sem-resultado: sem código de saída" "0" "$(grep -c '^\*\*Saída' "$tmp/comment.txt")"
check CA14 "sem-resultado: orientação sem etapa" "Rode \`/fabrica:avancar 7\` na sua máquina, ou repita o gesto." "$(body | tail -n 1)"

setup OPEN agente
check CA14 "PR que o gh não leu: run sai com 1" "1" "$(dispatch run pr 30)"
dispatch fail pr 30 >/dev/null
check CA14 "sem issue resolvida: comenta no PR por --body-file" "1 0" \
  "$(grep -c '^pr comment 30 --repo dono/projeto --body-file ' "$calls") $(grep -c '^issue comment' "$calls")"
check CA14 "sem issue resolvida: marcador e etapa não decidida" "<!-- fabrica:dispatcher -->|**Etapa:** não decidida" \
  "$(body | head -n 1)|$(grep '^\*\*Etapa' "$tmp/comment.txt")"

# Uso inválido.
check uso "número inválido sai com 1" "1" "$(dispatch run issue 'abc')"
check uso "tipo inválido sai com 1" "1" "$(dispatch run commit 7)"
check uso "subcomando desconhecido sai com 1" "1" "$(dispatch deploy)"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
