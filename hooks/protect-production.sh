#!/usr/bin/env bash
# PreToolUse (Bash): recusa comandos que citam um padrão de produção do
# repositório (ADR 0006). Os padrões ficam em .fabrica/producao.txt, uma
# regra por linha:
#   host <domínio>   (aceita o curinga *. no início)
#   texto <literal>  (mínimo de 4 caracteres)
# Vale a união da cópia de trabalho com a versão do branch padrão do origin,
# que só muda por merge do usuário: apagar a linha na branch não libera o
# comando. A comparação é por substring literal, sem diferenciar maiúsculas.
# Como o protect-main.sh, é uma checagem de texto: pega o erro inocente, e a
# barreira de rede, no modo sbx, é a política da VM (ADR 0010).
#
# Aceita dois contratos de entrada e responde no de quem chamou:
#   Claude Code:  .tool_input.command          -> hookSpecificOutput
#   Antigravity:  .toolCall.args.CommandLine   -> {decision, reason}

if ! command -v jq >/dev/null || ! command -v git >/dev/null; then
  echo "protect-production: faltam o jq ou o git; os padrões de produção não foram conferidos." >&2
  exit 0
fi

input=$(cat)
cmd=$(jq -r '.tool_input.command // .toolCall.args.CommandLine // ""' <<<"$input")
[[ -n $cmd ]] || exit 0
# No Antigravity, o hook roda na pasta do plugin: sem o cwd na entrada, a
# pasta do projeto vem de workspacePaths, e não do $PWD.
cwd=$(jq -r '.cwd // .workspacePaths[0]? // ""' <<<"$input")
[[ -n $cwd ]] || cwd=${CLAUDE_PROJECT_DIR:-$PWD}

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
file=.fabrica/producao.txt

rules=""
[[ -f $root/$file ]] && rules=$(<"$root/$file")

# Branch padrão do origin, ou main. Sem fetch: vale a última versão buscada.
ref=$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
[[ -n $ref ]] || ref=origin/main
if remote=$(git -C "$root" show "$ref:$file" 2>/dev/null); then
  rules+=$'\n'"$remote"
fi
[[ -n ${rules//[[:space:]]/} ]] || exit 0

lower=${cmd,,}
while IFS= read -r line; do
  line=${line%$'\r'}
  read -r kind value <<<"$line"
  [[ -z $kind || $kind == \#* || -z $value ]] && continue
  case $kind in
    host) needle=${value#\*} ;;
    texto) (( ${#value} >= 4 )) || continue; needle=$value ;;
    *) continue ;;
  esac
  [[ -n $needle ]] || continue
  if [[ $lower == *"${needle,,}"* ]]; then
    reason="Este comando cita um padrão de produção (\`$value\`, de $file). As etapas de agente só usam dev ou homologação: o que é de produção vai para o runbook e é rodado por você."
    if jq -e 'has("toolCall")' <<<"$input" >/dev/null 2>&1; then
      jq -n --arg r "$reason" '{decision: "deny", reason: $r}'
    else
      jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    fi
    exit 0
  fi
done <<<"$rules"
exit 0
