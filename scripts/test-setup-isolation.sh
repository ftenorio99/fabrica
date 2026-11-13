#!/usr/bin/env bash
# Testes do modo de isolamento (scripts/setup-isolation.sh), com projeto
# temporário. Os CAs são os da specs/SPEC-141.md.
# Uso: scripts/test-setup-isolation.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$script_dir/setup-isolation.sh"

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

proj="$tmp/proj"
file="$proj/.fabrica/isolamento.txt"
settings="$proj/.claude/settings.json"
warning="setup-isolation: sandbox nativo ligado em .claude/settings.json"

reset_env() {
  rm -rf "$proj"
  mkdir -p "$proj"
  git -C "$proj" init -q
}
run() { bash "$setup" --project "$proj" "$@"; }
# out <args>: stdout e código, sem stderr. err <args>: só stderr.
out() { local o c; o="$(run "$@" 2>/dev/null)"; c=$?; printf '%s|%s' "$o" "$c"; }
err() { run "$@" 2>&1 >/dev/null; }
# Conteúdo do arquivo com as quebras de linha visíveis.
content() { od -An -c "$file" | tr -s ' ' | sed 's/^ //'; }
exists() { [[ -e "$1" ]] && echo sim || echo não; }

# CA1: sem o arquivo.
reset_env
check "CA1 --check sem o arquivo" "ausente|0" "$(out --check)"
check "CA1 sem opção vale --check" "ausente|0" "$(out)"
check "CA1 --check não cria .fabrica" "não" "$(exists "$proj/.fabrica")"

# CA2: --set grava e --check lê.
for mode in sbx sem-sandbox; do
  reset_env
  check "CA2 --set $mode sem .fabrica" "gravado $mode|0" "$(out --set "$mode")"
  check "CA2 conteúdo exato de $mode" "$(printf '%s\n' "$mode" | od -An -c | tr -s ' ' | sed 's/^ //')" "$(content)"
  check "CA2 --check depois de --set $mode" "$mode|0" "$(out --check)"
done

# CA3: mesmo modo não regrava.
reset_env
run --set sbx >/dev/null
touch -d '2001-01-01 00:00:00' "$file"
before="$(stat -c %Y "$file")"
check "CA3 --set no mesmo modo" "ok sbx|0" "$(out --set sbx)"
check "CA3 conteúdo igual" "s b x \n" "$(content)"
check "CA3 data de modificação igual" "$before" "$(stat -c %Y "$file")"

# CA4: troca de modo e arquivo inválido são sobrescritos.
reset_env
run --set sbx >/dev/null
check "CA4 --set sem-sandbox sobre sbx" "gravado sem-sandbox|0" "$(out --set sem-sandbox)"
check "CA4 --check depois da troca" "sem-sandbox|0" "$(out --check)"
printf 'docker\n' >"$file"
check "CA4 --set sbx sobre inválido" "gravado sbx|0" "$(out --set sbx)"
check "CA4 conteúdo depois do inválido" "s b x \n" "$(content)"

# CA5: comentários, linhas vazias e espaços.
reset_env
mkdir -p "$proj/.fabrica"
printf '# modo do projeto\n\n  sbx  \n' >"$file"
check "CA5 comentário, linha vazia e espaços" "sbx|0" "$(out --check)"
printf '   # comentário com espaços antes\n\tsem-sandbox\t\nsbx\n' >"$file"
check "CA5 vale a primeira linha de modo" "sem-sandbox|0" "$(out --check)"
printf 'sbx' >"$file"
check "CA5 sem quebra de linha no fim" "sbx|0" "$(out --check)"

# CA6: arquivo inválido.
: >"$file"
check "CA6 arquivo vazio" "inválido|0" "$(out --check)"
printf '# só comentário\n\n' >"$file"
check "CA6 só comentários" "inválido|0" "$(out --check)"
printf 'SBX\n' >"$file"
check "CA6 maiúsculas" "inválido|0" "$(out --check)"
printf 'docker\n' >"$file"
check "CA6 outro valor" "inválido|0" "$(out --check)"
printf 'docker\nsbx\n' >"$file"
check "CA6 primeira linha inválida, mesmo com modo depois" "inválido|0" "$(out --check)"

# CA7: uso inválido não cria nem altera o arquivo.
reset_env
check "CA7 --set docker" "|1" "$(out --set docker)"
check "CA7 --set docker: mensagem" "sim" "$([[ -n "$(err --set docker)" ]] && echo sim || echo não)"
check "CA7 --set sem valor" "|1" "$(out --set)"
check "CA7 --check --set sbx" "|1" "$(out --check --set sbx)"
check "CA7 --set sbx --check" "|1" "$(out --set sbx --check)"
check "CA7 opção desconhecida" "|1" "$(out --force)"
check "CA7 opção desconhecida: mensagem" "sim" "$([[ -n "$(err --force)" ]] && echo sim || echo não)"
check "CA7 nada criado" "não" "$(exists "$proj/.fabrica")"
msg() { [[ -n "$(err "$@")" ]] && echo sim || echo não; }
check "CA7 --set sem valor: mensagem" "sim" "$(msg --set)"
check "CA7 --check --set sbx: mensagem" "sim" "$(msg --check --set sbx)"
check "CA7 nada criado depois das mensagens" "não" "$(exists "$proj/.fabrica")"
run --set sbx >/dev/null
check "CA7 --set docker não altera o arquivo" "|1 s b x \n" "$(out --set docker) $(content)"
check "CA7 --set sem valor não altera o arquivo" "|1 s b x \n" "$(out --set) $(content)"
check "CA7 --check --set sem-sandbox não altera o arquivo" "|1 s b x \n" "$(out --check --set sem-sandbox) $(content)"
check "CA7 opção desconhecida não altera o arquivo" "|1 s b x \n" "$(out --force --set sem-sandbox) $(content)"

# CA8: sem projeto.
mkdir -p "$tmp/fora"
check "CA8 fora de repositório git, sem --project" "|1" "$(cd "$tmp/fora" && o="$(GIT_CEILING_DIRECTORIES="$tmp" bash "$setup" --check 2>/dev/null)"; printf '%s|%s' "$o" "$?")"
check "CA8 fora de repositório git: mensagem" "sim" "$([[ -n "$(cd "$tmp/fora" && GIT_CEILING_DIRECTORIES="$tmp" bash "$setup" --check 2>&1 >/dev/null)" ]] && echo sim || echo não)"
check "CA8 --project inexistente" "|1" "$(o="$(bash "$setup" --project "$tmp/nao-existe" --check 2>/dev/null)"; printf '%s|%s' "$o" "$?")"
check "CA8 --project inexistente: mensagem" "sim" "$([[ -n "$(bash "$setup" --project "$tmp/nao-existe" --check 2>&1 >/dev/null)" ]] && echo sim || echo não)"
check "CA8 --project sem diretório" "|1" "$(o="$(bash "$setup" --project 2>/dev/null)"; printf '%s|%s' "$o" "$?")"
reset_env
check "CA8 sem --project, dentro do repositório" "ausente|0" "$(cd "$proj" && o="$(bash "$setup" 2>/dev/null)"; printf '%s|%s' "$o" "$?")"

# CA9: aviso do sandbox nativo.
reset_env
mkdir -p "$proj/.claude"
printf '{"sandbox": {"enabled": true, "network": {"allowedDomains": ["github.com"]}}}\n' >"$settings"
cp "$settings" "$tmp/settings-antes.json"
check "CA9 --check com o nativo: saída e código" "ausente|0" "$(out --check)"
check "CA9 --check com o nativo: aviso" "$warning" "$(err --check)"
check "CA9 --set com o nativo: saída e código" "gravado sbx|0" "$(out --set sbx)"
check "CA9 --set com o nativo: aviso" "$warning" "$(err --set sbx)"
check "CA9 settings idêntico" "igual" "$(cmp -s "$settings" "$tmp/settings-antes.json" && echo igual || echo diferente)"
printf '{"sandbox": {"enabled": false}}\n' >"$settings"
check "CA9 enabled: false, sem aviso" "sbx|0|" "$(out --check)|$(err --check)"
printf '{"sandbox": {"enabled": "true"}}\n' >"$settings"
check "CA9 enabled como texto, sem aviso" "sbx|0|" "$(out --check)|$(err --check)"
printf '{"permissions": {"deny": []}}\n' >"$settings"
check "CA9 sem bloco sandbox, sem aviso" "sbx|0|" "$(out --check)|$(err --check)"
printf '{"sandbox": tru' >"$settings"
cp "$settings" "$tmp/settings-antes.json"
check "CA9 JSON inválido, sem aviso nem erro" "sbx|0|" "$(out --check)|$(err --check)"
check "CA9 JSON inválido no --set" "ok sbx|0|" "$(out --set sbx)|$(err --set sbx)"
check "CA9 settings inválido idêntico" "igual" "$(cmp -s "$settings" "$tmp/settings-antes.json" && echo igual || echo diferente)"
printf '[1, 2]\n' >"$settings"
check "CA9 JSON que não é objeto, sem aviso nem erro" "sbx|0|" "$(out --check)|$(err --check)"
rm -rf "$proj/.claude"
check "CA9 sem settings, sem aviso" "sbx|0|" "$(out --check)|$(err --check)"

echo
echo "$((total - failures))/$total"
[[ $failures -eq 0 ]]
