#!/usr/bin/env bash
# Testes das regras comuns das etapas (SPEC-140): cada regra está escrita só em
# skills/etapas/regras.md, e as skills de etapa remetem a ele antes do primeiro
# passo. Só lê arquivos do repositório.
# Uso: bash scripts/test-regras-etapas.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
rules="$root/skills/etapas/regras.md"
agents_md="$root/AGENTS.md"

failures=0 total=0
check() { # check <CA> <descrição> <esperado> <obtido>
  total=$((total + 1))
  if [[ "$4" == "$3" ]]; then
    printf 'ok      %-4s %s\n' "$1" "$2"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3" "$4"
  fi
}
yesno() { if "$@"; then echo sim; else echo não; fi; }
# count <texto> <arquivo>: quantas vezes o texto literal aparece no arquivo.
count() { grep -oF -- "$1" "$2" 2>/dev/null | wc -l | tr -d ' '; }

# Uma frase que identifica cada uma das cinco regras.
anchors=(
  "Publique todo corpo de issue"
  "use o plano B de"
  "Não crie a label sozinho"
  "Os comentários do agente e do usuário saem da mesma conta"
  "--stage <etapa>"
)
# Trecho da regra da linha de custo que não depende do nome da etapa: pega uma
# cópia escrita com o nome no lugar de <etapa>.
copy_only_anchors=("O script nunca falha")

# Regras que se aplicam a cada skill de etapa.
all="corpo por arquivo; plano B; label inexistente; marcador; linha de custo"
declare -A applies=(
  [backlog]="corpo por arquivo; plano B"
  [triagem]="$all"
  [spec]="$all"
  [implementar]="$all"
  [revisar]="$all"
  [retro]="corpo por arquivo"
  [lancamento]="corpo por arquivo; plano B; marcador; linha de custo"
)
stages=(backlog triagem spec implementar revisar retro lancamento)

# --- CA1: o arquivo comum ---
check CA1 "skills/etapas/regras.md existe" sim "$(yesno test -f "$rules")"
check CA1 "skills/etapas/ não tem SKILL.md" não "$(yesno test -e "$root/skills/etapas/SKILL.md")"
for anchor in "${anchors[@]}"; do
  check CA1 "regras.md tem uma vez: $anchor" 1 "$(count "$anchor" "$rules")"
done

for stage in "${stages[@]}"; do
  skill="$root/skills/$stage/SKILL.md"

  # --- CA2: nenhuma skill repete uma regra ---
  for anchor in "${anchors[@]}" "${copy_only_anchors[@]}"; do
    check CA2 "$stage não repete: $anchor" 0 "$(count "$anchor" "$skill")"
  done

  # --- CA3: a remissão vem antes do primeiro passo e o caminho resolve ---
  intro="$(awk '/^## 1\. / { found = 1; exit } { print } END { if (!found) exit 1 }' "$skill")"
  check CA3 "$stage tem o primeiro passo" 0 "$?"
  expected="**Regras comuns:** antes de seguir, leia [../etapas/regras.md](../etapas/regras.md) e aplique as regras dele com \`<etapa>\` = \`$stage\`: ${applies[$stage]}."
  check CA3 "$stage remete antes do primeiro passo, com as regras dele" sim \
    "$(yesno grep -qxF -- "$expected" <<<"$intro")"
  check CA3 "$stage: o caminho da remissão resolve" sim \
    "$(yesno test "$(realpath -q "$root/skills/$stage/../etapas/regras.md")" -ef "$rules")"
done

# Cada nome citado nas remissões é uma seção do arquivo comum.
IFS=';' read -ra names <<<"$all"
for name in "${names[@]}"; do
  name="${name# }"
  check CA3 "regras.md tem a seção: $name" 1 "$(grep -icxF -- "## $name" "$rules" 2>/dev/null)"
done

# --- CA8: AGENTS.md ---
check CA8 "AGENTS.md cita skills/etapas/regras.md" sim \
  "$(yesno grep -qF 'skills/etapas/regras.md' "$agents_md")"
check CA8 "AGENTS.md cita o teste" sim \
  "$(yesno grep -qF 'bash scripts/test-regras-etapas.sh' "$agents_md")"
writing="$(awk '/^## Escrevendo skills/ { inside = 1; next } /^## / { inside = 0 } inside' "$agents_md")"
check CA8 "\"Escrevendo skills\" manda a regra comum para o arquivo comum" sim \
  "$(yesno grep -qF 'skills/etapas/regras.md' <<<"$writing")"

printf '\n%d casos, %d falhas\n' "$total" "$failures"
[[ "$failures" -eq 0 ]]
