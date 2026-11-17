#!/usr/bin/env bash
# Teste de aceite do adaptador da fábrica para o OpenCode (fase 5 do
# opencode/PLANO-OPENCODE.md). Rode dentro de uma VM do sbx criada com o agente
# opencode, na pasta do clone. Sobe um `opencode serve` local, sem modelo, e
# confere pela API o plugin, as 12 skills, os 12 comandos, o agente revisor e as
# decisões de permissão dos hooks.
# Imprime "ok <verificação>" ou "falha <verificação>: <motivo>", uma por linha,
# e sai com 1 se alguma falhar.
# Uso: opencode/test-adapter.sh [--root <pasta>]
set -uo pipefail

usage="Uso: opencode/test-adapter.sh [--root <pasta>]"

resolve_root() {
  ( cd "$1" 2>/dev/null && pwd )
}

script_dir="$(resolve_root "$(dirname "${BASH_SOURCE[0]}")")" || {
  echo "test-adapter: não encontrei a pasta do script." >&2
  exit 1
}
root="$(resolve_root "$script_dir/..")"

while [[ $# -gt 0 ]]; do
  case $1 in
    --root)
      if [[ $# -lt 2 ]]; then
        echo "test-adapter: --root precisa de uma pasta. $usage" >&2
        exit 1
      fi
      if [[ ! -d $2 ]]; then
        echo "test-adapter: a pasta do --root não existe: $2" >&2
        exit 1
      fi
      root="$(resolve_root "$2")"
      shift
      ;;
    --help | -h)
      echo "$usage"
      exit 0
      ;;
    *)
      echo "test-adapter: opção desconhecida: $1. $usage" >&2
      exit 1
      ;;
  esac
  shift
done

failures=0
ok() { printf 'ok %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf 'falha %s: %s\n' "$1" "$2"
}

work=""
project=""
server_pid=""
server_out=""
server_url=""
log_file=""
log_offset=0

stop_server() {
  [[ -n $server_pid ]] || return 0
  if kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
  fi
  if kill -0 "$server_pid" 2>/dev/null; then
    return 1
  fi
  server_pid=""
}

cleanup() {
  stop_server || true
  if [[ -n $work ]]; then
    rm -rf "$work"
    work=""
  fi
}
trap cleanup EXIT

# A VM do sbx deixa um dos dois sinais. O servidor grava em ~/.config/opencode e
# ~/.local/share/opencode, então o teste não roda no host.
if [[ ! -e /etc/sandbox-persistent.sh && -z ${PROXY_CA_CERT_B64:-} ]]; then
  bad vm "rode dentro da VM do sbx, com o agente opencode; o servidor grava em ~/.config/opencode e ~/.local/share/opencode"
  echo "test-adapter: fora da VM do sbx este teste não roda. Crie a VM com: sbx create --name opencode-<projeto> opencode ." >&2
  exit 1
fi
ok vm

missing=()
for cmd in opencode git jq realpath; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
  bad binários "faltam no PATH: ${missing[*]}"
  exit 1
fi
ok binários

log_dir="$(opencode debug paths 2>/dev/null | awk '$1 == "log" { print $2; exit }')"
if [[ -z $log_dir ]]; then
  bad log "não encontrei a pasta do log em \`opencode debug paths\`"
  exit 1
fi
log_file="$log_dir/opencode.log"

if [[ ! -f $root/opencode/server.ts ]]; then
  bad plugin "não achei $root/opencode/server.ts; confira o --root"
  exit 1
fi
root_real="$(realpath "$root")"

work="$(mktemp -d "${TMPDIR:-/tmp}/fabrica-opencode.XXXXXX")" || {
  bad limpeza "não consegui criar a pasta temporária"
  exit 1
}
project="$work/projeto"
server_out="$work/servidor.out"
mkdir -p "$project/.fabrica" || {
  bad limpeza "não consegui criar o projeto temporário"
  exit 1
}

if ! git -C "$project" init -q; then
  bad plugin "não consegui iniciar o repositório do projeto temporário"
  exit 1
fi
printf 'host prod.exemplo.com\n' >"$project/.fabrica/producao.txt"
if ! jq -n --arg path "$root/opencode" '{plugins: [$path]}' >"$project/opencode.jsonc"; then
  bad plugin "não consegui escrever o opencode.jsonc do projeto temporário"
  exit 1
fi

# O log é cumulativo: só as linhas acrescentadas depois daqui contam.
if [[ -f $log_file ]]; then
  log_offset="$(wc -c <"$log_file")"
fi

password="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
if [[ -z $password ]]; then
  bad servidor "não consegui gerar a senha do servidor"
  exit 1
fi
export OPENCODE_PASSWORD="$password"

start_server() {
  (
    cd "$project" || exit 1
    exec opencode serve --hostname 127.0.0.1 --port 0
  ) >"$server_out" 2>&1 &
  server_pid=$!
}

wait_url() {
  local _
  for _ in $(seq 1 60); do
    server_url="$(sed -n 's/^server listening on //p' "$server_out" | head -1)"
    [[ -n $server_url ]] && return 0
    kill -0 "$server_pid" 2>/dev/null || return 1
    sleep 0.5
  done
  return 1
}

start_server
if ! wait_url; then
  bad servidor "o opencode serve não imprimiu \`server listening on\` em 30 s: $(tail -5 "$server_out" 2>/dev/null | tr '\n' ' ')"
  exit 1
fi
ok servidor

# As chamadas da API também rodam com o projeto como diretório de trabalho.
cd "$project" || {
  bad plugin "não consegui entrar no projeto temporário"
  exit 1
}

api() {
  opencode api --server "$server_url" --param "location[directory]=$project" "$@"
}

session_json=""
session_id=""
new_session() {
  local body
  body="$(jq -n --arg dir "$project" '{location: {directory: $dir}}')" || return 1
  session_json="$(api --data "$body" POST /api/session 2>/dev/null)" || return 1
  session_id="$(jq -r '.data.id // empty' <<<"$session_json" 2>/dev/null)"
  [[ -n $session_id ]]
}

if ! new_session; then
  bad plugin "não criei a sessão de teste: ${session_json:-sem resposta}"
  exit 1
fi

# O plugin pode não ter registrado os hooks na janela de inicialização (visto na
# #159). A sonda é a mesma avaliação do `permissão: commit`, repetida até 30 s.
permission() {
  local action="$1" resources="$2" body
  body="$(jq -n --arg action "$action" --argjson resources "$resources" \
    '{action: $action, resources: $resources}')" || return 1
  api --data "$body" POST "/api/session/$session_id/permission" 2>/dev/null |
    jq -r '.data.effect // empty' 2>/dev/null
}

plugins_json=""
effect=""
for _ in $(seq 1 60); do
  plugins_json="$(api GET /api/plugin 2>/dev/null)" || plugins_json=""
  count="$(jq -r '[.data[]? | select(.id == "fabrica")] | length' <<<"$plugins_json" 2>/dev/null)"
  status="$(jq -r '.data[]? | select(.id == "fabrica") | .state.status' <<<"$plugins_json" 2>/dev/null)"
  if [[ $count == 1 && $status == active ]]; then
    effect="$(permission shell '["git commit --allow-empty -m teste --no-verify"]')"
    [[ $effect == deny ]] && break
  fi
  sleep 0.5
done

if [[ $effect == deny ]]; then
  ok "plugin pronto"
  ok "permissão: commit"
else
  bad "plugin pronto" "a sonda de negação não respondeu em 30 s (efeito: ${effect:-sem resposta})"
  bad "permissão: commit" "esperava deny, veio ${effect:-sem resposta}"
fi

check_permission() {
  local name="$1" resources="$2" expected="$3" got
  got="$(permission shell "$resources")"
  if [[ $got == "$expected" ]]; then
    ok "$name"
  else
    bad "$name" "esperava $expected, veio ${got:-sem resposta}"
  fi
}

check_permission "permissão: produção" '["curl https://prod.exemplo.com"]' deny
check_permission "permissão: ~/.claude" '["echo x > ~/.claude/teste"]' deny
check_permission "permissão: git status" '["git status"]' allow
check_permission "permissão: linha encadeada" \
  '["git status --short", "git commit --allow-empty -m teste --no-verify"]' deny

commands_json="$(api GET /api/command 2>/dev/null)" || commands_json=""
expected_commands="fabrica:avancar fabrica:backlog fabrica:implementar fabrica:licao fabrica:metricas fabrica:prd fabrica:retro fabrica:revisar fabrica:setup fabrica:spec fabrica:status fabrica:triagem"
got_commands="$(jq -r '.data[]? | select(.name | startswith("fabrica:")) | .name' <<<"$commands_json" 2>/dev/null | LC_ALL=C sort)"
want_commands="$(printf '%s\n' $expected_commands | LC_ALL=C sort)"
if [[ $got_commands == "$want_commands" ]]; then
  ok "12 comandos"
else
  bad "12 comandos" "esperava os 12 comandos: ${want_commands//$'\n'/, }; veio: ${got_commands:-nenhum}"
fi

skills_json="$(api GET /api/skill 2>/dev/null)" || skills_json=""
expected_skills="fabrica-avancar fabrica-backlog fabrica-implementar fabrica-licao fabrica-metricas fabrica-prd fabrica-retro fabrica-revisar fabrica-setup fabrica-spec fabrica-status fabrica-triagem"
got_skills="$(jq -r '.data[]? | select(.id | startswith("fabrica-")) | .id' <<<"$skills_json" 2>/dev/null | LC_ALL=C sort)"
want_skills="$(printf '%s\n' $expected_skills | LC_ALL=C sort)"
skills_problem=""
[[ $got_skills == "$want_skills" ]] || skills_problem="os IDs não batem"
if [[ -z $skills_problem ]]; then
  for id in $expected_skills; do
    want=false
    [[ $id == fabrica-status || $id == fabrica-metricas ]] && want=true
    got="$(jq -r --arg id "$id" '.data[]? | select(.id == $id) | .autoinvoke' <<<"$skills_json" 2>/dev/null)"
    if [[ $got != "$want" ]]; then
      skills_problem+="$id autoinvoke=$got (esperava $want); "
    fi
  done
fi
if [[ -z $skills_problem ]]; then
  ok "12 skills"
else
  bad "12 skills" "$skills_problem"
fi

# A origem do plugin: a pasta de onde ele veio e o path das skills.
plugin_problem=""
count="$(jq -r '[.data[]? | select(.id == "fabrica")] | length' <<<"$plugins_json" 2>/dev/null)"
status="$(jq -r '.data[]? | select(.id == "fabrica") | .state.status' <<<"$plugins_json" 2>/dev/null)"
source_path="$(jq -r '.data[]? | select(.id == "fabrica") | .source.path // empty' <<<"$plugins_json" 2>/dev/null)"
[[ $count == 1 ]] || plugin_problem="há $count plugins fabrica; tire a instalação global da VM e deixe só o projeto"
[[ $status == active ]] || plugin_problem+="status: ${status:-ausente}"
if [[ -n $source_path ]]; then
  source_real="$(realpath "$source_path" 2>/dev/null || echo "$source_path")"
  [[ $source_real == "$root_real/opencode" ]] || plugin_problem+=" origem fora da raiz: $source_path"
else
  plugin_problem+="sem a origem do plugin"
fi
paths="$(jq -r '.data[]? | select(.id | startswith("fabrica-")) | .path' <<<"$skills_json" 2>/dev/null)"
if [[ -z $paths ]]; then
  plugin_problem+="sem skills para conferir a origem"
else
  while IFS= read -r path; do
    real="$(realpath "$path" 2>/dev/null || echo "$path")"
    [[ $real == "$root_real/skills/"* ]] || plugin_problem+=" skill fora da raiz: $path"
  done <<<"$paths"
fi
if [[ -z $plugin_problem ]]; then
  ok plugin
else
  bad plugin "$plugin_problem"
fi

agents_json="$(api GET /api/agent 2>/dev/null)" || agents_json=""
revisor="$(jq -r '.data[]? | select(.id == "fabrica/revisor") | .mode // empty' <<<"$agents_json" 2>/dev/null)"
if [[ $revisor == subagent ]]; then
  ok revisor
else
  bad revisor "esperava fabrica/revisor com mode subagent, veio: ${revisor:-ausente}"
fi

# Só as linhas acrescentadas desde o começo do servidor contam. As negativas
# esperadas dos casos acima são erro no log do plugin, por desenho.
log_since() {
  local offset="$1" size
  [[ -f $log_file ]] || return 0
  size="$(wc -c <"$log_file")"
  (( size > offset )) || return 0
  tail -c +$((offset + 1)) "$log_file"
}
new_log="$(log_since "$log_offset")"
# O console.error do plugin vai para a saída do servidor, e não para o log
# estruturado do CLI: as duas fontes entram na conferência.
unexpected="$(
  {
    [[ -n $new_log ]] && grep -a '\[fabrica\]' <<<"$new_log"
    grep -a '\[fabrica\]' "$server_out" 2>/dev/null
  } | grep -av '\[fabrica\] shell negado (' | head -3 | tr '\n' ' '
)"
if [[ -z $unexpected ]]; then
  ok log
else
  bad log "erro do plugin: $unexpected"
fi

# Limpeza: o servidor e o projeto temporário não ficam para trás.
server_old="$server_pid"
cleaned=1
stop_server || cleaned=0
if [[ -n $work ]]; then
  if rm -rf "$work"; then
    work=""
  else
    cleaned=0
  fi
fi
[[ -e $project ]] && cleaned=0
if [[ -n $server_old ]] && kill -0 "$server_old" 2>/dev/null; then
  cleaned=0
fi
if (( cleaned == 1 )); then
  ok limpeza
else
  bad limpeza "o servidor ou o projeto temporário ficou para trás"
fi

if (( failures > 0 )); then
  exit 1
fi
exit 0
