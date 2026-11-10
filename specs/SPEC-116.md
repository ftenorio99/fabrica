# SPEC-116: Verificação de integração pelo CI do PR quando o sandbox não a deixa rodar

**Issue:** #116 · **PRD:** F1 (sandbox, ADR 0005) e F3 (verificação) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-10

## Contexto
O sandbox da ADR 0005 isola os comandos Bash do agente. No Linux, segundo a documentação do sandbox do Claude Code:
- todo socket Unix fica bloqueado, inclusive o do Docker;
- o `localhost` de cada comando é privado, então o banco da máquina fica fora de alcance;
- nenhuma configuração libera essas duas coisas sem desmontar o isolamento.

Na kairo#91, o `/fabrica:implementar` terminou o código e escalonou, porque o `make test` (Docker e Postgres) e o `make e2e` não rodaram. O `prettier --check .` também falhou com `EACCES` nos caminhos protegidos que o sandbox monta na raiz.

O CI do kairo já roda `make lint`, `make test` e `make e2e` com o banco, mas só dispara em `pull_request`. O token fine-grained da ADR 0005 não lê checks, e o `gh pr checks` falha com "Resource not accessible by personal access token" (kairo#89).

## Objetivo
No sandbox, o agente roda a verificação que cabe nele. A verificação que depende do Docker ou do `localhost` da máquina passa a ser comprovada pelo CI de um PR em rascunho, lido pela API do Actions. O setup deixa o `prettier --check .` rodar no sandbox. O sandbox não é afrouxado.

## Comportamento esperado

### Implementar (passo Verificar)
1. O agente roda `make lint` e `make test`, e `make e2e` se a spec pedir, como hoje.
2. Uma falha cuja saída traz uma **assinatura de limite do sandbox** não conta como falha da implementação. As assinaturas são:
   - `docker.sock` junto com `permission denied`, `EACCES` ou `connect: operation not permitted`;
   - `ECONNREFUSED` (ou `Connection refused`) para `127.0.0.1`, `::1` ou `localhost`;
   - `Operation not permitted` ao criar um socket (`socket(AF_UNIX`).
3. Nesse caso, o agente roda as partes do projeto que não dependem do bloqueio, quando o projeto as separa (ex.: o projeto `unit` do Vitest, o `typecheck`, o ESLint), e anota cada comando bloqueado com a assinatura que apareceu. As anotações vão para o `revisar` como **verificação pendente para o CI**.
4. Um erro sem assinatura conta como falha e segue a regra das duas rodadas de hoje. Se o mesmo comando falha com assinatura e com outro erro, vale o outro erro.
5. Sem verificação pendente, o fluxo é o de hoje.

### Revisar
1. **Pré-requisito:** `make lint` e `make test` passam, ou falham só com as assinaturas, com a verificação pendente anotada pelo `implementar`.
2. **Sem CI que verifique:** se há verificação pendente e nenhum workflow em `.github/workflows/` dispara em `pull_request`, a etapa escalona antes da revisão. Ela comenta na issue os comandos bloqueados, aplica `escalonado` e pede ao usuário a verificação com `!`.
3. **Com verificação pendente**, a ordem muda:
   1. abre o PR em rascunho (`gh pr create --draft`), com o corpo do passo 5 e os CAs de integração com ⏳ "aguardando o CI". Se o PR já existe, usa ele, e converte para rascunho com `gh pr ready --undo` se não estiver;
   2. espera o CI do head pela API do Actions;
   3. passa ao revisor as anotações e o resultado do CI (nome, `conclusion` e link de cada run);
   4. corrige os achados e, a cada push, espera o CI do head novo;
   5. com CI verde e sem achados bloqueantes, tira o rascunho com `gh pr ready` e aplica `pronto-revisao`.
4. **CI vermelho:** conta como rodada, como hoje. Depois de duas rodadas de correção, o PR fica em rascunho, a issue ganha `escalonado` e os achados pendentes vão para o PR.
5. **Sempre, com ou sem verificação pendente:** o passo de CI deixa o `gh pr checks --watch` e lê os runs pela API do Actions:
   ```
   gh api "repos/<dono>/<repo>/actions/runs?head_sha=<sha>" -q '.workflow_runs[] | [.name, .status, .conclusion, .html_url] | @tsv'
   ```
   - **CI terminou:** todos os runs do head estão com `status` `completed`.
   - **Verde:** nenhum run tem `conclusion` diferente de `success`, `skipped` ou `neutral`.
   - **Sem nenhum run do head depois de 10 minutos:** o PR não tem CI. A etapa registra isso no PR e segue, como hoje faz com o CI ausente.
6. **Evidência no PR:** cada CA verificado pelo CI leva na coluna "Evidência" o nome e o link do run, e o PR ganha a linha "Verificação de integração pelo CI (ADR 0007)".

### Revisor
- **Verificações:** o revisor roda `make lint` e `make test`. Uma falha com assinatura de limite do sandbox vira "bloqueado pelo sandbox (<assinatura>)", e não um achado.
- **CI como evidência:** um CA de integração ou de ponta a ponta conta como atendido com o run verde do CI do head, desde que o teste que o cobre exista e teste de fato o critério.
- **Sem o resultado do CI:** um CA que depende de verificação bloqueada fica `parcial`, com a evidência "bloqueado pelo sandbox, sem resultado do CI".

### Setup (`.prettierignore`)
1. **Os caminhos:** os protegidos que o sandbox do Claude Code monta na raiz do projeto, conferidos numa sessão aninhada do Claude Code 2.1.322: `.bash_profile`, `.bashrc`, `.gitconfig`, `.gitmodules`, `.idea`, `.mcp.json`, `.profile`, `.ripgreprc`, `.vscode`, `.zprofile` e `.zshrc`.
2. **Quando o setup grava:** se o projeto tem `.prettierignore`, o `setup-sandbox.sh` acrescenta os caminhos que faltam, num bloco no fim do arquivo:
   ```
   # Caminhos que o sandbox do Claude Code monta na raiz (fabrica#116)
   /.bashrc
   ...
   ```
   Cada linha é `/<caminho>`, ancorada na raiz.
3. **Caminhos que ficam de fora:** os versionados no projeto (`git ls-files` acha o arquivo ou algo dentro da pasta) continuam sendo formatados e não entram no bloco. Uma linha que o arquivo já tem, igual ou sem a barra inicial, também não entra.
4. **Sem `.prettierignore`:** o setup não cria o arquivo e não reporta nada.
5. **`--check`:** reporta `prettierignore:<caminho>` para cada caminho que falta, junto dos itens de hoje no `incompleto`.
6. **Escrita negada:** se o `.prettierignore` não pode ser gravado, sai o aviso em stderr, o código fica 1 e o settings já gravado fica.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/implementar/SKILL.md`, no passo Verificar, traz: as assinaturas de limite do sandbox; rodar as partes que não dependem do bloqueio; anotar a verificação pendente para o `revisar`; um erro sem assinatura conta como falha, como hoje. | revisão do diff |
| CA2 | `skills/revisar/SKILL.md` traz: o pré-requisito novo; o escalonamento sem workflow de `pull_request`; a ordem PR em rascunho → CI → revisor → `gh pr ready`; a leitura dos runs pela API do Actions no lugar do `gh pr checks --watch`, com as regras de "terminou", "verde" e "sem run em 10 minutos"; a evidência do run nos CAs. | revisão do diff |
| CA3 | `agents/revisor.md` trata a falha com assinatura como "bloqueado pelo sandbox", aceita o run verde do CI como evidência de CA de integração e marca `parcial` sem o resultado do CI. | revisão do diff |
| CA4 | Num projeto com `.prettierignore` e sem nenhum dos caminhos versionado, a instalação acrescenta o bloco com os 11 caminhos, e o `--check` anterior lista `prettierignore:/.bashrc` etc. | unitário (`scripts/test-setup-sandbox.sh`) |
| CA5 | Um caminho versionado (ex.: `.vscode/settings.json` no `git ls-files`) e um que o arquivo já tem (`.idea` sem barra) não entram no bloco. Uma segunda instalação não muda o arquivo, e o `--check` sai `ok`. As linhas do usuário ficam. | unitário |
| CA6 | Sem `.prettierignore`, nada é criado nem reportado. Com o `.prettierignore` sem permissão de escrita, sai o aviso em stderr e o código 1. | unitário |
| CA7 | Na kairo#91, com `escalonado` removido pelo usuário, o `/fabrica:revisar 91` do plugin desta branch, rodado no sandbox do kairo: anota o `make test` bloqueado, usa o PR em rascunho kairo#96, espera o CI pela API do Actions, passa o resultado ao revisor e, com CI verde e sem achado bloqueante, tira o rascunho e aplica `pronto-revisao`. | manual: `claude --plugin-dir <clone>` na branch, no kairo |
| CA8 | Numa cópia do kairo com o setup desta branch aplicado, o `prettier --check .` passa numa sessão aninhada no sandbox. | manual: sessão aninhada com `claude -p --settings`, como no aceite da #94 |
| CA9 | `docs/guias/isolamento-do-agente.md` ganha a seção "O que não roda no sandbox do Linux", com o motivo de cada limite e o caminho pelo CI. Também ficam em dia: o passo Sandbox de `skills/setup/SKILL.md`, a descrição do revisar em `docs/comandos.md`, a ADR 0007 (`proposto`, depois `aceito`), a nota na ADR 0005 e o `plugin.json` em `0.29.0`. | revisão do diff |

## Fora de escopo
- Liberar o socket do Docker (`allowAllUnixSockets`) ou pôr `make test`, `make e2e` ou `docker *` em `excludedCommands`.
- Banco embutido nos testes do kairo (ex.: PGlite).
- O `/fabrica:status` e o `/fabrica:avancar`, que leem o CI pelo `statusCheckRollup` do `gh pr list` e esbarram na mesma permissão do token. Fica para uma issue nova.
- Liberar no setup os domínios do build (ex.: Google Fonts). O guia explica como acrescentar em `allowedDomains`, e cada projeto decide.
- O runner isolado da #106.

## Desenho técnico
**Arquivos e módulos:**
- `skills/implementar/SKILL.md`: passo 4 (Verificar) e passo 5 (levar as anotações ao `revisar`).
- `skills/revisar/SKILL.md`: passos 1, 3, 5 e 6.
- `agents/revisor.md`: Regras, "O que fazer" (item 3 e item 4) e o formato de "Verificações".
- `scripts/setup-sandbox.sh`: uma função no Python embutido que lê `<projeto>/.prettierignore` e roda `git -C <projeto> ls-files -- <caminho>` para cada caminho. Ela anota os itens `prettierignore:` no `missing` do projeto e grava o bloco depois do settings.
- `scripts/test-setup-sandbox.sh`: casos dos CA4 a CA6.
- `skills/setup/SKILL.md`, `docs/guias/isolamento-do-agente.md`, `docs/comandos.md`, `docs/adr/0005-isolamento-do-agente-em-sandbox.md`, `docs/adr/0007-verificacao-de-integracao-pelo-ci.md` e `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:**
- **`setup-sandbox.sh --check`:** item novo `prettierignore:/<caminho>`. Os códigos de saída não mudam.
- **Anotação "verificação pendente para o CI":** o `implementar` a entrega ao `revisar` como lista de linhas `<comando>: bloqueado pelo sandbox (<assinatura>)`.
- **Leitura do CI:** a consulta da seção "Revisar", item 5.

**Decisões:**
- **Reconhecer o limite do sandbox por assinaturas fixas do erro** (recomendação da triagem). A issue nomeia os três casos, e o CI é a rede de segurança: uma falha real confundida com bloqueio aparece no CI e custa uma rodada. Alternativa descartada: o projeto declarar no `CLAUDE.md` quais comandos só rodam no CI, o que exige mudar cada projeto antes.
- **PR em rascunho antes do revisor** (recomendação da triagem). O CI do kairo só dispara em `pull_request`, e o revisor precisa do resultado para dar parecer sobre os CAs de integração. Alternativa descartada: esperar o CI só no passo 6, depois do parecer.
- **CI pela API do Actions** (recomendação da triagem). O token fine-grained da ADR 0005 não lê checks. Alternativa descartada: pedir a permissão de checks no token, que amplia o que ele alcança.
- **No `.prettierignore`, só os caminhos não versionados, ancorados na raiz** (recomendação da triagem). Um `.vscode/` versionado continua formatado. Alternativa descartada: ignorar a lista inteira.
- **ADR nova, a 0007** (recomendação da triagem). A regra muda o portão de verificação de todos os projetos. Alternativa descartada: só uma nota na ADR 0005.
- **Sem workflow de `pull_request`, escalonar** (recomendação da triagem). Sem CI, ninguém verifica. Alternativa descartada: seguir sem a verificação.
- **10 minutos sem nenhum run do head = sem CI.** Assim o passo não espera para sempre por um workflow que não dispara. Alternativa descartada: esperar sem limite, que trava o `/fabrica:avancar`.
- **A lista de caminhos fica fixa no script, conferida empiricamente.** A documentação do sandbox lista mais caminhos protegidos do que os que aparecem na raiz. A lista conferida na sessão aninhada é a que quebra o Prettier. Alternativa descartada: a lista completa da documentação, que poria no `.prettierignore` caminhos que nunca aparecem.
- **Nenhum estado novo em `skills/status/estados.md`.** Durante a espera do CI, o PR em rascunho fica com `em-andamento`, e a etapa sempre termina com o PR pronto ou com `escalonado`, que vem antes da linha 9. Alternativa descartada: um estado "Aguardando CI".

**Fontes da documentação:**
- Sandbox do Claude Code: code.claude.com/docs/en/sandboxing ("A command fails to reach a server on localhost", "Network isolation", "Protected paths") e settings-reference (`allowAllUnixSockets`, `allowLocalBinding`, `excludedCommands`), via Context7 `/websites/code_claude`. Versão não confirmada. Lista de caminhos montados conferida no Claude Code 2.1.322.
- gh 2.103.3: `gh pr ready --help` (`--undo` converte para rascunho), `gh pr create --help` (`--draft`), `gh api --help` (`-q`).
- API do GitHub Actions: `GET /repos/{owner}/{repo}/actions/runs?head_sha=`, já usada na kairo#89 e na #96. A documentação não foi consultada nesta etapa.

**ADR:** [docs/adr/0007-verificacao-de-integracao-pelo-ci.md](../docs/adr/0007-verificacao-de-integracao-pelo-ci.md) (proposto).

## Testes
- **`bash scripts/test-setup-sandbox.sh`:** casos novos, em projeto temporário com `git init`:
  - `.prettierignore` com uma linha do usuário (CA4);
  - `.vscode/settings.json` versionado e `.idea` sem barra (CA5);
  - sem o arquivo, e com o arquivo em `chmod 444` (CA6).
- **`bash scripts/test-protect-main.sh`, `test-protect-production.sh` e `test-statusline.sh`:** continuam passando.
- **CA7 e CA8:** manuais, com o resultado no PR. O CA7 depende de você tirar o `escalonado` da kairo#91 antes. Sem isso, ele fica para depois do merge, como desvio registrado.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Assinaturas mudam:** uma versão nova do Docker ou do driver do Postgres pode mudar o texto do erro. Aí o agente escalona como hoje, e a lista é ajustada.
- **Lista de caminhos montados muda:** o Claude Code pode montar outros caminhos. O `prettier --check .` volta a falhar, e o achado aparece como hoje.
- **Espera do CI:** o `e2e` do kairo leva alguns minutos. A etapa fica mais longa, mas sem intervenção sua.
- **`/fabrica:status` e `/fabrica:avancar`:** continuam lendo o CI pelo `statusCheckRollup`. Com o token fine-grained, a linha 10 ("CI vermelho") pode não ser detectada. Fica para a issue nova.
- **Arquivo sensível:** a mudança muda o portão automático de verificação. A revisão humana é obrigatória.

## Histórico
- 2026-11-10: criação.
