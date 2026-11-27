# SPEC-136: Script de espera do CI substitui o laço improvisado no revisar

**Issue:** #136 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-27

## Contexto
Para esperar o CI, o `/fabrica:revisar` manda ler os runs do head pela API do Actions "repetindo a consulta até o fim" (passo 6, "Ler o CI", e o item 3 da "Verificação pendente para o CI" do passo 3). O intervalo, o tempo máximo e a forma do laço ficam por conta do agente, e as regras de "terminou", "verde" e "sem CI" (SPEC-116) estão em prosa. A skill `babysit-pr` do tstack resolve isso com um script que imprime uma linha por evento e sai com um código por resultado, mas lê checks, que o token fine-grained do [guia de isolamento](../docs/guias/isolamento-do-agente.md#token-fine-grained) não lê.

## Objetivo
A espera do CI no `revisar` é feita pelo `scripts/ci-wait.sh`, com um código de saída por resultado e testes com respostas simuladas da API.

## Comportamento esperado
**Chamada:** `bash scripts/ci-wait.sh <dono>/<repo> <sha> <desde>`, em que `<desde>` é o início da espera em UTC (`AAAA-MM-DDTHH:MM:SSZ`), guardado pela etapa antes da primeira chamada. Cada chamada roda no máximo uma **fatia** de 100 segundos e, se o resultado ainda não saiu, termina com o código `6` ("continua"). A etapa chama de novo com os mesmos argumentos até sair outro código. Os prazos contam do `<desde>`, não do início da chamada.

**Laço de cada chamada:** consulta `gh api "repos/<dono>/<repo>/actions/runs?head_sha=<sha>&per_page=100" --jq '<filtro>'` logo no início e depois a cada 30 segundos, e decide pela tabela abaixo, na ordem das linhas, a cada consulta que deu certo:

| Situação na consulta | Saída | Código |
|---|---|---|
| Ao menos um run, todos `completed`, todos com `conclusion` `success`, `skipped` ou `neutral` | `resultado: verde` | 0 |
| Ao menos um run, todos `completed`, algum com outra `conclusion` (inclusive vazia) | uma linha `falhou: <nome>\t<conclusion>\t<link>` por run assim, e `resultado: vermelho` | 1 |
| Nenhum run e tempo desde o `<desde>` ≥ 600 s | `resultado: sem-ci` | 3 |
| Algum run não `completed` (ou nenhum run antes dos 600 s) e tempo desde o `<desde>` ≥ 3600 s | `resultado: tempo-esgotado` | 4 |
| Nenhuma das anteriores e a fatia de 100 s acabou | `resultado: continua` | 6 |

- **Linha por mudança de estado:** a cada consulta que deu certo, o script imprime `<instante UTC> <nome>\t<status>\t<conclusion>\t<link>` para cada run novo ou com `status` ou `conclusion` diferente da consulta anterior **da mesma chamada**. Na primeira consulta de cada chamada, todos os runs saem. Sem runs, a primeira consulta imprime `<instante UTC> nenhum run do head`.
- **Falha da consulta:** o `gh api` sai com código diferente de 0. O script imprime `<instante UTC> falha ao ler os runs: <primeira linha do erro>` e tenta de novo no intervalo seguinte. Com **5 falhas seguidas**, imprime `resultado: erro-leitura` e sai com `5`. A contagem é da chamada: uma chamada nova começa do zero. Uma consulta que dá certo zera a contagem.
- **Uso inválido:** número de argumentos diferente de 3, repositório fora de `<dono>/<repo>`, SHA fora de `^[0-9a-f]{7,64}$`, `<desde>` fora do formato ou no futuro: mensagem de uso no stderr, código `2`, sem consultar a API.
- **Bordas dos prazos:** os dois limites são inclusivos: com exatamente 600 s e nenhum run, sai `sem-ci`; com exatamente 3600 s, sai `tempo-esgotado`. Um run que aparece antes dos 600 s desliga a regra do "sem CI" naquela consulta; numa consulta posterior sem runs (run apagado), a regra volta a valer. A fatia nunca passa do tempo máximo: uma chamada que começa aos 3550 s espera até os 3600 s e sai com `4`, sem esperar a fatia inteira.
- **Testes:** as variáveis `FABRICA_CI_WAIT_INTERVAL`, `FABRICA_CI_WAIT_SLICE`, `FABRICA_CI_WAIT_NO_CI` e `FABRICA_CI_WAIT_MAX` (segundos, inteiros ≥ 0) trocam os 30, 100, 600 e 3600 s. Um valor que não é inteiro é uso inválido (código 2).

**No `revisar`:** os dois lugares que esperam o CI (item 3 da "Verificação pendente para o CI" do passo 3 e o passo 6) guardam o `<desde>` com `date -u +%Y-%m-%dT%H:%M:%SZ`, chamam o script com o SHA de `git rev-parse HEAD` em `<wt>` e agem pelo código:

| Código | O que o `revisar` faz |
|---|---|
| 0 | CI verde: segue como hoje. |
| 1 | CI vermelho: segue como hoje (corrige se for pela mudança, registra e segue se for motivo externo), usando as linhas `falhou:` como nome e link de cada run. |
| 3 | Sem CI: segue como hoje ("registre no PR e siga"; com verificação pendente, o item 1 do passo 3). |
| 4 ou 5 | PR em rascunho (`gh pr ready --undo` se não estiver), sem `pronto-revisao`, `escalonado` e um comentário na issue com o marcador `<!-- fabrica:revisar -->` dizendo o resultado (`tempo-esgotado` ou `erro-leitura`), a última linha de estado e que a retomada é `/fabrica:revisar <nº>`. Pare. |
| 6 | Chame de novo com os mesmos argumentos. |
| 2 ou outro | Trate como o 5. |

- As regras de "terminou", "verde" e "sem CI depois de 10 minutos" saem da prosa do `SKILL.md`: a skill remete ao script e à tabela de códigos.
- Fica na skill a regra que não é do script: depois da "Retomada" do item 1 do passo 3 (projeto sem CI, verificação respondida pelo usuário), o PR é tratado como sem CI e o script não é chamado.
- A retomada com `/fabrica:revisar <nº>` depois de um código 4 ou 5 começa uma espera nova, com um `<desde>` novo.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com runs todos `completed` e conclusões `success`, `skipped` e `neutral`, o script imprime `resultado: verde` e sai com 0. | unitário (`scripts/test-ci-wait.sh`) |
| CA2 | Com runs todos `completed` e um `failure` e um `cancelled`, imprime uma linha `falhou:` com nome, conclusão e link de cada um dos dois, não imprime `falhou:` para os verdes, imprime `resultado: vermelho` e sai com 1. Um run `completed` com `conclusion` vazia também conta como falha. | unitário |
| CA3 | Com runs ainda `in_progress` na primeira consulta e todos `success` na terceira, o script espera e sai com 0; a saída tem uma linha de estado na primeira consulta e outra quando o run muda, e nenhuma linha repetida para a consulta sem mudança. | unitário |
| CA4 | Sem nenhum run e `<desde>` 600 s no passado (com `FABRICA_CI_WAIT_NO_CI` no padrão), sai com 3 e `resultado: sem-ci`; com 599 s e a fatia esgotada, sai com 6. | unitário, com `<desde>` calculado no teste |
| CA5 | Um run que aparece antes do prazo do "sem CI" impede o código 3: com o run ainda `queued` depois do prazo, o script sai com 6 (fatia) ou 4 (tempo máximo), nunca com 3. | unitário, com prazos curtos pelas variáveis |
| CA6 | Com um run `queued` e `<desde>` 3600 s no passado, sai com 4 e `resultado: tempo-esgotado`; uma chamada com `<desde>` a menos que uma fatia do tempo máximo sai com 4 ao chegar no máximo, antes do fim da fatia. | unitário, com prazos curtos pelas variáveis |
| CA7 | Com o `gh api` falhando 5 vezes seguidas, o script imprime uma linha de falha por consulta, `resultado: erro-leitura` e sai com 5; com 4 falhas seguidas de uma resposta verde, sai com 0. | unitário, com `gh` simulado no `PATH` |
| CA8 | Com argumentos a menos, repositório sem `/`, SHA inválido, `<desde>` mal formado, `<desde>` no futuro ou uma das variáveis não inteira, sai com 2 e não chama o `gh`. | unitário (o `gh` simulado registra as chamadas) |
| CA9 | A consulta é `actions/runs?head_sha=<sha>&per_page=100` no repositório passado, conferida pelos argumentos que o `gh` simulado recebeu. | unitário |
| CA10 | `skills/revisar/SKILL.md` chama o script no item 3 da "Verificação pendente para o CI" do passo 3 e no passo 6, traz a tabela de códigos desta spec e não descreve mais o laço nem as regras de "terminou", "verde" e "sem run em 10 minutos"; a regra da "Retomada" num projeto sem CI continua no passo 6. | revisão do diff |
| CA11 | `AGENTS.md` cita `bash scripts/test-ci-wait.sh` na lista de testes de `scripts/`, `docs/comandos.md` diz na seção do `/fabrica:revisar` que a espera do CI tem limite de 60 minutos e o que acontece ao esgotar, e `.claude-plugin/plugin.json` sobe a `version`. | revisão do diff |
| CA12 | `bash scripts/test-ci-wait.sh` roda em menos de 30 segundos (prazos curtos pelas variáveis) e entra no CI do repositório pelo laço `scripts/test-*.sh` do `.github/workflows/ci.yml`, sem mudança no workflow. | unitário, com o tempo medido no CI do PR |
| CA13 | Um `/fabrica:revisar` de verdade espera o CI pelo script num PR deste repositório: a saída da etapa mostra as chamadas ao `ci-wait.sh` e o PR recebe `pronto-revisao` só depois do `resultado: verde`. | manual — o próprio `/fabrica:revisar` desta issue, com `claude --plugin-dir <wt>` na branch |

## Fora de escopo
- Vigiar comentários e reviews do PR; os pedidos do usuário continuam lidos pelo passo 2 do `revisar`.
- Retomada por evento do dispatcher, que é a #107.
- Rever as regras de verde, vermelho e sem CI da SPEC-116: o script só as move da prosa para o código.
- A busca do artefato `telas` do CI (passo 3), que continua na skill.
- Mudar o `timeout-minutes` do `templates/workflows/agente.yml`.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/ci-wait.sh` (novo): o script descrito acima, em bash, com o filtro `--jq` que gera uma linha TSV por run (`name`, `status`, `conclusion`, `html_url`). O cabeçalho em comentário lista os códigos de saída.
- `scripts/test-ci-wait.sh` (novo): no padrão dos outros `test-*.sh` (funções `result` e `check`, contagem de falhas, `mktemp -d` com `trap`). Um `gh` simulado num `bin/` temporário no começo do `PATH` grava os argumentos de cada chamada e devolve, a cada chamada, a próxima resposta de uma sequência de arquivos (`saida-1.tsv`, `saida-2.tsv`, …, repetindo a última), ou sai com 1 quando o arquivo da vez se chama `falha-<n>`. Os prazos vêm das variáveis `FABRICA_CI_WAIT_*` com valores de 0 a 3 s.
- `skills/revisar/SKILL.md`: o item 3 da "Verificação pendente para o CI" do passo 3 remete ao "Ler o CI"; o "Ler o CI" do passo 6 passa a ser a chamada ao script e a tabela de códigos; os itens "Terminou", "Verde" e "Sem CI" saem, e fica só a frase da retomada num projeto sem CI.
- `AGENTS.md`: o teste novo na lista de `scripts/` (recomendação da triagem).
- `docs/comandos.md`: uma frase na seção do `/fabrica:revisar`.
- `.claude-plugin/plugin.json`: `version` de `0.60.0` para `0.61.0` (ou a próxima livre na hora do merge).
- `skills/status/estados.md`: sem mudança. O código 4 ou 5 deixa o PR em rascunho com `escalonado`, que já cai na linha 9 ("PR em rascunho… retome com `/fabrica:revisar <nº>`"), sem estado novo.

**Dados:** nenhum.

**Interfaces:** `ci-wait.sh <dono>/<repo> <sha> <desde>` → stdout com as linhas de estado e uma última linha `resultado: <verde|vermelho|sem-ci|tempo-esgotado|erro-leitura|continua>`; códigos 0, 1, 2, 3, 4, 5 e 6, como na tabela.

**Decisões:**
- **Fatias de 100 s com retomada pelo `<desde>`** — cada chamada cabe no tempo padrão de um comando Bash em primeiro plano (2 min no Claude Code, também no `claude -p` do dispatcher, e no OpenCode), sem depender de comando em segundo plano, que nem toda harness avisa ao terminar. Alternativa descartada: rodar o script inteiro em segundo plano, como o `/fabrica:avancar` faz com o `stage-model.sh run`, porque no OpenCode e no Antigravity a espera pelo aviso não está garantida e no `claude -p` a sessão pode terminar antes.
- **Intervalo fixo de 30 s** — dá 3 consultas por fatia e 120 por espera de 60 min, bem abaixo do limite de requisições do token. Alternativa descartada: intervalo crescente, que atrasa a resposta de um CI curto.
- **Tempo máximo de 60 minutos por espera, contados do `<desde>`** (recomendação da triagem) — o prazo precisa caber no passo de 100 minutos do dispatcher (`templates/workflows/agente.yml`) e na validade de 2 h da `em-andamento` (ADR 0003). Alternativa descartada: sem limite próprio, só o do job.
- **Tempo esgotado: PR em rascunho, sem `pronto-revisao`, `escalonado` e retomada com `/fabrica:revisar <nº>`** (recomendação da triagem) — o passo 6 só aplica a label com o CI verde, e a linha 9 de `estados.md` já prevê retomar por esse comando uma espera interrompida. Alternativa descartada: registrar no PR e seguir, como numa falha por motivo externo.
- **Sem lição no tempo esgotado nem no erro de leitura** — a demora depende do CI do projeto ou da API, não da qualidade do trabalho do agente, como a parada por ação externa. Alternativa descartada: lição com o gatilho `escalonado`, como na revisão parcial.
- **Falha ao consultar a API: tenta de novo e, com 5 falhas seguidas na chamada, sai com o código 5, tratado como o tempo esgotado** (recomendação da triagem) — sem leitura não há CI verde, e o resultado precisa ser determinístico. Alternativa descartada: tratar como "sem CI", que confundiria erro de leitura com projeto sem CI.
- **Critérios mantidos** (recomendação da triagem): "terminou" é todo run do head `completed`; "verde" é todo run `success`, `skipped` ou `neutral`; os 10 minutos sem run contam do início da espera; e a retomada num projeto sem CI não chama o script — são as regras do passo 6 (SPEC-116), e a issue só as move para o script. Alternativa descartada: rever as regras nesta issue.
- **Teste novo citado no `AGENTS.md`, e não no `CLAUDE.md`** (recomendação da triagem) — a lista de scripts fica no `AGENTS.md`, que o `CLAUDE.md` importa. Alternativa descartada: repetir a lista no `CLAUDE.md`.
- **`per_page=100` sem `--paginate`** — um head com mais de 100 runs não é caso real da fábrica, e a paginação complicaria o `gh` simulado. Alternativa descartada: `--paginate`.

**Fontes da documentação:**
- gh 2.105.0 — `gh api --help` (`-q`/`--jq`, `--paginate`).
- API REST do GitHub Actions, `GET /repos/{owner}/{repo}/actions/runs` (`head_sha`, `per_page`, campos `status`, `conclusion`, `name`, `html_url`) — não verificada; o endpoint já é usado pelo passo 6 atual (SPEC-116).
- Tempo padrão de comando em primeiro plano do Claude Code (2 min) — descrição da ferramenta Bash da sessão; do OpenCode e do Antigravity — não verificada.

**ADR:** nenhum.

## Testes
- `bash scripts/test-ci-wait.sh` cobre do CA1 ao CA9 e o tempo do CA12, com o `gh` simulado e os prazos curtos. Os `<desde>` no passado do CA4 e do CA6 são calculados com `date -u -d "@$(( $(date +%s) - N ))"`.
- CA10 e CA11: revisão do diff pelo revisor.
- CA13: o `/fabrica:revisar` desta própria issue, que espera o CI do PR pelo script novo.

## Passos de produção
nenhum

## Riscos e dúvidas
- Cada fatia é uma volta do agente: uma espera longa custa até 36 chamadas por espera, com poucos tokens cada. Se o custo pesar, a fatia pode crescer junto com o `timeout` do comando, numa issue própria.
- No dispatcher, várias esperas de até 60 minutos na mesma execução podem passar dos 100 minutos do passo; o job é cortado e a issue fica com `em-andamento` até vencer (ADR 0003), como hoje.
- A #135 mexe no mesmo passo 6 e espera o CI de novo depois de atualizar a branch; quem entrar depois resolve o conflito e passa a chamar o script também nessa espera.

## Histórico
- 2026-11-27: criação.
