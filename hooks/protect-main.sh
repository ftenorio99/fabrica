#!/usr/bin/env bash
# PreToolUse (Bash): bloqueia git commit e git push na main/master.
# Exceções: o primeiro commit de um repositório novo e o primeiro push
# da main quando ela ainda não existe no remoto.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
dir=$(jq -r '.cwd // ""' <<<"$input")

# Só interessa se o comando roda git commit ou git push.
grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|push)([[:space:]]|$)' <<<"$cmd" || exit 0

# Respeita um "cd <dir> &&" no início do comando.
if [[ $cmd =~ ^[[:space:]]*cd[[:space:]]+([^[:space:];\&]+) ]]; then
  target="${BASH_REMATCH[1]/#\~/$HOME}"
  [[ $target = /* ]] || target="$dir/$target"
  dir="$target"
fi
[ -d "$dir" ] || dir="$PWD"

git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || exit 0
branch=$(git -C "$dir" branch --show-current 2>/dev/null)

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

if grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit' <<<"$cmd" && [[ $branch == main || $branch == master ]]; then
  # Repositório sem nenhum commit: permite o commit inicial.
  git -C "$dir" rev-parse --verify -q HEAD >/dev/null || exit 0
  deny "Commit direto na '$branch' bloqueado pelas práticas do usuário. Crie uma branch (ex.: git switch -c feat/<n>-descricao) e abra um PR."
fi

if grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push' <<<"$cmd"; then
  push_args=$(sed -E 's/.*git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push//' <<<"$cmd")
  if grep -Eq '(^|[[:space:]:])(main|master)([[:space:]]|$)' <<<"$push_args" || [[ $branch == main || $branch == master ]]; then
    # main ainda não existe no remoto: permite o primeiro push.
    remote=$(git -C "$dir" remote | head -n1)
    [ -n "$remote" ] || exit 0
    git -C "$dir" ls-remote --exit-code --heads "$remote" main master >/dev/null 2>&1 || exit 0
    deny "Push para a main bloqueado pelas práticas do usuário. Faça push da sua branch e abra um PR (gh pr create)."
  fi
fi
exit 0
