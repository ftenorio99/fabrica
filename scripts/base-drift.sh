#!/usr/bin/env bash
# Diz se a base de um PR avançou em arquivos que ele toca (SPEC-135). Usado
# pelo /fabrica:revisar (modo local) e pelo /fabrica:status (modo api). Só lê:
# não faz fetch, merge nem checkout, e não escreve na worktree nem no GitHub.
#
# Uso: base-drift.sh local [<base>]        (dentro da worktree; base: origin/main)
#      base-drift.sh api <dono>/<repo> <nº do PR>
#
# Imprime uma linha, em que <n> é o número de commits da base fora da branch:
#   em-dia
#   atras-sem-sobreposicao <n>
#   sobreposicao <n> <arquivo>...   arquivos mudados dos dois lados
#   conflito <n> <arquivo>...       arquivos em conflito (no modo api, os
#                                   mudados dos dois lados)
#
# Saídas: 0 classificado; 1 falha do git ou do gh; 2 uso errado.
set -uo pipefail
export LC_ALL=C.UTF-8

say() { echo "base-drift: $*" >&2; }

usage() {
  say "uso: base-drift.sh local [<base>] | base-drift.sh api <dono>/<repo> <nº do PR>"
  exit 2
}

fail() {
  say "$*"
  exit 1
}

# one_per_line: lista separada por NUL (stdin) em um caminho por linha, ordenada
# e sem repetição. Uma quebra de linha dentro de um nome vira "?", para a saída
# continuar com uma linha só.
one_per_line() { tr '\n\0' '?\n' | sed '/^$/d' | LC_ALL=C sort -u; }

# report <classe> <n> [lista, um arquivo por linha]
report() {
  local line="$1 $2" file
  if [[ -n ${3:-} ]]; then
    while IFS= read -r file; do
      line+=" $file"
    done <<<"$3"
  fi
  printf '%s\n' "$line"
}

local_mode() {
  local base=$1 ahead merge_base base_files head_files common tree_out status

  [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == true ]] || {
    say "o modo local roda dentro da worktree de um repositório git"
    exit 2
  }
  git rev-parse -q --verify "$base^{commit}" >/dev/null || fail "a base '$base' não existe"

  ahead=$(git rev-list --count "HEAD..$base") || fail "falha ao contar os commits de '$base'"
  if (( ahead == 0 )); then
    echo em-dia
    return
  fi

  merge_base=$(git merge-base HEAD "$base") || fail "HEAD e '$base' não têm base comum"

  tmp=$(mktemp -d) || fail "falha ao criar a pasta temporária"
  trap 'rm -rf "$tmp"' EXIT

  # O merge-tree sai com 0 sem conflito e com 1 com conflito; a saída é a árvore
  # e, com conflito, os arquivos conflitantes, separados por NUL.
  tree_out="$tmp/merge"
  git merge-tree --write-tree --name-only --no-messages -z HEAD "$base" >"$tree_out"
  status=$?
  case $status in
    0) ;;
    1)
      common=$(tail -z -n +2 "$tree_out" | one_per_line)
      report conflito "$ahead" "$common"
      return
      ;;
    *) fail "o git merge-tree falhou (saída $status)" ;;
  esac

  # --no-renames: um arquivo renomeado conta com o caminho antigo e o novo.
  base_files=$(git diff --no-renames --no-relative --name-only -z "$merge_base" "$base" | one_per_line) \
    || fail "falha no diff de '$base'"
  head_files=$(git diff --no-renames --no-relative --name-only -z "$merge_base" HEAD | one_per_line) \
    || fail "falha no diff da branch"
  common=$(LC_ALL=C comm -12 <(printf '%s\n' "$base_files") <(printf '%s\n' "$head_files") | sed '/^$/d')

  if [[ -n $common ]]; then
    report sobreposicao "$ahead" "$common"
  else
    report atras-sem-sobreposicao "$ahead"
  fi
}

# json <operação> <arquivo>: lê uma resposta do gh. Os nomes de arquivo saem
# separados por NUL.
json() {
  python3 -I -c '
import json, sys

op, path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)

def names(values):
    for value in values:
        if value:
            sys.stdout.buffer.write(value.encode("utf-8", "replace") + b"\0")

if op == "head" or op == "base":
    from urllib.parse import quote
    print(quote(data[op + "RefName"], safe="/"))
elif op == "mergeable":
    print(data["mergeable"])
elif op == "renamed":
    print(sum(f.get("changeType") == "RENAMED" for f in data["files"]))
elif op == "pr-files":
    names(f["path"] for f in data["files"])
elif op == "previous":
    names(f.get("previous_filename") for page in data for f in page)
elif op == "ahead":
    print(int(data["ahead_by"]))
elif op == "compare-files":
    names(f.get(k) for f in data.get("files") or [] for k in ("filename", "previous_filename"))
' "$@" 2>/dev/null
}

api_mode() {
  local repo=$1 pr=$2 head base mergeable renamed ahead pr_files base_files common

  tmp=$(mktemp -d) || fail "falha ao criar a pasta temporária"
  trap 'rm -rf "$tmp"' EXIT
  local unreadable="resposta ilegível do gh"

  gh pr view "$pr" -R "$repo" --json files,mergeable,baseRefName,headRefName >"$tmp/pr.json" \
    || fail "o gh pr view falhou"
  head=$(json head "$tmp/pr.json") || fail "$unreadable"
  base=$(json base "$tmp/pr.json") || fail "$unreadable"
  mergeable=$(json mergeable "$tmp/pr.json") || fail "$unreadable"
  renamed=$(json renamed "$tmp/pr.json") || fail "$unreadable"

  # Comparação invertida (head...base): o que a base mudou desde a base comum.
  gh api "repos/$repo/compare/$head...$base" >"$tmp/compare.json" || fail "o gh api compare falhou"
  ahead=$(json ahead "$tmp/compare.json") || fail "$unreadable"
  if (( ahead == 0 )); then
    echo em-dia
    return
  fi

  json pr-files "$tmp/pr.json" >"$tmp/pr-files" || fail "$unreadable"
  # O gh pr view não traz o caminho antigo de um arquivo renomeado.
  if (( renamed > 0 )); then
    gh api "repos/$repo/pulls/$pr/files" --paginate --slurp >"$tmp/renamed.json" \
      || fail "o gh api dos arquivos do PR falhou"
    json previous "$tmp/renamed.json" >>"$tmp/pr-files" || fail "$unreadable"
  fi
  json compare-files "$tmp/compare.json" >"$tmp/base-files" || fail "$unreadable"

  pr_files=$(one_per_line <"$tmp/pr-files")
  base_files=$(one_per_line <"$tmp/base-files")
  common=$(LC_ALL=C comm -12 <(printf '%s\n' "$base_files") <(printf '%s\n' "$pr_files") | sed '/^$/d')

  # UNKNOWN (o GitHub ainda não calculou) não conta como conflito.
  if [[ $mergeable == CONFLICTING ]]; then
    report conflito "$ahead" "$common"
  elif [[ -n $common ]]; then
    report sobreposicao "$ahead" "$common"
  else
    report atras-sem-sobreposicao "$ahead"
  fi
}

case ${1:-} in
  local)
    (( $# <= 2 )) || usage
    base=${2:-origin/main}
    [[ -n $base && $base != -* ]] || usage
    local_mode "$base"
    ;;
  api)
    (( $# == 3 )) || usage
    [[ $2 =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage
    [[ $3 =~ ^[1-9][0-9]*$ ]] || usage
    api_mode "$2" "$3"
    ;;
  *) usage ;;
esac
