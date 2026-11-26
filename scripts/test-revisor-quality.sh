#!/usr/bin/env bash
# Eval sob demanda do subagente `revisor` (SPEC-230): gera um repositório git
# temporário com `origin/main`, uma branch com 3 defeitos plantados
# (`feat/1-bugs-plantados`) e uma branch de controle limpo
# (`feat/1-controle-limpo`), invoca `fabrica:revisor` via `claude -p` e confere
# os achados e vereditos esperados. Não roda no CI automático.
#
# Variáveis opcionais:
#   FABRICA_CLAUDE_BIN    Binário do Claude CLI (padrão: claude)
#   FABRICA_REVISOR_MODEL Modelo passado via `--model` ao `claude -p`
#
# Uso: bash scripts/test-revisor-quality.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/.." && pwd)"
claude_bin="${FABRICA_CLAUDE_BIN:-claude}"

if ! command -v "$claude_bin" >/dev/null 2>&1; then
  echo "ERRO: binário '$claude_bin' não encontrado no PATH." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
total=0

check() { # check <CA> <descrição> <esperado> <obtido>
  total=$((total + 1))
  if [[ "$4" == "$3" ]]; then
    printf 'ok      %-4s %s\n' "$1" "$2"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-4s %s\n        esperado: %s\n        obtido:   %s\n' "$1" "$2" "$3" "$4"
  fi
}

# --- Monta o repositório fixture temporário ---
origin_dir="$tmp/origin.git"
repo_dir="$tmp/repo"

git init --bare -q "$origin_dir"
git clone -q "$origin_dir" "$repo_dir" 2>/dev/null || {
  git init -q -b main "$repo_dir"
  git -C "$repo_dir" remote add origin "$origin_dir"
}

git -C "$repo_dir" checkout -B main -q
git -C "$repo_dir" config user.name "Fabrica Eval"
git -C "$repo_dir" config user.email "eval@fabrica.local"

mkdir -p "$repo_dir/specs" "$repo_dir/tests"
touch "$repo_dir/tests/__init__.py"

cat > "$repo_dir/Makefile" <<'EOF'
.PHONY: lint test

lint:
	python3 -m compileall -q .

test:
	python3 -m unittest discover -s tests -p "test_*.py"
EOF

cat > "$repo_dir/AGENTS.md" <<'EOF'
# AGENTS.md

- Idioma: português do Brasil para documentação e mensagens.
- Antes de concluir qualquer mudança, rode `make lint` e `make test`.
- Nunca execute comandos de sistema com `shell=True` ou interpolação de entrada do usuário.
EOF

cat > "$repo_dir/specs/SPEC-1.md" <<'EOF'
# SPEC-1: Cálculo de desconto e verificação de arquivo

**Issue:** #1 · **Status:** aprovada

## Objetivo
Implementar o módulo `app.py` com cálculo de desconto por faixa de valor e contagem segura de linhas de um arquivo.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `calcular_desconto(valor, vip=False)` aplica 10% de desconto quando `valor >= 100` (e 0% quando `valor < 100`), somando +5% de desconto adicional se `vip=True`, retornando o valor final arredondado para 2 casas decimais (`round(..., 2)`). | unitário |
| CA2 | `contar_linhas(caminho)` executa `wc -l` sem `shell=True` e sem interpolação de string em comando shell, retornando a quantidade inteira de linhas do arquivo. | unitário |
| CA3 | `tests/test_app.py` testa explicitamente os valores de limite (`valor == 100`, `valor == 99.99`, `vip=True`) e a função `contar_linhas`. | unitário |

## Fora de escopo
- Interface web ou persistência em banco de dados.
EOF

git -C "$repo_dir" add Makefile AGENTS.md specs/SPEC-1.md tests/__init__.py
git -C "$repo_dir" commit -q -m "chore: estrutura inicial do projeto"
git -C "$repo_dir" push -q -u origin main

# --- Branch 1: feat/1-bugs-plantados (3 defeitos plantados) ---
git -C "$repo_dir" checkout -q -b feat/1-bugs-plantados main

cat > "$repo_dir/app.py" <<'EOF'
import subprocess


def calcular_desconto(valor: float, vip: bool = False) -> float:
    taxa = 0.0
    if valor > 100:  # BUG 1 (lógica): deveria ser valor >= 100 conforme CA1
        taxa += 0.10
    if vip:
        taxa += 0.05
    return round(valor * (1 - taxa), 2)


def contar_linhas(caminho: str) -> int:
    # BUG 2 (segurança): execução de comando shell com interpolação e shell=True
    proc = subprocess.run(
        f"wc -l {caminho}",
        shell=True,
        check=True,
        capture_output=True,
        text=True,
    )
    return int(proc.stdout.strip().split()[0])
EOF

cat > "$repo_dir/tests/test_app.py" <<'EOF'
import tempfile
import unittest

from app import calcular_desconto, contar_linhas


class TestApp(unittest.TestCase):
    def test_desconto_acima_do_limite(self):
        self.assertEqual(calcular_desconto(200), 180.0)

    def test_desconto_limite_100(self):
        # BUG 3 (teste enfraquecido): não valida o valor esperado (90.0)
        resultado = calcular_desconto(100)
        self.assertIsNotNone(resultado)

    def test_desconto_abaixo_do_limite(self):
        self.assertEqual(calcular_desconto(99.99), 99.99)

    def test_desconto_vip(self):
        self.assertEqual(calcular_desconto(200, vip=True), 170.0)

    def test_contar_linhas(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("a\nb\nc\n")
            caminho = f.name
        self.assertEqual(contar_linhas(caminho), 3)


if __name__ == "__main__":
    unittest.main()
EOF

git -C "$repo_dir" add app.py tests/test_app.py
git -C "$repo_dir" commit -q -m "feat: implementa calculo de desconto e contagem de linhas"
git -C "$repo_dir" push -q -u origin feat/1-bugs-plantados

# --- Branch 2: feat/1-controle-limpo (implementação correta e testes reais) ---
git -C "$repo_dir" checkout -q -b feat/1-controle-limpo main

cat > "$repo_dir/app.py" <<'EOF'
import subprocess


def calcular_desconto(valor: float, vip: bool = False) -> float:
    taxa = 0.0
    if valor >= 100:
        taxa += 0.10
    if vip:
        taxa += 0.05
    return round(valor * (1 - taxa), 2)


def contar_linhas(caminho: str) -> int:
    proc = subprocess.run(
        ["wc", "-l", caminho],
        shell=False,
        check=True,
        capture_output=True,
        text=True,
    )
    return int(proc.stdout.strip().split()[0])
EOF

cat > "$repo_dir/tests/test_app.py" <<'EOF'
import tempfile
import unittest

from app import calcular_desconto, contar_linhas


class TestApp(unittest.TestCase):
    def test_desconto_limite_100(self):
        self.assertEqual(calcular_desconto(100), 90.0)

    def test_desconto_abaixo_do_limite(self):
        self.assertEqual(calcular_desconto(99.99), 99.99)

    def test_desconto_vip_no_limite(self):
        self.assertEqual(calcular_desconto(100, vip=True), 85.0)

    def test_contar_linhas(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("a\nb\nc\n")
            caminho = f.name
        self.assertEqual(contar_linhas(caminho), 3)


if __name__ == "__main__":
    unittest.main()
EOF

git -C "$repo_dir" add app.py tests/test_app.py
git -C "$repo_dir" commit -q -m "feat: implementa calculo de desconto e contagem de linhas"
git -C "$repo_dir" push -q -u origin feat/1-controle-limpo

git -C "$repo_dir" checkout -q main

wt_bugs="$tmp/wt-bugs"
wt_clean="$tmp/wt-clean"
git -C "$repo_dir" worktree add -q "$wt_bugs" feat/1-bugs-plantados
git -C "$repo_dir" worktree add -q "$wt_clean" feat/1-controle-limpo

check CA1 "fixture criada com origin/main, spec, Makefile e duas branches" "ok" "$(
  if git -C "$repo_dir" rev-parse --verify origin/main >/dev/null 2>&1 \
     && git -C "$repo_dir" rev-parse --verify feat/1-bugs-plantados >/dev/null 2>&1 \
     && git -C "$repo_dir" rev-parse --verify feat/1-controle-limpo >/dev/null 2>&1 \
     && [[ -f "$wt_bugs/specs/SPEC-1.md" && -f "$wt_bugs/Makefile" ]]; then
    echo ok
  else
    echo erro
  fi
)"

run_revisor() { # run_revisor <wt> <branch> <arquivo_saida>
  local wt="$1" branch="$2" out_file="$3"
  local prompt
  local -a cmd=(
    env -u CLAUDECODE "$claude_bin" -p
    --plugin-dir "$root"
    --agent fabrica:revisor
    --permission-mode bypassPermissions
    --output-format text
  )
  if [[ -n "${FABRICA_REVISOR_MODEL:-}" ]]; then
    cmd+=(--model "$FABRICA_REVISOR_MODEL")
  fi

  prompt="Revise localmente a branch '$branch' da issue #1 na worktree '$wt'.
A spec aprovada está em '$wt/specs/SPEC-1.md'.
Este é um repositório git local de teste sem remote no GitHub: não execute 'gh issue view'.
Leia a spec, o AGENTS.md e o diff contra origin/main na worktree '$wt', rode 'make lint' e 'make test' dentro de '$wt', e responda estritamente no formato padrão do revisor (## Verificações, ## Critérios de aceite, ## Não encontrado, ## Achados, ## Veredito)."

  "${cmd[@]}" "$prompt" > "$out_file" 2>&1
}

eval_output() { # eval_output <modo: bugs|clean> <arquivo_saida>
  python3 - "$1" "$2" <<'PY'
import re
import sys

mode = sys.argv[1]
path = sys.argv[2]
text = open(path, encoding="utf-8", errors="replace").read()

def extract_section(name: str) -> str:
    pattern = rf"(?ims)^##\s+{re.escape(name)}\b.*?\n(.*?)(?=^##\s+|\Z)"
    m = re.search(pattern, text)
    return m.group(1).strip() if m else ""

achados = extract_section("Achados")
veredito = extract_section("Veredito")

# Divide os achados em itens numerados ou com marcador; fallback para linhas não vazias.
items = re.split(r"(?m)(?=^\s*(?:\d+\.|[-*])\s+)", achados)
items = [it.strip() for it in items if it.strip()]

def has_file_line(item: str, filename_pattern: str) -> bool:
    return bool(
        re.search(rf"{filename_pattern}[^\n]*?:\s*\d+", item, re.I)
        or re.search(rf"{filename_pattern}\s*(?:\(|na\s+)?linha\s*\d+", item, re.I)
    )

if mode == "bugs":
    veredito_ok = bool(re.search(r"corrigir\s+antes\s+do\s+pr", veredito, re.I)) and not bool(
        re.search(r"^\s*aprovar\b", veredito, re.I)
    )
    logic_ok = any(
        re.search(r"\bbloqueante\b", it, re.I)
        and has_file_line(it, r"app\.py")
        and re.search(r"(desconto|100|>=|>|l[oó]gica|limite|ca1)", it, re.I)
        for it in items
    )
    sec_ok = any(
        re.search(r"\bbloqueante\b", it, re.I)
        and has_file_line(it, r"app\.py")
        and re.search(r"(shell\s*=\s*true|shell|seguran[cç]a|inje[cç][aã]o|interpola[cç][aã]o|command)", it, re.I)
        for it in items
    )
    test_ok = any(
        re.search(r"\b(bloqueante|importante)\b", it, re.I)
        and has_file_line(it, r"(?:tests/)?test_app\.py")
        and re.search(r"(teste|enfraquecido|asser[cç][aã]o|assertisnotnull|cobertura|90|ca1|ca3)", it, re.I)
        for it in items
    )
    print(f"veredito={'ok' if veredito_ok else 'erro'}")
    print(f"logic={'ok' if logic_ok else 'erro'}")
    print(f"security={'ok' if sec_ok else 'erro'}")
    print(f"weak_test={'ok' if test_ok else 'erro'}")
elif mode == "clean":
    veredito_ok = bool(re.search(r"\baprovar\b", veredito, re.I)) and not bool(
        re.search(r"corrigir\s+antes\s+do\s+pr", veredito, re.I)
    )
    has_bad = bool(re.search(r"\b(bloqueante|importante)\b", achados, re.I))
    print(f"veredito={'ok' if veredito_ok else 'erro'}")
    print(f"no_bad_findings={'ok' if not has_bad else 'erro'}")
PY
}

# --- Executa contra feat/1-bugs-plantados (CA2) ---
out_bugs="$tmp/revisor-bugs.txt"
run_revisor "$wt_bugs" "feat/1-bugs-plantados" "$out_bugs"
rc_bugs=$?
check CA2 "revisor executou sem erro na branch com defeitos" "0" "$rc_bugs"

bugs_parsed="$(eval_output bugs "$out_bugs")"
get_field() { grep "^$1=" <<<"$2" | cut -d= -f2; }

check CA2 "bugs: veredito não aprova (corrigir antes do PR)" "ok" "$(get_field veredito "$bugs_parsed")"
check CA2 "bugs: bug de lógica detectado como bloqueante com app.py:linha" "ok" "$(get_field logic "$bugs_parsed")"
check CA2 "bugs: falha de segurança detectada como bloqueante com app.py:linha" "ok" "$(get_field security "$bugs_parsed")"
check CA2 "bugs: teste enfraquecido detectado (bloqueante/importante) com test_app.py:linha" "ok" "$(get_field weak_test "$bugs_parsed")"

if [[ "$failures" -gt 0 ]]; then
  echo "--- Saída do revisor (feat/1-bugs-plantados) ---" >&2
  cat "$out_bugs" >&2
  echo "------------------------------------------------" >&2
fi

# --- Executa contra feat/1-controle-limpo (CA3) ---
out_clean="$tmp/revisor-clean.txt"
run_revisor "$wt_clean" "feat/1-controle-limpo" "$out_clean"
rc_clean=$?
check CA3 "revisor executou sem erro na branch de controle limpo" "0" "$rc_clean"

clean_parsed="$(eval_output clean "$out_clean")"
check CA3 "limpo: veredito aprova" "ok" "$(get_field veredito "$clean_parsed")"
check CA3 "limpo: sem achados bloqueante nem importante" "ok" "$(get_field no_bad_findings "$clean_parsed")"

if [[ "$failures" -gt 0 ]]; then
  echo "--- Saída do revisor (feat/1-controle-limpo) ---" >&2
  cat "$out_clean" >&2
  echo "-----------------------------------------------" >&2
fi

echo
echo "Resumo: $((total - failures))/$total verificações passaram ($failures falhas)."
[[ "$failures" -eq 0 ]]
