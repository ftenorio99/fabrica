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

# Sem isto, o git config --global dos testes poderia cair no gitconfig real.
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
export GIT_CONFIG_NOSYSTEM=1

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
check "CA1 projeto: sem exceção ao sandbox" "False" "$(jget "$proj" '"excludedCommands" in d["sandbox"]')"
check "CA1 usuário: mask do git-auth" "~/.config/fabrica/git-auth.gitconfig mask ['github.com']" "$(jget "$user" '" ".join(map(str,[(f:=d["sandbox"]["credentials"]["files"][1])["path"], f["mode"], f["injectHosts"]]))')"
check "CA1 projeto: cache do npm gravável" "['~/.npm']" "$(jget "$proj" 'd["sandbox"]["filesystem"]["allowWrite"]')"
check "CA1 projeto: allowLocalBinding" "True" "$(jget "$proj" 'd["sandbox"]["network"]["allowLocalBinding"]')"
check "CA1 projeto: arquivos negados (#94 CA6: só os .env de produção)" "['~/.ssh', '.env.production', '.env.production.local']" "$(jget "$proj" '[f["path"] for f in d["sandbox"]["credentials"]["files"] if f["mode"]=="deny"]')"
check "CA1 projeto: variáveis negadas" "['GH_TOKEN', 'GITHUB_TOKEN']" "$(jget "$proj" '[v["name"] for v in d["sandbox"]["credentials"]["envVars"] if v["mode"]=="deny"]')"
check "CA1 usuário: tlsTerminate" "{}" "$(jget "$user" 'd["sandbox"]["network"]["tlsTerminate"]')"
check "CA1 usuário: mask do hosts.yml" "mask ['api.github.com', 'github.com'] deny True" "$(jget "$user" '" ".join(map(str,[(f:=d["sandbox"]["credentials"]["files"][0])["mode"], f["injectHosts"], f["onExtractNoMatch"], f["maskDuplicates"]]))')"
check "CA1 usuário: extract" 'oauth_token:\s*(\S+)' "$(jget "$user" 'd["sandbox"]["credentials"]["files"][0]["extract"]')"
check "CA1 usuário: path" "~/.config/gh/hosts.yml" "$(jget "$user" 'd["sandbox"]["credentials"]["files"][0]["path"]')"
check "CA1 sem .bak-fabrica-sandbox quando o settings não existia" "não" "$([[ -f "$user.bak-fabrica-sandbox" ]] && echo sim || echo não)"
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
run >/dev/null 2>&1
check "CA2 preserva permissions.deny do projeto" "['Read(.env)', 'Read(//**/.ssh/**)']" "$(jget "$proj" 'd["permissions"]["deny"]')"
check "CA2 soma domínios sem repetir" "['api.github.com', 'example.org', 'github.com', 'codeload.github.com', 'uploads.github.com', '*.githubusercontent.com', 'registry.npmjs.org']" "$(jget "$proj" 'd["sandbox"]["network"]["allowedDomains"]')"
check "CA2 preserva statusLine e theme do usuário" "/x/statusline.sh dark" "$(jget "$user" 'd["statusLine"]["command"]+" "+d["theme"]')"
check "CA2 .bak-fabrica-sandbox igual ao settings anterior" "igual" "$(cmp -s "$user.bak-fabrica-sandbox" "$tmp/user-antes.json" && echo igual || echo diferente)"

# CA3: segunda execução não muda nada; domínio acrescentado pelo repositório fica.
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["network"]["allowedDomains"].append("api.stripe.com"); json.dump(d,open(p,"w"),indent=2)' "$proj"
hash_before="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
out="$(run 2>/dev/null)"
hash_after="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
check "CA3 segunda execução responde ok" "ok" "$out"
check "CA3 segunda execução não muda os arquivos" "$hash_before" "$hash_after"
check "CA3 domínio do repositório continua" "True" "$(jget "$proj" '"api.stripe.com" in d["sandbox"]["network"]["allowedDomains"]')"

# CA4: incompleto quando falta ou diverge uma chave; --check não grava.
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["enabled"]=False; d["sandbox"]["network"]["allowedDomains"].remove("registry.npmjs.org"); json.dump(d,open(p,"w"),indent=2)' "$proj"
hash_before="$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
check "CA4 --check incompleto" "incompleto enabled=false sandbox.network.allowedDomains:registry.npmjs.org" "$(run --check 2>/dev/null)"
check "CA4 --check não grava" "$hash_before" "$(sha256sum "$proj" "$user" | cut -d' ' -f1 | tr '\n' ' ')"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["credentials"]["files"][0]["mode"]="allow"; json.dump(d,open(p,"w"),indent=2)' "$user"
check "CA4 --check aponta credencial divergente" "incompleto enabled=false sandbox.network.allowedDomains:registry.npmjs.org credentials:~/.config/gh/hosts.yml" "$(run --check 2>/dev/null)"
run >/dev/null 2>&1
check "CA4 instalar corrige o escalar" "True" "$(jget "$proj" 'd["sandbox"]["enabled"]')"
check "CA4 instalar não duplica a credencial existente" "1" "$(jget "$user" 'sum(f["path"].endswith("hosts.yml") for f in d["sandbox"]["credentials"]["files"])')"

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

# #94 CA7: os deny de .env que a fábrica gravava saem; os do usuário ficam.
reset_env
run >/dev/null
python3 -I -c '
import json, sys
p = sys.argv[1]; d = json.load(open(p)); f = d["sandbox"]["credentials"]["files"]
for x in (".env", ".env.local", ".env.development", ".env.test"):
    f.append({"path": x, "mode": "deny"})
f.append({"path": ".env.local", "mode": "allow"})
f.append({"path": ".env.test", "mode": "deny", "nota": "do usuário"})
json.dump(d, open(p, "w"), indent=2)' "$proj"
check "#94 CA7 --check aponta as entradas aposentadas" "incompleto remover:credentials:.env remover:credentials:.env.local remover:credentials:.env.development remover:credentials:.env.test" "$(run --check)"
check "#94 CA7 instala" "instalado" "$(run)"
check "#94 CA7 remove só as idênticas às da fábrica" "[('~/.ssh', 'deny'), ('.env.production', 'deny'), ('.env.production.local', 'deny'), ('.env.local', 'allow'), ('.env.test', 'deny')]" "$(jget "$proj" '[(f["path"], f["mode"]) for f in d["sandbox"]["credentials"]["files"]]')"
check "#94 CA7 --check depois" "ok" "$(run --check)"

# #94 CA8: hosts de .fabrica/producao.txt viram deniedDomains.
reset_env
run >/dev/null
check "#94 CA8 sem producao.txt, sem deniedDomains" "False" "$(jget "$proj" '"deniedDomains" in d["sandbox"]["network"]')"
mkdir -p "$tmp/proj/.fabrica"
cat >"$tmp/proj/.fabrica/producao.txt" <<'TXT'
# produção
host db.prod.exemplo
host *.api.exemplo
host db.prod.exemplo
texto sk_live_
texto abc
host dois hosts
banco x
TXT
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["sandbox"]["network"]["deniedDomains"]=["ja.estava.exemplo"]; json.dump(d,open(p,"w"),indent=2)' "$proj"
check "#94 CA8 --check aponta os hosts que faltam" "incompleto sandbox.network.deniedDomains:db.prod.exemplo sandbox.network.deniedDomains:*.api.exemplo" "$(run --check 2>/dev/null)"
check "#94 CA8 avisos em stderr" "setup-sandbox: .fabrica/producao.txt: padrão curto: abc|setup-sandbox: .fabrica/producao.txt: linha inválida: 7|setup-sandbox: .fabrica/producao.txt: linha inválida: 8" "$(run --check 2>&1 >/dev/null | paste -sd'|')"
check "#94 CA8 instala" "instalado" "$(run 2>/dev/null)"
check "#94 CA8 soma sem repetir e sem tirar" "['ja.estava.exemplo', 'db.prod.exemplo', '*.api.exemplo']" "$(jget "$proj" 'd["sandbox"]["network"]["deniedDomains"]')"
check "#94 CA8 --check depois: ok, mesmo com avisos" "ok" "$(run --check 2>/dev/null)"
check "#94 CA8 segunda instalação não muda nada" "ok" "$(run 2>/dev/null)"
check "#94 CA8 usuário sem deniedDomains" "False" "$(jget "$user" '"deniedDomains" in d["sandbox"]["network"]')"

# #112: o Prettier do projeto formata o settings que o script grava.
fake_prettier() { # fake_prettier <código de saída>
  mkdir -p "$tmp/proj/node_modules/.bin"
  printf '#!/usr/bin/env bash\necho "$PWD $*" >>"%s/prettier.log"\nexit %s\n' "$tmp" "$1" >"$tmp/proj/node_modules/.bin/prettier"
  chmod +x "$tmp/proj/node_modules/.bin/prettier"
  rm -f "$tmp/prettier.log"
}
reset_env
fake_prettier 0
check "#112 CA1 instala com prettier no projeto" "instalado" "$(run 2>/dev/null)"
check "#112 CA1 chama o prettier na raiz com --write" "$tmp/proj --write .claude/settings.json" "$(cat "$tmp/prettier.log" 2>/dev/null)"
rm -f "$tmp/prettier.log"
check "#112 CA4 --check não chama o prettier" "ok não" "$(run --check) $([[ -f "$tmp/prettier.log" ]] && echo sim || echo não)"
check "#112 CA4 instalação sem mudança não chama o prettier" "ok não" "$(run) $([[ -f "$tmp/prettier.log" ]] && echo sim || echo não)"
reset_env
fake_prettier 1
out="$(run 2>"$tmp/err")"; code=$?
check "#112 CA3 prettier com erro: instala com código 0" "instalado 0" "$out $code"
check "#112 CA3 prettier com erro: aviso em stderr" "setup-sandbox: não consegui formatar .claude/settings.json; rode o prettier do projeto nele." "$(cat "$tmp/err")"
reset_env
out="$(run 2>"$tmp/err")"
check "#112 CA2 sem prettier: instala sem aviso" "instalado " "$out $(cat "$tmp/err")"
check "#112 CA2 sem prettier: lista aberta como antes" "1" "$(grep -c '"allowWrite": \[$' "$proj")"

# #113: aviso quando o permissions.deny do projeto nega os .env de dev.
with_deny() { # with_deny <lista JSON>: grava o permissions.deny no projeto
  mkdir -p "$tmp/proj/.claude"
  python3 -I -c 'import json,sys; p=sys.argv[1]
try: d=json.load(open(p))
except FileNotFoundError: d={}
d["permissions"]=json.loads(sys.argv[2]); json.dump(d,open(p,"w"),indent=2)' "$proj" "$2"
}
msg() { echo "setup-sandbox: permissions.deny nega $1; o agente não vai ler os .env de dev no sandbox (ADR 0006)"; }
reset_env
run >/dev/null
with_deny "$proj" '{"deny": ["Read(.env)", "Read(.env*)", "Read(**/.env)", "Read(.env.production)", "Read(.env.*.local)", "Read(//**/.ssh/**)", "Read(src/.env)", "Bash(rm:*)"]}'
check "#113 CA1 --check avisa uma linha por regra" "$(msg 'Read(.env)')|$(msg 'Read(.env*)')|$(msg 'Read(**/.env)')" "$(run --check 2>&1 >/dev/null | paste -sd'|')"
check "#113 CA3 --check continua ok" "ok" "$(run --check 2>/dev/null)"
check "#113 CA1 instalação também avisa" "3" "$(run 2>&1 >/dev/null | grep -c 'permissions.deny nega')"
check "#113 CA3 permissions.deny intacto" "8" "$(jget "$proj" 'len(d["permissions"]["deny"])')"
with_deny "$proj" '{"deny": ["Read(.env.production)", "Read(.env.*.local)", "Read(//**/.ssh/**)", "Read(src/.env)"]}'
check "#113 CA2 regras que não pegam os .env de dev: sem aviso" "" "$(run --check 2>&1 >/dev/null)"
with_deny "$proj" '{"deny": "Read(.env)"}'
check "#113 CA4 deny que não é lista: sem aviso nem erro" "ok " "$(run --check 2>"$tmp/err") $(cat "$tmp/err")"
with_deny "$proj" '[]'
check "#113 CA4 permissions que não é objeto: sem aviso nem erro" "ok " "$(run --check 2>"$tmp/err") $(cat "$tmp/err")"

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

# setup-git-auth.sh: cabeçalho do git, com um gh falso e HOME temporário.
reset_env
unset XDG_CONFIG_HOME
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho gho_FAKETOKEN123\n' >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
gitauth="$script_dir/setup-git-auth.sh"
auth_file="$HOME/.config/fabrica/git-auth.gitconfig"
check "git-auth --check sem nada" "ausente" "$(PATH="$tmp/bin:$PATH" bash "$gitauth" --check)"
# gh lê um token que não é o do hosts.yml (chaveiro): recusa e não grava.
mkdir -p "$HOME/.config/gh"
printf 'github.com:\n    oauth_token: github_pat_OUTRO\n    user: x\n' >"$HOME/.config/gh/hosts.yml"
err="$(PATH="$tmp/bin:$PATH" bash "$gitauth" 2>&1 >/dev/null)"
code=$?
check "git-auth recusa token fora do hosts.yml: código 1" "1" "$code"
check "git-auth recusa token fora do hosts.yml: mensagem" "sim" "$([[ "$err" == *"não é o do"*"hosts.yml"* ]] && echo sim || echo não)"
check "git-auth recusa token fora do hosts.yml: não grava" "não" "$([[ -e "$auth_file" ]] && echo sim || echo não)"
printf 'github.com:\n    oauth_token: gho_FAKETOKEN123\n    user: x\n' >"$HOME/.config/gh/hosts.yml"
PATH="$tmp/bin:$PATH" bash "$gitauth" >/dev/null
check "git-auth grava com permissão 600" "600" "$(stat -c %a "$auth_file")"
expected="$(printf 'x-access-token:gho_FAKETOKEN123' | base64 | tr -d '\n')"
check "git-auth grava o Basic do token" "extraheader = Authorization: Basic $expected" "$(sed -n 's/^[[:space:]]*//; /extraheader/p' "$auth_file")"
check "git-auth inclui o arquivo no ~/.gitconfig" "~/.config/fabrica/git-auth.gitconfig" "$(git config --global --get-all include.path)"
PATH="$tmp/bin:$PATH" bash "$gitauth" >/dev/null
check "git-auth não repete o include" "1" "$(git config --global --get-all include.path | wc -l)"
check "git-auth --check depois de gravar" "ok" "$(PATH="$tmp/bin:$PATH" bash "$gitauth" --check)"
git config --global --unset-all include.path
check "git-auth --check sem o include" "sem-include" "$(PATH="$tmp/bin:$PATH" bash "$gitauth" --check)"

echo
echo "$((total - failures))/$total"
[[ $failures -eq 0 ]]
