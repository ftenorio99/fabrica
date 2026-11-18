#!/usr/bin/env bash
# Despacho da etapa de agente no GitHub Actions (SPEC-105, ADR 0015).
#
# Uso:
#   dispatch.sh run <nº>     -> relê a issue e roda a triagem se ela estiver em
#                               "Aguardando triagem"; pulos saem com 0 e uma
#                               linha "pulo: <motivo>"
#   dispatch.sh unmark <nº>  -> remove a em-andamento, só se este job a aplicou
#   dispatch.sh fail <nº>    -> comenta a falha na issue com o motivo e o link do run
#
# Variáveis: GITHUB_REPOSITORY (obrigatória, dono/repo), RUNNER_TEMP (pasta do
# estado entre os passos), GITHUB_SERVER_URL e GITHUB_RUN_ID (link do run),
# FABRICA_GH_BIN (padrão gh), FABRICA_NOW (instante atual em segundos, só para
# os testes). O FABRICA_CLAUDE_BIN chega ao stage-model.sh.
# Saída do run: 0 etapa ok ou pulo; 1 uso inválido ou falha da etapa; 2 labels
# modelo:* inconsistentes.
set -uo pipefail
export LC_ALL=C.UTF-8

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gh_bin="${FABRICA_GH_BIN:-gh}"
stage="triagem"
label_running="em-andamento"
max_age=7200 # 2 h, regra de skills/status/estados.md

say() { echo "dispatch: $*" >&2; }
usage() {
  say "uso: dispatch.sh run|unmark|fail <nº>"
  exit 1
}

[[ $# -eq 2 ]] || usage
sub="$1" number="$2"
[[ "$number" =~ ^[1-9][0-9]*$ ]] || { say "o número da issue precisa ser um inteiro positivo."; exit 1; }
repo="${GITHUB_REPOSITORY:-}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { say "GITHUB_REPOSITORY ausente ou inválido."; exit 1; }

state_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fabrica-dispatch"
marked_file="$state_dir/marked"
json_file="$state_dir/stage.json"
exit_file="$state_dir/stage.exit"

# Lê a issue (JSON do gh issue view na entrada) e imprime uma linha
# "<estado>\t<tem agente>\t<tem triagem>\t<tem em-andamento>" seguida de uma
# linha por label modelo:* com nome seguro.
issue_facts() {
  python3 -I -c '
import json, re, sys
d = json.load(sys.stdin)
labels = [l.get("name", "") for l in d.get("labels") or []]
triaged = any((c.get("body") or "").lstrip().startswith("<!-- fabrica:triagem -->") for c in d.get("comments") or [])
print("\t".join([str(d.get("state", "")).upper(), str("agente" in labels), str(triaged), str("em-andamento" in labels)]))
for l in labels:
    if re.fullmatch(r"modelo:[A-Za-z0-9._-]+", l):
        print(l)
'
}

# Idade em segundos do último "labeled em-andamento" da timeline (JSON do
# gh api --slurp na entrada); imprime vazio se não houver evento.
label_age() {
  python3 -I -c '
import json, sys, time
from datetime import datetime
now = float(sys.argv[1]) if sys.argv[1] else time.time()
pages = json.load(sys.stdin)
events = [e for p in pages for e in (p if isinstance(p, list) else [p])]
last = None
for e in events:
    if e.get("event") == "labeled" and (e.get("label") or {}).get("name") == "em-andamento" and e.get("created_at"):
        t = datetime.fromisoformat(e["created_at"].replace("Z", "+00:00")).timestamp()
        last = t if last is None or t > last else last
print("" if last is None else int(now - last))
' "${FABRICA_NOW:-}"
}

# Resumo seguro do JSON do claude para o log do Actions: só campos de controle,
# nunca o texto de result nem argumentos de ferramentas.
stage_summary() {
  python3 -I -c '
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit()
if not isinstance(d, dict):
    sys.exit()
def safe(v):
    return re.sub(r"[^A-Za-z0-9_.:-]", "", str(v))[:40]
keys = ("subtype", "is_error", "api_error_status", "num_turns", "duration_ms")
print(" ".join("%s=%s" % (k, safe(d.get(k))) for k in keys))
' "$json_file" 2>/dev/null
}

cmd_run() {
  rm -rf "$state_dir"
  mkdir -p "$state_dir" || { say "não consegui criar $state_dir."; return 1; }

  local view facts state has_agent triaged running models
  view="$("$gh_bin" issue view "$number" --repo "$repo" --json state,labels,comments)" \
    || { say "o gh não leu a issue #$number."; return 1; }
  facts="$(issue_facts <<< "$view")" || { say "não entendi a resposta do gh issue view."; return 1; }
  IFS=$'\t' read -r state has_agent triaged running <<< "$(head -n 1 <<< "$facts")"
  mapfile -t models < <(tail -n +2 <<< "$facts")

  if [[ "$state" != "OPEN" ]]; then echo "pulo: issue #$number não está aberta"; return 0; fi
  if [[ "$has_agent" != "True" ]]; then echo "pulo: issue #$number sem a label agente"; return 0; fi
  if [[ "$triaged" == "True" ]]; then
    echo "pulo: issue #$number já tem comentário de triagem (não está em Aguardando triagem)"
    return 0
  fi

  if [[ "$running" == "True" ]]; then
    local timeline age
    timeline="$("$gh_bin" api "repos/$repo/issues/$number/timeline" --paginate --slurp)" \
      || { say "o gh não leu a timeline da issue #$number."; return 1; }
    age="$(label_age <<< "$timeline")" || { say "não entendi a timeline da issue #$number."; return 1; }
    if [[ -n "$age" && "$age" -lt "$max_age" ]]; then
      echo "pulo: issue #$number com $label_running recente (outra execução está nela)"
      return 0
    fi
    say "$label_running esquecida na issue #$number; aplicando de novo."
    "$gh_bin" issue edit "$number" --repo "$repo" --remove-label "$label_running" >/dev/null \
      || { say "o gh não removeu a $label_running."; return 1; }
  fi

  "$gh_bin" issue edit "$number" --repo "$repo" --add-label "$label_running" >/dev/null \
    || { say "o gh não aplicou a $label_running."; return 1; }
  : > "$marked_file"

  local rc
  bash "$script_dir/stage-model.sh" run "$stage" "$number" "${models[@]}" > "$json_file"
  rc=$?
  echo "$rc" > "$exit_file"
  [[ $rc -eq 0 || $rc -eq 2 ]] || say "resumo da saída: $(stage_summary)"
  if [[ $rc -eq 2 ]]; then say "duas ou mais labels modelo:* na issue #$number."; return 2; fi
  if [[ $rc -ne 0 ]]; then say "o claude saiu com $rc."; return 1; fi

  local is_error
  is_error="$(python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("ilegivel"); sys.exit()
print("falso" if isinstance(d, dict) and d.get("is_error") is False else "verdadeiro")
' "$json_file")"
  case $is_error in
    falso) echo "etapa $stage da issue #$number concluída"; return 0 ;;
    ilegivel) say "a saída do claude não é um JSON legível."; return 1 ;;
    *) say "o claude terminou com is_error verdadeiro. Resumo: $(stage_summary)"; return 1 ;;
  esac
}

cmd_unmark() {
  if [[ ! -f "$marked_file" ]]; then
    echo "a $label_running não foi aplicada por este job; nada a remover"
    return 0
  fi
  if "$gh_bin" issue edit "$number" --repo "$repo" --remove-label "$label_running" >/dev/null; then
    rm -f "$marked_file"
  else
    say "o gh não removeu a $label_running da issue #$number (ela expira em 2 h)."
  fi
  return 0
}

cmd_fail() {
  local reason code="" denied=""
  if [[ ! -f "$exit_file" ]]; then
    reason="sem-resultado"
  else
    code="$(tr -dc '0-9' < "$exit_file")"
    if [[ "$code" == "2" ]]; then
      reason="labels"
    else
      # Só os nomes das ferramentas negadas, com caracteres seguros, nunca os argumentos.
      denied="$(python3 -I -c '
import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit()
names = []
for x in (d.get("permission_denials") or []) if isinstance(d, dict) else []:
    n = re.sub(r"[^A-Za-z0-9_.:-]", "", str(x.get("tool_name", "")) if isinstance(x, dict) else "")
    if n and n not in names:
        names.append(n)
print(", ".join("`%s`" % n for n in names))
' "$json_file" 2>/dev/null)"
      if [[ -n "$denied" ]]; then reason="permissao"; else reason="erro"; fi
    fi
  fi

  local link="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/${GITHUB_RUN_ID:-}"
  local body
  body="$(mktemp)" || return 1
  {
    echo "<!-- fabrica:dispatcher -->"
    echo "## Falha do dispatcher"
    echo
    echo "**Etapa:** $stage"
    echo "**Motivo:** \`$reason\`"
    [[ -n "$code" ]] && echo "**Saída do processo da etapa:** $code"
    [[ -n "$denied" ]] && echo "**Ferramentas negadas:** $denied"
    echo "**Run:** $link"
    echo
    echo "A issue continua em \"Aguardando triagem\". Reaplique a label \`agente\` ou rode \`/fabrica:$stage $number\` na sua máquina."
  } > "$body"
  "$gh_bin" issue comment "$number" --repo "$repo" --body-file "$body" >/dev/null
  local rc=$?
  rm -f "$body"
  [[ $rc -eq 0 ]] || { say "o gh não publicou o comentário de falha."; return 1; }
  echo "falha publicada na issue #$number (motivo: $reason)"
}

case $sub in
  run) cmd_run ;;
  unmark) cmd_unmark ;;
  fail) cmd_fail ;;
  *) usage ;;
esac
