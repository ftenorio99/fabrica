#!/usr/bin/env bash
# Teste de aceite do isolamento do job do dispatcher (SPEC-106, CA11). Roda no
# runner do GitHub Actions, como root, depois de `job-isolation.sh prepare` e
# `lock` (veja templates/workflows/isolamento-aceite.yml). Imprime
# `ok <verificação>` ou `falha <verificação>: <motivo>` e sai com 1 se alguma
# falhar. Os valores reais dos tokens só existem neste processo, que roda como
# root: as verificações do agente usam o `sudo -u fabrica-agent`.
#
# Variáveis: CLAUDE_CODE_OAUTH_TOKEN, FABRICA_GH_TOKEN e FABRICA_PLUGIN_TOKEN
# (os valores reais, para conferir que o agente não os alcança) e
# GITHUB_REPOSITORY e GITHUB_REPOSITORY_OWNER.
set -uo pipefail
export LC_ALL=C.UTF-8

dir="${FABRICA_ISOLATION_DIR:-/etc/fabrica}"
agent="${FABRICA_AGENT_USER:-fabrica-agent}"
proxy_home="${FABRICA_PROXY_HOME:-/var/lib/fabrica-proxy}"
plugin_copy="${FABRICA_PLUGIN_COPY:-/opt/fabrica-plugin}"
repo="${GITHUB_REPOSITORY:-}"
owner="${GITHUB_REPOSITORY_OWNER:-}"

failed=0
ok() { echo "ok $1"; }
bad() { echo "falha $1: $2"; failed=1; }

[[ $EUID -eq 0 ]] || { echo "falha raiz: rode com sudo." >&2; exit 1; }
[[ -r "$dir/agent.env" ]] || { echo "falha agent.env: rode o job-isolation.sh lock antes." >&2; exit 1; }
for var in CLAUDE_CODE_OAUTH_TOKEN FABRICA_GH_TOKEN FABRICA_PLUGIN_TOKEN GITHUB_REPOSITORY; do
  [[ -n "${!var:-}" ]] || { echo "falha ambiente: falta $var." >&2; exit 1; }
done

env_args=("PATH=$PATH" "HOME=/home/$agent" "LANG=C.UTF-8")
while IFS= read -r line; do
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && env_args+=("$line")
done < "$dir/agent.env"
as_agent() { sudo -n -u "$agent" -H env -i "${env_args[@]}" "$@"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 0700 "$work"

# 1. Sem rede direta: nem por IP, nem por nome, ignorando o proxy.
direct_ip="$(as_agent curl -sS --noproxy '*' --max-time 8 -o /dev/null https://1.1.1.1 2>&1)"; rc_ip=$?
direct_name="$(as_agent curl -sS --noproxy '*' --max-time 8 -o /dev/null https://api.github.com 2>&1)"; rc_name=$?
if [[ $rc_ip -ne 0 && $rc_name -ne 0 ]]; then
  ok agente-sem-rede-direta
else
  bad agente-sem-rede-direta "o agente alcançou a rede sem o proxy (IP: $rc_ip, nome: $rc_name)"
fi

# 2. Host da lista pelo proxy, com o marcador no lugar do token.
login="$(as_agent gh api user -q .login 2>"$work/gh.err")"
if [[ -n "$login" && ( -z "$owner" || "$login" == "$owner" ) ]]; then
  ok dominio-liberado
else
  bad dominio-liberado "gh api user devolveu '${login:-nada}' (esperado ${owner:-algum login}): $(head -c 200 "$work/gh.err")"
fi

# 3. Host fora da lista: 403 do proxy.
out="$(as_agent curl -sS --max-time 10 -o /dev/null https://example.com 2>&1)"; rc=$?
if [[ $rc -ne 0 && "$out" == *403* ]]; then
  ok dominio-fora-da-lista
else
  bad dominio-fora-da-lista "esperava 403 do proxy, veio rc=$rc: $(echo "$out" | head -c 200)"
fi

# 4. git pelo proxy, com o marcador no Basic.
marker="$(sed -n 's/^GH_TOKEN=//p' "$dir/agent.env")"
basic="$(printf 'x-access-token:%s' "$marker" | base64 -w0)"
sha="$(as_agent git -c credential.helper= -c "http.extraHeader=Authorization: Basic $basic" ls-remote "https://github.com/$repo" HEAD 2>"$work/git.err" | awk '{print $1}')"
if [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  ok git-pelo-proxy
else
  # Diagnóstico sem valores: o token alcança o conteúdo do repositório pela API?
  contents="$(as_agent gh api "repos/$repo/contents" -q 'length' 2>&1 | head -c 120)"
  other="$(as_agent git -c credential.helper= -c "http.extraHeader=Authorization: Basic $(printf 'git:%s' "$marker" | base64 -w0)" ls-remote "https://github.com/$repo" HEAD 2>&1 | head -c 160)"
  bad git-pelo-proxy "git ls-remote não devolveu um commit: $(head -c 200 "$work/git.err") | contents pela API: ${contents:-vazio} | com outro usuário: ${other:-vazio}"
fi

# 5. O ambiente do agente só tem marcadores.
oauth_seen="$(as_agent printenv CLAUDE_CODE_OAUTH_TOKEN)"
gh_seen="$(as_agent printenv GH_TOKEN)"
if [[ "$oauth_seen" == fabrica-marker-* && "$gh_seen" == fabrica-marker-* \
      && "$oauth_seen" != "$CLAUDE_CODE_OAUTH_TOKEN" && "$gh_seen" != "$FABRICA_GH_TOKEN" ]]; then
  ok marcador-no-ambiente
else
  bad marcador-no-ambiente "o CLAUDE_CODE_OAUTH_TOKEN ou o GH_TOKEN do agente não é um marcador"
fi

# 6. Nenhum arquivo nem /proc legível pelo agente tem os valores reais. Quem
# lista o que o agente lê é o próprio agente; quem procura os valores é o root,
# para os valores nunca chegarem ao agente.
printf '%s\n%s\n%s\n' "$CLAUDE_CODE_OAUTH_TOKEN" "$FABRICA_GH_TOKEN" "$FABRICA_PLUGIN_TOKEN" > "$work/needles"
# Só onde um segredo poderia ter ficado: os homes, o checkout e os temporários
# do runner, /etc, /tmp, /run e os logs. Fora disso (/usr, /opt/hostedtoolcache)
# são milhares de arquivos de ferramentas, e a busca passaria dos 20 minutos.
as_agent timeout 180 bash -c '
  for f in /proc/[0-9]*/environ /proc/[0-9]*/cmdline; do [ -r "$f" ] && echo "$f"; done
  find /home /etc /tmp /var/tmp /var/log /run /var/lib/fabrica-proxy /opt/fabrica-plugin -xdev -type f -readable -size -5M 2>/dev/null
' > "$work/readable.txt" 2>/dev/null
hits="$(tr '\n' '\0' < "$work/readable.txt" | timeout 300 xargs -0 -r grep -l -a -F -f "$work/needles" 2>/dev/null | head -n 5)"
if [[ -z "$hits" ]]; then
  ok segredo-fora-do-alcance
else
  bad segredo-fora-do-alcance "o agente lê arquivos com o valor real: $(echo "$hits" | tr '\n' ' ')"
fi

# 7. A chave privada da CA do proxy.
if as_agent test -r "$proxy_home/.mitmproxy/mitmproxy-ca.pem" 2>/dev/null; then
  bad ca-privada-ilegivel "o agente lê a chave privada da CA"
else
  ok ca-privada-ilegivel
fi

# 8. Sem sudo.
if as_agent sudo -n true >/dev/null 2>&1; then
  bad sem-sudo "o agente roda sudo"
else
  ok sem-sudo
fi

# 9. O token do plugin não ficou no home do agente.
if grep -r -a -l -F "$FABRICA_PLUGIN_TOKEN" "/home/$agent" >/dev/null 2>&1; then
  bad home-sem-token "o home do agente guarda o FABRICA_PLUGIN_TOKEN"
else
  ok home-sem-token
fi

# 10. O log do proxy só lista hosts da lista e mostra o bloqueio do teste 3.
domains="$plugin_copy/templates/workflows/dominios-liberados.txt"
seen="$(sed -n 's/.*permitido \([^ ]*\)$/\1/p' "$dir/proxy.log" | sort -u)"
outside=""
for host in $seen; do
  grep -v '^#' "$domains" | grep -q -x -F "$host" || outside="$outside $host"
done
if grep -q 'bloqueado example.com' "$dir/proxy.log" && [[ -z "$outside" ]]; then
  ok proxy-so-lista
else
  bad proxy-so-lista "sem o bloqueio de example.com no log, ou host fora da lista liberado:${outside:- nenhum}"
fi

if [[ $failed -eq 0 ]]; then
  echo "Aceite do isolamento: tudo ok. Guarde o link deste run no PR."
fi
exit $failed
