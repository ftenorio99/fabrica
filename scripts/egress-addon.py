#!/usr/bin/env python3
"""Addon do mitmdump que isola o agente no job do dispatcher (SPEC-106, ADR 0016).

Faz três coisas, todas no proxy, fora do alcance do agente:
  1. libera só os hosts da lista de domínios e responde 403 ao resto;
  2. troca, no cabeçalho Authorization, o marcador que o agente recebeu pelo
     valor real do segredo, só nos hosts daquele segredo;
  3. responde 403 a todo push para o github.com que cria, atualiza ou apaga a
     main ou a master, ou cujo corpo não pode ser lido (SPEC-204, ADR 0020).

Uso:
  mitmdump -s egress-addon.py --set fabrica_domains=<arquivo> \
      --set fabrica_markers=<arquivo>
  python3 egress-addon.py check <domínios> <marcadores>   (valida e sai 0 ou 1)

Arquivo de domínios: um host por linha; `*.dominio` vale só para subdomínios;
linhas vazias e começadas com # são ignoradas.
Arquivo de marcadores (JSON): {"<marcador>": {"env": "<NOME>", "hosts": [...]}}.
O valor real vem da variável de ambiente <NOME> do próprio processo do proxy.
O log só lista hosts: nunca cabeçalhos nem valores.
"""
import base64
import json
import os
import re
import sys


class ConfigError(Exception):
    """Configuração inválida: o proxy não pode subir (falha fechada)."""


def load_domains(path):
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        raise ConfigError(f"não consegui ler a lista de domínios {path}: {error.strerror}")
    domains = []
    for line in lines:
        line = line.strip().lower()
        if line and not line.startswith("#"):
            domains.append(line)
    if not domains:
        raise ConfigError(f"a lista de domínios {path} está vazia.")
    for domain in domains:
        if domain == "*" or domain.startswith("*.") and "." not in domain[2:]:
            raise ConfigError(f"domínio largo demais na lista: {domain}.")
    return domains


def load_markers(path, environ=None):
    """Devolve {marcador: {"secret": <valor real>, "hosts": [...]}}."""
    environ = os.environ if environ is None else environ
    try:
        with open(path, encoding="utf-8") as handle:
            raw = json.load(handle)
    except OSError as error:
        raise ConfigError(f"não consegui ler o mapa de marcadores {path}: {error.strerror}")
    except ValueError:
        raise ConfigError(f"o mapa de marcadores {path} não é um JSON válido.")
    if not isinstance(raw, dict) or not raw:
        raise ConfigError(f"o mapa de marcadores {path} está vazio ou não é um objeto.")
    markers = {}
    for marker, entry in raw.items():
        if not isinstance(entry, dict) or not isinstance(entry.get("env"), str) \
                or not isinstance(entry.get("hosts"), list) or not entry["hosts"] \
                or not all(isinstance(host, str) for host in entry["hosts"]):
            raise ConfigError("o mapa de marcadores tem uma entrada inválida (esperado env e hosts).")
        if len(marker) < 16:
            raise ConfigError("o mapa de marcadores tem um marcador curto demais.")
        secret = environ.get(entry["env"], "")
        if not secret:
            raise ConfigError(f"a variável {entry['env']} não tem valor no ambiente do proxy.")
        markers[marker] = {"secret": secret, "hosts": [host.lower() for host in entry["hosts"]]}
    return markers


def host_allowed(host, domains):
    """Host exato ou, em `*.dominio`, subdomínio (sem o apex). Sem porta, sem ponto final."""
    host = (host or "").lower()
    head, sep, tail = host.rpartition(":")
    if sep and tail.isdigit():
        host = head
    if not host:
        return False
    for domain in domains:
        if domain.startswith("*."):
            if host.endswith(domain[1:]) and host != domain[2:]:
                return True
        elif host == domain:
            return True
    return False


def swap_authorization(value, host, markers):
    """Troca o marcador do cabeçalho Authorization (Bearer, token ou Basic) pelo valor real, só no host do segredo."""
    host = (host or "").lower()
    scheme, _, rest = value.partition(" ")
    rest = rest.strip()
    if scheme.lower() in ("bearer", "token"):  # o `gh` manda "token <valor>"
        entry = markers.get(rest)
        if entry and host in entry["hosts"]:
            return f"{scheme} {entry['secret']}"
    elif scheme.lower() == "basic":
        try:
            decoded = base64.b64decode(rest, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return value
        user, sep, password = decoded.partition(":")
        entry = markers.get(password) if sep else None
        if entry and host in entry["hosts"]:
            raw = f"{user}:{entry['secret']}".encode("utf-8")
            return f"{scheme} {base64.b64encode(raw).decode('ascii')}"
    return value


# Os mesmos refs que os githooks/ protegem.
PROTECTED_REFS = frozenset({"refs/heads/main", "refs/heads/master"})
# Comando da lista do push: <old-id> <new-id> <ref>, com ids SHA-1 ou SHA-256.
COMMAND_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})? [0-9a-f]{40}(?:[0-9a-f]{24})? (\S+)$")
HEX_DIGITS = frozenset(b"0123456789abcdefABCDEF")


def parse_receive_pack(body):
    """Lê a lista de comandos do corpo de um push (gitprotocol-pack, "update-requests").

    Devolve os refs dos comandos, na ordem, ou None se o corpo é ilegível.
    Lê pkt-lines do início até o primeiro 0000 ou a linha push-cert-end;
    linhas que não são comando (shallow, cabeçalho do certificado,
    push-option, assinatura) são ignoradas.
    """
    if not isinstance(body, (bytes, bytearray)) or not body:
        return None
    refs = []
    pos = 0
    while True:
        size_field = body[pos:pos + 4]
        if len(size_field) < 4 or not all(byte in HEX_DIGITS for byte in size_field):
            return None
        size = int(size_field, 16)
        if size == 0:
            return refs
        if size < 4 or pos + size > len(body):
            return None
        line = bytes(body[pos + 4:pos + size]).split(b"\0", 1)[0]
        pos += size
        if line.endswith(b"\n"):
            line = line[:-1]
        # latin-1 decodifica qualquer byte; um ref que não é ASCII nunca é protegido.
        text = line.decode("latin-1")
        if text == "push-cert-end":
            return refs
        match = COMMAND_RE.match(text)
        if match:
            refs.append(match.group(1))


def push_to_protected_ref(refs):
    """Verdadeiro se algum comando do push mexe na main ou na master."""
    return any(ref in PROTECTED_REFS for ref in refs)


def is_receive_pack(flow):
    """POST a github.com cujo caminho termina em /git-receive-pack (o push do git por HTTP)."""
    request = flow.request
    if str(getattr(request, "method", "")).upper() != "POST":
        return False
    host = (request.host or "").lower()
    head, sep, tail = host.rpartition(":")
    if sep and tail.isdigit():
        host = head
    if host != "github.com":
        return False
    path = str(getattr(request, "path", "")).split("?", 1)[0].split("#", 1)[0]
    return path.lower().rstrip("/").endswith("/git-receive-pack")


class Egress:
    def __init__(self):
        self.domains = []
        self.markers = {}

    def load(self, loader):
        loader.add_option("fabrica_domains", str, "", "Arquivo com os domínios liberados.")
        loader.add_option("fabrica_markers", str, "", "Arquivo JSON com os marcadores.")

    def running(self):
        from mitmproxy import ctx
        try:
            self.domains = load_domains(ctx.options.fabrica_domains)
            self.markers = load_markers(ctx.options.fabrica_markers)
        except ConfigError as error:
            print(f"egress-addon: {error}", file=sys.stderr)
            os._exit(1)

    def _block(self, flow):
        from mitmproxy import ctx, http
        host = flow.request.host
        ctx.log.info(f"bloqueado {host}")
        flow.response = http.Response.make(
            403,
            f"O dispatcher bloqueou o host {host}: ele não está na lista de domínios liberados.\n".encode("utf-8"),
            {"Content-Type": "text/plain; charset=utf-8"},
        )

    def _block_push(self, flow, reason, text):
        from mitmproxy import ctx, http
        ctx.log.info(f"bloqueado {flow.request.host}: {reason}")
        flow.response = http.Response.make(
            403,
            f"{text} A mudança deve ir por um PR.\n".encode("utf-8"),
            {"Content-Type": "text/plain; charset=utf-8"},
        )

    def _check_push(self, flow):
        """Decide o push antes da troca do marcador; devolve True se bloqueou."""
        try:
            body = flow.request.content
        except ValueError:  # Content-Encoding que não decodifica
            body = None
        refs = parse_receive_pack(body)
        if refs is None:
            self._block_push(flow, "corpo de push ilegível",
                             "O dispatcher recusou o push: o corpo do push é ilegível.")
            return True
        if push_to_protected_ref(refs):
            self._block_push(flow, "push para a main/master",
                             "O dispatcher não deixa o agente enviar para a main/master.")
            return True
        return False

    def requestheaders(self, flow):
        # O corpo do push precisa chegar inteiro ao request, mesmo com
        # stream_large_bodies ligado.
        if is_receive_pack(flow):
            flow.request.stream = False

    def http_connect(self, flow):
        if not host_allowed(flow.request.host, self.domains):
            self._block(flow)

    def request(self, flow):
        from mitmproxy import ctx
        host = flow.request.host
        if not host_allowed(host, self.domains):
            self._block(flow)
            return
        if is_receive_pack(flow) and self._check_push(flow):
            return
        value = flow.request.headers.get("Authorization")
        if value:
            flow.request.headers["Authorization"] = swap_authorization(value, host, self.markers)
        ctx.log.info(f"permitido {host}")


addons = [Egress()]


def main(argv):
    if len(argv) == 4 and argv[1] == "check":
        try:
            load_domains(argv[2])
            load_markers(argv[3])
        except ConfigError as error:
            print(f"egress-addon: {error}", file=sys.stderr)
            return 1
        return 0
    print("uso: egress-addon.py check <domínios> <marcadores>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
