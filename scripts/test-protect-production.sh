#!/usr/bin/env bash
# Testa o hook hooks/protect-production.sh com repositórios locais, sem rede:
# um remoto vazio (git init --bare) com o .fabrica/producao.txt no main e um
# clone, alimentando o hook com a entrada JSON do PreToolUse.
# Uso: scripts/test-protect-production.sh [caminho do hook]
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$(realpath "${1:-$script_dir/../hooks/protect-production.sh}")"
[[ -f "$hook" ]] || { echo "test-protect-production: hook não encontrado em $hook" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Isola a configuração global do git numa pasta de teste.
unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDE_PROJECT_DIR
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name teste
git config --global user.email teste@exemplo.com
git config --global init.defaultBranch main

failures=0 total=0

# result <ok: 0|1> <CA> <descrição>
result() {
  total=$((total + 1))
  if (( $1 == 0 )); then
    printf 'ok      %-4s %s\n' "$2" "$3"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n' "$2" "$3"
  fi
}

# run <cwd> <comando>: grava a saída em $out e o código em $code.
run() {
  out=$(jq -n --arg c "$2" --arg d "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$hook" 2>"$tmp/stderr")
  code=$?
}

# denied <CA> <cwd> <comando> [padrão esperado no motivo]
denied() {
  run "$2" "$3"
  local ok=1
  if (( code == 0 )) && [[ $(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out" 2>/dev/null) == deny ]]; then
    ok=0
    [[ -n ${4:-} && $(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$out") != *"\`$4\`"* ]] && ok=1
  fi
  result $ok "$1" "nega: $3"
}

# allowed <CA> <cwd> <comando>
allowed() {
  run "$2" "$3"
  local ok=1
  (( code == 0 )) && [[ -z $out ]] && ok=0
  result $ok "$1" "deixa passar: $3"
}

# Remoto com o arquivo de padrões no main, e um clone dele.
remote="$tmp/remote.git" work="$tmp/work"
git init -q --bare "$remote"
git clone -q "$remote" "$tmp/seed" 2>/dev/null
mkdir -p "$tmp/seed/.fabrica"
cat >"$tmp/seed/.fabrica/producao.txt" <<'TXT'
# Padrões de produção do projeto de teste
host db.prod.exemplo
host *.api.exemplo

texto sk_live_
   texto   PROD_DATABASE_URL
texto abc
host
banco db.outro.exemplo
TXT
git -C "$tmp/seed" add -A
git -C "$tmp/seed" commit -q -m "padrões"
git -C "$tmp/seed" push -q origin main 2>/dev/null
git clone -q "$remote" "$work" 2>/dev/null
mkdir -p "$work/sub"

# CA1: host e texto negados, sem diferenciar maiúsculas; o resto passa.
denied CA1 "$work" "psql postgres://u@DB.PROD.exemplo/x" "db.prod.exemplo"
denied CA1 "$work" "echo sk_live_abc" "sk_live_"
denied CA1 "$work" "printenv prod_database_url" "PROD_DATABASE_URL"
denied CA1 "$work/sub" "curl https://db.prod.exemplo" "db.prod.exemplo"
allowed CA1 "$work" "make test"
[[ $(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$(jq -n --arg c 'echo sk_live_x' --arg d "$work" '{tool_input: {command: $c}, cwd: $d}' | bash "$hook")") == *".fabrica/producao.txt"* ]]
result $? CA1 "o motivo cita o arquivo de padrões"

# CA2: apagar o padrão na cópia de trabalho não libera; padrão novo local vale.
grep -v 'db.prod.exemplo' "$work/.fabrica/producao.txt" >"$tmp/p" && mv "$tmp/p" "$work/.fabrica/producao.txt"
denied CA2 "$work" "psql postgres://db.prod.exemplo" "db.prod.exemplo"
rm "$work/.fabrica/producao.txt"
denied CA2 "$work" "echo sk_live_abc (sem o arquivo local)" "sk_live_"
git -C "$work" checkout -q -- .fabrica/producao.txt
echo "texto homolog-nao" >>"$work/.fabrica/producao.txt"
denied CA2 "$work" "curl homolog-nao.exemplo" "homolog-nao"
git -C "$work" checkout -q -- .fabrica/producao.txt

# CA2: o branch padrão vem de origin/HEAD; sem ele, origin/main.
git -C "$work" remote set-head origin -d 2>/dev/null
rm "$work/.fabrica/producao.txt"
denied CA2 "$work" "echo sk_live_ (sem origin/HEAD nem arquivo local)" "sk_live_"
git -C "$work" checkout -q -- .fabrica/producao.txt

# CA3: fora do git, repositório sem arquivo, sem origin.
mkdir -p "$tmp/solto"
allowed CA3 "$tmp/solto" "echo sk_live_abc"
git init -q "$tmp/vazio"
allowed CA3 "$tmp/vazio" "echo sk_live_abc"
git init -q "$tmp/local"
mkdir -p "$tmp/local/.fabrica"
echo "texto segredo-local" >"$tmp/local/.fabrica/producao.txt"
denied CA3 "$tmp/local" "echo segredo-local" "segredo-local"
allowed CA3 "$tmp/local" "echo outro"
run "$tmp/solto" ""
(( code == 0 )) && [[ -z $out ]]
result $? CA3 "comando vazio passa sem saída"
out=$(jq -n --arg c 'echo sk_live_x' '{tool_input: {command: $c}}' | CLAUDE_PROJECT_DIR="$work" bash "$hook")
[[ $(jq -r '.hookSpecificOutput.permissionDecision' <<<"$out" 2>/dev/null) == deny ]]
result $? CA3 "sem cwd na entrada, usa o CLAUDE_PROJECT_DIR"

# CA4: comentário, padrão curto, linha sem valor e tipo desconhecido não barram.
allowed CA4 "$work" "echo Padrões de produção do projeto de teste"
allowed CA4 "$work" "echo abc"
allowed CA4 "$work" "ping db.outro.exemplo"
allowed CA4 "$work" "echo host"
denied CA4 "$work" "curl https://v1.API.exemplo/status" "*.api.exemplo"
allowed CA4 "$work" "curl https://api.exemplo.com.br"

echo
echo "$((total - failures))/$total casos passaram."
(( failures == 0 ))
