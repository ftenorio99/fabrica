#!/usr/bin/env bash
# Testa hooks/protect-main.sh com repositórios locais temporários, sem rede.
# Uso: scripts/test-protect-main.sh [caminho do hook]
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$(realpath "${1:-$script_dir/../hooks/protect-main.sh}")"
[[ -f "$hook" ]] || { echo "test-protect-main: hook não encontrado em $hook" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@exemplo.com
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@exemplo.com
export GIT_CONFIG_GLOBAL=/dev/null

# Repositórios de teste:
#   main      com commit, main em checkout, remoto com main
#   feat      clone do mesmo remoto, na branch feat/x
#   empty     sem nenhum commit, na main
#   newremote com commit, na main, remoto ainda sem main
#   wt        worktree do repositório main, na branch feature
setup() {
  git init -q --bare -b main "$tmp/remote.git"
  git init -q -b main "$tmp/main"
  git -C "$tmp/main" commit -q --allow-empty -m inicial
  git -C "$tmp/main" remote add origin "$tmp/remote.git"
  git -C "$tmp/main" push -q origin main
  git clone -q "$tmp/remote.git" "$tmp/feat"
  git -C "$tmp/feat" switch -q -c feat/x
  git init -q -b main "$tmp/empty"
  git init -q --bare "$tmp/empty-remote.git"
  git init -q -b main "$tmp/newremote"
  git -C "$tmp/newremote" commit -q --allow-empty -m inicial
  git -C "$tmp/newremote" remote add origin "$tmp/empty-remote.git"
  git -C "$tmp/main" worktree add -q -b feature "$tmp/wt"
  mkdir "$tmp/wt/sub"
}
setup || { echo "test-protect-main: falhou ao criar os repositórios de teste" >&2; exit 1; }

MAIN=$tmp/main FEAT=$tmp/feat EMPTY=$tmp/empty NEWREMOTE=$tmp/newremote WT=$tmp/wt
failures=0 total=0

# check <esperado: deny|allow> <CA> <cwd> <comando>
check() {
  local expected=$1 ca=$2 dir=$3 command=$4 got output label
  output=$(jq -n --arg c "$command" --arg d "$dir" '{tool_input: {command: $c}, cwd: $d}' | HOME=$tmp bash "$hook" 2>&1)
  if grep -q '"permissionDecision": *"deny"' <<<"$output"; then got=deny; else got=allow; fi
  total=$((total + 1))
  label="${command//$'\n'/⏎}"
  label="${label//$tmp/<tmp>}"
  if [[ $got == "$expected" ]]; then
    printf 'ok      %-4s %-5s %-9s %s\n' "$ca" "$expected" "${dir##*/}" "$label"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %-5s %-9s %s (veio %s)\n' "$ca" "$expected" "${dir##*/}" "$label" "$got"
  fi
}

# CA1: os dois casos da issue.
check allow CA1 "$FEAT" $'git commit -m "chore: algo sobre a main\n\ncorpo" && git push origin feat/x'
check allow CA1 "$MAIN" 'gh issue create --body "exemplo: git commit -m x"'
check allow CA1 "$FEAT" 'git push -u origin feat/x'
check allow CA1 "$MAIN" $'gh issue create --title t --body "$(cat <<\'EOF\'\nO hook bloqueia `git commit` na main (e o push.\ngit commit -m x\nEOF\n)"'

# CA2: texto citado não bloqueia.
check allow CA2 "$MAIN" "echo 'git push origin main'"
check allow CA2 "$MAIN" $'gh issue comment 1 --body-file - <<\'EOF\'\ngit commit -m x\ngit push origin main\nEOF'
check allow CA2 "$MAIN" $'cat <<-EOF\n\tgit commit -m x\n\tEOF'
check allow CA2 "$MAIN" 'ls # git commit -m x'
check allow CA2 "$FEAT" "gh pr create --title t --body 'O hook trata pipe para shell (x | bash ) e bloqueia git push origin main'"
check allow CA2 "$FEAT" $'gh pr create --body-file - <<\'EOF\'\nO hook trata echo x | bash\ne bloqueia git push origin main\nEOF'

# CA3: commit e push na main continuam bloqueados.
check deny CA3 "$MAIN" 'git commit -m x'
check deny CA3 "$FEAT" 'git push origin main'
check deny CA3 "$FEAT" 'git push origin HEAD:main'
check deny CA3 "$MAIN" 'git push'
check deny CA3 "$FEAT" 'git status; git push origin main'
check deny CA3 "$FEAT" $'git status\ngit push origin main'
check deny CA3 "$FEAT" 'FOO=1 git push origin main'
check deny CA3 "$FEAT" "git push origin 'main'"
check deny CA3 "$FEAT" 'git push origin "HEAD:main"'
check deny CA3 "$MAIN" 'if git commit -m x; then echo ok; fi'
check deny CA3 "$FEAT" 'while git push origin main; do break; done'
check deny CA3 "$FEAT" $'git push \\\n  origin main'

# CA4: bloqueio na dúvida.
check deny CA4 "$FEAT" 'bash -c "git push origin main"'
check deny CA4 "$FEAT" "sh -c 'git push origin main'"
check deny CA4 "$FEAT" 'eval "git push origin main"'
check deny CA4 "$MAIN" 'echo "$(git commit -m x)"'
check deny CA4 "$MAIN" 'echo "`git commit -m x`"'
check deny CA4 "$FEAT" $'bash <<EOF\ngit push origin main\nEOF'
check deny CA4 "$FEAT" 'echo "git push origin main" | bash'
check deny CA4 "$FEAT" 'echo "git push origin main'
check deny CA4 "$FEAT" 'bash <<< "git push origin main"'
check deny CA4 "$MAIN" 'sudo -u eu git commit -m x'
check deny CA4 "$MAIN" 'env -i git commit -m x'
check deny CA4 "$FEAT" $'cat <<EOF | bash\ngit push origin main\nEOF'

# CA5: diretório certo.
check deny CA5 "$FEAT" "cd $MAIN && git commit -m x"
check deny CA5 "$FEAT" "git -C $MAIN commit -m x"
check deny CA5 "$FEAT" "git status; cd $MAIN && git commit -m x"
check deny CA5 "$FEAT" "cd \"$MAIN\" && git commit -m x"
check deny CA5 "$FEAT" "git -C '$MAIN' commit -m x"
check deny CA5 "$FEAT" "git --git-dir $MAIN/.git commit -m x"
check deny CA5 "$MAIN" 'git -c "user.name=x" commit -m x'
check deny CA5 "$MAIN" "echo \"\$(git commit -m x)\"; cd $FEAT"
check deny CA5 "$MAIN" "bash -c 'git commit -m x'; cd $FEAT"
check deny CA5 "$MAIN" "eval 'git commit -m x' && cd $FEAT && ls"
check deny CA5 "$MAIN" 'D="$(cd /tmp && pwd)" && git commit -m x'
check deny CA5 "$MAIN" "D=\"\$(cd $FEAT && pwd)\"; git push"
check deny CA5 "$MAIN" "bash -c 'cd /tmp'; git commit -m x"
check deny CA5 "$MAIN" $'bash <<EOF\ncd /tmp\nEOF\ngit commit -m x'
check deny CA5 "$MAIN" 'D=$(cd /tmp && pwd) && git commit -m x'
check deny CA5 "$MAIN" '(cd /tmp && ls); git commit -m x'
check allow CA5 "$MAIN" "(cd $FEAT && git commit -m x)"
check allow CA5 "$MAIN" "eval 'cd $FEAT' && git commit -m x"
check deny CA5 "$MAIN" 'D=`cd /tmp && pwd`; git commit -m x'
check deny CA5 "$MAIN" 'cd /tmp && cd - ; git commit -m x'
check allow CA5 "$MAIN" "cd $FEAT && cd /tmp && cd - && git commit -m x"
check allow CA5 "$MAIN" "git -C $FEAT push origin feat/x"
check allow CA5 "$MAIN" "cd $FEAT && git commit -m x"

# Issue #22: variáveis em cd, git -C e --git-dir (casos V1 a V5, da SPEC-22).
# V1: os casos da issue.
check allow V1 "$MAIN" "W=$WT && cd \$W && git commit -m x"
check allow V1 "$MAIN" "W=$WT; git -C \$W commit -m x"
check allow V1 "$MAIN" "cd $WT && git commit -m x"
check allow V1 "$MAIN" "git -C $WT commit -m x"
check deny V1 "$MAIN" 'git commit -m x'
# V2: formas resolvidas.
check allow V2 "$MAIN" "W=$WT; cd \${W} && git commit -m x"
check allow V2 "$MAIN" "W=$WT; cd \"\$W\" && git commit -m x"
check allow V2 "$MAIN" "W=$WT; cd \"\$W/sub\" && git commit -m x"
check allow V2 "$MAIN" "export W=$WT && git -C \$W commit -m x"
check allow V2 "$MAIN" "A=$tmp; B=\$A/wt; cd \$B && git commit -m x"
check allow V2 "$MAIN" "W=$WT; git --git-dir \$W/.git commit -m x"
check allow V2 "$MAIN" "W=$WT; cd \$W && git commit -m x; cd \$OLDPWD"
check allow V2 "$MAIN" "cd $WT && D=\$PWD && cd /tmp && git -C \$D commit -m x"
check allow V2 "$MAIN" "W=$tmp/../${tmp##*/}/wt; cd \$W && git commit -m x"
# O hook roda com HOME=$tmp.
check allow V2 "$MAIN" 'W=~/wt; cd $W && git commit -m x'
check allow V2 "$MAIN" 'cd $HOME/wt && git commit -m x'
check allow V2 "$MAIN" 'git -C ${HOME}/wt commit -m x'
check deny V2 "$FEAT" 'W=~/main; cd $W && git commit -m x'
# V3: variável que aponta para a main bloqueia, mesmo saindo de uma feature.
check deny V3 "$FEAT" "W=$MAIN; cd \$W && git commit -m x"
check deny V3 "$FEAT" "W=$MAIN; git -C \$W commit -m x"
check deny V3 "$FEAT" "W=$MAIN; cd \$W && git push"
# V4: diretório desconhecido bloqueia na dúvida; sem commit/push, não.
check deny V4 "$FEAT" 'cd $NAO_DEFINIDA && git commit -m x'
check deny V4 "$FEAT" 'W=$(pwd); cd $W && git commit -m x'
check deny V4 "$FEAT" 'W="$(pwd)"; cd "$W" && git commit -m x'
check deny V4 "$FEAT" 'W=`pwd`; git -C $W commit -m x'
check deny V4 "$FEAT" 'cd ${W:-x} && git commit -m x'
check deny V4 "$FEAT" 'cd $1 && git push'
check deny V4 "$FEAT" 'cd $NAO_DEFINIDA && cd sub && git commit -m x'
check allow V4 "$FEAT" 'cd $NAO_DEFINIDA && ls'
check allow V4 "$FEAT" "cd \$NAO_DEFINIDA; cd $WT && git commit -m x"
# V5: escopo.
check deny V5 "$MAIN" "W=$WT git -C \$W commit -m x"
check deny V5 "$MAIN" "(W=$WT); cd \$W && git commit -m x"
check deny V5 "$MAIN" "echo \"\$(W=$WT)\"; cd \$W && git commit -m x"
check allow V5 "$MAIN" "eval 'W=$WT'; cd \$W && git commit -m x"
check deny V5 "$MAIN" "W=$WT; cd '\$W' && git commit -m x"
check deny V5 "$MAIN" "W=$WT; cd \\\$W && git commit -m x"
check deny V5 "$MAIN" "W=$WT; unset W; cd \$W && git commit -m x"
check allow V5 "$MAIN" "(W=$WT; cd \$W && git commit -m x)"
# Shell filho só herda variáveis exportadas.
check deny V5 "$MAIN" "W=$WT; bash -c 'git -C \"\$W\" commit -m x'"
check deny V5 "$MAIN" $'W='"$WT"$'; bash <<\'EOF\'\ngit -C "$W" commit -m x\nEOF'
check allow V5 "$MAIN" "export W=$WT; bash -c 'git -C \"\$W\" commit -m x'"
check allow V5 "$MAIN" "W=$WT; export W; bash -c 'cd \$W && git commit -m x'"
check allow V5 "$MAIN" "W=$WT; (git -C \$W commit -m x)"

# Issue #24: aspas dentro do código de bash -c, eval e here-string (Q1 a Q5,
# da SPEC-24).
# Q1: valor citado antes do subcomando não esconde o commit.
check deny Q1 "$MAIN" 'sh -c "git -c user.name=\"t\" commit -m y"'
check deny Q1 "$MAIN" "bash -c 'git -c user.name=\"t\" commit -m y'"
check deny Q1 "$MAIN" "eval 'git -c user.name=\"t\" commit -m y'"
check deny Q1 "$MAIN" 'eval "git -c user.name=\"t\" commit -m y"'
check deny Q1 "$MAIN" "bash <<< 'git -c user.name=\"t\" commit -m y'"
check deny Q1 "$FEAT" "bash -c \"git -C \\\"$MAIN\\\" commit -m y\""
# Espaço escapado no início não pode se passar pelo marcador do texto extraído.
check deny Q1 "$MAIN" "\\ CEcd $WT; git commit -m y"
check deny Q1 "$MAIN" $'\\ CEcd '"$WT"$'\ngit commit -m y'
# Q2: as mesmas formas numa worktree de feature liberam.
check allow Q2 "$MAIN" "bash -c \"git -C \\\"$WT\\\" commit -m y\""
check allow Q2 "$MAIN" "bash -c 'git -C \"$WT\" commit -m y'"
check allow Q2 "$MAIN" "eval 'git -C \"$WT\" commit -m y'"
check allow Q2 "$MAIN" "bash <<< 'git -C \"$WT\" commit -m y'"
# Q3: aninhamento; acima de 4 níveis vale o modo de dúvida.
check deny Q3 "$MAIN" "bash -c \"bash -c 'git -c a=\\\"b\\\" commit -m y'\""
nested() {
  local c=$1 i t
  for (( i = 0; i < $2; i++ )); do
    t=${c//\\/\\\\} t=${t//\"/\\\"}
    c="bash -c \"$t\""
  done
  printf '%s' "$c"
}
check deny Q3 "$MAIN" "$(nested 'git -c a="b" commit -m y' 3)"
check deny Q3 "$MAIN" "$(nested 'git -c a="b" commit -m y' 6)"
check allow Q3 "$MAIN" "$(nested "git -C \"$WT\" commit -m y" 3)"
# Q4: texto continua sendo texto no shell filho; \$( chega ao filho como código.
check allow Q4 "$MAIN" "bash -c 'echo \"git commit -m x\"'"
check allow Q4 "$MAIN" 'bash -c "echo \"git push origin main\""'
check deny Q4 "$MAIN" 'bash -c "echo \$(git commit -m x)"'
# Q5: modo de dúvida.
check deny Q5 "$MAIN" 'git -c user.name="t" commit -m y; echo "x'
check deny Q5 "$MAIN" 'echo x | bash; git -c k="v" commit -m y'

# CA6: exceções do commit inicial e do primeiro push.
check allow CA6 "$EMPTY" 'git commit -m inicial'
check allow CA6 "$NEWREMOTE" 'git push -u origin main'

# Semântica do bash usada pelo hook: a atribuição como prefixo não vale
# para os argumentos do próprio comando.
total=$((total + 1))
if [[ $(bash -c 'W=a; W=b echo $W') == a ]]; then
  echo "ok      V5   bash: W=a; W=b echo \$W imprime a"
else
  failures=$((failures + 1)); echo "FALHOU  V5   bash: W=a; W=b echo \$W não imprimiu a"
fi

# Escapes entre aspas duplas, como o hook desfaz: \\ e \$ sim, \a não.
total=$((total + 1))
if [[ $(bash -c "printf '%s' \"a\\\\b\\\$c\\d\"") == 'a\b$c\d' ]]; then
  echo "ok      Q4   bash: escapes de aspas duplas"
else
  failures=$((failures + 1)); echo "FALHOU  Q4   bash: escapes de aspas duplas"
fi

echo
if (( failures )); then
  echo "$failures de $total casos falharam."
  exit 1
fi
echo "Todos os $total casos passaram."
