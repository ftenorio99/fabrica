#!/usr/bin/env bash
# Liga o sandbox nativo do Claude Code num projeto (ADR 0005). Grava o bloco de
# base (templates/sandbox-project.json) no .claude/settings.json do projeto e o
# bloco do usuário (templates/sandbox-user.json), que o Claude Code só aceita
# nesse escopo, no settings.json do usuário. As listas são somadas, sem repetir,
# e as chaves que não são da fábrica ficam como estão.
# Uso: scripts/setup-sandbox.sh [--check] [--project <dir>]
#   --check  não grava nada; imprime "ok", "ausente" ou "incompleto <itens>".
#            Os itens incluem "remover:credentials:<path>" para os deny de
#            .env que a fábrica gravava antes da ADR 0006 e
#            "network.deniedDomains:<domínio>" para os hosts de
#            .fabrica/producao.txt que ainda não estão bloqueados.
# Saída: 0 sucesso; 1 JSON inválido ou opção desconhecida; 2 escrita negada no
# settings do usuário (a sessão já roda em sandbox).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates="$script_dir/../templates"
user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

fail() {
  echo "setup-sandbox: $*" >&2
  exit 1
}

check=false
project=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) check=true ;;
    --project)
      [[ $# -ge 2 ]] || fail "--project precisa de um diretório."
      project="$2"
      shift
      ;;
    *) fail "opção desconhecida: $1. Uso: setup-sandbox.sh [--check] [--project <dir>]" ;;
  esac
  shift
done

if [[ -z "$project" ]]; then
  project="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "não estou num repositório git. Use --project <dir>."
fi
[[ -d "$project" ]] || fail "o diretório $project não existe."
command -v python3 >/dev/null || fail "o python3 não está instalado."

mode=install
$check && mode=check

SETUP_SANDBOX_CMD="bash $script_dir/setup-sandbox.sh --project $project" python3 -I - "$mode" "$project/.claude/settings.json" "$user_settings" \
  "$templates/sandbox-project.json" "$templates/sandbox-user.json" "$project" <<'PY'
import fnmatch, json, os, re, shutil, subprocess, sys, tempfile

mode, project_path, user_path, project_tpl, user_tpl, project_root = sys.argv[1:7]
SCALARS = {"enabled", "allowUnsandboxedCommands", "allowLocalBinding"}
KEYED = {"files": "path", "envVars": "name"}
# Entradas que a fábrica gravava antes da ADR 0006: o agente passou a ler os
# .env de dev e de teste. Só saem quando idênticas às da fábrica.
RETIRED = [{"path": p, "mode": "deny"} for p in (".env", ".env.local", ".env.development", ".env.test")]
HOST = re.compile(r"^(\*\.)?[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$")
warnings = []


def production_hosts(root):
    """Hosts das linhas `host` de .fabrica/producao.txt; anota os avisos."""
    path = os.path.join(root, ".fabrica", "producao.txt")
    if not os.path.isfile(path):
        return []
    hosts = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            kind, _, value = line.partition(" ")
            value = value.strip()
            if kind == "host" and HOST.match(value):
                if value not in hosts:
                    hosts.append(value)
            elif kind == "texto" and value:
                if len(value) < 4:
                    warnings.append(f"padrão curto: {value}")
            else:
                warnings.append(f"linha inválida: {n}")
    return hosts


DEV_ENV = (".env", ".env.local", ".env.development", ".env.test")


def dev_env_denies(data):
    """Regras Read(...) de permissions.deny que negam um .env de dev (ADR 0006).

    Aproximação do casamento do Claude Code: tira os prefixos ./, **/ e //**/
    e testa o resto contra os nomes; padrões de outra pasta não contam (#113).
    """
    perms = data.get("permissions") if isinstance(data, dict) else None
    rules = perms.get("deny") if isinstance(perms, dict) else None
    if not isinstance(rules, list):
        return []
    found = []
    for rule in rules:
        if not (isinstance(rule, str) and rule.startswith("Read(") and rule.endswith(")")):
            continue
        pattern = rule[5:-1]
        for prefix in ("//**/", "**/", "./"):
            if pattern.startswith(prefix):
                pattern = pattern[len(prefix):]
                break
        if "/" in pattern:
            continue
        if any(fnmatch.fnmatchcase(name, pattern) for name in DEV_ENV):
            found.append(rule)
    return found


# Caminhos protegidos que o sandbox do Claude Code monta na raiz do projeto e
# em .claude/, ilegíveis para os comandos; conferidos numa sessão aninhada do
# Claude Code 2.1.322 (#116). Sem eles no .prettierignore, o `prettier --check .`
# falha.
MOUNTED = (".bash_profile", ".bashrc", ".gitconfig", ".gitmodules", ".idea", ".mcp.json",
           ".profile", ".ripgreprc", ".vscode", ".zprofile", ".zshrc",
           ".claude/agents", ".claude/commands", ".claude/hooks", ".claude/launch.json",
           ".claude/loop.md", ".claude/output-styles", ".claude/routines",
           ".claude/scheduled_tasks.json", ".claude/settings.local.json", ".claude/skills",
           ".claude/workflows")
PI_HEADER = "# Caminhos que o sandbox do Claude Code monta no projeto (fabrica#116)"


def prettierignore_missing(root):
    """Caminhos de MOUNTED que faltam no .prettierignore e não são versionados."""
    path = os.path.join(root, ".prettierignore")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as fh:
        present = {line.strip().strip("/") for line in fh}
    missing = []
    for name in MOUNTED:
        if name in present:
            continue
        try:
            tracked = subprocess.run(["git", "-C", root, "ls-files", "--", name],
                                     capture_output=True, text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            tracked = ""
        if not tracked:
            missing.append(name)
    return missing


def retire(data, missing):
    files = data.get("sandbox", {}).get("credentials", {}).get("files")
    if not isinstance(files, list):
        return
    for entry in RETIRED:
        while entry in files:
            files.remove(entry)
            missing.append(f"remover:credentials:{entry['path']}")


def load(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, UnicodeDecodeError):
        print(f"setup-sandbox: JSON inválido em {path}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, dict):
        print(f"setup-sandbox: JSON inválido em {path}", file=sys.stderr)
        sys.exit(1)
    return data


def merge(dst, src, path, missing):
    """Soma src em dst. Anota em missing o que faltava ou divergia."""
    for key, value in src.items():
        here = f"{path}.{key}" if path else key
        if isinstance(value, dict):
            if not isinstance(dst.get(key), dict):
                dst[key] = {}
                if not value:  # objeto vazio da fábrica, como tlsTerminate: {}
                    missing.append(here)
            merge(dst[key], value, here, missing)
        elif isinstance(value, list):
            current = dst.get(key)
            if not isinstance(current, list):
                current = []
                dst[key] = current
            ident = KEYED.get(key)
            for item in value:
                if ident and isinstance(item, dict):
                    same = [c for c in current if isinstance(c, dict) and c.get(ident) == item[ident]]
                    if not same:
                        current.append(item)
                        missing.append(f"{here}:{item[ident]}")
                    elif item not in same:
                        missing.append(f"credentials:{item[ident]}")
                elif item not in current:
                    current.append(item)
                    missing.append(f"{here}:{item}")
        else:
            if dst.get(key) != value:
                if key in SCALARS and key in dst:
                    missing.append(f"{key}={json.dumps(dst[key])}")
                else:
                    missing.append(here)
                dst[key] = value


def plan(path, tpl, hosts=None):
    data = load(path)
    exists = data is not None
    data = data or {}
    with open(tpl) as fh:
        template = json.load(fh)
    before = json.dumps(data, sort_keys=True)
    missing = []
    if hosts is not None:
        retire(data, missing)
        if hosts:
            template["sandbox"]["network"]["deniedDomains"] = hosts
    merge(data, template, "", missing)
    changed = json.dumps(data, sort_keys=True) != before
    return data, exists, missing, changed


# Lê e valida os dois antes de gravar qualquer um.
project_data, project_exists, project_missing, project_changed = plan(
    project_path, project_tpl, production_hosts(project_root))
for w in warnings:
    print(f"setup-sandbox: .fabrica/producao.txt: {w}", file=sys.stderr)
for rule in dev_env_denies(project_data):
    print(f"setup-sandbox: permissions.deny nega {rule}; o agente não vai ler os .env de dev no sandbox (ADR 0006)", file=sys.stderr)
user_data, user_exists, user_missing, user_changed = plan(user_path, user_tpl)

pi_missing = prettierignore_missing(project_root)
project_missing += [f"prettierignore:/{name}" for name in pi_missing]

if mode == "check":
    original = load(project_path) or {}
    items = []
    for i in project_missing + user_missing:
        if i not in items:
            items.append(i)
    if not items:
        print("ok")
    elif not isinstance(original.get("sandbox"), dict):
        print("ausente")
    else:
        print("incompleto " + " ".join(items))
    sys.exit(0)


def write(path, data, backup):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if backup and os.path.exists(path):
        shutil.copy2(path, path + ".bak-fabrica-sandbox")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings.")
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


if user_changed:
    try:
        write(user_path, user_data, backup=True)
    except OSError:
        print(
            f"setup-sandbox: não consegui gravar {user_path}; a sessão já roda em sandbox. "
            f"Rode no prompt, fora do sandbox: ! {os.environ.get('SETUP_SANDBOX_CMD', '')}",
            file=sys.stderr,
        )
        sys.exit(2)
if project_changed:
    try:
        write(project_path, project_data, backup=False)
    except OSError as err:
        print(f"setup-sandbox: não consegui gravar {project_path}: {err.strerror}", file=sys.stderr)
        sys.exit(1)
    # O json.dump abre toda lista em várias linhas; o Prettier do projeto, se
    # houver, deixa o arquivo no padrão que o lint dele confere (#112).
    prettier = os.path.join(project_root, "node_modules", ".bin", "prettier")
    if os.path.isfile(prettier) and os.access(prettier, os.X_OK):
        rel = os.path.relpath(project_path, project_root)
        try:
            ok = subprocess.run([prettier, "--write", rel], cwd=project_root,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                timeout=60).returncode == 0
        except (OSError, subprocess.SubprocessError):
            ok = False
        if not ok:
            print(f"setup-sandbox: não consegui formatar {rel}; rode o prettier do projeto nele.", file=sys.stderr)

if pi_missing:
    pi_path = os.path.join(project_root, ".prettierignore")
    try:
        with open(pi_path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        add = "" if text.endswith("\n") or not text else "\n"
        if PI_HEADER not in text:
            add += ("\n" if text else "") + PI_HEADER + "\n"
        add += "".join(f"/{name}\n" for name in pi_missing)
        with open(pi_path, "a", encoding="utf-8") as fh:
            fh.write(add)
    except OSError as err:
        print(f"setup-sandbox: não consegui gravar {pi_path}: {err.strerror}", file=sys.stderr)
        sys.exit(1)

print("instalado" if (user_changed or project_changed or pi_missing) else "ok")
PY
