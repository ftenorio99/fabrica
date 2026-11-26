#!/usr/bin/env bash
# Escolhe o modelo de cada etapa da fábrica e executa a etapa num `claude -p`
# (SPEC-179, ADR 0013). A fonte da verdade é skills/avancar/modelos.md.
#
# Uso:
#   stage-model.sh model <etapa> [label...]    -> "<apelido> <id> <esforço>"
#   stage-model.sh agy-tier <etapa> [label...] -> "<flash_lite|flash|pro>"
#   stage-model.sh next <apelido> <falhas>     -> apelido do próximo modelo
#   stage-model.sh run <etapa> <nº> [label...]  -> executa o claude e repassa a saída
#
# Variáveis: FABRICA_CLAUDE_BIN (binário, padrão claude) e
# FABRICA_MODELS_FILE (troca o caminho de modelos.md, só para os testes).
# O modo de permissão do run é bypassPermissions só dentro da VM do sbx com o
# projeto em modo sbx (sbx-context.sh e setup-isolation.sh); senão, auto.
# Saída: 0 sucesso; 1 uso/configuração inválida; 2 duas ou mais labels modelo:*;
# 3 harness de sessão (a etapa roda no modelo da sessão, sem claude -p).
set -uo pipefail
export LC_ALL=C.UTF-8

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
models_file="${FABRICA_MODELS_FILE:-$script_dir/../skills/avancar/modelos.md}"

fail() {
  echo "stage-model: $*" >&2
  exit 1
}

[[ -f "$models_file" ]] || fail "não encontrei a tabela de modelos em $models_file."

# Linhas "apelido<TAB>id<TAB>tier-agy" da seção "Modelos".
model_rows() {
  awk -F'|' '
    /^## / { in_t = ($0 == "## Modelos"); next }
    in_t && /^\| *`/ {
      for (i = 2; i <= 4; i++) { gsub(/^ +| +$/, "", $i); gsub(/`/, "", $i) }
      print $2 "\t" $3 "\t" $4
    }
  ' "$models_file"
}

# Linhas "etapa<TAB>regra<TAB>modelo<TAB>esforço<TAB>opus-se" da seção "Etapas".
stage_rows() {
  awk -F'|' '
    /^## / { in_t = ($0 == "## Etapas"); next }
    in_t && /^\| *`/ {
      for (i = 2; i <= 6; i++) { gsub(/^ +| +$/, "", $i); gsub(/`/, "", $i) }
      print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6
    }
  ' "$models_file"
}

# Linhas "apelido<TAB>falhas<TAB>sobe-para" da seção "Escalonamento".
step_rows() {
  awk -F'|' '
    /^## / { in_t = ($0 == "## Escalonamento"); next }
    in_t && /^\| *`/ {
      for (i = 2; i <= 4; i++) { gsub(/^ +| +$/, "", $i); gsub(/`/, "", $i) }
      print $2 "\t" $3 "\t" $4
    }
  ' "$models_file"
}

model_id() { # model_id <apelido>
  model_rows | awk -F'\t' -v a="$1" '$1 == a { print $2; found = 1 } END { exit !found }'
}

agy_tier() { # agy_tier <apelido>
  model_rows | awk -F'\t' -v a="$1" '$1 == a && $3 != "" { print $3; found = 1 } END { exit !found }'
}

# Apelido pedido pelas labels: imprime vazio (sem label) ou o apelido. Sai com 2
# quando há mais de uma label modelo:*.
label_alias() { # label_alias <label...>
  local found="" l
  for l in "$@"; do
    case $l in
      modelo:*)
        [[ -z "$found" ]] || { echo "stage-model: duas ou mais labels modelo:* na issue." >&2; return 2; }
        found="${l#modelo:}"
        ;;
    esac
  done
  if [[ -n "$found" ]]; then
    model_id "$found" >/dev/null || { echo "stage-model: label modelo:$found sem modelo na tabela." >&2; return 1; }
  fi
  printf '%s' "$found"
}

resolve_stage_selection() { # resolve_stage_selection <etapa> [label...] -> "<apelido>\t<esforço>"
  local stage="$1" row rule alias effort opus_if label rc
  shift
  row="$(stage_rows | awk -F'\t' -v s="$stage" '$1 == s { print; exit }')"
  [[ -n "$row" ]] || fail "etapa desconhecida: $stage."
  IFS=$'\t' read -r _ rule alias effort opus_if <<< "$row"
  label="$(label_alias "$@")"; rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  case $rule in
    fixo) ;;
    label)
      if [[ "$opus_if" == "sim" ]]; then
        [[ "$label" == "opus" ]] && alias="opus"
      elif [[ -n "$label" ]]; then
        alias="$label"
      fi
      ;;
    *) fail "regra desconhecida para $stage: $rule." ;;
  esac
  printf '%s\t%s\n' "$alias" "$effort"
}

cmd_model() {
  [[ $# -ge 1 ]] || fail "uso: stage-model.sh model <etapa> [label...]"
  local sel rc alias effort
  sel="$(resolve_stage_selection "$@")"; rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  IFS=$'\t' read -r alias effort <<< "$sel"
  printf '%s %s %s\n' "$alias" "$(model_id "$alias")" "$effort"
}

cmd_agy_tier() {
  [[ $# -ge 1 ]] || fail "uso: stage-model.sh agy-tier <etapa> [label...]"
  local sel rc alias effort tier
  sel="$(resolve_stage_selection "$@")"; rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  IFS=$'\t' read -r alias effort <<< "$sel"
  tier="$(agy_tier "$alias")" || fail "apelido $alias sem Tier agy na tabela."
  printf '%s\n' "$tier"
}

cmd_next() {
  [[ $# -eq 2 ]] || fail "uso: stage-model.sh next <apelido> <falhas>"
  local alias="$1" fails="$2" need to
  model_id "$alias" >/dev/null || fail "apelido desconhecido: $alias."
  [[ "$fails" =~ ^[0-9]+$ ]] || fail "falhas precisa ser um inteiro não negativo."
  fails=$((10#$fails)) # 08 e 09 não são octais
  read -r need to <<< "$(step_rows | awk -F'\t' -v a="$alias" '$1 == a { print $2, $3 }')"
  if [[ -n "${need:-}" && "$fails" -ge "$need" ]]; then
    echo "$to"
  else
    echo "$alias"
  fi
}

# Modo de permissão do processo da etapa (SPEC-179, ADR 0013): bypassPermissions
# só dentro da VM do sbx com o projeto em modo sbx; auto em todos os outros
# casos, inclusive quando um dos scripts de isolamento falha.
permission_mode() {
  local where mode
  where="$(bash "$script_dir/sbx-context.sh" --project "$PWD" 2>/dev/null | awk '$1 == "onde" { print $2 }')" || where=""
  mode="$(bash "$script_dir/setup-isolation.sh" --check --project "$PWD" 2>/dev/null)" || mode=""
  if [[ "$where" == "vm" && "$mode" == "sbx" ]]; then
    echo bypassPermissions
  else
    echo auto
  fi
}

cmd_run() {
  [[ $# -ge 2 ]] || fail "uso: stage-model.sh run <etapa> <nº> [label...]"
  local stage="$1" number="$2" selection rc alias id effort
  shift 2
  [[ "$number" =~ ^[1-9][0-9]*$ ]] || fail "o número da issue precisa ser um inteiro positivo."

  local harness
  harness="$(bash "$script_dir/harness.sh" detect)"; rc=$?
  [[ $rc -eq 0 ]] || fail "não consegui detectar a harness."
  case $harness in
    opencode | antigravity)
      echo "stage-model: a harness $harness roda a etapa na sessão; não use stage-model.sh run." >&2
      exit 3
      ;;
  esac

  selection="$(cmd_model "$stage" "$@")"; rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  read -r alias id effort <<< "$selection"

  local args=(-p --model "$id")
  [[ "$effort" == "padrao" ]] || args+=(--effort "$effort")
  args+=(--permission-mode "$(permission_mode)" --output-format json)
  # Fora de ~/.claude/plugins/ o plugin roda de um clone: o processo novo
  # precisa carregar esse clone, e não a versão instalada.
  local plugin_root plugins_dir
  plugin_root="$(cd "$script_dir/.." && pwd -P)"
  plugins_dir="${HOME:-}/.claude/plugins"
  case $plugin_root in
    "$plugins_dir"/*) ;;
    *) args+=(--plugin-dir "$plugin_root") ;;
  esac
  args+=("/fabrica:$stage $number")

  exec "${FABRICA_CLAUDE_BIN:-claude}" "${args[@]}"
}

[[ $# -ge 1 ]] || fail "uso: stage-model.sh model|agy-tier|next|run ..."
sub="$1"
shift
case $sub in
  model) cmd_model "$@" ;;
  agy-tier) cmd_agy_tier "$@" ;;
  next) cmd_next "$@" ;;
  run) cmd_run "$@" ;;
  *) fail "subcomando desconhecido: $sub." ;;
esac
