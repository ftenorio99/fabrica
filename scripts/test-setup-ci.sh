#!/usr/bin/env bash
# Testa o modelo templates/workflows/ci.yml e o scripts/setup-ci.sh
# (SPEC-128, CA1, CA2, CA3 e CA7 a CA10) em pastas e repositórios git
# temporários.
# Uso: bash scripts/test-setup-ci.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$script_dir/setup-ci.sh"
model="$script_dir/../templates/workflows/ci.yml"

python3 -c 'import yaml' 2>/dev/null || { echo "test-setup-ci: falta o PyYAML (pip install pyyaml ou apt install python3-yaml)." >&2; exit 1; }

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

# wf <expressão python sobre w (o YAML), jobs, steps(job) e step(job, nome)>
wf() {
  python3 -I -c '
import re, sys, yaml
w = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
jobs = w["jobs"]
def steps(job):
    return jobs[job]["steps"]
def step(job, name):
    return next(s for s in steps(job) if s.get("name") == name)
def idx(job, pred):
    return next(i for i, s in enumerate(steps(job)) if pred(s))
print(eval(sys.argv[2]))
' "$model" "$1"
}

# --- Modelo ---
# CA1: YAML válido, gatilhos, permissões, concorrência e nenhum secret.
check CA1 "o modelo é YAML válido" "dict" "$(wf 'type(w).__name__')"
check CA1 "dispara em pull_request e push" "['pull_request', 'push']" "$(wf 'sorted(w[True].keys())')"
check CA1 "o push é só na main" "{'branches': ['main']}" "$(wf 'w[True]["push"]')"
check CA1 "permissões exatas: só contents: read" "{'contents': 'read'}" "$(wf 'w["permissions"]')"
check CA1 "nenhum job amplia as permissões" "[]" "$(wf '[j for j in jobs if "permissions" in jobs[j]]')"
check CA1 "concurrency cancela a execução em curso" "True" "$(wf 'w["concurrency"]["cancel-in-progress"]')"
check CA1 "o grupo usa o número do PR ou a ref" "True" "$(wf '"github.event.pull_request.number" in w["concurrency"]["group"] and "github.ref" in w["concurrency"]["group"]')"
check CA1 "o arquivo não cita secrets." "0" "$(grep -c 'secrets\.' "$model")"

# CA2: toda ação fixada por SHA de 40 caracteres e comentário de versão.
uses_lines="$(grep -E '^[[:space:]]*(-[[:space:]]+)?uses:' "$model")"
check CA2 "o modelo usa ações" "True" "$([[ -n "$uses_lines" ]] && echo True || echo False)"
check CA2 "toda ação tem SHA de 40 hex e comentário # v<versão>" "" \
  "$(grep -vE 'uses:[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]+v[0-9]+(\.[0-9]+)*$' <<<"$uses_lines")"
check CA2 "o YAML lido traz só refs por SHA" "True" \
  "$(wf 'all(re.fullmatch(r"[0-9a-f]{40}", s["uses"].split("@")[1]) for j in jobs for s in steps(j) if "uses" in s)')"

# CA3: ordem dos comandos e condições dos passos.
check CA3 "dois jobs: verificacao e e2e" "['e2e', 'verificacao']" "$(wf 'sorted(jobs)')"
check CA3 "os jobs rodam em paralelo (sem needs)" "[]" "$(wf '[j for j in jobs if "needs" in jobs[j]]')"
check CA3 "verificacao roda make lint e depois make test" "['make lint', 'make test']" \
  "$(wf '[s["run"].strip() for s in steps("verificacao") if s.get("run", "").strip().startswith("make ")]')"
check CA3 "o job e2e roda make e2e" "True" "$(wf 'any(s.get("run", "").strip() == "make e2e" for s in steps("e2e"))')"
check CA3 "a conferência do alvo vem antes do make e2e" "True" \
  "$(wf 'idx("e2e", lambda s: s.get("id") == "alvo") < idx("e2e", lambda s: s.get("run", "").strip() == "make e2e")')"
check CA3 "o make e2e só roda com o alvo" "steps.alvo.outputs.tem == 'sim'" "$(wf 'step("e2e", "Roda o make e2e")["if"]')"
check CA3 "a instalação do Playwright só roda com o alvo" "True" \
  "$(wf 'all("steps.alvo.outputs.tem == '"'"'sim'"'"'" in s.get("if", "") for s in steps("e2e") if "playwright" in s.get("run", "") or "cache" in s.get("uses", ""))')"
check CA3 "o relatório sobe só em falha" "failure()" \
  "$(wf 'next(s for s in steps("e2e") if "upload-artifact" in s.get("uses", ""))["if"]')"
check CA3 "o artefato é playwright-report, de playwright-report/, por 7 dias" "playwright-report playwright-report/ 7" \
  "$(wf '" ".join(str(next(s for s in steps("e2e") if "upload-artifact" in s.get("uses", ""))["with"][k]) for k in ("name", "path", "retention-days"))')"
check CA3 "o upload é o último passo do e2e" "True" "$(wf '"upload-artifact" in steps("e2e")[-1].get("uses", "")')"
check CA3 "o job e2e não roda lint nem test" "[]" \
  "$(wf '[s["run"] for s in steps("e2e") if s.get("run", "").strip() in ("make lint", "make test")]')"

# Passo sem alvo: imprime a linha e não grava tem=sim.
alvo_script="$tmp/alvo.sh"
wf 'step("e2e", "Confere o alvo e2e")["run"]' > "$alvo_script"
d="$tmp/sem-alvo" && mkdir -p "$d" && printf 'test:\n\techo t\n' > "$d/Makefile"
out="$(cd "$d" && GITHUB_OUTPUT="$tmp/gho-sem" bash "$alvo_script")"
check CA3 "sem e2e: imprime a linha do nada a rodar" "ci: o Makefile não tem o alvo e2e; nada a rodar" "$out"
check CA3 "sem e2e: a saída do passo é tem=nao" "tem=nao" "$(cat "$tmp/gho-sem")"
d="$tmp/com-alvo" && mkdir -p "$d" && printf 'e2e: db-up\n\tnpx playwright test\n' > "$d/Makefile"
out="$(cd "$d" && GITHUB_OUTPUT="$tmp/gho-com" bash "$alvo_script")"
check CA3 "com e2e: o passo não imprime nada" "" "$out"
check CA3 "com e2e: a saída do passo é tem=sim" "tem=sim" "$(cat "$tmp/gho-com")"

# CA7: o passo de instalação e o do .env, extraídos do YAML.
check CA7 "o passo de instalação é igual nos dois jobs" "True" \
  "$(wf 'step("verificacao", "Instala as dependências")["run"] == step("e2e", "Instala as dependências")["run"]')"
check CA7 "o passo do .env é igual nos dois jobs" "True" \
  "$(wf 'step("verificacao", "Cria o .env de teste")["run"] == step("e2e", "Cria o .env de teste")["run"]')"
install_script="$tmp/install.sh" env_script="$tmp/env.sh"
wf 'step("verificacao", "Instala as dependências")["run"]' > "$install_script"
wf 'step("verificacao", "Cria o .env de teste")["run"]' > "$env_script"

# pnpm, npm e make falsos, que registram a chamada.
bin="$tmp/bin" && mkdir -p "$bin"
for c in pnpm npm make; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$CALLS"\n' "$c" > "$bin/$c"
  chmod +x "$bin/$c"
done

# install_case <descrição> <esperado> <arquivos...>: cria uma pasta com os
# arquivos (Makefile:install grava um Makefile com o alvo install) e roda o passo.
n=0
install_case() {
  local desc="$1" expected="$2"; shift 2
  n=$((n + 1))
  local d="$tmp/inst$n"; mkdir -p "$d"
  for f in "$@"; do
    case $f in
      Makefile:install) printf 'install:\n\techo i\n' > "$d/Makefile" ;;
      Makefile:sem) printf 'test:\n\techo t\n' > "$d/Makefile" ;;
      *) echo '{}' > "$d/$f" ;;
    esac
  done
  local out
  out="$(cd "$d" && CALLS="$d/.calls" PATH="$bin:$PATH" bash "$install_script")"
  check CA7 "$desc" "$expected" "$( [[ -f "$d/.calls" ]] && cat "$d/.calls"; echo -n "$out")"
}
install_case "pnpm-lock.yaml vence todos" "pnpm install --frozen-lockfile" pnpm-lock.yaml package-lock.json Makefile:install
install_case "package-lock.json vence o make install" "npm ci" package-lock.json Makefile:install
install_case "só o alvo install roda make install" "make install" Makefile:install
install_case "Makefile sem install imprime o aviso" "ci: sem lockfile nem alvo install; dependências não instaladas" Makefile:sem
install_case "pasta vazia imprime o aviso" "ci: sem lockfile nem alvo install; dependências não instaladas"

d="$tmp/env1" && mkdir -p "$d" && echo 'DATABASE_URL=postgres://local' > "$d/.env.example"
(cd "$d" && bash "$env_script")
check CA7 "sem .env, copia o .env.example" "DATABASE_URL=postgres://local" "$(cat "$d/.env" 2>/dev/null)"
d="$tmp/env2" && mkdir -p "$d" && echo 'A=exemplo' > "$d/.env.example" && echo 'A=proprio' > "$d/.env"
(cd "$d" && bash "$env_script")
check CA7 "com .env, não o troca" "A=proprio" "$(cat "$d/.env")"
d="$tmp/env3" && mkdir -p "$d"
(cd "$d" && bash "$env_script"); rc=$?
check CA7 "sem .env.example, não cria .env e não falha" "False 0" "$([[ -e "$d/.env" ]] && echo True || echo False) $rc"

# --- setup-ci.sh ---
# new_repo <nome>: repositório git com um commit; imprime a pasta.
new_repo() {
  local r="$tmp/$1"
  git init -q -b teste "$r"
  echo "# teste" > "$r/README.md"
  git -C "$r" add README.md
  git -C "$r" -c user.name=teste -c user.email=teste@exemplo.com commit -q -m inicial
  echo "$r"
}

# run <pasta> <args...>: roda o script na pasta; $out, $err e $rc.
run() {
  local d="$1"; shift
  out="$(cd "$d" && bash "$setup" "$@" 2>"$tmp/err")"; rc=$?
  err="$(cat "$tmp/err")"
}

# python3 falso sem PyYAML, para o caminho do grep.
nobin="$tmp/noyaml" && mkdir -p "$nobin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$nobin/python3" && chmod +x "$nobin/python3"
run_noyaml() {
  local d="$1"; shift
  out="$(cd "$d" && PATH="$nobin:$PATH" bash "$setup" "$@" 2>"$tmp/err")"; rc=$?
  err="$(cat "$tmp/err")"
}

# both <CA> <descrição> <esperado> <pasta>: confere o --check com e sem PyYAML.
both() {
  run "$4" --check
  check "$1" "$2 (PyYAML)" "$3" "$out $rc"
  run_noyaml "$4" --check
  check "$1" "$2 (grep)" "$3" "$out $rc"
}

snapshot() { (cd "$1" && git status --porcelain --untracked-files=all && git rev-parse HEAD); }

# write_wf <repo> <arquivo> <conteúdo>
write_wf() { mkdir -p "$1/.github/workflows" && printf '%s\n' "$3" > "$1/.github/workflows/$2"; }

# CA8: ausente.
r="$(new_repo ca8)"
before="$(snapshot "$r")"
both CA8 "sem .github/workflows/ imprime ausente" "ausente 0" "$r"
check CA8 "o --check não grava nada" "$before" "$(snapshot "$r")"
mkdir -p "$r/.github/workflows" && cp "$script_dir/../templates/workflows/agente.yml" "$r/.github/workflows/agente.yml"
both CA8 "só com o agente.yml imprime ausente" "ausente 0" "$r"
write_wf "$r" prt.yml 'on: pull_request_target
jobs: {}'
both CA8 "só pull_request_target imprime ausente" "ausente 0" "$r"
write_wf "$r" rev.yml 'on:
  pull_request_review:
    types: [submitted]
  pull_request_review_comment:
jobs: {}'
both CA8 "pull_request_review e _comment não contam" "ausente 0" "$r"
write_wf "$r" lista.yml 'on: [push, pull_request_target]
jobs: {}'
both CA8 "lista com pull_request_target não conta" "ausente 0" "$r"

# CA9: sem-e2e e ok, nas três formas de on:.
r="$(new_repo ca9a)"
printf 'e2e: db-up\n\tnpx playwright test\n' > "$r/Makefile"
write_wf "$r" ci.yml 'on: pull_request
jobs:
  t:
    runs-on: ubuntu-latest
    steps:
      - run: make test'
both CA9 "on: pull_request sem make e2e, Makefile com e2e: imprime sem-e2e" "sem-e2e 0" "$r"
write_wf "$r" ci.yml 'on: [push, pull_request]
jobs: {}'
both CA9 "on: [push, pull_request] sem make e2e imprime sem-e2e" "sem-e2e 0" "$r"
write_wf "$r" ci.yml 'name: CI
on:
  pull_request:
    branches: [main]
  push:
jobs: {}'
both CA9 "on: em mapa sem make e2e imprime sem-e2e" "sem-e2e 0" "$r"
write_wf "$r" ci.yml '"on":
  - push
  - pull_request
jobs: {}'
both CA9 "on: em lista de linhas sem make e2e imprime sem-e2e" "sem-e2e 0" "$r"
write_wf "$r" e2e.yml 'on: push
jobs:
  e:
    runs-on: ubuntu-latest
    steps:
      - run: make e2e'
both CA9 "outro workflow com make e2e imprime ok" "ok 0" "$r"
rm "$r/.github/workflows/e2e.yml"
write_wf "$r" ci.yml 'on: pull_request
jobs:
  e:
    runs-on: ubuntu-latest
    steps:
      - run: make e2e-ci'
both CA9 "make e2e-ci não conta como make e2e" "sem-e2e 0" "$r"
r="$(new_repo ca9b)"
printf 'test:\n\techo t\n' > "$r/Makefile"
write_wf "$r" ci.yml 'on: pull_request
jobs: {}'
both CA9 "Makefile sem e2e: imprime ok" "ok 0" "$r"
rm "$r/Makefile"
both CA9 "sem Makefile: imprime ok" "ok 0" "$r"
r="$(new_repo ca9c)"
printf 'e2e:\n\tnpx playwright test\n' > "$r/Makefile"
mkdir -p "$r/.github/workflows" && cp "$model" "$r/.github/workflows/ci.yaml"
both CA9 "o próprio modelo, em .yaml, imprime ok" "ok 0" "$r"
mkdir -p "$r/sub" && run "$r/sub" --check
check CA9 "funciona de uma subpasta do repositório" "ok 0" "$out $rc"

# CA10: --apply.
r="$(new_repo ca10)"
head_before="$(git -C "$r" rev-parse HEAD)"
run "$r" --apply
check CA10 "o --apply sai com 0" "0" "$rc"
check CA10 "grava o ci.yml igual, byte a byte, ao modelo" "True" "$(cmp -s "$model" "$r/.github/workflows/ci.yml" && echo True || echo False)"
check CA10 "não deixa temporário na pasta" "ci.yml" "$(ls -A "$r/.github/workflows")"
check CA10 "não faz commit" "$head_before" "$(git -C "$r" rev-parse HEAD)"
run "$r" --check
check CA10 "depois do --apply, o --check imprime ok" "ok 0" "$out $rc"
echo "# edição do projeto" >> "$r/.github/workflows/ci.yml"
copy="$(cat "$r/.github/workflows/ci.yml")"
run "$r" --apply
check CA10 "com o ci.yml existente, sai com 1" "1" "$rc"
check CA10 "com o ci.yml existente, não muda o arquivo" "$copy" "$(cat "$r/.github/workflows/ci.yml")"
check CA10 "a mensagem tem o prefixo setup-ci:" "True" "$([[ "$err" == setup-ci:* ]] && echo True || echo False)"
r="$(new_repo ca10b)"
mkdir -p "$r/a/b" && run "$r/a/b" --apply
check CA10 "de uma subpasta, grava na raiz do repositório" "True" "$(cmp -s "$model" "$r/.github/workflows/ci.yml" && echo True || echo False)"

d="$tmp/fora" && mkdir -p "$d"
out="$(cd "$d" && GIT_CEILING_DIRECTORIES="$tmp" bash "$setup" --check 2>"$tmp/err")"; rc=$?
check CA10 "fora de um repositório git, --check sai com 1" "1" "$rc"
out="$(cd "$d" && GIT_CEILING_DIRECTORIES="$tmp" bash "$setup" --apply 2>"$tmp/err")"; rc=$?
check CA10 "fora de um repositório git, --apply sai com 1" "1" "$rc"
check CA10 "fora de um repositório git, nada é gravado" "" "$(ls -A "$d")"
run "$r" --outra
check CA10 "opção desconhecida sai com 1" "1" "$rc"
check CA10 "o script não chama git add, git commit nem gh" "0" \
  "$(grep -v '^ *#' "$setup" | grep -c -E 'git (add|commit|push)|(^|[^a-z])gh ')"

echo
echo "$((total - failures))/$total verificações passaram."
[[ $failures -eq 0 ]]
