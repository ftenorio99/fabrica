#!/usr/bin/env bash
# Remove os restos do sandbox nativo do Claude Code, que saiu da fábrica
# (ADR 0010): o bloco "sandbox" do .claude/settings.json do projeto e, na
# máquina, o tlsTerminate e as entradas de mask do settings.json do usuário, a
# inclusão do git-auth.gitconfig na configuração global do git e o próprio
# ~/.config/fabrica/git-auth.gitconfig, que guarda uma credencial.
# Uso: scripts/migrate-native-sandbox.sh [--check] [--apply projeto|maquina] [--project <dir>]
#   --check  (padrão) não grava nada; imprime "ok" ou "pendente <itens>".
#   --apply projeto  remove a chave "sandbox" do settings do projeto, sem backup:
#            o arquivo é versionado.
#   --apply maquina  remove os itens da máquina. Antes, copia o settings.json do
#            usuário e o arquivo de configuração do git para
#            <arquivo>.bak-fabrica-sandbox. O git-auth.gitconfig é apagado sem
#            cópia, e o conteúdo dele nunca é impresso.
# Sem --project, o projeto é a raiz do repositório git do diretório atual; fora
# de um repositório, só a máquina é tratada.
# Saída: uma linha em stdout ("ok", "pendente <itens>" ou "removido <itens>");
# avisos e erros em stderr. Código 0 em sucesso; 1 em uso inválido, JSON
# inválido ou falha de escrita.
set -euo pipefail

usage="Uso: migrate-native-sandbox.sh [--check] [--apply projeto|maquina] [--project <dir>]"

fail() {
  echo "migrate-native-sandbox: $*" >&2
  exit 1
}

check=false
target=""
project=""
project_given=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) check=true ;;
    --apply)
      [[ $# -ge 2 ]] || fail "--apply precisa de um alvo: projeto ou maquina. $usage"
      target="$2"
      [[ "$target" == "projeto" || "$target" == "maquina" ]] ||
        fail "alvo inválido: $target. Os alvos aceitos são projeto e maquina. $usage"
      shift
      ;;
    --project)
      [[ $# -ge 2 ]] || fail "--project precisa de um diretório. $usage"
      project="$2"
      project_given=true
      shift
      ;;
    *) fail "opção desconhecida: $1. $usage" ;;
  esac
  shift
done

if $check && [[ -n "$target" ]]; then
  fail "--check e --apply não vão juntos. $usage"
fi

if $project_given; then
  [[ -d "$project" ]] || fail "o diretório $project não existe."
else
  project="$(git rev-parse --show-toplevel 2>/dev/null)" || project=""
fi
if [[ "$target" == "projeto" && -z "$project" ]]; then
  fail "não estou num repositório git. Use --project <dir>."
fi

user_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
git_auth="$HOME/.config/fabrica/git-auth.gitconfig"

python3 -I - "${target:-check}" "$project" "$user_settings" "$git_auth" <<'PY'
import json
import os
import shutil
import subprocess
import sys

mode, project_root, user_path, git_auth = sys.argv[1:5]
project_path = os.path.join(project_root, ".claude", "settings.json") if project_root else ""

PREFIX = "migrate-native-sandbox:"
BACKUP = ".bak-fabrica-sandbox"
INCLUDE = "~/.config/fabrica/git-auth.gitconfig"
# As duas entradas de mask que o setup antigo gravava no settings do usuário.
MASKS = [
    {"path": "~/.config/gh/hosts.yml", "mode": "mask", "extract": "oauth_token:\\s*(\\S+)",
     "maskDuplicates": True, "onExtractNoMatch": "deny",
     "injectHosts": ["api.github.com", "github.com"]},
    {"path": "~/.config/fabrica/git-auth.gitconfig", "mode": "mask", "extract": "Basic\\s+(\\S+)",
     "maskDuplicates": True, "onExtractNoMatch": "deny", "injectHosts": ["github.com"]},
]

removed = []


def die(message):
    print(f"{PREFIX} {message}", file=sys.stderr)
    if removed:
        print(f"{PREFIX} já removido: {' '.join(removed)}", file=sys.stderr)
    sys.exit(1)


def write_error(path, err):
    reason = err.strerror if isinstance(err, OSError) and err.strerror else str(err)
    die(f"não consegui gravar {path}: {reason}")


def load(path):
    """O objeto do arquivo, ou None se ele não existe."""
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (ValueError, OSError):
        die(f"JSON inválido em {path}")
    if not isinstance(data, dict):
        die(f"JSON inválido em {path}")
    return data


def dump(path, data):
    try:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    except OSError as err:
        write_error(path, err)


def canonical(value):
    """Texto que compara dois valores JSON sem depender da ordem das chaves."""
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


MASK_KEYS = [canonical(m) for m in MASKS]


def sub(data, *keys):
    """O dicionário em data[k1][k2]..., ou None se o caminho não é de dicionários."""
    for key in keys:
        if not isinstance(data, dict) or not isinstance(data.get(key), dict):
            return None
        data = data[key]
    return data


def has_tls(user):
    network = sub(user, "sandbox", "network")
    return network is not None and "tlsTerminate" in network and canonical(network["tlsTerminate"]) == "{}"


def mask_files(user):
    credentials = sub(user, "sandbox", "credentials")
    files = credentials.get("files") if credentials is not None else None
    return files if isinstance(files, list) else None


def has_mask(user, index):
    files = mask_files(user)
    return files is not None and any(canonical(entry) == MASK_KEYS[index] for entry in files)


def git_include_files():
    """Arquivos da configuração global do git que trazem a inclusão da fábrica."""
    try:
        result = subprocess.run(
            ["git", "config", "--global", "--show-origin", "-z", "--get-all", "include.path"],
            stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    tokens = result.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    files = []
    for origin, value in zip(tokens[0::2], tokens[1::2]):
        if value == INCLUDE and origin.startswith("file:") and origin[5:] not in files:
            files.append(origin[5:])
    return files


def machine_items(user):
    items = []
    if user is not None:
        if has_tls(user):
            items.append("maquina:tlsTerminate")
        for index, mask in enumerate(MASKS):
            if has_mask(user, index):
                items.append(f"maquina:mask:{mask['path']}")
    if git_include_files():
        items.append("maquina:gitconfig-include")
    if os.path.lexists(git_auth):
        items.append("maquina:git-auth")
    return items


def backup(path):
    try:
        shutil.copy2(path, path + BACKUP)
    except OSError as err:
        write_error(path + BACKUP, err)


def apply_project():
    data = load(project_path)
    if data is None or "sandbox" not in data:
        print("ok")
        return
    del data["sandbox"]
    dump(project_path, data)
    # O json.dump abre toda lista em várias linhas; o Prettier do projeto, se
    # houver, deixa o arquivo no padrão que o lint dele confere (#112).
    prettier = os.path.join(project_root, "node_modules", ".bin", "prettier")
    if os.path.isfile(prettier) and os.access(prettier, os.X_OK):
        rel = os.path.relpath(project_path, project_root)
        try:
            formatted = subprocess.run(
                [prettier, "--write", rel], cwd=project_root, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60).returncode == 0
        except (OSError, subprocess.SubprocessError):
            formatted = False
        if not formatted:
            print(f"{PREFIX} não consegui formatar {rel}; rode o prettier do projeto nele.",
                  file=sys.stderr)
    print("removido projeto:sandbox")


def apply_user_settings(user):
    """Remove do settings do usuário os itens da fábrica e os contêineres que esvaziaram."""
    found = []
    if has_tls(user):
        found.append("maquina:tlsTerminate")
    for index, mask in enumerate(MASKS):
        if has_mask(user, index):
            found.append(f"maquina:mask:{mask['path']}")
    if not found:
        return
    backup(user_path)
    sandbox = user["sandbox"]
    if "maquina:tlsTerminate" in found:
        del sandbox["network"]["tlsTerminate"]
        if not sandbox["network"]:
            del sandbox["network"]
    if any(item.startswith("maquina:mask:") for item in found):
        credentials = sandbox["credentials"]
        credentials["files"] = [e for e in credentials["files"] if canonical(e) not in MASK_KEYS]
        if not credentials["files"]:
            del credentials["files"]
            if not credentials:
                del sandbox["credentials"]
    if not sandbox:
        del user["sandbox"]
    dump(user_path, user)
    removed.extend(found)


def apply_git_include():
    files = git_include_files()
    for path in files:
        backup(path)
        try:
            result = subprocess.run(
                ["git", "config", "--file", path, "--fixed-value", "--unset-all", "include.path", INCLUDE],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as err:
            write_error(path, err)
        if result.returncode != 0:
            die(f"não consegui gravar {path}: {result.stderr.strip() or 'o git config falhou'}")
    if files:
        removed.append("maquina:gitconfig-include")


def apply_git_auth():
    if not os.path.lexists(git_auth):
        return
    try:
        os.remove(git_auth)
    except OSError as err:
        write_error(git_auth, err)
    removed.append("maquina:git-auth")


def apply_machine():
    user = load(user_path)
    if user is not None:
        apply_user_settings(user)
    apply_git_include()
    apply_git_auth()
    print(f"removido {' '.join(removed)}" if removed else "ok")


if mode == "projeto":
    apply_project()
elif mode == "maquina":
    apply_machine()
else:
    project = load(project_path)
    items = ["projeto:sandbox"] if project is not None and "sandbox" in project else []
    items += machine_items(load(user_path))
    print(f"pendente {' '.join(items)}" if items else "ok")
PY
