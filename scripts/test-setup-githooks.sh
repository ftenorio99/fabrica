#!/usr/bin/env bash
# Testa scripts/setup-githooks.sh (SPEC-246, CA1–CA16) com HOME e configuração
# do git temporários, sem rede. Monta cópias descartáveis da distribuição em
# versões diferentes, cada uma com um fabrica-hook marcado, e usa falsos de
# mv, cp, rm e ln no PATH para registrar o estado, atrasar e interromper.
# Uso: scripts/test-setup-githooks.sh [caminho do setup-githooks.sh]
#   Com outro script (ex.: o da base, por git show), os mesmos cenários
#   mostram quais critérios ele não cumpre; os testes de unidade das funções
#   só rodam com o script novo.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(realpath "$script_dir/..")"
target="$(realpath "${1:-$script_dir/setup-githooks.sh}")"
[[ -f $target ]] || { echo "test-setup-githooks: script não encontrado em $target" >&2; exit 1; }
unit=0
grep -q '^decide()' "$target" && unit=1

tmp="$(mktemp -d)"
bg_pids=()
cleanup() {
  local p
  for p in ${bg_pids[@]+"${bg_pids[@]}"}; do kill "$p" 2>/dev/null; done
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

# Isola a configuração global do git no HOME de teste.
unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
mkdir -p "$HOME"
git config --global user.name teste
git config --global user.email teste@exemplo.com
git config --global init.defaultBranch main
dest="$HOME/.config/fabrica/githooks"
PROT="fabrica-hook pre-commit pre-merge-commit pre-push"

failures=0 total=0
result() {
  total=$((total + 1))
  if (($1 == 0)); then
    printf 'ok      %-5s %s\n' "$2" "$3"
  else
    failures=$((failures + 1))
    printf 'FALHOU  %-5s %s\n' "$2" "$3"
  fi
}

# ---------------------------------------------------------------------------
# Falsos no PATH. Só leem variáveis FAKE_*; o script de produção não tem
# nenhuma variável de teste.
fake="$tmp/fake"
mkdir -p "$fake/bin" "$fake/state"
export FAKE_STATE="$fake/state" FAKE_DEST="$dest" FAKE_PROT="$PROT"
export REAL_MV="$(command -v mv)" REAL_CP="$(command -v cp)" REAL_RM="$(command -v rm)" REAL_LN="$(command -v ln)"

cat >"$fake/bin/mv" <<'EOF'
#!/usr/bin/env bash
case ${1-} in --version | --help) exec "$REAL_MV" "$@" ;; esac
n=$(($(cat "$FAKE_STATE/mv.count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FAKE_STATE/mv.count"
st=ok
for p in $FAKE_PROT; do
  f="$FAKE_DEST/$p"
  [[ -f $f && ! -L $f && -x $f ]] || st="$st,falta:$p"
done
hp=$(git config --global --get core.hooksPath 2>/dev/null || echo -)
echo "$n $st $hp ${*: -1}" >>"$FAKE_STATE/mv.log"
if [[ -n ${FAKE_MV_STEAL_AT-} && $FAKE_MV_STEAL_AT == "$n" ]]; then
  "$REAL_RM" -f "$FAKE_DEST/.lock"
  "$REAL_LN" -s "fabrica-githooks-lock v1 host=outro pid=1 start=1 token=ffffffffffffffff" "$FAKE_DEST/.lock"
fi
[[ -n ${FAKE_MV_SLEEP-} ]] && sleep "$FAKE_MV_SLEEP"
if [[ -n ${FAKE_MV_KILL_AT-} && $FAKE_MV_KILL_AT == "$n" ]]; then
  kill "-${FAKE_MV_SIG:-KILL}" "$PPID"
  exit 1
fi
exec "$REAL_MV" "$@"
EOF
cat >"$fake/bin/cp" <<'EOF'
#!/usr/bin/env bash
n=$(($(cat "$FAKE_STATE/cp.count" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FAKE_STATE/cp.count"
if [[ -n ${FAKE_CP_STEAL_AT-} && $FAKE_CP_STEAL_AT == "$n" ]]; then
  "$REAL_RM" -f "$FAKE_DEST/.lock"
  "$REAL_LN" -s "fabrica-githooks-lock v1 host=outro pid=1 start=1 token=ffffffffffffffff" "$FAKE_DEST/.lock"
fi
[[ -n ${FAKE_CP_SLEEP-} ]] && sleep "$FAKE_CP_SLEEP"
if [[ -n ${FAKE_CP_KILL_AT-} && $FAKE_CP_KILL_AT == "$n" ]]; then
  kill "-${FAKE_CP_SIG:-KILL}" "$PPID"
  exit 1
fi
exec "$REAL_CP" "$@"
EOF
cat >"$fake/bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ -n ${FAKE_RM_SLEEP-} && ${*: -1} == */.publicando ]]; then sleep "$FAKE_RM_SLEEP"; fi
exec "$REAL_RM" "$@"
EOF
cat >"$fake/bin/ln" <<'EOF'
#!/usr/bin/env bash
[[ -n ${FAKE_LN_SLEEP-} ]] && sleep "$FAKE_LN_SLEEP"
exec "$REAL_LN" "$@"
EOF
chmod +x "$fake/bin/"*

# PATH sem ferramenta de hash, para o CA4.
nohash="$tmp/nohash"
mkdir -p "$nohash"
for t in bash env git sed head sort cat mkdir cp chmod mv rm ln readlink stat od tr uname ps grep mktemp sleep dirname kill; do
  p=$(command -v "$t" 2>/dev/null) && [[ $p == /* ]] && ln -s "$p" "$nohash/$t"
done

fake_reset() {
  rm -rf "$fake/state"
  mkdir -p "$fake/state"
  unset FAKE_MV_KILL_AT FAKE_MV_SIG FAKE_MV_SLEEP FAKE_MV_STEAL_AT FAKE_CP_KILL_AT FAKE_CP_SIG FAKE_CP_SLEEP FAKE_CP_STEAL_AT FAKE_RM_SLEEP FAKE_LN_SLEEP
}

# ---------------------------------------------------------------------------
# Distribuições de teste

# make_dist <nome> <versão> [marca] [opção...]: reduzida (sem a regra do
# pre-merge-commit), -<hook> (sem a entrada), bad:<hook> (invólucro fora do
# modelo), link:<hook> (symlink), ilegivel:<hook>.
make_dist() {
  local name=$1 v=$2 mark=${3:-$2} d="$tmp/dist/$1" o
  shift 2
  (($#)) && shift
  rm -rf "$d"
  mkdir -p "$d/scripts" "$d/.claude-plugin"
  cp -r "$repo/githooks" "$d/githooks"
  cp "$target" "$d/scripts/setup-githooks.sh"
  printf '{\n  "name": "fabrica",\n  "version": "%s"\n}\n' "$v" >"$d/.claude-plugin/plugin.json"
  printf '# marca de teste: %s\n' "$mark" >>"$d/githooks/fabrica-hook"
  for o in "$@"; do
    case $o in
      reduzida) sed -i 's/pre-commit|pre-merge-commit)/pre-commit)/' "$d/githooks/fabrica-hook" ;;
      -*) rm "$d/githooks/${o#-}" ;;
      bad:*) echo '# extra' >>"$d/githooks/${o#bad:}" ;;
      link:*) rm "$d/githooks/${o#link:}"; ln -s pre-commit "$d/githooks/${o#link:}" ;;
      ilegivel:*) chmod 000 "$d/githooks/${o#ilegivel:}" ;;
    esac
  done
}

make_dist d1 1.0.0
make_dist d1x 1.0.0 1.0.0-outro
make_dist d0 0.9.0
make_dist d15 1.5.0
make_dist d2 2.0.0
make_dist d2v 2.1.0 2.0.0     # versão maior com os mesmos bytes do d2
make_dist d2x 2.0.0 2.0.0-outro
make_dist d3 3.0.0
make_dist red 1.5.0 reduzida reduzida
make_dist da 1.0.0 1.0.0 -post-merge -pre-rebase
make_dist db 2.0.0 2.0.0 -update

# Distribuição com o script da base (de4c39a), para gerar instalações legadas.
legacy_script="$tmp/legacy-setup-githooks.sh"
git -C "$repo" show de4c39a:scripts/setup-githooks.sh >"$legacy_script" 2>/dev/null
make_legacy() { # <nome> <versão> [marca]
  make_dist "$1" "$2" "${3:-$2}"
  cp "$legacy_script" "$tmp/dist/$1/scripts/setup-githooks.sh"
}
make_legacy l1 1.0.0
make_legacy l2 2.0.0

script_of() { printf '%s' "$tmp/dist/$1/scripts/setup-githooks.sh"; }

# run <dist> [args]: OUT, RC e ERR. PATH_PREFIX, se definido, vai à frente.
run() {
  local d=$1
  shift
  OUT=$(PATH="${PATH_PREFIX:+$PATH_PREFIX:}$PATH" bash "$(script_of "$d")" "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}
runfake() { PATH_PREFIX="$fake/bin" run "$@"; }

reset() {
  chmod -R u+rwx "$HOME/.config" 2>/dev/null
  rm -rf "$HOME/.config/fabrica"
  git config --global --unset core.hooksPath
  fake_reset
}
fresh() { # instala uma distribuição do zero
  reset
  run "$1"
  [[ $RC == 0 ]] || echo "  (instalação de $1 falhou: $RC $OUT $ERR)"
}

# Estado completo do destino: nome, tipo, inode, modo, mtime e hash.
snap() {
  local f
  [[ -d $dest ]] || { echo sem-destino; return; }
  for f in "$dest"/* "$dest"/.[!.]*; do
    [[ -e $f || -L $f ]] || continue
    if [[ -L $f ]]; then echo "${f##*/} L $(readlink "$f")"
    elif [[ -d $f ]]; then echo "${f##*/} D"
    else echo "${f##*/} $(stat -c '%i %a %y' "$f") $(sha256sum <"$f" | cut -c1-64)"
    fi
  done
}
content() { # só nomes e hashes das entradas e metadados
  local f
  for f in "$dest"/*; do
    [[ -f $f ]] && echo "${f##*/} $(sha256sum <"$f" | cut -c1-64)"
  done
}

# state: "<ST> <VERSION>" pelo leitor do script novo (só com unit=1).
state() {
  if ((unit)); then
    bash -c 'source "$1"; pick_hash; read_state; echo "$ST ${V_VER:--}"' _ "$repo/scripts/setup-githooks.sh"
  else
    echo "? $(cat "$dest/VERSION" 2>/dev/null)"
  fi
}
is_integra_at() { [[ $(state) == "integra $1" ]]; }

prot_ok() { # conjunto de proteção presente, regular e executável
  local p
  for p in $PROT; do [[ -f $dest/$p && ! -L $dest/$p && -x $dest/$p ]] || return 1; done
}
hook_is() { cmp -s "$dest/fabrica-hook" "$tmp/dist/$1/githooks/fabrica-hook"; }
no_internal() { ! ls -A "$dest" | grep -q '^\.'; }
mv_log_ok() { [[ -f $fake/state/mv.log ]] && ! grep -q 'falta:' "$fake/state/mv.log"; }

my_host() { local h; h=$(uname -n); echo "${h//[^A-Za-z0-9._-]/_}"; }
lock_id() { printf 'fabrica-githooks-lock v1 host=%s pid=%s start=%s token=0123456789abcdef' "$1" "$2" "$3"; }
start_of() {
  local s rest
  local -a f
  s=$(cat "/proc/$1/stat")
  rest=${s##*) }
  read -r -a f <<<"$rest"
  echo "${f[19]}"
}
live_pid() { sleep 60 & LIVE=$!; bg_pids+=("$LIVE"); }
dead_pid() { bash -c 'exit 0' & DEAD=$!; wait "$DEAD"; }

# ---------------------------------------------------------------------------
# Testes de unidade das funções de decisão (só o script novo)
if ((unit)); then
  # shellcheck source=/dev/null
  source "$target"
  set +e
  pick_hash

  u() { [[ $2 == "$3" ]]; result $? "${4:-UNIT}" "$1: esperado '$3', veio '$2'"; }
  for c in "1.2.3 1.2.3 0" "1.10.0 1.9.9 1" "0.9.0 1.0.0 -1" "2.0.0 10.0.0 -1" "999999999.0.0 999999998.9.9 1"; do
    set -- $c
    u "semver_cmp $1 $2" "$(semver_cmp "$1" "$2")" "$3"
  done
  bad=0
  for v in 1.2 v1.2.3 01.2.3 1.2.03 1.2.3-rc 1234567890.0.0 "" " 1.2.3" 1.2.3.4; do
    semver_valid "$v" && { bad=1; echo "  aceitou '$v'"; }
  done
  result $bad UNIT "semver_valid recusa formatos fora da política (zeros à esquerda, prefixo, 10 dígitos)"
  u "semver_max ignora inválidos" "$(semver_max 1.0.0 lixo 0.9.0 '' 2.0.0 1.10.0)" 2.0.0
  u "semver_max sem evidência" "$(semver_max lixo '')" ""
  bad=0
  journal_relation atualizacao 1.0.0 2.0.0 || bad=1
  journal_relation atualizacao 2.0.0 2.0.0 && bad=1
  journal_relation atualizacao desconhecida 2.0.0 && bad=1
  journal_relation reparo desconhecida 1.0.0 || bad=1
  journal_relation reparo 1.0.0 1.0.0 || bad=1
  journal_relation reparo 2.0.0 1.0.0 && bad=1
  journal_relation rollback 2.0.0 1.0.0 || bad=1
  journal_relation rollback 1.0.0 1.0.0 && bad=1
  journal_relation substituicao desconhecida 1.0.0 || bad=1
  journal_relation substituicao 1.0.0 0.5.0 && bad=1
  result $bad UNIT "journal_relation segue a tabela de modos do diário"

  # Tabela de decisão: equal_origin, resume_possible e o fabrica-hook da
  # origem são substituídos para isolar a decisão.
  EQ=1 RES=1 FH=1
  equal_origin() { ((EQ)); }
  resume_possible() { ((RES)); }
  cur_get() { CK=valid CH=$([[ $FH == 1 ]] && echo aaa || echo bbb); }
  list_hash() { LH=aaa; }
  # row <ST> <S> <I> <EQ> <modo> <para> <RES> <FH> <ACTION> <OUT>
  row() {
    ST=$1 S=$2 I=$3 EQ=$4 J_MODO=$5 J_PARA=$6 RES=$7 FH=$8
    [[ $I == - ]] && I=""
    decide
    [[ "$ACTION|$OUT" == "$9|${10}" ]]
    result $? DEC "$1 S=$2 I=$3 eq=$4 modo=$5 T=$6 res=$7 fh=$8 → $9 | ${10} (veio $ACTION | $OUT)"
  }
  row integra 1.0.0 1.0.0 1 - - 0 0 nada ok
  row integra 3.0.0 1.0.0 1 - - 0 0 nada ok
  row integra 2.0.0 1.0.0 0 - - 0 0 publicar "atualizado 2.0.0"
  row integra 1.0.0 2.0.0 0 - - 0 0 nada "mais-novo 2.0.0"
  row integra 2.0.0 2.0.0 0 - - 0 0 nada "divergente 2.0.0"
  row legada 2.0.0 1.0.0 0 - - 0 0 publicar "atualizado 2.0.0"
  row legada 1.0.0 1.0.0 1 - - 0 0 registrar ok
  row legada 1.0.0 1.0.0 0 - - 0 0 nada "divergente 1.0.0 incerta"
  row legada 1.0.0 2.0.0 0 - - 0 0 nada "mais-novo 2.0.0 incerta"
  row interrompida 3.0.0 2.0.0 0 rollback 1.0.0 1 1 nada "falha rollback-interrompido"
  row interrompida 3.0.0 2.0.0 0 substituicao 1.0.0 1 1 nada "falha rollback-interrompido"
  row interrompida 2.0.0 2.0.0 0 atualizacao 2.0.0 0 0 publicar "reparado 2.0.0"
  row interrompida 3.0.0 2.0.0 0 reparo 2.0.0 0 0 publicar "reparado 3.0.0"
  row interrompida 1.0.0 2.0.0 0 atualizacao 2.0.0 1 0 concluir "reparado 2.0.0"
  row interrompida 1.0.0 2.0.0 0 atualizacao 2.0.0 0 0 nada "falha interrompida"
  # T < I (um VERSION maior gravado depois do diário): os bytes alvo não bastam.
  row interrompida 1.0.0 3.0.0 0 atualizacao 2.0.0 1 0 nada "falha interrompida"
  row danificada 2.0.0 1.0.0 0 - - 0 0 publicar "reparado 2.0.0"
  row danificada 1.0.0 1.0.0 0 - - 0 0 publicar "reparado 1.0.0"
  row danificada 1.0.0 2.0.0 0 - - 0 0 minima "falha danificada"
  row danificada 1.0.0 - 0 - - 0 1 publicar "reparado 1.0.0"
  row danificada 1.0.0 - 0 - - 0 0 minima "falha versao-desconhecida"
  unset -f equal_origin resume_possible cur_get list_hash
  source "$target"
  set +e
  pick_hash

  # Trava: classificação com o kill -0 substituído.
  make_identity
  ldir="$tmp/lockunit"
  mkdir -p "$ldir"
  live_pid
  lstart=$(start_of "$LIVE")
  cls() { ln -sfn "$1" "$ldir/.lock"; lock_classify "$ldir/.lock"; }
  u "trava de processo vivo" "$(cls "$(lock_id "$MY_HOST" "$LIVE" "$lstart")")" viva CA15
  u "PID reutilizado (marca diferente)" "$(cls "$(lock_id "$MY_HOST" "$LIVE" 1)")" morta CA15
  u "marca de início indisponível" "$(cls "$(lock_id "$MY_HOST" "$LIVE" indisponivel)")" viva CA15
  dead_pid
  u "processo encerrado" "$(cls "$(lock_id "$MY_HOST" "$DEAD" 1)")" morta CA15
  u "outro host" "$(cls "$(lock_id outra-maquina "$DEAD" 1)")" viva CA15
  u "identidade malformada" "$(cls 'fabrica-githooks-lock v1 host=x pid=abc')" ambigua CA16
  u "identidade com campo a mais" "$(cls "$(lock_id "$MY_HOST" "$DEAD" 1) extra=1")" ambigua CA16
  rm -f "$ldir/.lock"; mkdir "$ldir/.lock"
  u ".lock que é uma pasta" "$(lock_classify "$ldir/.lock")" ambigua CA16
  rmdir "$ldir/.lock"; echo x >"$ldir/.lock"
  u ".lock que é um arquivo" "$(lock_classify "$ldir/.lock")" ambigua CA16
  rm -f "$ldir/.lock"
  pid_probe() { echo unknown; }
  u "kill -0 com resultado não reconhecido" "$(cls "$(lock_id "$MY_HOST" "$DEAD" 1)")" viva CA16
  proc_start() { return 1; }
  pid_probe() { echo exists; }
  u "marca do dono não obtida (sem /proc e ps que falha)" "$(cls "$(lock_id "$MY_HOST" "$LIVE" 123)")" viva CA15
  source "$target"
  set +e
  pick_hash
  make_identity

  # try_create com symlink para pasta: o ln -sn não cria nada dentro dela.
  rm -f "$ldir/.lock"; mkdir -p "$ldir/alvo"; ln -s alvo "$ldir/.lock"
  try_create "$ldir/.lock"; rc=$?
  [[ $rc == 1 && -z $(ls -A "$ldir/alvo") && $(readlink "$ldir/.lock") == alvo ]]
  result $? CA16 "try_create sobre symlink para pasta: recusa e não cria nada dentro"
  rm -f "$ldir/.lock"
  "$REAL_LN" -sn "$IDENTITY" "$ldir/alvo-link" 2>/dev/null
  ln -s alvo "$ldir/x"; "$REAL_LN" -sn "$IDENTITY" "$ldir/x" 2>/dev/null
  [[ -z $(ls -A "$ldir/alvo") ]]
  result $? CA16 "ln -sn sobre symlink para pasta não cria o link dentro da pasta (conferido no ln desta máquina)"
  # Liberação: com a trava trocada, não remove a do novo dono.
  dest_saved=$dest dest=$ldir
  rm -f "$ldir/.lock"; ln -s "$(lock_id outro 1 1)" "$ldir/.lock"
  HAVE_LOCK=1
  lock_release; rc=$?
  [[ $rc == 1 && $(readlink "$ldir/.lock") == "$(lock_id outro 1 1)" ]]
  result $? CA16 "lock_release com a trava de outro dono: não remove e sinaliza"
  dest=$dest_saved
  kill "$LIVE" 2>/dev/null
  set -uo pipefail
fi

# ---------------------------------------------------------------------------
# CA1: conteúdo igual ao da origem: ok sem escrever nada.
fresh d2
before=$(snap)
run d2 --check
[[ $OUT == ok && $RC == 0 && $(snap) == "$before" ]]
result $? CA1 "íntegra e igual à origem: ok, sem mudar inode, modo, mtime nem hash"
run d2v --check
[[ $OUT == ok && $RC == 0 && $(snap) == "$before" ]]
result $? CA1 "origem com outra versão de plugin e os mesmos bytes: ok, sem escrever"

# CA2: origem menor: mais-novo, sem mudar nada.
fresh d2
before=$(snap)
run d1 --check
[[ $OUT == "mais-novo 2.0.0" && $RC == 0 && $(snap) == "$before" ]]
result $? CA2 "íntegra 2.0.0 e origem 1.0.0: mais-novo 2.0.0, nada muda (veio '$OUT')"
run d1
[[ $RC == 0 && $(snap) == "$before" ]] && hook_is d2
result $? CA2 "instalação da origem menor também não faz downgrade"

# CA3: origem maior: atualizado, proteção presente antes de cada rename.
fresh d1
runfake d2 --check
[[ $OUT == "atualizado 2.0.0" ]] && mv_log_ok && is_integra_at 2.0.0 && hook_is d2 && no_internal
result $? CA3 "1.0.0 → 2.0.0: atualizado, proteção presente em cada rename, íntegra no fim (veio '$OUT')"
fresh da
runfake db --check
[[ $OUT == "atualizado 2.0.0" ]] && mv_log_ok && is_integra_at 2.0.0 && [[ -f $dest/post-merge && ! -e $dest/update ]]
result $? CA3 "com entradas novas e obsoletas: proteção presente em cada rename, obsoleta removida"
reset
runfake d2
[[ $RC == 0 ]] && ! awk '$3 != "-"' "$fake/state/mv.log" | grep -q . && is_integra_at 2.0.0 &&
  [[ $(git config --global --get core.hooksPath) == "$dest" ]]
result $? CA3 "primeira instalação: o core.hooksPath só aponta para o destino depois de íntegro"

# CA4: falha na preparação deixa o destino igual.
prep_case() { # <descrição> <dist> <saída esperada> [prefixo do PATH]
  fresh d1
  local before
  before=$(snap)
  PATH_PREFIX=${4-} run "$2" --check
  [[ $OUT == "$3" && $RC == 1 && $(snap) == "$before" ]]
  result $? CA4 "$1: '$3', destino igual (veio '$OUT' rc=$RC)"
}
make_dist p_bad 2.0.0 2.0.0 bad:pre-rebase
make_dist p_noprot 2.0.0 2.0.0 -pre-push
make_dist p_link 2.0.0 2.0.0 link:post-merge
make_dist p_unread 2.0.0 2.0.0 ilegivel:post-merge
make_dist p_ver 1.0 1.0
prep_case "invólucro fora do modelo na origem" p_bad "falha preparacao"
prep_case "entrada de proteção ausente na origem" p_noprot "falha preparacao"
prep_case "symlink na origem" p_link "falha preparacao"
if (($(id -u) != 0)); then
  prep_case "arquivo ilegível na origem" p_unread "falha preparacao"
fi
fresh d1
before=$(snap)
OUT=$(PATH="$nohash" bash "$(script_of d2)" --check 2>/dev/null); RC=$?
[[ $OUT == "falha preparacao" && $RC == 1 && $(snap) == "$before" ]]
result $? CA4 "ferramenta de hash ausente: falha preparacao, destino igual (veio '$OUT')"
prep_case "versão da origem inválida" p_ver "falha origem-invalida"
fresh d1
mv "$dest" "$HOME/.config/fabrica/real"
ln -s real "$dest"
run d2 --check
[[ $OUT == "falha destino-invalido" && $RC == 1 && -L $dest ]] && [[ $(cat "$HOME/.config/fabrica/real/VERSION") == 1.0.0 ]]
result $? CA4 "destino que é um symlink: falha destino-invalido, nada escrito (veio '$OUT')"
fresh d1
before=$(snap)
FAKE_CP_KILL_AT=1 runfake d2 --check
[[ $(snap | grep -v '^\.') == "$(echo "$before" | grep -v '^\.')" ]] && prot_ok
result $? CA4 "interrupção no meio da cópia: entradas do destino intactas"

# CA5: danificada com I ≤ S é reparada até íntegra.
repair_case() { # <descrição> <dist> <saída> <comando de dano>
  fresh d1
  (cd "$dest" && eval "$4")
  runfake "$2" --check
  [[ $OUT == "$3" ]] && is_integra_at "${3#reparado }" && no_internal
  result $? CA5 "$1: '$3' e íntegra (veio '$OUT', estado $(state))"
}
repair_case "entrada editada" d1 "reparado 1.0.0" 'echo "# mexido" >>post-merge'
repair_case "entrada ausente" d1 "reparado 1.0.0" 'rm pre-push'
repair_case "VERSION ausente" d1 "reparado 1.0.0" 'rm VERSION'
repair_case "VERSION ausente, origem maior" d2 "reparado 2.0.0" 'rm VERSION'
repair_case "CONTENTS ausente com invólucro editado" d1 "reparado 1.0.0" 'rm CONTENTS.sha256; echo x >>update'
repair_case "CONTENTS sem uma entrada de proteção" d1 "reparado 1.0.0" 'grep -v " pre-push$" CONTENTS.sha256 >c && mv c CONTENTS.sha256'
repair_case "invólucro registrado fora do modelo" d1 "reparado 1.0.0" 'echo x >>post-merge; h=$(sha256sum <post-merge | cut -c1-64); sed -i "s/^[0-9a-f]*  post-merge$/$h  post-merge/" CONTENTS.sha256'
repair_case "entrada trocada por symlink" d1 "reparado 1.0.0" 'rm pre-commit; ln -s fabrica-hook pre-commit'
repair_case "entrada extra não registrada" d1 "reparado 1.0.0" 'printf "#!/bin/sh\n" >extra-hook; chmod 755 extra-hook'
fresh d1
rm "$dest/VERSION"
runfake d1 --check
# Antes de cada rename do reparo, as entradas de proteção presentes no início
# continuam presentes.
mv_log_ok
result $? CA5 "durante o reparo, as entradas de proteção presentes no início ficam presentes"
fresh d1
ino=$(stat -c %i "$dest/pre-commit")
chmod 644 "$dest/pre-commit" "$dest/fabrica-hook"
run d0 --check
[[ $OUT == "reparado 1.0.0" && $(stat -c '%i %a' "$dest/pre-commit") == "$ino 755" && -x $dest/fabrica-hook ]] && hook_is d1
result $? CA5 "modo perdido com bytes registrados: modo devolvido sem trocar o conteúdo, mesmo com origem menor (veio '$OUT')"

# CA6: mesma versão, conteúdo diferente: divergente, sem escrever.
fresh d2
before=$(snap)
run d2x --check
[[ $OUT == "divergente 2.0.0" && $RC == 0 && $(snap) == "$before" ]]
result $? CA6 "íntegra 2.0.0 e origem 2.0.0 com outro fabrica-hook: divergente, nada escrito (veio '$OUT')"

# CA7: execuções simultâneas terminam na versão maior.
fresh d1
rm -f "$tmp"/ca7.*
for i in $(seq 1 20); do
  bash "$(script_of d1)" --check >"$tmp/ca7.1.$i" 2>/dev/null &
  bash "$(script_of d2)" --check >"$tmp/ca7.2.$i" 2>/dev/null &
done
wait
low_updates=$(cat "$tmp"/ca7.1.* | grep -c '^atualizado' || true)
high_updates=$(cat "$tmp"/ca7.2.* | grep -c '^atualizado 2.0.0' || true)
[[ $low_updates == 0 && $high_updates == 1 ]] && is_integra_at 2.0.0 && hook_is d2 && no_internal
result $? CA7 "20 pares simultâneos 1.0.0/2.0.0: íntegra em 2.0.0, uma atualização, nenhuma para a menor (menor=$low_updates maior=$high_updates)"

# CA8: instalação legada, gerada pelo script da base. O "arquivo válido" da
# spec tem modo 0755: o script da base só gera isso com umask 022. Com umask
# 002 ele gera 0775, e a pasta conta como danificada (caso no fim do CA8).
legacy() { reset; local m; m=$(umask); umask 022; run "$1"; umask "$m"; }
legacy l1
run d2 --check
[[ $OUT == "atualizado 2.0.0" ]] && is_integra_at 2.0.0
result $? CA8 "legada 1.0.0 e origem 2.0.0: atualizado 2.0.0 (veio '$OUT')"
legacy l1
inodes=$(stat -c '%n %i' "$dest"/[a-z]*)
run d1 --check
[[ $OUT == ok && -f $dest/CONTENTS.sha256 && $(stat -c '%n %i' "$dest"/[a-z]*) == "$inodes" ]] && is_integra_at 1.0.0
r1=$?
before=$(snap)
run d1 --check
[[ $r1 == 0 && $OUT == ok && $(snap) == "$before" ]]
result $? CA8 "legada 1.0.0 com os mesmos bytes: grava só o CONTENTS (inodes iguais), ok, e a seguinte não escreve"
legacy l1
before=$(snap)
run d1x --check
[[ $OUT == "divergente 1.0.0 incerta" && $(snap) == "$before" ]]
result $? CA8 "legada 1.0.0 com outro fabrica-hook: divergente 1.0.0 incerta, nada escrito (veio '$OUT')"
legacy l2
before=$(snap)
run d1 --check
[[ $OUT == "mais-novo 2.0.0 incerta" && $(snap) == "$before" ]]
result $? CA8 "legada 2.0.0 e origem 1.0.0: mais-novo 2.0.0 incerta, nada escrito (veio '$OUT')"
legacy l1
echo x >>"$dest/update"
[[ $(state) == "danificada 1.0.0" ]]
result $? CA8 "legada com invólucro fora do modelo é danificada"
legacy l1
rm "$dest/pre-push"
[[ $(state) == "danificada 1.0.0" ]]
result $? CA8 "legada sem uma entrada de proteção é danificada"
reset
m=$(umask); umask 002; run l2; umask "$m"
before=$(content)
run d1 --check
[[ $OUT == "falha danificada" && $(content) == "$before" ]] && hook_is l2
r1=$?

run d2 --check
[[ $r1 == 0 && $OUT == "reparado 2.0.0" ]] && is_integra_at 2.0.0
result $? CA8 "legada com modo 0775 (umask 002): danificada, sem downgrade com origem menor e reparada com a mesma versão (veio '$OUT')"

# CA9: rollback só com --allow-downgrade, na instalação.
fresh d2
run d1 --allow-downgrade 1.0.0
[[ $RC == 0 && $ERR == *"revertido 1.0.0"* ]] && is_integra_at 1.0.0 && hook_is d1
result $? CA9 "--allow-downgrade 1.0.0 sobre 2.0.0: revertido 1.0.0 e íntegra (veio rc=$RC '$ERR')"
run d2 --check
[[ $OUT == "atualizado 2.0.0" ]]
result $? CA9 "depois do rollback, uma origem maior volta a subir (veio '$OUT')"
fresh d2
FAKE_MV_KILL_AT=2 runfake d1 --allow-downgrade 1.0.0
grep -q '^modo rollback$' "$dest/.publicando" 2>/dev/null
result $? CA9 "o diário do rollback registra modo rollback"
fresh d2
rm "$dest/VERSION" "$dest/CONTENTS.sha256"
echo '# mexido' >>"$dest/fabrica-hook"
FAKE_MV_KILL_AT=2 runfake d1 --allow-downgrade 1.0.0
grep -q '^modo substituicao$' "$dest/.publicando" 2>/dev/null
result $? CA9 "sem versão comprovada, o diário registra modo substituicao"
fresh d2
before=$(snap)
run d1 --allow-downgrade 2.0.0
r1=$RC
run d1 --check --allow-downgrade 1.0.0
[[ $r1 == 2 && $RC == 2 && $(snap) == "$before" ]]
result $? CA9 "versão diferente da origem ou no --check: saída 2, nada escrito (rc=$r1 e $RC)"

# CA10: comportamento real do git depois de cada publicação.
repos() {
  rm -rf "$tmp/r"
  git init -q --bare "$tmp/r/remote.git"
  git init -q "$tmp/r/w"
  git -C "$tmp/r/w" remote add origin "$tmp/r/remote.git"
  git -C "$tmp/r/w" commit -q --allow-empty -m init
  git -C "$tmp/r/w" push -q origin main 2>/dev/null
  git -C "$tmp/r/w" switch -q -c feat/x
  git -C "$tmp/r/w" commit -q --allow-empty -m feat
  git -C "$tmp/r/w" switch -q main
  printf '#!/bin/sh\necho encadeado >"%s"\n' "$tmp/r/chain" >"$tmp/r/w/.git/hooks/pre-commit"
  chmod +x "$tmp/r/w/.git/hooks/pre-commit"
}
git_rules() { # imprime commit merge push chain: 1 recusado, 0 passou
  local c m p ch
  repos
  git -C "$tmp/r/w" commit -q --allow-empty -m direto 2>/dev/null; c=$?
  git -C "$tmp/r/w" merge -q --no-ff -m merge feat/x 2>/dev/null; m=$?
  git -C "$tmp/r/w" reset -q --hard origin/main
  git -C "$tmp/r/w" switch -q feat/x
  git -C "$tmp/r/w" push -q origin feat/x:main 2>/dev/null; p=$?
  git -C "$tmp/r/w" commit -q --allow-empty -m ok-na-branch 2>/dev/null
  [[ -f $tmp/r/chain ]] && ch=1 || ch=0
  echo "$((c != 0)) $((m != 0)) $((p != 0)) $ch"
}
fresh d1
runfake d2 --check
[[ $(git_rules) == "1 1 1 1" ]]
result $? CA10 "depois de atualizar para 2.0.0: commit, merge --no-ff e push na main recusados; hook do repositório encadeado"
fresh d1
FAKE_MV_KILL_AT=3 runfake d2 --check
[[ $(git_rules) == "1 1 1 1" ]] && prot_ok
result $? CA10 "numa publicação interrompida depois do fabrica-hook: as regras continuam valendo"
fresh d2
run red --allow-downgrade 1.5.0
[[ $RC == 0 && $(git_rules) == "1 0 1 1" ]] && prot_ok
result $? CA10 "rollback confirmado para a versão reduzida: o merge --no-ff passa (redução intencional)"
fresh d2
run red --check
[[ $OUT == "mais-novo 2.0.0" ]] && [[ $(git_rules) == "1 1 1 1" ]]
result $? CA10 "sem --allow-downgrade, a versão reduzida não é instalada (veio '$OUT')"

# CA12: danificada com I > S não sofre downgrade.
nodown_case() { # <descrição> <dist> <saída> <dano>
  fresh d2
  (cd "$dest" && eval "$4")
  local before
  before=$(content)
  run "$2" --check
  [[ $OUT == "$3" && $RC == 1 && $(content) == "$before" ]]
  result $? CA12 "$1: '$3', arquivos existentes iguais (veio '$OUT')"
}
nodown_case "I pelo VERSION e pelo CONTENTS" d1 "falha danificada" 'echo x >>post-merge'
nodown_case "I só pelo VERSION" d1 "falha danificada" 'rm CONTENTS.sha256; echo x >>update'
nodown_case "I só pelo CONTENTS" d1 "falha danificada" 'rm VERSION'
nodown_case "VERSION e CONTENTS divergentes: vale o máximo" d15 "falha danificada" 'echo 1.0.0 >VERSION'
nodown_case "VERSION inválido não conta como zero" d1 "falha danificada" 'echo 0.0 >VERSION'
nodown_case "sem versão e fabrica-hook diferente do da origem" d1 "falha versao-desconhecida" 'rm VERSION CONTENTS.sha256'
fresh d2
rm "$dest/fabrica-hook"
run d1 --check
[[ $OUT == "falha danificada" && ! -e $dest/fabrica-hook ]]
result $? CA12 "fabrica-hook ausente com origem menor: não é criado (veio '$OUT')"
run d2 --check
[[ $OUT == "reparado 2.0.0" ]] && hook_is d2
result $? CA12 "fabrica-hook ausente com origem igual: criado (veio '$OUT')"
fresh d2
rm "$dest/pre-commit"
run d1 --check
[[ $OUT == "reparado 2.0.0" && -x $dest/pre-commit ]] && hook_is d2
result $? CA12 "invólucro ausente com origem menor: só o invólucro é criado, fabrica-hook intacto (veio '$OUT')"

# CA13 e CA14: interrupção em cada rename e recuperação na execução seguinte.
fresh da
runfake db --check
total_mv=$(cat "$fake/state/mv.count")
names_da=$(ls "$tmp/dist/da/githooks" | sort)
ca13=0 ca14=0 detail=""
for k in $(seq 1 "$total_mv"); do
  for next in db da; do
    fresh da
    FAKE_MV_KILL_AT=$k runfake db --check
    # Conjunto de proteção, fabrica-hook de uma das duas versões, nenhuma
    # entrada anterior removida.
    if ! prot_ok || ! { hook_is da || hook_is db; } ||
      [[ -n $(comm -23 <(echo "$names_da") <(ls "$dest" | sort)) ]]; then
      ca13=1 detail+=" k=$k"
    fi
    run "$next" --check
    v=$(cat "$dest/VERSION" 2>/dev/null)
    case $next:$OUT in
      db:"reparado 2.0.0" | db:"atualizado 2.0.0") is_integra_at 2.0.0 || { ca14=1; detail+=" k=$k/$next:$OUT"; } ;;
      da:ok | da:"mais-novo 2.0.0") ;;
      da:"reparado 2.0.0") is_integra_at 2.0.0 || { ca14=1; detail+=" k=$k/$next:$OUT"; } ;;
      da:"falha interrompida") [[ $v == 1.0.0 || $v == 2.0.0 ]] && prot_ok || { ca14=1; detail+=" k=$k/$next:$OUT"; } ;;
      *) ca14=1 detail+=" k=$k/$next:'$OUT'" ;;
    esac
    # Nunca abaixo da maior evidência sem --allow-downgrade.
    [[ $v == 1.0.0 && $OUT == "reparado 2.0.0" ]] && { ca14=1; detail+=" k=$k/$next:v=$v"; }
  done
done
result $ca13 CA13 "interrupção (KILL) em cada um dos $total_mv renames: proteção presente, fabrica-hook de uma das versões, nada removido$detail"
result $ca14 CA14 "recuperação depois de cada interrupção, com origem maior e menor$detail"

fresh da
FAKE_MV_KILL_AT=2 runfake db --check
run da --check
[[ $OUT == ok && ! -e $dest/.publicando ]] && is_integra_at 1.0.0
result $? CA14 "diário gravado sem nada trocado: diário apagado e decisão refeita (veio '$OUT')"
fresh d2
FAKE_MV_KILL_AT=3 runfake d1 --allow-downgrade 1.0.0
run d3 --check
r1=$OUT
run d1 --check
[[ $r1 == "falha rollback-interrompido" && $OUT == "falha rollback-interrompido" ]] && prot_ok
result $? CA14 "rollback interrompido: execução automática, maior ou menor, não continua (veio '$r1' e '$OUT')"
run d1 --allow-downgrade 1.0.0
[[ $RC == 0 ]] && is_integra_at 1.0.0
result $? CA14 "rollback interrompido: só um novo --allow-downgrade conclui"
fresh d1
FAKE_MV_KILL_AT=4 runfake d2 --check   # depois do fabrica-hook e do CONTENTS
echo 3.0.0 >"$dest/VERSION"
run d1 --check
[[ $OUT == "falha interrompida" ]] && hook_is d2
result $? CA14 "VERSION maior gravado depois do diário (T < I): nada é concluído pelos bytes alvo (veio '$OUT')"

# Sinais em cada fase: TERM libera a trava; KILL deixa a trava de dono morto.
phase_case() { # <fase> <sinal> <variáveis do falso>
  fresh d1
  local before
  before=$(content)
  (export $3; PATH="$fake/bin:$PATH" timeout -s "$2" 1 bash "$(script_of d2)" --check >/dev/null 2>&1)
  sleep 0.3
  local ok=0
  prot_ok || ok=1
  { hook_is d1 || hook_is d2; } || ok=1
  run d2 --check
  [[ $OUT == "atualizado 2.0.0" || $OUT == "reparado 2.0.0" || $OUT == ok ]] && is_integra_at 2.0.0 && no_internal || ok=1
  result $ok CA13 "$2 na $1: proteção presente e a execução seguinte termina íntegra (veio '$OUT')"
}
for sig in TERM KILL; do
  phase_case preparação $sig FAKE_CP_SLEEP=2
  phase_case publicação $sig FAKE_MV_SLEEP=0.4
  phase_case limpeza $sig FAKE_RM_SLEEP=3
done
for sig in TERM KILL; do
  fresh d1
  live_pid
  ln -s "$(lock_id "$(my_host)" "$LIVE" "$(start_of "$LIVE")")" "$dest/.lock"
  before=$(snap)
  timeout -s $sig 1 bash "$(script_of d2)" --check >/dev/null 2>&1
  [[ $(snap) == "$before" ]]
  result $? CA13 "$sig na espera pela trava: nada muda e a trava do outro dono fica"
  kill "$LIVE" 2>/dev/null
done
# Filho ainda rodando depois do KILL só no processo principal.
fresh d1
FAKE_MV_SLEEP=1 PATH="$fake/bin:$PATH" bash "$(script_of d2)" --check >/dev/null 2>&1 &
main_pid=$!
sleep 0.5
kill -KILL "$main_pid" 2>/dev/null
wait "$main_pid" 2>/dev/null
sleep 1.5
ok=0
prot_ok || ok=1
run d2 --check
is_integra_at 2.0.0 && no_internal || ok=1
result $ok CA13 "KILL só no script com um mv filho ainda rodando: proteção presente e recuperação íntegra (veio '$OUT')"

# CA15: trava de processo vivo não é removida por idade.
lock_case() { # <descrição> <identidade> <saída esperada> <espera mín> <espera máx> <CA>
  local t0 t1
  fresh d1
  rm -f "$dest/.lock"
  ln -s "$2" "$dest/.lock"
  touch -h -d '1 hour ago' "$dest/.lock" 2>/dev/null
  before=$(snap)
  t0=$(date +%s)
  run d2 --check
  t1=$(($(date +%s) - t0))
  [[ $OUT == "$3" && $t1 -ge $4 && $t1 -le $5 && $(snap) == "$before" ]]
  result $? "$6" "$1: '$3' em ${t1}s, trava e destino intactos (veio '$OUT')"
}
live_pid
hs=$(my_host)
lock_case "dono vivo com mtime de uma hora atrás" "$(lock_id "$hs" "$LIVE" "$(start_of "$LIVE")")" "ocupado integra" 4 7 CA15
lock_case "dono de outro host" "$(lock_id outra-maquina 1 1)" "ocupado integra" 4 7 CA15
lock_case "dono vivo sem marca de início registrada" "$(lock_id "$hs" "$LIVE" indisponivel)" "ocupado integra" 4 7 CA15
dead_pid
fresh d1
ln -s "$(lock_id "$hs" "$DEAD" 1)" "$dest/.lock"
run d2 --check
[[ $OUT == "atualizado 2.0.0" ]] && no_internal
result $? CA15 "dono encerrado: trava quebrada e adquirida (veio '$OUT')"
fresh d1
ln -s "$(lock_id "$hs" "$LIVE" 1)" "$dest/.lock"
run d2 --check
[[ $OUT == "atualizado 2.0.0" ]] && no_internal
result $? CA15 "PID reutilizado (marca diferente): trava quebrada e adquirida (veio '$OUT')"
fresh d1
before=$(snap)
FAKE_LN_SLEEP=8.5 runfake d2 --check
[[ $OUT == "ocupado integra" && $(snap | grep -v '^\.') == "$(echo "$before" | grep -v '^\.')" ]] && hook_is d1
result $? CA15 "--check depois de 8 s: não começa a publicação (veio '$OUT')"
kill "$LIVE" 2>/dev/null

# CA16: situações ambíguas nunca levam a aquisição ou quebra.
lock_case "identidade malformada" "lixo" "ocupado incerta" 0 2 CA16
dead_pid
fresh d1
ln -s "$(lock_id "$hs" "$DEAD" 1)" "$dest/.lock"
ln -s "$(lock_id "$hs" "$DEAD" 2)" "$dest/.break"
before=$(snap)
run d2 --check
[[ $OUT == "ocupado incerta" && $(snap) == "$before" ]]
result $? CA16 ".break existente, mesmo de dono morto: ocupado incerta, nada removido (veio '$OUT')"
for kind in pasta arquivo link-pasta; do
  fresh d1
  case $kind in
    pasta) mkdir "$dest/.lock" ;;
    arquivo) echo x >"$dest/.lock" ;;
    link-pasta) mkdir "$tmp/alvo-$kind"; ln -s "$tmp/alvo-$kind" "$dest/.lock" ;;
  esac
  before=$(snap)
  run d2 --check
  inside=""
  [[ $kind == link-pasta ]] && inside=$(ls -A "$tmp/alvo-$kind")
  [[ $kind == pasta ]] && inside=$(ls -A "$dest/.lock")
  [[ $OUT == "ocupado incerta" && $(snap) == "$before" && -z $inside ]]
  result $? CA16 ".lock que é $kind: ocupado incerta, nada criado dentro (veio '$OUT')"
done
fresh d1
FAKE_MV_STEAL_AT=2 runfake d2 --check
[[ $OUT == "falha trava" && $(readlink "$dest/.lock") == *host=outro* && -f $dest/.publicando ]] && prot_ok
result $? CA16 "trava perdida antes dos metadados: para com falha trava e não remove a do novo dono (veio '$OUT')"
fresh d1
FAKE_CP_STEAL_AT=1 runfake d2 --check
[[ $OUT == "falha trava" && ! -e $dest/.publicando ]] && hook_is d1
result $? CA16 "trava perdida antes do diário: para com falha trava, sem diário (veio '$OUT')"
bad=0
for i in 1 2 3 4 5; do
  dead_pid
  fresh d1
  ln -s "$(lock_id "$hs" "$DEAD" 1)" "$dest/.lock"
  bash "$(script_of d2)" --check >"$tmp/br.a" 2>/dev/null &
  bash "$(script_of d2)" --check >"$tmp/br.b" 2>/dev/null &
  wait
  n=$(cat "$tmp/br.a" "$tmp/br.b" | grep -c '^atualizado' || true)
  [[ $n == 1 ]] && is_integra_at 2.0.0 && no_internal || bad=1
done
result $bad CA16 "duas quebras simultâneas da mesma trava morta: uma única aquisição que publica (5 rodadas)"

echo
if ((failures)); then
  echo "$failures de $total casos falharam."
  exit 1
fi
echo "Todos os $total casos passaram."
