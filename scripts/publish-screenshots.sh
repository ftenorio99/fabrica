#!/usr/bin/env bash
# Publica os screenshots das telas de uma issue na branch órfã fabrica-telas
# do próprio repositório e imprime a tabela da seção "## Telas" do PR
# (SPEC-129, ADR 0020).
#
# Uso: publish-screenshots.sh <dono/repo> <nº da issue> <sha do head> <pasta>
# Roda dentro de um clone com o remoto origin. Lê só os *.png do primeiro
# nível da pasta, com o nome <tela>--<estado>--<celular|computador>.png, e os
# grava em fabrica-telas:issue-<nº>/<sha curto>/, substituindo essa pasta e
# preservando as outras. Não toca a branch atual, o índice nem a cópia de
# trabalho: usa um índice temporário e os comandos de baixo nível do git.
#
# Saídas: 0 publicado, com a tabela no stdout; 1 erro do git; 2 argumentos
# errados; 3 nome de PNG fora do padrão; 4 pasta inexistente ou sem PNG;
# 5 push recusado nas 3 tentativas.
set -uo pipefail
export LC_ALL=C.UTF-8

branch=fabrica-telas
max_attempts=3
name_re='^[a-z0-9]+(-[a-z0-9]+)*--[a-z0-9]+(-[a-z0-9]+)*--(celular|computador)\.png$'

say() { echo "publish-screenshots: $*" >&2; }

usage() {
  say "uso: publish-screenshots.sh <dono/repo> <nº da issue> <sha do head> <pasta>"
  exit 2
}

(( $# == 4 )) || usage
repo=$1 issue=$2 head_sha=$3 dir=$4
[[ $repo =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage
[[ $issue =~ ^[1-9][0-9]*$ ]] || usage
[[ $head_sha =~ ^[0-9a-f]{7,64}$ ]] || usage
short=${head_sha:0:7}
prefix="issue-$issue/$short"

if [[ ! -d $dir ]]; then
  say "a pasta '$dir' não existe"
  exit 4
fi

files=() invalid=()
while IFS= read -r -d '' path; do
  name=${path##*/}
  if [[ $name =~ $name_re ]]; then
    files+=("$name")
  else
    invalid+=("$name")
  fi
done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.png' -print0 | sort -z)

if (( ${#invalid[@]} > 0 )); then
  say "nomes fora do padrão <tela>--<estado>--<celular|computador>.png:"
  printf '  %s\n' "${invalid[@]}" >&2
  exit 3
fi
if (( ${#files[@]} == 0 )); then
  say "a pasta '$dir' não tem nenhum PNG"
  exit 4
fi

git rev-parse --git-dir >/dev/null 2>&1 || { say "rode dentro de um clone do repositório"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_INDEX_FILE="$tmp/index"

# Os blobs não dependem da ponta da branch: grava uma vez só.
declare -A blobs
for name in "${files[@]}"; do
  blobs[$name]=$(git hash-object -w -- "$dir/$name") || { say "falha ao gravar $name"; exit 1; }
done

# build_commit <pai ou vazio>: monta o commit com a pasta desta publicação
# sobre a árvore do pai e imprime o SHA.
build_commit() {
  local parent=$1 name tree
  rm -f "$GIT_INDEX_FILE"
  if [[ -n $parent ]]; then
    git read-tree "$parent" || return 1
    git ls-files -z -- "$prefix/" | git update-index -z --force-remove --stdin || return 1
  else
    git read-tree --empty || return 1
  fi
  for name in "${files[@]}"; do
    git update-index --add --cacheinfo "100644,${blobs[$name]},$prefix/$name" || return 1
  done
  tree=$(git write-tree) || return 1
  if [[ -n $parent ]]; then
    git commit-tree "$tree" -p "$parent" -m "telas da issue #$issue no head $short"
  else
    git commit-tree "$tree" -m "telas da issue #$issue no head $short"
  fi
}

attempt=0 commit="" push_err=""
while (( attempt < max_attempts )); do
  attempt=$((attempt + 1))
  parent=""
  remote_line=$(git ls-remote origin "refs/heads/$branch") || { say "falha ao ler o remoto origin"; exit 1; }
  if [[ -n $remote_line ]]; then
    git fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" || { say "falha ao buscar a $branch"; exit 1; }
    parent=$(git rev-parse --verify -q "refs/remotes/origin/$branch^{commit}") || { say "falha ao ler a $branch"; exit 1; }
  fi
  commit=$(build_commit "$parent") || { say "falha ao montar o commit"; exit 1; }
  if push_err=$(git push -q origin "$commit:refs/heads/$branch" 2>&1); then
    break
  fi
  commit=""
  say "push recusado (tentativa $attempt de $max_attempts)"
done

if [[ -z $commit ]]; then
  say "o push da $branch foi recusado $max_attempts vezes:"
  printf '%s\n' "$push_err" >&2
  exit 5
fi

# Tabela: uma linha por par tela–estado, em ordem de tela e depois de estado.
declare -A have
pairs=()
for name in "${files[@]}"; do
  base=${name%.png}
  device=${base##*--}
  pair=${base%--*}
  [[ -n ${have[$pair]+x} ]] || pairs+=("$pair")
  have[$pair]=1
  have[$pair--$device]=1
done

url="https://github.com/$repo/raw/$commit/$prefix"
echo "Head \`$short\` · celular 390 × 844 (iPhone 12 Pro) · computador 1440 × 900 (Laptop L)"
echo
echo "| Tela | Estado | Celular | Computador |"
echo "|---|---|---|---|"
for pair in "${pairs[@]}"; do
  printf '%s\t%s\n' "${pair%%--*}" "${pair#*--}"
done | sort -t $'\t' -k1,1 -k2,2 | while IFS=$'\t' read -r screen state; do
  cells=()
  for device in celular computador; do
    if [[ -n ${have[$screen--$state--$device]+x} ]]; then
      cells+=("![$screen $state $device]($url/$screen--$state--$device.png)")
    else
      cells+=("falta")
    fi
  done
  echo "| $screen | $state | ${cells[0]} | ${cells[1]} |"
done
