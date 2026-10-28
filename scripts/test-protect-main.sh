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
}
setup || { echo "test-protect-main: falhou ao criar os repositórios de teste" >&2; exit 1; }

MAIN=$tmp/main FEAT=$tmp/feat EMPTY=$tmp/empty NEWREMOTE=$tmp/newremote
failures=0 total=0

# check <esperado: deny|allow> <CA> <cwd> <comando>
check() {
  local expected=$1 ca=$2 dir=$3 command=$4 got output label
  output=$(jq -n --arg c "$command" --arg d "$dir" '{tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>&1)
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
check allow CA5 "$MAIN" "git -C $FEAT push origin feat/x"
check allow CA5 "$MAIN" "cd $FEAT && git commit -m x"

# CA6: exceções do commit inicial e do primeiro push.
check allow CA6 "$EMPTY" 'git commit -m inicial'
check allow CA6 "$NEWREMOTE" 'git push -u origin main'

echo
if (( failures )); then
  echo "$failures de $total casos falharam."
  exit 1
fi
echo "Todos os $total casos passaram."
