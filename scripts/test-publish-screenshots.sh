#!/usr/bin/env bash
# Testa o scripts/publish-screenshots.sh (SPEC-129, CA5 a CA12) com um HOME
# temporário e um remoto --bare local, sem rede.
# Uso: bash scripts/test-publish-screenshots.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sut="$script_dir/publish-screenshots.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 LC_ALL=C.UTF-8
mkdir -p "$HOME"
git config --global user.name teste
git config --global user.email teste@exemplo.com
git config --global init.defaultBranch main

failures=0 total=0

# result <ok: 0|1> <CA> <descrição>
result() {
  total=$((total + 1))
  if (( $1 == 0 )); then
    printf 'ok      %-5s %s\n' "$2" "$3"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-5s %s\n' "$2" "$3"
  fi
}

# check <CA> <descrição> <comando...>: ok se o comando sai com 0.
check() {
  local ca=$1 desc=$2
  shift 2
  if "$@"; then result 0 "$ca" "$desc"; else result 1 "$ca" "$desc"; fi
}

# new_repo <nome>: remoto --bare com main e um clone dele em $tmp/<nome>.
new_repo() {
  local name=$1
  git init -q --bare "$tmp/$name.git"
  git clone -q "$tmp/$name.git" "$tmp/$name" 2>/dev/null
  (
    cd "$tmp/$name" || exit 1
    echo app >app.txt
    git add app.txt
    git commit -qm "commit inicial"
    git push -q origin main
  )
}

# pngs <pasta> <nome>...: cria PNGs mínimos, com conteúdo diferente por nome.
pngs() {
  local dir=$1 name
  shift
  mkdir -p "$dir"
  for name in "$@"; do
    printf '\x89PNG\r\n\x1a\n%s' "$name" >"$dir/$name"
  done
}

# run <clone> <args...>: roda o script no clone; guarda saída em $out, $err e $rc.
run() {
  local clone=$1
  shift
  out=$(cd "$clone" && bash "$sut" "$@" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}

remote_tip() { git --git-dir="$1" rev-parse -q --verify refs/heads/fabrica-telas; }
remote_files() { git --git-dir="$1" ls-tree -r --name-only refs/heads/fabrica-telas; }

head_sha=0123456789abcdef0123456789abcdef01234567
short=0123456

# --- CA5, CA6, CA7: primeira publicação, sem fabrica-telas no remoto ---
new_repo app
pngs "$tmp/shots" \
  novo-evento--padrao--celular.png novo-evento--padrao--computador.png \
  novo-evento--erro--celular.png novo-evento--erro--computador.png \
  agenda--vazio--celular.png agenda--vazio--computador.png
echo nota >"$tmp/shots/notas.txt"
pngs "$tmp/shots/sub" outra--padrao--celular.png

# Estado do clone com mudança no índice e na cópia de trabalho.
(
  cd "$tmp/app" || exit 1
  git switch -q -c feat/7-tela
  echo mudou >>app.txt
  echo novo >novo.txt
  git add novo.txt
)
snapshot() {
  (
    cd "$tmp/app" || exit 1
    git symbolic-ref HEAD
    git rev-parse HEAD
    git ls-files -s
    git status --porcelain
  )
}
before=$(snapshot)

run "$tmp/app" dono/app 7 "$head_sha" "$tmp/shots"
tip=$(remote_tip "$tmp/app.git")
check CA5 "sai com 0 na primeira publicação" test "$rc" -eq 0
expected_files="issue-7/$short/agenda--vazio--celular.png
issue-7/$short/agenda--vazio--computador.png
issue-7/$short/novo-evento--erro--celular.png
issue-7/$short/novo-evento--erro--computador.png
issue-7/$short/novo-evento--padrao--celular.png
issue-7/$short/novo-evento--padrao--computador.png"
check CA5 "grava os PNGs em fabrica-telas:issue-7/<sha curto>/ no remoto" \
  test "$(remote_files "$tmp/app.git")" == "$expected_files"
check CA5 "o conteúdo do PNG gravado é o da pasta" \
  cmp -s <(git --git-dir="$tmp/app.git" cat-file blob "$tip:issue-7/$short/agenda--vazio--celular.png") \
  "$tmp/shots/agenda--vazio--celular.png"
u="https://github.com/dono/app/raw/$tip/issue-7/$short"
expected_table="Head \`$short\` · celular 390 × 844 (iPhone 12 Pro) · computador 1440 × 900 (Laptop L)

| Tela | Estado | Celular | Computador |
|---|---|---|---|
| agenda | vazio | ![agenda vazio celular]($u/agenda--vazio--celular.png) | ![agenda vazio computador]($u/agenda--vazio--computador.png) |
| novo-evento | erro | ![novo-evento erro celular]($u/novo-evento--erro--celular.png) | ![novo-evento erro computador]($u/novo-evento--erro--computador.png) |
| novo-evento | padrao | ![novo-evento padrao celular]($u/novo-evento--padrao--celular.png) | ![novo-evento padrao computador]($u/novo-evento--padrao--computador.png) |"
check CA5 "imprime a tabela em ordem de tela e estado, com o SHA completo do commit enviado" \
  test "$out" == "$expected_table"
check CA8 "ignora arquivos que não são PNG e subpastas" \
  bash -c "! git --git-dir='$tmp/app.git' ls-tree -r --name-only refs/heads/fabrica-telas | grep -qE 'notas|outra'"
check CA6 "cria a fabrica-telas órfã: o primeiro commit não tem pai" \
  test "$(git --git-dir="$tmp/app.git" rev-list --parents -n 1 "$tip")" == "$tip"
check CA6 "a árvore da branch órfã só tem issue-7/" \
  test "$(git --git-dir="$tmp/app.git" ls-tree --name-only "$tip")" == "issue-7"
check CA6 "nenhum commit da main no histórico da fabrica-telas" \
  test "$(git --git-dir="$tmp/app.git" rev-list --count "$tip")" -eq 1
check CA7 "branch atual, HEAD, índice e git status do clone iguais aos de antes" \
  test "$(snapshot)" == "$before"

# --- CA10: par com um dispositivo só ---
pngs "$tmp/shots10" lista--padrao--celular.png
run "$tmp/app" dono/app 10 "$head_sha" "$tmp/shots10"
tip=$(remote_tip "$tmp/app.git")
check CA10 "sai com 0 com um par incompleto" test "$rc" -eq 0
check CA10 "a célula do dispositivo sem arquivo é 'falta'" \
  test "$(tail -n 1 <<<"$out")" == "| lista | padrao | ![lista padrao celular](https://github.com/dono/app/raw/$tip/issue-10/$short/lista--padrao--celular.png) | falta |"

# --- CA11: publicar de novo a mesma issue e o mesmo SHA ---
other_before=$(git --git-dir="$tmp/app.git" rev-parse "refs/heads/fabrica-telas:issue-10")
rm "$tmp/shots/agenda--vazio--celular.png" "$tmp/shots/agenda--vazio--computador.png"
old_tip=$(remote_tip "$tmp/app.git")
run "$tmp/app" dono/app 7 "$head_sha" "$tmp/shots"
tip=$(remote_tip "$tmp/app.git")
check CA11 "sai com 0 na republicação" test "$rc" -eq 0
check CA11 "o PNG que só existia na primeira publicação some" \
  bash -c "! git --git-dir='$tmp/app.git' ls-tree -r --name-only refs/heads/fabrica-telas | grep -q agenda"
check CA11 "os links usam o SHA do commit novo" \
  bash -c "[[ '$tip' != '$old_tip' ]] && grep -q 'raw/$tip/issue-7/' <<<\"\$1\" && ! grep -q '$old_tip' <<<\"\$1\"" _ "$out"
check CA11 "a pasta de outra issue continua igual" \
  test "$(git --git-dir="$tmp/app.git" rev-parse "refs/heads/fabrica-telas:issue-10")" == "$other_before"
check CA11 "o commit novo tem o anterior como pai" \
  test "$(git --git-dir="$tmp/app.git" rev-parse "$tip^")" == "$old_tip"

# --- CA8: nomes fora do padrão ---
new_repo bad
for name in Tela--padrao--celular.png a--b--tablet.png a---b--celular.png; do
  rm -rf "$tmp/shots8"
  pngs "$tmp/shots8" ok--padrao--celular.png "$name"
  run "$tmp/bad" dono/bad 8 "$head_sha" "$tmp/shots8"
  check CA8 "'$name' faz o script sair com 3, listando o nome" \
    bash -c "(( $rc == 3 )) && grep -qF -- '$name' <<<\"\$1\" && ! grep -qF ok--padrao <<<\"\$1\"" _ "$err"
  check CA8 "'$name': nada enviado ao remoto" test -z "$(remote_tip "$tmp/bad.git")"
done
check CA8 "nenhum objeto da publicação recusada no remoto" \
  test "$(git --git-dir="$tmp/bad.git" rev-list --all --count)" -eq 1

# --- CA9: pasta inexistente ou sem PNG ---
run "$tmp/bad" dono/bad 9 "$head_sha" "$tmp/nao-existe"
check CA9 "pasta inexistente sai com 4" test "$rc" -eq 4
mkdir -p "$tmp/shots9/sub"
echo x >"$tmp/shots9/leia.txt"
pngs "$tmp/shots9/sub" a--b--celular.png
run "$tmp/bad" dono/bad 9 "$head_sha" "$tmp/shots9"
check CA9 "pasta sem PNG no primeiro nível sai com 4" test "$rc" -eq 4
check CA9 "nada enviado ao remoto" test -z "$(remote_tip "$tmp/bad.git")"

# Argumentos errados.
run "$tmp/bad" dono/bad abc "$head_sha" "$tmp/shots10"
check uso "número de issue inválido sai com 2" test "$rc" -eq 2
run "$tmp/bad" dono/bad 9
check uso "faltando argumentos sai com 2" test "$rc" -eq 2

# --- CA12: remoto avançado entre a leitura e o push ---
new_repo race
pngs "$tmp/shots1" um--padrao--celular.png
run "$tmp/race" dono/race 1 "$head_sha" "$tmp/shots1"
first=$(remote_tip "$tmp/race.git")
# Commit de outra publicação (issue 2) sobre a ponta atual, guardado numa
# ref fora de refs/heads para o hook avançar a fabrica-telas com ele.
git clone -q "$tmp/race.git" "$tmp/race-outra" 2>/dev/null
(
  cd "$tmp/race-outra" || exit 1
  git switch -q fabrica-telas
  pngs issue-2/abcdef0 dois--padrao--celular.png
  git add issue-2
  git commit -qm "telas da issue #2"
  git push -q origin HEAD:refs/test/outra
)
other=$(git --git-dir="$tmp/race.git" rev-parse refs/test/outra)

# pre-receive: conta as chamadas em $tmp/count; recusa enquanto a contagem
# não passa de $tmp/refuse; na primeira, com $tmp/race-flag, avança a branch.
cat >"$tmp/race.git/hooks/pre-receive" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$tmp/count" 2>/dev/null || echo 0) + 1 ))
echo "\$n" >"$tmp/count"
if (( n == 1 )) && [[ -f "$tmp/race-flag" ]]; then
  env -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    git update-ref refs/heads/fabrica-telas "$other" "$first"
fi
next=\$(sed -n "\${n}p" "$tmp/chain" 2>/dev/null)
if [[ -n \$next ]]; then
  env -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    git update-ref refs/heads/fabrica-telas "\$next"
fi
if (( n <= \$(cat "$tmp/refuse") )); then
  echo "recusado pelo teste (\$n)" >&2
  exit 1
fi
EOF
chmod +x "$tmp/race.git/hooks/pre-receive"

echo 1 >"$tmp/refuse"
touch "$tmp/race-flag"
rm -f "$tmp/count"
pngs "$tmp/shots3" tres--padrao--celular.png
run "$tmp/race" dono/race 3 "$head_sha" "$tmp/shots3"
tip=$(remote_tip "$tmp/race.git")
check CA12 "com o remoto avançado, refaz o commit e sai com 0" test "$rc" -eq 0
check CA12 "duas tentativas de push" test "$(cat "$tmp/count")" -eq 2
check CA12 "o commit enviado tem a ponta nova como pai" \
  test "$(git --git-dir="$tmp/race.git" rev-parse "$tip^")" == "$other"
check CA12 "preserva a pasta da outra publicação" \
  test "$(git --git-dir="$tmp/race.git" ls-tree --name-only "$tip" | tr '\n' ' ')" == "issue-1 issue-2 issue-3 "
check CA12 "a tabela usa o SHA do commit enviado" grep -q "raw/$tip/issue-3/" <<<"$out"

# Esgotamento: cada chamada do hook avança a fabrica-telas para o próximo commit
# da cadeia, então o origin avança em todas as tentativas e o script sai com 5.
rm -f "$tmp/race-flag" "$tmp/count"
echo 99 >"$tmp/refuse"
tree=$(git --git-dir="$tmp/race.git" rev-parse "$other^{tree}")
prev=$other
: >"$tmp/chain"
for i in 1 2 3; do
  prev=$(echo "corrida $i" | git --git-dir="$tmp/race.git" commit-tree "$tree" -p "$prev")
  echo "$prev" >>"$tmp/chain"
done
pngs "$tmp/shots4" quatro--padrao--celular.png
run "$tmp/race" dono/race 4 "$head_sha" "$tmp/shots4"
check CA12 "com o origin avançando em cada tentativa, sai com 5" test "$rc" -eq 5
check CA12 "sem uma 4ª tentativa" test "$(cat "$tmp/count")" -eq 3
check CA12 "repete a mensagem do git" grep -q "recusado pelo teste" <<<"$err"
check CA12 "a fabrica-telas fica no último avanço da corrida" \
  test "$(remote_tip "$tmp/race.git")" == "$(sed -n 3p "$tmp/chain")"
check CA12 "nada no stdout quando falha" test -z "$out"

# Recusa sem avanço do origin (hook que recusa sem mexer no remoto): não é
# corrida, então sai com 1 na primeira tentativa, sem repetir.
rm -f "$tmp/chain" "$tmp/count"
echo 99 >"$tmp/refuse"
before_tip=$(remote_tip "$tmp/race.git")
pngs "$tmp/shots5" cinco--padrao--celular.png
run "$tmp/race" dono/race 5 "$head_sha" "$tmp/shots5"
check CA12 "recusa sem avanço do origin sai com 1" test "$rc" -eq 1
check CA12 "recusa sem avanço não repete" test "$(cat "$tmp/count")" -eq 1
check CA12 "recusa sem avanço não muda o remoto" test "$(remote_tip "$tmp/race.git")" == "$before_tip"
check CA12 "recusa sem avanço repete a mensagem do git" grep -q "recusado pelo teste" <<<"$err"

echo
echo "$((total - failures)) de $total passaram"
(( failures == 0 ))
