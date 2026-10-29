#!/usr/bin/env bash
# Testa a proteção da main com um HOME temporário e repositórios locais, sem
# rede: instala os hooks do git com scripts/setup-githooks.sh, faz commits e
# pushes de verdade e confere as checagens do PreToolUse.
# Uso: scripts/test-protect-main.sh [caminho do hook PreToolUse]
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup_script="$script_dir/setup-githooks.sh"
source_dir="$(realpath "$script_dir/../githooks")"
hook="$(realpath "${1:-$script_dir/../hooks/protect-main.sh}")"
[[ -f "$hook" ]] || { echo "test-protect-main: hook não encontrado em $hook" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Isola a configuração global do git no HOME de teste.
unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name teste
git config --global user.email teste@exemplo.com
git config --global init.defaultBranch main
dest="$HOME/.config/fabrica/githooks"
version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$script_dir/../.claude-plugin/plugin.json")"

failures=0 total=0

# result <ok: 0|1> <CA> <descrição>
result() {
  total=$((total + 1))
  local label="${3//$'\n'/⏎}"
  label="${label//$tmp/<tmp>}"
  if (( $1 == 0 )); then
    printf 'ok      %-4s %s\n' "$2" "$label"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n' "$2" "$label"
  fi
}

# ---------------------------------------------------------------------------
# CA5: scripts/setup-githooks.sh

[[ $(bash "$setup_script" --check) == ausente ]]
result $? CA5 "--check sem instalação: ausente"

bash "$setup_script" >/dev/null
[[ $(git config --global core.hooksPath) == "$dest" ]]
result $? CA5 "instalação define o core.hooksPath global"

ok=0
for f in "$source_dir"/*; do
  [[ -x "$dest/${f##*/}" ]] && cmp -s "$f" "$dest/${f##*/}" || ok=1
done
[[ $(cat "$dest/VERSION") == "$version" ]] || ok=1
result $ok CA5 "copia todos os hooks, executáveis, e o VERSION $version"

snapshot() { cat "$HOME/.gitconfig"; ls -l --time-style=+ "$dest"; }
before=$(snapshot)
bash "$setup_script" >/dev/null
[[ $(snapshot) == "$before" ]]
result $? CA5 "rodar de novo não muda nada"

[[ $(bash "$setup_script" --check) == ok ]]
result $? CA5 "--check instalado: ok"

echo 0.0.0 >"$dest/VERSION"
rm "$dest/pre-push"
[[ $(bash "$setup_script" --check) == "atualizado $version" && -x "$dest/pre-push" && $(cat "$dest/VERSION") == "$version" ]]
result $? CA5 "--check com versão antiga: atualizado $version e copia de novo"

git config --global core.hooksPath /outra/ferramenta
bash "$setup_script" >/dev/null 2>&1
[[ $? -ne 0 && $(git config --global core.hooksPath) == /outra/ferramenta ]]
result $? CA5 "com outro core.hooksPath global: erro e nada muda"

[[ $(bash "$setup_script" --check) == ausente && $(git config --global core.hooksPath) == /outra/ferramenta ]]
result $? CA5 "--check com outro core.hooksPath: ausente, sem alterar"

bash "$setup_script" --force >/dev/null
[[ $(git config --global core.hooksPath) == "$dest" ]]
result $? CA5 "--force troca o core.hooksPath"

# ---------------------------------------------------------------------------
# Repositórios de teste, com os hooks instalados:
#   main      com commit, main em checkout, remoto com main; branch feat
#   wt        worktree do repositório main, na branch feature
#   master    com commit, master em checkout
#   empty     sem nenhum commit, remoto sem nenhuma branch
#   chain     na branch feat/x, com hooks próprios em .git/hooks
setup() {
  git init -q --bare "$tmp/remote.git"
  git init -q "$tmp/main"
  git -C "$tmp/main" remote add origin "$tmp/remote.git"
  git init -q -b master "$tmp/master"
  git -C "$tmp/master" commit -q --no-verify --allow-empty -m inicial
  git init -q "$tmp/empty"
  git init -q --bare "$tmp/empty-remote.git"
  git -C "$tmp/empty" remote add origin "$tmp/empty-remote.git"
  git init -q -b feat/x "$tmp/chain"
}
setup || { echo "test-protect-main: falhou ao criar os repositórios de teste" >&2; exit 1; }
MAIN=$tmp/main WT=$tmp/wt EMPTY=$tmp/empty CHAIN=$tmp/chain

# run <dir> <comando>: roda o comando num bash, como o Claude faria. A saída
# de erro fica em $tmp/err.
run() { (cd "$1" && bash -c "$2") >/dev/null 2>"$tmp/err"; }
head_of() { git -C "$1" rev-parse -q --verify "${2:-HEAD}"; }

# CA3: commit inicial e primeiro push passam.
run "$MAIN" 'git commit --allow-empty -m inicial'
result $? CA3 "commit inicial num repositório novo na main"
run "$MAIN" 'git push -q -u origin main'
result $? CA3 "primeiro push da main, ainda ausente no remoto"
git -C "$MAIN" branch -q feat
git -C "$MAIN" worktree add -q -b feature "$WT"

# CA1: commit na main falha em todas as formas, e a main não muda.
# deny_commit <dir> <comando>
deny_commit() {
  local before after
  before=$(head_of "$1")
  run "$1" "$2"
  local rc=$?
  after=$(head_of "$1")
  [[ $rc -ne 0 && $before == "$after" ]] && grep -q "Commit direto na '" "$tmp/err"
  result $? CA1 "falha: $2"
}
deny_commit "$MAIN" 'git commit --allow-empty -m x'
deny_commit "$MAIN" 'bash -c "git -c user.name=\"b\" commit --allow-empty -m x"'
deny_commit "$MAIN" 'eval git commit --allow-empty -m x'
deny_commit "$MAIN" "cd /; W=$MAIN; git -C \$W commit --allow-empty -m x"
deny_commit "$MAIN" "timeout 5 bash -c 'git commit --allow-empty -m x'"
deny_commit "$MAIN" 'bash -c "$(echo git) commit --allow-empty -m x"'
deny_commit "$MAIN" "bash -c 'git -c user.name='\\''b'\\'' commit --allow-empty -m x'"
deny_commit "$MAIN" 'git commit --amend --allow-empty -m y'
deny_commit "$tmp/master" 'git commit --allow-empty -m x'

git -C "$WT" commit -q --allow-empty -m "na feature"
deny_commit "$MAIN" 'git merge --no-ff -m m feature'
git -C "$MAIN" merge --abort 2>/dev/null

# CA3: fora da main, o commit passa.
before=$(head_of "$WT")
run "$WT" 'git commit --allow-empty -m "na worktree"'
[[ $? -eq 0 && $(head_of "$WT") != "$before" ]]
result $? CA3 "commit numa worktree de feature, com o clone principal na main"
run "$MAIN" 'git switch -q feat && git commit --allow-empty -m "na feat" && git switch -q main'
result $? CA3 "commit numa branch de feature"

# CA2: push para a main que já existe no remoto falha.
git -C "$MAIN" commit -q --no-verify --allow-empty -m "local na main"
remote_main=$(git -C "$tmp/remote.git" rev-parse main)
# deny_push <comando>
deny_push() {
  run "$MAIN" "$1"
  local rc=$?
  [[ $rc -ne 0 && $(git -C "$tmp/remote.git" rev-parse -q --verify main) == "$remote_main" ]] \
    && grep -q "Push para a main bloqueado" "$tmp/err"
  result $? CA2 "falha: $1"
}
deny_push 'git push origin main'
deny_push 'git push origin HEAD:main'
deny_push 'git push'
deny_push 'git push origin :main'
deny_push 'git push origin feat:refs/heads/main'
run "$MAIN" 'git push -q origin feat'
[[ $? -eq 0 && $(git -C "$tmp/remote.git" rev-parse feat) == $(head_of "$MAIN" feat) ]]
result $? CA2 "passa: git push origin feat, com a main em checkout"

run "$EMPTY" 'git commit --allow-empty -m inicial && git push -q origin main'
result $? CA3 "commit inicial e primeiro push num repositório sem remoto"

# CA4: os hooks do próprio repositório continuam rodando, encadeados.
cat >"$CHAIN/.git/hooks/pre-commit" <<EOF
#!/bin/sh
touch "$tmp/pre-commit-rodou"
EOF
cat >"$CHAIN/.git/hooks/commit-msg" <<EOF
#!/bin/sh
grep -q mensagem "\$1" && touch "$tmp/commit-msg-rodou"
EOF
cat >"$CHAIN/.git/hooks/pre-push" <<EOF
#!/bin/sh
cat >"$tmp/pre-push-stdin"
EOF
chmod +x "$CHAIN/.git/hooks/"*
run "$CHAIN" 'git commit --allow-empty -m mensagem'
[[ $? -eq 0 && -f $tmp/pre-commit-rodou ]]
result $? CA4 "pre-commit do repositório roda"
[[ -f $tmp/commit-msg-rodou ]]
result $? CA4 "commit-msg do repositório roda, com o argumento"
git init -q --bare "$tmp/chain-remote.git"
git -C "$CHAIN" remote add origin "$tmp/chain-remote.git"
run "$CHAIN" 'git push -q origin feat/x'
[[ $? -eq 0 ]] && grep -q "^refs/heads/feat/x [0-9a-f]* refs/heads/feat/x 0*$" "$tmp/pre-push-stdin"
result $? CA4 "pre-push do repositório roda, com o mesmo stdin"
printf '#!/bin/sh\nexit 1\n' >"$CHAIN/.git/hooks/pre-commit"
before=$(head_of "$CHAIN")
run "$CHAIN" 'git commit --allow-empty -m mensagem'
[[ $? -ne 0 && $(head_of "$CHAIN") == "$before" ]]
result $? CA4 "pre-commit do repositório que falha impede o commit"

# Push para a branch em checkout com updateInstead continua atualizando a
# worktree: não pode haver entrada push-to-checkout.
git init -q "$tmp/dest"
git -C "$tmp/dest" commit -q --allow-empty -m inicial
git -C "$tmp/dest" switch -q -c feat/y
git -C "$tmp/dest" config receive.denyCurrentBranch updateInstead
git clone -q "$tmp/dest" "$tmp/src"
echo conteudo >"$tmp/src/f"
git -C "$tmp/src" add f
git -C "$tmp/src" commit -q -m f
run "$tmp/src" 'git push -q origin feat/y'
[[ $? -eq 0 && -f $tmp/dest/f && -z $(git -C "$tmp/dest" status --porcelain) ]]
result $? CA4 "push com updateInstead atualiza a worktree do destino"

# pre-receive do repositório de destino roda, com o stdin do git.
printf '#!/bin/sh\ncat >"%s/pre-receive-stdin"\n' "$tmp" >"$tmp/chain-remote.git/hooks/pre-receive"
chmod +x "$tmp/chain-remote.git/hooks/pre-receive"
run "$CHAIN" 'git switch -q -c feat/z && git commit --no-verify --allow-empty -m z && git push -q origin feat/z'
grep -q " refs/heads/feat/z$" "$tmp/pre-receive-stdin" 2>/dev/null
result $? CA4 "pre-receive do remoto local roda, com o mesmo stdin"

# ---------------------------------------------------------------------------
# CA6: checagens do PreToolUse.

# check <esperado: deny|allow> <comando> [HOME]
check() {
  local expected=$1 command=$2 home=${3:-$HOME} got
  if jq -n --arg c "$command" --arg d "$MAIN" '{tool_input: {command: $c}, cwd: $d}' |
    HOME=$home bash "$hook" 2>&1 | grep -q '"permissionDecision": *"deny"'; then
    got=deny
  else
    got=allow
  fi
  [[ $got == "$expected" ]]
  result $? CA6 "$expected: $command"
}
check deny 'git commit --no-verify -m x'
check deny 'git push --no-verify origin main'
check deny 'git commit -n -m x'
check deny 'git commit -nm x'
check deny 'git commit -an -m x'
check deny $'git commit --allow-empty -m x \\\n  -n'
check deny 'git -c core.hooksPath=/dev/null commit -m x'
check deny 'git config --global --unset core.hooksPath'
check deny 'git --config-env=core.hookspath=X commit -m x'
check deny 'GIT_CONFIG_GLOBAL=/dev/null git commit -m x'
check deny 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x git commit -m x'
check deny 'HOME=/tmp git commit -m x'
check deny 'export XDG_CONFIG_HOME=/tmp; git commit -m x'
check deny 'rm -rf ~/.config/fabrica/githooks'
check deny 'gh pr create --title t --body "não use --no-verify"'
check allow "$(printf 'git commit -m "$(cat <<%sEOF%s\nfeat: adiciona x\n\nCo-Authored-By: t <t@t>\nEOF\n)"' "'" "'")"
check allow 'git log -n 5'
check allow 'git push -u origin feat/x'
check allow 'echo "git commit"'
check allow 'git commit -m x && git log -n 1'
check allow 'ls'
check deny 'git commit -m x' "$tmp/sem-hooks"
check deny 'git push origin feat/x' "$tmp/sem-hooks"
check allow 'ls -la' "$tmp/sem-hooks"
mkdir -p "$tmp/sem-hooks"
jq -n --arg c 'git commit -m x' '{tool_input: {command: $c}}' | HOME=$tmp/sem-hooks bash "$hook" |
  grep -q 'não estão instalados. Rode /fabrica:setup'
result $? CA6 "sem hooks: mensagem de instalação"

# Tempo: comando de 40 KB.
big="git commit -m \"$(head -c 40000 /dev/zero | tr '\0' a)\""
start=$(date +%s%N)
jq -n --arg c "$big" '{tool_input: {command: $c}}' | bash "$hook" >/dev/null
ms=$(( ($(date +%s%N) - start) / 1000000 ))
(( ms < 50 ))
result $? CA6 "comando de 40 KB em ${ms} ms (limite 50 ms)"

echo
if (( failures )); then
  echo "$failures de $total casos falharam."
  exit 1
fi
echo "Todos os $total casos passaram."
