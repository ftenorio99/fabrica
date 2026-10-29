# SPEC-22: Hook protect-main bloqueia commit em worktree quando o caminho vem numa variável

**Issue:** #22 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-10-29

## Contexto
O `hooks/protect-main.sh` resolve o diretório de `cd` e `git -C` com o texto literal. Em `W=/caminho/wt && cd $W && git commit`, o `$W` vira `<cwd>/$W`, que não existe. A linha `[ -d "$gitdir" ] || gitdir=$cwd` (`hooks/protect-main.sh:327`) então volta para o diretório da sessão. Com a sessão na `main`, o commit na worktree de outra branch é bloqueado por engano. Isso aconteceu no passo 5 do `/fabrica:backlog`, no kairo. O mesmo recuo para o `cwd` cria o erro oposto: numa sessão em branch de feature, `cd $W && git commit`, com `W` apontando para um clone na `main`, passa. A #18 decidiu "bloquear na dúvida", e esta spec aplica essa decisão às variáveis.

## Objetivo
O hook expande as variáveis que o próprio comando define antes de resolver `cd`, `git -C` e `--git-dir`. Quando a variável não pode ser resolvida, ele bloqueia commit e push na dúvida, em vez de conferir a branch do diretório da sessão.

## Comportamento esperado

### Variáveis conhecidas
O laço de comandos do hook mantém uma tabela de variáveis, que começa com `HOME` (do ambiente do hook) e é atualizada na ordem em que os comandos rodam:

| Forma | Efeito na tabela |
|---|---|
| `W=valor` sozinho, ou várias atribuições sem comando (`A=1 B=2`) | Define `W`. |
| `export W=valor`, `declare W=valor`, `local W=valor`, `readonly W=valor` | Define `W`. |
| `W=valor comando …` (atribuição como prefixo de um comando) | Não muda a tabela. O shell expande os argumentos antes da atribuição valer, então `W=/x git -C $W commit` usa o `W` anterior. |
| `unset W` | Remove `W`. |
| Atribuição dentro de `$(...)`, crases, `( ... )`, `bash -c` ou heredoc para shell | Vale só dentro desse trecho. Ao sair dele, a tabela volta ao estado anterior, como já acontece com o diretório. |
| Atribuição dentro de `eval` | Vale para os comandos seguintes, porque o `eval` roda no shell atual, como o `cd` hoje. |

**Valor da atribuição:**
- **Literal:** o texto, já sem as aspas.
- **Composto:** `$NOME` e `${NOME}` de variáveis conhecidas são substituídos (`B=$A/wt`). O `~` no início vira `$HOME`.
- **Desconhecido:** qualquer outro `$` no valor deixa a variável desconhecida. Isso inclui `$(...)`, crases, variável não definida, `${W:-x}`, `${W%/}`, `$1`, `$@`, `$?` e `$$`.

### Expansão em `cd`, `git -C` e `--git-dir`
- **Expansão:** `$NOME` e `${NOME}` são expandidos no argumento, sem aspas ou entre aspas duplas (`cd "$W/sub"`). Também valem `$PWD` (diretório atual do laço) e `$OLDPWD` (diretório anterior).
- **Aspas simples:** `$` entre aspas simples, ou escapado com `\$`, é literal e não é expandido. `cd '$W'` continua sendo o diretório de nome `$W`.
- **Diretório desconhecido:** o argumento tem `$` e alguma variável é desconhecida (ou tem uma das formas listadas acima). Depois de `cd` com argumento desconhecido, o diretório atual fica desconhecido até um `cd` com caminho absoluto ou `~` resolvido, ou até a saída do subshell em que estava. Um `cd` relativo a um diretório desconhecido continua desconhecido.

### Decisão
| Situação | Resultado |
|---|---|
| `git commit` ou `git push` com diretório resolvido | Como hoje: confere a branch desse diretório. |
| `git commit` ou `git push` com diretório desconhecido | Bloqueia na dúvida com a mensagem: "Não foi possível resolver o diretório do git commit/push (variável `<nome>`). Na dúvida, o comando foi bloqueado. Use o caminho literal em cd/git -C." Quando não houver um nome, a mensagem diz `$(...)` ou a forma encontrada. |
| Diretório desconhecido, mas sem `git commit` nem `git push` depois | Não bloqueia nada. |
| Caminho literal resolvido que ainda não existe (ex.: `mkdir x && cd x && git init && git commit`) | Mantém o comportamento atual (volta para o `cwd`). Esta issue não muda esse caso. |

As mensagens de bloqueio que já existem não mudam.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Os casos da tabela da issue, com uma worktree na branch `feature` e o clone na `main` como `cwd`: `W=<wt> && cd $W && git commit` e `W=<wt>; git -C $W commit` liberam; `cd <wt> && git commit` e `git -C <wt> commit` continuam liberando; `git commit` no clone continua bloqueando. | unitário (`scripts/test-protect-main.sh`) |
| CA2 | As formas resolvidas liberam numa worktree de feature: `${W}`, `"$W"`, `"$W/sub"` (com `sub` existente), `export W=…`, `B=$A/wt` encadeado, `W=~/…` e `$HOME/…`, e `--git-dir $W/.git`. | unitário |
| CA3 | A variável que aponta para um repositório na `main` bloqueia, a partir de um `cwd` em branch de feature: `W=<main>; cd $W && git commit`, `git -C $W commit` e `W=<main>; cd $W && git push`. | unitário |
| CA4 | Diretório desconhecido antes de commit ou push bloqueia com a mensagem de dúvida, mesmo com o `cwd` em branch de feature: `cd $NAO_DEFINIDA && git commit`, `W=$(pwd); cd $W && git commit`, `` W=`pwd`; git -C $W commit ``, `cd ${W:-x} && git commit` e `cd $1 && git push`. Já `cd $NAO_DEFINIDA && ls` não bloqueia. | unitário |
| CA5 | O escopo é respeitado: `W=<wt> git -C $W commit` (prefixo) bloqueia na dúvida; `(W=<wt>); cd $W && git commit` bloqueia na dúvida; `eval 'W=<wt>'; cd $W && git commit` libera; `cd '$W' && git commit` no clone na `main` bloqueia como hoje (literal, sem expansão); `unset W` depois de `W=<wt>` torna `W` desconhecida. | unitário |
| CA6 | Os 59 casos atuais de `scripts/test-protect-main.sh` continuam passando, e os casos novos entram no mesmo script. | unitário |
| CA7 | Contra o hook da `main` atual (`git show origin/main:hooks/protect-main.sh`), o script falha pelo menos nos dois falsos positivos do CA1 e no caso de `cwd` em feature do CA3. | unitário |
| CA8 | Numa sessão com `claude --plugin-dir ~/projetos/fabrica` e o plugin instalado desligado, com uma worktree de feature e a sessão no clone na `main`, `W=<wt> && cd $W && git commit --allow-empty -m x` roda, e `git commit --allow-empty -m x` no clone é bloqueado. | manual |
| CA9 | A `version` do plugin passa a 0.8.1. | manual |

## Fora de escopo
- O caminho 2 da issue (pedir caminho literal nas skills): com a expansão no hook, ele deixa de ser necessário.
- Variáveis definidas em chamadas anteriores do Bash ou no perfil do shell, exceto `HOME`: o estado do shell não persiste entre chamadas, e elas contam como desconhecidas.
- Expansões além de `$NOME` e `${NOME}`: `${W:-x}`, `${W%/}`, arrays, `$((...))`, aritmética e globs. Todas contam como desconhecidas.
- Funções de shell, `source`/`.` e `read W`.
- Variáveis em outros pontos do comando (ex.: `git push origin $B`), já que a decisão do push continua usando o texto literal dos argumentos.
- Caminho literal que ainda não existe (ver a tabela "Decisão").

## Desenho técnico
**Arquivos e módulos:**
- `hooks/protect-main.sh`:
  - **`code_view` (awk):** dentro de aspas simples e em `\$`, troca o `$` por um marcador novo (`\003`), para o laço não expandir esse `$`. O laço devolve o `$` depois da expansão.
  - **Laço de comandos:**
    - `declare -A vars` com `HOME`;
    - a detecção de comando só de atribuições e de `export`/`declare`/`local`/`readonly`/`unset`;
    - uma função `expand <texto>`, que devolve o texto expandido ou sai com erro e o nome da variável desconhecida;
    - `resolve` e `from_git_dir` passam a receber o texto expandido;
    - um estado `curdir_unknown` (com o motivo), salvo e restaurado nos marcadores `\001S`/`\001R` junto com `curdir`, `prevdir` e uma cópia da tabela de variáveis;
    - antes de `check_commit` e `check_push`, se o diretório for desconhecido, `deny` com a mensagem de dúvida.
  - **Cabeçalho:** o comentário do topo ganha uma linha sobre variáveis.
- `scripts/test-protect-main.sh`: uma worktree de teste (`git worktree add -b feature`) a partir do repositório `main`, e os casos dos CA1 a CA5, rotulados com o CA.
- `.claude-plugin/plugin.json`: 0.8.0 → 0.8.1.

**Dados:** nenhum.

**Interfaces:** a entrada e a saída do hook não mudam (JSON do PreToolUse e `permissionDecision: deny`). Só entra uma mensagem de bloqueio nova.

**Decisões:**
- **Expandir só variáveis definidas no próprio comando, mais `HOME`:** o hook não enxerga o estado do shell da sessão, que não persiste entre chamadas. Usar o ambiente do processo do hook arriscaria um valor diferente do que o shell real teria. Alternativa descartada: expandir com o ambiente do hook, que pode divergir do shell da sessão.
- **Diretório desconhecido bloqueia na dúvida**, conforme a decisão (a) da #18. Isso fecha o falso negativo de hoje (`cd $W && git commit` a partir de uma branch de feature). Alternativa descartada: manter o recuo para o `cwd`, que é exatamente o que causa o falso positivo e o falso negativo.
- **Prefixo `W=x comando` não define a variável para os argumentos do mesmo comando:** é a semântica do bash. Alternativa descartada: tratar o prefixo como atribuição, o que abriria `W=<wt> git -C $W commit` liberando quando o shell real usaria outro valor.
- **Marcador `\003` para `$` literal:** é o único jeito de distinguir `'$W'` de `"$W"` depois que o `code_view` junta o texto citado numa palavra. Alternativa descartada: expandir também entre aspas simples, o que liberaria `cd '$W'; git commit` com o shell real fazendo o commit no `cwd`.
- **Caminho literal inexistente continua voltando para o `cwd`:** bloquear esse caso na dúvida quebraria `mkdir x && cd x && git init && git commit`, a exceção do commit inicial. Ele fica para outra issue, se aparecer.

**Fontes da documentação:**
- Bash (expansão de parâmetros, atribuições como prefixo de comando): conhecimento do modelo, não verificada. A semântica do prefixo (`W=x cmd $W` usa o `W` anterior) será conferida com o `bash` local no script de testes.

**ADR:** nenhum.

## Testes
- **`scripts/test-protect-main.sh`:**
  - cria a worktree de feature junto dos repositórios atuais;
  - acrescenta os casos dos CA1 a CA5;
  - confere com o `bash` real a semântica do prefixo: `W=a; W=b echo $W` imprime `a`;
  - roda todos os casos (CA6) com `bash scripts/test-protect-main.sh`;
  - roda também contra o hook da `main` (CA7): `bash scripts/test-protect-main.sh <hook antigo>`.
- **Verificação manual do CA8:** uma sessão com `--plugin-dir` e `--settings '{"enabledPlugins":{"fabrica@fabrica":false}}'`, como na #18.
- **Tempo:** o caso de 20 KB da #18 continua abaixo de 200 ms.

## Riscos e dúvidas
- **Bloqueios novos:** a dúvida pode bloquear comandos que hoje passam por acaso. Por exemplo, `cd "$(git rev-parse --show-toplevel)" && git commit` numa branch de feature passava, porque o recuo para o `cwd` acertava. A mensagem orienta a usar o caminho literal. O risco é aceito pela decisão (a) da #18.
- **Tamanho do hook:** o hook passa de 334 linhas. A tabela de variáveis no salvar e restaurar dos subshells precisa de cópia de array associativo em bash, que é verboso. Se ficar complexo demais, o desvio vai para o PR.
- **`\$` sem aspas:** hoje o `code_view` trata `\$` como texto comum. Marcá-lo com `\003` também precisa preservar o comportamento atual dos outros escapes.

## Histórico
- 2026-10-29: criação.
- 2026-10-29: aprovada pelo usuário.
