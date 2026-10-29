# SPEC-24: Hook protect-main libera git commit em bash -c com aspas escapadas antes do subcomando

**Issue:** #24 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-10-29

## Contexto
O `hooks/protect-main.sh` trata como código o argumento de `bash -c`/`sh -c`, de `eval` e de here-string para shell. Para isso, a função `rawcode` do `code_view` troca as aspas por espaços (`gsub("[\"" sq "]", " ", t)`). Assim, `git -c user.name="t" commit` dentro desses textos vira `git -c user.name= t  commit`: o `-c` consome `user.name=`, o `t` passa a ser lido como subcomando e o `commit` nunca é reconhecido. A triagem confirmou cinco formas que fazem commit na `main` sem bloqueio:
- aspas escapadas em `bash -c "…"`;
- aspas duplas dentro de `bash -c '…'`;
- `eval '…'`;
- `eval "…"`;
- `bash <<< '…'`.

O modo de dúvida (fallback), usado quando o comando não pode ser separado, troca as aspas por espaços do mesmo jeito e tem a mesma brecha.

## Objetivo
O texto que roda como código num shell filho ou no `eval` é lido com as mesmas regras de aspas do comando principal. Um valor citado antes do subcomando volta a ser uma palavra só, e o `git commit`/`git push` na `main` volta a ser bloqueado nas cinco formas e no modo de dúvida.

## Comportamento esperado

### Segunda leitura do texto extraído
| Origem do texto | Como é preparado antes da segunda leitura |
|---|---|
| Entre aspas simples (`bash -c '…'`, `eval '…'`, `bash <<< '…'`) | Fica como está: entre aspas simples nada é escapado. |
| Entre aspas duplas (`bash -c "…"`, `eval "…"`, `bash <<< "…"`) | Desfaz os escapes de aspas duplas, como o shell faz: `\"` → `"`, `\\` → `\`, `` \` `` → `` ` ``, `\$` → `$`, e barra seguida de quebra de linha some. As outras barras ficam. |

O texto preparado é lido de novo pelo `code_view` com as mesmas regras do comando principal: aspas, `$(...)`, heredocs, `bash -c` aninhado, pipe para shell e os marcadores \001S, \001X e \001R. O resultado entra no lugar do texto, com os mesmos marcadores de hoje:
- `bash -c`, here-string e heredoc para shell abrem com \001X, de shell filho, que herda só as variáveis exportadas (#22);
- `eval` entra sem marcador, porque roda no shell atual.

**Limites:**
- **Aninhamento:** até 4 níveis de leitura (`bash -c` dentro de `bash -c`…). Acima disso, vale o modo de dúvida.
- **Segunda leitura falha** (aspas sem fechamento, `$(` sem par, heredoc sem fim): o comando inteiro passa para o modo de dúvida, que bloqueia.

### Modo de dúvida
Quando o `code_view` sai com 2, o hook usa o comando inteiro, sem separar o texto citado. Isso acontece com aspas sem fechamento, pipe para shell ou falha na segunda leitura. Nesse modo:
- as aspas são removidas, em vez de trocadas por espaço. Assim, `user.name="t"` vira `user.name=t`, uma palavra só;
- depois de achar o `git`, o hook procura `commit` ou `push` em qualquer palavra seguinte do mesmo comando simples. Se achar, confere o diretório e a branch como hoje.

### O que não muda
- As mensagens de bloqueio.
- O tratamento de texto citado fora desses casos: argumentos de `echo`, `gh … --body`, corpo de heredoc que não é para shell.
- As regras de diretório e variáveis da #18 e da #22.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com o `cwd` num repositório na `main`, estes comandos bloqueiam: `sh -c "git -c user.name=\"t\" commit -m y"`, `bash -c 'git -c user.name="t" commit -m y'`, `eval 'git -c user.name="t" commit -m y'`, `eval "git -c user.name=\"t\" commit -m y"`, `bash <<< 'git -c user.name="t" commit -m y'` e `bash -c "git -C \"<main>\" commit -m y"` a partir de uma feature. | unitário (`scripts/test-protect-main.sh`) |
| CA2 | As mesmas formas apontando para uma worktree de feature liberam, com o `cwd` no clone na `main`: `bash -c "git -C \"<wt>\" commit -m y"`, `bash -c 'git -C "<wt>" commit -m y'`, `eval 'git -C "<wt>" commit -m y'` e `bash <<< 'git -C "<wt>" commit -m y'`. | unitário |
| CA3 | Aninhamento: `bash -c "bash -c 'git -c a=\"b\" commit -m y'"` bloqueia na `main`. Um aninhamento acima de 4 níveis, com `git commit` no fundo, bloqueia pelo modo de dúvida. | unitário |
| CA4 | Texto continua sendo texto no shell filho: `bash -c 'echo "git commit -m x"'` e `bash -c "echo \"git push origin main\""` liberam na `main`. `bash -c "echo \$(git commit -m x)"` bloqueia, porque o `$(` chega ao filho. | unitário |
| CA5 | Modo de dúvida: na `main`, `git -c user.name="t" commit -m y; echo "x` (aspas sem fechamento) e `echo x \| bash; git -c k="v" commit -m y` bloqueiam. | unitário |
| CA6 | Os 103 casos atuais de `scripts/test-protect-main.sh` continuam passando, inclusive os da #22 sobre variáveis exportadas em `bash -c` e heredoc. Os casos novos entram no mesmo script, com rótulos `Q1` a `Q5`. | unitário |
| CA7 | Contra o hook da `main` atual (`git show origin/main:hooks/protect-main.sh`), o script falha nos cinco casos do CA1 da issue. | unitário |
| CA8 | Numa sessão com `claude --plugin-dir ~/projetos/fabrica` e o plugin instalado desligado, num repositório temporário na `main`, `sh -c "git -c user.name=\"t\" -c user.email=\"t@t\" commit --allow-empty -m y"` é bloqueado. | manual |
| CA9 | A `version` do plugin passa a 0.8.2. | manual |

## Fora de escopo
- O falso positivo, no lado seguro, de `bash -c "git -C $W commit"` em aspas duplas e de `bash <<EOF` sem aspas no delimitador. Nesses casos, o shell pai expande `$W` antes, mas o hook trata o texto como código do filho. O comportamento continua igual ao de hoje.
- Texto de `bash -c` montado por concatenação de pedaços (`bash -c "a"'b'`) ou vindo de variável (`bash -c "$CMD"`). Isso continua como hoje.
- As sugestões da #22: `W+=`, `for W in`, `export -n`, til entre aspas e a mensagem de `${W:-x}`.

## Desenho técnico
**Arquivos e módulos:**
- `hooks/protect-main.sh`:
  - **`code_view`:** passa a ler o comando de um argumento, não mais de `$cmd`. Assim, ele pode ser chamado de novo com o texto extraído.
  - **`rawcode` (awk):** em vez de trocar as aspas por espaço, emite uma linha `\001C<k><texto>`. O `<k>` é `S` para shell filho ou `E` para `eval`. O `<texto>` vem já sem os escapes de aspas duplas, quando for o caso, e codificado numa linha só: a quebra de linha e os separadores `;&|()` e crase viram caracteres de controle (`\006`, `\016` a `\023`).
    - O heredoc para shell continua emitindo as linhas do corpo como código, entre \001X e \001R, porque o corpo já chega sem aspas a desfazer.
  - **Nova função `expand_code <texto> <nível>`, em bash:** percorre a saída do `code_view` e troca cada linha `\001C…` pela saída do `code_view` sobre o texto decodificado, envolta em \001X…\001R quando é shell filho. Ela chama a si mesma até o nível 4. Se uma chamada sair com 2 ou passar do nível 4, ela sai com 2, e o hook usa o modo de dúvida.
  - **Modo de dúvida:**
    - `tr -d` remove as aspas, em vez de trocá-las por espaço;
    - no laço, com `fallback` ligado, o subcomando é a primeira palavra `commit` ou `push` depois do `git`.
- `scripts/test-protect-main.sh`: os casos dos CA1 a CA5, com os rótulos `Q1` a `Q5`.
- `.claude-plugin/plugin.json`: 0.8.1 → 0.8.2.

**Dados:** nenhum.

**Interfaces:** a entrada e a saída do hook não mudam.

**Decisões:**
- **Segunda leitura com o próprio `code_view`:** é o único jeito de as regras de aspas, subshells e heredocs valerem igual dentro e fora do `bash -c`. Alternativa descartada: um tratamento especial só para `\"` no `rawcode`, que corrigiria o caso da issue, mas deixaria as aspas duplas dentro de `bash -c '…'` e o `eval '…'`.
- **A expansão recursiva fica no bash, não no awk:** o awk do `code_view` é um laço único sobre uma string, e reentrar nele exigiria guardar toda a pilha de estado. Chamar o `code_view` de novo a partir do bash reaproveita o código sem mudar a estrutura. Alternativa descartada: recursão dentro do awk.
- **Limite de 4 níveis:** cobre os aninhamentos reais (`bash -c` dentro de `ssh … bash -c` e afins) e impede que um comando montado para isso multiplique as chamadas ao awk. Acima disso, vale a regra "bloquear na dúvida" da #18. Alternativa descartada: sem limite.
- **No modo de dúvida, procurar `commit`/`push` em qualquer palavra depois do `git`:** o modo de dúvida existe para bloquear quando não dá para separar o comando com segurança, e pular as opções globais por posição é justamente o que falha. Alternativa descartada: manter a leitura por posição, que deixa a brecha aberta nesse modo.

**Fontes da documentação:**
- Bash, regras de escape entre aspas duplas (`\` só escapa `$`, `` ` ``, `"`, `\` e a quebra de linha): conhecimento do modelo, não verificada. Será conferida com o `bash` local no script de testes, com `bash -c "printf '%s' \"a\\\\b\\\$c\""`.

**ADR:** nenhum.

## Testes
- **Casos novos:** `scripts/test-protect-main.sh` ganha os casos dos CA1 a CA5. Inclui uma checagem com o `bash` real de que a regra de escape de aspas duplas é a usada pelo hook.
- **Antes e depois:** o script roda contra o hook novo (CA6) e contra o hook da `main` (CA7).
- **Verificação manual do CA8:** uma sessão com `--plugin-dir` e `--settings '{"enabledPlugins":{"fabrica@fabrica":false}}'`, como na #22.
- **Tempo:**
  - o caso de 40 KB com texto citado da #22 deve continuar abaixo de 200 ms;
  - um comando com 20 `bash -c '…'` deve ficar abaixo de 500 ms, já que cada um abre um awk.

## Riscos e dúvidas
- **Mudança de comportamento no shell filho:** a segunda leitura muda como o código do shell filho é lido. Casos que hoje passam por acaso, como texto dentro de `bash -c` que parecia código depois de trocar as aspas, podem mudar de resultado. Os 103 casos atuais são a rede de segurança.
- **Desempenho:** cada texto extraído abre mais um processo `awk`. Comandos com muitos `bash -c` ficam mais lentos, por isso o limite de 500 ms do item "Testes".
- **Codificação numa linha:** a codificação do texto extraído precisa ser reversível com os mesmos caracteres de controle que o hook já usa (`\001` a `\004`) sem colisão. Se o texto original já tiver esses caracteres, o que é raro, o comando vai para o modo de dúvida.

## Histórico
- 2026-10-29: criação.
