#!/usr/bin/env bash
# Isolamento do job do dispatcher (SPEC-106, ADR 0016). Roda como root, por sudo.
#
# Uso:
#   job-isolation.sh prepare <pasta do plugin instalado> <pasta do checkout>
#       cria os usuários fabrica-proxy e fabrica-agent, copia o plugin sem o
#       .git para uma pasta que o agente lê, instala os hooks do git da
#       main numa pasta que o agente só lê (com o arquivo de configuração
#       que a aponta), grava a lista final de domínios (a do plugin seguida
#       dos hosts de .fabrica/dominios.txt do checkout; SPEC-108, ADR 0018)
#       e passa o checkout ao agente
#   job-isolation.sh lock
#       com CLAUDE_CODE_OAUTH_TOKEN e FABRICA_GH_TOKEN no ambiente: grava os
#       segredos num arquivo só do proxy, sorteia os marcadores, sobe o
#       mitmdump com o egress-addon.py e a lista final de domínios e fecha a
#       rede do agente
#
# Falha fechada: qualquer erro sai com 1 antes de o agente poder rodar.
# Saídas: 0 pronto; 1 erro; 2 uso inválido.
#
# Variáveis (os padrões valem no runner; os testes trocam os binários e as
# pastas): FABRICA_ISOLATION_DIR, FABRICA_PROXY_PORT, FABRICA_AGENT_USER,
# FABRICA_PROXY_USER, FABRICA_PLUGIN_COPY, FABRICA_CA_DIR, FABRICA_PROXY_HOME,
# FABRICA_MITMDUMP_BIN, FABRICA_DOMAINS_FILE, FABRICA_WAIT_SECONDS,
# FABRICA_WORKSPACE_GROUP, FABRICA_SUDO_BIN, FABRICA_IPTABLES_BIN,
# FABRICA_IP6TABLES_BIN, FABRICA_USERADD_BIN, FABRICA_CHOWN_BIN,
# FABRICA_HOOKS_COPY (pasta dos hooks do git do agente) e FABRICA_GITCONFIG_FILE
# (arquivo de configuração global do agente, que aponta para a pasta dos hooks).
set -uo pipefail
export LC_ALL=C.UTF-8

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${FABRICA_ISOLATION_DIR:-/etc/fabrica}"
port="${FABRICA_PROXY_PORT:-8899}"
agent_user="${FABRICA_AGENT_USER:-fabrica-agent}"
proxy_user="${FABRICA_PROXY_USER:-fabrica-proxy}"
plugin_dst="${FABRICA_PLUGIN_COPY:-/opt/fabrica-plugin}"
hooks_dst="${FABRICA_HOOKS_COPY:-/opt/fabrica-githooks}"
gitconfig_dst="${FABRICA_GITCONFIG_FILE:-/opt/fabrica-gitconfig}"
ca_dir="${FABRICA_CA_DIR:-/usr/local/share/fabrica}"
proxy_home="${FABRICA_PROXY_HOME:-/var/lib/fabrica-proxy}"
mitm_bin="${FABRICA_MITMDUMP_BIN:-/opt/fabrica-mitm/bin/mitmdump}"
wait_seconds="${FABRICA_WAIT_SECONDS:-30}"
sudo_bin="${FABRICA_SUDO_BIN:-sudo}"
iptables_bin="${FABRICA_IPTABLES_BIN:-iptables}"
ip6tables_bin="${FABRICA_IP6TABLES_BIN:-ip6tables}"
useradd_bin="${FABRICA_USERADD_BIN:-useradd}"
chown_bin="${FABRICA_CHOWN_BIN:-chown}"

say() { echo "job-isolation: $*" >&2; }
fail() { say "$*"; exit 1; }
usage() { say "uso: job-isolation.sh prepare <pasta do plugin> <pasta do checkout> | lock"; exit 2; }

random_hex() { od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; }

# project_host_error <linha já sem espaços nas pontas e em minúsculas>:
# imprime o motivo de a linha não ser um host exato aceito, ou nada.
# Mais estrita que a lista do plugin: nenhum curinga (SPEC-108, ADR 0018).
project_host_error() {
  local host="$1" label='[a-z0-9]([a-z0-9-]*[a-z0-9])?'
  case $host in
    *'*'*) echo "curinga não é aceito na lista do projeto"; return ;;
    */*) echo "esquema ou caminho não é aceito, só o host"; return ;;
    *:*) echo "porta não é aceita, só o host"; return ;;
    *[[:space:]]*) echo "espaço no meio da linha"; return ;;
    *.*) ;;
    *) echo "host sem ponto"; return ;;
  esac
  [[ "$host" =~ ^$label(\.$label)+$ ]] || { echo "host inválido"; return; }
  [[ "${host##*.}" =~ [a-z] ]] || echo "IP não é aceito, só nome de host"
}

# build_domains <lista do plugin> <pasta do checkout>: grava em
# $dir/dominios.txt, de root e 0644, a lista do plugin seguida dos hosts de
# <checkout>/.fabrica/dominios.txt que ela ainda não tem. Uma linha inválida
# falha fechado, sem gravar a lista final.
build_domains() {
  local plugin_list="$1" project_list="$2/.fabrica/dominios.txt"
  local -A seen=()
  local -a extra=()
  local line host reason n=0 bad=0 tmp_list

  rm -f "$dir/dominios.txt" || fail "não consegui limpar $dir/dominios.txt."
  [[ -f "$plugin_list" ]] || fail "não achei a lista de domínios do plugin em $plugin_list."
  while IFS= read -r line || [[ -n "$line" ]]; do
    host="$(printf '%s' "$line" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ -n "$host" && "$host" != \#* ]] && seen[$host]=1
  done < "$plugin_list"

  if [[ -e "$project_list" || -L "$project_list" ]]; then
    # Root lê o arquivo: um link (no arquivo ou na pasta) poderia apontar
    # para fora do checkout e levar o conteúdo ao log do job.
    [[ -f "$project_list" && ! -L "$project_list" && ! -L "$2/.fabrica" ]] \
      || fail "o .fabrica/dominios.txt do projeto não é um arquivo comum; o agente não vai rodar."
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      host="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
      [[ -z "$host" || "$host" == \#* ]] && continue
      reason="$(project_host_error "$host")"
      if [[ -n "$reason" ]]; then
        say ".fabrica/dominios.txt, linha $n: \"$line\": $reason."
        bad=1
        continue
      fi
      [[ -n "${seen[$host]:-}" ]] && continue
      seen[$host]=1
      extra+=("$host")
    done < "$project_list"
    [[ $bad -eq 0 ]] || fail "a lista de domínios do projeto tem linha inválida; o agente não vai rodar."
  fi

  mkdir -p "$dir" || fail "não consegui criar $dir."
  chmod 0755 "$dir"
  tmp_list="$(mktemp "$dir/.dominios.XXXXXX")" || fail "não consegui gravar a lista final de domínios."
  {
    cat "$plugin_list"
    if [[ ${#extra[@]} -gt 0 ]]; then
      printf '\n# Hosts do projeto (.fabrica/dominios.txt da branch padrão).\n'
      printf '%s\n' "${extra[@]}"
    fi
  } > "$tmp_list" && chmod 0644 "$tmp_list" && mv -f "$tmp_list" "$dir/dominios.txt" \
    || { rm -f "$tmp_list"; fail "não consegui gravar a lista final de domínios."; }
}

cmd_prepare() {
  [[ $# -eq 2 ]] || usage
  local plugin_src="$1" workspace="$2" user group d
  [[ -f "$plugin_src/scripts/job-isolation.sh" ]] || fail "não achei o plugin instalado em $plugin_src."
  [[ -d "$workspace" ]] || fail "não achei a pasta do checkout $workspace."

  for user in "$agent_user" "$proxy_user"; do
    id -u "$user" >/dev/null 2>&1 && continue
    "$useradd_bin" --system --user-group --create-home --shell /usr/sbin/nologin "$user" \
      || fail "não consegui criar o usuário $user."
  done

  rm -rf "$plugin_dst" || fail "não consegui limpar $plugin_dst."
  mkdir -p "$plugin_dst" || fail "não consegui criar $plugin_dst."
  cp -a "$plugin_src/." "$plugin_dst/" || fail "não consegui copiar o plugin para $plugin_dst."
  rm -rf "$plugin_dst/.git"
  chmod -R a+rX,go-w "$plugin_dst"

  # Hooks do git da main (SPEC-107, CA22): cópia de root, sem escrita para o
  # agente, e o arquivo de configuração global do agente que aponta para ela.
  # Sem a configuração, o git do agente não teria os hooks, por isso falha
  # aqui e o lock não sobe.
  [[ -d "$plugin_src/githooks" ]] || fail "não achei a pasta githooks/ em $plugin_src."
  rm -rf "$hooks_dst" || fail "não consegui limpar $hooks_dst."
  mkdir -p "$hooks_dst" || fail "não consegui criar $hooks_dst."
  cp -a "$plugin_src/githooks/." "$hooks_dst/" || fail "não consegui copiar os hooks do git para $hooks_dst."
  chmod -R a+rX,go-w "$hooks_dst"
  {
    echo "[core]"
    echo "	hooksPath = $hooks_dst"
  } > "$gitconfig_dst" || fail "não consegui gravar $gitconfig_dst."
  chmod 0644 "$gitconfig_dst"

  # Lista final de domínios (SPEC-108, ADR 0018): lida do checkout enquanto
  # ele ainda não é do agente, que poderia editá-la antes do lock.
  build_domains "$plugin_dst/templates/workflows/dominios-liberados.txt" "$workspace"

  group="${FABRICA_WORKSPACE_GROUP:-${SUDO_USER:-runner}}"
  "$chown_bin" -R "$agent_user:$group" "$workspace" || fail "não consegui passar $workspace ao agente."
  chmod -R g+rwX "$workspace"
  # O agente precisa atravessar as pastas acima do checkout.
  d="$(dirname "$workspace")"
  while [[ "$d" != "/" && "$d" != "." ]]; do
    chmod o+x "$d" 2>/dev/null || true
    d="$(dirname "$d")"
  done
  say "usuários prontos, plugin copiado, lista de domínios gravada e checkout passado ao agente."
}

proxy_ready() {
  [[ -f "$proxy_home/.mitmproxy/mitmproxy-ca-cert.pem" ]] || return 1
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null
}

cmd_lock() {
  [[ $# -eq 0 ]] || usage
  local oauth="${CLAUDE_CODE_OAUTH_TOKEN:-}" ghtoken="${FABRICA_GH_TOKEN:-}"
  local addon="${FABRICA_ADDON_FILE:-$plugin_dst/scripts/egress-addon.py}"
  local domains="${FABRICA_DOMAINS_FILE:-$dir/dominios.txt}"
  local anth_marker gh_marker i

  [[ -n "$oauth" ]] || fail "o CLAUDE_CODE_OAUTH_TOKEN não está no ambiente."
  [[ -n "$ghtoken" ]] || fail "o FABRICA_GH_TOKEN não está no ambiente."
  case $oauth$ghtoken in
    *$'\n'*|*"'"*) fail "um dos tokens tem quebra de linha ou aspas simples." ;;
  esac
  [[ -f "$domains" ]] || fail "não achei a lista final de domínios $domains; rode job-isolation.sh prepare antes."
  [[ -f "$addon" ]] || fail "não achei o addon $addon."
  [[ -f "$gitconfig_dst" && -d "$hooks_dst" ]] \
    || fail "os hooks do git do agente não estão instalados; rode job-isolation.sh prepare antes."

  anth_marker="fabrica-marker-$(random_hex)"
  gh_marker="fabrica-marker-$(random_hex)"

  umask 077
  mkdir -p "$dir" "$proxy_home/.mitmproxy" || fail "não consegui criar as pastas do isolamento."
  chmod 0755 "$dir"
  chmod 0700 "$proxy_home" "$proxy_home/.mitmproxy"

  printf '{"%s":{"env":"CLAUDE_CODE_OAUTH_TOKEN","hosts":["api.anthropic.com"]},"%s":{"env":"FABRICA_GH_TOKEN","hosts":["github.com","api.github.com","uploads.github.com","codeload.github.com"]}}\n' \
    "$anth_marker" "$gh_marker" > "$dir/markers.json"
  {
    printf "export CLAUDE_CODE_OAUTH_TOKEN='%s'\n" "$oauth"
    printf "export FABRICA_GH_TOKEN='%s'\n" "$ghtoken"
  } > "$dir/proxy.env"
  chmod 0600 "$dir/markers.json" "$dir/proxy.env"

  # Valida antes de subir qualquer coisa: lista vazia, mapa inválido ou segredo
  # sem valor impedem o agente de rodar.
  (set -a; . "$dir/proxy.env"; exec python3 -I "$addon" check "$domains" "$dir/markers.json") \
    || fail "a configuração do proxy é inválida; o agente não vai rodar."

  # O que o agente enxerga: só marcadores e o caminho do proxy.
  umask 022
  {
    echo "CLAUDE_CODE_OAUTH_TOKEN=$anth_marker"
    echo "GH_TOKEN=$gh_marker"
    echo "HTTPS_PROXY=http://127.0.0.1:$port"
    echo "HTTP_PROXY=http://127.0.0.1:$port"
    echo "https_proxy=http://127.0.0.1:$port"
    echo "http_proxy=http://127.0.0.1:$port"
    echo "NODE_EXTRA_CA_CERTS=$ca_dir/ca.pem"
    echo "SSL_CERT_FILE=$ca_dir/ca.pem"
    echo "GIT_SSL_CAINFO=$ca_dir/ca.pem"
    echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
    # O git do agente lê só este arquivo, root-owned: o ~/.gitconfig dele
    # não sobrescreve a pasta dos hooks (SPEC-107, CA22 e CA23).
    echo "GIT_CONFIG_GLOBAL=$gitconfig_dst"
    # Destino dos hooks que o protect-main confere (SPEC-107, CA25 e CA26).
    echo "FABRICA_GITHOOKS_DEST=$hooks_dst"
  } > "$dir/agent.env"
  chmod 0644 "$dir/agent.env"
  : > "$dir/proxy.log"
  chmod 0644 "$dir/proxy.log"

  "$chown_bin" "$proxy_user:" "$dir/markers.json" "$dir/proxy.env" "$dir/proxy.log" \
    || fail "não consegui passar os arquivos do proxy ao $proxy_user."
  "$chown_bin" -R "$proxy_user:" "$proxy_home" || fail "não consegui passar a pasta do proxy ao $proxy_user."

  # O proxy lê os segredos do arquivo, não dos argumentos: o `ps` não os mostra.
  nohup "$sudo_bin" -n -u "$proxy_user" -H bash -c \
    '. "$1"; export PYTHONUNBUFFERED=1; exec "$2" --listen-host 127.0.0.1 --listen-port "$3" --set confdir="$4" --set flow_detail=0 --set fabrica_domains="$5" --set fabrica_markers="$6" -s "$7"' \
    _ "$dir/proxy.env" "$mitm_bin" "$port" "$proxy_home/.mitmproxy" "$domains" "$dir/markers.json" "$addon" \
    >> "$dir/proxy.log" 2>&1 &

  for ((i = 0; i < wait_seconds * 2; i++)); do
    proxy_ready && break
    sleep 0.5
  done
  proxy_ready || { tail -n 20 "$dir/proxy.log" >&2; fail "o proxy não subiu em ${wait_seconds}s."; }

  mkdir -p "$ca_dir" && cp "$proxy_home/.mitmproxy/mitmproxy-ca-cert.pem" "$ca_dir/ca.pem" \
    || fail "não consegui publicar o certificado público da CA."
  chmod 0755 "$ca_dir"
  chmod 0644 "$ca_dir/ca.pem"

  # Só depois do proxy de pé: o agente fala apenas com a porta dele.
  # `-I` na frente da cadeia: uma regra ACCEPT que o runner já tenha não passa
  # na frente. O REJECT entra primeiro e o ACCEPT do proxy entra na posição 1,
  # então a ordem final é ACCEPT do proxy e depois REJECT.
  "$iptables_bin" -I OUTPUT 1 -m owner --uid-owner "$agent_user" -j REJECT \
    || fail "não consegui fechar a rede do agente (iptables)."
  "$iptables_bin" -I OUTPUT 1 -m owner --uid-owner "$agent_user" -o lo -p tcp --dport "$port" -j ACCEPT \
    || fail "não consegui criar a regra do iptables que libera o proxy."
  "$ip6tables_bin" -I OUTPUT 1 -m owner --uid-owner "$agent_user" -j REJECT \
    || fail "não consegui fechar a rede do agente (ip6tables)."
  say "proxy na porta $port e rede do $agent_user fechada."
}

[[ $# -ge 1 ]] || usage
sub="$1"
shift
case $sub in
  prepare) cmd_prepare "$@" ;;
  lock) cmd_lock "$@" ;;
  *) usage ;;
esac
