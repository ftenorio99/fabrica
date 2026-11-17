#!/usr/bin/env bash
# Testes do contexto do checklist do sbx (scripts/sbx-context.sh), com projeto
# temporário. Os CAs são os da specs/SPEC-147.md. Os valores de GH_TOKEN são
# inventados, só no formato das expressões.
# Uso: scripts/test-sbx-context.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ctx="$script_dir/sbx-context.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0 total=0
check() { # check <descrição> <esperado> <obtido>
  total=$((total + 1))
  if [[ "$3" == "$2" ]]; then
    printf 'ok      %s\n' "$1"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3"
  fi
}

proj="$tmp/x/kairo"
signal="$tmp/sandbox-persistent.sh"
mkdir -p "$proj/src"
git -C "$proj" init -q

# run [VAR=valor...] -- <args>: roda o script num ambiente limpo, sem o sinal
# de VM e sem GH_TOKEN, a não ser pelas variáveis passadas.
run() {
  local vars=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do vars+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  env -u PROXY_CA_CERT_B64 -u GH_TOKEN FABRICA_SBX_PERSISTENT_FILE="$signal" "${vars[@]}" \
    bash "$ctx" "$@"
}
line() { run "${@:2}" | grep "^$1 "; }
code() { run "$@" >/dev/null 2>&1; echo $?; }

# CA1: arquivo de sinal presente.
touch "$signal"
check "CA1 com o arquivo de sinal" "onde vm" "$(line onde -- --project "$proj")"
rm -f "$signal"

# CA2: PROXY_CA_CERT_B64 sem o arquivo.
check "CA2 PROXY_CA_CERT_B64 não vazio" "onde vm" "$(line onde PROXY_CA_CERT_B64=abc -- --project "$proj")"
check "CA2 PROXY_CA_CERT_B64 vazio" "onde host" "$(line onde PROXY_CA_CERT_B64= -- --project "$proj")"
check "CA2 PROXY_CA_CERT_B64 indefinido" "onde host" "$(line onde -- --project "$proj")"

# CA3: nome pela pasta do topo, também numa subpasta.
check "CA3 nome com --project no topo" "nome claude-kairo" "$(line nome -- --project "$proj")"
check "CA3 nome com --project na subpasta" "nome claude-kairo" "$(line nome -- --project "$proj/src")"
check "CA3 nome rodando na subpasta" "nome claude-kairo" "$(cd "$proj/src" && line nome --)"

# CA4: formato do GH_TOKEN.
fake_classic="ghp_$(printf 'a%.0s' {1..36})"
check "CA4 GH_TOKEN indefinido" "token ausente" "$(line token -- --project "$proj")"
check "CA4 GH_TOKEN vazio" "token ausente" "$(line token GH_TOKEN= -- --project "$proj")"
check "CA4 GH_TOKEN clássico" "token real" "$(line token GH_TOKEN="$fake_classic" -- --project "$proj")"
check "CA4 GH_TOKEN fine-grained" "token real" "$(line token GH_TOKEN=github_pat_inventado -- --project "$proj")"
check "CA4 GH_TOKEN curto demais" "token marcador" "$(line token GH_TOKEN=ghp_curto -- --project "$proj")"
check "CA4 GH_TOKEN marcador" "token marcador" "$(line token GH_TOKEN=sbx-proxy-marcador -- --project "$proj")"

# CA5: alvo e2e no Makefile.
check "CA5 sem Makefile" "e2e não" "$(line e2e -- --project "$proj")"
printf 'test:\n\techo t\n' >"$proj/Makefile"
check "CA5 Makefile sem e2e" "e2e não" "$(line e2e -- --project "$proj")"
printf 'test-e2e:\n\techo t\nlint: # roda antes do e2e:\n\techo l\n' >"$proj/Makefile"
check "CA5 test-e2e e e2e no meio da linha" "e2e não" "$(line e2e -- --project "$proj")"
printf 'test:\n\techo t\ne2e: build\n\techo e\n' >"$proj/Makefile"
check "CA5 Makefile com e2e:" "e2e sim" "$(line e2e -- --project "$proj")"
check "CA5 e2e lido do topo, na subpasta" "e2e sim" "$(line e2e -- --project "$proj/src")"

# CA6: quatro linhas, na ordem, e erros de uso.
check "CA6 ordem das linhas" "onde nome token e2e" "$(run -- --project "$proj" | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
check "CA6 saída 0" "0" "$(code -- --project "$proj")"
check "CA6 fora de repositório git" "1" "$(cd "$tmp" && code --)"
outside_err="$(cd "$tmp" && run -- 2>&1 >/dev/null)"
check "CA6 mensagem fora de repositório" "sim" "$([[ "$outside_err" == *'não estou num repositório git'* ]] && echo sim || echo não)"
check "CA6 --project inexistente" "1" "$(code -- --project "$tmp/nao-existe")"
check "CA6 opção desconhecida" "1" "$(code -- --check)"
check "CA6 --project sem diretório" "1" "$(code -- --project)"

# CA7: não roda sbx e não grava nada.
fakebin="$tmp/bin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\ntouch %q\n' "$tmp/sbx-chamado" >"$fakebin/sbx"
chmod +x "$fakebin/sbx"
touch "$signal"
before="$(cd "$tmp" && find . -path ./sbx-chamado -prune -o -print | sort)"
PATH="$fakebin:$PATH" run GH_TOKEN=sbx-proxy-marcador -- --project "$proj" >/dev/null 2>&1
after="$(cd "$tmp" && find . -path ./sbx-chamado -prune -o -print | sort)"
check "CA7 sbx não é chamado" "não" "$([[ -e "$tmp/sbx-chamado" ]] && echo sim || echo não)"
check "CA7 nenhum arquivo novo" "$before" "$after"
rm -f "$signal"

echo
echo "$((total - failures))/$total passaram"
[[ $failures -eq 0 ]]
