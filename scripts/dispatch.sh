#!/usr/bin/env bash
# Despacho das etapas de agente no GitHub Actions (SPEC-105, SPEC-107,
# ADR 0015 e 0017).
#
# Uso:
#   dispatch.sh run <issue|pr> <nº>     -> resolve a issue do evento, relê o
#                                          estado e roda as etapas de agente em
#                                          sequência até um portão do usuário ou
#                                          o teto de 4; pulos saem com 0 e uma
#                                          linha "pulo: <motivo>"
#   dispatch.sh unmark <issue|pr> <nº>  -> remove a em-andamento, só se este job a aplicou
#   dispatch.sh fail <issue|pr> <nº>    -> comenta a falha com a etapa, o motivo e o link do run
#
# Variáveis: GITHUB_REPOSITORY (obrigatória, dono/repo), RUNNER_TEMP (pasta do
# estado entre os passos), GITHUB_SERVER_URL e GITHUB_RUN_ID (link do run),
# FABRICA_GH_BIN (padrão gh), FABRICA_NOW (instante atual em segundos) e
# FABRICA_STATE_BIN (troca o issue-state.py), só para os testes. O
# FABRICA_CLAUDE_BIN chega ao stage-model.sh.
# Saída do run: 0 etapas ok, pulo, freio ou teto; 1 uso inválido ou falha da
# etapa; 2 labels modelo:* inconsistentes.
set -uo pipefail
export LC_ALL=C.UTF-8

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gh_bin="${FABRICA_GH_BIN:-gh}"
label_running="em-andamento"
max_age=7200    # 2 h, regra de skills/status/estados.md
brake_window=3600
brake_limit=8   # execuções na última hora que acionam o freio
max_stages=4    # etapas por run, como no /fabrica:avancar

say() { echo "dispatch: $*" >&2; }
# O leitor de estado; o FABRICA_STATE_BIN o troca nos testes.
issue_state() {
  if [[ -n "${FABRICA_STATE_BIN:-}" ]]; then "$FABRICA_STATE_BIN" "$@"
  else python3 "$script_dir/issue-state.py" "$@"
  fi
}
usage() {
  say "uso: dispatch.sh run|unmark|fail <issue|pr> <nº>"
  exit 1
}

[[ $# -eq 3 ]] || usage
sub="$1" kind="$2" number="$3"
[[ "$kind" == issue || "$kind" == pr ]] || usage
[[ "$number" =~ ^[1-9][0-9]*$ ]] || { say "o número do evento precisa ser um inteiro positivo."; exit 1; }
repo="${GITHUB_REPOSITORY:-}"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { say "GITHUB_REPOSITORY ausente ou inválido."; exit 1; }

state_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fabrica-dispatch"
issue_file="$state_dir/issue"
stage_file="$state_dir/stage"
marked_file="$state_dir/marked"
json_file="$state_dir/stage.json"
exit_file="$state_dir/stage.exit"
link="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/${GITHUB_RUN_ID:-}"

# Lê a issue (JSON do gh issue view na entrada) e imprime uma linha
# "<estado>\t<tem agente>\t<tem em-andamento>" seguida de uma linha por label
# modelo:* com nome seguro.
issue_facts() {
  python3 -I -c '
import json, re, sys
d = json.load(sys.stdin)
labels = [l.get("name", "") for l in d.get("labels") or []]
print("\t".join([str(d.get("state", "")).upper(), str("agente" in labels), str("em-andamento" in labels)]))
for l in labels:
    if re.fullmatch(r"modelo:[A-Za-z0-9._-]+", l):
        print(l)
'
}

# Eventos "labeled em-andamento" da timeline (JSON do gh api --slurp na
# entrada): imprime "<idade do último ou vazio>\t<quantos com idade até a janela>".
label_events() {
  python3 -I -c '
import json, sys, time
from datetime import datetime
now = float(sys.argv[1]) if sys.argv[1] else time.time()
window = int(sys.argv[2])
pages = json.load(sys.stdin)
events = [e for p in pages for e in (p if isinstance(p, list) else [p])]
ages = []
for e in events:
    if isinstance(e, dict) and e.get("event") == "labeled" and (e.get("label") or {}).get("name") == "em-andamento" and e.get("created_at"):
        t = datetime.fromisoformat(e["created_at"].replace("Z", "+00:00")).timestamp()
        ages.append(int(now - t))
last = min(ages) if ages else ""
print("%s\t%d" % (last, sum(1 for a in ages if 0 <= a <= window)))
' "${FABRICA_NOW:-}" "$brake_window"
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

# Publica um comentário do dispatcher na issue a partir do corpo na entrada.
comment_issue() {
  local issue="$1" body rc
  body="$(mktemp)" || return 1
  cat > "$body"
  "$gh_bin" issue comment "$issue" --repo "$repo" --body-file "$body" >/dev/null
  rc=$?
  rm -f "$body"
  return $rc
}

# Resolve a issue de um PR (seção 3 da SPEC-107). Imprime o número da issue ou
# uma linha "pulo: ..." e sai com 0; sai com 1 se o gh falhar.
resolve_pr() {
  local view
  view="$("$gh_bin" pr view "$number" --repo "$repo" --json state,headRefName,closingIssuesReferences)" \
    || { say "o gh não leu o PR #$number."; return 1; }
  python3 -I -c '
import json, re, sys
repo, number = sys.argv[1].lower(), sys.argv[2]
d = json.load(sys.stdin)
if str(d.get("state", "")).upper() != "OPEN":
    print("pulo: PR #%s não está aberto" % number); sys.exit()
refs = []
for r in d.get("closingIssuesReferences") or []:
    if not isinstance(r, dict):
        continue
    rr = r.get("repository") or {}
    owner = ((rr.get("owner") or {}).get("login") or "")
    if rr.get("name") and owner and ("%s/%s" % (owner, rr["name"])).lower() != repo:
        continue
    if isinstance(r.get("number"), int) and r["number"] > 0 and r["number"] not in refs:
        refs.append(r["number"])
if len(refs) != 1:
    print("pulo: PR #%s sem uma issue única" % number); sys.exit()
head = str(d.get("headRefName") or "")
if not re.fullmatch(r"[A-Za-z0-9._/-]+", head):
    head = ""
print("%d\t%s" % (refs[0], head))
' "$repo" "$number" <<< "$view" || { say "não entendi a resposta do gh pr view."; return 1; }
}

# Coleta os dados da issue e imprime a linha do issue-state.py, seguida das
# labels modelo:* seguras, uma por linha.
read_state() {
  local issue="$1" view facts branch package acao="" prs="[]"
  view="$("$gh_bin" issue view "$issue" --repo "$repo" --json state,labels,comments)" \
    || { say "o gh não leu a issue #$issue."; return 1; }
  printf '%s' "$view" > "$state_dir/issue.json"
  facts="$(issue_facts <<< "$view")" || { say "não entendi a resposta do gh issue view."; return 1; }

  if python3 -I -c '
import json, sys
sys.exit(0 if "acao-externa" in [l.get("name") for l in json.load(open(sys.argv[1])).get("labels") or []] else 1)
' "$state_dir/issue.json"; then
    "$gh_bin" api "repos/$repo/issues/$issue/comments" --paginate --slurp > "$state_dir/comments.json" \
      || { say "o gh não leu os comentários da issue #$issue."; return 1; }
    acao="$(python3 "$script_dir/acao-status.py" "$state_dir/comments.json")" \
      || { say "o acao-status.py não leu os comentários da issue #$issue."; return 1; }
  fi

  branch="$(issue_state branch "$state_dir/issue.json")" || { say "o issue-state.py não leu a issue #$issue."; return 1; }
  if [[ -n "$branch" ]]; then
    prs="$("$gh_bin" pr list --repo "$repo" --head "$branch" --state all \
      --json number,state,isDraft,mergedAt,statusCheckRollup,reviewDecision,reviews,comments,updatedAt)" \
      || { say "o gh não listou os PRs da branch da issue #$issue."; return 1; }
  fi

  python3 -I -c '
import json, sys
issue = json.load(open(sys.argv[1]))
acao = sys.argv[2] or None
prs = json.loads(sys.argv[3])
json.dump({"issue": issue, "acao": acao, "prs": prs}, open(sys.argv[4], "w"))
' "$state_dir/issue.json" "$acao" "$prs" "$state_dir/package.json" \
    || { say "não montei o pacote de estado da issue #$issue."; return 1; }
  issue_state state "$state_dir/package.json" || { say "o issue-state.py não leu o estado da issue #$issue."; return 1; }
  tail -n +2 <<< "$facts"
}

# field <campo> <linha do issue-state.py>
field() { tr ' ' '\n' <<< "$2" | sed -n "s/^$1=//p"; }

# Roda uma etapa e trata a saída. 0 ok; 1 falha; 2 labels modelo:*.
run_stage() {
  local stage="$1" issue="$2"
  shift 2
  local rc is_error
  echo "$stage" > "$stage_file"
  rm -f "$json_file" "$exit_file"
  bash "$script_dir/stage-model.sh" run "$stage" "$issue" "$@" > "$json_file"
  rc=$?
  echo "$rc" > "$exit_file"
  [[ $rc -eq 0 || $rc -eq 2 ]] || say "resumo da saída: $(stage_summary)"
  if [[ $rc -eq 2 ]]; then say "duas ou mais labels modelo:* na issue #$issue."; return 2; fi
  if [[ $rc -ne 0 ]]; then say "o claude saiu com $rc."; return 1; fi
  is_error="$(python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("ilegivel"); sys.exit()
print("falso" if isinstance(d, dict) and d.get("is_error") is False else "verdadeiro")
' "$json_file")"
  case $is_error in
    falso) echo "etapa $stage da issue #$issue concluída"; return 0 ;;
    ilegivel) say "a saída do claude não é um JSON legível."; return 1 ;;
    *) say "o claude terminou com is_error verdadeiro. Resumo: $(stage_summary)"; return 1 ;;
  esac
}

cmd_run() {
  rm -rf "$state_dir"
  mkdir -p "$state_dir" || { say "não consegui criar $state_dir."; return 1; }

  # 1. Issue do evento.
  local issue="$number" head=""
  if [[ "$kind" == pr ]]; then
    local resolved
    resolved="$(resolve_pr)" || return 1
    if [[ "$resolved" == pulo:* ]]; then echo "$resolved"; return 0; fi
    IFS=$'\t' read -r issue head <<< "$resolved"
  fi

  local view facts state has_agent running
  view="$("$gh_bin" issue view "$issue" --repo "$repo" --json state,labels,comments)" \
    || { say "o gh não leu a issue #$issue."; return 1; }
  facts="$(issue_facts <<< "$view")" || { say "não entendi a resposta do gh issue view."; return 1; }
  IFS=$'\t' read -r state has_agent running <<< "$(head -n 1 <<< "$facts")"

  if [[ "$kind" == pr ]]; then
    local branch
    printf '%s' "$view" > "$state_dir/issue.json"
    branch="$(issue_state branch "$state_dir/issue.json")" || { say "o issue-state.py não leu a issue #$issue."; return 1; }
    if [[ -z "$branch" || "$branch" != "$head" ]]; then
      echo "pulo: PR #$number não é da branch da issue #$issue"
      return 0
    fi
  fi
  if [[ "$state" != "OPEN" ]]; then echo "pulo: issue #$issue não está aberta"; return 0; fi
  if [[ "$has_agent" != "True" ]]; then echo "pulo: issue #$issue sem a label agente"; return 0; fi
  echo "$issue" > "$issue_file"

  # 2. Freio de cascata e 3. em-andamento, pela timeline.
  local timeline events age recent
  timeline="$("$gh_bin" api "repos/$repo/issues/$issue/timeline" --paginate --slurp)" \
    || { say "o gh não leu a timeline da issue #$issue."; return 1; }
  events="$(label_events <<< "$timeline")" || { say "não entendi a timeline da issue #$issue."; return 1; }
  IFS=$'\t' read -r age recent <<< "$events"
  if [[ "$recent" -ge "$brake_limit" ]]; then
    comment_issue "$issue" <<EOF || { say "o gh não publicou o comentário do freio."; return 1; }
<!-- fabrica:dispatcher -->
## Freio do dispatcher

**Motivo:** \`freio\`
**Execuções na última hora:** $recent
**Run:** $link

O dispatcher já rodou $recent vezes nesta issue na última hora, o que passa do ritmo dos seus gestos e pode ser uma cascata de eventos. Ele não roda mais nada nela por enquanto. Confira os comentários da issue e, se estiver tudo certo, rode \`/fabrica:avancar $issue\` na sua máquina.
EOF
    echo "pulo: issue #$issue com $recent execuções na última hora (freio)"
    return 0
  fi
  if [[ "$running" == "True" ]]; then
    if [[ -n "$age" && "$age" -lt "$max_age" ]]; then
      echo "pulo: issue #$issue com $label_running recente (outra execução está nela)"
      return 0
    fi
    say "$label_running esquecida na issue #$issue; aplicando de novo."
    "$gh_bin" issue edit "$issue" --repo "$repo" --remove-label "$label_running" >/dev/null \
      || { say "o gh não removeu a $label_running."; return 1; }
  fi

  # 4. Estado inicial.
  local out line lin stage who inc models
  out="$(read_state "$issue")" || return 1
  line="$(head -n 1 <<< "$out")"
  lin="$(field linha "$line")" stage="$(field etapa "$line")" who="$(field quem "$line")" inc="$(field inconsistencia "$line")"
  if [[ "$inc" != "-" ]]; then echo "pulo: issue #$issue com inconsistência $inc"; return 0; fi
  if [[ "$who" != "agente" ]]; then echo "pulo: issue #$issue em $lin (portão do usuário)"; return 0; fi

  # 5. Marca uma vez, antes da primeira etapa.
  "$gh_bin" issue edit "$issue" --repo "$repo" --add-label "$label_running" >/dev/null \
    || { say "o gh não aplicou a $label_running."; return 1; }
  : > "$marked_file"

  # 6. Laço.
  local count=0 rc before
  while :; do
    case $stage in
      triagem|spec|implementar|revisar) ;;
      *) say "etapa desconhecida '$stage' no estado $lin da issue #$issue."; return 1 ;;
    esac
    mapfile -t models < <(tail -n +2 <<< "$out")
    count=$((count + 1))
    before="$lin"
    run_stage "$stage" "$issue" "${models[@]}"
    rc=$?
    [[ $rc -eq 0 ]] || return $rc

    out="$(read_state "$issue")" || return 1
    line="$(head -n 1 <<< "$out")"
    lin="$(field linha "$line")" stage="$(field etapa "$line")" who="$(field quem "$line")" inc="$(field inconsistencia "$line")"
    if [[ "$inc" != "-" ]]; then echo "parou: issue #$issue com inconsistência $inc"; return 0; fi
    if [[ "$who" != "agente" ]]; then echo "parou: issue #$issue em $lin (portão do usuário)"; return 0; fi
    if [[ "$lin" == "$before" ]]; then echo "parou: issue #$issue continua em $lin (sem avanço)"; return 0; fi
    if [[ $count -ge $max_stages ]]; then
      comment_issue "$issue" <<EOF || { say "o gh não publicou o comentário do teto."; return 1; }
<!-- fabrica:dispatcher -->
## Teto de etapas do dispatcher

**Motivo:** \`teto\`
**Estado:** linha $lin de estados.md, etapa seguinte \`$stage\`
**Run:** $link

O dispatcher rodou $max_stages etapas nesta issue e parou antes de começar outra. Para seguir, rode \`/fabrica:avancar $issue\` na sua máquina ou faça um novo gesto na issue.
EOF
      echo "parou: issue #$issue no teto de $max_stages etapas, em $lin"
      return 0
    fi
  done
}

# Issue resolvida por este job; vazio num evento de PR sem issue resolvida.
resolved_issue() {
  if [[ -f "$issue_file" ]]; then tr -dc '0-9' < "$issue_file"
  elif [[ "$kind" == issue ]]; then echo "$number"
  fi
}

cmd_unmark() {
  if [[ ! -f "$marked_file" ]]; then
    echo "a $label_running não foi aplicada por este job; nada a remover"
    return 0
  fi
  local issue
  issue="$(resolved_issue)"
  if [[ -n "$issue" ]] && "$gh_bin" issue edit "$issue" --repo "$repo" --remove-label "$label_running" >/dev/null; then
    rm -f "$marked_file"
  else
    say "o gh não removeu a $label_running da issue #$issue (ela expira em 2 h)."
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

  local stage="não decidida" issue guide
  [[ -f "$stage_file" ]] && stage="$(tr -dc 'a-z' < "$stage_file")"
  [[ -n "$stage" ]] || stage="não decidida"
  issue="$(resolved_issue)"
  if [[ -z "$issue" ]]; then
    guide="O dispatcher não chegou a decidir a issue deste PR. Veja a causa no log do run e repita o gesto."
  elif [[ "$stage" == "não decidida" ]]; then
    guide="Rode \`/fabrica:avancar $issue\` na sua máquina, ou repita o gesto."
  else
    guide="Rode \`/fabrica:$stage $issue\` ou \`/fabrica:avancar $issue\` na sua máquina, ou repita o gesto."
  fi

  local body rc
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
    echo "$guide"
  } > "$body"
  if [[ -n "$issue" ]]; then
    "$gh_bin" issue comment "$issue" --repo "$repo" --body-file "$body" >/dev/null
  else
    "$gh_bin" pr comment "$number" --repo "$repo" --body-file "$body" >/dev/null
  fi
  rc=$?
  rm -f "$body"
  [[ $rc -eq 0 ]] || { say "o gh não publicou o comentário de falha."; return 1; }
  if [[ -n "$issue" ]]; then
    echo "falha publicada na issue #$issue (motivo: $reason)"
  else
    echo "falha publicada no PR #$number (motivo: $reason)"
  fi
}

case $sub in
  run) cmd_run ;;
  unmark) cmd_unmark ;;
  fail) cmd_fail ;;
  *) usage ;;
esac
