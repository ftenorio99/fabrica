#!/usr/bin/env bash
# Instala e atualiza os hooks globais do git da fábrica, que recusam commit e
# push na main (ADR 0002). Publica githooks/ numa pasta estável do usuário e
# aponta o core.hooksPath global para ela. A atualização segue a SPEC-246:
# nunca volta sozinha a uma versão menor, troca os arquivos por rename sem
# deixar faltar as entradas de proteção e se coordena por uma trava.
#
# Uso: scripts/setup-githooks.sh [--check] [--force] [--allow-downgrade <versão>]
#   --check            não muda a configuração do git; imprime uma linha:
#                      ok, atualizado <v>, mais-novo <v> [incerta], reparado <v>,
#                      divergente <v> [incerta], ausente, ocupado integra|incerta
#                      ou falha <código>. Sai com 0, exceto em falha (1) e em
#                      uso inválido (2).
#   --force            sobrescreve um core.hooksPath global de outra ferramenta.
#   --allow-downgrade  só na instalação: publica a versão desta origem mesmo
#                      abaixo da instalada. <versão> repete a versão da origem,
#                      como confirmação.
#
# Pode ser carregado com source (os testes fazem isso): só as funções são
# definidas, e o main roda apenas quando o arquivo é executado.

export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$script_dir/../githooks"
plugin_json="$script_dir/../.claude-plugin/plugin.json"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks"

PROTECTION="fabrica-hook pre-commit pre-merge-commit pre-push"
NAME_RE='^[a-z0-9-]+$'
SEMVER_RE='^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$'
HASH_RE='^[0-9a-f]{64}$'
SUM_RE='^([0-9a-f]{64}) [ *]([a-z0-9-]+)$'
LOCK_RE='^fabrica-githooks-lock v1 host=([A-Za-z0-9._-]+) pid=([0-9]+) start=([^ ]+) token=([0-9a-f]{16})$'
CHECK_WAIT=5           # segundos de espera pela trava no --check
INSTALL_WAIT=30        # segundos de espera pela trava na instalação
CHECK_PUBLISH_LIMIT=8  # o --check não começa a escrever depois disto

# Estado global, preenchido pelas funções de leitura.
HASH_CMD=""
ORIG_LIST=""                           # "<hash> <nome>" da origem, em ordem de nome
V_VER="" V_PRESENT=0                   # VERSION
C_OK=0 C_VER="" C_LIST="" C_PRESENT=0  # CONTENTS.sha256
CUR=""                                 # "<tipo> <hash|-> <nome>"; tipo valid|nomode|other
J_PRESENT=0 J_FMT=0 J_VALID=0 J_NADA=0 J_MODO="" J_DE="" J_PARA="" J_ANT="" J_ALVO=""
ST="" I="" S=""
ACTION="" MODO="" OUT=""
TOKEN="" IDENTITY="" MY_HOST="" HAVE_LOCK=0 HAVE_BREAK=0 LOCK_SEEN=""
PHASE=none STAGE=""
CK="" CH="" LH="" WH="" REPLY="" WRAP_CACHE="" STAT_GNU=1

# ---------------------------------------------------------------------------
# Versões

source_version() {
  sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$plugin_json" 2>/dev/null | head -n 1
}

semver_valid() { [[ $1 =~ $SEMVER_RE ]]; }

# semver_cmp <a> <b>: imprime -1, 0 ou 1. As duas precisam ser válidas.
semver_cmp() {
  local IFS=. i x y
  local -a a b
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2; do
    x=$((10#${a[i]})) y=$((10#${b[i]}))
    if ((x > y)); then echo 1; return; fi
    if ((x < y)); then echo -1; return; fi
  done
  echo 0
}

# Maior versão válida entre os argumentos; os inválidos e vazios não contam.
semver_max() {
  local m="" v
  for v in "$@"; do
    semver_valid "$v" || continue
    if [[ -z $m || $(semver_cmp "$v" "$m") == 1 ]]; then m=$v; fi
  done
  printf '%s' "$m"
}

# ---------------------------------------------------------------------------
# Arquivos

pick_hash() {
  if stat -c %a / >/dev/null 2>&1; then STAT_GNU=1; else STAT_GNU=0; fi
  if command -v sha256sum >/dev/null 2>&1; then HASH_CMD=sha256sum
  elif command -v shasum >/dev/null 2>&1; then HASH_CMD=shasum
  else return 1
  fi
}

hash_stdin() {
  local out
  if [[ $HASH_CMD == sha256sum ]]; then out=$(sha256sum 2>/dev/null) || return 1
  else out=$(shasum -a 256 2>/dev/null) || return 1
  fi
  out=${out%% *}
  [[ $out =~ $HASH_RE ]] || return 1
  printf '%s\n' "$out"
}

hash_file() { hash_stdin <"$1" 2>/dev/null; }

# hash_names <pasta> <nome>...: "<hash> <nome>" de cada arquivo legível, numa
# só chamada da ferramenta de hash.
hash_names() {
  local dir=$1 line
  shift
  (($#)) || return 0
  (
    cd -- "$dir" 2>/dev/null || exit 1
    if [[ $HASH_CMD == sha256sum ]]; then sha256sum -- "$@"; else shasum -a 256 -- "$@"; fi 2>/dev/null
  ) | while IFS= read -r line; do
    if [[ $line =~ $SUM_RE ]]; then printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; fi
  done
}

# mode_names <pasta> <nome>...: "<modo octal> <nome>", numa só chamada do stat.
mode_names() {
  local dir=$1
  shift
  (($#)) || return 0
  (
    cd -- "$dir" 2>/dev/null || exit 1
    if ((STAT_GNU)); then stat -c '%a %n' -- "$@"; else stat -f '%Lp %N' -- "$@"; fi 2>/dev/null
  )
}

wrapper_bytes() {
  printf '#!/usr/bin/env bash\n# Entrada do hook %s: regra da fábrica e hook do repositório.\nexec "${0%%/*}/fabrica-hook" "${0##*/}" "$@"\n' "$1"
}

# wrap_get <nome>: hash do modelo do invólucro em WH, guardado em WRAP_CACHE.
wrap_get() {
  if list_hash "$WRAP_CACHE" "$1"; then WH=$LH; return 0; fi
  WH=$(wrapper_bytes "$1" | hash_stdin) || { WH=""; return 1; }
  WRAP_CACHE+="$WH $1"$'\n'
}

# wrap_prime <nome>...: calcula o modelo de vários invólucros de uma vez.
wrap_prime() {
  local t n
  (($#)) || return 0
  t=$(mktemp -d "${TMPDIR:-/tmp}/fabrica-githooks.XXXXXX" 2>/dev/null) || return 0
  for n in "$@"; do wrapper_bytes "$n" >"$t/$n"; done
  WRAP_CACHE+=$(hash_names "$t" "$@")$'\n'
  rm -rf -- "$t"
}

# read_exact <arquivo>: conteúdo de um arquivo regular em REPLY, sem a última
# quebra de linha. Falha se não for regular ou não terminar em quebra de linha.
read_exact() {
  local c
  REPLY=""
  [[ -f $1 && ! -L $1 ]] || return 1
  c=$(cat -- "$1" 2>/dev/null && printf x) || return 1
  c=${c%x}
  [[ $c == *$'\n' ]] || return 1
  REPLY=${c%$'\n'}
}

# Imprime a versão de um arquivo com uma única linha válida.
read_version_file() {
  read_exact "$1" || return 1
  [[ $REPLY != *$'\n'* ]] && semver_valid "$REPLY" || return 1
  printf '%s\n' "$REPLY"
}

# list_hash <lista "<hash> <nome>"> <nome>: o hash fica em LH.
list_hash() {
  local h n
  LH=""
  while read -r h n; do
    if [[ -n $n && $n == "$2" ]]; then LH=$h; return 0; fi
  done <<<"$1"
  return 1
}

list_names() {
  local h n
  while read -r h n; do
    if [[ -n $n ]]; then printf '%s\n' "$n"; fi
  done <<<"$1"
}

# cur_get <nome>: o tipo fica em CK e o hash em CH (CK=none se não existe).
cur_get() {
  local k h n
  CK=none CH=-
  while read -r k h n; do
    if [[ -n $n && $n == "$1" ]]; then CK=$k CH=$h; return 0; fi
  done <<<"$CUR"
  return 1
}

# Entradas do destino: nomes sem ponto inicial, menos os metadados. Um nome
# fora do formato vira "!invalido", que nunca é válido.
entry_names() {
  local p n
  for p in "$dest"/*; do
    [[ -e $p || -L $p ]] || continue
    n=${p##*/}
    [[ $n == VERSION || $n == CONTENTS.sha256 ]] && continue
    [[ $n =~ $NAME_RE ]] || n='!invalido'
    printf '%s\n' "$n"
  done | sort
}

scan_entries() {
  local n h k hashes="" modes=""
  local -a names=() regs=()
  CUR=""
  while IFS= read -r n; do
    if [[ -n $n ]]; then names+=("$n"); fi
  done < <(entry_names)
  ((${#names[@]})) || return 0
  for n in "${names[@]}"; do
    if [[ $n != '!invalido' && -f $dest/$n && ! -L $dest/$n ]]; then regs+=("$n"); fi
  done
  if ((${#regs[@]})); then
    hashes=$(hash_names "$dest" "${regs[@]}")
    modes=$(mode_names "$dest" "${regs[@]}")
  fi
  for n in "${names[@]}"; do
    k=other h=-
    if [[ $n != '!invalido' ]] && list_hash "$hashes" "$n"; then
      h=$LH
      if list_hash "$modes" "$n" && [[ $LH == 755 ]]; then k=valid; else k=nomode; fi
    fi
    CUR+="$k $h $n"$'\n'
  done
}

# Entradas válidas como "<hash> <nome>", para comparar com as listas.
cur_hn() {
  local k h n
  while read -r k h n; do
    if [[ $k == valid ]]; then printf '%s %s\n' "$h" "$n"; fi
  done <<<"$CUR"
}

all_entries_valid() {
  local k h n
  while read -r k h n; do
    [[ -z $n ]] && continue
    [[ $k == valid ]] || return 1
  done <<<"$CUR"
  return 0
}

# ---------------------------------------------------------------------------
# Origem

# Lê e confere githooks/: nomes no formato, arquivos regulares legíveis,
# invólucros iguais ao modelo e o conjunto de proteção completo.
read_origin() {
  local p n hashes
  local -a names=() wrappers=()
  ORIG_LIST=""
  [[ -d $source_dir ]] || { echo "setup-githooks: não encontrei a pasta $source_dir." >&2; return 1; }
  while IFS= read -r n; do
    if [[ -n $n ]]; then names+=("$n"); fi
  done < <(for p in "$source_dir"/*; do if [[ -e $p || -L $p ]]; then printf '%s\n' "${p##*/}"; fi; done | sort)
  ((${#names[@]})) || { echo "setup-githooks: a pasta $source_dir está vazia." >&2; return 1; }
  for n in "${names[@]}"; do
    p="$source_dir/$n"
    [[ $n =~ $NAME_RE ]] || { echo "setup-githooks: nome inválido na origem: $n" >&2; return 1; }
    [[ -f $p && ! -L $p ]] || { echo "setup-githooks: a origem $n não é um arquivo regular." >&2; return 1; }
    if [[ $n != fabrica-hook ]]; then wrappers+=("$n"); fi
  done
  hashes=$(hash_names "$source_dir" "${names[@]}")
  wrap_prime ${wrappers[@]+"${wrappers[@]}"}
  for n in "${names[@]}"; do
    list_hash "$hashes" "$n" || { echo "setup-githooks: não consegui ler a origem $n." >&2; return 1; }
    ORIG_LIST+="$LH $n"$'\n'
    if [[ $n != fabrica-hook ]]; then
      local h=$LH
      wrap_get "$n"
      if [[ $h != "$WH" ]]; then
        echo "setup-githooks: o invólucro $n da origem foge do modelo." >&2
        return 1
      fi
    fi
  done
  for n in $PROTECTION; do
    list_hash "$ORIG_LIST" "$n" || { echo "setup-githooks: a origem não tem $n." >&2; return 1; }
  done
}

# ---------------------------------------------------------------------------
# Leitura do estado

parse_contents() {
  local f="$dest/CONTENTS.sha256" line first=1 prev="" v list=""
  C_OK=0 C_VER="" C_LIST="" C_PRESENT=0
  [[ -e $f || -L $f ]] || return 0
  C_PRESENT=1
  read_exact "$f" || return 0
  while IFS= read -r line; do
    if ((first)); then
      first=0
      [[ $line =~ ^fabrica-githooks-contents\ v1\ ([^ ]+)$ ]] || return 0
      v=${BASH_REMATCH[1]}
      semver_valid "$v" || return 0
      # A versão do cabeçalho é evidência mesmo se o resto não conferir.
      C_VER=$v
      continue
    fi
    [[ $line =~ ^([0-9a-f]{64})\ \ ([a-z0-9-]+)$ ]] || return 0
    if [[ -n $prev && ! ${BASH_REMATCH[2]} > $prev ]]; then return 0; fi
    prev=${BASH_REMATCH[2]}
    list+="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"$'\n'
  done <<<"$REPLY"
  C_LIST=$list
  C_OK=1
}

# journal_relation <modo> <de> <para>: a relação exigida pela tabela de modos.
journal_relation() {
  case $1 in
    atualizacao) [[ $2 != desconhecida && $(semver_cmp "$3" "$2") == 1 ]] ;;
    reparo) [[ $2 == desconhecida || $(semver_cmp "$3" "$2") != -1 ]] ;;
    rollback) [[ $2 != desconhecida && $(semver_cmp "$3" "$2") == -1 ]] ;;
    substituicao) [[ $2 == desconhecida ]] ;;
    *) return 1 ;;
  esac
}

parse_journal() {
  local f="$dest/.publicando" line i=0 kind h n v modo="" de="" para="" ant="" alvo=""
  J_PRESENT=0 J_FMT=0 J_MODO="" J_DE="" J_PARA="" J_ANT="" J_ALVO=""
  [[ -e $f || -L $f ]] || return 0
  J_PRESENT=1
  read_exact "$f" || return 0
  while IFS= read -r line; do
    i=$((i + 1))
    case $i in
      1) [[ $line == 'fabrica-githooks-journal v1' ]] || return 0 ;;
      2) [[ $line =~ ^dono\ [0-9a-f]{16}$ ]] || return 0 ;;
      3) [[ $line =~ ^modo\ (atualizacao|reparo|rollback|substituicao)$ ]] || return 0
         modo=${BASH_REMATCH[1]} ;;
      4) [[ $line =~ ^de\ ([^ ]+)$ ]] || return 0
         v=${BASH_REMATCH[1]}
         [[ $v == desconhecida ]] || semver_valid "$v" || return 0
         de=$v ;;
      5) [[ $line =~ ^para\ ([^ ]+)$ ]] || return 0
         v=${BASH_REMATCH[1]}
         semver_valid "$v" || return 0
         para=$v ;;
      *) [[ $line =~ ^(anterior|alvo)\ ([0-9a-f]{64})\ ([a-z0-9-]+)$ ]] || return 0
         kind=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]} n=${BASH_REMATCH[3]}
         if [[ $kind == anterior ]]; then
           list_hash "$ant" "$n" && return 0
           ant+="$h $n"$'\n'
         else
           list_hash "$alvo" "$n" && return 0
           alvo+="$h $n"$'\n'
         fi ;;
    esac
  done <<<"$REPLY"
  ((i >= 5)) || return 0
  journal_relation "$modo" "$de" "$para" || return 0
  for n in $PROTECTION; do list_hash "$alvo" "$n" || return 0; done
  J_MODO=$modo J_DE=$de J_PARA=$para J_ANT=$ant J_ALVO=$alvo J_FMT=1
}

# Diário válido diante do destino (J_VALID) e publicação que não trocou nada
# (J_NADA).
journal_check() {
  local k h n ha hb nada=1
  J_VALID=0 J_NADA=0
  ((J_FMT)) || return 0
  cur_get fabrica-hook
  [[ $CK == valid ]] || return 0
  while read -r k h n; do
    [[ -n $n ]] || continue
    [[ $k == valid ]] || return 0
    ha="" hb=""
    list_hash "$J_ANT" "$n" && ha=$LH
    list_hash "$J_ALVO" "$n" && hb=$LH
    [[ $h == "$ha" || $h == "$hb" ]] || return 0
    [[ $h == "$ha" ]] || nada=0
  done <<<"$CUR"
  J_VALID=1
  J_NADA=$nada
}

# As 6 condições de "Instalação comprovadamente íntegra".
is_integra() {
  local n h
  [[ -n $V_VER ]] && ((C_OK)) && [[ $C_VER == "$V_VER" ]] || return 1
  for n in $PROTECTION; do list_hash "$C_LIST" "$n" || return 1; done
  all_entries_valid || return 1
  [[ $(cur_hn) == "${C_LIST%$'\n'}" ]] || return 1
  while read -r h n; do
    [[ -n $n && $n != fabrica-hook ]] || continue
    wrap_get "$n"; [[ $h == "$WH" ]] || return 1
  done <<<"$C_LIST"
  return 0
}

is_legada() {
  local k h n
  [[ -n $V_VER ]] && ((!C_PRESENT)) || return 1
  all_entries_valid || return 1
  for n in $PROTECTION; do
    cur_get "$n"
    [[ $CK == valid ]] || return 1
  done
  while read -r k h n; do
    [[ -n $n && $n != fabrica-hook ]] || continue
    wrap_get "$n"; [[ $h == "$WH" ]] || return 1
  done <<<"$CUR"
  return 0
}

# classify <usar o diário: 1|0>: preenche ST e I. I é sempre o máximo das
# evidências válidas.
classify() {
  local de
  if (($1 && J_VALID && !J_NADA)); then
    de=$J_DE
    [[ $de == desconhecida ]] && de=""
    I=$(semver_max "$V_VER" "$C_VER" "$de" "$J_PARA")
    ST=interrompida
    return
  fi
  I=$(semver_max "$V_VER" "$C_VER")
  if is_integra; then ST=integra
  elif is_legada; then ST=legada
  else ST=danificada
  fi
}

read_state() {
  V_PRESENT=0
  [[ -e $dest/VERSION || -L $dest/VERSION ]] && V_PRESENT=1
  V_VER=$(read_version_file "$dest/VERSION") || V_VER=""
  parse_contents
  scan_entries
  parse_journal
  journal_check
  classify 1
}

# Dentro da trava: apaga um diário inválido ou de uma publicação que não
# trocou nada, e relê.
settle_journal() {
  if ((J_PRESENT && (!J_VALID || J_NADA))); then
    rm -f -- "$dest/.publicando" 2>/dev/null
    read_state
  fi
}

equal_origin() {
  all_entries_valid && [[ $(cur_hn) == "${ORIG_LIST%$'\n'}" ]]
}

# Todo arquivo que falta chegar ao alvo do diário tem, na origem, os bytes
# do alvo.
resume_possible() {
  local h n
  while read -r h n; do
    [[ -n $n ]] || continue
    cur_get "$n"
    [[ $CK == valid && $CH == "$h" ]] && continue
    list_hash "$ORIG_LIST" "$n" && [[ $LH == "$h" ]] || return 1
  done <<<"$J_ALVO"
  return 0
}

# ---------------------------------------------------------------------------
# Decisão das execuções automáticas (tabela da SPEC-246). Usa S, ST e I e
# preenche ACTION (nada|publicar|registrar|concluir|minima), MODO e OUT.

decide() {
  local c
  ACTION=nada MODO="" OUT=""
  case $ST in
    integra)
      c=$(semver_cmp "$S" "$I")
      if equal_origin; then OUT=ok
      elif [[ $c == 1 ]]; then ACTION=publicar MODO=atualizacao OUT="atualizado $S"
      elif [[ $c == -1 ]]; then OUT="mais-novo $I"
      else OUT="divergente $I"
      fi ;;
    legada)
      c=$(semver_cmp "$S" "$I")
      if [[ $c == 1 ]]; then ACTION=publicar MODO=atualizacao OUT="atualizado $S"
      elif [[ $c == 0 ]] && equal_origin; then ACTION=registrar MODO=reparo OUT=ok
      elif [[ $c == 0 ]]; then OUT="divergente $I incerta"
      else OUT="mais-novo $I incerta"
      fi ;;
    interrompida)
      if [[ $J_MODO == rollback || $J_MODO == substituicao ]]; then
        OUT="falha rollback-interrompido"
      elif [[ $(semver_cmp "$S" "$I") != -1 ]]; then
        ACTION=publicar MODO=reparo OUT="reparado $S"
      elif [[ $J_PARA == "$I" ]] && resume_possible; then
        # T >= I: como I é o máximo e inclui T, isso é T = I.
        ACTION=concluir MODO=reparo OUT="reparado $J_PARA"
      else
        OUT="falha interrompida"
      fi ;;
    danificada)
      if [[ -n $I ]]; then
        if [[ $(semver_cmp "$S" "$I") != -1 ]]; then
          ACTION=publicar MODO=reparo OUT="reparado $S"
        else
          ACTION=minima OUT="falha danificada"
        fi
      else
        cur_get fabrica-hook
        list_hash "$ORIG_LIST" fabrica-hook
        if [[ $CK == valid && $CH == "$LH" ]]; then
          ACTION=publicar MODO=reparo OUT="reparado $S"
        else
          ACTION=minima OUT="falha versao-desconhecida"
        fi
      fi ;;
  esac
}

# Depois da recuperação mínima de uma instalação danificada, a decisão que
# termina numa pasta íntegra vira "reparado".
damaged_outcome() {
  case $OUT in
    ok) OUT="reparado $I" ;;
    "atualizado "*) OUT="reparado ${OUT#atualizado }" ;;
    "mais-novo "*[0-9] | "divergente "*[0-9]) [[ $ST == integra ]] && OUT="reparado $I" ;;
  esac
}

# ---------------------------------------------------------------------------
# Trava

# Marca de início do processo: campo 22 do /proc/<pid>/stat ou, sem /proc,
# o lstart do ps com os espaços trocados por _.
proc_start() {
  local s rest
  local -a f
  if [[ -r /proc/$1/stat ]]; then
    s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
    rest=${s##*) }
    read -r -a f <<<"$rest"
    [[ ${f[19]-} =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${f[19]}"
    return 0
  fi
  s=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null) || return 1
  s=$(printf '%s' "$s" | sed 's/^ *//; s/ *$//; s/  */_/g; s/ /_/g')
  [[ -n $s ]] || return 1
  printf '%s\n' "$s"
}

# pid_probe <pid>: exists, gone ou unknown, pelo kill -0 com LC_ALL=C.
pid_probe() {
  local err
  if err=$( (export LC_ALL=C; kill -0 "$1") 2>&1); then echo exists; return; fi
  case $err in
    *"No such process"*) echo gone ;;
    *"Operation not permitted"*) echo exists ;;
    *) echo unknown ;;
  esac
}

make_identity() {
  local start
  MY_HOST=$(uname -n 2>/dev/null) || MY_HOST=""
  MY_HOST=${MY_HOST//[^A-Za-z0-9._-]/_}
  [[ -n $MY_HOST ]] || MY_HOST=desconhecido
  TOKEN=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  [[ $TOKEN =~ ^[0-9a-f]{16}$ ]] || TOKEN=$(printf '%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM)
  start=$(proc_start $$) || start=indisponivel
  IDENTITY="fabrica-githooks-lock v1 host=$MY_HOST pid=$$ start=$start token=$TOKEN"
}

# try_create <caminho>: 0 criado com a própria identidade, 1 o nome já existe,
# 2 ambíguo (o ln criou outra coisa).
try_create() {
  local p=$1
  [[ -e $p || -L $p ]] && return 1
  ln -sn -- "$IDENTITY" "$p" 2>/dev/null || return 1
  if [[ -L $p && $(readlink -- "$p") == "$IDENTITY" ]]; then return 0; fi
  # O nome virou uma pasta entre a conferência e o ln: o link foi criado dentro.
  if [[ -L $p/$IDENTITY && $(readlink -- "$p/$IDENTITY") == "$IDENTITY" ]]; then
    rm -f -- "$p/$IDENTITY"
  fi
  return 2
}

owns() { [[ -L $1 && $(readlink -- "$1" 2>/dev/null) == "$IDENTITY" ]]; }

# lock_classify <caminho>: imprime livre, viva, morta ou ambigua. Só a trava
# comprovadamente morta pode ser quebrada; qualquer dúvida conta como viva.
lock_classify() {
  local p=$1 id host pid start now
  [[ -e $p || -L $p ]] || { echo livre; return; }
  [[ -L $p ]] || { echo ambigua; return; }
  id=$(readlink -- "$p" 2>/dev/null) || { echo ambigua; return; }
  [[ $id =~ $LOCK_RE ]] || { echo ambigua; return; }
  host=${BASH_REMATCH[1]} pid=${BASH_REMATCH[2]} start=${BASH_REMATCH[3]}
  if [[ $MY_HOST == desconhecido || $host != "$MY_HOST" ]]; then echo viva; return; fi
  case $(pid_probe "$pid") in
    gone) echo morta ;;
    exists)
      if [[ $start != indisponivel ]] && now=$(proc_start "$pid") && [[ $now != "$start" ]]; then
        echo morta
      else
        echo viva
      fi ;;
    *) echo viva ;;
  esac
}

# lock_break: quebra a trava cuja identidade, julgada morta, está em
# LOCK_SEEN. 0 quebrou ou a trava mudou (tentar de novo), 1 o .break existe
# (esperar), 2 ambíguo.
lock_break() {
  local rc
  try_create "$dest/.break"; rc=$?
  ((rc == 1)) && return 1
  ((rc == 2)) && return 2
  HAVE_BREAK=1
  if [[ -L $dest/.lock && $(readlink -- "$dest/.lock" 2>/dev/null) == "$LOCK_SEEN" ]]; then
    rm -f -- "$dest/.lock"
  fi
  owns "$dest/.break" && rm -f -- "$dest/.break"
  HAVE_BREAK=0
  return 0
}

# lock_acquire <segundos>: 0 adquirida, 1 dono vivo até o prazo, 2 ambígua
# (inclusive um .break que não sai até o prazo).
lock_acquire() {
  local deadline=$((SECONDS + $1)) rc state
  while :; do
    try_create "$dest/.lock"; rc=$?
    if ((rc == 0)); then HAVE_LOCK=1; return 0; fi
    ((rc == 2)) && return 2
    LOCK_SEEN=$(readlink -- "$dest/.lock" 2>/dev/null)
    state=$(lock_classify "$dest/.lock")
    case $state in
      livre) continue ;;
      ambigua) return 2 ;;
      morta)
        # A identidade julgada precisa ser a mesma lida antes da classificação.
        [[ -L $dest/.lock && $(readlink -- "$dest/.lock" 2>/dev/null) == "$LOCK_SEEN" ]] || continue
        lock_break; rc=$?
        ((rc == 2)) && return 2
        ((rc == 0)) && continue
        ((SECONDS >= deadline)) && return 2 ;;
      viva)
        if ((SECONDS >= deadline)); then
          [[ -e $dest/.break || -L $dest/.break ]] && return 2
          return 1
        fi ;;
    esac
    sleep 0.1
  done
}

# 0 liberada (ou não havia trava); 1 a trava não é mais deste processo, e
# nada foi removido.
lock_release() {
  ((HAVE_LOCK)) || return 0
  HAVE_LOCK=0
  if owns "$dest/.lock"; then rm -f -- "$dest/.lock"; return 0; fi
  return 1
}

# ---------------------------------------------------------------------------
# Publicação

MV_T=""
# rename_to <origem> <destino>: rename atômico que nunca entra numa pasta nem
# segue um symlink no destino.
rename_to() {
  if [[ -z $MV_T ]]; then
    if mv --version 2>/dev/null | grep -q -e 'GNU coreutils' -e uutils; then MV_T=1; else MV_T=0; fi
  fi
  if ((MV_T)); then
    mv -f -T -- "$1" "$2"
  else
    [[ -d $2 ]] && return 1
    mv -f -- "$1" "$2"
  fi
}

remove_orphans() {
  local p
  for p in "$dest"/.stage.* "$dest"/.publicando.*; do
    [[ -e $p || -L $p ]] || continue
    rm -rf -- "$p"
  done
}

on_signal() {
  trap '' TERM INT HUP
  case $PHASE in
    staging) rm -rf -- "$STAGE" "$dest/.publicando.$TOKEN" 2>/dev/null ;;
    journaled) rm -rf -- "$STAGE" 2>/dev/null ;;
  esac
  ((HAVE_BREAK)) && owns "$dest/.break" && rm -f -- "$dest/.break"
  lock_release >/dev/null 2>&1
  printf 'falha publicacao\n'
  exit 1
}

on_exit() {
  [[ $PHASE == staging ]] && rm -rf -- "$STAGE" "$dest/.publicando.$TOKEN" 2>/dev/null
  ((HAVE_BREAK)) && owns "$dest/.break" && rm -f -- "$dest/.break"
  lock_release >/dev/null 2>&1
}

# publish <versão alvo> <lista alvo>: usa MODO e I. Retorna 0 depois de
# publicar e conferir a pasta íntegra; senão, OUT recebe a falha.
publish() {
  local tver=$1 tlist=$2 h n p k
  local -a need=()
  PHASE=staging
  # Passo 2: restos de donos anteriores.
  remove_orphans
  STAGE="$dest/.stage.$TOKEN"
  if ! mkdir -- "$STAGE" 2>/dev/null; then OUT="falha preparacao"; PHASE=locked; return 1; fi
  # Passo 3: preparação, só dos arquivos que mudam.
  while read -r h n; do
    [[ -n $n ]] || continue
    cur_get "$n"
    [[ $CK == valid && $CH == "$h" ]] && continue
    if ! list_hash "$ORIG_LIST" "$n" || [[ $LH != "$h" ]] ||
      ! cp -- "$source_dir/$n" "$STAGE/$n" 2>/dev/null ||
      ! chmod 755 -- "$STAGE/$n" ||
      [[ $(hash_file "$STAGE/$n") != "$h" ]]; then
      echo "setup-githooks: falha ao preparar $n." >&2
      rm -rf -- "$STAGE"; PHASE=locked; OUT="falha preparacao"; return 1
    fi
    need+=("$n")
  done <<<"$tlist"
  if ! {
    printf 'fabrica-githooks-contents v1 %s\n' "$tver"
    while read -r h n; do
      if [[ -n $n ]]; then printf '%s  %s\n' "$h" "$n"; fi
    done <<<"$tlist"
  } >"$STAGE/CONTENTS.sha256" || ! printf '%s\n' "$tver" >"$STAGE/VERSION" ||
    ! chmod 644 -- "$STAGE/CONTENTS.sha256" "$STAGE/VERSION"; then
    rm -rf -- "$STAGE"; PHASE=locked; OUT="falha preparacao"; return 1
  fi
  # Passo 4: diário, só com a trava.
  if ! owns "$dest/.lock"; then rm -rf -- "$STAGE"; PHASE=locked; OUT="falha trava"; return 1; fi
  if ! {
    printf 'fabrica-githooks-journal v1\ndono %s\nmodo %s\nde %s\npara %s\n' \
      "$TOKEN" "$MODO" "${I:-desconhecida}" "$tver"
    while read -r k h n; do
      if [[ -n $n && ($k == valid || $k == nomode) ]]; then printf 'anterior %s %s\n' "$h" "$n"; fi
    done <<<"$CUR"
    while read -r h n; do
      if [[ -n $n ]]; then printf 'alvo %s %s\n' "$h" "$n"; fi
    done <<<"$tlist"
  } >"$dest/.publicando.$TOKEN" || ! rename_to "$dest/.publicando.$TOKEN" "$dest/.publicando"; then
    rm -rf -- "$STAGE" "$dest/.publicando.$TOKEN"; PHASE=locked; OUT="falha publicacao"; return 1
  fi
  PHASE=journaled
  # Passos 5 e 6: o fabrica-hook primeiro, depois os invólucros.
  for n in fabrica-hook ${need[@]+"${need[@]}"}; do
    [[ -e $STAGE/$n ]] || continue
    if ! rename_to "$STAGE/$n" "$dest/$n"; then
      echo "setup-githooks: falha ao trocar $n." >&2
      rm -rf -- "$STAGE"; PHASE=locked; OUT="falha publicacao"; return 1
    fi
  done
  # Passos 7 e 8: metadados, de novo só com a trava.
  if ! owns "$dest/.lock"; then rm -rf -- "$STAGE"; PHASE=locked; OUT="falha trava"; return 1; fi
  if ! rename_to "$STAGE/CONTENTS.sha256" "$dest/CONTENTS.sha256" ||
    ! rename_to "$STAGE/VERSION" "$dest/VERSION"; then
    rm -rf -- "$STAGE"; PHASE=locked; OUT="falha publicacao"; return 1
  fi
  # Passo 9: entradas fora do alvo. O alvo sempre tem o conjunto de proteção.
  scan_entries
  while read -r k h n; do
    [[ -n $n && $n != '!invalido' ]] || continue
    list_hash "$tlist" "$n" && continue
    p="$dest/$n"
    if [[ -L $p || -f $p ]]; then rm -f -- "$p"; fi
  done <<<"$CUR"
  # Releitura antes de apagar o diário: só conta como publicada se íntegra.
  V_VER=$(read_version_file "$dest/VERSION") || V_VER=""
  parse_contents
  scan_entries
  classify 0
  if [[ $ST != integra || $V_VER != "$tver" ]]; then
    echo "setup-githooks: a pasta não ficou íntegra depois da publicação." >&2
    rm -rf -- "$STAGE"; PHASE=locked; OUT="falha publicacao"; return 1
  fi
  # Passo 10.
  rm -f -- "$dest/.publicando"
  rm -rf -- "$STAGE"
  PHASE=locked
  J_PRESENT=0 J_FMT=0 J_VALID=0 J_NADA=0
  return 0
}

# Recuperação mínima: devolve o modo 0755 a arquivos regulares com os bytes
# registrados e cria os invólucros ausentes. Não sobrescreve nada nem grava
# VERSION, CONTENTS.sha256 ou diário.
minimal_recovery() {
  local k h n reg names
  while read -r k h n; do
    [[ $k == nomode ]] || continue
    reg=""
    if ((C_OK)) && list_hash "$C_LIST" "$n"; then reg=$LH; fi
    if [[ $h == "$reg" ]] || { [[ $n != fabrica-hook ]] && wrap_get "$n" && [[ $h == "$WH" ]]; }; then
      chmod 755 -- "$dest/$n" 2>/dev/null
    fi
  done <<<"$CUR"
  scan_entries
  cur_get fabrica-hook
  [[ $CK == valid ]] || return 0
  names=$({
    for n in $PROTECTION; do echo "$n"; done
    if ((C_OK)); then list_names "$C_LIST"; fi
  } | sort -u)
  remove_orphans
  STAGE="$dest/.stage.$TOKEN"
  mkdir -- "$STAGE" 2>/dev/null || return 0
  PHASE=staging
  while IFS= read -r n; do
    [[ -n $n && $n != fabrica-hook ]] || continue
    [[ -e $dest/$n || -L $dest/$n ]] && continue
    wrapper_bytes "$n" >"$STAGE/$n" && chmod 755 -- "$STAGE/$n" && rename_to "$STAGE/$n" "$dest/$n"
  done <<<"$names"
  rm -rf -- "$STAGE"
  PHASE=locked
}

# ---------------------------------------------------------------------------

usage() {
  echo "setup-githooks: $1. Uso: setup-githooks.sh [--check] [--force] [--allow-downgrade <versão>]" >&2
  exit 2
}

main() {
  set -u -o pipefail
  local check=false force=false allow="" current ro_st wait rc first can_write

  while (($#)); do
    case $1 in
      --check) check=true ;;
      --force) force=true ;;
      --allow-downgrade)
        (($# >= 2)) || usage "--allow-downgrade precisa da versão"
        allow=$2
        shift ;;
      *) usage "opção desconhecida: $1" ;;
    esac
    shift
  done
  if $check && [[ -n $allow ]]; then usage "--allow-downgrade só vale na instalação, não no --check"; fi

  # No --check, uma linha no stdout. Na instalação, a mensagem de sempre e o
  # core.hooksPath, só quando a pasta terminou íntegra.
  finish() {
    local line=$1 code=$2
    if ! lock_release; then line="falha trava" code=1; fi
    if $check; then
      printf '%s\n' "$line"
      exit "$code"
    fi
    case $line in
      ok | "atualizado "* | "reparado "* | "revertido "* | "mais-novo "*[0-9] | "divergente "*[0-9])
        git config --global core.hooksPath "$dest"
        case $line in
          ok | "atualizado "* | "reparado "*) ;;
          *) echo "setup-githooks: $line" >&2 ;;
        esac
        echo "Hooks do git da fábrica ${V_VER:-$S} instalados em $dest (core.hooksPath global)."
        exit 0 ;;
    esac
    echo "setup-githooks: $line. O core.hooksPath não foi alterado." >&2
    exit 1
  }

  S=$(source_version)
  if ! semver_valid "$S"; then
    echo "setup-githooks: versão da origem inválida em $plugin_json: '$S'." >&2
    finish "falha origem-invalida" 1
  fi
  if [[ -n $allow && $allow != "$S" ]]; then
    usage "--allow-downgrade $allow não confere com a versão desta origem ($S)"
  fi

  current="$(git config --global --get core.hooksPath || true)"
  if $check && [[ $current != "$dest" ]]; then
    echo ausente
    exit 0
  fi
  if ! $check && [[ -n $current && $current != "$dest" ]] && ! $force; then
    echo "setup-githooks: o core.hooksPath global já aponta para \"$current\", de outra ferramenta. Nada foi alterado. Para trocar pelos hooks da fábrica, rode de novo com --force." >&2
    exit 1
  fi
  if [[ -L $dest ]] || { [[ -e $dest ]] && [[ ! -d $dest ]]; }; then
    echo "setup-githooks: $dest não é uma pasta real." >&2
    finish "falha destino-invalido" 1
  fi
  pick_hash || { echo "setup-githooks: falta sha256sum ou shasum." >&2; finish "falha preparacao" 1; }
  read_origin || finish "falha preparacao" 1
  if ! $check; then
    mkdir -p -- "$dest" 2>/dev/null || finish "falha preparacao" 1
  elif [[ ! -d $dest ]]; then
    finish "falha versao-desconhecida" 1
  fi

  trap on_signal TERM INT HUP
  trap on_exit EXIT

  # Leitura sem escrita. Conteúdo íntegro e igual ao da origem, sem diário,
  # é "ok" sem precisar da trava: nada seria escrito.
  read_state
  if $check && [[ $ST == integra ]] && ((!J_PRESENT)) && equal_origin; then finish ok 0; fi
  ro_st=$ST
  wait=$INSTALL_WAIT
  $check && wait=$CHECK_WAIT
  make_identity
  lock_acquire "$wait"; rc=$?
  if ((rc == 1)); then
    [[ $ro_st == integra ]] && finish "ocupado integra" 0
    finish "ocupado incerta" 0
  elif ((rc == 2)); then
    echo "setup-githooks: a trava dos hooks pede conferência manual (veja docs/solucao-de-problemas.md)." >&2
    finish "ocupado incerta" 0
  fi
  PHASE=locked

  read_state
  settle_journal
  can_write=true
  if $check && ((SECONDS >= CHECK_PUBLISH_LIMIT)); then can_write=false; fi
  first=false
  if ! $check && [[ -z $CUR && $V_PRESENT == 0 && $C_PRESENT == 0 ]]; then first=true; fi

  if $first; then
    # Primeira instalação: pasta sem entradas nem metadados.
    I="" ACTION=publicar MODO=reparo OUT="atualizado $S"
  elif [[ -n $allow ]] && ! { [[ $ST == integra ]] && equal_origin; } &&
    { [[ -z $I ]] || [[ $(semver_cmp "$S" "$I") == -1 ]] ||
      [[ $ST == interrompida && ($J_MODO == rollback || $J_MODO == substituicao) ]]; }; then
    # Rollback ou substituição confirmados pelo usuário.
    ACTION=publicar
    if [[ -z $I ]]; then MODO=substituicao OUT="revertido $S"
    elif [[ $(semver_cmp "$S" "$I") == -1 ]]; then MODO=rollback OUT="revertido $S"
    else MODO=reparo OUT="reparado $S"
    fi
  elif [[ $ST == danificada ]]; then
    if $can_write; then
      minimal_recovery
      read_state
    fi
    decide
    damaged_outcome
    [[ $ACTION == minima ]] && ACTION=nada
  else
    decide
  fi

  if [[ $ACTION != nada ]] && ! $can_write; then
    [[ $ST == integra ]] && finish "ocupado integra" 0
    finish "ocupado incerta" 0
  fi

  case $ACTION in
    publicar | registrar) publish "$S" "$ORIG_LIST" || finish "$OUT" 1 ;;
    concluir) publish "$J_PARA" "$J_ALVO" || finish "$OUT" 1 ;;
  esac
  case $OUT in
    "falha "*) finish "$OUT" 1 ;;
  esac
  finish "$OUT" 0
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
