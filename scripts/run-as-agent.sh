#!/usr/bin/env bash
# Roda o `claude` como o usuário sem rede direta do job do dispatcher
# (SPEC-106, ADR 0016). É o valor do FABRICA_CLAUDE_BIN do workflow: o
# stage-model.sh chama este script no lugar do `claude`.
#
# O agente recebe um ambiente de lista fechada: o PATH do chamador, o HOME dele
# e as linhas do agent.env que o `job-isolation.sh lock` gravou (marcadores no
# lugar dos tokens e o caminho do proxy). Nenhuma variável do runner passa.
# Argumentos, saída padrão e código de saída são os do `claude`.
#
# Variáveis: FABRICA_ISOLATION_DIR, FABRICA_AGENT_USER, FABRICA_AGENT_HOME,
# FABRICA_PLUGIN_COPY, FABRICA_REAL_CLAUDE_BIN, FABRICA_SUDO_BIN.
set -uo pipefail
export LC_ALL=C.UTF-8

dir="${FABRICA_ISOLATION_DIR:-/etc/fabrica}"
agent_user="${FABRICA_AGENT_USER:-fabrica-agent}"
agent_home="${FABRICA_AGENT_HOME:-/home/$agent_user}"
plugin_copy="${FABRICA_PLUGIN_COPY:-/opt/fabrica-plugin}"
env_file="$dir/agent.env"

[[ -r "$env_file" ]] || { echo "run-as-agent: não achei $env_file; rode o job-isolation.sh lock antes." >&2; exit 1; }
claude_bin="${FABRICA_REAL_CLAUDE_BIN:-$(command -v claude)}"
[[ -n "$claude_bin" ]] || { echo "run-as-agent: não achei o claude no PATH." >&2; exit 1; }

env_args=("PATH=$PATH" "HOME=$agent_home" "LANG=C.UTF-8")
while IFS= read -r line; do
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && env_args+=("$line")
done < "$env_file"

args=("$@")
has_plugin_dir=false
for arg in "$@"; do
  [[ "$arg" == "--plugin-dir" ]] && has_plugin_dir=true
done
$has_plugin_dir || args=(--plugin-dir "$plugin_copy" "${args[@]}")

exec "${FABRICA_SUDO_BIN:-sudo}" -n -u "$agent_user" -H env -i "${env_args[@]}" "$claude_bin" "${args[@]}"
