#!/usr/bin/env bash
# Testes da instalação do sandbox (scripts/setup-sandbox.sh), com HOME,
# CLAUDE_CONFIG_DIR e projeto temporários. Não toca no settings.json real.
# Uso: scripts/test-setup-sandbox.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$script_dir/setup-sandbox.sh"

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

# jq <arquivo> <expressão python sobre d>: imprime o resultado.
jget() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

reset_env() {
  rm -rf "$tmp/home" "$tmp/proj"
  export HOME="$tmp/home" CLAUDE_CONFIG_DIR="$tmp/home/.claude"
  mkdir -p "$HOME" "$tmp/proj"
}
user="$tmp/home/.claude/settings.json"
proj="$tmp/proj/.claude/settings.json"
run() { bash "$setup" --project "$tmp/proj" "$@"; }

# CA1: projeto e HOME vazios.
reset_env
check "CA1 --check sem nada" "ausente" "$(run --check)"
check "CA1 instala" "instalado" "$(run)"
check "CA1 projeto: enabled" "True" "$(jget "$proj" 'd["sandbox"]["enabled"]')"
check "CA1 projeto: allowUnsandboxedCommands" "False" "$(jget "$proj" 'd["sandbox"]["allowUnsandboxedCommands"]')"
check "CA1 projeto: domínios" "['github.com', 'api.github.com', 'codeload.github.com', 'uploads.github.com', '*.githubusercontent.com', 'registry.npmjs.org']" "$(jget "$proj" 'd["sandbox"]["network"]["allowedDomains"]')"
check "CA1 projeto: cache do npm gravável" "['~/.npm']" "$(jget "$proj" 'd["sandbox"]["filesystem"]["allowWrite"]')"
check "CA1 projeto: allowLocalBinding" "True" "$(jget "$proj" 'd["sandbox"]["network"]["allowLocalBinding"]')"
check "CA1 projeto: arquivos negados" "['~/.ssh', '.env', '.env.local', '.env.development', '.env.test', '.env.production']" "$(jget "$proj" '[f["path"] for f in d["sandbox"]["credentials"]["files"] if f["mode"]=="deny"]')"
check "CA1 projeto: variáveis negadas" "['GH_TOKEN', 'GITHUB_TOKEN']" "$(jget "$proj" '[v["name"] for v in d["sandbox"]["credentials"]["envVars"] if v["mode"]=="deny"]')"
check "CA1 usuário: tlsTerminate" "{}" "$(jget "$user" 'd["sandbox"]["network"]["tlsTerminate"]')"
check "CA1 usuário: mask do hosts.yml" "mask ['api.github.com', 'github.com'] deny True" "$(jget "$user" '" ".join(map(str,[(f:=d["sandbox"]["credentials"]["files"][0])["mode"], f["injectHosts"], f["onExtractNoMatch"], f["maskDuplicates"]]))')"
check "CA1 usuário: extract" 'oauth_token:\s*(\S+)' "$(jget "$user" 'd["sandbox"]["credentials"]["files"][0]["extract"]')"
check "CA1 usuário: path" "~/.config/gh/hosts.yml" "$(jget "$user" 'd["sandbox"]["credentials"]["files"][0]["path"]')"
check "CA1 sem .bak-fabrica quando o settings não existia" "não" "$([[ -f "$user.bak-fabrica" ]] && echo sim || echo não)"
check "CA4 --check depois de instalar" "ok" "$(run --check)"

# CA2: settings existentes são preservados.
reset_env
mkdir -p "$tmp/proj/.claude" "$tmp/home/.claude"
cat >"$proj" <<'EOF'
{"permissions": {"deny": ["Read(.env)", "Read(//**/.ssh/**)"]}, "sandbox": {"network": {"allowedDomains": ["api.github.com", "example.org"]}}}
EOF
cat >"$user" <<'EOF'
{"statusLine": {"type": "command", "command": "/x/statusline.sh"}, "theme": "dark"}
EOF
cp "$user" "$tmp/user-antes.json"
run >/dev/null
check "CA2 preserva permissions.deny do projeto" "['Read(.env)', 'Read(//**/.ssh/**)']" "$(jget "$proj" 'd["permissions"]["deny"]')"
check "CA2 soma domínios sem repetir" "['api.github.com', 'example.org', 'github.com', 'codeload.github.com', 'uploads.github.com', '*.githubusercontent.com', 'registry.npmjs.org']" "$(jget "$proj" 'd["sandbox"]["network"]["allowedDomains"]')"
check "CA2 preserva statusLine e theme do usuário" "/x/statusline.sh dark" "$(jget "$user" 'd["statusLine"]["command"]+" "+d["theme"]')"
check "CA2 .bak-fabrica igual ao settings anterior" "igual" "$(cmp -s "$user.bak-fabrica" "$tmp/user-antes.json" && echo igual || echo diferente)"

# CA3: segunda execução não muda nada; domínio acrescentado pelo repositório fica.
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["network"]["allowedDomains"].append("api.stripe.com"); json.dump(d,open(p,"w"),indent=2)' "$proj"
hash_before="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
out="$(run)"
hash_after="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
check "CA3 segunda execução responde ok" "ok" "$out"
check "CA3 segunda execução não muda os arquivos" "$hash_before" "$hash_after"
check "CA3 domínio do repositório continua" "True" "$(jget "$proj" '"api.stripe.com" in d["sandbox"]["network"]["allowedDomains"]')"

# CA4: incompleto quando falta ou diverge uma chave; --check não grava.
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["enabled"]=False; d["sandbox"]["network"]["allowedDomains"].remove("registry.npmjs.org"); json.dump(d,open(p,"w"),indent=2)' "$proj"
hash_before="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
check "CA4 --check incompleto" "incompleto enabled=false sandbox.network.allowedDomains:registry.npmjs.org" "$(run --check)"
check "CA4 --check não grava" "$hash_before" "$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["credentials"]["files"][0]["mode"]="allow"; json.dump(d,open(p,"w"),indent=2)' "$user"
check "CA4 --check aponta credencial divergente" "incompleto enabled=false sandbox.network.allowedDomains:registry.npmjs.org credentials:~/.config/gh/hosts.yml" "$(run --check)"
run >/dev/null
check "CA4 instalar corrige o escalar" "True" "$(jget "$proj" 'd["sandbox"]["enabled"]')"
check "CA4 instalar não duplica a credencial existente" "1" "$(jget "$user" 'len(d["sandbox"]["credentials"]["files"])')"

# CA5: JSON inválido em qualquer um dos dois não grava nada.
for broken in proj user; do
  reset_env
  mkdir -p "$tmp/proj/.claude" "$tmp/home/.claude"
  echo '{"theme": "dark"}' >"$user"
  echo '{"permissions": {}}' >"$proj"
  if [[ $broken == proj ]]; then echo '{ quebrado' >"$proj"; target="$proj"; else echo '{ quebrado' >"$user"; target="$user"; fi
  hash_before="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
  err="$(run 2>&1 >/dev/null)"
  code=$?
  check "CA5 $broken inválido: código 1" "1" "$code"
  check "CA5 $broken inválido: mensagem" "setup-sandbox: JSON inválido em $target" "$err"
  check "CA5 $broken inválido: nada muda" "$hash_before" "$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
done

# Opção desconhecida.
bash "$setup" --xyz >/dev/null 2>&1
check "opção desconhecida: código 1" "1" "$?"

# Escrita negada no settings do usuário: código 2 e o comando com !.
reset_env
mkdir -p "$tmp/home/.claude"
chmod a-w "$tmp/home/.claude"
err="$(run 2>&1 >/dev/null)"
code=$?
chmod u+w "$tmp/home/.claude"
check "escrita negada: código 2" "2" "$code"
check "escrita negada: indica o comando com !" "sim" "$([[ "$err" == *"! bash "*"setup-sandbox.sh --project $tmp/proj"* ]] && echo sim || echo não)"
check "escrita negada: projeto não é gravado" "não" "$([[ -f "$proj" ]] && echo sim || echo não)"

echo
echo "$((total - failures))/$total"
[[ $failures -eq 0 ]]
