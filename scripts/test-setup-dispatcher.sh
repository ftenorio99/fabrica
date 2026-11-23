#!/usr/bin/env bash
# Testa o setup-dispatcher.sh (SPEC-108, CA1 a CA5) em repositórios git
# temporários.
# Uso: bash scripts/test-setup-dispatcher.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$script_dir/setup-dispatcher.sh"
model="$script_dir/../templates/workflows/agente.yml"

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

# new_repo <nome>: repositório git com um commit; imprime a pasta.
new_repo() {
  local r="$tmp/$1"
  git init -q -b teste "$r"
  echo "# teste" > "$r/README.md"
  git -C "$r" add README.md
  git -C "$r" -c user.name=teste -c user.email=teste@exemplo.com commit -q -m inicial
  echo "$r"
}

# run <pasta> <args...>: roda o script na pasta; stdout e stderr separados
# em $out e $err, código em $rc.
run() {
  local d="$1"; shift
  out="$(cd "$d" && bash "$setup" "$@" 2>"$tmp/err")"; rc=$?
  err="$(cat "$tmp/err")"
}

# snapshot <pasta>: estado da cópia de trabalho e do HEAD.
snapshot() { (cd "$1" && git status --porcelain --untracked-files=all && git rev-parse HEAD && find . -path ./.git -prune -o -type f -print | sort); }

wf=".github/workflows/agente.yml"

# CA1: ausente, ok e desatualizado, sem gravar nada.
r="$(new_repo ca1)"
before="$(snapshot "$r")"
run "$r" --check
check CA1 "sem o workflow imprime ausente" "ausente 0" "$out $rc"
check CA1 "o ausente não grava nada" "$before" "$(snapshot "$r")"

mkdir -p "$r/.github/workflows" && cp "$model" "$r/$wf"
before="$(snapshot "$r")"
run "$r" --check
check CA1 "igual ao modelo imprime ok" "ok 0" "$out $rc"
check CA1 "o ok não imprime diferença" "" "$err"
check CA1 "o ok não grava nada" "$before" "$(snapshot "$r")"

(cd "$r/.github/workflows" && sed -i '3s/.*/# linha trocada/' agente.yml)
before="$(snapshot "$r")"
run "$r" --check
check CA1 "uma linha diferente imprime desatualizado" "desatualizado 0" "$out $rc"
check CA1 "o desatualizado não grava nada" "$before" "$(snapshot "$r")"

cp "$model" "$r/$wf"
printf '%s' "$(cat "$model")" > "$r/$wf"
run "$r" --check
check CA1 "sem a quebra de linha final imprime desatualizado" "desatualizado" "$out"

cp "$model" "$r/$wf" && echo >> "$r/$wf"
run "$r" --check
check CA1 "com uma linha em branco a mais imprime desatualizado" "desatualizado" "$out"

mkdir -p "$r/sub/pasta"
cp "$model" "$r/$wf"
run "$r/sub/pasta" --check
check CA1 "numa subpasta, acha o arquivo na raiz do repositório" "ok" "$out"

# CA2: resumo da diferença em stderr.
r="$(new_repo ca2)"
mkdir -p "$r/.github/workflows"
cp "$model" "$r/$wf"
(cd "$r/.github/workflows" && sed -i '3s/.*/# linha trocada/' agente.yml && echo "# a mais 1" >> agente.yml && echo "# a mais 2" >> agente.yml)
run "$r" --check
check CA2 "uma linha trocada e duas a mais: +1 -3" "diferença: +1 -3 linhas" "$err"
cp "$model" "$r/$wf"
sed -i '1,2d' "$r/$wf"
run "$r" --check
check CA2 "duas linhas a menos: +2 -0" "diferença: +2 -0 linhas" "$err"
check CA2 "as contagens batem com o diff" "$(diff "$r/$wf" "$model" | grep -c '^>') $(diff "$r/$wf" "$model" | grep -c '^<')" \
  "$(sed -n 's/^diferença: +\([0-9]*\) -\([0-9]*\) linhas$/\1 \2/p' <<<"$err")"

# CA3: --apply cria a pasta e grava igual ao modelo; substitui o desatualizado.
r="$(new_repo ca3)"
run "$r" --apply
check CA3 "--apply sai com 0 e diz o que gravou" "0 instalado $wf" "$rc $out"
check CA3 "o arquivo gravado é igual ao modelo" "igual" "$(cmp -s "$model" "$r/$wf" && echo igual || echo diferente)"
run "$r" --check
check CA3 "depois do --apply, o --check imprime ok" "ok" "$out"
echo "# edição local" >> "$r/$wf"
run "$r" --check
check CA3 "a edição local aparece como desatualizado" "desatualizado" "$out"
run "$r" --apply
check CA3 "--apply substitui o desatualizado" "0 igual" "$rc $(cmp -s "$model" "$r/$wf" && echo igual || echo diferente)"
check CA3 "não sobra arquivo temporário" "agente.yml" "$(ls -A "$r/.github/workflows")"

# CA4: erros saem com 1, sem gravar nada.
nogit="$tmp/sem-git"; mkdir -p "$nogit"
run "$nogit" --apply
check CA4 "fora de um repositório git sai com 1" "1" "$rc"
check CA4 "fora de um repositório git, a mensagem vai para stderr" "True" "$([[ "$err" == *"repositório git"* ]] && echo True || echo False)"
check CA4 "fora de um repositório git não grava nada" "" "$(ls -A "$nogit")"

r="$(new_repo ca4)"
before="$(snapshot "$r")"
run "$r" --force
check CA4 "opção desconhecida sai com 1 e mensagem" "1 True" "$rc $([[ -n "$err" ]] && echo True || echo False)"
run "$r"
check CA4 "sem opção sai com 1 e mensagem" "1 True" "$rc $([[ -n "$err" ]] && echo True || echo False)"
run "$r" --check --apply
check CA4 "duas opções saem com 1" "1" "$rc"
check CA4 "os erros de uso não gravam nada" "$before" "$(snapshot "$r")"

fake="$tmp/plugin-sem-modelo"
mkdir -p "$fake/scripts"
cp "$setup" "$fake/scripts/"
out="$(cd "$r" && bash "$fake/scripts/setup-dispatcher.sh" --apply 2>"$tmp/err")"; rc=$?
check CA4 "sem o modelo do plugin, o --apply sai com 1 e mensagem" "1 True" \
  "$rc $(grep -q 'modelo' "$tmp/err" && echo True || echo False)"
out="$(cd "$r" && bash "$fake/scripts/setup-dispatcher.sh" --check 2>/dev/null)"; rc=$?
check CA4 "sem o modelo do plugin, o --check sai com 1" "1" "$rc"
check CA4 "sem o modelo do plugin, nada é gravado" "$before" "$(snapshot "$r")"

# CA5: sem commit, sem git add, sem gh.
r="$(new_repo ca5)"
head_before="$(git -C "$r" rev-parse HEAD)"
bin="$tmp/bin"; mkdir -p "$bin"
printf '#!/usr/bin/env bash\necho "gh $*" >> "%s/gh.calls"\nexit 0\n' "$tmp" > "$bin/gh"
chmod +x "$bin/gh"
out="$(cd "$r" && PATH="$bin:$PATH" bash "$setup" --apply 2>&1)"
check CA5 "depois do --apply, o arquivo aparece como não rastreado" "?? $wf" "$(git -C "$r" status --porcelain --untracked-files=all)"
check CA5 "o git log não muda" "$head_before" "$(git -C "$r" rev-parse HEAD)"
check CA5 "o índice continua vazio" "" "$(git -C "$r" diff --cached --name-only)"
git -C "$r" add "$wf"
git -C "$r" -c user.name=teste -c user.email=teste@exemplo.com commit -q -m wf
head_before="$(git -C "$r" rev-parse HEAD)"
echo "# edição local" >> "$r/$wf"
(cd "$r" && PATH="$bin:$PATH" bash "$setup" --apply >/dev/null 2>&1)
echo "# outra" >> "$r/$wf"
(cd "$r" && PATH="$bin:$PATH" bash "$setup" --apply >/dev/null 2>&1)
check CA5 "substituir um arquivo rastreado não faz commit" "$head_before" "$(git -C "$r" rev-parse HEAD)"
check CA5 "o gh nunca é chamado" "False" "$([[ -f "$tmp/gh.calls" ]] && echo True || echo False)"
check CA5 "o script não chama git add, git commit nem gh" "0" \
  "$(grep -v '^ *#' "$setup" | grep -c -E 'git (add|commit|push)|(^|[^a-z])gh ')"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
