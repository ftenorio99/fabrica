#!/usr/bin/env bash
# Testa o scripts/base-drift.sh (SPEC-135, CA1 a CA6) com repositórios git
# temporários para o modo local e um gh falso para o modo api, sem rede.
# Uso: bash scripts/test-base-drift.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sut="$script_dir/base-drift.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 LC_ALL=C.UTF-8
export GIT_CEILING_DIRECTORIES="$tmp"
mkdir -p "$HOME"
git config --global user.name teste
git config --global user.email teste@exemplo.com
git config --global init.defaultBranch main

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

# run <pasta> <args...>: roda o script na pasta; guarda $out, $err e $rc.
run() {
  local dir=$1
  shift
  out=$(cd "$dir" && bash "$sut" "$@" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}

# new_repo <nome>: origin --bare e um clone em $repo, com a.txt, b.txt e d.txt
# na main e a branch do PR já criada.
new_repo() {
  repo="$tmp/$1"
  git init -q --bare "$repo.git"
  git clone -q "$repo.git" "$repo" 2>/dev/null
  seq 1 20 >"$repo/a.txt"
  seq 101 120 >"$repo/b.txt"
  seq 201 220 >"$repo/d.txt"
  commit "commit inicial"
  git -C "$repo" push -q origin main
  git -C "$repo" switch -q -c feat/1-pr
}

commit() {
  git -C "$repo" add -A
  git -C "$repo" commit -qm "$1"
}

# on_main <função...>: roda a função na main, publica e volta à branch do PR.
on_main() {
  git -C "$repo" switch -q main
  "$@"
  git -C "$repo" push -q origin main
  git -C "$repo" switch -q feat/1-pr
  git -C "$repo" fetch -q origin
}

# edit <arquivo> <linha> <texto>: troca uma linha e faz o commit.
edit() {
  sed -i "$2s/.*/$3/" "$repo/$1"
  commit "muda $1"
}

add_file() {
  echo conteudo >"$repo/$1"
  commit "cria $1"
}

remove_file() {
  git -C "$repo" rm -q "$1"
  commit "apaga $1"
}

rename_file() {
  git -C "$repo" mv "$1" "$2"
  commit "renomeia $1"
}

# --- CA1: em-dia ---
new_repo igual
run "$repo" local
check CA1 "branch sem commit próprio igual à main" "0 em-dia" "$rc $out"
add_file novo.txt
edit a.txt 1 pr
run "$repo" local
check CA1 "branch com commits próprios sobre a ponta da main" "0 em-dia" "$rc $out"
run "$repo" local main
check CA1 "base informada no argumento" "0 em-dia" "$rc $out"

# --- CA2: atrás sem sobreposição ---
new_repo atras
edit a.txt 1 pr
main_two() { edit b.txt 1 main; add_file e.txt; }
on_main main_two
run "$repo" local
check CA2 "2 commits da main em arquivos que o PR não muda" "0 atras-sem-sobreposicao 2" "$rc $out"
mkdir -p "$repo/sub"
run "$repo/sub" local
check CA2 "mesma saída a partir de uma subpasta" "0 atras-sem-sobreposicao 2" "$rc $out"

# --- CA3: sobreposição ---
new_repo sobre
edit a.txt 1 pr
on_main edit a.txt 18 main
run "$repo" local
check CA3 "mesmo arquivo em linhas distantes" "0 sobreposicao 1 a.txt" "$rc $out"

new_repo ordem
edit d.txt 1 pr
edit a.txt 1 pr
add_file so-do-pr.txt
main_both() { sed -i '18s/.*/main/' "$repo/d.txt"; sed -i '18s/.*/main/' "$repo/a.txt"; commit "muda dois"; }
on_main main_both
run "$repo" local
check CA3 "arquivos em ordem alfabética, só os comuns" "0 sobreposicao 1 a.txt d.txt" "$rc $out"

new_repo renomeado-main
edit b.txt 1 pr
on_main rename_file b.txt c.txt
run "$repo" local
check CA3 "main renomeia o arquivo que o PR altera" "0 sobreposicao 1 b.txt" "$rc $out"

new_repo renomeado-pr
rename_file b.txt c.txt
on_main edit b.txt 18 main
run "$repo" local
check CA3 "PR renomeia o arquivo que a main altera" "0 sobreposicao 1 b.txt" "$rc $out"

new_repo depois-do-merge
edit a.txt 1 pr
on_main edit a.txt 18 main
git -C "$repo" merge -q --no-edit origin/main >/dev/null
run "$repo" local
check CA3 "depois do merge da main a branch fica em dia" "0 em-dia" "$rc $out"
on_main edit b.txt 1 main
run "$repo" local
check CA3 "a base comum passa a ser o commit mergeado" "0 atras-sem-sobreposicao 1" "$rc $out"

# --- CA4: conflito ---
new_repo conflito
edit a.txt 5 pr
edit d.txt 1 pr
main_conflict() { edit a.txt 5 main; edit d.txt 18 main; }
on_main main_conflict
head_before=$(git -C "$repo" rev-parse HEAD)
run "$repo" local
check CA4 "mesma linha: só o arquivo em conflito, com precedência" "0 conflito 2 a.txt" "$rc $out"
check CA4 "worktree limpa depois da execução" "" "$(git -C "$repo" status --porcelain)"
check CA4 "HEAD igual ao de antes" "$head_before" "$(git -C "$repo" rev-parse HEAD)"
check CA4 "sem merge em andamento" "não" \
  "$(git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null && echo sim || echo não)"

new_repo apagado
edit b.txt 1 pr
on_main remove_file b.txt
head_before=$(git -C "$repo" rev-parse HEAD)
run "$repo" local
check CA4 "apagado na main e alterado no PR" "0 conflito 1 b.txt" "$rc $out"
check CA4 "worktree limpa no arquivo apagado" "" "$(git -C "$repo" status --porcelain)"
check CA4 "HEAD igual no arquivo apagado" "$head_before" "$(git -C "$repo" rev-parse HEAD)"

new_repo varios
edit d.txt 5 pr
edit a.txt 5 pr
main_two_conflicts() { edit d.txt 5 main; edit a.txt 5 main; }
on_main main_two_conflicts
run "$repo" local
check CA4 "conflitos em ordem alfabética" "0 conflito 2 a.txt d.txt" "$rc $out"

# --- CA5: modo api com gh falso ---
bin="$tmp/bin"
mkdir -p "$bin"
cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_GH/calls"
[[ -f "$FAKE_GH/fail" ]] && { echo "gh: falha simulada" >&2; exit 1; }
case "$*" in
  "pr view 7 -R dono/app --json files,mergeable,baseRefName,headRefName") cat "$FAKE_GH/pr.json" ;;
  "api repos/dono/app/compare/feat/1-pr...main") cat "$FAKE_GH/compare.json" ;;
  "api repos/dono/app/pulls/7/files --paginate --slurp") cat "$FAKE_GH/pr-files.json" ;;
  *) echo "gh falso: argumentos inesperados: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$bin/gh"
export FAKE_GH="$tmp/gh"
mkdir -p "$FAKE_GH"
PATH="$bin:$PATH"

# pr <mergeable> <arquivo[:changeType]>...
pr() {
  local mergeable=$1 files="" f type
  shift
  for f in "$@"; do
    type=MODIFIED
    [[ $f == *:* ]] && type=${f#*:}
    files+="${files:+,}{\"path\":\"${f%%:*}\",\"changeType\":\"$type\"}"
  done
  printf '{"baseRefName":"main","headRefName":"feat/1-pr","mergeable":"%s","files":[%s]}' \
    "$mergeable" "$files" >"$FAKE_GH/pr.json"
}

# compare <ahead_by> <arquivo[:anterior]>...
compare() {
  local ahead=$1 files="" f prev
  shift
  for f in "$@"; do
    prev=""
    [[ $f == *:* ]] && prev=",\"previous_filename\":\"${f#*:}\""
    files+="${files:+,}{\"filename\":\"${f%%:*}\"$prev}"
  done
  printf '{"ahead_by":%s,"files":[%s]}' "$ahead" "$files" >"$FAKE_GH/compare.json"
}

api() { run "$tmp" api dono/app 7; }

pr MERGEABLE a.txt
compare 0
api
check CA5 "ahead_by 0" "0 em-dia" "$rc $out"

compare 2 b.txt e.txt
api
check CA5 "nenhum arquivo em comum" "0 atras-sem-sobreposicao 2" "$rc $out"

pr MERGEABLE d.txt a.txt so-do-pr.txt
compare 3 d.txt a.txt e.txt
api
check CA5 "arquivos em comum, em ordem" "0 sobreposicao 3 a.txt d.txt" "$rc $out"

pr MERGEABLE b.txt
compare 1 c.txt:b.txt
api
check CA5 "caminho antigo de um renomeado na base" "0 sobreposicao 1 b.txt" "$rc $out"

pr MERGEABLE c.txt:RENAMED
compare 1 b.txt
echo '[[{"filename":"c.txt","previous_filename":"b.txt"}]]' >"$FAKE_GH/pr-files.json"
api
check CA5 "caminho antigo de um renomeado no PR" "0 sobreposicao 1 b.txt" "$rc $out"

pr CONFLICTING a.txt so-do-pr.txt
compare 1 a.txt e.txt
api
check CA5 "mergeable CONFLICTING" "0 conflito 1 a.txt" "$rc $out"

pr UNKNOWN a.txt
compare 1 a.txt
api
check CA5 "UNKNOWN com arquivos em comum" "0 sobreposicao 1 a.txt" "$rc $out"

compare 1 e.txt
api
check CA5 "UNKNOWN sem arquivos em comum" "0 atras-sem-sobreposicao 1" "$rc $out"

# --- CA6: erros ---
# usage_case <descrição> <pasta> <args...>
usage_case() {
  local desc=$1
  shift
  run "$@"
  check CA6 "$desc: sai com 2, sem saída padrão" "2 []" "$rc [$out]"
}
mkdir -p "$tmp/fora"
usage_case "sem argumento" "$repo"
usage_case "modo desconhecido" "$repo" outro
usage_case "argumento sobrando no local" "$repo" local main extra
usage_case "api sem o nº do PR" "$tmp" api dono/app
usage_case "api sem argumentos" "$tmp" api
usage_case "api com nº inválido" "$tmp" api dono/app abc
usage_case "api com repositório inválido" "$tmp" api app 7
usage_case "local fora de um repositório git" "$tmp/fora" local
usage_case "local dentro de um repositório bare" "$repo.git" local

run "$repo" local origin/nao-existe
check CA6 "base inexistente sai com 1, sem saída padrão" "1 []" "$rc [$out]"
check CA6 "base inexistente explica na saída de erro" "sim" "$([[ -n $err ]] && echo sim || echo não)"

pr MERGEABLE a.txt
touch "$FAKE_GH/fail"
api
check CA6 "gh falhando sai com 1, sem saída padrão" "1 []" "$rc [$out]"
check CA6 "a mensagem do gh vai para a saída de erro" "sim" \
  "$([[ $err == *"falha simulada"* ]] && echo sim || echo não)"
rm "$FAKE_GH/fail"

echo 'não é json' >"$FAKE_GH/compare.json"
api
check CA6 "resposta ilegível do gh sai com 1" "1 []" "$rc [$out]"

echo
echo "$((total - failures))/$total verificações passaram"
(( failures == 0 ))
