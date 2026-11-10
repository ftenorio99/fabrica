#!/usr/bin/env bash
# Teste de aceite do sandbox (ADR 0005). Rode pelo Bash do agente, numa sessão
# do Claude Code aberta num projeto com o sandbox instalado (/fabrica:setup).
# Fora do sandbox, as verificações de bloqueio falham, como devem. Não é um
# teste de unidade: ele faz git push de uma branch test/sandbox-*, apagada no fim.
# Imprime "ok <verificação>" ou "falha <verificação>: <motivo>", uma por linha,
# e sai com 1 se alguma falhar.
# Uso: scripts/test-sandbox-acceptance.sh [--remote <nome>]
set -uo pipefail

remote=origin
while [[ $# -gt 0 ]]; do
  case $1 in
    --remote)
      remote="${2:?--remote precisa de um nome}"
      shift
      ;;
    *)
      echo "test-sandbox-acceptance: opção desconhecida: $1" >&2
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

# Aceite 1: escrita fora do projeto falha; dentro dele funciona.
probe="$HOME/fabrica-sandbox-probe-$$"
if touch "$probe" 2>/dev/null; then
  rm -f "$probe"
  bad "escrita-fora-do-projeto" "criei $probe"
else
  ok "escrita-fora-do-projeto"
fi
# Apagar também depende de escrever no diretório: se criar em ~ falha por
# sistema de arquivos só de leitura, apagar ali falha pelo mesmo motivo. Por
# isso o teste não apaga nenhum arquivo real fora do projeto.
if mkdir "$probe.d" 2>/dev/null; then
  rmdir "$probe.d"
  bad "diretorio-fora-do-projeto" "criei $probe.d"
else
  ok "diretorio-fora-do-projeto"
fi
# Abre o settings em modo de acréscimo, sem escrever nada, só se ele existe.
if [[ ! -f "$root/.claude/settings.json" ]]; then
  bad "settings-do-projeto-protegido" "o projeto não tem .claude/settings.json; rode /fabrica:setup"
elif : >>"$root/.claude/settings.json" 2>/dev/null; then
  bad "settings-do-projeto-protegido" "consegui abrir .claude/settings.json para escrita"
else
  ok "settings-do-projeto-protegido"
fi
inside="$root/.fabrica-sandbox-probe-$$"
if touch "$inside" 2>/dev/null && rm "$inside" 2>/dev/null; then
  ok "escrita-dentro-do-projeto"
else
  bad "escrita-dentro-do-projeto" "não consegui criar e apagar $inside"
fi

# Aceite 2: rede só para os domínios liberados.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://example.com 2>/dev/null)"
if [[ "$code" =~ ^[23] ]]; then
  bad "dominio-fora-da-lista" "example.com respondeu $code"
else
  ok "dominio-fora-da-lista"
fi
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://api.github.com 2>/dev/null)"
if [[ "$code" =~ ^[23] ]]; then
  ok "dominio-liberado"
else
  bad "dominio-liberado" "api.github.com respondeu '${code:-nada}'"
fi

# Aceite 3: nenhum segredo em claro.
hosts="${XDG_CONFIG_HOME:-$HOME/.config}/gh/hosts.yml"
if grep -Eq 'gh[opsu]_[A-Za-z0-9]{30,}|github_pat_' "$hosts" 2>/dev/null; then
  bad "token-no-hosts-yml" "o $hosts tem um token do GitHub em claro"
else
  ok "token-no-hosts-yml"
fi
if [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]]; then
  bad "token-no-ambiente" "GH_TOKEN ou GITHUB_TOKEN não está vazia"
else
  ok "token-no-ambiente"
fi
token="$(gh auth token 2>/dev/null)"
if [[ "$token" =~ gh[opsu]_[A-Za-z0-9]{30,}|github_pat_ ]]; then
  bad "gh-auth-token" "gh auth token devolveu um token em claro (token no chaveiro do sistema?)"
else
  ok "gh-auth-token"
fi
if ls "$HOME/.ssh" >/dev/null 2>&1 && [[ -d "$HOME/.ssh" ]]; then
  bad "ssh-ilegivel" "consegui listar ~/.ssh"
else
  ok "ssh-ilegivel"
fi
if [[ -f "$root/.env" ]]; then
  if cat "$root/.env" >/dev/null 2>&1; then
    bad "env-ilegivel" "consegui ler .env"
  else
    ok "env-ilegivel"
  fi
else
  bad "env-ilegivel" "crie um .env de teste no projeto antes de rodar"
fi

# O fluxo continua funcionando.
if login="$(gh api user -q .login 2>&1)"; then
  ok "gh-api-user ($login)"
else
  hint=""
  grep -q oauth_token "$hosts" 2>/dev/null || hint=" O token não está no hosts.yml: veja docs/guias/isolamento-do-agente.md."
  bad "gh-api-user" "$(head -1 <<<"$login").$hint"
fi
branch="test/sandbox-$(date -u +%Y%m%d%H%M%S)"
push_err="$(mktemp)"
if git push -q "$remote" "HEAD:refs/heads/$branch" 2>"$push_err"; then
  ok "git-push"
  git push -q "$remote" --delete "$branch" 2>/dev/null || bad "git-push-limpeza" "apague a branch $branch em $remote"
else
  bad "git-push" "$(head -1 "$push_err")"
fi
rm -f "$push_err"
if version="$(npm view npm version 2>/dev/null)" && [[ -n "$version" ]]; then
  ok "npm-view ($version)"
else
  bad "npm-view" "npm view npm version falhou"
fi

[[ $failures -eq 0 ]]
