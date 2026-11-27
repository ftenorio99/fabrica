#!/usr/bin/env bash
# Testa o scripts/ci-wait.sh (SPEC-136, CA1 a CA9 e CA12), com um gh falso no
# PATH. Não usa o gh da máquina nem a rede.
# Uso: bash scripts/test-ci-wait.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sut="$script_dir/ci-wait.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

unset FABRICA_CI_WAIT_INTERVAL FABRICA_CI_WAIT_SLICE FABRICA_CI_WAIT_NO_CI FABRICA_CI_WAIT_MAX

failures=0 total=0

# result <ok: 0|1> <CA> <descrição>
result() {
  total=$((total + 1))
  if (( $1 == 0 )); then
    printf 'ok      %-5s %s\n' "$2" "$3"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-5s %s\n' "$2" "$3"
    printf '        código: %s\n        saída: %s\n        stderr: %s\n' "${rc-}" "${out-}" "${err-}"
  fi
}

# check <CA> <descrição> <comando...>: ok se o comando sai com 0.
check() {
  local ca=$1 desc=$2
  shift 2
  if "$@"; then result 0 "$ca" "$desc"; else result 1 "$ca" "$desc"; fi
}

# O gh falso grava os argumentos e responde, na chamada n, com saida-<n>.tsv, ou
# falha se houver falha-<n>. Sem arquivo para a vez, repete o último.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_DIR/calls.log"
n=$(wc -l <"$FAKE_DIR/calls.log")
while ((n > 1)) && [[ ! -e "$FAKE_DIR/saida-$n.tsv" && ! -e "$FAKE_DIR/falha-$n" ]]; do
  n=$((n - 1))
done
if [[ -e "$FAKE_DIR/falha-$n" ]]; then
  printf 'gh: Resource not accessible (HTTP 403)\nsegunda linha\n' >&2
  exit 1
fi
cat "$FAKE_DIR/saida-$n.tsv"
EOF
chmod +x "$tmp/bin/gh"

repo=dono/projeto
sha=0123456789abcdef0123456789abcdef01234567
cases=0

# scenario: começa uma sequência de respostas nova.
scenario() {
  cases=$((cases + 1))
  FAKE_DIR="$tmp/caso-$cases"
  mkdir -p "$FAKE_DIR"
  : >"$FAKE_DIR/calls.log"
}

# answer <n> [linha de run...]: resposta da chamada n (sem linhas, nenhum run).
answer() {
  local n=$1
  shift
  : >"$FAKE_DIR/saida-$n.tsv"
  (($# == 0)) || printf '%s\n' "$@" >"$FAKE_DIR/saida-$n.tsv"
}
fail_on() { : >"$FAKE_DIR/falha-$1"; }

# line <nome> <status> <conclusion>
line() { printf '%s\t%s\t%s\thttps://github.com/dono/projeto/actions/runs/%s' "$1" "$2" "$3" "$1"; }
link() { echo "https://github.com/dono/projeto/actions/runs/$1"; }

# ago <segundos>: instante UTC no passado.
ago() { date -u -d "@$(($(date +%s) - $1))" +%Y-%m-%dT%H:%M:%SZ; }

# tick: espera o segundo virar, para as bordas de 1 s não oscilarem.
tick() {
  local s
  s=$(date +%s)
  while [[ $(date +%s) == "$s" ]]; do sleep 0.02; done
}

# run [VAR=valor...] -- <args...>: guarda saída em $out, $err e $rc.
run() {
  local vars=()
  while [[ "$1" != -- ]]; do
    vars+=("$1")
    shift
  done
  shift
  out=$(env "${vars[@]}" FAKE_DIR="$FAKE_DIR" PATH="$tmp/bin:$PATH" bash "$sut" "$@" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}

calls() { wc -l <"$FAKE_DIR/calls.log"; }
count() { grep -cF -- "$1" <<<"$out"; }
last() { tail -n 1 <<<"$out"; }
# ends <código> <resultado>
ends() { [[ $rc == "$1" && "$(last)" == "resultado: $2" ]]; }

fast=(FABRICA_CI_WAIT_INTERVAL=0 FABRICA_CI_WAIT_SLICE=3)
once=(FABRICA_CI_WAIT_SLICE=0)

# --- CA1: verde ---
scenario
answer 1 "$(line a completed success)" "$(line b completed skipped)" "$(line c completed neutral)"
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA1 "success, skipped e neutral: verde, código 0" ends 0 verde
check CA1 "nenhuma linha falhou:" test "$(count 'falhou:')" = 0

# --- CA9: a consulta ---
check CA9 "consulta os runs do head com per_page=100" \
  grep -qF "api repos/$repo/actions/runs?head_sha=$sha&per_page=100 --jq " "$FAKE_DIR/calls.log"
check CA9 "o filtro pede nome, status, conclusion e link" \
  grep -qF '.workflow_runs[] | [.name, .status, .conclusion, .html_url] | @tsv' "$FAKE_DIR/calls.log"

# --- CA2: vermelho ---
scenario
answer 1 "$(line lint completed failure)" "$(line testes completed cancelled)" "$(line docs completed success)"
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA2 "failure e cancelled: vermelho, código 1" ends 1 vermelho
check CA2 "linha do failure com nome, conclusão e link" \
  test "$(count "falhou: lint"$'\t'"failure"$'\t'"$(link lint)")" = 1
check CA2 "linha do cancelled com nome, conclusão e link" \
  test "$(count "falhou: testes"$'\t'"cancelled"$'\t'"$(link testes)")" = 1
check CA2 "só duas linhas falhou:" test "$(count 'falhou:')" = 2

scenario
answer 1 "$(line vazio completed '')" "$(line docs completed success)"
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA2 "conclusion vazia: vermelho" ends 1 vermelho
check CA2 "conclusion vazia: link no lugar certo" \
  test "$(count "falhou: vazio"$'\t\t'"$(link vazio)")" = 1

# --- CA3: espera e imprime só as mudanças ---
scenario
answer 1 "$(line ci in_progress '')"
answer 2 "$(line ci in_progress '')"
answer 3 "$(line ci completed success)"
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA3 "espera o run terminar: verde" ends 0 verde
check CA3 "três consultas" test "$(calls)" = 3
check CA3 "uma linha na primeira consulta" test "$(count "ci"$'\t'"in_progress"$'\t\t'"$(link ci)")" = 1
check CA3 "outra quando o run muda" test "$(count "ci"$'\t'"completed"$'\t'"success"$'\t'"$(link ci)")" = 1
check CA3 "nada além disso" test "$(wc -l <<<"$out")" = 3
check CA3 "a linha de estado começa com o instante UTC" \
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ci'$'\t' <<<"$out"

# --- CA4: sem CI ---
scenario
answer 1
tick
run "${once[@]}" -- "$repo" "$sha" "$(ago 600)"
check CA4 "600 s sem run: sem-ci, código 3" ends 3 sem-ci
check CA4 "avisa que não há run" test "$(count 'nenhum run do head')" = 1

scenario
answer 1
tick
run "${once[@]}" -- "$repo" "$sha" "$(ago 599)"
check CA4 "599 s e fatia esgotada: continua, código 6" ends 6 continua

scenario
answer 1
run FABRICA_CI_WAIT_INTERVAL=1 FABRICA_CI_WAIT_SLICE=2 -- "$repo" "$sha" "$(ago 0)"
check CA4 "sem run antes do prazo: continua ao fim da fatia" ends 6 continua
check CA4 "a linha sem run sai uma vez por chamada" test "$(count 'nenhum run do head')" = 1

# --- CA5: um run que apareceu desliga o sem-ci ---
scenario
answer 1 "$(line ci queued '')"
run "${once[@]}" FABRICA_CI_WAIT_NO_CI=2 -- "$repo" "$sha" "$(ago 10)"
check CA5 "queued depois do prazo do sem CI: continua" ends 6 continua

scenario
answer 1 "$(line ci queued '')"
run "${once[@]}" FABRICA_CI_WAIT_NO_CI=2 FABRICA_CI_WAIT_MAX=3 -- "$repo" "$sha" "$(ago 10)"
check CA5 "queued depois do tempo máximo: tempo-esgotado, não sem-ci" ends 4 tempo-esgotado

scenario
answer 1 "$(line ci queued '')"
answer 2
run "${fast[@]}" FABRICA_CI_WAIT_NO_CI=2 -- "$repo" "$sha" "$(ago 10)"
check CA5 "run apagado numa consulta posterior: a regra do sem CI volta" ends 3 sem-ci

# --- CA6: tempo máximo ---
scenario
answer 1 "$(line ci queued '')"
run -- "$repo" "$sha" "$(ago 3600)"
check CA6 "3600 s com run queued: tempo-esgotado, código 4" ends 4 tempo-esgotado

scenario
answer 1 "$(line ci queued '')"
before=$(date +%s)
run FABRICA_CI_WAIT_MAX=100 FABRICA_CI_WAIT_SLICE=60 FABRICA_CI_WAIT_INTERVAL=60 -- "$repo" "$sha" "$(ago 98)"
elapsed=$(($(date +%s) - before))
check CA6 "chega ao máximo no meio da fatia: código 4" ends 4 tempo-esgotado
check CA6 "sem esperar a fatia inteira (${elapsed} s)" test "$elapsed" -lt 10

# --- CA7: falhas de leitura ---
scenario
fail_on 1
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA7 "5 falhas seguidas: erro-leitura, código 5" ends 5 erro-leitura
check CA7 "uma linha por falha, com a primeira linha do erro" \
  test "$(count 'falha ao ler os runs: gh: Resource not accessible (HTTP 403)')" = 5
check CA7 "só a primeira linha do erro" test "$(count 'segunda linha')" = 0
check CA7 "cinco consultas" test "$(calls)" = 5

scenario
for n in 1 2 3 4; do fail_on "$n"; done
answer 5 "$(line ci completed success)"
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA7 "4 falhas e depois verde: código 0" ends 0 verde

scenario
for n in 1 2 3 4 6 7 8 9; do fail_on "$n"; done
answer 5 "$(line ci queued '')"
answer 10 "$(line ci completed success)"
run "${fast[@]}" -- "$repo" "$sha" "$(ago 0)"
check CA7 "uma consulta certa zera a contagem" ends 0 verde

scenario
fail_on 1
run FABRICA_CI_WAIT_INTERVAL=2 FABRICA_CI_WAIT_SLICE=3 -- "$repo" "$sha" "$(ago 0)"
check CA7 "fatia acaba com menos de 5 falhas: continua" ends 6 continua
check CA7 "consulta também no fim da fatia" test "$(calls)" = 3

scenario
fail_on 1
run "${once[@]}" -- "$repo" "$sha" "$(ago 3600)"
check CA7 "falha no tempo máximo: erro-leitura, sem pedir outra chamada" ends 5 erro-leitura

# --- CA8: uso inválido ---
scenario
answer 1
now="$(ago 0)"
invalid() { # invalid <descrição> [VAR=valor...] -- <args...>
  local desc=$1
  shift
  run "$@"
  check CA8 "$desc: código 2 e uso no stderr" test "$rc|$(grep -c '^uso: ' "$tmp/err")" = "2|1"
}
invalid "argumentos a menos" -- "$repo" "$sha"
invalid "argumentos a mais" -- "$repo" "$sha" "$now" extra
invalid "repositório sem /" -- projeto "$sha" "$now"
invalid "repositório com 3 partes" -- a/b/c "$sha" "$now"
invalid "SHA curto demais" -- "$repo" 012345 "$now"
invalid "SHA com letra fora do hexadecimal" -- "$repo" 012345g "$now"
invalid "desde mal formado" -- "$repo" "$sha" "2026-11-27 10:00:00"
invalid "desde com data impossível" -- "$repo" "$sha" "2026-13-45T10:00:00Z"
invalid "desde no futuro" -- "$repo" "$sha" "$(ago -120)"
for var in INTERVAL SLICE NO_CI MAX; do
  invalid "FABRICA_CI_WAIT_$var não inteira" "FABRICA_CI_WAIT_$var=1.5" -- "$repo" "$sha" "$now"
done
invalid "variável vazia" FABRICA_CI_WAIT_SLICE= -- "$repo" "$sha" "$now"
check CA8 "nenhuma chamada ao gh" test "$(calls)" = 0

# --- CA12: duração ---
check CA12 "a suíte roda em menos de 30 s (${SECONDS} s)" test "$SECONDS" -lt 30

echo
echo "$((total - failures))/$total verificações passaram."
((failures == 0))
