# SPEC-135: Revisar confere se a main avançou em arquivos do PR antes de aplicar pronto-revisao

**Issue:** #135 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-27

## Contexto
Hoje a branch da issue só é atualizada com a `main` no início do `/fabrica:implementar` (`skills/implementar/SKILL.md`, passo de preparo: `git rebase origin/main`). Com até 3 issues em andamento, outro PR entra na `main` enquanto este é implementado ou espera a revisão, e o `/fabrica:revisar` aplica `pronto-revisao` (passo 6) com um CI verde que vale para uma base antiga. A ideia vem da seção "Base branch and merging" da skill `babysit-pr` do tstack: o PR não está pronto se ficou atrás da base em arquivos que ele toca ou em conflito, e a conferência se repete logo antes de liberar.

## Objetivo
Um PR só recebe `pronto-revisao` se a `main` não avançou em arquivos que ele toca e não há conflito, ou depois de a branch ser atualizada com a `main` e o CI do head novo ficar verde; o `/fabrica:status` e o guia de revisão mostram o PR que ficou para trás depois disso.

## Comportamento esperado

### Classificação da base
Um script novo, `scripts/base-drift.sh`, classifica a branch do PR em relação à `main` e imprime uma linha só. Ele só lê: não faz fetch, merge, checkout nem escreve na worktree ou no GitHub.

| Saída | Quando |
|---|---|
| `em-dia` | a `main` não tem commit fora da branch (a `main` é ancestral do head) |
| `atras-sem-sobreposicao <n>` | a `main` tem `<n>` ≥ 1 commits fora da branch, nenhum arquivo mudado por eles foi mudado pelo PR, e não há conflito |
| `sobreposicao <n> <arquivo>…` | a `main` tem `<n>` ≥ 1 commits fora da branch, ao menos um arquivo mudou dos dois lados desde a base comum, e o merge não tem conflito; os arquivos vão em ordem alfabética, separados por espaço |
| `conflito <n> <arquivo>…` | o merge da `main` na branch tem conflito; os arquivos são os conflitantes, em ordem alfabética |

- "Arquivo mudado" é todo caminho que aparece no diff por nome desde a base comum (`merge-base`), inclusive criado, apagado ou renomeado (conta o caminho novo e o antigo). Um arquivo apagado na `main` e alterado no PR é sobreposição ou conflito, nunca `atras-sem-sobreposicao`.
- O conflito tem precedência sobre a sobreposição.
- Branch à frente da `main` e com a `main` ancestral do head é `em-dia`, qualquer que seja o número de commits do PR.

Dois modos:
- `bash scripts/base-drift.sh local [<base>]`, rodado dentro de `<wt>`, com `<base>` padrão `origin/main`. Usa só o `git` local, sobre o estado já buscado pelo chamador (`git fetch origin` antes). O conflito sai de `git merge-tree --write-tree --name-only HEAD <base>`, que não toca a worktree.
- `bash scripts/base-drift.sh api <dono>/<repo> <nº do PR>`, para o `status`, sem clone. Lê o PR com `gh pr view <nº> -R <repo> --json files,mergeable,baseRefName,headRefName` e os commits e arquivos da base desde a base comum com `gh api repos/<repo>/compare/<headRefName>...<baseRefName>` (`ahead_by` = `<n>`, `files[].filename` e `files[].previous_filename`). `mergeable` = `CONFLICTING` é `conflito`, com os arquivos da sobreposição como lista (a API não diz quais conflitam); `UNKNOWN` não conta como conflito, e a classificação sai só dos arquivos.

Saídas de erro, sem linha na saída padrão: `2` para uso errado (modo desconhecido, argumento faltando, fora de um repositório git no modo `local`), `1` para falha do `git` ou do `gh`, com a mensagem na saída de erro.

### `/fabrica:revisar`, passo 6
Com o CI verde e sem achados bloqueantes, **antes** de aplicar `pronto-revisao`, a etapa roda `git fetch origin` e `bash <plugin>/scripts/base-drift.sh local` em `<wt>`:

| Saída | O que fazer |
|---|---|
| `em-dia` ou `atras-sem-sobreposicao` | Segue para aplicar `pronto-revisao`. Com `atras-sem-sobreposicao`, a resposta no PR ganha a linha "A `main` avançou <n> commits em arquivos que este PR não toca." |
| `sobreposicao` | Atualização sem conflito: `git merge --no-edit origin/main`, `make lint` e `make test`, push, e espera o CI do head novo ("Ler o CI"). Sem nova rodada do revisor. |
| `conflito` | `git merge origin/main` e resolve os conflitos. Se a resolução muda o comportamento de um CA ou mexe em "Fora de escopo", `git merge --abort` e escala como mudança de escopo do passo 2 (`escalonado` e lição com o gatilho `escalonado`). Senão, commit do merge, `make lint` e `make test`, push, espera o CI do head novo e faz uma nova rodada do revisor (passo 3). |

- Depois de cada atualização, com o CI verde (e o revisor sem bloqueante, no caso do conflito), a etapa repete o `fetch` e a classificação logo antes de aplicar a label.
- **Limite:** no máximo **2 atualizações** por execução da etapa, contadas juntas para `sobreposicao` e `conflito`. A 2ª é feita; se depois dela a classificação ainda pedir uma 3ª, a etapa não atualiza: converte o PR em rascunho (`gh pr ready --undo`), aplica `escalonado`, registra uma lição com o gatilho `escalonado` e diz na resposta do PR que a `main` avançou de novo durante a espera.
- **Falha depois da atualização:** `make lint`, `make test` ou CI vermelhos por causa da combinação com a `main` são achado `bloqueante` e seguem as rodadas de correção do passo 4, com o mesmo teto de duas rodadas da etapa. Os achados da nova rodada do revisor depois de um conflito também.
- **`pronto-revisao` já aplicada:** se a issue já tem `pronto-revisao` quando a etapa precisa atualizar a branch, ela remove a label antes do push (`gh issue edit <nº> --remove-label pronto-revisao`) e só a reaplica pelo caminho normal.
- **Execução só para conferir a base:** se a issue tem `pronto-revisao`, o PR está aberto e o passo 2 não achou pedido novo, a etapa pula os passos 3 a 5 e vai direto à conferência da base. Com `em-dia` ou `atras-sem-sobreposicao`, mantém a label e responde no PR "PR já está atualizado com a `main` nos arquivos que ele toca", sem a seção "Evidência por critério".
- **Push recusado por falta da permissão Workflows:** se o `git push` da branch atualizada é recusado com uma mensagem que cita `workflow` (o `FABRICA_GH_TOKEN` do dispatcher não tem a permissão Workflows, `docs/guias/dispatcher.md`, e a `main` trouxe mudança em `.github/workflows/`), a etapa volta a branch local ao remoto (`git reset --hard origin/<branch>`), converte o PR em rascunho, aplica `escalonado` e comenta na issue, com o marcador `<!-- fabrica:revisar -->`, que a atualização traz mudança em workflow e que o usuário deve rodar `/fabrica:revisar <nº>` numa sessão na máquina dele. Não registra lição, porque não é falha do fluxo. Outra recusa de push segue como hoje.
- A resposta no PR (passo 6, "Resposta no PR") cita cada atualização feita: a saída da classificação, o commit do merge e o run do CI do head novo.

### `/fabrica:status`
Para cada PR aberto em "PR para revisar" (linha 13 de `skills/status/estados.md`), o status roda `bash <plugin>/scripts/base-drift.sh api <repo> <nº do PR>` e, com `sobreposicao` ou `conflito`, acrescenta um alerta:
- `sobreposicao`: "`<repo>#<nº>`: a `main` avançou em <k> arquivo(s) que o PR #<pr> toca (<até 3 arquivos>, e mais <m>); rode `/fabrica:revisar <nº>` antes do merge."
- `conflito`: "`<repo>#<nº>`: o PR #<pr> está em conflito com a `main`; rode `/fabrica:revisar <nº>` antes do merge."
- `em-dia`, `atras-sem-sobreposicao` e saída 1 ou 2 do script não geram alerta. A saída 1 ou 2 não interrompe o quadro.

O estado da issue não muda: continua "PR para revisar", sem linha nova em `estados.md`.

### Guia de revisão
`docs/guias/revisar-pr.md` ganha, antes de "Decidir", o passo "Antes do merge": conferir no `/fabrica:status` se o PR tem o alerta de `main` avançada ou de conflito; com o alerta, rodar `/fabrica:revisar <nº>`, que atualiza a branch e devolve o PR com `pronto-revisao`; um PR atrás só em arquivos que ele não toca pode ser mergeado.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `base-drift.sh local` imprime `em-dia` numa branch com commits próprios cuja base é a ponta da `main`, e também numa branch sem commit próprio igual à `main`. | unitário — `scripts/test-base-drift.sh`, repositório git temporário |
| CA2 | `base-drift.sh local` imprime `atras-sem-sobreposicao 2` quando a `main` tem 2 commits novos só em arquivos que o PR não muda. | unitário — `scripts/test-base-drift.sh` |
| CA3 | `base-drift.sh local` imprime `sobreposicao 1 a.txt` quando a `main` e o PR mudam `a.txt` em linhas distantes, sem conflito; e imprime `sobreposicao` também quando a `main` renomeia `b.txt` para `c.txt` e o PR altera `b.txt` sem conflito, com `b.txt` na lista. | unitário — `scripts/test-base-drift.sh` |
| CA4 | `base-drift.sh local` imprime `conflito <n> <arquivos>` quando a `main` e o PR mudam a mesma linha, e um arquivo apagado na `main` e alterado no PR dá `conflito`; depois da execução, `git status --porcelain` está vazio e o `HEAD` é o mesmo de antes. | unitário — `scripts/test-base-drift.sh` |
| CA5 | `base-drift.sh api` com um `gh` falso no `PATH` devolve `em-dia` (`ahead_by` 0), `atras-sem-sobreposicao`, `sobreposicao` e `conflito` (`mergeable` `CONFLICTING`) a partir dos JSONs de PR e de compare; `mergeable` `UNKNOWN` com arquivos em comum dá `sobreposicao`, e com nenhum, `atras-sem-sobreposicao`. | unitário — `scripts/test-base-drift.sh` |
| CA6 | O script sai com 2, sem nada na saída padrão, com modo desconhecido, com o modo `api` sem o nº do PR e com o modo `local` fora de um repositório git; sai com 1 quando o `gh` falso falha. | unitário — `scripts/test-base-drift.sh` |
| CA7 | O passo 6 do `skills/revisar/SKILL.md` roda `git fetch origin` e o `base-drift.sh local` antes de aplicar `pronto-revisao`, com a tabela das quatro saídas, o merge de `origin/main` como forma de atualizar, a nova rodada do revisor só depois de conflito e a repetição da conferência antes da label. | manual — leitura do revisor contra esta spec |
| CA8 | Limite inclusivo de atualizações: o texto do passo 6 diz que a 2ª atualização é feita e que, se a classificação pedir uma 3ª, o PR vai para rascunho com `escalonado` e lição `escalonado`, sem `pronto-revisao`. | manual — leitura do revisor contra esta spec |
| CA9 | Num PR de teste no próprio repositório com `pronto-revisao`, com um commit na `main` que toca um arquivo do PR, `/fabrica:revisar <nº>` rodado com `claude --plugin-dir <wt>` faz o merge de `origin/main` na branch, espera o CI do head novo, reaplica `pronto-revisao` e cita a atualização na resposta do PR; rodado de novo sem mudança na `main`, responde "PR já está atualizado…" sem rodar o revisor. O PR e a issue de teste são fechados no fim com um comentário dizendo que eram teste, e o commit de teste na `main` sai por um PR de reversão. | manual — PR de teste no próprio repositório, `claude --plugin-dir <wt>` na branch |
| CA10 | O texto do passo 6 trata o push recusado por falta da permissão Workflows: volta a branch ao remoto, deixa o PR em rascunho com `escalonado`, comenta na issue pedindo `/fabrica:revisar <nº>` numa sessão local e não registra lição. | manual — leitura do revisor contra esta spec |
| CA11 | O passo de alertas do `skills/status/SKILL.md` roda o `base-drift.sh api` para cada PR em "PR para revisar" e gera os dois textos de alerta desta spec, sem alerta para `em-dia`, `atras-sem-sobreposicao` e saída 1 ou 2; `skills/status/estados.md` não ganha linha nova. | manual — leitura do revisor contra esta spec e `/fabrica:status fabrica` com `claude --plugin-dir <wt>` durante o CA9, antes da atualização, mostrando o alerta |
| CA12 | `docs/guias/revisar-pr.md` tem o passo "Antes do merge" com o critério desta spec (alerta do status → `/fabrica:revisar <nº>`; atrás só em outros arquivos → pode mergear). | manual — leitura do revisor contra esta spec |
| CA13 | `scripts/test-base-drift.sh` passa no CI do repositório (o laço `scripts/test-*.sh` do `.github/workflows/ci.yml` o inclui sem mudança no workflow), o `AGENTS.md` cita o script e o comando de teste, e a `version` do `.claude-plugin/plugin.json` sobe. | unitário — CI do PR |

## Fora de escopo
- Vigiar o PR continuamente depois do `pronto-revisao`: a conferência acontece quando o `revisar` roda e quando o `status` é consultado.
- Fila de merge ou merge automático.
- Detectar conflito semântico entre arquivos diferentes.
- Fazer o dispatcher acordar sozinho quando a `main` avança.
- Mudar o `rebase` do início do `/fabrica:implementar`.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/base-drift.sh` (novo): os modos `local` e `api` descritos acima.
- `scripts/test-base-drift.sh` (novo): repositórios git temporários para o modo `local` e um `gh` falso no `PATH`, no padrão de `scripts/test-publish-screenshots.sh` e `scripts/test-setup-dispatcher.sh`, para o modo `api`.
- `skills/revisar/SKILL.md`: passo 2 (execução só para conferir a base), passo 6 (conferência, atualização, limite, push recusado, resposta no PR).
- `skills/status/SKILL.md`: coleta do `base-drift.sh api` para os PRs em "PR para revisar" e os dois alertas.
- `docs/guias/revisar-pr.md`: passo "Antes do merge".
- `docs/fluxo.md`: uma frase no trecho do `revisar` dizendo que a etapa confere a base antes de liberar o PR.
- `AGENTS.md`: o `base-drift.sh` e o `bash scripts/test-base-drift.sh` na lista de `scripts/`.
- `.claude-plugin/plugin.json`: `version` sobe para a próxima minor.

**Dados:** nenhum.

**Interfaces:** `base-drift.sh local [<base>]` e `base-drift.sh api <dono>/<repo> <nº do PR>`; saída padrão de uma linha (`em-dia` | `atras-sem-sobreposicao <n>` | `sobreposicao <n> <arquivo>…` | `conflito <n> <arquivo>…`); código 0, 1 (falha do `git`/`gh`) ou 2 (uso).

**Decisões:**
- Atualizar a branch com `git merge origin/main`, não com rebase (recomendação da triagem) — o merge com squash apaga o commit de merge, o push não precisa ser forçado e é o que o `/fabrica:backlog` já faz numa branch com PR aberto; os hooks do git (`githooks/fabrica-hook`, `pre-merge-commit`) e o proxy do job (`scripts/egress-addon.py`) só barram a `main`/`master`. Alternativa descartada: rebase com `--force-with-lease`, como o `implementar`, que reescreve um histórico já revisado e exige push forçado num PR aberto.
- Atualização sem conflito só repete `make lint`, `make test` e o CI; conflito resolvido à mão passa por nova rodada do revisor (recomendação da triagem) — o passo 4 do `revisar` já pede nova rodada depois de código mexido à mão. Alternativa descartada: revisor em toda atualização, que gasta uma rodada inteira para um merge que o `git` resolveu sozinho.
- Repetir a conferência antes da label, com no máximo 2 atualizações por execução e escalonamento depois (recomendação da triagem) — o objetivo vale no momento da label, e o `revisar` já limita as correções a duas rodadas. Alternativa descartada: conferir uma vez só, que deixa passar a `main` que avançou durante a espera do CI.
- Falha depois da atualização segue as rodadas de correção do passo 4 (recomendação da triagem) — é o mesmo tratamento do CI vermelho. Alternativa descartada: escalar na primeira falha.
- Guia com o mesmo critério da etapa (recomendação da triagem) — PR atrás só em outros arquivos não precisa de atualização. Alternativa descartada: pedir o `/fabrica:revisar` para qualquer atraso.
- `status` só alerta, sem estado novo em `estados.md` (recomendação da triagem) — o escopo pede um alerta. Alternativa descartada: nova linha na tabela de estados.
- A classificação fica num script com teste, usado pelas duas skills — o critério de "arquivo mudado" e de conflito precisa ser o mesmo na etapa e no status, e a borda (apagado, renomeado, `UNKNOWN`) fica coberta por teste. Alternativa descartada: descrever os comandos `git` e `gh` no texto de cada skill.
- Conflito detectado com `git merge-tree --write-tree` — classifica sem tocar a worktree (git 2.38+; a máquina tem 2.53). Alternativa descartada: `git merge --no-commit` seguido de `--abort`, que mexe na worktree e deixa resto se a etapa parar no meio.
- Push recusado por falta de Workflows escala para uma sessão local, sem lição — a recusa é limite do token do dispatcher, não do fluxo, e dar Workflows ao token aumenta o que um agente enganado pode fazer. Alternativa descartada: pedir a permissão Workflows no `FABRICA_GH_TOKEN`.

**Fontes da documentação:**
- GitHub REST API, compare de commits — Context7 `/websites/github_en_rest` (`GET /repos/{owner}/{repo}/compare/{basehead}`: formato `BASE...HEAD`, `ahead_by`, `files` com até 300 arquivos). Versão não confirmada (API sem versão no projeto).
- git 2.53.0 — `git merge-tree --write-tree` e `--name-only`: não verificada nesta etapa; o implementador confere em `git merge-tree --help` antes de usar.
- Recusa de push de workflow sem a permissão Workflows: não verificada (conhecimento do modelo); o texto da skill casa a mensagem por `workflow`, sem depender da frase exata.
- gh 2.105.0 — `gh pr view --help` (campos `files`, `mergeable`, `baseRefName`, `headRefName`), `gh pr list --help`, `gh api --help`.

**ADR:** nenhum.

## Testes
- `bash scripts/test-base-drift.sh` (CA1 a CA6): cada caso monta um repositório com `git init` e um `origin` local em pasta temporária, cria a `main` e a branch do PR com os commits do CA, roda o script e compara a saída e o código de saída; no CA4 confere também `git status --porcelain` e o `HEAD`. O modo `api` usa um `gh` falso que devolve JSONs fixos por argumento e um modo que sai com 1.
- `make lint` e `make test`, se existirem, e o CI do PR (CA13).
- CA7, CA8, CA10, CA11 e CA12: leitura do revisor contra esta spec.
- CA9 e o trecho de execução do CA11: PR de teste no próprio repositório, com `claude --plugin-dir <wt>`.

## Passos de produção
nenhum

## Riscos e dúvidas
- A #136 (espera do CI) e a #138 (retomada de branch parada) mexem no passo 6 do `revisar` ou no mesmo assunto: a que entrar depois resolve o conflito de texto.
- O compare da API lista até 300 arquivos e o `gh pr view --json files` pode não trazer todos num PR enorme: o `status` pode deixar de alertar nesse caso. A etapa, que usa o `git` local, não tem esse limite.
- O CA9 precisa de um commit de teste na `main` da fábrica, que só entra por PR: o implementador pode, em vez disso, usar um repositório de teste com o plugin, registrando qual usou.

## Histórico
- 2026-11-27: criação.
