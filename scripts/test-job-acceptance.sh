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
  bad git-pelo-proxy "git ls-remote não devolveu um commit: $(head -c 200 "$work/git.err")"
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

# 6. Nenhum arquivo nem /proc legível pelo agente tem os valores reais. O root
# procura os valores nas pastas onde um segredo poderia ter ficado, com o
# `find`/`grep` dele, e depois confere, para cada arquivo encontrado, se o agente
# consegue abri-lo: o proxy.env, por exemplo, tem os valores e o agente não o lê.
# Os valores nunca chegam ao agente. Passar do tempo é falha, não "nada achado".
printf '%s\n%s\n%s\n' "$CLAUDE_CODE_OAUTH_TOKEN" "$FABRICA_GH_TOKEN" "$FABRICA_PLUGIN_TOKEN" > "$work/needles"
timeout 900 grep -r -I -l -a -F -f "$work/needles" \
  --exclude-dir=hostedtoolcache --exclude-dir=docker --exclude-dir=containerd --exclude-dir=snapd \
  /home /etc /tmp /var/tmp /var/log /var/lib /run /opt/fabrica-plugin /usr/local 2>/dev/null > "$work/found.txt"
rc_scan=$?
# O grep sai com 2 quando algum arquivo não abre, mesmo com resultados: só 124
# (tempo) e códigos acima de 2 são falha da busca.
leaks=""
while IFS= read -r f; do
  [[ -n "$f" && "$f" != "$work"/* ]] || continue
  as_agent test -r "$f" 2>/dev/null && leaks="$leaks $f"
done < "$work/found.txt"
# /proc: só o que o agente consegue abrir (o `environ` de outro usuário ele não abre).
as_agent timeout 60 bash -c 'for f in /proc/[0-9]*/environ /proc/[0-9]*/cmdline; do [ -r "$f" ] && echo "$f"; done' > "$work/proc.txt" 2>/dev/null
proc_hits="$(tr '\n' '\0' < "$work/proc.txt" | xargs -0 -r grep -l -a -F -f "$work/needles" 2>/dev/null | head -n 5)"
if [[ $rc_scan -eq 124 ]]; then
  bad segredo-fora-do-alcance "a busca passou de 15 minutos e foi cortada"
elif [[ $rc_scan -gt 2 ]]; then
  bad segredo-fora-do-alcance "a busca terminou com código $rc_scan"
elif [[ -n "$leaks$proc_hits" ]]; then
  bad segredo-fora-do-alcance "o agente lê arquivos com o valor real: $leaks $(echo "$proc_hits" | tr '\n' ' ')"
else
  ok segredo-fora-do-alcance
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
