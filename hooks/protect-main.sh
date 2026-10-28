#!/usr/bin/env bash
# PreToolUse (Bash): bloqueia git commit e git push na main/master.
# Exceções: o primeiro commit de um repositório novo e o primeiro push
# da main quando ela ainda não existe no remoto.
#
# O comando é lido em duas etapas: code_view separa o código do texto
# citado (aspas, heredocs) e o laço final divide o código em comandos
# simples, analisando só os git commit e git push que vão rodar.
# Na dúvida (bash -c, eval, $(...), heredoc ou pipe para shell, aspas
# sem fechamento), o texto é tratado como código e pode bloquear.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
[ -d "$cwd" ] || cwd="$PWD"

# Filtro rápido: sem essas palavras, não há o que analisar.
grep -Eq 'commit|push' <<<"$cmd" || exit 0

# Devolve só o código do comando: texto entre aspas e corpo de heredoc
# viram espaço. Exceções mantidas como código: argumento de bash/sh -c e
# de eval, $(...) e crases dentro de aspas duplas, heredoc para shell e
# palavra entre aspas na posição de comando. Sai com 2 se não conseguir
# separar (aspas, $( ou heredoc sem fechamento).
code_view() {
  awk -v sq="'" '
    function flushword() { if (inword) { nw++; w[nw] = cw } cw = ""; inword = 0 }
    function resetcmd() { flushword(); nw = 0 }
    function cmdname(   i) {
      for (i = 1; i <= nw; i++) {
        if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
        if (w[i] ~ /^(\{|!|time|sudo|command|exec|nohup|then|do|else|env)$/) continue
        return w[i]
      }
      return ""
    }
    function isshell(name) { sub(/.*\//, "", name); return name ~ /^(bash|sh|zsh|dash|ksh)$/ }
    function shellarg(   name, i) {
      name = cmdname()
      if (name == "eval") return 1
      if (!isshell(name)) return 0
      for (i = 1; i <= nw; i++) if (w[i] ~ /^-[A-Za-z]*c[A-Za-z]*$/) return 1
      return 0
    }
    { s = s (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(s); i = 1; out = ""; nh = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out substr(s, i, 2); cw = cw substr(s, i + 1, 1); inword = 1; i += 2; continue }
        if (c == "#" && !inword) {
          while (i <= n && substr(s, i, 1) != "\n") i++
          continue
        }
        if (c == sq) {
          j = index(substr(s, i + 1), sq)
          if (!j) exit 2
          body = substr(s, i + 1, j - 1)
          if (shellarg()) out = out "\n" body "\n"
          else if (nw == 0 && !inword) out = out body
          else out = out " "
          cw = cw "Q"; inword = 1; i += j + 1; continue
        }
        if (c == "\"") {
          j = i + 1; body = ""; code = ""
          while (j <= n) {
            d = substr(s, j, 1)
            if (d == "\\") { body = body substr(s, j, 2); j += 2; continue }
            if (d == "\"") break
            if (d == "$" && substr(s, j + 1, 1) == "(") {
              depth = 1; k = j + 2
              while (k <= n && depth > 0) {
                e = substr(s, k, 1)
                if (e == "(") depth++
                else if (e == ")") depth--
                k++
              }
              if (depth > 0) exit 2
              code = code "\n" substr(s, j + 2, k - j - 3) "\n"
              body = body substr(s, j, k - j); j = k; continue
            }
            if (d == "`") {
              k = index(substr(s, j + 1), "`")
              if (!k) exit 2
              code = code "\n" substr(s, j + 1, k - 1) "\n"
              body = body substr(s, j, k + 1); j += k + 1; continue
            }
            body = body d; j++
          }
          if (j > n) exit 2
          if (shellarg()) out = out "\n" body "\n"
          else if (nw == 0 && !inword) out = out body
          else out = out " " code " "
          cw = cw "Q"; inword = 1; i = j + 1; continue
        }
        if (substr(s, i, 3) == "<<<") { flushword(); out = out " "; i += 3; continue }
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
          out = out " "; i = k; continue
        }
        if (c == "\n") {
          resetcmd(); out = out "\n"; i++
          for (h = 1; h <= nh; h++) {
            found = 0
            while (i <= n) {
              e = index(substr(s, i), "\n")
              line = e ? substr(s, i, e - 1) : substr(s, i)
              i = e ? i + e : n + 1
              cmp = line
              if (hs[h]) sub(/^\t+/, "", cmp)
              if (cmp == hd[h]) { found = 1; break }
              if (hsh[h]) out = out line "\n"
            }
            if (!found) exit 2
          }
          nh = 0; continue
        }
        if (c ~ /[;&|()`]/) { resetcmd(); out = out c; i++; continue }
        if (c ~ /[ \t]/) { flushword(); out = out c; i++; continue }
        cw = cw c; inword = 1; out = out c; i++
      }
      if (nh > 0) exit 2
      printf "%s", out
    }
  ' <<<"$cmd"
}

# Pipe para um shell executa o texto da esquerda: analisa tudo como código.
fallback=0
if grep -Eq '\|[[:space:]]*(sudo[[:space:]]+)?([^[:space:]]*/)?(bash|sh|zsh|dash|ksh)([[:space:]]|$|[;&|)])' <<<"$cmd"; then
  fallback=1
elif ! code=$(code_view); then
  fallback=1
fi
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

check_commit() {
  local dir=$1 branch
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
while IFS= read -r segment; do
  read -ra words <<<"$segment"
  (( ${#words[@]} )) || continue

  # Primeira palavra do comando, depois de atribuições e prefixos.
  k=0
  while (( k < ${#words[@]} )); do
    case ${words[k]} in
      [A-Za-z_]*=*|'{'|'!'|time|sudo|command|exec|nohup|then|do|else|env) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  # Sem separar o texto, procura o git em qualquer posição do comando.
  if (( fallback )); then
    while (( k < ${#words[@]} )) && [[ ${words[k]##*/} != git ]]; do k=$((k + 1)); done
  fi
  (( k < ${#words[@]} )) || continue

  if [[ ${words[k]} == cd ]]; then
    next=${words[k + 1]:-$HOME}
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
      -c) k=$((k + 2)) ;;
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
