# SPEC-18: Hook protect-main dá falso positivo com comandos de várias linhas e textos citados

**Issue:** #18 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-10-28

## Contexto
O `hooks/protect-main.sh` roda antes de todo comando Bash onde o plugin está instalado e bloqueia commit e push na `main`. Hoje ele procura `git commit` e `git push` no texto inteiro do comando. Por isso bloqueia o push de uma branch comum quando uma linha da mensagem de commit termina em "main", e bloqueia na `main` um `gh issue create --body "..."` que só cita `git commit`. Os dois casos aconteceram na #14 e na criação da própria #18. Na triagem, o usuário escolheu **bloquear na dúvida**: o hook ignora o texto passado a comandos que não são shell, mas continua analisando o que vai para `bash -c`, `sh -c` e `eval`.

## Objetivo
O hook decide com base nos comandos `git commit` e `git push` que vão de fato rodar: não bloqueia mais texto citado nem o push de uma branch comum, e continua bloqueando commit e push na `main`, inclusive quando houver dúvida.

## Comportamento esperado
O hook passa a ler o comando em duas etapas:

1. **Separar código de texto.** O conteúdo entre aspas simples ou duplas e o corpo de heredocs vira texto e é ignorado, com estas exceções, analisadas como código:
   - o argumento de `bash -c`, `sh -c`, `zsh -c` e de `eval`;
   - `$(...)` e crases dentro de aspas duplas, que o shell executa;
   - o corpo de um heredoc entregue a um shell (`bash <<EOF`, `sh <<EOF`).
2. **Dividir em comandos simples.** O código é dividido em comandos nos separadores `;`, `&&`, `||`, `|`, `&` e quebra de linha. Um comando é `git commit` ou `git push` quando começa por `git`, opcionalmente depois de atribuições de variável (`FOO=1 git ...`), com opções globais antes do subcomando (`-C <dir>`, `-c <chave=valor>` e opções sem argumento como `--no-pager`). Os argumentos do push são só os daquele comando.

O diretório usado para descobrir a branch em checkout é, nesta ordem: o `-C <dir>` do próprio comando git, o destino do último `cd <dir>` antes dele no mesmo comando Bash ou o `cwd` do Claude Code.

| Situação | Resultado |
|---|---|
| `git commit` com a `main` (ou `master`) em checkout | bloqueia, exceto no primeiro commit de um repositório sem commits |
| `git push` com destino `main`/`master` nos argumentos daquele push (ex.: `origin main`, `HEAD:main`) | bloqueia, exceto quando a `main` ainda não existe no remoto |
| `git push` sem destino explícito, com a `main` em checkout | bloqueia, com a mesma exceção |
| Comando de várias linhas numa branch comum, com mensagem `-m` cuja linha termina em "main", seguido de `git push origin <branch>` | libera |
| `git commit` ou `git push` só dentro de aspas passadas a outro comando (`gh ... --body "..."`, `echo '...'`, `-m "..."`) | libera |
| `git commit` ou `git push` no corpo de um heredoc entregue a um comando que não é shell (`gh issue comment --body-file - <<'EOF'`) | libera |
| `bash -c "git push origin main"`, `sh -c '...'`, `eval "git commit ..."` com a `main` alvo | bloqueia |
| `"$(git commit -m x)"` ou crases dentro de aspas duplas, com a `main` em checkout | bloqueia |
| Heredoc entregue a um shell (`bash <<EOF` … `git push origin main` … `EOF`) | bloqueia |
| Aspas sem fechamento ou outro texto que o hook não consegue separar | analisa o comando inteiro como código, como hoje (bloqueia na dúvida) |

As mensagens de bloqueio continuam as atuais.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Os dois casos da issue passam: push de branch comum num comando de várias linhas cuja mensagem tem uma linha terminando em "main", e `gh issue create --body "exemplo: git commit -m x"` com a `main` em checkout. | unitário |
| CA2 | Texto citado não bloqueia: `echo 'git push origin main'` e um heredoc com `git commit` entregue a `gh issue comment --body-file -`, ambos com a `main` em checkout, são liberados. | unitário |
| CA3 | Continuam bloqueados: `git commit -m x` na `main`; `git push origin main` e `git push origin HEAD:main` numa branch comum; `git push` com a `main` em checkout; `git status; git push origin main` e o push na segunda linha de um comando de várias linhas. | unitário |
| CA4 | Bloqueio na dúvida: `bash -c "git push origin main"`, `sh -c 'git push origin main'`, `eval "git push origin main"`, `echo "$(git commit -m x)"` na `main`, `bash <<EOF` com `git push origin main` e um comando com aspas sem fechamento contendo `git push origin main` são bloqueados. | unitário |
| CA5 | Diretório certo: `cd <repo na main> && git commit -m x` e `git -C <repo na main> commit -m x` rodados de uma branch comum são bloqueados, e `git -C <repo numa branch comum> push origin feat/x` rodado da `main` é liberado. | unitário |
| CA6 | As exceções continuam: primeiro commit de um repositório sem commits e primeiro push da `main` para um remoto sem `main` são liberados. | unitário |
| CA7 | `scripts/test-protect-main.sh` roda todos os casos de CA1 a CA6, imprime uma linha por caso e sai com 0 só se todos passarem. Rodado contra o hook da `main` atual, ele falha pelo menos nos casos de CA1, CA2 e no `git -C` de CA5. | manual |
| CA8 | `version` do plugin sobe um patch em relação à `main` no momento do merge (0.7.0 → 0.7.1, se nada entrar antes). | manual |

## Fora de escopo
- Interpretar shell por completo: aliases, funções, `source` de scripts, variáveis que montam o comando (`$CMD`), `xargs`, `find -exec`, subshells `( ... )` com `cd` dentro. Nesses casos vale o que a leitura em duas etapas der; nada disso é coberto pelos testes.
- Mudar quais branches são protegidas (`main` e `master`) ou as mensagens de bloqueio.
- Proteção da `main` pelo próprio GitHub (branch protection).
- Criar `make test` na fábrica.

## Desenho técnico
**Arquivos e módulos:**
- `hooks/protect-main.sh`: troca a regex sobre o texto inteiro por duas funções:
  - `code_view`: recebe o comando e devolve só o código, com o texto citado trocado por espaços e as exceções da etapa 1 mantidas;
  - `git_commands`: divide o código em comandos simples e emite, para cada `git commit` ou `git push`, o subcomando, o diretório efetivo e os argumentos.

  As regras de bloqueio e as exceções do commit inicial e do primeiro push são aplicadas a cada comando emitido. Se a separação falhar (aspas sem fechamento), o comando inteiro é analisado como código.
- `scripts/test-protect-main.sh` (novo, executável): cria num diretório temporário os repositórios de teste:
  - um repositório com commit, com a `main` em checkout e uma branch `feat/x`;
  - um clone dele na `feat/x`;
  - um repositório sem commits;
  - um remoto vazio, sem `main`.

  Para cada caso, monta o JSON de entrada (`tool_input.command`, `cwd`), roda o hook e confere se a saída tem `"permissionDecision": "deny"`. Não acessa a rede nem o GitHub.
- `.claude-plugin/plugin.json`: `version` 0.7.0 → 0.7.1.

**Dados:** nenhum.

**Interfaces:**
- Entrada e saída do hook não mudam: JSON do PreToolUse na entrada; na saída, o JSON de `deny` ou nada (sai com 0).
- `scripts/test-protect-main.sh [caminho do hook]`: por padrão, testa o `hooks/protect-main.sh` do repositório. O argumento permite rodar contra outra versão (CA7). Sai com 0 se todos os casos passarem.

**Decisões:**
- **Separar código de texto com um leitor de aspas e heredocs escrito no próprio hook**, em bash e `awk`, que já são usados, além do `jq`. Resolve os dois casos da issue sem parser externo. Alternativa descartada: um parser de shell de verdade (ex.: `shfmt --to-json`), que seria dependência nova em toda máquina com o plugin.
- **Exceções analisadas como código** (`bash -c`, `sh -c`, `zsh -c`, `eval`, `$(...)` e crases em aspas duplas, heredoc para shell), conforme a escolha (a) da triagem. Alternativa descartada: ignorar todo texto citado, opção (b), recusada pelo usuário.
- **Reconhecer `git -C <dir>` e usar esse diretório para descobrir a branch.** Hoje `git -C <dir> push` nem é detectado, porque a regex só aceita opções sem argumento antes do subcomando. Isso abre um buraco na proteção que a issue quer manter. Alternativa descartada: deixar como está e abrir outra issue, o que manteria o buraco aberto.
- **Acompanhar o `cd` em qualquer posição do comando**, não só no início. A divisão em comandos simples já fornece essa informação. Alternativa descartada: manter só o `cd` do início, que erraria o diretório em `git status; cd ../outro && git commit`.
- **Testes num script shell próprio, sem framework** (ex.: bats). A fábrica não tem `make test`, e o script roda com o que o hook já exige. Alternativa descartada: bats, que seria dependência nova só para testes.
- **Versão sobe um patch**, porque é uma correção sem mudança de interface. Alternativa descartada: subir um minor, como na #14, que adicionou funcionalidade.

**Fontes da documentação:**
- bash e jq 1.8.1: sem decisão de biblioteca nova. A sintaxe de aspas, heredoc, `$(...)` e separadores segue o manual do bash (`man bash`, seções QUOTING e Here Documents), a conferir na implementação.

**ADR:** nenhum (a mudança vale só para o hook do próprio plugin).

## Testes
A fábrica não tem `make test`. A verificação é o `scripts/test-protect-main.sh`, rodado à mão e registrado no PR.
- **CA1 a CA6:** um caso por linha das tabelas acima, cada um com o comando, o `cwd` (repositório na `main`, na `feat/x`, sem commits) e o resultado esperado (`deny` ou liberado). Os casos do primeiro push usam o remoto local vazio, sem rede.
- **CA7:** rodar `scripts/test-protect-main.sh` contra o hook novo (tudo passa) e contra `git show origin/main:hooks/protect-main.sh` salvo num arquivo temporário (falham os casos de CA1, CA2 e o `git -C` de CA5).
- **Verificação manual no Claude Code:** com `claude --plugin-dir` na branch, rodar um `gh issue comment` com `--body` citando `git commit`, com a sessão na `main`, e conferir que não é bloqueado. Rodar `git push origin main` numa branch comum e conferir que é bloqueado.
- **CA8:** ler o `plugin.json`.

## Riscos e dúvidas
- **Regressão silenciosa:** se a nova leitura liberar algo que deveria bloquear, a `main` fica sem proteção sem aviso. Os casos de bloqueio de CA3 a CA5 existem para pegar isso, e o fallback para aspas sem fechamento é bloquear na dúvida.
- **Tempo de execução:** o hook roda em todo comando Bash que cita `git`, com limite de 15 s em `hooks/hooks.json`. Ler caractere por caractere em bash puro pode ficar lento em comandos longos. Se ficar acima de 1 s num comando de 10 KB, a leitura vai para o `awk`.
- **Heredoc com aspas no delimitador** (`<<'EOF'`, `<<"EOF"`) e com `<<-`: o leitor precisa reconhecer as três formas para não tratar o corpo como código.
- **Ordem de merge** com outros PRs que mexem na `version` (ex.: a #16).

## Histórico
- 2026-10-28: criação.
- 2026-10-28: aprovada.
