#!/usr/bin/env bash
# SessionStart: confere os hooks do git da fábrica com setup-githooks.sh --check
# e avisa ou informa conforme a tabela de saídas da SPEC-246. Nas saídas
# silenciosas, não imprime nada.
#
# Aceita dois contratos e responde no de quem chamou:
#   Claude Code:  stdin com session_id    -> texto puro (vira contexto do modelo)
#   Antigravity:  stdin com conversationId -> {"injectSteps":[{"systemMessage":...}]}
# O agy lê o stdout como JSON e descarta o texto puro com erro de parsing (#178).

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

input=$(cat 2>/dev/null || true)

line=$(bash "$plugin_root/scripts/setup-githooks.sh" --check 2>/dev/null)
rc=$?

v='(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})'
fail_codes='origem-invalida|destino-invalido|preparacao|publicacao|interrompida|rollback-interrompido|danificada|versao-desconhecida|trava'
unknown='A verificação dos hooks do git da fábrica não respondeu como esperado, e a proteção da main pode estar incompleta. Rode /fabrica:setup.'

# As mensagens são fixas por saída e só interpolam versões já conferidas.
msg=""
if [[ $line =~ ^(ok|ocupado\ integra|atualizado\ $v|mais-novo\ $v)$ ]]; then
  ((rc == 0)) || msg=$unknown
elif ((rc == 1)) && [[ $line =~ ^falha\ ($fail_codes)$ ]]; then
  msg="A verificação dos hooks do git da fábrica falhou (${BASH_REMATCH[1]}), e a proteção da main pode estar incompleta. Rode /fabrica:setup para ver o diagnóstico."
elif ((rc != 0)); then
  msg=$unknown
elif [[ $line == ausente ]]; then
  msg='Os hooks do git da fábrica não estão instalados nesta máquina. Rode /fabrica:setup.'
elif [[ $line =~ ^reparado\ ($v)$ ]]; then
  msg="Os hooks do git da fábrica estavam danificados ou com uma atualização interrompida e foram recuperados na versão ${BASH_REMATCH[1]}."
elif [[ $line =~ ^mais-novo\ ($v)\ incerta$ ]]; then
  msg="Os hooks do git da fábrica nesta máquina são da versão ${BASH_REMATCH[1]}, mais nova que a deste plugin. Não houve downgrade, mas a integridade deles não está comprovada. Rode o setup de uma distribuição da fábrica na versão ${BASH_REMATCH[1]} ou mais nova."
elif [[ $line =~ ^divergente\ ($v)$ ]]; then
  msg="Os hooks do git da fábrica instalados (versão ${BASH_REMATCH[1]}) têm conteúdo diferente do deste plugin na mesma versão. Nada foi alterado. Rode /fabrica:setup para ver as opções."
elif [[ $line =~ ^divergente\ ($v)\ incerta$ ]]; then
  msg="Os hooks do git da fábrica instalados (versão ${BASH_REMATCH[1]}) têm conteúdo diferente do deste plugin na mesma versão, e a integridade deles não está comprovada. Nada foi alterado. Rode /fabrica:setup para ver as opções."
elif [[ $line == 'ocupado incerta' ]]; then
  msg='Outro processo está atualizando os hooks do git da fábrica, ou a trava deles precisa de conferência manual. Se o aviso se repetir, siga a recuperação manual da trava em docs/solucao-de-problemas.md.'
else
  msg=$unknown
fi

[[ -n $msg ]] || exit 0

if jq -e 'has("conversationId")' <<<"$input" >/dev/null 2>&1; then
  jq -n --arg m "$msg" '{injectSteps: [{systemMessage: {systemMessage: $m}}]}'
else
  echo "$msg"
fi
