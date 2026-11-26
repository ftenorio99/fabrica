# SPEC-129: Spec descreve as telas, e a implementação anexa screenshots no celular e no computador ao PR

**Issue:** #129 · **PRD:** F7 (item 11 do fatiamento) · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-25

## Contexto
A F7 do [PRD](../docs/prd.md) pede aprovação visual: a spec descreve as telas, e a implementação anexa ao PR screenshots reais, no celular e no computador. A primeira metade já existe: o `docs/design.md` e o campo `Interface` da triagem ([ADR 0009](../docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md), #45), e o CI do PR roda o Playwright ([ADR 0019](../docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md), #128). Esta issue liga as duas pontas: a descrição de cada tela na spec e as imagens no PR.

## Objetivo
Numa issue com interface, a spec descreve cada tela e seus estados, e o PR mostra um screenshot de cada tela e estado no celular e no computador, gerado pelo Playwright do projeto; numa issue sem interface, nada muda.

## Comportamento esperado

**Quem tem telas.** Uma spec "tem telas" quando a seção `## Telas` dela traz ao menos uma tela (`### <id>`). A spec de uma issue com `Interface: não`, ou com triagem antiga sem o campo, escreve `## Telas` com a linha `nenhuma (Interface: não)`. Uma spec antiga sem a seção conta como sem telas. O `implementar`, o `revisar` e o revisor decidem pelo arquivo da spec, não pela triagem.

**Descrição de uma tela na spec** (texto estruturado, com um esboço anexado à issue como referência opcional):
- `### <id>`: id em minúsculas, com letras, números e hífen simples (`[a-z0-9]+(-[a-z0-9]+)*`), único na spec;
- **Rota:** o caminho da tela (ex.: `/eventos/novo`);
- **O que aparece:** os elementos da tela, em itens curtos;
- **Ações:** o que cada ação do usuário faz;
- **Estados:** tabela `Estado | Como chegar | Captura`. O estado `padrao` (a tela com dados típicos) é obrigatório. Os estados `vazio`, `erro` e `carregando` entram quando a tela os tem. `Captura` é `sim`, ou `não — <motivo>` (ex.: `carregando` dura menos que a captura). O estado `padrao` tem sempre `Captura: sim`;
- **Referência:** o link do esboço anexado à issue, se houver.

**Dispositivos** (fixos pela fábrica, presets do DevTools do Chrome, só Chromium, página inteira):

| Dispositivo | Preset | Viewport | Escala |
|---|---|---|---|
| `celular` | iPhone 12 Pro | 390 × 844, `isMobile` e `hasTouch` | 3 |
| `computador` | Laptop L | 1440 × 900 | 1 |

**Contrato do `make screenshots`** ([ADR 0020](../docs/adr/0020-screenshots-das-telas-numa-branch-orfa.md)): o alvo roda o Playwright e grava em `screenshots/`, na raiz do projeto, um PNG por tela, estado com `Captura: sim` e dispositivo, com o nome `<tela>--<estado>--<celular|computador>.png`. A pasta fica no `.gitignore`. O alvo sobe o que precisa (banco, app) como o `make e2e`.

**Fluxo numa issue com telas:**
1. **Triagem:** `Interface: sim` não cabe no atalho. O comentário diz `**Atalho:** não` com o motivo "issue com interface precisa da descrição das telas na spec completa".
2. **Spec:** preenche `## Telas` como acima.
3. **Implementar:** se o `Makefile` não tem o alvo `screenshots:`, cria o alvo e o teste do Playwright que o alimenta, pelo modelo do guia `docs/guias/telas-e-screenshots.md`. Na verificação, depois do `make e2e`, apaga `screenshots/` e roda `make screenshots`, com as mesmas regras do `make e2e`: falha sem assinatura de ambiente conta como rodada de correção; falha com assinatura vira "verificação pendente para o CI".
4. **Revisor:** roda `make screenshots` na worktree e confere que existe o par `celular` e `computador` de cada tela e estado com `Captura: sim`. Faltar um arquivo é achado `importante`; arquivo a mais não é achado. Com assinatura de ambiente, anota o comando como pendente para o CI e confere o artefato `telas` do CI do head, quando o `revisar` o passa.
5. **Revisar, antes de abrir ou atualizar o PR (passo 5):** obtém as imagens do head atual e publica com o `publish-screenshots.sh`:

   | Situação | Origem das imagens | O que acontece |
   |---|---|---|
   | `make screenshots` passa na etapa | `screenshots/` da worktree, recém-gerada | publica e põe a tabela na seção `## Telas` do PR |
   | `make screenshots` falha com assinatura e o CI do head tem o artefato `telas` | `gh run download <run-id> -n telas -D <pasta temporária>` | publica do mesmo jeito; a seção diz "geradas pelo CI: [<run>](<link>)" |
   | assinatura e o CI do head terminou sem o artefato `telas` (cópia antiga do `ci.yml`), ou o projeto não tem CI | nenhuma | PR em rascunho, seção `## Telas` com "pendente", sem `pronto-revisao`; comentário na issue com as duas saídas (acrescentar os passos do guia ao CI, ou rodar `! make screenshots` na máquina e depois `/fabrica:revisar <nº>`) e `escalonado` |
   | `make screenshots` falha sem assinatura | nenhuma | achado `bloqueante`, segue as rodadas de correção do passo 4 do `revisar` |
   | `publish-screenshots.sh` sai com 3 (nome inválido) | — | achado `bloqueante` da implementação |
   | `publish-screenshots.sh` sai com 5 (push recusado 3 vezes) | — | PR em rascunho, seção com a mensagem do script, `escalonado` |

   A cada nova publicação (head novo depois de correções), a seção `## Telas` é substituída pela do head novo.
6. **Usuário:** aprova as telas junto com o PR. Pedido de mudança visual segue o passo 2 do `revisar` (ajuste ou mudança de escopo).

**Seção `## Telas` do corpo do PR**, logo depois de "Critérios de aceite":
```markdown
## Telas
Head `<sha curto>` · celular 390 × 844 (iPhone 12 Pro) · computador 1440 × 900 (Laptop L)

| Tela | Estado | Celular | Computador |
|---|---|---|---|
| novo-evento | padrao | ![novo-evento padrao celular](<link>) | ![novo-evento padrao computador](<link>) |
```
Numa issue sem telas, o corpo do PR não tem a seção.

**`scripts/publish-screenshots.sh <dono/repo> <nº da issue> <sha do head> <pasta>`**, rodado dentro de um clone com o remoto `origin`:
- lê só os arquivos `*.png` do primeiro nível da pasta; outros arquivos e subpastas são ignorados;
- um PNG fora do padrão `^[a-z0-9]+(-[a-z0-9]+)*--[a-z0-9]+(-[a-z0-9]+)*--(celular|computador)\.png$` faz o script sair com 3, listando os nomes, sem gravar nem enviar nada;
- pasta inexistente ou sem nenhum PNG: sai com 4, sem gravar nem enviar nada;
- grava os PNGs na branch `fabrica-telas` em `issue-<nº>/<sha curto, 7 caracteres>/`, substituindo a pasta inteira se ela já existe (um PNG da publicação anterior que não está na pasta nova some), e preserva as outras pastas da branch;
- sem `fabrica-telas` em `origin`, cria a branch órfã, sem nenhum commit da `main` no histórico;
- não toca a branch atual, o índice nem a cópia de trabalho do clone (usa um índice temporário e os comandos de baixo nível do git);
- `git push origin fabrica-telas`; se o push é recusado porque `origin` avançou, busca de novo, refaz o commit sobre a ponta nova e tenta outra vez, em até 3 tentativas no total; recusada a 3ª, sai com 5 e a mensagem do git;
- com sucesso, sai com 0 e imprime a tabela do PR (a linha do cabeçalho `Head …` e a tabela), uma linha por par tela–estado, em ordem alfabética de tela e depois de estado; o link é `https://github.com/<dono/repo>/raw/<sha completo do commit da fabrica-telas>/issue-<nº>/<sha curto>/<arquivo>`; a célula de um dispositivo sem arquivo é `falta`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Numa issue com `Interface: sim`, o `/fabrica:spec` escreve `## Telas` com ao menos uma tela, cada uma com id válido, rota, o que aparece, ações e a tabela de estados com `padrao` e `Captura: sim`. | manual — `claude --plugin-dir <clone>` na branch, `/fabrica:spec` numa issue de teste com interface num repositório de teste, fechada no fim com um comentário dizendo que era teste |
| CA2 | Numa issue com `Interface: não`, ou com triagem sem o campo, a spec escreve `## Telas` só com `nenhuma (Interface: não)`. | manual — `claude --plugin-dir <clone>` na branch, `/fabrica:spec` numa issue de teste sem interface no próprio repositório, fechada no fim com um comentário dizendo que era teste |
| CA3 | Numa spec sem telas (com `nenhuma` ou sem a seção), o `implementar` não roda `make screenshots`, o revisor não confere screenshots e o corpo do PR não tem `## Telas`. | manual — `claude --plugin-dir <clone>` na branch, issue de teste sem interface no repositório de teste até o PR, fechados no fim com um comentário dizendo que era teste |
| CA4 | A triagem de uma issue com `Interface: sim` responde `**Atalho:** não` com o motivo da descrição das telas, mesmo pequena e com `docs/design.md` no projeto. | manual — `claude --plugin-dir <clone>` na branch, `/fabrica:triagem` numa issue de teste pequena com interface no repositório de teste, fechada no fim com um comentário dizendo que era teste |
| CA5 | Com uma pasta de PNGs válidos, o `publish-screenshots.sh` sai com 0, grava os arquivos em `fabrica-telas:issue-<nº>/<sha curto>/`, envia a branch e imprime a tabela com uma linha por par tela–estado, em ordem alfabética, e links com o SHA completo do commit enviado. | unitário — `bash scripts/test-publish-screenshots.sh`, com um remoto `--bare` local |
| CA6 | Sem `fabrica-telas` no remoto, o script cria a branch órfã: o primeiro commit não tem pai e a árvore só tem `issue-<nº>/`. | unitário — `bash scripts/test-publish-screenshots.sh` |
| CA7 | Depois do script, a branch atual, o `HEAD`, o índice e a saída de `git status --porcelain` do clone são iguais aos de antes. | unitário — `bash scripts/test-publish-screenshots.sh` |
| CA8 | Um PNG com nome fora do padrão (ex.: `Tela--padrao--celular.png`, `a--b--tablet.png`, `a---b--celular.png`) faz o script sair com 3, listando o nome, sem criar commit nem enviar; arquivos que não são PNG e subpastas são ignorados. | unitário — `bash scripts/test-publish-screenshots.sh` |
| CA9 | Pasta inexistente, ou sem nenhum PNG no primeiro nível, faz o script sair com 4, sem criar commit nem enviar. | unitário — `bash scripts/test-publish-screenshots.sh` |
| CA10 | Um par tela–estado com só um dispositivo sai na tabela com `falta` na célula do outro. | unitário — `bash scripts/test-publish-screenshots.sh` |
| CA11 | Publicar de novo a mesma issue e o mesmo SHA substitui a pasta: um PNG que só existia na primeira publicação some, os links usam o SHA do commit novo, e a pasta de outra issue na branch continua igual. | unitário — `bash scripts/test-publish-screenshots.sh` |
| CA12 | Com o remoto avançado por outra publicação entre a leitura e o push, o script refaz o commit e envia, preservando a pasta da outra publicação; com o push recusado nas 3 tentativas, sai com 5 sem uma 4ª tentativa. | unitário — `bash scripts/test-publish-screenshots.sh`, com um hook `pre-receive` no remoto que recusa as N primeiras vezes |
| CA13 | Numa spec com telas e um projeto sem o alvo `screenshots:`, o `implementar` cria o alvo pelo modelo do guia, roda `make screenshots` depois do `make e2e` e grava em `screenshots/` os pares de cada tela e estado com `Captura: sim`. | manual — `claude --plugin-dir <clone>` na branch, issue de teste com interface no repositório de teste até o PR, fechados no fim com um comentário dizendo que era teste |
| CA14 | Com o `make screenshots` local passando, o PR tem `## Telas` logo depois de "Critérios de aceite", com a linha do head e dos dispositivos e uma imagem por tela, estado e dispositivo, e as imagens aparecem na página do PR num repositório privado. | manual — PR de teste do CA13 num repositório de teste privado; o usuário abre o PR no navegador e confere as imagens |
| CA15 | Com o `make screenshots` local falhando com assinatura de ambiente (ex.: `PLAYWRIGHT_BROWSERS_PATH` apontando para uma pasta vazia, que dá `Executable doesn't exist at`), o `revisar` baixa o artefato `telas` do run do head e publica, e a seção diz "geradas pelo CI" com o link do run. | manual — `claude --plugin-dir <clone>` na branch, PR de teste no repositório de teste com o `ci.yml` novo, fechado no fim com um comentário dizendo que era teste |
| CA16 | Com assinatura de ambiente e o CI do head sem o artefato `telas`, o PR fica em rascunho com `## Telas` "pendente", a issue não recebe `pronto-revisao`, recebe `escalonado` e um comentário `<!-- fabrica:revisar -->` com as duas saídas. | manual — `claude --plugin-dir <clone>` na branch, PR de teste no repositório de teste com o `ci.yml` antigo, fechado no fim com um comentário dizendo que era teste |
| CA17 | O job `e2e` do `templates/workflows/ci.yml` roda `make screenshots` depois do `make e2e` só quando o `Makefile` tem o alvo `screenshots:`, guarda `screenshots/` como o artefato `telas` com `retention-days: 7` e `if-no-files-found: ignore`; sem o alvo, os dois passos são pulados; o `permissions` continua só `contents: read`. | unitário — `bash scripts/test-setup-ci.sh` |
| CA18 | O revisor aponta como `importante` cada tela e estado com `Captura: sim` sem o par `celular` e `computador`, e não aponta os estados com `Captura: não — <motivo>`; os dois arquivos do revisor têm o corpo igual. | manual — `claude --plugin-dir <clone>` na branch, revisor numa branch de teste do repositório de teste com uma captura removida do teste; unitário — `bash scripts/test-revisor-agent.sh` |
| CA19 | O guia `docs/guias/telas-e-screenshots.md` traz o contrato do `make screenshots`, a tabela de dispositivos, um modelo de `playwright` (projetos `celular` e `computador`) e de alvo, e os passos para acrescentar a reserva a um `ci.yml` já copiado; `docs/README.md`, `docs/fluxo.md`, `docs/comandos.md`, `docs/guias/ci-do-pr.md` e `AGENTS.md` remetem a ele ou ao novo teste, e a `version` do `plugin.json` sobe. | manual — leitura do diff contra a `origin/main` |

## Fora de escopo
- `make design-lint` (`impeccable detect`) no CI e no `/fabrica:revisar`, e a instalação do Impeccable pelo `/fabrica:setup` (recomendação 3 da triagem). Vira uma issue nova pelo `/fabrica:backlog`.
- Comparação automática dos screenshots com uma versão anterior (regressão visual).
- Limpeza das pastas de issues fechadas na `fabrica-telas`.
- Outros dispositivos (tablet) ou navegadores (WebKit, Firefox) e configuração dos dispositivos por projeto.
- Spec curta do atalho com telas: issue com interface sai do atalho (CA4).
- Atualizar sozinho o `ci.yml` de projetos que já o copiaram ([ADR 0019](../docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md)).

## Desenho técnico
**Arquivos e módulos:**
- `scripts/publish-screenshots.sh` (novo) e `scripts/test-publish-screenshots.sh` (novo).
- `skills/spec/template.md`: seção `## Telas` entre "Comportamento esperado" e "Critérios de aceite", com o modelo de tela.
- `skills/spec/SKILL.md`: regra de preenchimento de `## Telas` pela linha `Interface`, ao lado da tabela do design system.
- `skills/triagem/SKILL.md`: `Interface: sim` entra nos motivos de não caber no atalho (hoje só barra quando falta `docs/design.md`).
- `skills/implementar/SKILL.md`: criação do alvo `screenshots:` no passo 3 e o `make screenshots` no passo 4, com as mesmas regras de assinatura do `make e2e`.
- `skills/revisar/SKILL.md`: obtenção e publicação das imagens antes do passo 5 (tabela do comportamento esperado), seção `## Telas` no modelo do corpo do PR, e a passagem do artefato `telas` ao revisor.
- `agents/revisor.md` e `agy-agents/revisor.md`: conferência dos pares, com o corpo igual nos dois.
- `templates/workflows/ci.yml`: dois passos novos no fim do job `e2e`, antes do upload do `playwright-report`: `Roda o make screenshots` (com `if` que confere o alvo `screenshots:` e `steps.alvo.outputs.tem == 'sim'`) e o `actions/upload-artifact` do artefato `telas`, com o mesmo SHA fixado do upload existente. O upload do `playwright-report` continua o último passo.
- `scripts/test-setup-ci.sh`: casos do CA17.
- `docs/guias/telas-e-screenshots.md` (novo), `docs/guias/ci-do-pr.md`, `docs/fluxo.md`, `docs/comandos.md`, `docs/README.md`, `AGENTS.md` (linha do novo teste e da branch `fabrica-telas`), `docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md` (consequência: a verificação visual saiu no item 11, ver ADR 0020).
- `.claude-plugin/plugin.json`: `version` sobe a cada mudança de comportamento (0.55.0 com o merge da `origin/main`; 0.56.0 com a correção do push do `publish-screenshots.sh` e do link do template da spec).
- `opencode/`: nada a mudar; o `server.ts` lê as skills e o revisor dos arquivos do plugin a cada reload.

**Dados:** nenhum banco. A branch órfã `fabrica-telas` de cada projeto com interface, com `issue-<nº>/<sha curto>/<tela>--<estado>--<dispositivo>.png`.

**Interfaces:**
- `publish-screenshots.sh <dono/repo> <nº> <sha> <pasta>`: saídas 0 (tabela no stdout), 2 (argumentos errados, uso no stderr), 3 (nome inválido), 4 (sem PNG), 5 (push recusado 3 vezes).
- Alvo `make screenshots` do projeto: sem argumentos, grava `screenshots/*.png` no padrão de nome; código diferente de 0 é falha.
- Artefato `telas` do CI: o conteúdo de `screenshots/`, baixado com `gh run download <run-id> -n telas -D <pasta>`, com o `<run-id>` do run do workflow do CI no head (lido pela API do Actions, como o passo 6 do `revisar` já faz).

**Decisões:**
- Imagens na branch órfã `fabrica-telas` do próprio repositório, linkadas pelo SHA do commit — o PR mostra as imagens a quem tem acesso ao repositório, sem serviço externo, e o squash não as leva para a `main`. Alternativa descartada: artefato do Actions, que o PR não exibe (o usuário baixa um zip) ([ADR 0020](../docs/adr/0020-screenshots-das-telas-numa-branch-orfa.md)).
- A etapa de agente publica, e o CI só gera o artefato — o modelo do CI continua com `contents: read`. Alternativa descartada: o CI publicar e comentar no PR, com `contents: write` e `pull-requests: write`.
- Geração pelo alvo `make screenshots` do projeto — mesmo contrato do `make e2e` (ADR 0019), igual na etapa e no CI. Alternativa descartada: um script da fábrica que dirige o navegador pelas rotas da spec, que não sabe logar nem montar os estados de cada projeto.
- Issue com `Interface: não` (ou triagem sem o campo) não tem descrição de telas nem screenshots, e o fluxo dela não muda (recomendação da triagem). Alternativa descartada: pedir screenshots em toda issue.
- Se o ambiente da etapa não roda o Playwright, os screenshots saem do CI do PR, e a falta deles na etapa entra como verificação pendente para o CI, como no ADR 0011 (recomendação da triagem). Alternativa descartada: parar a etapa até o ambiente rodar o Playwright.
- `make design-lint` fora desta issue, para uma issue nova pelo `/fabrica:backlog` (recomendação da triagem). Alternativa descartada: tudo nesta issue, bem acima de 2 dias.
- Telas descritas em texto estruturado por tela, com o esboço do usuário como referência opcional (recomendação da triagem). Alternativa descartada: exigir esboço em imagem.
- Dispositivos pelos presets do DevTools do Chrome, como pediu o usuário: iPhone 12 Pro (390 × 844, escala 3) e Laptop L (1440 × 900, escala 1), em Chromium e página inteira. Alternativa descartada: o "Laptop" do DevTools tem 1024 de largura, abaixo da maioria dos notebooks; a proposta da triagem, 1280 × 800, não é preset do DevTools. O DevTools não fixa altura para o Laptop L; 900 é a escolha da fábrica, e a página inteira torna a altura pouco relevante.
- Celular emulado no Chromium (viewport, escala, `isMobile`, `hasTouch`), e não pelo `devices['iPhone 12 Pro']`, que pede o WebKit — o CI só instala o Chromium. Alternativa descartada: instalar o WebKit no CI, mais tempo e cache por PR.
- Issue com interface sai do atalho — a descrição das telas é parte da spec completa, e a spec curta não tem lugar para ela. Alternativa descartada: uma linha `**Telas:**` na spec curta, que mudaria o formato do atalho para um caso raro.
- Os estados têm captura obrigatória, salvo `Captura: não — <motivo>` — o usuário aprova o que vê, inclusive o vazio e o erro. Alternativa descartada: só o estado `padrao`, que deixaria o vazio e o erro sem aprovação.

**Fontes da documentação:**
- Playwright 1.64.1 — `/microsoft/playwright/v1.64.1` (projetos com `devices`, `page.screenshot` com `fullPage`). Versão do Context7, não a de um projeto: a fábrica não tem `package.json`, e cada projeto usa a sua.
- `actions/upload-artifact` v7.0.2 — `if-no-files-found` e `retention-days`: não verificada; o SHA é o já fixado no `ci.yml`.
- gh 2.105.0 — `gh run download --help` (`-n`, `-D`), `gh run list --help` (`--commit`, `--workflow`, `--json`).
- GitHub: link `github.com/<dono>/<repo>/raw/<sha>/<caminho>` exibido em repositório privado para quem tem acesso — não verificada; o CA14 confere.

**ADR:** [docs/adr/0020-screenshots-das-telas-numa-branch-orfa.md](../docs/adr/0020-screenshots-das-telas-numa-branch-orfa.md) (proposto).

## Testes
- `bash scripts/test-publish-screenshots.sh` (CA5 a CA12): cria um remoto `--bare` e um clone em pasta temporária, gera PNGs mínimos e confere código de saída, árvore e histórico da `fabrica-telas` no remoto (`git ls-tree`, `git rev-list --parents`), a tabela impressa e o estado do clone antes e depois. O CA12 usa um `pre-receive` no remoto com um contador em arquivo: recusa 1 vez (com um commit de outra issue enviado pelo próprio hook antes, simulando a corrida) e depois 3 vezes.
- `bash scripts/test-setup-ci.sh` (CA17): lê o YAML como os casos atuais (ordem dos passos, `if`, `with` do upload, `permissions`) e roda o script do passo que confere o alvo com e sem `screenshots:` no `Makefile`.
- `bash scripts/test-revisor-agent.sh` (CA18): corpo igual nos dois arquivos do revisor.
- CA1 a CA4, CA13 a CA16 e CA18: no repositório de teste com interface (privado, Next.js com Playwright e `docs/design.md`), com `claude --plugin-dir <clone>` na branch; issues e PRs fechados no fim com um comentário dizendo que eram teste. O CA14 depende do usuário abrir o PR no navegador.
- CA19: leitura do diff.

## Passos de produção
nenhum

## Riscos e dúvidas
- O link `raw` pode não aparecer num repositório privado em algum cliente (app do GitHub no celular, e-mail de notificação). O CA14 confere o navegador; se falhar, a decisão do ADR 0020 volta para a spec.
- O token fine-grained do agente precisa de `actions: read` para baixar o artefato; o guia de isolamento já pede leitura do Actions para os runs, mas o download não foi testado com ele.
- Screenshots de dados dinâmicos (datas, relógio) mudam a cada rodada; o modelo do guia fixa a data e os dados no teste.
- A `fabrica-telas` cresce sem limpeza (fora de escopo); a escala 3 do celular deixa cada PNG maior.
- O job do dispatcher precisa alcançar o download do Chromium, como já faz para o `make e2e`.

## Histórico
- 2026-11-24: criação.
- 2026-11-25: aprovada.
