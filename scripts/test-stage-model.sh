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
run() { env -u PROXY_CA_CERT_B64 -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID HOME="$tmp/home" FABRICA_SBX_PERSISTENT_FILE="$tmp/ausente.sh" FABRICA_CLAUDE_BIN="$fake" bash "$script" run "$@" 2>/dev/null; }
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
mkdir -p "$installed/scripts" "$installed/skills/avancar"
cp "$script" "$installed/scripts/stage-model.sh"
cp "$script_dir/harness.sh" "$installed/scripts/harness.sh"
cp "$script_dir/../skills/avancar/modelos.md" "$installed/skills/avancar/modelos.md"
rm -f "$args_file"
env -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID HOME="$tmp/home" \
  FABRICA_CLAUDE_BIN="$fake" bash "$installed/scripts/stage-model.sh" run triagem 12 >/dev/null 2>&1
check CA6 "de dentro de ~/.claude/plugins/ não leva --plugin-dir" "no" \
  "$(grep -qx -- '--plugin-dir' "$args_file" && echo yes || echo no)"

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
cp "$script" "$broken/scripts/stage-model.sh"
cp "$script_dir/harness.sh" "$broken/scripts/harness.sh"
cp "$script_dir/../skills/avancar/modelos.md" "$broken/skills/avancar/modelos.md"
run_broken() { (cd "$proj" && env -u PROXY_CA_CERT_B64 -u CLAUDECODE -u FABRICA_HARNESS -u OPENCODE_SESSION_ID HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$broken/scripts/stage-model.sh" run triagem 12 >/dev/null 2>&1); }
printf '#!/usr/bin/env bash\nexit 3\n' > "$broken/scripts/sbx-context.sh"
printf '#!/usr/bin/env bash\necho sbx\n' > "$broken/scripts/setup-isolation.sh"
rm -f "$args_file"; run_broken
check CA13 "sbx-context.sh falhando usa auto" "auto" "$(perm_mode)"
printf '#!/usr/bin/env bash\necho "onde vm"\n' > "$broken/scripts/sbx-context.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$broken/scripts/setup-isolation.sh"
rm -f "$args_file"; run_broken
check CA13 "setup-isolation.sh falhando usa auto" "auto" "$(perm_mode)"

# CA1/CA2/CA3 (SPEC-218): tradução para tiers do Antigravity via agy-tier.
agy_tier() { bash "$script" agy-tier "$@" 2>/dev/null; }
agy_tier_code() { bash "$script" agy-tier "$@" >/dev/null 2>&1; echo $?; }
check CA2 "agy-tier triagem usa flash" "flash" "$(agy_tier triagem)"
check CA2 "agy-tier triagem ignora label" "flash" "$(agy_tier triagem modelo:opus)"
check CA2 "agy-tier spec usa pro" "pro" "$(agy_tier spec)"
check CA2 "agy-tier spec ignora label" "pro" "$(agy_tier spec modelo:haiku)"
check CA2 "agy-tier implementar sem label usa flash" "flash" "$(agy_tier implementar)"
check CA2 "agy-tier implementar modelo:haiku usa flash_lite" "flash_lite" "$(agy_tier implementar modelo:haiku)"
check CA2 "agy-tier implementar modelo:opus usa pro" "pro" "$(agy_tier implementar modelo:opus)"
check CA2 "agy-tier revisar sem label usa flash" "flash" "$(agy_tier revisar)"
check CA2 "agy-tier revisar modelo:haiku usa flash" "flash" "$(agy_tier revisar modelo:haiku)"
check CA2 "agy-tier revisar modelo:opus usa pro" "pro" "$(agy_tier revisar modelo:opus)"
check CA3 "agy-tier duas labels modelo:* sai com código 2" "2" "$(agy_tier_code implementar modelo:haiku modelo:opus)"
check CA3 "agy-tier etapa desconhecida sai com código 1" "1" "$(agy_tier_code desconhecida)"
check CA3 "agy-tier label desconhecida sai com código 1" "1" "$(agy_tier_code implementar modelo:invalido)"
check CA3 "agy-tier sem argumentos sai com código 1" "1" "$(agy_tier_code)"

echo
echo "$((total - failures)) de $total passaram."
[[ $failures -eq 0 ]]
