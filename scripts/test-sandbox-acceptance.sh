#!/usr/bin/env bash
# Teste de aceite do isolamento no modo sbx (ADR 0010). Rode pelo Bash do
# agente, dentro da VM do sbx de um projeto preparado pelo checklist do
# /fabrica:setup. Fora da VM, token-marcador e home-isolado falham, como devem.
# Não é um teste de unidade: ele usa a rede e faz git push de uma branch
# test/sandbox-*, apagada no fim. O push de teste na main usa --dry-run e nunca
# chega ao remoto.
# Imprime "ok <verificação>" ou "falha <verificação>: <motivo>", uma por linha,
# e sai com 1 se alguma falhar.
# Uso: scripts/test-sandbox-acceptance.sh [--remote <nome>]
set -uo pipefail

remote=origin
while [[ $# -gt 0 ]]; do
  case $1 in
    --remote)
      if [[ $# -lt 2 ]]; then
        echo "test-sandbox-acceptance: --remote precisa de um nome." >&2
        exit 1
      fi
      remote="$2"
      shift
      ;;
    *)
      echo "test-sandbox-acceptance: opção desconhecida: $1. Uso: test-sandbox-acceptance.sh [--remote <nome>]" >&2
      exit 1
      ;;
  esac
  shift
done

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "test-sandbox-acceptance: rode dentro de um repositório git." >&2
  exit 1
}
cd "$root" || exit 1

failures=0
ok() { printf 'ok %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf 'falha %s: %s\n' "$1" "$2"
}

real_token='gh[opsu]_[A-Za-z0-9]{30,}|github_pat_'

# O token do GitHub fica no host: na VM, o GH_TOKEN é um marcador, e o proxy
# põe o token real nas requisições.
if [[ -z "${GH_TOKEN:-}" ]]; then
  bad "token-marcador" "GH_TOKEN está vazia; no host, rode sbx secret set github"
elif [[ "$GH_TOKEN" =~ $real_token ]]; then
  bad "token-marcador" "GH_TOKEN tem o formato de um token real do GitHub"
else
  ok "token-marcador"
fi

# O home é o da VM: sem as chaves SSH e sem o login do gh da máquina.
# Arquivos públicos (known_hosts, config, authorized_keys, chaves .pub) não
# expõem segredo e podem vir na imagem da VM.
readable="$(find "$HOME/.ssh" -maxdepth 1 -type f -readable \
  ! -name 'known_hosts*' ! -name config ! -name 'authorized_keys*' ! -name '*.pub' \
  -print -quit 2>/dev/null)"
if [[ -n "$readable" ]]; then
  bad "home-isolado" "consegui ler $readable"
elif grep -q 'oauth_token' "$HOME/.config/gh/hosts.yml" 2>/dev/null; then
  bad "home-isolado" "o ~/.config/gh/hosts.yml tem um oauth_token"
else
  ok "home-isolado"
fi

# O fluxo funciona com o marcador.
if login="$(gh api user -q .login 2>&1)" && [[ -n "$login" ]]; then
  ok "gh-api-user"
else
  bad "gh-api-user" "$(head -1 <<<"$login")"
fi

# Rede só para os hosts da política da VM. O teste olha o corpo da resposta, e
# não o código HTTP: o proxy do sbx responde 200 ao CONNECT de um host bloqueado.
if body="$(curl -s --max-time 10 https://api.github.com/zen 2>/dev/null)" && [[ -n "$body" ]]; then
  ok "dominio-liberado"
else
  bad "dominio-liberado" "api.github.com não respondeu"
fi
body="$(curl -s --max-time 10 https://example.com 2>/dev/null)"
if grep -q 'Example Domain' <<<"$body"; then
  bad "dominio-fora-da-lista" "example.com respondeu com a página dele"
else
  ok "dominio-fora-da-lista"
fi

# Os hooks do git vivem na VM e somem com sbx rm.
hooks_path="$(git config --global --type=path core.hooksPath 2>/dev/null)"
if [[ -n "$hooks_path" && -x "$hooks_path/pre-push" ]]; then
  ok "hooks-do-git"
else
  bad "hooks-do-git" "o core.hooksPath global não aponta para uma pasta com pre-push executável; rode /fabrica:setup"
fi

# Push na main: um commit solto sobre o HEAD dá ao push o que mandar mesmo com
# o HEAD igual à main, e o --dry-run não deixa nada chegar ao remoto.
# O pai do commit solto é a ponta da main do remoto, para o push ser
# fast-forward: com o HEAD atrás da main, o git recusaria o push como
# non-fast-forward antes de chamar o hook. Sem main no remoto, vale o HEAD.
push_err="$(mktemp)"
first_error() { grep -m1 -E 'rejected|error|fatal' "$push_err" || head -1 "$push_err"; }
parent=HEAD
if git fetch -q "$remote" main 2>/dev/null; then
  parent="$(git rev-parse FETCH_HEAD)"
fi
sha="$(git -c user.name=fabrica -c user.email=fabrica@localhost commit-tree 'HEAD^{tree}' -p "$parent" -m 'teste de aceite do isolamento' 2>"$push_err")"
if [[ -z "$sha" ]]; then
  bad "push-na-main-recusado" "não consegui criar o commit de teste: $(first_error)"
elif git push --dry-run "$remote" "$sha:refs/heads/main" >/dev/null 2>"$push_err"; then
  bad "push-na-main-recusado" "os hooks do git não estão instalados nesta VM; rode /fabrica:setup"
elif grep -q 'Push para a main bloqueado' "$push_err"; then
  ok "push-na-main-recusado"
else
  bad "push-na-main-recusado" "o push falhou por outro motivo: $(first_error)"
fi

# O push de uma branch funciona, com o token posto pelo proxy.
branch="test/sandbox-$(date -u +%Y%m%d%H%M%S)"
if git push -q "$remote" "HEAD:refs/heads/$branch" 2>"$push_err"; then
  ok "git-push"
  git push -q "$remote" --delete "$branch" 2>/dev/null || bad "git-push-limpeza" "apague a branch $branch em $remote"
else
  bad "git-push" "$(first_error)"
fi
rm -f "$push_err"

if [[ $failures -eq 0 ]]; then
  # Só o log do proxy, no host, mostra o que foi bloqueado.
  echo "confira no host: sbx policy log $(basename "$root")"
fi
[[ $failures -eq 0 ]]
