#!/usr/bin/env bash
# Prepara o git push por HTTPS dentro do sandbox (ADR 0005). Grava em
# ~/.config/fabrica/git-auth.gitconfig o cabeçalho Authorization: Basic do token
# do gh, já codificado, e inclui esse arquivo no ~/.gitconfig. No sandbox, o
# valor aparece mascarado e o proxy põe o real só nas requisições a github.com.
# Rode você mesmo, fora do sandbox (no prompt do Claude Code, com "!"), na
# primeira vez e sempre que o token do gh mudar.
# Uso: scripts/setup-git-auth.sh [--check]
#   --check  não grava nada; imprime "ok", "ausente" ou "sem-include".
set -euo pipefail

# Caminho fixo, sem XDG_CONFIG_HOME: é o caminho que o mask de
# templates/sandbox-user.json cobre. Em outro lugar, o agente leria o valor real.
dest_dir="$HOME/.config/fabrica"
dest="$dest_dir/git-auth.gitconfig"
include="~/.config/fabrica/git-auth.gitconfig"

fail() {
  echo "setup-git-auth: $*" >&2
  exit 1
}

check=false
for arg in "$@"; do
  case $arg in
    --check) check=true ;;
    *) fail "opção desconhecida: $arg. Uso: setup-git-auth.sh [--check]" ;;
  esac
done

has_include() {
  git config --global --get-all include.path 2>/dev/null | grep -Fxq -e "$include" -e "$dest"
}

if $check; then
  if ! grep -q '^[[:space:]]*extraheader = Authorization: Basic ' "$dest" 2>/dev/null; then
    echo ausente
  elif ! has_include; then
    echo sem-include
  else
    echo ok
  fi
  exit 0
fi

command -v gh >/dev/null || fail "o gh não está instalado."
token="$(gh auth token 2>/dev/null)" || fail "o gh não devolveu um token. Rode gh auth login."
[[ -n "$token" ]] || fail "o gh não devolveu um token. Rode gh auth login."
# O token tem de ser o do hosts.yml, o mesmo que o sandbox mascara. Se o gh
# lê outro (do chaveiro do sistema, que tem preferência), o cabeçalho do git
# levaria esse outro token, em geral o antigo e amplo.
hosts="$HOME/.config/gh/hosts.yml"
file_token="$(sed -n 's/^[[:space:]]*oauth_token:[[:space:]]*//p' "$hosts" 2>/dev/null | head -1)"
if [[ "$file_token" != "$token" ]]; then
  unset token file_token
  fail "o gh usa um token que não é o do $hosts (em geral, o do chaveiro do sistema). Rode gh auth logout e gh auth login --with-token --insecure-storage com o token fine-grained, e depois este script de novo. Nada foi gravado."
fi
unset file_token
basic="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
unset token

mkdir -p "$dest_dir"
tmp="$(umask 077 && mktemp "$dest.XXXXXX")"
printf '[http "https://github.com/"]\n\textraheader = Authorization: Basic %s\n' "$basic" >"$tmp"
chmod 600 "$tmp"
mv "$tmp" "$dest"
unset basic

has_include || git config --global --add include.path "$include"
echo "gravado $dest"
