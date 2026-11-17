#!/usr/bin/env bash
# Statusline da fábrica: onde a sessão está (repositório, branch, issue, PR, issues
# esperando o usuário, backlog) e quanto ainda dá para usar (contexto e limites da
# assinatura). Recebe o JSON da sessão pelo stdin e imprime uma linha.
# Instalada por scripts/setup-statusline.sh; não é chamada direto pelas skills.

input=$(cat)

# Separador \x1f: com tab, campos vazios seguidos colapsariam no read.
IFS=$'\x1f' read -r cwd repo_owner repo_name model effort ctx rl5 rl5_reset rl7 pr_num pr_state wt <<<"$(jq -r '[
  .workspace.current_dir // .cwd // "",
  .workspace.repo.owner // "",
  .workspace.repo.name // "",
  .model.display_name // "",
  .effort.level // "",
  (.context_window.used_percentage // 0 | floor),
  (.rate_limits.five_hour.used_percentage // "" | if . == "" then "" else floor end),
  .rate_limits.five_hour.resets_at // "",
  (.rate_limits.seven_day.used_percentage // "" | if . == "" then "" else floor end),
  .pr.number // "",
  .pr.review_state // "",
  .worktree.name // ""
] | map(tostring) | join("\u001f")' <<<"$input" 2>/dev/null)"

dim=$'\033[2m'; yellow=$'\033[33m'; magenta=$'\033[35m'; reset=$'\033[0m'

# Verde abaixo de 50%, amarelo até 80%, vermelho acima.
color() {
  if [ "$1" -ge 80 ]; then printf '\033[31m'; elif [ "$1" -ge 50 ]; then printf '\033[33m'; else printf '\033[32m'; fi
}

parts=()

# Repositório e branch; numa branch <tipo>/<nº>-<descrição>, o tipo e o número da issue.
loc="${cwd##*/}"
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  if [[ "$branch" =~ ^[a-z]+/([0-9]+)- ]]; then
    loc+=" ${dim}${branch%%/*}${reset} #${BASH_REMATCH[1]}"
  elif [ "$branch" = main ] || [ "$branch" = master ]; then
    loc+=" ${yellow}${branch}${reset}"
  else
    loc+=" ${dim}${branch}${reset}"
  fi
fi
[ -n "$wt" ] && loc+=" ${dim}(worktree ${wt})${reset}"
parts+=("$loc")

[ -n "$pr_num" ] && parts+=("PR #${pr_num}${pr_state:+ ${dim}${pr_state}${reset}}")

# Issues esperando o usuário (aproximadas pelas labels; o quadro exato é o /fabrica:status)
# e backlog (abertas sem a label agente). Cache de 5 min, atualizado em segundo plano;
# o arquivo guarda "<esperando> <backlog>".
if [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/fabrica/statusline"
  mkdir -p "$cache_dir" 2>/dev/null
  cache="$cache_dir/${repo_owner}_${repo_name}"
  if [ ! -f "$cache" ] || [ $(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) )) -gt 300 ]; then
    touch "$cache" 2>/dev/null
    ( gh issue list --repo "$repo_owner/$repo_name" --state open --json labels --limit 200 2>/dev/null \
        | jq -r '[.[] | [.labels[].name]] as $all
              | ([$all[] | select(index("precisa-info") or index("escalonado") or index("acao-externa") or index("pronto-revisao")
                  or (index("spec-pronta") and (index("spec-aprovada") | not)))] | length) as $wait
              | ([$all[] | select(index("agente") | not)] | length) as $backlog
              | "\($wait) \($backlog)"' \
        > "$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache" ) >/dev/null 2>&1 &
    disown 2>/dev/null
  fi
  read -r waiting backlog < "$cache" 2>/dev/null
  if [ "${waiting:-0}" -gt 0 ] 2>/dev/null; then
    [ "$waiting" -gt 1 ] && label=issues || label=issue
    parts+=("${magenta}${waiting} ${label}${reset}")
  fi
  [ "${backlog:-0}" -gt 0 ] 2>/dev/null && parts+=("${dim}${backlog} backlog${reset}")
fi

# Modelo, esforço, contexto e limites da assinatura. Sem custo em dólar: na assinatura
# ele é só uma estimativa a preço de API.
[ "$effort" = medium ] && effort=med
right="${model}${effort:+ ${dim}${effort}${reset}}"
right+=" · ctx $(color "${ctx:-0}")${ctx:-0}%${reset}"
if [ -n "$rl5" ]; then
  reset_at=""
  [ -n "$rl5_reset" ] && reset_at=" ${dim}↻$(date -d "@$rl5_reset" +%H:%M 2>/dev/null)${reset}"
  right+=" · 5h $(color "$rl5")${rl5}%${reset}${reset_at}"
fi
[ -n "$rl7" ] && right+=" · 7d $(color "$rl7")${rl7}%${reset}"

left=""
for p in "${parts[@]}"; do left+="${left:+ · }$p"; done
printf '%s %s│%s %s\n' "$left" "$dim" "$reset" "$right"
