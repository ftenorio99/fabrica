#!/usr/bin/env bash
# Testa scripts/stage-model.sh (SPEC-179, CA2 a CA6) com um `claude` falso.
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
run() { HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$script" run "$@" 2>/dev/null; }
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
HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$script" run triagem '12; rm' >/dev/null 2>&1
check CA5 "número com texto sai com código 1" "1" "$(HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$script" run triagem '12; rm' >/dev/null 2>&1; echo $?)"
check CA5 "número inválido não chama o binário" "no" "$([[ -e "$args_file" ]] && echo yes || echo no)"
check CA5 "número zero sai com código 1" "1" "$(HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$script" run triagem 0 >/dev/null 2>&1; echo $?)"
check CA5 "labels inconsistentes saem com código 2" "2" \
  "$(HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$script" run implementar 12 modelo:haiku modelo:opus >/dev/null 2>&1; echo $?)"

# CA6: --plugin-dir só quando o plugin roda de um clone.
clone_root="$(cd "$script_dir/.." && pwd -P)"
rm -f "$args_file"
run triagem 12 >/dev/null
check CA6 "fora de ~/.claude/plugins/ leva --plugin-dir do clone" "yes" \
  "$(grep -qx -- "$clone_root" "$args_file" && grep -qx -- '--plugin-dir' "$args_file" && echo yes || echo no)"

installed="$tmp/home/.claude/plugins/cache/fabrica/fabrica/9.9.9"
mkdir -p "$installed/scripts" "$installed/skills/avancar"
cp "$script" "$installed/scripts/stage-model.sh"
cp "$script_dir/../skills/avancar/modelos.md" "$installed/skills/avancar/modelos.md"
rm -f "$args_file"
HOME="$tmp/home" FABRICA_CLAUDE_BIN="$fake" bash "$installed/scripts/stage-model.sh" run triagem 12 >/dev/null 2>&1
check CA6 "de dentro de ~/.claude/plugins/ não leva --plugin-dir" "no" \
  "$(grep -qx -- '--plugin-dir' "$args_file" && echo yes || echo no)"

echo
echo "$((total - failures)) de $total passaram."
[[ $failures -eq 0 ]]
