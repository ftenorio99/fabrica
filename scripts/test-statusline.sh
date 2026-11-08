#!/usr/bin/env bash
# Testes da statusline (scripts/statusline.sh) e da instalação
# (scripts/setup-statusline.sh), com um gh falso no PATH e um HOME temporário.
# Não usa o gh da máquina, a rede nem o settings.json real.
# Uso: scripts/test-statusline.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
statusline="$script_dir/statusline.sh"
setup="$script_dir/setup-statusline.sh"
version="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$script_dir/../.claude-plugin/plugin.json")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0 total=0
check() { # check <descrição> <esperado> <obtido>
  total=$((total + 1))
  if [[ "$3" == "$2" ]]; then
    printf 'ok      %s\n' "$1"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3"
  fi
}

# Ambiente isolado: HOME, config e cache temporários; gh falso que devolve FAKE_ISSUES.
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_CACHE_HOME="$tmp/home/.cache"
export CLAUDE_CONFIG_DIR="$tmp/home/.claude"
mkdir -p "$HOME" "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_ISSUES"
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
export FAKE_ISSUES="$tmp/issues.json"
cat >"$FAKE_ISSUES" <<'EOF'
[
  {"labels": [{"name": "agente"}, {"name": "precisa-info"}]},
  {"labels": [{"name": "agente"}, {"name": "spec-pronta"}]},
  {"labels": [{"name": "agente"}, {"name": "spec-pronta"}, {"name": "spec-aprovada"}]},
  {"labels": [{"name": "agente"}, {"name": "pronto-revisao"}]},
  {"labels": [{"name": "enhancement"}]},
  {"labels": []}
]
EOF

# Repositório git de teste
repo="$tmp/meu-app"
git init -q -b main "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
render() { "$statusline" <<<"$1" | plain; }

# --- Renderização ---
base='"workspace":{"current_dir":"'"$repo"'","repo":{"owner":"o","name":"r"}},"model":{"display_name":"Opus"}'

render "{$base}" >/dev/null # primeira chamada dispara o cache em segundo plano
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$XDG_CACHE_HOME/fabrica/statusline/o_r" ]] && break; sleep 0.2; done
check "cache guarda esperando e backlog" "3 2" "$(cat "$XDG_CACHE_HOME/fabrica/statusline/o_r" 2>/dev/null)"

check "main em destaque, issues e backlog, sem limites" \
  "meu-app main · 3 issues · 2 backlog │ Opus · ctx 0%" "$(render "{$base}")"

git -C "$repo" checkout -q -b feat/12-tela-login
check "branch da fábrica vira tipo e número da issue" \
  "meu-app feat #12 · 3 issues · 2 backlog │ Opus · ctx 0%" "$(render "{$base}")"

full="{$base"',"effort":{"level":"medium"},"context_window":{"used_percentage":63.7},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":0},"seven_day":{"used_percentage":84.2}},"cost":{"total_cost_usd":2.71},"pr":{"number":78,"review_state":"pending"},"worktree":{"name":"wt1"}}'
out="$(render "$full")"
reset_hm="$(date -d @0 +%H:%M)"
check "PR, worktree, esforço abreviado, contexto e limites, sem custo" \
  "meu-app feat #12 (worktree wt1) · PR #78 pending · 3 issues · 2 backlog │ Opus med · ctx 63% · 5h 23% ↻${reset_hm} · 7d 84%" "$out"

echo '[{"labels": [{"name": "agente"}, {"name": "escalonado"}]}]' >"$FAKE_ISSUES"
rm -f "$XDG_CACHE_HOME/fabrica/statusline/o_r"
render "{$base}" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$XDG_CACHE_HOME/fabrica/statusline/o_r" ]] && break; sleep 0.2; done
check "uma issue no singular e backlog zerado some" \
  "meu-app feat #12 · 1 issue │ Opus · ctx 0%" "$(render "{$base}")"

check "fora de um repositório do GitHub, sem contadores" \
  "tmp │ Opus · ctx 0%" "$(render '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"}}')"

# --- Instalação ---
settings="$CLAUDE_CONFIG_DIR/settings.json"
dest="$XDG_CONFIG_HOME/fabrica/statusline.sh"

check "check sem settings.json" "ausente" "$("$setup" --check)"
check "instala sem settings.json" "instalada $version" "$("$setup")"
check "statusLine aponta para a cópia" "$dest 60" "$(jq -r '"\(.statusLine.command) \(.statusLine.refreshInterval)"' "$settings")"
check "cópia é executável" "sim" "$([[ -x "$dest" ]] && echo sim || echo não)"
check "check depois de instalar" "ok" "$("$setup" --check)"

echo "0.0.0" >"$XDG_CONFIG_HOME/fabrica/statusline.VERSION"
check "check atualiza a cópia quando a versão muda" "atualizado $version" "$("$setup" --check)"

echo '{"theme": "dark", "statusLine": {"type": "command", "command": "~/minha.sh"}}' >"$settings"
check "check com statusline de outra origem" "outra ~/minha.sh" "$("$setup" --check)"
"$setup" >/dev/null 2>&1; rc=$?
check "não troca statusline de outra origem sem --force" "1 ~/minha.sh" "$rc $(jq -r .statusLine.command "$settings")"
check "troca com --force e mantém as outras chaves" "instalada $version dark $dest" \
  "$("$setup" --force) $(jq -r '"\(.theme) \(.statusLine.command)"' "$settings")"
check "guarda backup do settings.json" "~/minha.sh" "$(jq -r .statusLine.command "$settings.bak-fabrica")"

echo '{ quebrado' >"$settings"
"$setup" --check >/dev/null 2>&1; rc=$?
check "settings.json inválido falha sem alterar" "1 { quebrado" "$rc $(cat "$settings")"

echo
echo "$((total - failures))/$total testes passaram"
[[ $failures -eq 0 ]]
