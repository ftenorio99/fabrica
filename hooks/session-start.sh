#!/usr/bin/env bash
# SessionStart: avisa quando os hooks do git da fábrica não estão instalados.
# Sem aviso, não imprime nada.
#
# Aceita dois contratos e responde no de quem chamou:
#   Claude Code:  stdin com session_id    -> texto puro (vira contexto do modelo)
#   Antigravity:  stdin com conversationId -> {"injectSteps":[{"systemMessage":...}]}
# O agy lê o stdout como JSON e descarta o texto puro com erro de parsing (#178).

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

input=$(cat 2>/dev/null || true)

[[ "$(bash "$plugin_root/scripts/setup-githooks.sh" --check 2>/dev/null)" == ausente ]] || exit 0

msg='Os hooks do git da fábrica não estão instalados nesta máquina. Rode /fabrica:setup.'

if jq -e 'has("conversationId")' <<<"$input" >/dev/null 2>&1; then
  jq -n --arg m "$msg" '{injectSteps: [{systemMessage: {systemMessage: $m}}]}'
else
  echo "$msg"
fi
