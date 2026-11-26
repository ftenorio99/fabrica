#!/usr/bin/env bash
# Detecta a harness que executa a etapa da fábrica (SPEC-200, ADR 0013).
#
# Uso:
#   harness.sh detect -> claude-code | opencode | antigravity | binario
#
# Precedência: CLAUDECODE (um claude -p aberto de dentro do OpenCode ou do
# Antigravity herda as variáveis da sessão e precisa continuar sendo Claude
# Code), FABRICA_HARNESS (injetada pelo adaptador ou override manual),
# OPENCODE_SESSION_ID, ANTIGRAVITY_AGENT / ANTIGRAVITY_CONVERSATION_ID e, sem
# sinal, binario (regra antiga do /fabrica:avancar, pelo binário claude).
#
# Saídas: 0 detectou; 1 uso inválido; 2 FABRICA_HARNESS com valor desconhecido.
set -uo pipefail
export LC_ALL=C.UTF-8

usage() {
  echo "uso: harness.sh detect" >&2
  exit 1
}

cmd_detect() {
  [[ $# -eq 0 ]] || usage

  if [[ -n "${CLAUDECODE:-}" ]]; then
    echo claude-code
    return 0
  fi

  if [[ -n "${FABRICA_HARNESS:-}" ]]; then
    case "$FABRICA_HARNESS" in
      opencode | antigravity | claude-code)
        echo "$FABRICA_HARNESS"
        return 0
        ;;
      *)
        echo "harness: FABRICA_HARNESS inválida: '$FABRICA_HARNESS'. Use opencode, antigravity ou claude-code." >&2
        return 2
        ;;
    esac
  fi

  if [[ -n "${OPENCODE_SESSION_ID:-}" ]]; then
    echo opencode
    return 0
  fi

  if [[ -n "${ANTIGRAVITY_AGENT:-}" || -n "${ANTIGRAVITY_CONVERSATION_ID:-}" ]]; then
    echo antigravity
    return 0
  fi

  echo binario
}

[[ $# -ge 1 ]] || usage
sub="$1"
shift
case $sub in
  detect) cmd_detect "$@" ;;
  *) usage ;;
esac
