#!/usr/bin/env bash
# Testa o scripts/issue-worktree.sh (SPEC-182) com um HOME temporário,
# repositórios locais com remote --bare e um gh falso no PATH, sem rede.
# Uso: bash scripts/test-issue-worktree.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
sut="$script_dir/issue-worktree.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE FABRICA_GH_BIN
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name teste
git config --global user.email teste@exemplo.com
git config --global init.defaultBranch main

failures=0 total=0

# result <ok: 0|1> <CA> <descrição>
result() {
  total=$((total + 1))
  if (( $1 == 0 )); then
    printf 'ok      %-5s %s\n' "$2" "$3"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-5s %s\n' "$2" "$3"
  fi
}

# gh falso (cada new_repo cria a pasta $tmp/<nome>-gh): responde com $FAKE_GH/<branch com / trocada por _>.json (ou []),
# falha com FAKE_GH_FAIL=1 e registra cada chamada em $FAKE_GH/calls.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_GH/calls"
[[ ${FAKE_GH_FAIL:-0} == 1 ]] && { echo "gh: erro de rede" >&2; exit 1; }
head=""
while (($#)); do [[ $1 == --head ]] && head=$2; shift; done
f="$FAKE_GH/${head//\//_}.json"
if [[ -f $f ]]; then cat "$f"; else echo '[]'; fi
EOF
chmod +x "$tmp/bin/gh"
export FABRICA_GH_BIN="$tmp/bin/gh"

# new_repo <nome>: remote --bare com main e um clone dele em $tmp/<nome>.
new_repo() {
  local r="$tmp/$1"
  git init -q --bare "$r.git"
  git init -q "$r"
  git -C "$r" remote add origin "$r.git"
  echo base >"$r/README.md"
  printf '.env\n*.log\n' >"$r/.gitignore"
  git -C "$r" add . && git -C "$r" commit -q -m inicial
  git -C "$r" push -q -u origin main
  mkdir -p "$tmp/$1-gh"
  echo "$r"
}

# ens <dir> <args...>: roda o ensure a partir de <dir>; saída em $out, código em $rc.
ens() {
  local d=$1; shift
  out="$(cd "$d" && bash "$sut" ensure "$@" 2>"$tmp/err")"; rc=$?
}

# ---------------------------------------------------------------------------
R="$(new_repo a)"
head_before="$(git -C "$R" rev-parse HEAD) $(git -C "$R" symbolic-ref HEAD)"
git -C "$R.git" update-ref refs/heads/main "$(git -C "$R" rev-parse HEAD)"

# CA1
ens "$R" 7 feat/7-x
[[ $rc -eq 0 && $(tail -n 1 <<<"$out") == "$R/.worktrees/7" && -d $R/.worktrees/7 \
  && $(git -C "$R/.worktrees/7" branch --show-current) == feat/7-x \
  && $(git -C "$R/.worktrees/7" rev-parse HEAD) == $(git -C "$R" rev-parse origin/main) \
  && "$(git -C "$R" rev-parse HEAD) $(git -C "$R" symbolic-ref HEAD)" == "$head_before" ]]
result $? CA1 "ensure cria .worktrees/7 em feat/7-x a partir de origin/main, sem mudar o HEAD do clone"
[[ -z $(git -C "$R/.worktrees/7" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) ]]
result $? CA1 "a branch nova não rastreia a origin/main"

# CA2
echo rascunho >"$R/.worktrees/7/nao-commitado.txt"
ens "$R" 7 feat/7-x
[[ $rc -eq 0 && $(tail -n 1 <<<"$out") == "$R/.worktrees/7" && $(cat "$R/.worktrees/7/nao-commitado.txt") == rascunho ]]
result $? CA2 "segundo ensure reusa a worktree sem perder o arquivo não commitado"

# CA3
ens "$R/.worktrees/7" 8 feat/8-y
[[ $rc -eq 0 && $(tail -n 1 <<<"$out") == "$R/.worktrees/8" && -d $R/.worktrees/8 && ! -e $R/.worktrees/7/.worktrees ]]
result $? CA3 "chamado de dentro da worktree 7, cria <clone>/.worktrees/8"

# CA4
git clone -q "$R.git" "$tmp/outro"
git -C "$tmp/outro" switch -q -c feat/9-z
git -C "$tmp/outro" commit -q --allow-empty -m remoto
git -C "$tmp/outro" push -q origin feat/9-z
remote_sha="$(git -C "$tmp/outro" rev-parse HEAD)"
ens "$R" 9 feat/9-z
[[ $rc -eq 0 && $(git -C "$R/.worktrees/9" rev-parse HEAD) == "$remote_sha" \
  && $(git -C "$R/.worktrees/9" rev-parse --abbrev-ref '@{upstream}') == origin/feat/9-z ]]
result $? CA4 "branch só em origin vira branch local rastreando origin/feat/9-z"

# CA6: 7, 8 e 9 ocupam as 3 vagas.
ens "$R" 10 feat/10-w
[[ $rc -eq 5 && ! -e $R/.worktrees/10 ]] && ! git -C "$R" show-ref -q --verify refs/heads/feat/10-w \
  && grep -q '#7' "$tmp/err"
result $? CA6 "4ª worktree: saída 5, sem criar pasta nem branch, citando as issues"
ens "$R" 8 feat/8-y
[[ $rc -eq 0 ]]
result $? CA6 "reusar uma das 3 continua com saída 0"

# CA5
git -C "$R" branch -q feat/11-v
git -C "$R" switch -q feat/11-v
R2="$(new_repo b)"
git -C "$R2" switch -q -c feat/7-x
ens "$R2" 7 feat/7-x
[[ $rc -eq 4 && ! -e $R2/.worktrees/7 ]] && grep -qF "$R2" "$tmp/err"
result $? CA5 "branch em uso no clone principal: saída 4, cita o clone, não cria pasta"
git -C "$R2" switch -q main
git -C "$R" switch -q main
ens "$R" 7 feat/outra
[[ $rc -eq 3 && $(git -C "$R/.worktrees/7" branch --show-current) == feat/7-x ]] && grep -q "feat/7-x" "$tmp/err"
result $? CA5 "worktree em outra branch: saída 3, sem mexer"

# CA7
for args in "abc feat/x" "0 feat/x" "-1 feat/x" "12" "1.5 feat/x" "12 feat/x extra"; do
  # shellcheck disable=SC2086
  ens "$R2" $args
  [[ $rc -eq 2 && ! -e $R2/.worktrees ]]
  result $? CA7 "ensure $args: saída 2, sem criar nada"
done

# CA8
ens "$R2" 20 feat/20-a
ens "$R2" 21 feat/21-b
[[ $(grep -cxF '/.worktrees/' "$R2/.git/info/exclude") -eq 1 && -z $(git -C "$R2" status --porcelain) ]]
result $? CA8 "/.worktrees/ uma vez no exclude e o git status do clone limpo"

# CA9
R3="$(new_repo c)"
printf '.env\nconfig/*.local\nREADME.md\n' >"$R3/.worktreeinclude"
echo 'SEGREDO=1' >"$R3/.env"
mkdir -p "$R3/config"
echo local >"$R3/config/app.local"
printf 'config/*.local\n.worktreeinclude\n' >>"$R3/.git/info/exclude"
echo 'nao.log' >"$R3/x.log"
echo alterado >"$R3/README.md"
ens "$R3" 30 feat/30-e
wt="$R3/.worktrees/30"
[[ $rc -eq 0 && $(cat "$wt/.env") == 'SEGREDO=1' && $(cat "$wt/config/app.local") == local ]]
result $? CA9 "copia os arquivos ignorados que casam com o .worktreeinclude, com o caminho relativo"
[[ $(cat "$wt/README.md") == base && ! -e $wt/x.log ]]
result $? CA9 "não copia arquivo rastreado nem ignorado fora do padrão"
echo 'SEGREDO=2' >"$wt/.env"
ens "$R3" 30 feat/30-e
[[ $rc -eq 0 && $(cat "$wt/.env") == 'SEGREDO=2' ]]
result $? CA9 "na reutilização, o .env alterado na worktree não é sobrescrito"
R4="$(new_repo d)"
echo 'SEGREDO=1' >"$R4/.env"
ens "$R4" 31 feat/31-f
[[ $rc -eq 0 && ! -e $R4/.worktrees/31/.env ]]
result $? CA9 "sem .worktreeinclude, nada é copiado"

# CA10
gitfile="$(cat "$R4/.worktrees/31/.git")"
gitdir_back="$(cat "$R4/.git/worktrees/31/gitdir")"
[[ $gitfile != *"$tmp"* && $gitdir_back != /* ]]
result $? CA10 "o .git da worktree e o gitdir usam caminhos relativos"
mv "$R4" "$tmp/movido"
git -C "$tmp/movido/.worktrees/31" status >/dev/null 2>&1 \
  && [[ $(git -C "$tmp/movido/.worktrees/31" branch --show-current) == feat/31-f ]]
result $? CA10 "depois de mover o clone, a worktree funciona sem git worktree repair"

# CA11
R5="$(new_repo e)"
export FAKE_GH="$tmp/e-gh"
for n in 40 41 42; do ens "$R5" "$n" "feat/$n-x"; done
for n in 40 41 42; do
  git -C "$R5/.worktrees/$n" commit -q --allow-empty -m "trabalho $n"
done
sha() { git -C "$R5/.worktrees/$1" rev-parse HEAD; }
printf '[{"number":3,"state":"CLOSED","headRefOid":"aaaa"},{"number":5,"state":"MERGED","headRefOid":"%s"}]' "$(sha 40)" >"$FAKE_GH/feat_40-x.json"
printf '[{"number":6,"state":"MERGED","headRefOid":"%s"}]' "$(sha 41)" >"$FAKE_GH/feat_41-x.json"
echo sujo >"$R5/.worktrees/41/sujo.txt"
printf '[{"number":7,"state":"OPEN","headRefOid":"%s"}]' "$(sha 42)" >"$FAKE_GH/feat_42-x.json"
mkdir -p "$R5/.worktrees/lixo"
# 43: PR fechado, mas com commit local que não está no PR. O limite de 3 já
# foi atingido, então a worktree é criada à mão.
git -C "$R5" worktree add -q --relative-paths -b feat/43-x "$R5/.worktrees/43" origin/main
printf '[{"number":8,"state":"CLOSED","headRefOid":"%s"}]' "$(git -C "$R5/.worktrees/43" rev-parse HEAD)" >"$FAKE_GH/feat_43-x.json"
git -C "$R5/.worktrees/43" commit -q --allow-empty -m "fora do PR"
# 44: sem PR.
git -C "$R5" worktree add -q --relative-paths -b feat/44-x "$R5/.worktrees/44" origin/main
# Worktree registrada e apagada à mão: o prune limpa o registro.
git -C "$R5" worktree add -q --relative-paths -b feat/99-x "$tmp/fantasma" origin/main
rm -rf "$tmp/fantasma"
clean_out="$(cd "$R5" && bash "$sut" clean 2>"$tmp/err")"; rc=$?
[[ $rc -eq 0 ]] && grep -qx 'removida 40 feat/40-x' <<<"$clean_out" && [[ ! -e $R5/.worktrees/40 ]] \
  && ! git -C "$R5" show-ref -q --verify refs/heads/feat/40-x
result $? CA11 "PR MERGED (o mais recente) e worktree limpa: remove a worktree e a branch"
grep -qx 'mantida 41 feat/41-x trabalho-local' <<<"$clean_out" && [[ -f $R5/.worktrees/41/sujo.txt ]]
result $? CA11 "PR MERGED com arquivo não commitado: mantida trabalho-local"
grep -qx 'mantida 43 feat/43-x trabalho-local' <<<"$clean_out" && [[ -d $R5/.worktrees/43 ]]
result $? CA11 "PR CLOSED com commit fora do PR: mantida trabalho-local"
grep -qx 'mantida 42 feat/42-x em-andamento' <<<"$clean_out" && grep -qx 'mantida 44 feat/44-x em-andamento' <<<"$clean_out"
result $? CA11 "PR OPEN e sem PR: mantida em-andamento"
grep -qx 'mantida lixo - desconhecida' <<<"$clean_out" && [[ -d $R5/.worktrees/lixo ]]
result $? CA11 "pasta que não é worktree: mantida desconhecida, intocada"
! git -C "$R5" worktree list | grep -q fantasma
result $? CA11 "roda git worktree prune"

# CA12
printf '[{"number":9,"state":"MERGED","headRefOid":"%s"}]' "$(git -C "$R5/.worktrees/42" rev-parse HEAD)" >"$FAKE_GH/feat_42-x.json"
before="$(git -C "$R5" worktree list)"
(cd "$R5" && FAKE_GH_FAIL=1 bash "$sut" clean >/dev/null 2>&1); rc=$?
[[ $rc -eq 1 && $(git -C "$R5" worktree list) == "$before" && -d $R5/.worktrees/42 ]]
result $? CA12 "gh com erro: saída 1 e nenhuma worktree removida"

# CA13
rm -f "$FAKE_GH/calls"
list_out="$(cd "$R5/.worktrees/42" && FAKE_GH_FAIL=1 bash "$sut" list)"; rc=$?
[[ $rc -eq 0 && ! -e $FAKE_GH/calls ]] && grep -qx "42 feat/42-x $R5/.worktrees/42" <<<"$list_out" \
  && grep -qx "41 feat/41-x $R5/.worktrees/41" <<<"$list_out" && ! grep -q lixo <<<"$list_out"
result $? CA13 "list imprime <nº> <branch> <caminho> sem chamar o gh"

# CA17
bad="$(grep -nE 'git (switch|checkout)( |$)' "$repo_dir"/skills/{spec,implementar,revisar}/SKILL.md)"
[[ -z $bad ]]
result $? CA17 "spec, implementar e revisar não mandam git switch nem git checkout${bad:+: $bad}"

echo
if (( failures )); then
  echo "$failures de $total casos falharam."
  exit 1
fi
echo "Todos os $total casos passaram."
