#!/usr/bin/env bash
# Uma worktree por issue em <clone>/.worktrees/<nº> (SPEC-182, ADR 0014).
#
# Uso:
#   issue-worktree.sh ensure <nº> <branch>  -> cria ou reusa; caminho na última linha
#   issue-worktree.sh clean                 -> remove as worktrees de PR fechado e limpas
#   issue-worktree.sh list                  -> "<nº> <branch> <caminho>", sem gh
#
# <clone> é a worktree principal do repositório, a mesma rodando no clone ou
# dentro de uma worktree. Variável FABRICA_GH_BIN (padrão gh) troca o gh nos
# testes.
#
# Saídas do ensure: 0 pronto; 1 erro do git; 2 uso inválido; 3 a pasta da
# issue está em outra branch; 4 a branch está em uso noutra pasta; 5 limite
# de 3 worktrees de issue. Saídas do clean: 0 feito; 1 o gh falhou e nada
# foi removido.
set -uo pipefail
export LC_ALL=C.UTF-8

gh_bin="${FABRICA_GH_BIN:-gh}"
max_worktrees=3

say() { echo "issue-worktree: $*" >&2; }

usage() {
  say "uso: issue-worktree.sh ensure <nº> <branch> | clean | list"
  exit 2
}

# Linhas "<caminho>\t<branch curta ou ->" de cada worktree registrada; a
# primeira é a worktree principal.
worktree_rows() {
  git worktree list --porcelain | awk '
    /^worktree / { if (p != "") print p "\t" b; p = substr($0, 10); b = "-" }
    /^branch refs\/heads\// { b = substr($0, 19) }
    END { if (p != "") print p "\t" b }
  '
}

clone="$(worktree_rows 2>/dev/null | head -n 1 | cut -f 1)"
[[ -n $clone ]] || { say "não estou dentro de um repositório git."; exit 1; }
base="$clone/.worktrees"

# Branch registrada na pasta, ou vazio se a pasta não é worktree.
branch_of() {
  worktree_rows | awk -F'\t' -v p="$1" '$1 == p { print $2; found = 1 } END { exit !found }'
}

# Linhas "<nome>\t<branch>\t<caminho>" das worktrees registradas em <clone>/.worktrees/.
issue_rows() {
  worktree_rows | awk -F'\t' -v b="$base/" '
    index($1, b) == 1 { name = substr($1, length(b) + 1); if (name !~ /\//) print name "\t" $2 "\t" $1 }
  '
}

ensure_exclude() {
  local exclude
  exclude="$(git -C "$clone" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  mkdir -p "${exclude%/*}"
  grep -qxF '/.worktrees/' "$exclude" 2>/dev/null || echo '/.worktrees/' >>"$exclude"
}

# Copia do clone os arquivos ignorados que casam com o .worktreeinclude.
copy_included() {
  local wt=$1 file
  [[ -f $clone/.worktreeinclude ]] || return 0
  while IFS= read -r -d '' file; do
    [[ $file == .worktrees/* ]] && continue
    mkdir -p "$wt/$(dirname "$file")"
    cp -p "$clone/$file" "$wt/$file" || say "não consegui copiar $file."
  done < <(git -C "$clone" ls-files -z --others --ignored --exclude-from=.worktreeinclude |
    git -C "$clone" check-ignore -z --stdin)
}

cmd_ensure() {
  local n=${1:-} branch=${2:-}
  [[ $# -eq 2 && $n =~ ^[1-9][0-9]*$ && -n $branch ]] || usage
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || usage
  local wt="$base/$n" current other count busy

  if current="$(branch_of "$wt")"; then
    if [[ $current == "$branch" ]]; then
      echo "$wt"
      return 0
    fi
    say "a worktree $wt está na branch '$current', e não em '$branch'. Confira a issue e a branch."
    return 3
  fi
  if [[ -e $wt ]]; then
    say "a pasta $wt existe e não é uma worktree do git. Remova-a ou mova-a e repita."
    return 3
  fi

  other="$(worktree_rows | awk -F'\t' -v b="$branch" '$2 == b { print $1; exit }')"
  if [[ -n $other ]]; then
    say "a branch '$branch' está em uso em $other. Troque essa pasta de branch (ex.: git -C $other switch main) e repita."
    return 4
  fi

  count="$(issue_rows | awk -F'\t' '$1 ~ /^[0-9]+$/' | wc -l)"
  if (( count >= max_worktrees )); then
    busy="$(issue_rows | awk -F'\t' '$1 ~ /^[0-9]+$/ { printf "%s#%s (%s)", sep, $1, $2; sep = ", " }')"
    say "já há $count worktrees de issue neste clone: $busy. A fábrica aceita $max_worktrees; termine uma antes."
    return 5
  fi

  ensure_exclude
  mkdir -p "$base"
  if git -C "$clone" show-ref -q --verify "refs/heads/$branch"; then
    git -C "$clone" worktree add -q --relative-paths "$wt" "$branch" >&2 || return 1
  else
    git -C "$clone" fetch -q origin >&2 || say "o git fetch falhou; sigo com as referências locais."
    if git -C "$clone" show-ref -q --verify "refs/remotes/origin/$branch"; then
      git -C "$clone" worktree add -q --relative-paths --track -b "$branch" "$wt" "origin/$branch" >&2 || return 1
    else
      git -C "$clone" worktree add -q --relative-paths --no-track -b "$branch" "$wt" origin/main >&2 || return 1
    fi
  fi
  copy_included "$wt"
  echo "$wt"
}

cmd_clean() {
  [[ $# -eq 0 ]] || usage
  local entry name branch path json pr state oid
  local -a names=() branches=() paths=() prs=()

  # Primeiro lê o PR de todas; se o gh falhar em qualquer uma, nada é removido.
  if [[ -d $base ]]; then
    for entry in "$base"/*/ "$base"/.[!.]*/; do
      [[ -d $entry ]] || continue
      path="${entry%/}"
      name="${path##*/}"
      if ! branch="$(branch_of "$path")" || [[ $branch == - ]]; then
        echo "mantida $name - desconhecida"
        continue
      fi
      json="$(cd "$clone" && "$gh_bin" pr list --head "$branch" --state all --json number,state,headRefOid)" || {
        say "o gh falhou ao ler o PR da branch '$branch'; nenhuma worktree foi removida."
        return 1
      }
      pr="$(jq -r 'if length == 0 then "NONE -" else (max_by(.number) | "\(.state) \(.headRefOid)") end' <<<"$json")" || {
        say "resposta inesperada do gh para a branch '$branch'; nenhuma worktree foi removida."
        return 1
      }
      names+=("$name") branches+=("$branch") paths+=("$path") prs+=("$pr")
    done
  fi

  local i
  for i in "${!names[@]}"; do
    name=${names[i]} branch=${branches[i]} path=${paths[i]}
    read -r state oid <<<"${prs[i]}"
    if [[ $state != MERGED && $state != CLOSED ]]; then
      echo "mantida $name $branch em-andamento"
      continue
    fi
    if [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]] ||
      ! git -C "$path" merge-base --is-ancestor HEAD "$oid" 2>/dev/null; then
      echo "mantida $name $branch trabalho-local"
      continue
    fi
    if git -C "$clone" worktree remove "$path" >&2 && git -C "$clone" branch -q -D "$branch" >&2; then
      echo "removida $name $branch"
    else
      echo "mantida $name $branch erro"
    fi
  done
  git -C "$clone" worktree prune
  return 0
}

cmd_list() {
  [[ $# -eq 0 ]] || usage
  issue_rows | awk -F'\t' '{ print $1 " " $2 " " $3 }'
}

sub=${1:-}
shift || true
case $sub in
  ensure) cmd_ensure "$@" ;;
  clean) cmd_clean "$@" ;;
  list) cmd_list "$@" ;;
  *) usage ;;
esac
