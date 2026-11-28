# Módulo interno de stage-model.sh. Carregado antes do despacho dos comandos,
# depois de disponibilizar as funções de seleção e o diretório dos scripts.

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
