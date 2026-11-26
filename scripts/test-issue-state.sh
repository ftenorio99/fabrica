#!/usr/bin/env bash
# Testa scripts/issue-state.py (SPEC-107, CA6 a CA9; #205) com pacotes JSON fixos.
# Uso: bash scripts/test-issue-state.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/issue-state.py"

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

# pkg <labels> <acao|-> <prs JSON> [<segundos>|<corpo> ...]: monta o pacote em
# $tmp/p.json. Cada comentário é "<segundos depois de 10:00:00>|<corpo>".
pkg() {
  python3 -I -c '
import json, sys
from datetime import datetime, timedelta, timezone
base = datetime(2026, 11, 19, 10, 0, 0, tzinfo=timezone.utc)
labels, acao, prs = sys.argv[1:4]
comments = []
for raw in sys.argv[4:]:
    secs, body = raw.split("|", 1)
    at = (base + timedelta(seconds=int(secs))).strftime("%Y-%m-%dT%H:%M:%SZ")
    comments.append({"author": {"login": "dono"}, "body": body, "createdAt": at})
issue = {"state": "OPEN", "labels": [{"name": l} for l in labels.split(",") if l], "comments": comments}
print(json.dumps({"issue": issue, "acao": None if acao == "-" else acao, "prs": json.loads(prs)}))
' "$@" > "$tmp/p.json"
}
state() { python3 "$script" state "$tmp/p.json" 2>&1; }
# só <campo> do resultado
field() { state | tr ' ' '\n' | sed -n "s/^$1=//p"; }

TRI='<!-- fabrica:triagem -->
## Triagem
**Atalho:** não — mexe em mais de um módulo'
TRI_SHORT='<!-- fabrica:triagem -->
## Triagem
**Atalho:** sim — uma linha de doc

### Spec curta
**Branch:** `docs/7-ajuste`'
SPEC='<!-- fabrica:spec -->
## Spec pronta para aprovação
**Branch:** `feat/7-coisa`
<!-- fabrica:custo etapa=spec inicio=2026-11-19T10:00:00Z fim=2026-11-19T10:05:00Z tokens=nao-medido -->'
USER='Pode seguir com a opção 2.'
H="2026-11-19T10"
# pr <estado> <draft> <rollup JSON> [reviewDecision] [reviews JSON] [comments JSON] [mergedAt]
pr() {
  printf '[{"number":30,"state":"%s","isDraft":%s,"mergedAt":%s,"statusCheckRollup":%s,"reviewDecision":"%s","reviews":%s,"comments":%s,"updatedAt":"%s:30:00Z"}]' \
    "$1" "$2" "${7:-null}" "$3" "${4:-}" "${5:-[]}" "${6:-[]}" "$H"
}
OK='[{"conclusion":"SUCCESS","status":"COMPLETED"}]'

issue_only() { python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1]))["issue"]))' "$tmp/p.json" > "$tmp/i.json"; }
branch() { issue_only; python3 "$script" branch "$tmp/i.json"; }

# --- CA6: um pacote por estado ---
pkg agente - '[]'
check CA6 "2: sem marcador de triagem" "linha=2 etapa=triagem quem=agente inconsistencia=-" "$(state)"

pkg agente,escalonado 'estado=concluida etapa=revisar marcados=2 total=2 url=-' '[]' "0|$TRI"
check CA6 "1: escalonado tem precedência sobre a ação concluída" "linha=1 etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,acao-externa 'estado=pendente etapa=implementar marcados=1 total=2 url=-' '[]' "0|$TRI"
check CA6 "1a: ação pendente" "linha=1a etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,acao-externa,spec-aprovada 'estado=concluida etapa=revisar marcados=2 total=2 url=-' "$(pr OPEN false "$OK")" "0|$TRI" "60|$SPEC"
check CA6 "1b: ação concluída roda a etapa do marcador" "linha=1b etapa=revisar quem=agente inconsistencia=-" "$(state)"

pkg agente,precisa-info - '[]' "0|$TRI"
check CA6 "3: perguntas sem resposta" "linha=3 etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,precisa-info - '[]' "0|$TRI" "60|$USER"
check CA6 "4: resposta à triagem" "linha=4 etapa=triagem quem=agente inconsistencia=-" "$(state)"

pkg agente - '[]' "0|$TRI"
check CA6 "5: triada" "linha=5 etapa=spec quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-pronta - '[]' "0|$TRI" "60|$SPEC" "120|$USER"
check CA6 "6: ajuste pedido com spec" "linha=6 etapa=spec quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-pronta - '[]' "0|$TRI_SHORT" "60|$USER"
check CA6 "6: ajuste pedido no atalho" "linha=6 etapa=spec quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-pronta - '[]' "0|$TRI" "60|$SPEC"
check CA6 "7: spec para aprovar" "linha=7 etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,spec-pronta - '[]' "0|$TRI_SHORT"
check CA6 "7: spec curta para aprovar" "linha=7 etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,spec-pronta,spec-aprovada - '[]' "0|$TRI" "60|$SPEC"
check CA6 "8: aprovada sem PR" "linha=8 etapa=implementar quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-pronta,spec-aprovada - '[]' "0|$TRI_SHORT"
check CA6 "8: aprovada no atalho, sem PR" "linha=8 etapa=implementar quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-aprovada - "$(pr OPEN true "$OK")" "0|$TRI" "60|$SPEC"
check CA6 "9: PR em rascunho" "linha=9 etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,spec-aprovada - "$(pr OPEN false '[{"conclusion":"FAILURE"}]')" "0|$TRI" "60|$SPEC"
check CA6 "10: CI falhando" "linha=10 etapa=revisar quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-aprovada,pronto-revisao - "$(pr OPEN false "$OK" '' '[]' "[{\"body\":\"Troque o nome\",\"createdAt\":\"$H:40:00Z\"}]")" "0|$TRI" "60|$SPEC"
check CA6 "11: pedido novo no PR" "linha=11 etapa=revisar quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-aprovada,pronto-revisao - "$(pr OPEN false "$OK" CHANGES_REQUESTED)" "0|$TRI" "60|$SPEC"
check CA6 "11: CHANGES_REQUESTED" "linha=11 etapa=revisar quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-aprovada - "$(pr OPEN false "$OK")" "0|$TRI" "60|$SPEC"
check CA6 "12: PR aberto sem pronto-revisao" "linha=12 etapa=revisar quem=agente inconsistencia=-" "$(state)"

pkg agente,spec-aprovada,pronto-revisao - "$(pr OPEN false "$OK")" "0|$TRI" "60|$SPEC"
check CA6 "13: PR para revisar" "linha=13 etapa=- quem=usuario inconsistencia=-" "$(state)"

pkg agente,precisa-info,spec-aprovada - "$(pr OPEN false '[{"conclusion":"FAILURE"}]')" "0|$TRI" "60|$SPEC"
check CA6 "precedência: precisa-info (3) antes do CI vermelho (10)" "3" "$(field linha)"

# --- CA7: classificação de comentários ---
for ignored in 'licao gatilho=rodadas' 'dispatcher' 'backlog par-recusado item=3'; do
  pkg agente,precisa-info - '[]' "0|$TRI" "60|<!-- fabrica:$ignored -->
texto"
  check CA7 "ignorado não é resposta nova: fabrica:${ignored%% *}" "3" "$(field linha)"
done
pkg agente,spec-pronta - '[]' "0|$TRI" "60|$SPEC"
check CA7 "linha de custo no fim não vira resposta nova" "7" "$(field linha)"
pkg agente,precisa-info - '[]' "0|$TRI" "60|   
  $SPEC"
check CA7 "marcador com espaços antes não conta como do agente (é do usuário, como no filtro)" "linha=4 etapa=triagem" "$(state | cut -d' ' -f1,2)"
pkg agente,precisa-info - '[]' "0|$TRI" "0|$USER"
check CA7 "usuário no mesmo segundo do marcador não é resposta nova" "3" "$(field linha)"
pkg agente,precisa-info - '[]' "0|$TRI" "1|$USER"
check CA7 "usuário um segundo depois é resposta nova" "4" "$(field linha)"
pkg agente,precisa-info - '[]' "0|$TRI" "60|$SPEC" "120|$USER"
check CA7 "linha 4: último marcador é spec" "linha=4 etapa=spec" "$(state | cut -d' ' -f1,2)"
pkg agente,precisa-info - '[]' "0|$SPEC" "60|$TRI" "120|$USER"
check CA7 "linha 4: último marcador é triagem" "linha=4 etapa=triagem" "$(state | cut -d' ' -f1,2)"
pkg agente,precisa-info - '[]' "0|$TRI" "60|<!-- fabrica:specx -->
não é marcador"
check CA7 "marcador sem espaço nem --> depois da etapa é do usuário" "4" "$(field linha)"

# --- #205: marcadores sem diferenciar maiúsculas ---
# kind_of <corpo>: tipo e etapa que o leitor dá ao comentário.
kind_of() {
  python3 -I -c '
import runpy, sys
print(*runpy.run_path(sys.argv[1])["kind"](sys.argv[2]))
' "$script" "$1" 2>&1
}
for stage in triagem spec implementar revisar backlog lancamento acao; do
  check '#205' "marcador em maiúsculas vale como o em minúsculas: $stage" "agente $stage" \
    "$(kind_of "<!-- FABRICA:${stage^^} -->")"
done
check '#205' "marcador de ação com atributo e caixa mista" "agente acao" "$(kind_of '<!-- Fabrica:Acao etapa=revisar -->')"
for ignored in 'LICAO gatilho=rodadas' 'Dispatcher' 'BACKLOG PAR-RECUSADO item=3'; do
  check '#205' "ignorado em qualquer caixa: $ignored" "ignorado None" "$(kind_of "<!-- FABRICA:$ignored -->")"
  pkg agente,precisa-info - '[]' "0|$TRI" "60|<!-- FABRICA:$ignored -->
texto"
  check '#205' "ignorado em qualquer caixa não é resposta nova: $ignored" "3" "$(field linha)"
  pkg agente,precisa-info - '[]' "0|$TRI" "30|$USER" "60|<!-- FABRICA:$ignored -->"
  check '#205' "ignorado em qualquer caixa não é comentário do agente: $ignored" "linha=4 etapa=triagem" \
    "$(state | cut -d' ' -f1,2)"
done
pkg agente,spec-pronta - '[]' "0|$TRI" "60|${SPEC/fabrica:spec/FABRICA:SPEC}"
check '#205' "spec em maiúsculas não é resposta do usuário" "7" "$(field linha)"
check '#205' "spec em maiúsculas dá a branch da issue" "feat/7-coisa" "$(branch)"
pkg agente,precisa-info - '[]' "0|$TRI" "60|<!-- fabrica:Spec -->" "120|$USER"
check '#205' "etapa capturada sai em minúsculas" "linha=4 etapa=spec" "$(state | cut -d' ' -f1,2)"
check '#205' "espaços antes do marcador em maiúsculas: do usuário" "usuario None" "$(kind_of '  <!-- FABRICA:spec -->')"
check '#205' "letra fora do ASCII não casa com o marcador" "usuario None" "$(kind_of '<!-- fabrica:ſpec -->')"

# --- CA8: regras do PR ---
REV="<!-- fabrica:revisar -->\\n**Pedidos lidos até:** $H:40:00Z\\nPR pronto"
REV_OLD="<!-- fabrica:revisar -->\\nPR pronto"
c() { printf '{"body":"%s","createdAt":"%s"}' "$1" "$2"; }
base_labels=agente,spec-aprovada,pronto-revisao
pkg $base_labels - "$(pr OPEN false "$OK" '' '[]' "[$(c "$REV" "$H:35:00Z"),$(c 'Ajuste' "$H:40:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "comentário no instante da referência não é pedido novo" "13" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' '[]' "[$(c "$REV" "$H:35:00Z"),$(c 'Ajuste' "$H:40:01Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "um segundo depois da referência é pedido novo" "11" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' '[]' "[$(c 'Ajuste' "$H:35:00Z"),$(c "$REV_OLD" "$H:35:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "sem a linha, a referência é a data do comentário revisar (mesmo instante)" "13" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' '[]' "[$(c "$REV_OLD" "$H:35:00Z"),$(c 'Ajuste' "$H:35:01Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "sem a linha, um segundo depois do revisar é pedido novo" "11" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' '[]' "[$(c 'Ajuste antigo' "$H:01:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "sem comentário revisar, todo comentário do usuário conta" "11" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' '[]' "[$(c '<!-- fabrica:implementar -->\nPR aberto' "$H:01:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "comentário do agente no PR não é pedido" "13" "$(field linha)"
rv() { printf '[{"state":"%s","body":"%s","submittedAt":"%s:50:00Z"}]' "$1" "$2" "$H"; }
pkg $base_labels - "$(pr OPEN false "$OK" '' "$(rv APPROVED '')" "[$(c "$REV" "$H:35:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "APPROVED de corpo vazio não conta" "13" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' "$(rv APPROVED 'Só troque o título')" "[$(c "$REV" "$H:35:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "APPROVED com corpo conta" "11" "$(field linha)"
pkg $base_labels - "$(pr OPEN false "$OK" '' "$(rv COMMENTED '')" "[$(c "$REV" "$H:35:00Z")]")" "0|$TRI" "60|$SPEC"
check CA8 "COMMENTED de corpo vazio conta (comentário em linha)" "11" "$(field linha)"
pkg $base_labels - "$(pr OPEN false '[{"conclusion":"TIMED_OUT"}]')" "0|$TRI" "60|$SPEC"
check CA8 "CI com TIMED_OUT é linha 10" "10" "$(field linha)"
pkg $base_labels - "$(pr OPEN false '[{"state":"ERROR"}]')" "0|$TRI" "60|$SPEC"
check CA8 "status com ERROR é linha 10" "10" "$(field linha)"
pkg $base_labels - "$(pr OPEN false '[{"conclusion":"SUCCESS"},{"status":"IN_PROGRESS","conclusion":""},{"state":"PENDING"}]')" "0|$TRI" "60|$SPEC"
check CA8 "item pendente não é falha" "13" "$(field linha)"
# SPEC-107, CA29: sem o campo statusCheckRollup (o job não o pede), a linha 10 não vale.
no_field='[{"number":30,"state":"OPEN","isDraft":false,"mergedAt":null,"reviewDecision":"","reviews":[],"comments":[],"updatedAt":"2026-11-19T10:00:00Z"}]'
pkg agente,spec-aprovada - "$no_field" "0|$TRI" "60|$SPEC"
check CA29 "sem o campo de CI, PR sem pronto-revisao vai à linha 12" "12" "$(field linha)"
pkg agente,spec-aprovada,pronto-revisao - "$no_field" "0|$TRI" "60|$SPEC"
check CA29 "sem o campo de CI, PR com pronto-revisao vai à linha 13" "13" "$(field linha)"
two_prs='[{"number":20,"state":"CLOSED","isDraft":false,"mergedAt":null,"statusCheckRollup":[],"reviewDecision":"","reviews":[],"comments":[],"updatedAt":"2026-11-19T12:00:00Z"},{"number":21,"state":"OPEN","isDraft":false,"mergedAt":null,"statusCheckRollup":[],"reviewDecision":"","reviews":[],"comments":[],"updatedAt":"2026-11-19T11:00:00Z"}]'
pkg agente,spec-aprovada - "$two_prs" "0|$TRI" "60|$SPEC"
check CA8 "entre um PR fechado e um aberto vale o aberto" "linha=12 etapa=revisar quem=agente inconsistencia=-" "$(state)"

# --- CA9: inconsistências e branch ---
pkg agente,spec-aprovada - '[]' "0|$TRI"
check CA9 "spec-aprovada-sem-spec" "spec-aprovada-sem-spec" "$(field inconsistencia)"
pkg agente,spec-pronta,pronto-revisao - '[]' "0|$TRI" "60|$SPEC"
check CA9 "pronto-revisao-sem-pr" "pronto-revisao-sem-pr" "$(field inconsistencia)"
pkg agente,acao-externa 'estado=sem-comentario etapa=- marcados=0 total=0 url=-' '[]' "0|$TRI"
check CA9 "acao-sem-comentario" "acao-sem-comentario" "$(field inconsistencia)"
pkg agente,acao-externa - '[]' "0|$TRI"
check CA9 "acao-externa sem a linha do acao-status é acao-sem-comentario" "acao-sem-comentario" "$(field inconsistencia)"
pkg agente,acao-externa 'estado=sem-itens etapa=implementar marcados=0 total=0 url=-' '[]' "0|$TRI"
check CA9 "acao-sem-itens" "acao-sem-itens" "$(field inconsistencia)"
pkg agente,acao-externa 'estado=etapa-invalida etapa=lancamento marcados=1 total=1 url=-' '[]' "0|$TRI"
check CA9 "acao-etapa-invalida" "acao-etapa-invalida" "$(field inconsistencia)"
pkg agente,spec-aprovada - "$(pr CLOSED false "$OK")" "0|$TRI" "60|$SPEC"
check CA9 "pr-fechado-sem-merge, sem etapa" "etapa=- quem=usuario inconsistencia=pr-fechado-sem-merge" "$(state | cut -d' ' -f2-)"
pkg agente,spec-aprovada - "$(pr MERGED false "$OK" '' '[]' '[]' "\"$H:50:00Z\"")" "0|$TRI" "60|$SPEC"
check CA9 "PR mergeado com a issue aberta não é inconsistência nem etapa" "linha=- etapa=- quem=usuario inconsistencia=-" "$(state)"

SPEC2='<!-- fabrica:spec -->
**Branch:** `feat/7-coisa-v2`'
pkg agente - '[]' "0|$TRI" "60|$SPEC" "120|$SPEC2"
check CA9 "branch do comentário de spec mais recente" "feat/7-coisa-v2" "$(branch)"
pkg agente - '[]' "0|$TRI_SHORT"
check CA9 "branch do atalho sem comentário de spec" "docs/7-ajuste" "$(branch)"
pkg agente - '[]' "0|$TRI_SHORT" "60|$SPEC"
check CA9 "comentário de spec vale sobre o atalho" "feat/7-coisa" "$(branch)"
pkg agente - '[]' "0|$TRI"
check CA9 "triada sem atalho e sem spec: nada" "" "$(branch)"
pkg agente - '[]' "0|$TRI_SHORT" "60|$TRI"
check CA9 "atalho só vale no comentário de triagem mais recente" "" "$(branch)"
pkg agente - '[]' "0|<!-- fabrica:spec -->
**Branch:** \`feat/7;rm -rf ~\`"
check CA9 "branch com caractere inseguro: nada" "" "$(branch)"

# Entrada inválida.
echo 'não é json' > "$tmp/ruim.json"
python3 "$script" state "$tmp/ruim.json" >/dev/null 2>&1
check uso "JSON inválido sai com 2" "2" "$?"
python3 "$script" state "$tmp/ausente.json" >/dev/null 2>&1
check uso "arquivo ausente sai com 2" "2" "$?"
python3 "$script" estado "$tmp/p.json" >/dev/null 2>&1
check uso "subcomando desconhecido sai com 2" "2" "$?"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
