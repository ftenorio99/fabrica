#!/usr/bin/env bash
# Testa scripts/stage-model.sh (SPEC-179, CA2 a CA6 e CA13) com um `claude` falso.
# Uso: bash scripts/test-stage-model.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/stage-model.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0 total=0

# check <CA> <descrição> <esperado> <obtido>
check() {
  total=$((total + 1))
  if [[ "$4" == "$3" ]]; then
    printf 'ok      %-4s %s\n' "$1" "$2"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3" "$4"
  fi
}

# model <etapa> [label...]: saída padrão do subcomando
model() { bash "$script" model "$@" 2>/dev/null; }
# code <argumentos...>: código de saída
code() { bash "$script" "$@" >/dev/null 2>&1; echo $?; }

# CA2: modelo e esforço de cada etapa.
check CA2 "triagem usa sonnet" "sonnet claude-sonnet-5-5 padrao" "$(model triagem)"
check CA2 "triagem ignora a label" "sonnet claude-sonnet-5-5 padrao" "$(model triagem modelo:opus)"
check CA2 "spec usa opus em esforço médio" "opus claude-opus-5-5 medium" "$(model spec)"
check CA2 "spec usa opus com qualquer label" "opus claude-opus-5-5 medium" "$(model spec modelo:haiku)"
check CA2 "implementar sem label usa sonnet" "sonnet claude-sonnet-5-5 padrao" "$(model implementar)"
check CA2 "implementar ignora labels que não são de modelo" "sonnet claude-sonnet-5-5 padrao" "$(model implementar agente spec-aprovada)"
check CA2 "implementar com modelo:haiku usa haiku" "haiku claude-haiku-5-5 padrao" "$(model implementar modelo:haiku)"
check CA2 "implementar com modelo:opus usa opus" "opus claude-opus-5-5 padrao" "$(model implementar agente modelo:opus)"
check CA2 "revisar sem label usa sonnet" "sonnet claude-sonnet-5-5 padrao" "$(model revisar)"
check CA2 "revisar com modelo:haiku usa sonnet" "sonnet claude-sonnet-5-5 padrao" "$(model revisar modelo:haiku)"
check CA2 "revisar com modelo:opus usa opus" "opus claude-opus-5-5 padrao" "$(model revisar modelo:opus)"

# CA3: labels inconsistentes e etapa desconhecida.
check CA3 "duas labels modelo:* saem com código 2" "2" "$(code model implementar modelo:haiku modelo:opus)"
check CA3 "duas labels iguais também são inconsistência" "2" "$(code model revisar modelo:opus modelo:opus)"
check CA3 "etapa desconhecida sai com código 1" "1" "$(code model deploy)"
check CA3 "label de modelo fora da tabela sai com código 1" "1" "$(code model implementar modelo:gpt)"

# CA4: subida de modelo.
next() { bash "$script" next "$@" 2>/dev/null; }
check CA4 "haiku sem falha fica em haiku" "haiku" "$(next haiku 0)"
check CA4 "haiku com 1 falha sobe para sonnet" "sonnet" "$(next haiku 1)"
check CA4 "sonnet com 1 falha fica em sonnet" "sonnet" "$(next sonnet 1)"
check CA4 "sonnet com 2 falhas sobe para opus" "opus" "$(next sonnet 2)"
check CA4 "sonnet com 3 falhas sobe para opus" "opus" "$(next sonnet 3)"
check CA4 "opus com 5 falhas fica em opus" "opus" "$(next opus 5)"
check CA4 "zero à esquerda não vira octal (08 falhas)" "sonnet" "$(next haiku 08)"
check CA4 "zero à esquerda não vira octal (02 falhas)" "opus" "$(next sonnet 02)"
check CA4 "falhas negativas saem com código 1" "1" "$(code next sonnet -1)"
check CA4 "falhas não numéricas saem com código 1" "1" "$(code next sonnet duas)"
check CA4 "apelido desconhecido sai com código 1" "1" "$(code next gpt 1)"

# O claude falso grava um argumento por linha e imprime um JSON fixo.
fake="$tmp/claude"
args_file="$tmp/args.txt"
cat > "$fake" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$args_file"
echo '{"result":"ok"}'
EOF
chmod +x "$fake"

# run <etapa> <nº> [label...]: com HOME fora do clone, como numa máquina comum
# (e fora da VM do sbx, para o modo de permissão ser sempre auto, onde quer que o teste rode)
run() { env -u PROXY_CA_CERT_B64 -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID HOME="$tmp/home" FABRICA_SBX_PERSISTENT_FILE="$tmp/ausente.sh" FABRICA_CLAUDE_BIN="$fake" bash "$script" run "$@" 2>/dev/null; }
args() { tr '\n' ' ' < "$args_file" | sed 's/ $//'; }

# CA5: argumentos do claude.
rm -f "$args_file"
out="$(run spec 179)"
check CA5 "run repassa a saída do claude" '{"result":"ok"}' "$out"
last="$(tail -n 1 "$args_file")"
check CA5 "o último argumento é só o comando e o número" "/fabrica:spec 179" "$last"
check CA5 "spec leva -p, o modelo, o esforço e o modo auto" "yes" \
  "$(args | grep -q -- '^-p --model claude-opus-5-5 --effort medium --permission-mode auto --output-format json ' && echo yes || echo no)"
rm -f "$args_file"
run implementar 12 agente modelo:haiku >/dev/null
check CA5 "implementar com modelo:haiku usa o ID do haiku" "yes" \
  "$(args | grep -q -- '--model claude-haiku-5-5 ' && echo yes || echo no)"
check CA5 "esforço padrão não leva --effort" "no" \
  "$(args | grep -q -- '--effort' && echo yes || echo no)"
rm -f "$args_file"
run triagem '12; rm' >/dev/null
check CA5 "número com texto sai com código 1" "1" "$(run triagem '12; rm' >/dev/null 2>&1; echo $?)"
check CA5 "número inválido não chama o binário" "no" "$([[ -e "$args_file" ]] && echo yes || echo no)"
check CA5 "número zero sai com código 1" "1" "$(run triagem 0 >/dev/null 2>&1; echo $?)"
check CA5 "labels inconsistentes saem com código 2" "2" \
  "$(run implementar 12 modelo:haiku modelo:opus >/dev/null 2>&1; echo $?)"

# CA6: --plugin-dir só quando o plugin roda de um clone.
clone_root="$(cd "$script_dir/.." && pwd -P)"
rm -f "$args_file"
run triagem 12 >/dev/null
check CA6 "fora de ~/.claude/plugins/ leva --plugin-dir do clone" "yes" \
  "$(grep -qx -- "$clone_root" "$args_file" && grep -qx -- '--plugin-dir' "$args_file" && echo yes || echo no)"

installed="$tmp/home/.claude/plugins/cache/fabrica/fabrica/9.9.9"
prepare_installed_fixture() {
  local source_dir="$1" target="$2"
  mkdir -p "$target/scripts" "$target/skills/avancar" &&
    cp "$source_dir"/{stage-model,harness,sbx-context,setup-isolation,run-as-agent}.sh "$target/scripts/" &&
    cp "$source_dir/../skills/avancar/modelos.md" "$target/skills/avancar/modelos.md" || {
      printf '%s\n' 'test-stage-model: falha ao preparar a fixture do cache do plugin' >&2
      exit 1
    }
}
prepare_installed_fixture "$script_dir" "$installed"

# O preparo negativo roda em subshell para que seu exit seja verificável.
cache_error="$(
  exec 2>&1
  prepare_installed_fixture "$tmp/origem-ausente/scripts" "$tmp/cache-negativo"
  printf '%s\n' 'preparo continuou indevidamente'
  exit 0
)"
cache_status=$?
check CA6 "falha na cópia obrigatória encerra a preparação" 1 "$cache_status"
check CA6 "falha na preparação emite diagnóstico" sim \
  "$( [[ "$cache_error" == *'falha ao preparar a fixture do cache do plugin'* ]] && echo sim || echo não )"

rm -f "$args_file"
env -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID HOME="$tmp/home" \
  FABRICA_SBX_PERSISTENT_FILE="$tmp/ausente.sh" FABRICA_CLAUDE_BIN="$fake" \
  bash "$installed/scripts/stage-model.sh" run triagem 12 >/dev/null 2>&1
check CA6 "a fachada no cache consegue rodar o executor" 0 "$?"
check CA6 "de dentro de ~/.claude/plugins/ passa os argumentos sem --plugin-dir" \
  "-p --model claude-sonnet-5-5 --permission-mode auto --output-format json /fabrica:triagem 12" "$(args)"

# O wrapper do dispatcher completa o caminho do plugin quando a fachada está
# no cache. O sudo falso mantém o exec e passa pelo env -i real do wrapper.
fake_sudo="$tmp/sudo"
cat > "$fake_sudo" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2 $3 $4" == "-n -u fabrica-agent -H" ]] || exit 99
shift 4
exec "$@"
EOF
chmod +x "$fake_sudo"
mkdir -p "$tmp/isolation"
: > "$tmp/isolation/agent.env"
env -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID \
  -u PROXY_CA_CERT_B64 HOME="$tmp/home" FABRICA_SBX_PERSISTENT_FILE="$tmp/ausente.sh" \
  FABRICA_CLAUDE_BIN="$installed/scripts/run-as-agent.sh" FABRICA_REAL_CLAUDE_BIN="$fake" \
  FABRICA_ISOLATION_DIR="$tmp/isolation" FABRICA_SUDO_BIN="$fake_sudo" FABRICA_PLUGIN_COPY="$tmp/plugin-copy" \
  bash "$installed/scripts/stage-model.sh" run triagem 12 > "$tmp/wrapper.out"
check B1.2 "a fachada no cache delega para run-as-agent.sh" 0 "$?"
check B1.2 "o wrapper injeta apenas o caminho da cópia isolada" \
  "--plugin-dir $tmp/plugin-copy -p --model claude-sonnet-5-5 --permission-mode auto --output-format json /fabrica:triagem 12" "$(args)"
check B1.2 "o wrapper conserva stdout da etapa" '{"result":"ok"}' "$(cat "$tmp/wrapper.out")"

# CA13: modo de permissão pela VM e pelo modo de isolamento.
proj="$tmp/proj"
mkdir -p "$proj/.fabrica"
vm_file="$tmp/sandbox-persistent.sh"
: > "$vm_file"
perm_mode() { awk 'prev == "--permission-mode" { print; exit } { prev = $0 }' "$args_file"; }
# mode_of <vm|host> <conteúdo de isolamento.txt | -sem-arquivo>: valor de --permission-mode
mode_of() {
  local where="$1" iso="$2" persistent="$tmp/ausente.sh"
  [[ "$where" == "vm" ]] && persistent="$vm_file"
  rm -f "$proj/.fabrica/isolamento.txt" "$args_file"
  [[ "$iso" == "-sem-arquivo" ]] || printf '%s\n' "$iso" > "$proj/.fabrica/isolamento.txt"
  (cd "$proj" && env -u PROXY_CA_CERT_B64 -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID \
    -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID \
    HOME="$tmp/home" FABRICA_SBX_PERSISTENT_FILE="$persistent" \
    FABRICA_CLAUDE_BIN="$fake" bash "$script" run triagem 12 >/dev/null 2>&1)
  perm_mode
}
check CA13 "VM com modo sbx usa bypassPermissions" "bypassPermissions" "$(mode_of vm sbx)"
check CA13 "VM com sem-sandbox usa auto" "auto" "$(mode_of vm sem-sandbox)"
check CA13 "host com modo sbx usa auto" "auto" "$(mode_of host sbx)"
check CA13 "host com sem-sandbox usa auto" "auto" "$(mode_of host sem-sandbox)"
check CA13 "VM sem arquivo de modo (ausente) usa auto" "auto" "$(mode_of vm -sem-arquivo)"
check CA13 "VM com modo inválido usa auto" "auto" "$(mode_of vm valor-estranho)"

# Um dos scripts de isolamento falhando também cai em auto: cópia do script com
# os dois auxiliares trocados por versões falsas.
broken="$tmp/broken"
mkdir -p "$broken/scripts" "$broken/skills/avancar"
cp "$script" "$broken/scripts/"
cp "$script_dir/harness.sh" "$broken/scripts/harness.sh"
cp "$script_dir/../skills/avancar/modelos.md" "$broken/skills/avancar/modelos.md"
run_broken() { (cd "$proj" && env -u PROXY_CA_CERT_B64 -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$broken/scripts/stage-model.sh" run triagem 12 >/dev/null 2>&1); }
printf '#!/usr/bin/env bash\nexit 3\n' > "$broken/scripts/sbx-context.sh"
printf '#!/usr/bin/env bash\necho sbx\n' > "$broken/scripts/setup-isolation.sh"
rm -f "$args_file"; run_broken
check CA13 "sbx-context.sh falhando usa auto" "auto" "$(perm_mode)"
printf '#!/usr/bin/env bash\necho "onde vm"\n' > "$broken/scripts/sbx-context.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$broken/scripts/setup-isolation.sh"
rm -f "$args_file"; run_broken
check CA13 "setup-isolation.sh falhando usa auto" "auto" "$(perm_mode)"

# CA2 (SPEC-241): agy-tier foi removido e sai com código 1 (subcomando desconhecido).
agy_tier_code() { bash "$script" agy-tier "$@" >/dev/null 2>&1; echo $?; }
check CA2 "agy-tier removido sai com código 1" "1" "$(agy_tier_code triagem)"

# B1.1: o processo herda o diretório e o ambiente, substitui a fachada com
# exec, e conserva os dois canais de saída e o código nativo.
process_dir="$tmp/projeto com espaco"
executor="$tmp/claude falso"
mkdir -p "$process_dir"
printf '{ "is_error": false, "result": "linha\\nseguinte" }\n\n' > "$process_dir/native.json"
cat > "$executor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$LC_ALL" "$TEST_MARKER" "$$" > process.txt
cat native.json
printf 'diagnóstico do processo\n\n' >&2
exit "$TEST_EXIT"
EOF
chmod +x "$executor"
process_run() (
  cd "$process_dir" || exit 1
  export HOME="$tmp/home" FABRICA_CLAUDE_BIN="$executor" TEST_MARKER="valor de teste" TEST_EXIT="$1"
  unset CLAUDECODE FABRICA_HARNESS OPENCODE_SESSION_ID ANTIGRAVITY_AGENT ANTIGRAVITY_CONVERSATION_ID
  exec bash -c 'echo "$$" > facade.pid; exec bash "$@"' bash "$script" run triagem 12
)
process_run 0 > "$process_dir/stdout" 2> "$process_dir/stderr"
check B1.1 "executor com espaço no caminho roda com sucesso" 0 "$?"
check B1.1 "stdout conserva o JSON e as quebras finais" sim \
  "$(cmp -s "$process_dir/native.json" "$process_dir/stdout" && echo sim || echo não)"
check B1.1 "stderr conserva o diagnóstico separado do JSON" sim \
  "$(printf 'diagnóstico do processo\n\n' | cmp -s - "$process_dir/stderr" && echo sim || echo não)"
check B1.1 "diretório, locale e variável herdada chegam ao executor" \
  "$(printf '%s\n' "$process_dir" C.UTF-8 'valor de teste')" "$(head -n 3 "$process_dir/process.txt")"
check B1.1 "exec preserva o PID da fachada" "$(cat "$process_dir/facade.pid")" "$(tail -n 1 "$process_dir/process.txt")"
for native_exit in 2 3 124 130 143; do
  process_run "$native_exit" > "$process_dir/stdout" 2> "$process_dir/stderr"
  check B1.1 "a fachada repassa o código nativo $native_exit" "$native_exit" "$?"
done
check B1.1 "saída do processo continua disponível depois de exit não zero" sim \
  "$(cmp -s "$process_dir/native.json" "$process_dir/stdout" && echo sim || echo não)"

# BASH_ENV pode ter efeitos a cada inicialização de Bash. Entrar no executor
# intermediário deve preservar o ambiente sem carregar o arquivo outra vez.
printf '%s\n' 'export TEST_BOOTSTRAPS=$(( ${TEST_BOOTSTRAPS:-0} + 1 ))' > "$tmp/startup.sh"
cat > "$executor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_BOOTSTRAPS" "$BASH_ENV"
EOF
out="$(BASH_ENV="$tmp/startup.sh" TEST_BOOTSTRAPS=0 process_run 0)"
check B1.2 "BASH_ENV roda só no lançador, na fachada e no binário falso" \
  "$(printf '3\n%s' "$tmp/startup.sh")" "$out"

# CA1 (SPEC-247): confira o ambiente e as inicializações nos filhos da
# fachada. As sondas falsas exercitam os mesmos pontos de chamada da base.
cat > "$tmp/registrar-ambiente.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s %s %s\n' "${0##*/}" "${BASH_ENV-<ausente>}" "${TEST_BOOTSTRAPS:-0}" >> "$TEST_LOG"
if [[ ${bash_env_exported+x} || ${bash_env_value+x} ]]; then
  printf 'atributos internos exportados\n' >> "$TEST_LOG"
fi
case "${0##*/}" in
  harness.sh) echo claude ;;
  sbx-context.sh) echo 'onde host' ;;
  setup-isolation.sh) echo sem-sandbox ;;
esac
EOF
for child in harness.sh sbx-context.sh setup-isolation.sh; do
  cp "$tmp/registrar-ambiente.sh" "$broken/scripts/$child"
done
cp "$tmp/registrar-ambiente.sh" "$executor"
chmod +x "$executor"
cat > "$tmp/startup.sh" <<'EOF'
export TEST_BOOTSTRAPS=$(( ${TEST_BOOTSTRAPS:-0} + 1 ))
printf 'início %s\n' "${0##*/}" >> "$TEST_LOG"
if [[ ${0##*/} == stage-model.sh ]]; then
  case "$TEST_CASE" in
    local) unset BASH_ENV; BASH_ENV="$TEST_SECONDARY" ;;
    desexportada) export -n BASH_ENV ;;
    removida) unset BASH_ENV ;;
    alterada) BASH_ENV="$TEST_SECONDARY" ;;
    allexport) set -a ;;
    readonly) readonly BASH_ENV ;;
    array) unset BASH_ENV; declare -ax BASH_ENV=("$TEST_SECONDARY") ;;
  esac
fi
EOF
cat > "$tmp/secondary.sh" <<'EOF'
export TEST_BOOTSTRAPS=$(( ${TEST_BOOTSTRAPS:-0} + 1 ))
printf 'alternativo %s\n' "${0##*/}" >> "$TEST_LOG"
EOF
bash_env_log() {
  local scenario="$1"
  shift
  : > "$tmp/bootstrap.log"
  env -u BASH_ENV -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID \
    -u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID HOME="$tmp/home" \
    FABRICA_CLAUDE_BIN="$executor" TEST_CASE="$scenario" TEST_BOOTSTRAPS=0 \
    TEST_LOG="$tmp/bootstrap.log" TEST_SECONDARY="$tmp/secondary.sh" "$@" \
    bash "$broken/scripts/stage-model.sh" run triagem 12 2>"$tmp/bootstrap.err" || return
  if [[ -s "$tmp/bootstrap.err" ]]; then
    cat "$tmp/bootstrap.err"
    return
  fi
  cat "$tmp/bootstrap.log"
}
expect_bash_env() {
  local scenario="$1" value="$2" bootstraps="$3" startup="$4" child_startup="$5"
  shift 5
  local expected child actual
  expected="$(
    if [[ -n "$startup" ]]; then
      printf '%s stage-model.sh\n' "$startup"
    fi
    for child in harness.sh sbx-context.sh setup-isolation.sh "${executor##*/}"; do
      if [[ -n "$child_startup" ]]; then
        printf '%s %s\n' "$child_startup" "$child"
      fi
      printf '%s %s %s\n' "$child" "$value" "$bootstraps"
    done
  )"
  actual="$(bash_env_log "$scenario" "$@")" || actual="falha ao executar a fachada: $?"
  check CA1 "BASH_ENV $scenario preserva ambiente e inicializações" "$expected" "$actual"
}
expect_bash_env ausente '<ausente>' 0 '' ''
expect_bash_env vazia '' 0 '' '' BASH_ENV=
expect_bash_env exportada "$tmp/startup.sh" 2 início início BASH_ENV="$tmp/startup.sh"
expect_bash_env local '<ausente>' 1 início '' BASH_ENV="$tmp/startup.sh"
expect_bash_env desexportada '<ausente>' 1 início '' BASH_ENV="$tmp/startup.sh"
expect_bash_env removida '<ausente>' 1 início '' BASH_ENV="$tmp/startup.sh"
expect_bash_env alterada "$tmp/secondary.sh" 2 início alternativo BASH_ENV="$tmp/startup.sh"
expect_bash_env allexport "$tmp/startup.sh" 2 início início BASH_ENV="$tmp/startup.sh"
expect_bash_env readonly "$tmp/startup.sh" 2 início início BASH_ENV="$tmp/startup.sh"
expect_bash_env array '<ausente>' 1 início '' BASH_ENV="$tmp/startup.sh"

if python3 -I "$script_dir/test-stage-model-environment.py" > "$tmp/environment-diff.log" 2>&1; then
  environment_diff=igual
else
  environment_diff="$(cat "$tmp/environment-diff.log")"
fi
check CA1 "ambiente integral e resultado iguais à base de4c39a" igual "$environment_diff"

echo
echo "$((total - failures)) de $total passaram."
[[ $failures -eq 0 ]]
