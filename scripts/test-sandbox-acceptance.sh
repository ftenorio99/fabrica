#!/usr/bin/env bash
# Teste de aceite do sandbox (ADR 0005). Rode pelo Bash do agente, numa sessão
# do Claude Code aberta num projeto com o sandbox instalado (/fabrica:setup).
# Fora do sandbox, as verificações de bloqueio falham, como devem. Não é um
# teste de unidade: ele lê os segredos da máquina para conferir que não os vê e
# faz git push de uma branch test/sandbox-*, apagada no fim.
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
elif { : >>"$root/.claude/settings.json"; } 2>/dev/null; then
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
# No sandbox, o ~/.ssh negado aparece vazio; fora dele, as chaves são legíveis.
readable="$(find "$HOME/.ssh" -maxdepth 1 -type f -readable -print -quit 2>/dev/null)"
if [[ -n "$readable" ]] && head -c 1 "$readable" >/dev/null 2>&1; then
  bad "ssh-ilegivel" "consegui ler $readable"
else
  ok "ssh-ilegivel"
fi
# No sandbox, o .env de produção negado vira um dispositivo ilegível, e não
# um arquivo comum. Os .env de dev e de teste continuam legíveis (ADR 0006).
if [[ -e "$root/.env.production" ]]; then
  if cat "$root/.env.production" >/dev/null 2>&1; then
    bad "env-producao-ilegivel" "consegui ler .env.production"
  else
    ok "env-producao-ilegivel"
  fi
else
  bad "env-producao-ilegivel" "crie um .env.production de teste no projeto antes de rodar"
fi
if [[ -e "$root/.env" ]]; then
  if cat "$root/.env" >/dev/null 2>&1; then
    ok "env-dev-legivel"
  else
    bad "env-dev-legivel" "não consegui ler .env; os .env de dev deveriam ser legíveis"
  fi
else
  bad "env-dev-legivel" "crie um .env de teste no projeto antes de rodar"
fi

# Reflexão: o marcador mandado no corpo de uma requisição a um host liberado
# não pode voltar trocado pelo valor real. O /markdown do GitHub devolve o texto.
reflect() { # reflect <verificação> <arquivo> <regex do valor> <regex do real>
  local marker
  marker="$(grep -oE "$3" "$2" 2>/dev/null | head -1 | awk '{print $NF}')"
  if [[ -z "$marker" ]]; then
    bad "$1" "não encontrei o marcador em $2"
    return
  fi
  # Fora do sandbox, o "marcador" é o valor real: não o mande para lugar nenhum.
  if grep -Eq "$4" <<<"$marker"; then
    bad "$1" "o valor em $2 está em claro; rode dentro do sandbox"
    return
  fi
  local out
  out="$(gh api -X POST /markdown -f text="x${marker}x" 2>&1)"
  if grep -Eq "$4" <<<"$out"; then
    # Risco aceito (ADR 0005): o proxy troca o marcador em toda a requisição.
    # O que limita o estrago é o token fine-grained, conferido abaixo.
    printf 'aviso %s: %s\n' "$1" "o proxy troca o marcador também no corpo; o token vaza pelo próprio GitHub (risco aceito, ADR 0005)"
  elif grep -Fq "$marker" <<<"$out"; then
    ok "$1"
  else
    bad "$1" "resposta inesperada: $(head -c 120 <<<"$out")"
  fi
}
reflect "reflexao-token-gh" "$hosts" 'oauth_token:[[:space:]]*[^[:space:]]+' 'gh[opsu]_[A-Za-z0-9]{30,}|github_pat_'
reflect "reflexao-git-auth" "$HOME/.config/fabrica/git-auth.gitconfig" 'Basic [^[:space:]]+' 'eC1hY2Nlc3MtdG9rZW46'

# O token do gh é fine-grained: o GitHub devolve a expiração dele num cabeçalho.
if gh api -i /user 2>/dev/null | grep -qi '^github-authentication-token-expiration:'; then
  ok "token-com-expiracao"
else
  bad "token-com-expiracao" "o token do gh não tem expiração; use um token fine-grained (docs/guias/isolamento-do-agente.md)"
fi

# O fluxo continua funcionando.
if login="$(gh api user -q .login 2>&1)"; then
  ok "gh-api-user ($login)"
else
  hint=""
  grep -q oauth_token "$hosts" 2>/dev/null || hint=" O token não está no hosts.yml: veja docs/guias/isolamento-do-agente.md."
  bad "gh-api-user" "$(head -1 <<<"$login").$hint"
fi
if version="$(npm view npm version 2>/dev/null)" && [[ -n "$version" ]]; then
  ok "npm-view ($version)"
else
  bad "npm-view" "npm view npm version falhou"
fi

# O git push autentica pelo cabeçalho mascarado de ~/.config/fabrica/git-auth.gitconfig.
auth_file="$HOME/.config/fabrica/git-auth.gitconfig"
if grep -Eq 'Basic eC1hY2Nlc3MtdG9rZW46' "$auth_file" 2>/dev/null; then
  bad "token-no-git-auth" "o $auth_file tem o cabeçalho do token em claro"
else
  ok "token-no-git-auth"
fi
branch="test/sandbox-$(date -u +%Y%m%d%H%M%S)"
push_err="$(mktemp)"
if git push -q "$remote" "HEAD:refs/heads/$branch" 2>"$push_err"; then
  ok "git-push"
  git push -q "$remote" --delete "$branch" 2>/dev/null || bad "git-push-limpeza" "apague a branch $branch em $remote"
else
  hint=""
  [[ -e "$auth_file" ]] || hint=" Falta o $auth_file: rode scripts/setup-git-auth.sh fora do sandbox."
  bad "git-push" "$(head -1 "$push_err").$hint"
fi
rm -f "$push_err"

[[ $failures -eq 0 ]]
