---
name: backlog
description: Cria e mantém o backlog no GitHub a partir do fatiamento do docs/prd.md - todas as milestones de uma vez e issues enxutas só para o marco atual e o seguinte, sem a label agente - e anota o número das issues no PRD num PR docs. Use depois do merge do PRD, quando o marco atual estiver perto de fechar ou quando o PRD mudar.
disable-model-invocation: true
---

# Backlog do produto

O backlog liga o fatiamento do PRD às issues. O planejamento é em ondas: todas as milestones existem desde o início, mas só os dois marcos mais próximos têm issues. Cada issue de backlog é enxuta; o detalhe vem depois, na triagem e na spec, uma issue por vez. Aplicar `agente` continua sendo o gesto do usuário de puxar uma issue para o fluxo.

Os termos (item com issue, marco atual, perto de fechar, janela) e o marcador estão definidos na seção "Backlog" de [estados.md](../status/estados.md). Siga-os à risca.

## Regras
- Nunca altere uma issue que tenha `agente`: ela já está no fluxo. Divergências com o PRD só são listadas para o usuário decidir.
- Nunca apague milestone e nunca feche issue sem a confirmação do passo 4.
- Nunca aplique `agente`.
- Publique todo corpo de issue, comentário ou PR a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- Nada é criado ou alterado antes da confirmação do usuário.
- Não commite na `main`: a anotação do PRD vai pela branch `docs/backlog` e por PR.
- Em qualquer saída depois de criar a worktree do passo 1 (plano vazio, PRD inválido, cancelamento, erro ou fim do passo 5), remova-a com `git worktree remove --force <tmp>`. O git não deixa a mesma branch em duas worktrees, e uma worktree esquecida quebra a próxima execução.

## Formato do fatiamento
```markdown
## Fatiamento
Itens de 1 a 2 dias de trabalho humano, agrupados por marco e em ordem de dependência dentro de cada marco. O número do item é fixo: não renumere; item novo recebe o próximo número livre.

### M1 · Base
- **1.** Criar o app com lint, testes e CI (base) · #2
- **2.** Configurar o banco e o ambiente local (base) · depende de 1 · #6

### M2 · Tarefas (F2, F11, F12)
- **5.** Modelo e API de tarefas (F2) · depende de 2
```
- O título do marco (`M1 · Base`, sem as F entre parênteses) é o título da milestone no GitHub. O prefixo `M<n>` dá a ordem e identifica o marco mesmo se o nome mudar.
- Cada item tem número fixo, título, as F entre parênteses (`base` quando não há F) e, quando houver, `depende de <números>`. A ordem da lista não cria dependência. Ao ganhar issue, o item recebe ` · #<nº>` no fim.

## 1. Ler
- Confirme que está num clone com remote no GitHub (`gh repo view --json nameWithOwner`). Se não estiver, pare e diga o que falta.
- Se sobrou uma worktree da branch `docs/backlog` de uma execução anterior (`git worktree list`), remova-a com `git worktree remove --force <caminho>`.
- `git fetch origin`. Veja se existe PR aberto da branch `docs/backlog` (`gh pr list --head docs/backlog --state open`).
  - **Sem PR aberto:** leia o PRD da `main` (`git show origin/main:docs/prd.md`).
  - **Com PR aberto:** a branch tem a migração e as anotações ainda sem merge, mas pode estar atrás da `main`. Crie a worktree do passo 5 (`git worktree add <tmp> docs/backlog`, depois `git pull`), traga a `main` para ela (`git merge origin/main`) e leia o PRD dali. Assim, as mudanças do PRD mergeadas na `main` depois que o PR foi aberto entram no plano. Se o merge der conflito, rode `git merge --abort`, remova a worktree e pare: peça para mergear ou fechar o PR `docs/backlog` pendente antes de rodar de novo. Se o usuário cancelar no passo 4, remova a worktree sem push.
- Sem `docs/prd.md` ou sem a seção de fatiamento, pare e indique `/fabrica:prd`.
- Milestones: `gh api "repos/<repo>/milestones?state=all&per_page=100"`.
- Issues, abertas e fechadas: `gh issue list --state all --limit 1000 --json number,title,body,state,labels,milestone`.

## 2. Migrar, se preciso
- **PRD sem marcos** (fatiamento numa lista única, sem `### M<n>`): proponha o agrupamento em marcos, com nome e F de cada um, a partir das funcionalidades e da ordem da lista. Mantenha os números dos itens e proponha as dependências explícitas (`depende de`) que a ordem e os títulos sugerem.
- **Item sem issue registrada** (sem issue com o marcador e sem `#<nº>` no PRD): procure issue sem o marcador `fabrica:backlog` cujo título, ignorando maiúsculas e espaços nas pontas, seja igual ao do item. Isso vira um **par**. Títulos parecidos, mas não iguais, viram **possível par**. Issue fechada também conta.

## 3. Planejar
Calcule, com o PRD já migrado:
- **Item com issue:** o marcador `<!-- fabrica:backlog item=<n> -->` no corpo vale mais que a anotação no PRD. Uma issue com marcador cujo item não tem anotação no PRD entra só na anotação do passo 5.
- **Marco atual, perto de fechar e janela**, conforme [estados.md](../status/estados.md). Os pares e possíveis pares contam como issue do item.

O plano tem:
1. **Milestones a criar:** os marcos sem milestone com o mesmo prefixo `M<n> · `.
2. **Milestones a atualizar:** título ou descrição diferentes do PRD.
3. **Issues a criar:** só os itens sem issue nos marcos da janela.
4. **Pares e possíveis pares** a vincular (issue existente ↔ item).
5. **Issues de backlog abertas, sem `agente`, a atualizar:** título, F, dependências ou marco diferentes do PRD.
6. **Divergências no fluxo:** issues abertas com `agente` cujo título, marco ou dependências não batem com o PRD. Só listadas.
7. **Itens removidos:** issues abertas com marcador cujo número não existe mais no PRD, com proposta de fechamento. As com `agente` vão para a lista de divergências.
8. **PRD:** a migração, quando houver, e as anotações ` · #<nº>` que faltam.

Os grupos 5, 6 e 7 olham só issues abertas. Uma issue fechada conta para "item com issue" e para o avanço do marco, mas nunca é atualizada, listada como divergência ou proposta para fechamento. Sem isso, a mesma issue fechada voltaria ao plano em toda execução.

## 4. Confirmar
- Plano vazio (nada nos itens 1 a 8): diga "Backlog em dia" e pare, sem criar nada.
- Senão, mostre o plano no chat, em tabelas curtas por grupo, com o marco atual e a janela. Quando houver migração, mostre o fatiamento novo inteiro.
- Pergunte com o AskUserQuestion:
  - **Aplicar tudo**, com fechamento dos itens removidos, se houver;
  - **Aplicar sem os possíveis pares**, que só aparece quando houver possíveis pares;
  - **Cancelar**.
  Para fechar issues de itens removidos, use uma pergunta separada, com seleção múltipla das issues. Sem confirmação, nada fecha.
- Cancelado: diga que nada foi alterado e pare.

## 5. Aplicar
Aplique nesta ordem. Se um comando falhar, pare, mostre o que já foi aplicado e o erro. Rodar de novo continua de onde parou, porque as milestones existentes e os marcadores impedem duplicação.

1. **Milestones:**
   - criar com `gh api -X POST repos/<repo>/milestones -f title="<M<n> · nome>" -f description="<lista>"`;
   - atualizar com `gh api -X PATCH repos/<repo>/milestones/<número> -f title=... -f description=...`.

   A descrição lista os itens do marco, um por linha: `<n>. <título> (<F>)`.
2. **Issues novas**, em ordem de número de item:
   - comando: `gh issue create --title "<título do item>" --milestone "<título do marco>" --label enhancement --body-file <arquivo>`, com o corpo no formato abaixo;
   - as dependências viram `#<nº>` das issues já existentes ou recém-criadas;
   - se a label `enhancement` não existir, crie sem ela e avise no resumo.
3. **Pares confirmados:**
   - ponha a issue na milestone com `gh issue edit <nº> --milestone "<título do marco>"`, mesmo que ela esteja fechada;
   - acrescente ao fim do corpo uma linha `---` seguida do bloco do formato abaixo, sem apagar o texto que já existe.
4. **Issues de backlog sem `agente` a atualizar:** reescreva título, corpo e milestone com `gh issue edit`.
5. **Fechamento:** só as issues confirmadas, com `gh issue close <nº> --reason "not planned" --comment "<!-- fabrica:backlog -->"` e uma linha dizendo que o item saiu do PRD.
6. **PRD:**
   - **branch:** trabalhe numa worktree temporária, para não mexer na branch em que o clone está:
     - com PR aberto de `docs/backlog`, use a worktree criada no passo 1, que já tem a `main` mesclada;
     - sem PR aberto, use `git worktree add -B docs/backlog <tmp> origin/main`. Se já houver uma branch `docs/backlog` remota com PR mergeado, faça o push com `--force-with-lease`, porque a branch recomeça da `main`.
   - **conteúdo:** grave a migração, se houver, e as anotações ` · #<nº>`. Não mude nenhuma outra linha do PRD.
   - **commit e PR:** commit `docs: registra issues do backlog no prd` e push. Sem PR aberto, crie um com `gh pr create --base main --head docs/backlog`, com o título igual ao commit e um corpo que liste as issues criadas e vinculadas.
   - **limpeza:** remova a worktree (`git worktree remove <tmp>`).
   - **merge:** é do usuário; não faça.

## Formato da issue de backlog
```markdown
<!-- fabrica:backlog item=5 -->
**Funcionalidade:** F2 · **Item do fatiamento:** 5 · **Marco:** M2 · Tarefas (F2, F11, F12)
**PRD:** [docs/prd.md](https://github.com/<dono>/<repo>/blob/main/docs/prd.md#fatiamento)

Depende de #12
```
- O título da issue é o título do item, sem as F e sem as dependências.
- `Funcionalidade` traz as F do item, ou `base`.
- A linha `Depende de` só aparece quando o item declara dependência, com as issues separadas por vírgula (`Depende de #12, #13`).

## 6. Resumir
No chat:
- milestones criadas e atualizadas;
- issues criadas, vinculadas, atualizadas e fechadas, com links;
- divergências no fluxo, para o usuário decidir;
- link do PR do PRD, lembrando que o merge é dele;
- próximo passo: aplicar `agente` na primeira issue do marco atual com as dependências fechadas, citando o número. Se nenhuma tiver as dependências fechadas, cite a issue que bloqueia.
