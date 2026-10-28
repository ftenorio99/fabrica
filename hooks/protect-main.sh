#!/usr/bin/env bash
# PreToolUse (Bash): bloqueia git commit e git push na main/master.
# Exceções: o primeiro commit de um repositório novo e o primeiro push
# da main quando ela ainda não existe no remoto.
#
# O comando é lido em duas etapas: code_view separa o código do texto
# citado (aspas, heredocs) e o laço final divide o código em comandos
# simples, analisando só os git commit e git push que vão rodar.
# Na dúvida (bash -c, eval, $(...), heredoc, here-string ou pipe para
# shell, aspas sem fechamento), o texto é tratado como código e pode bloquear.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
[ -d "$cwd" ] || cwd="$PWD"

# Filtro rápido: sem essas palavras, não há o que analisar.
grep -Eq 'commit|push' <<<"$cmd" || exit 0

soh=$'\001' stx=$'\002'

# Devolve só o código do comando. O texto entre aspas continua como uma
# única palavra, com espaços e separadores trocados por \001 (e \002 marca
# a aspa, para "" virar palavra vazia); o corpo de heredoc some.
# $(...) e crases dentro de aspas duplas abrem um nível novo, lido com as
# mesmas regras e emitido como comandos à parte, logo depois do comando
# em que aparece.
# O argumento de bash/sh -c, de eval e de here-string para shell e o corpo
# de heredoc para shell também vão como código. Sai com 2 se não conseguir
# separar (aspas, $( ou heredoc sem fechamento) ou se houver pipe para shell.
code_view() {
  awk -v sq="'" '
    function emit(t) { ob[L] = ob[L] t }
    function addw(t) { cw[L] = cw[L] t; iw[L] = 1; emit(t) }
    function flushword() { if (iw[L]) { nw[L]++; w[L, nw[L]] = cw[L] } cw[L] = ""; iw[L] = 0 }
    # Fim de um comando no nível principal: o código extra que apareceu nele
    # ($(...) em aspas, bash -c, eval) vai logo depois, antes do próximo
    # comando, para valer o mesmo diretório.
    function resetcmd() {
      flushword(); nw[L] = 0; hsnext = 0
      if (L == 0 && pend != "") { emit("\n" pend "\n"); pend = "" }
    }
    function cmdname(   i, x) {
      for (i = 1; i <= nw[L]; i++) {
        x = w[L, i]
        if (x ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || x ~ /^-/) continue
        if (x ~ /^(\{|!|if|elif|while|until|then|do|else|time|sudo|command|exec|nohup|env)$/) continue
        return x
      }
      return ""
    }
    function isshell(x) { sub(/.*\//, "", x); return x ~ /^(bash|sh|zsh|dash|ksh)$/ }
    function shellarg(   x, i) {
      if (hsnext) return 1
      x = cmdname()
      if (x == "eval") return 2
      if (!isshell(x)) return 0
      for (i = 1; i <= nw[L]; i++) if (w[L, i] ~ /^-[A-Za-z]*c[A-Za-z]*$/) return 1
      return 0
    }
    function mapped(t) { gsub(/[ \t\n;&|()`]/, soh, t); return t }
    # Código que roda em outro processo ($(...), crases, bash -c, heredoc e
    # here-string para shell) vai entre os marcadores \001S e \001R: um cd
    # dentro dele não muda o diretório dos comandos seguintes. eval roda no
    # shell atual e vai sem marcadores.
    function sub_open() { return "\n" soh "S\n" }
    function sub_close() { return "\n" soh "R\n" }
    function rawcode(t, own) {
      gsub("[\"" sq "]", " ", t)
      pend = pend (own ? sub_open() t sub_close() : "\n" t)
    }
    function push(t) { L++; ob[L] = ""; cw[L] = ""; iw[L] = 0; nw[L] = 0; dq[L] = 0; pd[L] = 0; term[L] = t }
    function pop() { flushword(); pend = pend sub_open() ob[L] sub_close(); L-- }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      soh = sprintf("%c", 1); stx = sprintf("%c", 2)
      dqspecial = "\\\"$`"; special = "\\#" sq "\"<\n;&|()` \t"
      n = length(s); i = 1; L = 0; nh = 0; pend = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\" && substr(s, i + 1, 1) == "\n") { i += 2; continue }

        # Dentro de aspas duplas: texto, exceto $(...) e crases.
        if (dq[L]) {
          # Trecho sem caractere especial vai de uma vez (concatenar
          # caractere por caractere fica quadrático em comandos longos).
          j = i
          while (j <= n && !index(dqspecial, substr(s, j, 1))) j++
          if (j > i) { addw(mapped(substr(s, i, j - i))); i = j; continue }
          if (c == "\\") { addw(mapped(substr(s, i + 1, 1))); i += 2; continue }
          if (c == "\"") { dq[L] = 0; i++; continue }
          if (c == "$" && substr(s, i + 1, 1) == "(") { push(""); i += 2; continue }
          if (c == "`") { push("`"); i++; continue }
          addw(mapped(c)); i++; continue
        }

        # Fim de um nível aberto dentro de aspas duplas.
        if (L > 0 && term[L] == "`" && c == "`") { pop(); i++; continue }
        if (L > 0 && term[L] == "" && c == ")" && pd[L] == 0) { pop(); i++; continue }

        if (c == "\\") { addw(mapped(substr(s, i + 1, 1))); i += 2; continue }
        if (c == "#" && !iw[L]) {
          while (i <= n && substr(s, i, 1) != "\n") i++
          continue
        }
        if (c == sq) {
          j = index(substr(s, i + 1), sq)
          if (!j) exit 2
          body = substr(s, i + 1, j - 1)
          if ((sa = shellarg())) rawcode(body, sa == 1)
          addw(stx mapped(body)); i += j + 1; continue
        }
        if (c == "\"") {
          if ((sa = shellarg())) {
            j = i + 1; body = ""
            while (j <= n && substr(s, j, 1) != "\"") {
              if (substr(s, j, 1) == "\\") { body = body substr(s, j, 2); j += 2 }
              else { body = body substr(s, j, 1); j++ }
            }
            if (j > n) exit 2
            rawcode(body, sa == 1); addw(stx); i = j + 1; continue
          }
          dq[L] = 1; addw(stx); i++; continue
        }
        if (substr(s, i, 3) == "<<<") {
          flushword()
          if (isshell(cmdname())) hsnext = 1
          emit(" "); i += 3; continue
        }
        if (substr(s, i, 2) == "<<") {
          flushword()
          k = i + 2; strip = 0
          if (substr(s, k, 1) == "-") { strip = 1; k++ }
          while (substr(s, k, 1) ~ /[ \t]/) k++
          q = substr(s, k, 1)
          if (q == sq || q == "\"") {
            e = index(substr(s, k + 1), q)
            if (!e) exit 2
            delim = substr(s, k + 1, e - 1); k += e + 1
          } else {
            delim = ""
            while (k <= n && substr(s, k, 1) !~ /[ \t\n;&|<>()]/) {
              ch = substr(s, k, 1)
              if (ch != "\\") delim = delim ch
              k++
            }
          }
          if (delim == "") exit 2
          nh++; hd[nh] = delim; hs[nh] = strip; hsh[nh] = isshell(cmdname())
          emit(" "); i = k; continue
        }
        if (c == "\n") {
          resetcmd(); emit("\n"); i++
          for (h = 1; h <= nh; h++) {
            found = 0
            if (hsh[h]) emit(soh "S\n")
            while (i <= n) {
              e = index(substr(s, i), "\n")
              line = e ? substr(s, i, e - 1) : substr(s, i)
              i = e ? i + e : n + 1
              cmp = line
              if (hs[h]) sub(/^\t+/, "", cmp)
              if (cmp == hd[h]) { found = 1; break }
              if (hsh[h]) emit(line "\n")
            }
            if (!found) exit 2
            if (hsh[h]) emit(soh "R\n")
          }
          nh = 0; continue
        }
        if (c ~ /[;&|()`]/) {
          # Pipe para um shell executa o texto da esquerda: sai para o
          # modo de dúvida, que analisa tudo como código.
          if (c == "|" && substr(s, i + 1, 1) != "|" && substr(s, i - 1, 1) != "|") {
            j = i + 1
            for (r = 0; r < 2; r++) {
              while (substr(s, j, 1) ~ /[ \t]/) j++
              k = j
              while (k <= n && substr(s, k, 1) !~ /[ \t\n;&|()]/) k++
              word = substr(s, j, k - j)
              if (word != "sudo") break
              j = k
            }
            if (isshell(word)) exit 2
          }
          # $( ) e ( ) sem aspas também rodam em outro processo.
          resetcmd()
          if (c == "(") { pd[L]++; emit(sub_open()) }
          else if (c == ")") { pd[L]--; emit(sub_close()) }
          else emit(c)
          i++; continue
        }
        if (c ~ /[ \t]/) { flushword(); emit(c); i++; continue }
        j = i + 1
        while (j <= n && !index(special, substr(s, j, 1))) j++
        addw(substr(s, i, j - i)); i = j
      }
      if (L > 0 || dq[0] || nh > 0) exit 2
      if (pend != "") emit("\n" pend)
      printf "%s", ob[0]
    }
  ' <<<"$cmd"
}

fallback=0
code=$(code_view) || fallback=1
if (( fallback )); then
  code=$(tr '\047"' '  ' <<<"$cmd")
fi

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Resolve um caminho de cd ou git -C relativo ao diretório atual.
resolve() {
  local target="${1/#\~/$HOME}"
  [[ $target = /* ]] || target="$2/$target"
  printf '%s' "$target"
}

# Diretório de trabalho a partir de um --git-dir.
from_git_dir() {
  local target
  target=$(resolve "$1" "$2")
  [[ $target == */.git ]] && target=${target%/.git}
  printf '%s' "$target"
}

declare -A commit_checked
check_commit() {
  local dir=$1 branch
  # O mesmo diretório só precisa ser conferido uma vez.
  [[ -n ${commit_checked[$dir]} ]] && return 0
  commit_checked[$dir]=1
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 0
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  [[ $branch == main || $branch == master ]] || return 0
  # Repositório sem nenhum commit: permite o commit inicial.
  git -C "$dir" rev-parse --verify -q HEAD >/dev/null || return 0
  deny "Commit direto na '$branch' bloqueado pelas práticas do usuário. Crie uma branch (ex.: git switch -c feat/<n>-descricao) e abra um PR."
}

check_push() {
  local dir=$1 branch remote arg to_main=0
  shift
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 0
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  for arg in "$@"; do
    [[ $arg == -* ]] && continue
    [[ $arg =~ (^|:)\+?(refs/heads/)?(main|master)$ ]] && to_main=1
  done
  (( to_main )) || [[ $branch == main || $branch == master ]] || return 0
  # main ainda não existe no remoto: permite o primeiro push.
  remote=$(git -C "$dir" remote | head -n1)
  [ -n "$remote" ] || return 0
  git -C "$dir" ls-remote --exit-code --heads "$remote" main master >/dev/null 2>&1 || return 0
  deny "Push para a main bloqueado pelas práticas do usuário. Faça push da sua branch e abra um PR (gh pr create)."
}

set -f
curdir=$cwd
saved=()
while IFS= read -r segment; do
  read -ra words <<<"$segment"
  (( ${#words[@]} )) || continue
  # Marcadores de código em outro processo: salva e restaura o diretório.
  case ${words[0]} in
    "${soh}S") saved+=("$curdir"); continue ;;
    "${soh}R")
      # ")" sem par (ex.: padrão de case) não tem diretório salvo.
      (( ${#saved[@]} )) && { curdir=${saved[-1]}; unset 'saved[-1]'; }
      continue ;;
  esac
  # Texto citado volta ao valor real, numa palavra só.
  words=("${words[@]//$soh/ }")
  words=("${words[@]//$stx/}")

  # Primeira palavra do comando, depois de atribuições e prefixos.
  k=0 wrapped=0
  while (( k < ${#words[@]} )); do
    case ${words[k]} in
      [A-Za-z_]*=*|'{'|'!'|if|elif|while|until|then|do|else) k=$((k + 1)) ;;
      sudo|env|time|command|exec|nohup) wrapped=1; k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  # Depois de sudo/env com opções, ou sem separar o texto, procura o git
  # em qualquer posição do comando.
  if (( fallback || wrapped )); then
    j=$k
    while (( j < ${#words[@]} )) && [[ ${words[j]##*/} != git ]]; do j=$((j + 1)); done
    (( j < ${#words[@]} )) && k=$j
  fi
  (( k < ${#words[@]} )) || continue

  if [[ ${words[k]} == cd ]]; then
    next=${words[k + 1]-$HOME}
    [[ $next == - ]] || curdir=$(resolve "$next" "$curdir")
    continue
  fi
  [[ ${words[k]##*/} == git ]] || continue

  # Opções globais do git antes do subcomando.
  gitdir=$curdir
  k=$((k + 1))
  while (( k < ${#words[@]} )); do
    case ${words[k]} in
      -C) gitdir=$(resolve "${words[k + 1]}" "$gitdir"); k=$((k + 2)) ;;
      -C?*) gitdir=$(resolve "${words[k]#-C}" "$gitdir"); k=$((k + 1)) ;;
      --git-dir) gitdir=$(from_git_dir "${words[k + 1]}" "$gitdir"); k=$((k + 2)) ;;
      --git-dir=*) gitdir=$(from_git_dir "${words[k]#--git-dir=}" "$gitdir"); k=$((k + 1)) ;;
      -c|--work-tree|--namespace) k=$((k + 2)) ;;
      -*) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  [ -d "$gitdir" ] || gitdir=$cwd

  case ${words[k]} in
    commit) check_commit "$gitdir" ;;
    push) check_push "$gitdir" "${words[@]:k+1}" ;;
  esac
done < <(tr ';&|()`' '\n\n\n\n\n\n' <<<"$code")
exit 0
