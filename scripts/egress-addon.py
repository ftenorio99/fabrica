#!/usr/bin/env python3
"""Addon do mitmdump que isola o agente no job do dispatcher (SPEC-106, ADR 0016).

Faz duas coisas, as duas no proxy, fora do alcance do agente:
  1. libera só os hosts da lista de domínios e responde 403 ao resto;
  2. troca, no cabeçalho Authorization, o marcador que o agente recebeu pelo
     valor real do segredo, só nos hosts daquele segredo.

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

    def http_connect(self, flow):
        if not host_allowed(flow.request.host, self.domains):
            self._block(flow)

    def request(self, flow):
        from mitmproxy import ctx
        host = flow.request.host
        if not host_allowed(host, self.domains):
            self._block(flow)
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
