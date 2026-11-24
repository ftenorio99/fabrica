#!/usr/bin/env bash
# Testa o isolamento do job do dispatcher (SPEC-106, CA1 a CA8 e CA10; SPEC-107,
# CA22 a CA26; SPEC-108, CA8 a CA12, marcados como 108-CA<n>): o addon
# do proxy, o job-isolation.sh e o run-as-agent.sh, com sudo, useradd, chown,
# iptables, claude e mitmdump falsos. O addon roda com um módulo mitmproxy
# falso, então não precisa do pacote.
# Uso: bash scripts/test-job-isolation.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
addon="$script_dir/egress-addon.py"
isolation="$script_dir/job-isolation.sh"
wrapper="$script_dir/run-as-agent.sh"
domains_file="$script_dir/../templates/workflows/dominios-liberados.txt"

tmp="$(mktemp -d)"
cleanup() {
  for pidfile in "$tmp"/*/proxy.pid; do
    [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

failures=0 total=0

# check <CA> <descrição> <esperado> <obtido>
check() {
  total=$((total + 1))
  if [[ "$4" == "$3" ]]; then
    printf 'ok      %-4s %s\n' "$1" "$2"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3" "$4"
  fi
}

# --- addon: funções puras e hooks, com um módulo mitmproxy falso ---

# py <expressão python>: avalia a expressão com o addon carregado como `m`,
# `mk(host, auth=None, extra=None)` para criar um fluxo e `logs` com o log.
py() {
  python3 -I -c '
import importlib.util, sys, types, base64
sys.dont_write_bytecode = True
class Resp:
    @staticmethod
    def make(status, content=b"", headers=None):
        return types.SimpleNamespace(status_code=status, content=content, headers=headers or {})
logs = []
ctx = types.SimpleNamespace(log=types.SimpleNamespace(info=lambda msg: logs.append(msg)))
pkg = types.ModuleType("mitmproxy")
pkg.http = types.SimpleNamespace(Response=Resp)
pkg.ctx = ctx
sys.modules["mitmproxy"] = pkg
spec = importlib.util.spec_from_file_location("egress", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
def mk(host, auth=None, extra=None):
    headers = {}
    if auth is not None:
        headers["Authorization"] = auth
    headers.update(extra or {})
    return types.SimpleNamespace(request=types.SimpleNamespace(host=host, headers=headers, content=b"corpo"), response=None)
def egress(domains, markers):
    e = m.Egress()
    e.domains = domains
    e.markers = markers
    return e
b64 = lambda s: base64.b64encode(s.encode()).decode()
unb64 = lambda s: base64.b64decode(s).decode()
print(eval(sys.argv[2]))
' "$addon" "$1"
}

# CA1: a lista de domínios.
check CA1 "host exato da lista é liberado" "True" "$(py 'm.host_allowed("github.com", ["github.com"])')"
check CA1 "*.dominio libera subdomínio" "True" "$(py 'm.host_allowed("a.example.com", ["*.example.com"])')"
check CA1 "*.dominio não libera o apex" "False" "$(py 'm.host_allowed("example.com", ["*.example.com"])')"
check CA1 "*.dominio não libera outro-dominio" "False" "$(py 'm.host_allowed("outro-example.com", ["*.example.com"])')"
check CA1 "maiúsculas não mudam o resultado" "True" "$(py 'm.host_allowed("GitHub.COM", ["github.com"])')"
check CA1 "host fora da lista é barrado" "False" "$(py 'm.host_allowed("example.org", ["github.com"])')"
check CA1 "api.github.com.evil.com é barrado" "False" "$(py 'm.host_allowed("api.github.com.evil.com", ["api.github.com"])')"
check CA1 "github.com. (ponto final) é barrado" "False" "$(py 'm.host_allowed("github.com.", ["github.com"])')"
check CA1 "a porta é ignorada: api.github.com:8443 é liberado" "True" "$(py 'm.host_allowed("api.github.com:8443", ["api.github.com"])')"
check CA1 "a porta é ignorada: host fora da lista com porta é barrado" "False" "$(py 'm.host_allowed("example.org:443", ["api.github.com"])')"
check CA1 "porta não destrava o ponto final" "False" "$(py 'm.host_allowed("github.com.:443", ["github.com"])')"
check CA1 "host vazio é barrado" "False" "$(py 'm.host_allowed("", ["github.com"])')"
check CA1 "CONNECT fora da lista recebe 403 com o host" "403 example.org" \
  "$(py '(lambda f: (egress(["github.com"], {}).http_connect(f), f.response.status_code, b"example.org" in f.response.content)[1:] )(mk("example.org"))' | sed 's/, True)/ example.org/; s/(//; s/)//; s/,//')"
check CA1 "pedido fora da lista recebe 403" "403" \
  "$(py '(lambda f: (egress(["github.com"], {}).request(f), f.response.status_code)[1])(mk("example.org"))')"
check CA1 "CONNECT de host liberado segue" "None" \
  "$(py '(lambda f: (egress(["github.com"], {}).http_connect(f), f.response)[1])(mk("github.com"))')"
check CA1 "pedido de host liberado segue e registra o host" "None permitido github.com" \
  "$(py '(lambda f, e: (e.request(f), str(f.response) + " " + logs[-1])[1])(mk("github.com"), egress(["github.com"], {}))')"

# CA2: a troca do marcador em Bearer, só no host do segredo.
markers_expr='{"fabrica-marker-aaaaaaaaaaaaaaaa": {"secret": "REAL-ANTHROPIC", "hosts": ["api.anthropic.com"]}, "fabrica-marker-bbbbbbbbbbbbbbbb": {"secret": "REAL-GITHUB", "hosts": ["github.com", "api.github.com"]}}'
doms_expr='["api.anthropic.com", "github.com", "api.github.com"]'
check CA2 "Bearer: marcador vira o valor real no host do segredo" "Bearer REAL-ANTHROPIC" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['Authorization'])[1])(mk('api.anthropic.com', 'Bearer fabrica-marker-aaaaaaaaaaaaaaaa'))")"
check CA2 "Bearer: o marcador da Anthropic não é trocado no GitHub" "Bearer fabrica-marker-aaaaaaaaaaaaaaaa" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['Authorization'])[1])(mk('github.com', 'Bearer fabrica-marker-aaaaaaaaaaaaaaaa'))")"
check CA2 "Bearer: o marcador do GitHub não é trocado na Anthropic" "Bearer fabrica-marker-bbbbbbbbbbbbbbbb" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['Authorization'])[1])(mk('api.anthropic.com', 'Bearer fabrica-marker-bbbbbbbbbbbbbbbb'))")"
check CA2 "host fora da lista: 403 e sem troca" "403 Bearer fabrica-marker-bbbbbbbbbbbbbbbb" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), str(f.response.status_code) + ' ' + f.request.headers['Authorization'])[1])(mk('evil.example', 'Bearer fabrica-marker-bbbbbbbbbbbbbbbb'))")"
check CA2 "token que não é marcador segue como veio" "Bearer outro-token" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['Authorization'])[1])(mk('github.com', 'Bearer outro-token'))")"

check CA2 "token: o esquema do gh também é trocado, só no host do segredo" "Token REAL-GITHUB Token fabrica-marker-bbbbbbbbbbbbbbbb" \
  "$(py "(lambda f, g: (egress($doms_expr, $markers_expr).request(f), egress($doms_expr, $markers_expr).request(g), f.request.headers['Authorization'] + ' ' + g.request.headers['Authorization'])[2])(mk('api.github.com', 'Token fabrica-marker-bbbbbbbbbbbbbbbb'), mk('api.anthropic.com', 'Token fabrica-marker-bbbbbbbbbbbbbbbb'))")"

# CA3: o Basic do git.
check CA3 "Basic: o marcador vira o valor real em github.com" "x-access-token:REAL-GITHUB" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), unb64(f.request.headers['Authorization'].split(' ')[1]))[1])(mk('github.com', 'Basic ' + b64('x-access-token:fabrica-marker-bbbbbbbbbbbbbbbb')))")"
check CA3 "Basic: continua um Basic válido" "Basic" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['Authorization'].split(' ')[0])[1])(mk('github.com', 'Basic ' + b64('x-access-token:fabrica-marker-bbbbbbbbbbbbbbbb')))")"
check CA3 "Basic: base64 inválido segue como veio" "Basic ***" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['Authorization'])[1])(mk('github.com', 'Basic ***'))")"

# CA4: só o cabeçalho Authorization; o valor real não vai para log nem para o 403.
check CA4 "outro cabeçalho com o marcador não é trocado" "fabrica-marker-bbbbbbbbbbbbbbbb" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.headers['X-Outro'])[1])(mk('github.com', 'Bearer fabrica-marker-bbbbbbbbbbbbbbbb', {'X-Outro': 'fabrica-marker-bbbbbbbbbbbbbbbb'}))")"
check CA4 "o corpo do pedido não é tocado" "b'corpo'" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), f.request.content)[1])(mk('github.com', 'Bearer fabrica-marker-bbbbbbbbbbbbbbbb'))")"
check CA4 "o log não traz o valor real" "False" \
  "$(py "(lambda f, e: (e.request(f), 'REAL-GITHUB' in ' '.join(logs))[1])(mk('github.com', 'Bearer fabrica-marker-bbbbbbbbbbbbbbbb'), egress($doms_expr, $markers_expr))")"
check CA4 "o 403 não traz o valor real" "False" \
  "$(py "(lambda f: (egress($doms_expr, $markers_expr).request(f), b'REAL' in f.response.content)[1])(mk('evil.example', 'Bearer fabrica-marker-bbbbbbbbbbbbbbbb'))")"

# CA5: falha fechada na configuração.
cfg="$tmp/cfg"; mkdir -p "$cfg"
printf '# só comentário\n\n' > "$cfg/comentarios.txt"
: > "$cfg/vazia.txt"
printf 'api.anthropic.com\n' > "$cfg/ok.txt"
printf '*.com\n' > "$cfg/larga.txt"
printf '{"fabrica-marker-aaaaaaaaaaaaaaaa": {"env": "TOKEN_A", "hosts": ["api.anthropic.com"]}}\n' > "$cfg/markers-ok.json"
printf 'isto não é json\n' > "$cfg/markers-ruim.json"
printf '{"fabrica-marker-aaaaaaaaaaaaaaaa": {"env": "TOKEN_A"}}\n' > "$cfg/markers-sem-hosts.json"
printf '{"curto": {"env": "TOKEN_A", "hosts": ["api.anthropic.com"]}}\n' > "$cfg/markers-curto.json"
printf '{}\n' > "$cfg/markers-vazio.json"
chk() { TOKEN_A="${3-valor}" python3 -I "$addon" check "$cfg/$1" "$cfg/$2" >/dev/null 2>&1; echo $?; }
check CA5 "configuração boa passa" "0" "$(chk ok.txt markers-ok.json)"
check CA5 "lista ausente falha" "1" "$(chk nao-existe.txt markers-ok.json)"
check CA5 "lista vazia falha" "1" "$(chk vazia.txt markers-ok.json)"
check CA5 "lista só com comentários falha" "1" "$(chk comentarios.txt markers-ok.json)"
check CA5 "domínio largo demais falha" "1" "$(chk larga.txt markers-ok.json)"
check CA5 "mapa que não é JSON falha" "1" "$(chk ok.txt markers-ruim.json)"
check CA5 "entrada sem hosts falha" "1" "$(chk ok.txt markers-sem-hosts.json)"
check CA5 "marcador curto demais falha" "1" "$(chk ok.txt markers-curto.json)"
check CA5 "mapa vazio falha" "1" "$(chk ok.txt markers-vazio.json)"
check CA5 "segredo sem valor no ambiente falha" "1" "$(chk ok.txt markers-ok.json '')"
check CA5 "a mensagem de erro diz qual variável falta" "True" \
  "$(msg="$(TOKEN_A='' python3 -I "$addon" check "$cfg/ok.txt" "$cfg/markers-ok.json" 2>&1)"; [[ "$msg" == *TOKEN_A* ]] && echo True || echo False)"

# CA10: a lista de domínios versionada.
check CA10 "tem a API da Anthropic e os hosts do GitHub" "5" \
  "$(grep -c -x -E 'api\.anthropic\.com|github\.com|api\.github\.com|codeload\.github\.com|uploads\.github\.com' "$domains_file")"
check CA10 "não tem curinga largo" "0" \
  "$(grep -c -E '^\*$|^\*\.github\.com$|^\*\.githubusercontent\.com$' "$domains_file")"
check CA10 "tem comentários que explicam os hosts" "True" \
  "$([[ "$(grep -c '^#' "$domains_file")" -ge 3 ]] && echo True || echo False)"
check CA10 "o addon aceita a lista" "0" "$(TOKEN_A=valor python3 -I "$addon" check "$domains_file" "$cfg/markers-ok.json" >/dev/null 2>&1; echo $?)"

# --- job-isolation.sh e run-as-agent.sh com binários falsos ---
bin="$tmp/bin"; mkdir -p "$bin"

cat > "$bin/sudo" <<'EOF'
#!/usr/bin/env bash
# sudo falso: registra e executa o comando como o usuário atual.
echo "sudo $*" >> "$FAKE_CALLS"
[[ "$1" == "-n" ]] && shift
[[ "$1" == "-u" ]] && shift 2
[[ "$1" == "-H" ]] && shift
exec "$@"
EOF
cat > "$bin/useradd" <<'EOF'
#!/usr/bin/env bash
echo "useradd $*" >> "$FAKE_CALLS"
mkdir -p "$FAKE_USERS"; touch "$FAKE_USERS/${@: -1}"
EOF
cat > "$bin/id" <<'EOF'
#!/usr/bin/env bash
[[ -e "$FAKE_USERS/${@: -1}" ]]
EOF
cat > "$bin/chown" <<'EOF'
#!/usr/bin/env bash
echo "chown $*" >> "$FAKE_CALLS"
# Registra se a lista final de domínios já existia quando o checkout foi
# passado ao agente (SPEC-108, CA8).
if [[ "$1" == "-R" && "$2" == fabrica-agent:* ]]; then
  [[ -f "$FAKE_STATE/etc/dominios.txt" ]] && echo sim > "$FAKE_STATE/lista-antes-do-chown" \
    || echo nao > "$FAKE_STATE/lista-antes-do-chown"
fi
EOF
for tool in iptables ip6tables; do
  cat > "$bin/$tool" <<EOF
#!/usr/bin/env bash
echo "$tool \$*" >> "\$FAKE_CALLS"
EOF
done
cat > "$bin/mitmdump" <<'EOF'
#!/usr/bin/env python3
# mitmdump falso: grava a CA, o argv e os segredos que recebeu, e abre a porta.
import os, socket, sys, time
args = sys.argv[1:]
def opt(name):
    return args[args.index(name) + 1]
conf = [a.split("=", 1)[1] for a in args if a.startswith("confdir=")][0]
os.makedirs(conf, exist_ok=True)
open(os.path.join(conf, "mitmproxy-ca-cert.pem"), "w").write("CERTIFICADO-PUBLICO\n")
open(os.path.join(conf, "mitmproxy-ca.pem"), "w").write("CHAVE-PRIVADA\n")
base = os.path.dirname(conf.rstrip("/"))
open(os.path.join(os.environ["FAKE_STATE"], "proxy.argv"), "w").write(" ".join(args) + "\n")
open(os.path.join(os.environ["FAKE_STATE"], "proxy.env.seen"), "w").write(
    "%s %s\n" % (os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", ""), os.environ.get("FABRICA_GH_TOKEN", "")))
open(os.path.join(os.environ["FAKE_STATE"], "proxy.pid"), "w").write(str(os.getpid()))
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(opt("--listen-port"))))
s.listen(5)
time.sleep(60)
EOF
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
# claude falso: imprime os argumentos e o ambiente que recebeu.
for arg in "$@"; do echo "arg:$arg"; done
env | sed 's/^/env:/'
[[ " $* " == *" --falha "* ]] && exit 7
exit 0
EOF
chmod +x "$bin"/*

free_port() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

# new_case <nome>: pasta de estado e variáveis de um caso; imprime a pasta.
new_case() {
  local d="$tmp/$1"
  mkdir -p "$d/users" "$d/plugin/scripts" "$d/plugin/templates/workflows" "$d/work/projeto"
  cp "$isolation" "$wrapper" "$addon" "$d/plugin/scripts/"
  cp "$domains_file" "$d/plugin/templates/workflows/"
  cp -r "$script_dir/../githooks" "$d/plugin/githooks"
  mkdir -p "$d/plugin/.git"; echo x > "$d/plugin/.git/config"
  : > "$d/calls.log"
  echo "$d"
}

# iso <pasta> <subcomando...>: roda o job-isolation.sh do caso com tudo falso.
iso() {
  local d="$1"; shift
  PATH="$bin:$PATH" FAKE_CALLS="$d/calls.log" FAKE_USERS="$d/users" FAKE_STATE="$d" \
    FABRICA_SUDO_BIN="$bin/sudo" FABRICA_USERADD_BIN="$bin/useradd" FABRICA_CHOWN_BIN="$bin/chown" \
    FABRICA_IPTABLES_BIN="$bin/iptables" FABRICA_IP6TABLES_BIN="$bin/ip6tables" \
    FABRICA_MITMDUMP_BIN="$bin/mitmdump" FABRICA_ISOLATION_DIR="$d/etc" FABRICA_PROXY_HOME="$d/proxyhome" \
    FABRICA_PLUGIN_COPY="${PLUGIN_COPY:-$d/opt-plugin}" FABRICA_CA_DIR="$d/ca" FABRICA_PROXY_PORT="${PORT:-0}" \
    FABRICA_HOOKS_COPY="$d/opt-githooks" FABRICA_GITCONFIG_FILE="$d/opt-gitconfig" \
    FABRICA_WAIT_SECONDS=10 FABRICA_WORKSPACE_GROUP=runner \
    bash "$d/plugin/scripts/job-isolation.sh" "$@"
}

# CA6: prepare.
c="$(new_case prepare)"
iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1
check CA6 "prepare sai com 0" "0" "$(iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1; echo $?)"
check CA6 "cria os dois usuários com shell nologin, uma vez cada" "2" \
  "$(grep -c '^useradd .*--shell /usr/sbin/nologin' "$c/calls.log")"
check CA6 "cria fabrica-agent e fabrica-proxy" "fabrica-agent fabrica-proxy" \
  "$(grep '^useradd' "$c/calls.log" | awk '{print $NF}' | sort | tr '\n' ' ' | sed 's/ $//')"
check CA6 "rodar de novo não cria os usuários outra vez" "2" "$(grep -c '^useradd' "$c/calls.log")"
check CA6 "passa o checkout ao agente" "True" \
  "$(grep -q "^chown -R fabrica-agent:runner $c/work/projeto\$" "$c/calls.log" && echo True || echo False)"
check CA6 "copia o plugin sem o .git" "True" \
  "$([[ -f "$c/opt-plugin/scripts/job-isolation.sh" && ! -e "$c/opt-plugin/.git" ]] && echo True || echo False)"
check CA6 "não escreve em /etc/sudoers" "0" "$(grep -c 'sudoers' "$isolation")"
check CA6 "sem o plugin no caminho, falha" "1" \
  "$(iso "$c" prepare "$c/nao-existe" "$c/work/projeto" >/dev/null 2>&1; echo $?)"

# CA22: hooks do git do agente, instalados pelo prepare (c é o caso do prepare).
check CA22 "copia os hooks da pasta githooks/ do plugin" "True" \
  "$([[ -x "$c/opt-githooks/pre-commit" && -f "$c/opt-githooks/fabrica-hook" ]] && echo True || echo False)"
check CA22 "a pasta dos hooks não tem escrita para o grupo nem para outros" "0" \
  "$(find "$c/opt-githooks" -perm /022 | wc -l)"
check CA22 "o arquivo de configuração aponta para a pasta dos hooks" "True" \
  "$(grep -q "hooksPath = $c/opt-githooks\$" "$c/opt-gitconfig" && echo True || echo False)"
check CA22 "o arquivo de configuração não tem escrita para o grupo nem para outros" "644" \
  "$(stat -c %a "$c/opt-gitconfig")"
check CA1 "o arquivo de configuração tem user.name do agente" "fabrica-agent" \
  "$(git config --file "$c/opt-gitconfig" --get user.name)"
check CA1 "o arquivo de configuração tem user.email noreply do agente" "fabrica-agent@users.noreply.github.com" \
  "$(git config --file "$c/opt-gitconfig" --get user.email)"
check CA22 "prepare sem a pasta githooks/ no plugin falha" "1" \
  "$(c2="$(new_case semhooks)"; rm -rf "$c2/plugin/githooks"; iso "$c2" prepare "$c2/plugin" "$c2/work/projeto" >/dev/null 2>&1; echo $?)"

# CA23: o hook recusa commit na main com a configuração do agente e aceita na
# branch de feature. O git roda com GIT_CONFIG_GLOBAL no arquivo do prepare e
# um ~/.gitconfig do teste que aponta para outra pasta, que tem de ser ignorado.
g="$tmp/git23"; mkdir -p "$g/home" "$g/vazio"
mkdir -p "$g/ro" && cp "$c/opt-gitconfig" "$g/ro/gitconfig"
cfg="$g/ro/gitconfig"
printf '[core]\n\thooksPath = %s\n' "$g/vazio" > "$g/home/.gitconfig"
repo="$g/repo"
git init -q -b main "$repo"
git -C "$repo" -c user.name=teste -c user.email=teste@exemplo.com commit -q --allow-empty -m inicial
printf '[user]\n\tname = outro\n\temail = outro@exemplo.com\n' >> "$g/home/.gitconfig"
agent_git() {
  env -i PATH="$PATH" HOME="$g/home" GIT_CONFIG_GLOBAL="$cfg" git -C "$repo" "$@"
}
check CA23 "commit direto na main é recusado pelo hook da fábrica" "1" \
  "$(agent_git commit -q --allow-empty -m x 2>&1 >/dev/null | grep -c 'bloqueado')"
check CA23 "a main não recebe o commit recusado" "1" "$(agent_git rev-list --count main)"
agent_git switch -q -c feat/1-teste
check CA23 "commit numa branch de feature passa" "aceito" \
  "$(agent_git commit -q --allow-empty -m x >/dev/null 2>&1 && echo aceito || echo recusado)"
# CA2: a identidade vem do arquivo, não do ~/.gitconfig com outro [user].
want="fabrica-agent <fabrica-agent@users.noreply.github.com>"
check CA2 "autor e committer são os do arquivo do prepare" "$want|$want" \
  "$(agent_git log -1 --format='%an <%ae>|%cn <%ce>')"
# CA3: controle negativo, sem [user] o commit falha.
cp "$cfg" "$g/semuser"; git config --file "$g/semuser" --remove-section user
before="$(agent_git rev-list --count feat/1-teste)"
neg_rc="$(env -i PATH="$PATH" HOME="$g/home" GIT_CONFIG_GLOBAL="$g/semuser" git -C "$repo" -c user.useConfigOnly=true commit -q --allow-empty -m y >/dev/null 2>&1; echo $?)"
check CA3 "sem [user] o commit falha" "falhou" "$([[ $neg_rc -ne 0 ]] && echo falhou || echo passou)"
check CA3 "a branch não muda" "$before" "$(agent_git rev-list --count feat/1-teste)"
# Como o runner: a pasta é do root e o agente não escreve nela. O git grava
# por arquivo de trabalho e renomeação, então a pasta sem escrita é o que
# impede a alteração.
chmod 0555 "$g/ro"
check CA23 "git config global do agente não consegue mudar a configuração dos hooks" "falhou" \
  "$(agent_git config --global core.editor vim >/dev/null 2>&1 && echo gravou || echo falhou)"
chmod 0755 "$g/ro"

# CA7: lock.
c="$(new_case lock)"
PORT="$(free_port)"
oauth_real="REAL-OAUTH-TOKEN-0123456789abcdef"
gh_real="REAL-GH-TOKEN-0123456789abcdef"
iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1
lock_out="$(PLUGIN_COPY="$c/plugin" CLAUDE_CODE_OAUTH_TOKEN="$oauth_real" FABRICA_GH_TOKEN="$gh_real" iso "$c" lock 2>&1; echo "rc=$?")"
check CA7 "lock sai com 0" "rc=0" "$(echo "$lock_out" | tail -n 1)"
[[ "$(echo "$lock_out" | tail -n 1)" == "rc=0" ]] && : || echo "$lock_out" | head -n 8 | sed 's/^/        lock: /'
check CA7 "iptables: entra na frente da cadeia, REJECT e depois o ACCEPT do proxy na posição 1" \
  "iptables -I OUTPUT 1 -m owner --uid-owner fabrica-agent -j REJECT|iptables -I OUTPUT 1 -m owner --uid-owner fabrica-agent -o lo -p tcp --dport $PORT -j ACCEPT" \
  "$(grep '^iptables' "$c/calls.log" | paste -sd '|')"
check CA7 "ip6tables: rejeita tudo do agente, na frente da cadeia" "ip6tables -I OUTPUT 1 -m owner --uid-owner fabrica-agent -j REJECT" \
  "$(grep '^ip6tables' "$c/calls.log" | paste -sd '|')"
check CA7 "nenhuma regra vale para outro uid" "0" \
  "$(grep -E '^ip6?tables' "$c/calls.log" | grep -c -v -- '--uid-owner fabrica-agent')"
check CA7 "o proxy só sobe depois e antes das regras" "True" \
  "$([[ -f "$c/proxy.pid" ]] && echo True || echo False)"
check CA7 "proxy.env é 0600 e tem os valores reais" "600 True" \
  "$(stat -c %a "$c/etc/proxy.env") $(grep -q "$oauth_real" "$c/etc/proxy.env" && grep -q "$gh_real" "$c/etc/proxy.env" && echo True || echo False)"
check CA7 "markers.json é 0600" "600" "$(stat -c %a "$c/etc/markers.json")"
check CA7 "a pasta da CA do proxy é 0700" "700 700" "$(stat -c %a "$c/proxyhome/.mitmproxy") $(stat -c %a "$c/proxyhome")"
check CA7 "só o certificado público vai para a pasta do agente, 0644" "ca.pem 644 CERTIFICADO-PUBLICO" \
  "$(ls "$c/ca") $(stat -c %a "$c/ca/ca.pem") $(cat "$c/ca/ca.pem")"
check CA7 "agent.env é 0644 e não tem valor real" "644 0" \
  "$(stat -c %a "$c/etc/agent.env") $(grep -c -e "$oauth_real" -e "$gh_real" "$c/etc/agent.env")"
check CA7 "agent.env tem os dois marcadores e o proxy" "2 True" \
  "$(grep -c '=fabrica-marker-' "$c/etc/agent.env") $(grep -q "^HTTPS_PROXY=http://127.0.0.1:$PORT\$" "$c/etc/agent.env" && echo True || echo False)"
check CA22 "agent.env manda o git do agente para o arquivo de configuração" "1 True" \
  "$(grep -c '^GIT_CONFIG_GLOBAL=' "$c/etc/agent.env") $(grep -q "^GIT_CONFIG_GLOBAL=$c/opt-gitconfig\$" "$c/etc/agent.env" && echo True || echo False)"
check CA26 "agent.env grava o destino dos hooks que o protect-main confere" "1 True" \
  "$(grep -c '^FABRICA_GITHOOKS_DEST=' "$c/etc/agent.env") $(grep -q "^FABRICA_GITHOOKS_DEST=$c/opt-githooks\$" "$c/etc/agent.env" && echo True || echo False)"
check CA22 "lock sem os hooks instalados falha antes de subir o proxy" "1" \
  "$(c3="$(new_case semprep)"; PLUGIN_COPY="$c3/plugin" CLAUDE_CODE_OAUTH_TOKEN=x FABRICA_GH_TOKEN=y iso "$c3" lock >/dev/null 2>&1; echo $?)"
check CA7 "o proxy recebeu os segredos pelo ambiente" "$oauth_real $gh_real" "$(cat "$c/proxy.env.seen")"
check CA7 "os segredos não estão nos argumentos do proxy nem das chamadas" "0" \
  "$(cat "$c/proxy.argv" "$c/calls.log" | grep -c -e "$oauth_real" -e "$gh_real")"
check CA7 "o log do proxy não tem segredo" "0" "$(grep -c -e "$oauth_real" -e "$gh_real" "$c/etc/proxy.log")"
check CA7 "o mapa de marcadores não tem segredo" "0" "$(grep -c -e "$oauth_real" -e "$gh_real" "$c/etc/markers.json")"

# CA5 (lock): configuração inválida não sobe nada.
c2="$(new_case lock-vazio)"
: > "$c2/plugin/templates/workflows/dominios-liberados.txt"
iso "$c2" prepare "$c2/plugin" "$c2/work/projeto" >/dev/null 2>&1
: > "$c2/calls.log"
PORT="$(free_port)"
rc="$(PLUGIN_COPY="$c2/plugin" CLAUDE_CODE_OAUTH_TOKEN="$oauth_real" FABRICA_GH_TOKEN="$gh_real" iso "$c2" lock >/dev/null 2>&1; echo $?)"
check CA5 "lock com lista vazia sai com 1" "1" "$rc"
check CA5 "lock com lista vazia não sobe o proxy nem mexe no iptables" "0 False" \
  "$(grep -c -E '^(iptables|ip6tables)' "$c2/calls.log") $([[ -f "$c2/proxy.pid" ]] && echo True || echo False)"
c3="$(new_case lock-sem-token)"
rc="$(PLUGIN_COPY="$c3/plugin" CLAUDE_CODE_OAUTH_TOKEN="$oauth_real" iso "$c3" lock >/dev/null 2>&1; echo $?)"
check CA5 "lock sem o FABRICA_GH_TOKEN sai com 1 e não fecha a rede" "1 0" \
  "$rc $(grep -c -E '^(iptables|ip6tables)' "$c3/calls.log")"

# --- SPEC-108: lista de domínios do projeto (.fabrica/dominios.txt) ---

# 108-CA8: lista válida do projeto, acrescentada à do plugin sem repetição.
c="$(new_case dominios-ok)"
mkdir -p "$c/work/projeto/.fabrica"
printf '# pnpm e corepack\nregistry.npmjs.org\n\n  Registry-1.Docker.IO  \napi.github.com\nregistry.npmjs.org\r\n' > "$c/work/projeto/.fabrica/dominios.txt"
rc="$(iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1; echo $?)"
check 108-CA8 "prepare com lista válida sai com 0" "0" "$rc"
check 108-CA8 "a lista final começa com a do plugin, sem mudança" "igual" \
  "$(head -n "$(wc -l < "$domains_file")" "$c/etc/dominios.txt" | cmp -s - "$domains_file" && echo igual || echo diferente)"
check 108-CA8 "os hosts do projeto vêm depois, normalizados e sem repetição" "registry.npmjs.org registry-1.docker.io" \
  "$(tail -n +"$(($(wc -l < "$domains_file") + 1))" "$c/etc/dominios.txt" | grep -v -e '^#' -e '^$' | paste -sd ' ')"
check 108-CA8 "um host que já está na lista do plugin não se repete" "1" "$(grep -c -x 'api.github.com' "$c/etc/dominios.txt")"
check 108-CA8 "a lista final é 0644" "644" "$(stat -c %a "$c/etc/dominios.txt")"
check 108-CA8 "a lista final já existia quando o checkout passou ao agente" "sim" "$(cat "$c/lista-antes-do-chown" 2>/dev/null)"
check 108-CA8 "o addon aceita a lista final" "0" \
  "$(TOKEN_A=valor python3 -I "$addon" check "$c/etc/dominios.txt" "$tmp/cfg/markers-ok.json" >/dev/null 2>&1; echo $?)"
check 108-CA8 "o arquivo do projeto não é alterado" "6" "$(wc -l < "$c/work/projeto/.fabrica/dominios.txt")"
check 108-CA8 "um .fabrica/dominios.txt que é link falha fechado" "1 False" \
  "$(c2="$(new_case dominios-link)"; mkdir -p "$c2/work/projeto/.fabrica"; echo segredo.example.com > "$c2/fora.txt"
     ln -s "$c2/fora.txt" "$c2/work/projeto/.fabrica/dominios.txt"
     echo "$(iso "$c2" prepare "$c2/plugin" "$c2/work/projeto" >/dev/null 2>&1; echo $?) $([[ -f "$c2/etc/dominios.txt" ]] && echo True || echo False)")"
check 108-CA8 "uma pasta .fabrica que é link falha fechado" "1" \
  "$(c2="$(new_case dominios-pasta-link)"; mkdir -p "$c2/fora"; echo x.example.com > "$c2/fora/dominios.txt"
     ln -s "$c2/fora" "$c2/work/projeto/.fabrica"
     iso "$c2" prepare "$c2/plugin" "$c2/work/projeto" >/dev/null 2>&1; echo $?)"

# 108-CA9: sem arquivo, ou só com comentários e linhas vazias, igual à do plugin.
c="$(new_case dominios-sem)"
iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1
check 108-CA9 "sem .fabrica/dominios.txt, a lista final é igual à do plugin" "igual" \
  "$(cmp -s "$c/etc/dominios.txt" "$domains_file" && echo igual || echo diferente)"
c="$(new_case dominios-comentarios)"
mkdir -p "$c/work/projeto/.fabrica"
printf '# nada por enquanto\n\n   \n' > "$c/work/projeto/.fabrica/dominios.txt"
iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1
check 108-CA9 "só com comentários e linhas vazias, a lista final é igual à do plugin" "igual" \
  "$(cmp -s "$c/etc/dominios.txt" "$domains_file" && echo igual || echo diferente)"

# 108-CA10: cada forma inválida falha fechado, com a linha em stderr.
for bad in '*' '*.npmjs.org' 'https://x.org' 'x.org:443' 'a b.org' 'localhost' '10.0.0.1' '-x.org' 'x-.org' 'x..org'; do
  c="$(new_case "dominios-invalido-$(printf '%s' "$bad" | md5sum | cut -c1-8)")"
  mkdir -p "$c/work/projeto/.fabrica"
  printf 'registry.npmjs.org\n%s\n' "$bad" > "$c/work/projeto/.fabrica/dominios.txt"
  err="$(iso "$c" prepare "$c/plugin" "$c/work/projeto" 2>&1 >/dev/null)"; rc=$?
  check 108-CA10 "\"$bad\": sai com 1, com a linha em stderr, sem lista final e sem passar o checkout" "1 True False 0" \
    "$rc $([[ "$err" == *"linha 2: \"$bad\""* ]] && echo True || echo False) $([[ -f "$c/etc/dominios.txt" ]] && echo True || echo False) $(grep -c '^chown -R fabrica-agent' "$c/calls.log")"
done
c="$(new_case dominios-invalido-depois)"
mkdir -p "$c/etc" "$c/work/projeto/.fabrica"
echo velho > "$c/etc/dominios.txt"
echo '*.org' > "$c/work/projeto/.fabrica/dominios.txt"
iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1
check 108-CA10 "uma lista final de um prepare anterior não sobra depois da falha" "False" \
  "$([[ -f "$c/etc/dominios.txt" ]] && echo True || echo False)"

# 108-CA11: o lock lê a lista final; sem ela, falha antes de subir o proxy.
c="$(new_case dominios-lock)"
mkdir -p "$c/work/projeto/.fabrica"
echo registry.npmjs.org > "$c/work/projeto/.fabrica/dominios.txt"
iso "$c" prepare "$c/plugin" "$c/work/projeto" >/dev/null 2>&1
PORT="$(free_port)"
rc="$(CLAUDE_CODE_OAUTH_TOKEN="$oauth_real" FABRICA_GH_TOKEN="$gh_real" iso "$c" lock >/dev/null 2>&1; echo $?)"
check 108-CA11 "lock com a lista final sai com 0" "0" "$rc"
check 108-CA11 "o proxy recebe a lista final" "True" \
  "$(grep -q "fabrica_domains=$c/etc/dominios.txt " "$c/proxy.argv" && echo True || echo False)"
check 108-CA12 "o markers.json não tem host do projeto" "0" "$(grep -c 'npmjs' "$c/etc/markers.json")"
check 108-CA12 "o markers.json continua com os hosts fixos de cada segredo" \
  '["api.anthropic.com"] ["github.com","api.github.com","uploads.github.com","codeload.github.com"]' \
  "$(python3 -I -c 'import json, sys; print(" ".join(json.dumps(v["hosts"], separators=(",", ":")) for v in sorted(json.load(open(sys.argv[1])).values(), key=lambda v: v["env"])))' "$c/etc/markers.json")"
c="$(new_case dominios-lock-sem-prepare)"
mkdir -p "$c/opt-githooks"; : > "$c/opt-gitconfig"
err="$(PLUGIN_COPY="$c/plugin" CLAUDE_CODE_OAUTH_TOKEN=x FABRICA_GH_TOKEN=y iso "$c" lock 2>&1 >/dev/null)"; rc=$?
check 108-CA11 "lock sem a lista final sai com 1 e pede o prepare" "1 True" \
  "$rc $([[ "$err" == *"rode job-isolation.sh prepare antes"* ]] && echo True || echo False)"
check 108-CA11 "lock sem a lista final não sobe o proxy nem mexe no iptables" "0 False" \
  "$(grep -c -E '^(iptables|ip6tables)' "$c/calls.log") $([[ -f "$c/proxy.pid" ]] && echo True || echo False)"
PORT="$(free_port)"
rc="$(PLUGIN_COPY="$c/plugin" FABRICA_DOMAINS_FILE="$domains_file" CLAUDE_CODE_OAUTH_TOKEN=x FABRICA_GH_TOKEN=y iso "$c" lock >/dev/null 2>&1; echo $?)"
check 108-CA11 "o FABRICA_DOMAINS_FILE continua trocando o arquivo" "0 True" \
  "$rc $(grep -q "fabrica_domains=$domains_file " "$c/proxy.argv" && echo True || echo False)"

# CA8: run-as-agent.sh.
c4="$(new_case wrapper)"
mkdir -p "$c4/etc"
printf 'CLAUDE_CODE_OAUTH_TOKEN=fabrica-marker-zzzz\nGH_TOKEN=fabrica-marker-yyyy\nHTTPS_PROXY=http://127.0.0.1:8899\nlinha invalida\n' > "$c4/etc/agent.env"
wrap() {
  PATH="$bin:$PATH" FAKE_CALLS="$c4/calls.log" FABRICA_SUDO_BIN="$bin/sudo" FABRICA_ISOLATION_DIR="$c4/etc" \
    FABRICA_PLUGIN_COPY=/opt/fabrica-plugin FABRICA_AGENT_HOME=/home/fabrica-agent \
    SEGREDO_DO_RUNNER=vazou CLAUDE_CODE_OAUTH_TOKEN="$oauth_real" FABRICA_GH_TOKEN="$gh_real" GITHUB_TOKEN=gh-do-runner \
    bash "$wrapper" "$@"
}
out="$(wrap -p --model m "/fabrica:triagem 5" 2>&1)"
check CA8 "passa o --plugin-dir da cópia e os argumentos, sem mudar nada" "--plugin-dir|/opt/fabrica-plugin|-p|--model|m|/fabrica:triagem 5" \
  "$(echo "$out" | grep '^arg:' | sed 's/^arg://' | paste -sd '|')"
check CA8 "chama o sudo como fabrica-agent" "True" \
  "$(grep -q '^sudo -n -u fabrica-agent -H env -i ' "$c4/calls.log" && echo True || echo False)"
check CA8 "o ambiente tem os marcadores e o proxy" "fabrica-marker-zzzz fabrica-marker-yyyy http://127.0.0.1:8899" \
  "$(echo "$out" | sed -n 's/^env:CLAUDE_CODE_OAUTH_TOKEN=//p') $(echo "$out" | sed -n 's/^env:GH_TOKEN=//p') $(echo "$out" | sed -n 's/^env:HTTPS_PROXY=//p')"
check CA8 "nenhum valor real nem variável do runner chega ao agente" "0" \
  "$(echo "$out" | grep -c -e "$oauth_real" -e "$gh_real" -e SEGREDO_DO_RUNNER -e gh-do-runner -e FABRICA_GH_TOKEN -e GITHUB_TOKEN)"
check CA8 "o ambiente só tem as variáveis da lista fechada" "CLAUDE_CODE_OAUTH_TOKEN GH_TOKEN HOME HTTPS_PROXY LANG PATH" \
  "$(echo "$out" | sed -n 's/^env:\([A-Za-z_]*\)=.*/\1/p' | grep -v -x -e _ -e PWD -e SHLVL -e OLDPWD | sort | tr '\n' ' ' | sed 's/ $//')"
check CA8 "linha inválida do agent.env é ignorada" "0" "$(echo "$out" | grep -c 'linha invalida')"
check CA8 "o código de saída do claude é preservado" "7" "$(wrap -p --falha >/dev/null 2>&1; echo $?)"
check CA8 "um --plugin-dir já dado não é repetido" "1" "$(wrap --plugin-dir /outro -p 2>&1 | grep -c '^arg:--plugin-dir$')"
check CA8 "sem o agent.env, falha com 1" "1" "$(FABRICA_ISOLATION_DIR="$c4/nao-existe" PATH="$bin:$PATH" bash "$wrapper" -p >/dev/null 2>&1; echo $?)"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
