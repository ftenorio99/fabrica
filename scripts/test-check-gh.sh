#!/usr/bin/env bash
# Testes do scripts/check-gh.sh (SPEC-39), com um gh falso no PATH. Não usa o
# gh da máquina nem a rede.
# Uso: scripts/test-check-gh.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
script="$script_dir/check-gh.sh"
bash_bin="$(command -v bash)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

min="$(sed -nE 's/^MIN_GH_VERSION="([^"]+)"$/\1/p' "$script")"

# O gh falso responde --version com FAKE_GH_VERSION e auth status com
# FAKE_GH_AUTH (0 = autenticado). Cada chamada fica registrada em calls.log.
mkdir -p "$tmp/fake" "$tmp/nogh"
cat > "$tmp/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
case "$1" in
  --version) printf '%s\n' "$FAKE_GH_VERSION"; echo "https://github.com/cli/cli/releases/latest" ;;
  auth) exit "${FAKE_GH_AUTH:-0}" ;;
esac
EOF
chmod +x "$tmp/fake/gh"
# PATH sem gh, com só o que o script usa.
for tool in head env; do ln -s "$(command -v "$tool")" "$tmp/nogh/$tool"; done

# run <linha do --version> <auth>: imprime "<saída>|<código>".
run() {
  : > "$tmp/calls.log"
  local out code
  out="$(FAKE_GH_LOG="$tmp/calls.log" FAKE_GH_VERSION="$1" FAKE_GH_AUTH="$2" PATH="$tmp/fake:$PATH" "$bash_bin" "$script")"
  code=$?
  echo "$out|$code"
}

check CA6 "a mínima é lida do script" "2.82.1" "$min"

check CA1 "2.46.0: desatualizado, código 1" "desatualizado 2.46.0 $min|1" "$(run 'gh version 2.46.0 (2024-04-01)' 0)"
check CA1 "desatualizado: não chama gh auth status" 0 "$(grep -c '^auth' "$tmp/calls.log")"

check CA2 "na mínima: ok" "ok $min|0" "$(run "gh version $min (2025-10-22)" 0)"
check CA2 "2.103.3: ok" "ok 2.103.3|0" "$(run 'gh version 2.103.3 (2026-10-26)' 0)"
check CA2 "ok: confere o login" 1 "$(grep -c '^auth status' "$tmp/calls.log")"
check CA2 "2.9.0: comparação numérica" "desatualizado 2.9.0 $min|1" "$(run 'gh version 2.9.0 (2022-04-26)' 0)"
check CA2 "2.82.0: logo abaixo da mínima" "desatualizado 2.82.0 $min|1" "$(run 'gh version 2.82.0 (2025-10-15)' 0)"

check CA3 "sem login" "sem-login 2.103.3|1" "$(run 'gh version 2.103.3 (2026-10-26)' 1)"
check CA3 "versão ilegível" "desatualizado desconhecida $min|1" "$(run 'gh dev' 0)"
out="$(PATH="$tmp/nogh" "$bash_bin" "$script")"
check CA3 "sem gh no PATH: ausente, código 1" "ausente|1" "$out|$?"

# CA4 e CA5: as etapas que escrevem no GitHub rodam a checagem e citam o gh.md.
for stage in triagem spec implementar revisar backlog prd; do
  file="$root/skills/$stage/SKILL.md"
  check CA4 "$stage roda o check-gh.sh" 1 "$(grep -c 'scripts/check-gh.sh' "$file" | awk '{print ($1 > 0)}')"
  check CA5 "$stage cita o setup/gh.md" 1 "$(grep -c '\.\./setup/gh\.md' "$file" | awk '{print ($1 > 0)}')"
done
check CA5 "o gh.md descreve o plano B" 1 "$(grep -c 'gh api -X PATCH' "$root/skills/setup/gh.md" | awk '{print ($1 > 0)}')"

# CA6: a versão mínima aparece num único arquivo do plugin.
found="$(cd "$root" && grep -rlF "$min" --exclude-dir=.git --exclude-dir=specs --exclude=test-check-gh.sh . | sort)"
check CA6 "a mínima só existe no check-gh.sh" "./scripts/check-gh.sh" "$found"

echo
if ((failures)); then
  echo "$failures de $total falharam"
  exit 1
fi
echo "$total/$total ok"
