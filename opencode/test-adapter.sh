#!/usr/bin/env bash
# Teste de aceite do adaptador da fábrica para o OpenCode (fase 5 do
# opencode/PLANO-OPENCODE.md). Rode dentro de uma VM do sbx criada com o agente
# opencode, na pasta do clone. Sobe um `opencode serve` local, sem modelo, e
# confere pela API o plugin, as 12 skills, os 12 comandos, o agente revisor e as
# decisões de permissão dos hooks, na instalação por projeto, na global e nas
# duas juntas.
# Imprime "ok <verificação>" ou "falha <verificação>: <motivo>", uma por linha,
# e sai com 1 se alguma falhar.
# Uso: opencode/test-adapter.sh [--root <pasta>] [--install projeto|global|ambos|todos]
set -uo pipefail

usage="Uso: opencode/test-adapter.sh [--root <pasta>] [--install projeto|global|ambos|todos]"

resolve_root() {
  ( cd "$1" 2>/dev/null && pwd )
}

script_dir="$(resolve_root "$(dirname "${BASH_SOURCE[0]}")")" || {
  echo "test-adapter: não encontrei a pasta do script." >&2
  exit 1
}
root="$(resolve_root "$script_dir/..")"
install="todos"

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
    --install)
      if [[ $# -lt 2 ]]; then
        echo "test-adapter: --install precisa de um modo. $usage" >&2
        exit 1
      fi
      case $2 in
        projeto | global | ambos | todos) install=$2 ;;
        *)
          echo "test-adapter: modo desconhecido no --install: $2. $usage" >&2
          exit 1
          ;;
      esac
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

case $install in
  projeto) modes=(projeto) ;;
  global) modes=(global) ;;
  ambos) modes=(ambos) ;;
  todos) modes=(projeto global ambos) ;;
esac

failures=0
ok() { printf 'ok %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf 'falha %s: %s\n' "$1" "$2"
}

work=""
server_pid=""
server_out=""
server_url=""
log_file=""
log_offset=0
project=""
project_b=""
serve_env=()
api_env=()
api_location=""

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

# A configuração global do OpenCode só é tocada no plano B, quando a versão
# instalada não respeita XDG_CONFIG_HOME: cópia antes, restauração no trap, no
# sucesso e na falha. No caminho normal (XDG), o arquivo global nem é lido pelo
# servidor de teste.
global_cfg="${HOME}/.config/opencode/opencode.jsonc"
global_backup=""
global_written=0

restore_global() {
  (( global_written )) || return 0
  if [[ -n $global_backup && -f $global_backup ]]; then
    cp -p "$global_backup" "$global_cfg" || return 1
  else
    rm -f "$global_cfg" || return 1
  fi
  global_written=0
}

cleanup() {
  stop_server || true
  restore_global || true
  if [[ -n $work ]]; then
    cd / 2>/dev/null || true
    rm -rf "$work"
    work=""
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# A VM do sbx deixa um dos dois sinais. O servidor grava em ~/.config/opencode e
# ~/.local/share/opencode, então o teste não roda no host.
if [[ ! -e /etc/sandbox-persistent.sh && -z ${PROXY_CA_CERT_B64:-} ]]; then
  bad vm "rode dentro da VM do sbx, com o agente opencode; o servidor grava em ~/.config/opencode e ~/.local/share/opencode"
  echo "test-adapter: fora da VM do sbx este teste não roda. Crie a VM com: sbx create --name opencode-<projeto> opencode ." >&2
  exit 1
fi
ok vm

missing=()
for cmd in opencode git jq realpath sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
  bad binários "faltam no PATH: ${missing[*]}"
  exit 1
fi
ok binários

if [[ ! -f $root/opencode/server.ts ]]; then
  bad plugin "não achei $root/opencode/server.ts; confira o --root"
  exit 1
fi
root_real="$(realpath "$root")"

work="$(mktemp -d "${TMPDIR:-/tmp}/fabrica-opencode.XXXXXX")" || {
  bad limpeza "não consegui criar a pasta temporária"
  exit 1
}

global_state() {
  if [[ -f $global_cfg ]]; then
    sha256sum "$global_cfg" | awk '{print $1}'
  else
    echo ausente
  fi
}
global_before="$(global_state)"

# A versão respeita XDG_CONFIG_HOME e XDG_DATA_HOME? Medido com `opencode debug
# paths`, que é barato e não sobe servidor. Sem o respeito, o teste cai na cópia
# e restauração da configuração global.
xdg_probe="$work/xdg-probe"
mkdir -p "$xdg_probe/config/opencode" "$xdg_probe/data" 2>/dev/null
xdg_ok=0
if [[ -n $xdg_probe ]]; then
  probe_paths="$(XDG_CONFIG_HOME="$xdg_probe/config" XDG_DATA_HOME="$xdg_probe/data" \
    opencode debug paths 2>/dev/null)" || probe_paths=""
  probe_config="$(awk '$1 == "config" { print $2; exit }' <<<"$probe_paths")"
  [[ $probe_config == "$xdg_probe/config/opencode" ]] && xdg_ok=1
fi

write_project_config() {
  jq -n --arg path "$root/opencode" '{plugins: [$path]}' >"$project/opencode.jsonc"
}

# Plano B: a configuração global real recebe a entrada do plugin e volta ao que
# era pelo trap. O arquivo existente é copiado inteiro; o teste não tenta
# preservar outras chaves, e a VM é o lugar dele.
prepare_global_write() {
  [[ $global_written == 0 ]] || return 0
  mkdir -p "$(dirname "$global_cfg")" || return 1
  if [[ -f $global_cfg ]]; then
    global_backup="$work/global-opencode.jsonc.bak"
    cp -p "$global_cfg" "$global_backup" || return 1
  else
    global_backup=""
  fi
  global_written=1
}

new_session() {
  local dir="$1" body
  body="$(jq -n --arg dir "$dir" '{location: {directory: $dir}}')" || return 1
  session_json="$(api --data "$body" POST /api/session 2>/dev/null)" || return 1
  session_id="$(jq -r '.data.id // empty' <<<"$session_json" 2>/dev/null)"
  [[ -n $session_id ]]
}

# Espera o plugin da localização atual ficar ativo. O carregamento é preguiçoso,
# por localização: a avaliação que chega antes do setup é atendida pela
# instância anterior, e a troca de localização abre a mesma janela da subida.
wait_plugin() {
  local deadline=$((SECONDS + 30)) plugins count status
  while (( SECONDS < deadline )); do
    plugins="$(api GET /api/plugin 2>/dev/null)" || plugins=""
    count="$(jq -r '[.data[]? | select(.id == "fabrica")] | length' <<<"$plugins" 2>/dev/null)"
    status="$(jq -r '.data[]? | select(.id == "fabrica") | .state.status' <<<"$plugins" 2>/dev/null)"
    if [[ $count == 1 && $status == active ]]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# A sonda é a mesma avaliação do `permissão: commit`, repetida até 30 s: o
# plugin carrega depois do primeiro acesso, na janela de inicialização.
permission() {
  local action="$1" resources="$2" body
  body="$(jq -n --arg action "$action" --argjson resources "$resources" \
    '{action: $action, resources: $resources}')" || return 1
  api --data "$body" POST "/api/session/$session_id/permission" 2>/dev/null |
    jq -r '.data.effect // empty' 2>/dev/null
}

# Conta as linhas de negação que a chamada deixou na saída do servidor. O
# console.error do plugin vai para a saída do `opencode serve`, e não para o log
# estruturado. A espera cobre a escrita assíncrona da linha.
denial_line_count() {
  local needle="$1" offset="$2" count=0 deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    count="$(tail -c +$((offset + 1)) "$server_out" 2>/dev/null |
      grep -acF -- "shell negado (resources): $needle")"
    (( count > 0 )) && break
    sleep 0.2
  done
  # Uma segunda instância do plugin escreveria a linha no mesmo instante; esta
  # pausa dá tempo de a duplicata aparecer.
  sleep 0.3
  count="$(tail -c +$((offset + 1)) "$server_out" 2>/dev/null |
    grep -acF -- "shell negado (resources): $needle")"
  printf '%s' "$count"
}

# Nome da verificação, recursos, efeito esperado. A chamada é repetida até o
# efeito esperado (até 15 s): a avaliação que chega durante a troca de
# localização pode ser atendida pela instância anterior do plugin. Nas
# negativas, guarda quantas linhas de negação a chamada deixou, para a
# conferência do modo `ambos`.
check_permission() {
  local name="$1" resources="$2" expected="$3" got before line count
  local deadline=$((SECONDS + 15))
  before="$(wc -c <"$server_out" 2>/dev/null || echo 0)"
  while :; do
    got="$(permission shell "$resources")"
    [[ $got == "$expected" ]] && break
    (( SECONDS < deadline )) || break
    sleep 0.5
  done
  if [[ $got == "$expected" ]]; then
    ok "$name"
  else
    bad "$name" "esperava $expected, veio ${got:-sem resposta}"
  fi
  if [[ $expected == deny ]]; then
    line="$(jq -r 'join(" && ")' <<<"$resources")"
    count="$(denial_line_count "$line" "$before")"
    [[ $count == 1 ]] || denials_problem+="${name}: ${count:-0} linha(s); "
  fi
}

start_server() {
  (
    cd "$project" || exit 1
    exec "${serve_env[@]}" opencode serve --hostname 127.0.0.1 --port 0
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

api() {
  "${api_env[@]}" opencode api --server "$server_url" --param "location[directory]=$api_location" "$@"
}

# Uma rodada completa numa instalação: projeto temporário (A, com produção; B,
# sem), servidor e conferências próprios. `projeto` e `ambos` escrevem a entrada
# no `opencode.jsonc` do projeto A; `global` e `ambos` escrevem na configuração
# global do servidor de teste.
run_mode() {
  local mode="$1"
  local mode_work="$work/$mode"
  local mode_config="" mode_data="" log_dir="" server_old cleaned=1
  local session_json="" session_id="" plugins_json="" effect="" count status
  local commands_json="" got_commands="" want_commands="" commands_ok=0
  local skills_json="" got_skills="" want_skills="" skills_problem=""
  local plugin_problem="" plugin_count="" source_path="" source_real="" paths=""
  local agents_json="" revisor="" denials_problem=""

  denials_problem=""
  project="$mode_work/projeto-a"
  project_b="$mode_work/projeto-b"
  server_out="$mode_work/servidor.out"
  server_pid=""
  server_url=""
  log_file=""
  log_offset=0
  serve_env=()
  api_env=()
  api_location="$project"

  mkdir -p "$project/.fabrica" "$project_b" || {
    bad "$mode: limpeza" "não consegui criar os projetos temporários"
    return 1
  }
  if ! git -C "$project" init -q || ! git -C "$project_b" init -q; then
    bad "$mode: plugin" "não consegui iniciar os repositórios temporários"
    return 1
  fi
  printf 'host prod.exemplo.com\n' >"$project/.fabrica/producao.txt"

  if [[ $xdg_ok == 1 ]]; then
    mode_config="$mode_work/config"
    mode_data="$mode_work/data"
    mkdir -p "$mode_config/opencode" "$mode_data" || {
      bad "$mode: limpeza" "não consegui criar a configuração isolada"
      return 1
    }
    serve_env=(env "XDG_CONFIG_HOME=$mode_config" "XDG_DATA_HOME=$mode_data")
    api_env=(env "XDG_CONFIG_HOME=$mode_config" "XDG_DATA_HOME=$mode_data")
  fi

  case $mode in
    projeto)
      if ! write_project_config; then
        bad "$mode: plugin" "não consegui escrever o opencode.jsonc do projeto temporário"
        return 1
      fi
      ;;
    global)
      if [[ $xdg_ok == 1 ]]; then
        if ! jq -n --arg path "$root/opencode" '{plugins: [$path]}' >"$mode_config/opencode/opencode.jsonc"; then
          bad "$mode: plugin" "não consegui escrever a configuração global isolada"
          return 1
        fi
      else
        prepare_global_write || { bad "$mode: plugin" "não consegui proteger a configuração global"; return 1; }
        if ! jq -n --arg path "$root/opencode" '{plugins: [$path]}' >"$global_cfg"; then
          bad "$mode: plugin" "não consegui escrever a configuração global"
          return 1
        fi
      fi
      ;;
    ambos)
      if ! write_project_config; then
        bad "$mode: plugin" "não consegui escrever o opencode.jsonc do projeto temporário"
        return 1
      fi
      if [[ $xdg_ok == 1 ]]; then
        if ! jq -n --arg path "$root/opencode" '{plugins: [$path]}' >"$mode_config/opencode/opencode.jsonc"; then
          bad "$mode: plugin" "não consegui escrever a configuração global isolada"
          return 1
        fi
      else
        prepare_global_write || { bad "$mode: plugin" "não consegui proteger a configuração global"; return 1; }
        if ! jq -n --arg path "$root/opencode" '{plugins: [$path]}' >"$global_cfg"; then
          bad "$mode: plugin" "não consegui escrever a configuração global"
          return 1
        fi
      fi
      ;;
  esac

  log_dir="$("${api_env[@]}" opencode debug paths 2>/dev/null | awk '$1 == "log" { print $2; exit }')"
  if [[ -z $log_dir ]]; then
    bad "$mode: log" "não encontrei a pasta do log em \`opencode debug paths\`"
    return 1
  fi
  log_file="$log_dir/opencode.log"

  # O log é cumulativo: só as linhas acrescentadas depois daqui contam.
  if [[ -f $log_file ]]; then
    log_offset="$(wc -c <"$log_file")"
  fi

  local password
  password="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  if [[ -z $password ]]; then
    bad "$mode: servidor" "não consegui gerar a senha do servidor"
    return 1
  fi
  export OPENCODE_PASSWORD="$password"

  start_server
  if ! wait_url; then
    bad "$mode: servidor" "o opencode serve não imprimiu \`server listening on\` em 30 s: $(tail -5 "$server_out" 2>/dev/null | tr '\n' ' ')"
    return 1
  fi
  ok "$mode: servidor"

  # As chamadas da API também rodam com o projeto como diretório de trabalho.
  cd "$project" || {
    bad "$mode: plugin" "não consegui entrar no projeto temporário"
    return 1
  }

  if ! new_session "$project"; then
    bad "$mode: plugin" "não criei a sessão de teste: ${session_json:-sem resposta}"
    return 1
  fi

  local probe_before
  probe_before="$(wc -c <"$server_out" 2>/dev/null || echo 0)"
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
    ok "$mode: plugin pronto"
    ok "$mode: permissão: commit"
    count="$(denial_line_count "git commit --allow-empty -m teste --no-verify" "$probe_before")"
    [[ $count == 1 ]] || denials_problem+="$mode: permissão: commit: ${count:-0} linha(s); "
  else
    bad "$mode: plugin pronto" "a sonda de negação não respondeu em 30 s (efeito: ${effect:-sem resposta})"
    bad "$mode: permissão: commit" "esperava deny, veio ${effect:-sem resposta}"
    denials_problem+="a sonda não negou; "
  fi

  check_permission "$mode: produção do projeto" '["curl https://prod.exemplo.com"]' deny
  check_permission "$mode: permissão: ~/.claude" '["echo x > ~/.claude/teste"]' deny
  check_permission "$mode: permissão: git status" '["git status"]' allow
  check_permission "$mode: permissão: linha encadeada" \
    '["git status --short", "git commit --allow-empty -m teste --no-verify"]' deny

  # Projeto B: sem .fabrica/producao.txt, o mesmo comando passa. A instância do
  # plugin da localização de B é quem avalia, então nada do projeto A vaza.
  api_location="$project_b"
  if wait_plugin && new_session "$project_b"; then
    check_permission "$mode: produção isolada" '["curl https://prod.exemplo.com"]' allow
  else
    bad "$mode: produção isolada" "não cheguei ao plugin do projeto B: ${session_json:-sem resposta}"
  fi
  api_location="$project"

  commands_json="$(api GET /api/command 2>/dev/null)" || commands_json=""
  expected_commands="fabrica:avancar fabrica:backlog fabrica:implementar fabrica:licao fabrica:metricas fabrica:prd fabrica:retro fabrica:revisar fabrica:setup fabrica:spec fabrica:status fabrica:triagem"
  got_commands="$(jq -r '.data[]? | select(.name | startswith("fabrica:")) | .name' <<<"$commands_json" 2>/dev/null | LC_ALL=C sort)"
  want_commands="$(printf '%s\n' $expected_commands | LC_ALL=C sort)"
  if [[ $got_commands == "$want_commands" ]]; then
    commands_ok=1
    ok "$mode: 12 comandos"
  else
    bad "$mode: 12 comandos" "esperava os 12 comandos: ${want_commands//$'\n'/, }; veio: ${got_commands:-nenhum}"
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
    ok "$mode: 12 skills"
  else
    bad "$mode: 12 skills" "$skills_problem"
  fi

  # A origem do plugin: a pasta de onde ele veio e o path das skills.
  plugin_problem=""
  plugin_count="$(jq -r '[.data[]? | select(.id == "fabrica")] | length' <<<"$plugins_json" 2>/dev/null)"
  status="$(jq -r '.data[]? | select(.id == "fabrica") | .state.status' <<<"$plugins_json" 2>/dev/null)"
  source_path="$(jq -r '.data[]? | select(.id == "fabrica") | .source.path // empty' <<<"$plugins_json" 2>/dev/null)"
  [[ $plugin_count == 1 ]] || plugin_problem="há $plugin_count plugins fabrica; "
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
    ok "$mode: plugin"
  else
    bad "$mode: plugin" "$plugin_problem"
  fi

  agents_json="$(api GET /api/agent 2>/dev/null)" || agents_json=""
  revisor="$(jq -r '.data[]? | select(.id == "fabrica/revisor") | .mode // empty' <<<"$agents_json" 2>/dev/null)"
  if [[ $revisor == subagent ]]; then
    ok "$mode: revisor"
  else
    bad "$mode: revisor" "esperava fabrica/revisor com mode subagent, veio: ${revisor:-ausente}"
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
  local new_log unexpected
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
    ok "$mode: log"
  else
    bad "$mode: log" "erro do plugin: $unexpected"
  fi

  # No `ambos`, a entrada global e a do projeto apontam para a mesma pasta: o
  # OpenCode tem de manter 1 plugin, os 12 comandos e uma negação por comando.
  if [[ $mode == ambos ]]; then
    local sem_duplicata=""
    [[ $plugin_count == 1 ]] || sem_duplicata+="plugins fabrica: ${plugin_count:-0}; "
    (( commands_ok )) || sem_duplicata+="os 12 comandos não batem; "
    [[ -z $denials_problem ]] || sem_duplicata+="$denials_problem"
    if [[ -z $sem_duplicata ]]; then
      ok "ambos: sem duplicata"
    else
      bad "ambos: sem duplicata" "$sem_duplicata"
    fi
  fi

  # Limpeza: o servidor e os projetos temporários não ficam para trás.
  server_old="$server_pid"
  cleaned=1
  stop_server || cleaned=0
  cd "$work" 2>/dev/null || true
  if rm -rf "$mode_work"; then
    project=""
    project_b=""
  else
    cleaned=0
  fi
  [[ -e $mode_work ]] && cleaned=0
  if [[ -n $server_old ]] && kill -0 "$server_old" 2>/dev/null; then
    cleaned=0
  fi
  if (( cleaned == 1 )); then
    ok "$mode: limpeza"
  else
    bad "$mode: limpeza" "o servidor ou os projetos temporários ficaram para trás"
  fi

  # No plano B, a configuração global volta ao que era antes do modo.
  if ! restore_global; then
    bad "$mode: config global intacta" "não consegui restaurar $global_cfg"
  fi

  return 0
}

for mode in "${modes[@]}"; do
  run_mode "$mode" || true
  stop_server || true
done

# O arquivo global do usuário não pode ter mudado em nenhum modo, no sucesso ou
# na falha. No caminho XDG, o servidor nem o leu.
cd / 2>/dev/null || true
global_after="$(global_state)"
if [[ $global_before == "$global_after" ]]; then
  ok "config global intacta"
else
  bad "config global intacta" "o opencode.jsonc global mudou: antes $global_before, depois $global_after"
fi

if (( failures > 0 )); then
  exit 1
fi
exit 0
