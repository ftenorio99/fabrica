# SPEC-182: cada issue em andamento roda na própria worktree

**Issue:** #182 · **PRD:** nenhuma funcionalidade específica (infraestrutura da fábrica; base das issues #16 e #99) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-18

## Contexto
As etapas `spec` e `implementar` fazem `git switch` no próprio clone (`skills/spec/SKILL.md` passo 2, `skills/implementar/SKILL.md` passo 2), e o `revisar` supõe que o clone já está na branch da issue. Com duas sessões no mesmo clone, uma troca a branch da outra: entre 2026-11-17 e 2026-11-18 isso aconteceu três vezes no `~/projetos/fabrica` (a #162 commitou na branch da #176; o ajuste do PR #180 encontrou o clone na branch de outras duas issues). Rodar várias issues ao mesmo tempo, e mais tarde um orquestrador (#16, #99), exige isolamento por issue. Só a `backlog` já usa uma worktree temporária.

## Objetivo
Cada etapa que mexe na branch de uma issue trabalha numa worktree própria da issue, em `<clone>/.worktrees/<nº>`, criada e removida pela fábrica, e o clone principal nunca troca de branch por causa de uma etapa.

## Comportamento esperado
**Script novo `scripts/issue-worktree.sh`**, com três subcomandos. `<clone>` é a worktree principal do repositório, achada a partir de `git rev-parse --path-format=absolute --git-common-dir`, e não a pasta de onde o script é chamado. Assim o resultado é o mesmo rodando no clone ou dentro de uma worktree.

1. `ensure <nº> <branch>`: imprime na última linha o caminho absoluto `<clone>/.worktrees/<nº>`, pronto para uso.

   | Situação | O que acontece | Saída |
   |---|---|---|
   | `<clone>/.worktrees/<nº>` existe e está na `<branch>` | reusa, sem mexer em nada | 0 |
   | `<clone>/.worktrees/<nº>` existe em outra branch | não mexe; mensagem com a branch encontrada | 3 |
   | `<branch>` está em uso noutra pasta (o clone principal ou outra worktree) | não mexe; mensagem com a pasta e o pedido para trocá-la de branch | 4 |
   | já há 3 ou mais worktrees de outras issues em `<clone>/.worktrees/` e a desta não existe | não cria; mensagem com as issues que ocupam as worktrees | 5 |
   | `<branch>` existe só local | `git worktree add --relative-paths <caminho> <branch>` | 0 |
   | `<branch>` existe só em `origin` | cria a branch local rastreando `origin/<branch>` na worktree nova | 0 |
   | `<branch>` não existe | `git fetch origin` e cria a branch a partir de `origin/main` na worktree nova | 0 |
   | `<nº>` não é inteiro positivo, ou falta argumento | não mexe; mensagem de uso | 2 |

   Ao **criar** (não ao reusar), o script também:
   - garante a linha `/.worktrees/` no `.git/info/exclude` do clone, sem duplicá-la;
   - copia do clone para a worktree os arquivos que casam com o `<clone>/.worktreeinclude` (sintaxe do `.gitignore`) **e** são ignorados pelo git, mantendo o caminho relativo. Sem `.worktreeinclude`, não copia nada. Um arquivo rastreado nunca é copiado. Na reutilização nada é copiado nem sobrescrito.
2. `clean`: para cada worktree em `<clone>/.worktrees/`, lê o PR da branch (`gh pr list --head <branch> --state all --json number,state,headRefOid`, o mais recente). Imprime uma linha por worktree e sai com 0; se o `gh` falhar, não remove nada e sai com 1.

   | Situação da worktree | Ação | Linha |
   |---|---|---|
   | PR `MERGED` ou `CLOSED`, `git status --porcelain` vazio e o `HEAD` igual ao `headRefOid` do PR ou ancestral dele | `git worktree remove`, `git branch -D <branch>` | `removida <nº> <branch>` |
   | PR `MERGED` ou `CLOSED`, com mudança não commitada ou commit que não está no PR | mantém | `mantida <nº> <branch> trabalho-local` |
   | PR `OPEN`, ou sem PR | mantém | `mantida <nº> <branch> em-andamento` |

   No fim, roda `git worktree prune`. Uma pasta em `.worktrees/` que o git não reconhece como worktree fica intocada, com a linha `mantida <nome> - desconhecida`.
3. `list`: só leitura, sem `gh`. Uma linha por worktree em `<clone>/.worktrees/`: `<nº> <branch> <caminho>`.

**Etapas**
- **`spec`** (passo 2) e **`implementar`** (passo 2, inclusive o atalho): em vez de `git switch`, rodam `scripts/issue-worktree.sh clean` e depois `ensure <nº> <branch>`, e guardam o caminho impresso como `<wt>`. Todo comando git, `make` e `gh pr` da etapa roda com `cd <wt> && …` no mesmo comando, e todo arquivo lido ou escrito usa caminho absoluto dentro de `<wt>`. O `rebase origin/main` do `implementar` acontece em `<wt>`.
- Saída 3, 4 ou 5 do `ensure` faz a etapa parar sem commit, dizendo no chat a mensagem do script. A saída 5 é o limite de worktrees: a etapa não comenta na issue (como o limite de 3 em andamento hoje), e no `avancar` conta como "sem avanço".
- **`revisar`**: quando rodada sozinha, faz o mesmo `ensure` (reusa a worktree que o `implementar` criou) e opera em `<wt>`. Seguida a partir do `implementar`, usa o `<wt>` dele. O prompt do subagente `revisor` passa a levar o caminho `<wt>`, e o revisor lê e roda as verificações ali.
- **`avancar`**: no passo 1, antes de coletar, roda `clean` no repositório atual e põe as linhas `removida` e `mantida … trabalho-local` nos alertas do relatório.
- **`status`**: quando roda dentro de um clone, chama `list` e `gh pr list` (só leitura) e mostra nos alertas cada worktree cujo PR está `MERGED` ou `CLOSED`, com o texto "`<repo>`: a worktree da #<nº> sobrou depois do PR fechado; a próxima etapa ou o `/fabrica:avancar` a remove". Fora de um clone, não mostra nada de worktree.
- **Clone principal:** nenhuma etapa roda `git switch`, `git checkout <branch>` ou `git pull` no clone principal. Ele fica na branch em que o usuário o deixou.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `ensure 7 feat/7-x` num repositório sem a branch cria `<clone>/.worktrees/7` na branch `feat/7-x` a partir de `origin/main`, imprime o caminho absoluto na última linha e sai com 0; o `HEAD` do clone principal não muda | unitário (`scripts/test-issue-worktree.sh`, repositório temporário com remote local) |
| CA2 | Um segundo `ensure 7 feat/7-x` reusa a worktree: mesmo caminho, saída 0, e um arquivo não commitado criado nela continua lá | unitário |
| CA3 | Chamado de dentro de `<clone>/.worktrees/7`, `ensure 8 feat/8-y` cria `<clone>/.worktrees/8`, e não `<clone>/.worktrees/7/.worktrees/8` | unitário |
| CA4 | Com `feat/9-z` só em `origin`, `ensure 9 feat/9-z` cria a branch local rastreando `origin/feat/9-z`, com o commit do remoto | unitário |
| CA5 | Com `feat/7-x` no clone principal, `ensure 7 feat/7-x` sai com 4, cita o caminho do clone e não cria pasta; com `.worktrees/7` em outra branch, sai com 3 | unitário |
| CA6 | Com 3 worktrees de outras issues em `.worktrees/`, `ensure` de uma 4ª sai com 5 e não cria nada; o `ensure` de uma das 3 continua saindo com 0 | unitário |
| CA7 | `ensure` com número não inteiro (`abc`, `0`, `-1`) ou sem branch sai com 2, sem criar nada | unitário |
| CA8 | Ao criar, a linha `/.worktrees/` aparece uma única vez no `.git/info/exclude`, mesmo depois de dois `ensure` de issues diferentes, e o `git status` do clone não lista `.worktrees/` | unitário |
| CA9 | Com `.worktreeinclude` contendo `.env`, e `.env` ignorado no clone, a worktree nova recebe o `.env`; um arquivo rastreado que casa com o padrão não é copiado; numa reutilização, um `.env` alterado na worktree não é sobrescrito | unitário |
| CA10 | O `.git` da worktree e o `gitdir` em `.git/worktrees/<nº>` usam caminhos relativos: depois de mover o clone inteiro para outra pasta, `git -C <novo>/.worktrees/7 status` funciona sem `git worktree repair` | unitário |
| CA11 | `clean` remove a worktree e a branch local de uma issue com PR `MERGED` e worktree limpa, mantém a de PR `MERGED` com arquivo não commitado (`trabalho-local`), a de PR `OPEN` e a sem PR (`em-andamento`), e roda `git worktree prune` | unitário, com um `gh` falso no `PATH` |
| CA12 | Com o `gh` falso saindo com erro, `clean` sai com 1 e não remove nenhuma worktree | unitário, com um `gh` falso |
| CA13 | `list` imprime `<nº> <branch> <caminho>` de cada worktree e não chama o `gh` | unitário, com um `gh` falso que falha se chamado |
| CA14 | Os hooks do git da fábrica e o `protect-main.sh` funcionam numa worktree criada pelo `ensure`: commit e push da branch de feature passam, e `git push origin HEAD:main` feito a partir dela é recusado | unitário (caso novo em `scripts/test-protect-main.sh`) |
| CA15 | Duas sessões, em duas issues de teste do repositório, rodam `/fabrica:spec` ao mesmo tempo: cada spec é commitada na branch da própria issue, dentro da própria worktree, e o `HEAD` do clone principal não muda em nenhum momento | manual — `claude --plugin-dir <clone>` na branch, com duas issues de teste no próprio repositório, fechadas no fim com um comentário dizendo que eram teste |
| CA16 | Depois do merge do PR de uma das issues de teste do CA15, rodar `/fabrica:avancar` remove a worktree e a branch local dela, e o relatório mostra a linha `removida` | manual — mesmo caminho do CA15, com o PR de teste mergeado num repositório de teste ou fechado sem merge (o `clean` trata `CLOSED` igual a `MERGED`) |
| CA17 | Nenhum `SKILL.md` das etapas `spec`, `implementar` e `revisar` manda rodar `git switch` ou `git checkout` de branch no clone principal | unitário (`grep` no `scripts/test-issue-worktree.sh`) |

## Fora de escopo
- Portas de servidor de dev e de banco distintas por worktree (caso do kairo): vira issue própria, porque depende da stack de cada projeto.
- Instalar as dependências do projeto na worktree: o passo "Ambiente" do `implementar` continua como está; a worktree nova não tem `node_modules`, e o `make` do projeto decide como instalar.
- O orquestrador e as ondas com subagentes paralelos (#16, #99) e o dispatcher no GitHub Actions. No Actions o script funciona igual (o checkout do job é um clone comum), sem caso especial.
- O `/fabrica:limpar` separado e a remoção da worktree no momento do merge: o merge é sempre do usuário, fora de qualquer etapa.
- Migrar as issues que hoje estão com a branch no clone principal: o `ensure` sai com 4 e o usuário troca o clone de branch uma vez.
- O adaptador do OpenCode (`opencode/server.ts`): ele lê o texto das skills do repositório, então herda a mudança sem alteração.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/issue-worktree.sh` (novo): `ensure`, `clean` e `list`, como acima. Sem dependência além de `git`, `gh` (só no `clean`) e `jq`.
- `scripts/test-issue-worktree.sh` (novo): CA1 a CA13 e CA17, com repositório temporário, remote local (`git init --bare`) e um `gh` falso no `PATH`.
- `scripts/test-protect-main.sh`: caso novo do CA14.
- `skills/spec/SKILL.md` passo 2, `skills/implementar/SKILL.md` passo 2, `skills/revisar/SKILL.md` passo 1 e o trecho que monta o prompt do revisor, `skills/avancar/SKILL.md` passo 1 e relatório, `skills/status/SKILL.md` coleta e alertas.
- `agents/revisor.md`: passa a receber e usar o caminho da worktree.
- `skills/status/estados.md`: a regra da branch da issue cita a worktree `<clone>/.worktrees/<nº>`. Labels, marcadores e estados não mudam.
- Manual: `docs/fluxo.md` (seção nova "Uma worktree por issue"), `docs/guias/isolamento-do-agente.md` (a VM do `sbx` já monta o clone inteiro, e os caminhos relativos do CA10 fazem a worktree funcionar lá dentro), `docs/solucao-de-problemas.md` (saídas 3, 4 e 5 do `ensure`; o `gh pr merge --delete-branch` rodado no clone avisando que não apagou a branch local presa na worktree, que o `clean` apaga depois), `docs/glossario.md` (worktree da issue).
- `AGENTS.md`: o script e o teste novos na lista de `scripts/`.
- `.claude-plugin/plugin.json`: `version` 0.40.0.

**Dados:** nenhum. Estado local: as pastas em `<clone>/.worktrees/` e a linha no `.git/info/exclude`.

**Interfaces:**
- `scripts/issue-worktree.sh ensure <nº> <branch>` → caminho absoluto na última linha de stdout; mensagens no stderr; saídas 0, 2, 3, 4, 5.
- `scripts/issue-worktree.sh clean` → linhas `removida <nº> <branch>` e `mantida <nº|nome> <branch|-> <motivo>`; saídas 0 e 1.
- `scripts/issue-worktree.sh list` → linhas `<nº> <branch> <caminho>`; saída 0.
- Variável `FABRICA_GH_BIN` (padrão `gh`) para os testes trocarem o `gh`, no mesmo estilo do `FABRICA_CLAUDE_BIN` do `stage-model.sh`.

**Decisões:**
- Local `<clone>/.worktrees/<nº>`, ignorado pelo git (recomendação da triagem) — é um caminho previsível que o `status` e o usuário acham, fica dentro da pasta que a VM do `sbx` monta e dentro da pasta de trabalho da sessão do Claude Code, onde o `cd` vale entre comandos. Alternativa descartada: `../<repo>-<nº>` ao lado do clone, que fica fora da montagem do `sbx` e da pasta da sessão.
- Ignorar pelo `.git/info/exclude` do clone, e não pelo `.gitignore` — vale para todo projeto sem commit em cada um. Alternativa descartada: acrescentar `/.worktrees/` ao `.gitignore` de cada projeto, que exige um PR por repositório.
- Quem cria e reusa (recomendação da triagem): a primeira etapa que precisa da branch (`spec`, ou `implementar` no atalho) cria; as seguintes reusam — a triagem não toca em branch. Alternativa descartada: criar sempre na triagem.
- Quem remove (recomendação da triagem, com ajuste): nenhuma etapa faz merge na fábrica (o merge é do usuário), então a remoção é o `clean`, rodado no começo do `spec`, do `implementar` e do `avancar`, e o `status` aponta as worktrees que sobraram. Alternativa descartada: um `/fabrica:limpar` separado, que o usuário teria que lembrar de rodar.
- Script próprio em vez do `claude --worktree` (recomendação da triagem: verificar o nativo antes) — o nativo cria em `.claude/worktrees/<nome>` numa branch `worktree-<nome>`, fora do padrão `<tipo>/<nº>-<descricao>`, remove a worktree limpa ao fim da sessão (a worktree da issue precisa durar da spec ao merge) e não existe no OpenCode nem no Antigravity. O hook `WorktreeCreate` mudaria o caminho, mas não o tempo de vida. Alternativa descartada: `claude --worktree` com hooks `WorktreeCreate`/`WorktreeRemove`.
- Arquivos fora do git pelo `.worktreeinclude` — é o mesmo formato que o Claude Code já usa, então um projeto configura uma vez para os dois caminhos; a seleção é do próprio git (`git ls-files --others --ignored --exclude-from=.worktreeinclude`). Alternativa descartada: lista fixa de arquivos na fábrica (`.env`, `opencode.jsonc`), que não cobre a variedade dos projetos.
- Caminhos relativos (`git worktree add --relative-paths`, git 2.48 ou mais novo) — o `.git` da worktree aponta para o clone por caminho relativo, então funciona na VM do `sbx` qualquer que seja o caminho de montagem. Alternativa descartada: uma VM por issue, que multiplica VMs e políticas de rede.
- Limite de 3 worktrees por clone (recomendação da triagem) — o `ensure` recusa criar a 4ª worktree de issue, contando as de specs ainda não aprovadas; reusar é sempre permitido. Alternativa descartada: só o limite atual de 3 issues com `spec-aprovada`, sem limite de worktrees, que deixaria escrever specs sem teto.
- Etapa trabalha com `cd <wt> && …` em cada comando e caminhos absolutos — funciona igual no Claude Code, no OpenCode e no `claude -p` do `avancar`, sem depender de o `cd` persistir. Alternativa descartada: abrir a sessão na worktree, que exige uma sessão por issue aberta à mão e não serve ao `avancar`.

**Fontes da documentação:**
- Claude Code 2.1.327 — `/websites/code_claude` (Context7: páginas "worktrees" e "hooks", `--worktree`, `.worktreeinclude`, `WorktreeCreate`, `WorktreeRemove`) e `claude --help`.
- git 2.53.0 — `git worktree -h`, `git worktree add -h` (`--relative-paths`), `git ls-files -h` (`--others`, `--ignored`, `--exclude-from`), `git branch -h` (`-D`).
- gh 2.104.0 — `gh pr list --help` (`--head`, `--state all`, `--json number,state,headRefOid`).
- Montagem da pasta do projeto na VM do Docker Sandboxes: não verificada (a decisão dos caminhos relativos não depende dela).

**ADR:** [docs/adr/0014-uma-worktree-por-issue.md](../docs/adr/0014-uma-worktree-por-issue.md)

## Testes
- `bash scripts/test-issue-worktree.sh`: CA1 a CA13 e CA17. Cada caso cria um repositório temporário com um remote `--bare` local e confere pastas, branches, `HEAD` do clone principal, `.git/info/exclude`, saídas e linhas impressas. O CA10 move o diretório do repositório temporário. O CA11 a CA13 põem no `PATH` um `gh` falso que devolve o JSON de cada caso (ou falha).
- `bash scripts/test-protect-main.sh`: o caso novo do CA14, ao lado do CA3 atual.
- Verificação manual do CA15 e do CA16, com o plugin carregado da branch (`claude --plugin-dir <clone>`), duas issues de teste no próprio repositório e o PR de teste fechado sem merge; tudo fechado no fim com um comentário dizendo que era teste. Anote no PR o `git -C <clone> rev-parse HEAD` antes, durante e depois.

## Passos de produção
nenhum

## Riscos e dúvidas
- O limite de 3 worktrees aperta o fluxo: com 3 issues em implementação, a spec de uma 4ª espera. Se você preferir só o limite atual de `spec-aprovada`, a decisão muda para "sem limite de worktrees" e o CA6 sai.
- `gh pr merge --delete-branch` rodado no clone não consegue apagar a branch local que está numa worktree e avisa disso; o merge acontece, e o `clean` apaga a branch depois. Fica documentado em `docs/solucao-de-problemas.md`.
- Uma worktree de PR fechado com trabalho local nunca é removida sozinha: aparece como `mantida … trabalho-local` até o usuário decidir.
- As issues em andamento hoje, com a branch no clone principal, param no `ensure` (saída 4) até o clone voltar para a `main`.
- Tamanho no limite do G; se a implementação passar de 2 dias, o corte natural é deixar o `status` e o `avancar` (CA16) para uma issue seguinte.

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
