#!/usr/bin/env bash
# Testes da migração do sandbox nativo (scripts/migrate-native-sandbox.sh), com
# projeto, HOME e CLAUDE_CONFIG_DIR temporários: nenhum teste toca a máquina de
# verdade. O último bloco confere o uso do teste de aceite
# (scripts/test-sandbox-acceptance.sh). Os CAs são os da specs/SPEC-142.md.
# Uso: scripts/test-migrate-native-sandbox.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
migrate="$script_dir/migrate-native-sandbox.sh"
acceptance="$script_dir/test-sandbox-acceptance.sh"

# Com o arquivo global do git apontado por variável, o HOME temporário não
# isolaria o teste.
if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
  echo "test-migrate-native-sandbox: rode sem a variável GIT_CONFIG_GLOBAL." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export HOME="$tmp/root/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
unset XDG_CONFIG_HOME

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

proj="$tmp/root/proj"
psettings="$proj/.claude/settings.json"
usettings="$CLAUDE_CONFIG_DIR/settings.json"
gitconfig="$HOME/.gitconfig"
gitauth="$HOME/.config/fabrica/git-auth.gitconfig"
include="~/.config/fabrica/git-auth.gitconfig"
secret="SEGREDO-de-teste-142"

mask_gh='{"path": "~/.config/gh/hosts.yml", "mode": "mask", "extract": "oauth_token:\\s*(\\S+)", "maskDuplicates": true, "onExtractNoMatch": "deny", "injectHosts": ["api.github.com", "github.com"]}'
mask_git='{"path": "~/.config/fabrica/git-auth.gitconfig", "mode": "mask", "extract": "Basic\\s+(\\S+)", "maskDuplicates": true, "onExtractNoMatch": "deny", "injectHosts": ["github.com"]}'
# As mesmas entradas, com as chaves em outra ordem.
mask_gh_shuffled='{"injectHosts": ["api.github.com", "github.com"], "onExtractNoMatch": "deny", "maskDuplicates": true, "extract": "oauth_token:\\s*(\\S+)", "mode": "mask", "path": "~/.config/gh/hosts.yml"}'
mask_git_shuffled='{"mode": "mask", "injectHosts": ["github.com"], "path": "~/.config/fabrica/git-auth.gitconfig", "maskDuplicates": true, "extract": "Basic\\s+(\\S+)", "onExtractNoMatch": "deny"}'
all_items="projeto:sandbox maquina:tlsTerminate maquina:mask:~/.config/gh/hosts.yml maquina:mask:~/.config/fabrica/git-auth.gitconfig maquina:gitconfig-include maquina:git-auth"
settings_items="maquina:tlsTerminate maquina:mask:~/.config/gh/hosts.yml maquina:mask:~/.config/fabrica/git-auth.gitconfig"

reset_env() {
  chmod -R u+w "$tmp/root" 2>/dev/null
  rm -rf "$tmp/root"
  mkdir -p "$proj/.claude" "$CLAUDE_CONFIG_DIR"
  git -C "$proj" init -q
}
run() { bash "$migrate" --project "$proj" "$@"; }
# out <args>: stdout e código, sem stderr. err <args>: só stderr.
out() { local o c; o="$(run "$@" 2>/dev/null)"; c=$?; printf '%s|%s' "$o" "$c"; }
err() { run "$@" 2>&1 >/dev/null; }
exists() { [[ -e "$1" ]] && echo sim || echo não; }
same() { cmp -s "$1" "$2" && echo igual || echo diferente; }
# JSON do arquivo, ou do texto, com as chaves em ordem: compara valores.
norm() { python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), sort_keys=True, ensure_ascii=False))' "$1"; }
norms() { python3 -I -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]), sort_keys=True, ensure_ascii=False))' "$1"; }
# Retrato de tudo o que há no projeto e no HOME de teste, fora o .git.
snapshot() {
  (cd "$tmp/root" && find . -path ./proj/.git -prune -o -print | sort &&
    find . -path ./proj/.git -prune -o -type f -exec sha256sum {} + | sort) | sha256sum
}
backups() { find "$tmp/root" -name '*bak*' | wc -l | tr -d ' '; }

project_block() { printf '{"permissions": {"deny": ["Read(.env.local)"]}, "sandbox": {"enabled": true, "network": {"allowedDomains": ["github.com"]}}, "hooks": {"Stop": [{"x": 1}]}}\n' >"$psettings"; }
user_block() { printf '{"statusLine": {"type": "command", "command": "x"}, "sandbox": {"network": {"tlsTerminate": {}}, "credentials": {"files": [%s, %s]}}, "permissions": {"allow": ["Bash(ls)"]}}\n' "$mask_gh" "$mask_git" >"$usettings"; }
git_include() { git config --global --add include.path "$include"; }
git_auth_file() {
  mkdir -p "$(dirname "$gitauth")"
  printf '[http "https://github.com/"]\n\textraheader = Authorization: Basic %s\n' "$secret" >"$gitauth"
}
all_leftovers() {
  project_block
  user_block
  git_include
  git_auth_file
}

# CA2: sem resto nenhum.
reset_env
before="$(snapshot)"
check "CA2 --check sem arquivos" "ok|0" "$(out --check)"
check "CA2 sem opção vale --check" "ok|0" "$(out)"
check "CA2 --check não cria arquivo" "$before" "$(snapshot)"
printf '{"permissions": {"deny": []}}\n' >"$psettings"
printf '{"statusLine": {"type": "command", "command": "x"}}\n' >"$usettings"
before="$(snapshot)"
check "CA2 settings sem sandbox" "ok|0" "$(out --check)"
check "CA2 settings sem sandbox: nada muda" "$before" "$(snapshot)"

# CA3: todos os restos, na ordem da tabela.
reset_env
all_leftovers
before="$(snapshot)"
check "CA3 --check com todos os restos" "pendente $all_items|0" "$(out --check)"
check "CA3 sem opção, com todos os restos" "pendente $all_items|0" "$(out)"
check "CA3 arquivos idênticos" "$before" "$(snapshot)"
check "CA3 --check não imprime a credencial" "0" "$(run --check 2>&1 | grep -c "$secret")"

# CA4: --apply projeto.
reset_env
all_leftovers
cp -a "$HOME" "$tmp/home-antes"
expected="$(norms '{"permissions": {"deny": ["Read(.env.local)"]}, "hooks": {"Stop": [{"x": 1}]}}')"
check "CA4 --apply projeto" "removido projeto:sandbox|0" "$(out --apply projeto)"
check "CA4 sandbox sai, o resto fica" "$expected" "$(norm "$psettings")"
check "CA4 quebra de linha no fim" "\n" "$(tail -c 1 "$psettings" | od -An -c | tr -d ' ')"
check "CA4 sem backup no projeto" "0" "$(find "$proj" -name '*bak*' | wc -l | tr -d ' ')"
check "CA4 máquina idêntica" "" "$(diff -r "$HOME" "$tmp/home-antes")"
check "CA4 --check depois: só a máquina" "pendente ${all_items#projeto:sandbox }|0" "$(out --check)"
touch -d '2001-01-01 00:00:00' "$psettings"
stamp="$(stat -c %Y "$psettings")"
check "CA4 --apply projeto de novo" "ok|0" "$(out --apply projeto)"
check "CA4 não regrava o arquivo" "$stamp" "$(stat -c %Y "$psettings")"
rm -rf "$tmp/home-antes"

# CA5: sandbox como única chave e bloco desligado.
reset_env
printf '{"sandbox": {"enabled": true}}\n' >"$psettings"
check "CA5 sandbox é a única chave" "removido projeto:sandbox|0" "$(out --apply projeto)"
check "CA5 o arquivo fica com {}" "{}" "$(cat "$psettings")"
printf '{"sandbox": {"enabled": false}, "permissions": {}}\n' >"$psettings"
check "CA5 enabled: false aparece no --check" "pendente projeto:sandbox|0" "$(out --check)"
check "CA5 enabled: false é removido" "removido projeto:sandbox|0" "$(out --apply projeto)"
check "CA5 enabled: false: o resto fica" '{"permissions": {}}' "$(norm "$psettings")"
rm -f "$psettings"
check "CA5 projeto sem settings" "ok|0|não" "$(out --apply projeto)|$(exists "$psettings")"

# CA6: --apply maquina no settings do usuário, com as chaves em outra ordem.
reset_env
printf '{"statusLine": {"type": "command", "command": "ação"}, "sandbox": {"credentials": {"files": [%s, %s]}, "network": {"tlsTerminate": {}}}, "permissions": {"allow": ["Bash(ls)"]}}\n' "$mask_gh_shuffled" "$mask_git_shuffled" >"$usettings"
cp "$usettings" "$tmp/usettings-antes"
expected="$(norms '{"statusLine": {"type": "command", "command": "ação"}, "permissions": {"allow": ["Bash(ls)"]}}')"
check "CA6 --check com as chaves em outra ordem" "pendente $settings_items|0" "$(out --check)"
check "CA6 --apply maquina" "removido $settings_items|0" "$(out --apply maquina)"
check "CA6 e CA7 só as outras chaves ficam, sem sandbox" "$expected" "$(norm "$usettings")"
check "CA6 acento sem escape" "1" "$(grep -c 'ação' "$usettings")"
check "CA6 backup byte a byte" "igual" "$(same "$usettings.bak-fabrica-sandbox" "$tmp/usettings-antes")"
check "CA6 --apply maquina de novo" "ok|0" "$(out --apply maquina)"
check "CA6 o backup não é regravado sem resto" "igual" "$(same "$usettings.bak-fabrica-sandbox" "$tmp/usettings-antes")"

# CA6: um backup anterior de mesmo nome é sobrescrito.
reset_env
user_block
printf 'backup antigo\n' >"$usettings.bak-fabrica-sandbox"
cp "$usettings" "$tmp/usettings-antes"
run --apply maquina >/dev/null 2>&1
check "CA6 backup anterior sobrescrito" "igual" "$(same "$usettings.bak-fabrica-sandbox" "$tmp/usettings-antes")"

# CA7: o que é do usuário fica, com os contêineres dele.
reset_env
user_entry='{"path": "~/.aws/credentials", "mode": "deny"}'
printf '{"sandbox": {"network": {"tlsTerminate": {}, "allowedDomains": ["example.org"]}, "credentials": {"files": [%s, %s, %s]}}}\n' "$mask_gh" "$user_entry" "$mask_git" >"$usettings"
expected="$(norms "{\"sandbox\": {\"network\": {\"allowedDomains\": [\"example.org\"]}, \"credentials\": {\"files\": [$user_entry]}}}")"
check "CA7 --apply maquina com itens do usuário" "removido $settings_items|0" "$(out --apply maquina)"
check "CA7 entrada e allowedDomains do usuário ficam" "$expected" "$(norm "$usettings")"
# Contêiner que já estava vazio e não tinha item da fábrica.
printf '{"sandbox": {"network": {}, "credentials": {"files": [%s], "envVars": []}}}\n' "$mask_gh" >"$usettings"
check "CA7 só um mask" "removido maquina:mask:~/.config/gh/hosts.yml|0" "$(out --apply maquina)"
check "CA7 contêiner já vazio não é tocado" '{"sandbox": {"credentials": {"envVars": []}, "network": {}}}' "$(norm "$usettings")"
printf '{"sandbox": {"enabled": true, "network": {"tlsTerminate": {}}}}\n' >"$usettings"
check "CA7 só o tlsTerminate" "removido maquina:tlsTerminate|0" "$(out --apply maquina)"
check "CA7 sandbox com outra chave fica" '{"sandbox": {"enabled": true}}' "$(norm "$usettings")"

# CA8: o que não é idêntico ao que a fábrica gravava fica.
reset_env
other_mask='{"path": "~/.config/gh/hosts.yml", "mode": "mask", "extract": "token:\\s*(\\S+)", "maskDuplicates": true, "onExtractNoMatch": "deny", "injectHosts": ["api.github.com", "github.com"]}'
extra_mask='{"path": "~/.config/fabrica/git-auth.gitconfig", "mode": "mask", "extract": "Basic\\s+(\\S+)", "maskDuplicates": true, "onExtractNoMatch": "deny", "injectHosts": ["github.com"], "extra": 1}'
printf '{"sandbox": {"network": {"tlsTerminate": {"x": 1}}, "credentials": {"files": [%s, %s]}}}\n' "$other_mask" "$extra_mask" >"$usettings"
cp "$usettings" "$tmp/usettings-antes"
check "CA8 --check ignora o que difere" "ok|0" "$(out --check)"
check "CA8 --apply maquina não remove" "ok|0" "$(out --apply maquina)"
check "CA8 arquivo idêntico" "igual" "$(same "$usettings" "$tmp/usettings-antes")"
check "CA8 sem backup" "0" "$(backups)"
printf '{"sandbox": {"network": {"tlsTerminate": []}, "credentials": {"files": "x"}}}\n' >"$usettings"
check "CA8 tipos inesperados não são resto" "ok|0" "$(out --check)"
printf '{"sandbox": "ligado"}\n' >"$usettings"
check "CA8 sandbox do usuário que não é objeto" "ok|0" "$(out --apply maquina)"

# CA9: a inclusão do git e o arquivo da credencial.
reset_env
git config --global user.name "Teste"
git config --global --add include.path "~/.gitconfig-pessoal"
git_include
git_auth_file
cp "$gitconfig" "$tmp/gitconfig-antes"
run --apply maquina >"$tmp/out" 2>"$tmp/err"
check "CA9 --apply maquina: código e saída" "0|removido maquina:gitconfig-include maquina:git-auth" "$?|$(cat "$tmp/out")"
check "CA9 o outro include.path continua" "~/.gitconfig-pessoal" "$(git config --global --get-all include.path)"
check "CA9 o resto do gitconfig continua" "Teste" "$(git config --global user.name)"
check "CA9 backup do gitconfig" "igual" "$(same "$gitconfig.bak-fabrica-sandbox" "$tmp/gitconfig-antes")"
check "CA9 git-auth apagado" "não" "$(exists "$gitauth")"
check "CA9 sem cópia da credencial no HOME" "0" "$(grep -rl "$secret" "$HOME" | wc -l | tr -d ' ')"
check "CA9 credencial fora do stdout e do stderr" "0" "$(cat "$tmp/out" "$tmp/err" | grep -c "$secret")"
check "CA9 --apply maquina de novo" "ok|0" "$(out --apply maquina)"

# CA9: a inclusão no arquivo XDG do git.
reset_env
mkdir -p "$HOME/.config/git"
printf '[include]\n\tpath = %s\n[user]\n\tname = Teste\n' "$include" >"$HOME/.config/git/config"
cp "$HOME/.config/git/config" "$tmp/gitconfig-antes"
check "CA9 inclusão no arquivo XDG" "removido maquina:gitconfig-include|0" "$(out --apply maquina)"
check "CA9 XDG: backup ao lado do arquivo" "igual" "$(same "$HOME/.config/git/config.bak-fabrica-sandbox" "$tmp/gitconfig-antes")"
check "CA9 XDG: inclusão removida" "|Teste" "$(git config --global --get-all include.path)|$(git config --global user.name)"

# CA9: todos os itens da máquina de uma vez, na ordem da tabela.
reset_env
all_leftovers
check "CA9 todos os itens da máquina" "removido ${all_items#projeto:sandbox }|0" "$(out --apply maquina)"
check "CA9 o projeto não é tocado" "pendente projeto:sandbox|0" "$(out --check)"

# CA10: parte dos restos, e nenhum.
reset_env
rm -rf "$CLAUDE_CONFIG_DIR"
git_auth_file
check "CA10 só o git-auth: --check" "pendente maquina:git-auth|0" "$(out --check)"
check "CA10 só o git-auth: --apply maquina" "removido maquina:git-auth|0" "$(out --apply maquina)"
check "CA10 só o git-auth: sem backup" "0" "$(backups)"
reset_env
git_include
check "CA10 só a inclusão" "removido maquina:gitconfig-include|0" "$(out --apply maquina)"
reset_env
before="$(snapshot)"
check "CA10 sem resto: --apply maquina" "ok|0" "$(out --apply maquina)"
check "CA10 sem resto: nada criado" "$before" "$(snapshot)"

# CA11: JSON inválido.
for broken in '{"sandbox": tru' '[1, 2]'; do
  reset_env
  all_leftovers
  printf '%s' "$broken" >"$psettings"
  before="$(snapshot)"
  message="migrate-native-sandbox: JSON inválido em $psettings"
  check "CA11 projeto com $broken: --check" "|1|$message" "$(out --check)|$(err --check)"
  check "CA11 projeto com $broken: --apply projeto" "|1|$message" "$(out --apply projeto)|$(err --apply projeto)"
  check "CA11 projeto com $broken: nada muda" "$before" "$(snapshot)"

  reset_env
  all_leftovers
  printf '%s' "$broken" >"$usettings"
  before="$(snapshot)"
  message="migrate-native-sandbox: JSON inválido em $usettings"
  check "CA11 usuário com $broken: --check" "|1|$message" "$(out --check)|$(err --check)"
  check "CA11 usuário com $broken: --apply maquina" "|1|$message" "$(out --apply maquina)|$(err --apply maquina)"
  check "CA11 usuário com $broken: nada muda, sem backup" "$before|0" "$(snapshot)|$(backups)"
done

# CA12: uso inválido.
reset_env
all_leftovers
before="$(snapshot)"
msg() { [[ -n "$(err "$@")" ]] && echo sim || echo não; }
check "CA12 --apply docker" "|1|sim" "$(out --apply docker)|$(msg --apply docker)"
check "CA12 --apply sem valor" "|1|sim" "$(out --apply)|$(msg --apply)"
check "CA12 --check --apply projeto" "|1|sim" "$(out --check --apply projeto)|$(msg --check --apply projeto)"
check "CA12 --apply maquina --check" "|1|sim" "$(out --apply maquina --check)|$(msg --apply maquina --check)"
check "CA12 opção desconhecida" "|1|sim" "$(out --force)|$(msg --force)"
check "CA12 --project inexistente" "|1|sim" "$(o="$(bash "$migrate" --project "$tmp/nao-existe" --check 2>/dev/null)"; printf '%s|%s' "$o" "$?")|$([[ -n "$(bash "$migrate" --project "$tmp/nao-existe" --check 2>&1 >/dev/null)" ]] && echo sim || echo não)"
check "CA12 --project sem diretório" "|1" "$(o="$(bash "$migrate" --project 2>/dev/null)"; printf '%s|%s' "$o" "$?")"
check "CA12 nada muda" "$before" "$(snapshot)"
mkdir -p "$tmp/fora"
outside() { (cd "$tmp/fora" && o="$(GIT_CEILING_DIRECTORIES="$tmp" bash "$migrate" "$@" 2>/dev/null)"; printf '%s|%s' "$o" "$?"); }
check "CA12 fora de repositório git: só a máquina" "pendente ${all_items#projeto:sandbox }|0" "$(outside --check)"
check "CA12 fora de repositório git: --apply projeto" "|1" "$(outside --apply projeto)"
check "CA12 fora de repositório git: mensagem" "sim" "$([[ -n "$(cd "$tmp/fora" && GIT_CEILING_DIRECTORIES="$tmp" bash "$migrate" --apply projeto 2>&1 >/dev/null)" ]] && echo sim || echo não)"
check "CA12 fora de repositório git: nada muda" "$before" "$(snapshot)"
check "CA12 sem --project, dentro do repositório" "pendente $all_items|0" "$(cd "$proj" && o="$(bash "$migrate" 2>/dev/null)"; printf '%s|%s' "$o" "$?")"

# CA13: Prettier do projeto.
reset_env
project_block
mkdir -p "$proj/node_modules/.bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$PWD" "$*" >"%s"\n' "$tmp/prettier-args" >"$proj/node_modules/.bin/prettier"
chmod +x "$proj/node_modules/.bin/prettier"
run --apply projeto >"$tmp/out" 2>"$tmp/err"
check "CA13 com prettier: código, saída e stderr" "0|removido projeto:sandbox|" "$?|$(cat "$tmp/out")|$(cat "$tmp/err")"
check "CA13 prettier chamado na raiz, com --write" "$proj|--write .claude/settings.json" "$(paste -sd'|' "$tmp/prettier-args")"
project_block
printf '#!/usr/bin/env bash\nexit 2\n' >"$proj/node_modules/.bin/prettier"
run --apply projeto >"$tmp/out" 2>"$tmp/err"
check "CA13 prettier com erro: código e saída" "0|removido projeto:sandbox" "$?|$(cat "$tmp/out")"
check "CA13 prettier com erro: aviso em stderr" "migrate-native-sandbox: não consegui formatar .claude/settings.json; rode o prettier do projeto nele." "$(cat "$tmp/err")"
check "CA13 prettier com erro: bloco removido" "ok|0" "$(out --check)"
project_block
chmod -x "$proj/node_modules/.bin/prettier"
check "CA13 prettier não executável: sem aviso" "removido projeto:sandbox|0|" "$(out --apply projeto)|$(err --apply projeto)"

# Falha de escrita (o root grava mesmo sem permissão; lá, o bloco é pulado).
if [[ "$(id -u)" != "0" ]]; then
  reset_env
  project_block
  chmod 444 "$psettings"
  cp "$psettings" "$tmp/psettings-antes"
  run --apply projeto >"$tmp/out" 2>"$tmp/err"
  check "escrita negada no projeto: código e saída" "1|" "$?|$(cat "$tmp/out")"
  check "escrita negada no projeto: mensagem" "sim" "$([[ "$(cat "$tmp/err")" == "migrate-native-sandbox: não consegui gravar $psettings: "* ]] && echo sim || echo não)"
  check "escrita negada no projeto: arquivo idêntico" "igual" "$(same "$psettings" "$tmp/psettings-antes")"

  reset_env
  user_block
  git_auth_file
  chmod 555 "$(dirname "$gitauth")"
  run --apply maquina >"$tmp/out" 2>"$tmp/err"
  check "falha no meio: código e saída" "1|" "$?|$(cat "$tmp/out")"
  check "falha no meio: diz o que já foi removido" "migrate-native-sandbox: já removido: $settings_items" "$(sed -n 2p "$tmp/err")"
  check "falha no meio: credencial fora das saídas" "0" "$(cat "$tmp/out" "$tmp/err" | grep -c "$secret")"
  chmod 755 "$(dirname "$gitauth")"
fi

# CA16: uso do teste de aceite. Nenhuma verificação roda nestes casos.
reset_env
check "CA16 bash -n do aceite" "0" "$(bash -n "$acceptance" >/dev/null 2>&1; echo $?)"
(cd "$proj" && bash "$acceptance" --force >"$tmp/out" 2>"$tmp/err")
check "CA16 opção desconhecida: código" "1" "$?"
check "CA16 opção desconhecida: mensagem em stderr" "sim" "$([[ -s "$tmp/err" ]] && echo sim || echo não)"
check "CA16 opção desconhecida: nenhuma verificação" "0" "$(grep -cE '^(ok|falha) ' "$tmp/out")"
(cd "$proj" && bash "$acceptance" --remote >"$tmp/out" 2>"$tmp/err")
check "CA16 --remote sem nome: código e verificações" "1|0" "$?|$(grep -cE '^(ok|falha) ' "$tmp/out")"
(cd "$tmp/fora" && GIT_CEILING_DIRECTORIES="$tmp" bash "$acceptance" >"$tmp/out" 2>"$tmp/err")
check "CA16 fora de repositório git: código" "1" "$?"
check "CA16 fora de repositório git: mensagem em stderr" "sim" "$([[ -s "$tmp/err" ]] && echo sim || echo não)"
check "CA16 fora de repositório git: nenhuma verificação" "0" "$(grep -cE '^(ok|falha) ' "$tmp/out")"
check "CA16 o aceite não cita o sandbox nativo" "0" "$(grep -cE 'git-auth|tlsTerminate|\.env\.production|mask' "$acceptance")"

echo
echo "$((total - failures))/$total"
[[ $failures -eq 0 ]]
