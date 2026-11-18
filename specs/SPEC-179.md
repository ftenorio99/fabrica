# SPEC-179: roteia as etapas da fábrica por modelo com rótulos modelo:* e despacho no avancar

**Issue:** #179 · **PRD:** F10 (nova, veja "Decisões") · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-18

## Contexto
Hoje toda etapa roda no modelo da sessão. O `/fabrica:avancar` executa a etapa lendo o `SKILL.md` na própria sessão, então uma issue de documentação gasta o mesmo modelo de uma migração. O usuário decidiu usar três modelos do Claude Code (Opus 5.5, Sonnet 5.5 e Haiku 5.5), com o mais caro só onde o julgamento compensa. Os estudos #98 e #120 trazem os dados de capacidade e de robustez a injeção que sustentam a tabela abaixo. O PRD hoje não tem funcionalidade para isso, e a linha "Roteamento entre modelos e ferramentas" do "Fora de escopo" fala da Fase 3 (OpenRouter e OpenCode).

## Objetivo
Cada etapa executada pelo `/fabrica:avancar` roda num processo `claude -p` com o modelo que a tabela da fábrica dá para aquela etapa e aquela issue, e uma issue que falha num modelo menor sobe para o seguinte.

## Comportamento esperado
**Rótulo da issue**
- Três labels: `modelo:haiku`, `modelo:sonnet` e `modelo:opus`. A triagem aplica uma delas, com a razão em uma linha. O usuário pode trocá-la até aplicar `spec-aprovada`.
- Critério da triagem: `haiku` para documentação, chore, renomeação e teste simples, sem arquivo sensível; `opus` para classe `implementacao-complexa` que toca arquivo sensível (autenticação, pagamentos, migração, `.github/`), decisão de arquitetura ou ambiguidade que a spec vai resolver; `sonnet` nos outros casos.
- Se a issue já tem uma label `modelo:*` quando a triagem roda, a triagem a mantém e só registra o valor na tabela.
- Sem label `modelo:*`, vale `sonnet`. Duas ou mais labels `modelo:*` na mesma issue são inconsistência.
- As labels `modelo:*` não mudam o estado da issue.

**Modelo por etapa** (tabela em `skills/avancar/modelos.md`)

| Etapa | Modelo | Esforço |
|---|---|---|
| `triagem` | `sonnet` | padrão |
| `spec` | `opus` | `medium` |
| `implementar` | o da label `modelo:*` | padrão |
| `revisar` | `opus` se a label é `modelo:opus`; senão `sonnet` | padrão |

| Apelido | ID |
|---|---|
| `haiku` | `claude-haiku-5-5` |
| `sonnet` | `claude-sonnet-5-5` |
| `opus` | `claude-opus-5-5` |

**Despacho**
1. Para cada etapa, o `avancar` roda `bash <plugin>/scripts/stage-model.sh run <etapa> <nº> <labels…>` em segundo plano (a etapa pode passar dos 10 min de um comando em primeiro plano) e espera o fim.
2. O script monta e executa `claude -p --model <id> [--effort <esforço>] --permission-mode auto --output-format json [--plugin-dir <clone>] "/fabrica:<etapa> <nº>"` no diretório do projeto e grava o JSON de saída. O `--plugin-dir` só entra quando o plugin roda de um clone, e não da pasta de plugins instalados (`~/.claude/plugins/`).
3. O prompt leva só o comando e o número ([ADR 0008](../docs/adr/0008-texto-externo-fora-do-prompt.md)). Número que não é inteiro positivo é recusado antes de chamar o `claude`.
4. O relatório do `avancar` ganha a coluna "Modelo", com os modelos de cada etapa lidos do `modelUsage` do JSON.
5. **Revisão encadeada:** o `implementar` continua encadeando o `revisar` no mesmo processo, no modelo do `implementar`. O julgamento da revisão, que é o subagente `revisor`, roda no modelo da linha `revisar` da tabela: o `revisar` passa esse apelido no `model` da chamada do subagente.
6. **Sem o `claude`:** se o binário (`FABRICA_CLAUDE_BIN`, padrão `claude`) não existe, o `avancar` executa a etapa na sessão, como hoje, e a coluna "Modelo" mostra `sessão`. Isso mantém o `avancar` funcionando no OpenCode e no Antigravity.

**Escalonamento de modelo** (só `implementar` e `revisar`)
- **Falha de qualidade:** a etapa registrou, nesta execução, uma lição `rodadas` ou `achado-pendente`, ou o processo terminou com erro (`is_error` no JSON ou saída diferente de zero). Parada por permissão negada (texto do classificador ou hook no resultado), `precisa-info`, `acao-externa` e escalonamento por mudança de escopo não contam.
- A cada falha de qualidade, o `avancar` registra uma lição com o gatilho novo `modelo`: um bloco com `**Falha:** modelo=<apelido> etapa=<etapa> motivo=<rodadas|achado-pendente|erro>`.
- **Subida:** o número de falhas é o de blocos `**Falha:**` com o modelo atual na lição `modelo` da issue. `haiku` com 1 falha sobe para `sonnet`; `sonnet` com 2 falhas sobe para `opus`; `opus` não sobe. Na subida, o `avancar` troca a label (`--remove-label modelo:<de> --add-label modelo:<para>`) e acrescenta à lição um bloco `**Troca:** <de> → <para>`.
- A subida não retoma a etapa: a issue segue no estado em que a etapa a deixou (em geral `escalonado`), e a próxima execução já usa o modelo novo.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `scripts/setup-labels.sh` cria ou corrige `modelo:haiku`, `modelo:sonnet` e `modelo:opus` a partir da tabela "Labels" de `estados.md`, com cor e descrição | manual — `scripts/setup-labels.sh ftenorio99/fabrica` na branch e `gh label list` |
| CA2 | `stage-model.sh model <etapa> <labels…>` imprime `<apelido> <id> <esforço>` conforme a tabela: `triagem` → `sonnet claude-sonnet-5-5 padrao`; `spec` → `opus claude-opus-5-5 medium`, com qualquer label; `implementar` sem label → `sonnet`; `implementar` com `modelo:haiku` → `haiku`; `revisar` com `modelo:haiku` → `sonnet`; `revisar` com `modelo:opus` → `opus` | unitário — `scripts/test-stage-model.sh` |
| CA3 | Com duas ou mais labels `modelo:*`, `stage-model.sh` sai com código 2 e uma mensagem; com etapa desconhecida, sai com código 1 | unitário — `scripts/test-stage-model.sh` |
| CA4 | `stage-model.sh next <apelido> <falhas>`: `haiku 0` → `haiku`; `haiku 1` → `sonnet`; `sonnet 1` → `sonnet`; `sonnet 2` → `opus`; `sonnet 3` → `opus`; `opus 5` → `opus`. Falhas negativas ou não numéricas saem com código 1 | unitário — `scripts/test-stage-model.sh` |
| CA5 | `stage-model.sh run` chama o binário de `FABRICA_CLAUDE_BIN` com `-p`, o `--model` e o `--effort` da tabela (sem `--effort` quando é `padrao`), `--permission-mode auto`, `--output-format json` e, como último argumento, exatamente `/fabrica:<etapa> <nº>`. Com `<nº>` não inteiro (ex.: `12; rm`), sai com código 1 sem chamar o binário | unitário — `scripts/test-stage-model.sh`, com um `claude` falso que grava os argumentos |
| CA6 | `stage-model.sh run` passa `--plugin-dir <clone>` quando o script roda de fora de `~/.claude/plugins/`, e não passa quando roda de dentro | unitário — `scripts/test-stage-model.sh`, com `HOME` apontando para uma pasta temporária |
| CA7 | A triagem acrescenta a linha `Modelo` à tabela do comentário (apelido e razão) e aplica a label; numa issue que já tem `modelo:*`, mantém a label e registra o valor | manual — issue de teste de documentação, `claude --plugin-dir <clone>` com `/fabrica:triagem <nº>` |
| CA8 | O `/fabrica:avancar <nº>` numa issue de teste de documentação roda a triagem e a spec cada uma num `claude -p`, e o relatório mostra `sonnet` na triagem e `opus` na spec, lidos do `modelUsage` | manual — issue de teste, `claude --plugin-dir <clone>`, fechada no fim com um comentário dizendo que era teste |
| CA9 | Com `FABRICA_CLAUDE_BIN` apontando para um caminho que não existe, o `avancar` executa a etapa na sessão e mostra `sessão` na coluna "Modelo" | manual — mesma issue de teste do CA8 |
| CA10 | Numa falha de qualidade, o `avancar` registra o bloco `**Falha:**` na lição `modelo`, e na subida troca a label e registra `**Troca:**`. Parada por permissão negada não gera bloco | manual — issue de teste com `modelo:haiku` cuja spec curta tem dois CAs contraditórios, para forçar `rodadas` |
| CA11 | `estados.md` documenta as três labels, a regra de que elas não mudam o estado e a inconsistência de duas ou mais; o `/fabrica:status` mostra essa inconsistência nos alertas | manual — issue de teste com duas labels `modelo:*`, `/fabrica:status` com `--plugin-dir` |
| CA12 | `docs/prd.md` tem a F10 e a linha da Fase 3 no "Fora de escopo" passa a excluir só o roteamento entre provedores; `skills/licao/formato.md` lista o gatilho `modelo`; `docs/comandos.md` e `docs/fluxo.md` descrevem o modelo por etapa; o ADR 0013 existe | manual — leitura do diff |

## Fora de escopo
- `effort` e `maxTurns` no frontmatter das skills e do revisor (#98), fora o `medium` da spec da tabela acima.
- Separar tokens por modelo na linha de custo e no `/fabrica:metricas` (#120). O relatório do `avancar` já mostra o modelo.
- O dispatcher no GitHub Actions (#99, #108). O `stage-model.sh run` serve de base para ele depois.
- Roteamento entre provedores (OpenRouter, OpenCode como motor): Fase 3.
- Mudar o modelo das etapas `status`, `metricas`, `backlog`, `prd`, `retro` e `setup`, que não passam pelo `avancar`.
- Paralelismo entre issues: o `avancar` continua executando uma etapa por vez.

## Desenho técnico
**Arquivos e módulos:**
- `skills/avancar/modelos.md` (novo): as duas tabelas da seção "Comportamento esperado" (etapa → modelo e esforço; apelido → ID). Ponto único para trocar de versão.
- `scripts/stage-model.sh` (novo): lê `modelos.md` com `awk`, como o `setup-labels.sh` lê `estados.md`. Subcomandos `model`, `next` e `run`.
- `scripts/test-stage-model.sh` (novo): testes dos CA2 a CA6, no formato de `scripts/test-acao-status.sh` (função `check`, contagem de falhas, saída diferente de zero quando algo falha).
- `skills/avancar/SKILL.md`: passo 3 ("Como executar") passa a despachar pelo `stage-model.sh run` em segundo plano, com o caminho sem o `claude`; passo 4 ganha a detecção de falha de qualidade e a subida; passo 5 ganha a coluna "Modelo".
- `skills/triagem/SKILL.md`: linha `Modelo` na tabela do passo 4, critério do rótulo no passo 2 e o `gh issue edit --add-label modelo:<apelido>`.
- `skills/revisar/SKILL.md`: a chamada do subagente `revisor` passa o `model` com o apelido de `stage-model.sh model revisar <labels…>`.
- `skills/status/estados.md`: três linhas na tabela "Labels" (quem aplica: triagem, avancar, usuário), a regra de que não mudam o estado e a inconsistência.
- `skills/status/SKILL.md`: o alerta da inconsistência.
- `skills/licao/formato.md`: gatilho `modelo`, aplicado pelo `avancar`, com os blocos `**Falha:**` e `**Troca:**`.
- `docs/prd.md`: F10 e a linha da Fase 3.
- `docs/comandos.md`, `docs/fluxo.md`: o modelo por etapa e o escalonamento.
- `docs/adr/0013-modelo-por-etapa-e-por-issue.md` (novo).
- `AGENTS.md`: o `test-stage-model.sh` na lista de testes de `scripts/`.
- `.claude-plugin/plugin.json`: sobe a `version` (minor), porque o comportamento do `avancar`, da triagem e do `revisar` muda.

**Dados:** nenhum.

**Interfaces:**
- `stage-model.sh model <etapa> [label…]` → `<apelido> <id> <esforço>` (esforço `padrao` quando não há). Saída 0; 1 etapa desconhecida ou tabela ilegível; 2 duas ou mais labels `modelo:*`.
- `stage-model.sh next <apelido> <falhas>` → `<apelido>`. Saída 0; 1 apelido desconhecido ou falhas inválidas.
- `stage-model.sh run <etapa> <nº> [label…]` → executa o `claude` e repassa a saída dele (o JSON) e o código de saída. Saída 1 sem executar para `<nº>` inválido; 2 para labels inconsistentes.
- Variáveis: `FABRICA_CLAUDE_BIN` (binário, padrão `claude`); `FABRICA_MODELS_FILE` (troca o caminho de `modelos.md`, só para os testes).

**Decisões:**
- **Um `claude -p` por etapa** — é a forma de trocar o modelo por etapa sem trocar o da sessão, e o teste de 2026-11-18 confirmou que o `claude -p "/<plugin>:<skill> <arg>"` executa uma skill com `disable-model-invocation: true` e substitui o `$ARGUMENTS` (Claude Code 2.1.327, plugin descartável, `modelUsage` com `claude-haiku-5-5`). Alternativa descartada: subagente com `model`, porque o `implementar` já chama o subagente `revisor` e um subagente não cria outro.
- **Tabela num arquivo só, lida pelo `avancar` (recomendação da triagem)** — a issue pede os IDs em um ponto único e a #140 propõe juntar regras comuns. Alternativa descartada: o frontmatter de cada skill (#98), que fixa o modelo por etapa mas não deixa o rótulo da issue decidir.
- **F10 no PRD e a linha da Fase 3 esclarecida (recomendação da triagem)** — a decisão do usuário na issue é rotear entre modelos do próprio Claude Code, o que a linha atual parece excluir. Alternativa descartada: tratar a #179 como melhoria sem funcionalidade do PRD.
- **ADR 0013 (recomendação da triagem)** — a escolha de modelo por exposição a conteúdo externo muda o desenho de todas as etapas, como os ADRs 0005 e 0008. Alternativa descartada: só documentar em `docs/fluxo.md`.
- **Triagem no Sonnet e spec no Opus em esforço médio** — decisão do usuário na issue (2026-11-17), apoiada na #120: a triagem é a primeira a ler texto de issue, e o Sonnet 5.5 resiste bem mais a injeção que o Opus 5.5. A spec lê comentários do usuário só pelo `gh` (ADR 0008), nunca no prompt. Alternativa descartada: Opus na triagem.
- **`--permission-mode auto` no processo da etapa** — o `-p` não tem a quem perguntar, e o `auto` mantém o classificador como camada além dos hooks `protect-main` e `protect-production`, que valem no `-p`. Alternativa descartada: `bypassPermissions` dentro da VM do sbx, que tira essa camada; a #122 estuda o assunto.
- **Revisor no modelo da tabela, mesmo encadeado** — o julgamento é o que a tabela quer proteger, e o resto do `revisar` (PR, CI) é mecânico. Alternativa descartada: um segundo `claude -p` para o `revisar`, que quebraria o encadeamento atual do `implementar`.
- **Escalonamento por lição `modelo`** — o estado da fábrica mora no GitHub, sem arquivo local, e a lição já é o registro de eventos por issue. Alternativa descartada: contar as lições `rodadas` e `achado-pendente`, que não dizem em que modelo a falha aconteceu.

**Fontes da documentação:**
- Claude Code 2.1.327 — `claude --help` (`--model`, `--effort`, `--permission-mode`, `--output-format`, `--plugin-dir`); `/websites/code_claude` no Context7, "Control who invokes a skill" e "Run a prompt repeatedly with /loop", que não respondem sobre o `-p`; por isso o teste com plugin descartável.
- gh 2.104.0 — `gh issue edit --help` (`--add-label`, `--remove-label`), `gh label create --help`.

**ADR:** [docs/adr/0013-modelo-por-etapa-e-por-issue.md](../docs/adr/0013-modelo-por-etapa-e-por-issue.md)

## Testes
- `bash scripts/test-stage-model.sh`: CA2 a CA6. O `claude` falso é um script na pasta temporária do teste que grava um argumento por linha e imprime um JSON fixo; o teste confere a lista de argumentos e que o último é exatamente `/fabrica:<etapa> <nº>`.
- `make lint` e `make test` do repositório, se cobrirem os scripts; senão, o teste novo entra onde os outros `scripts/test-*.sh` rodam.
- CA1, CA7 a CA11: issue de teste no próprio repositório, com o plugin pela branch (`claude --plugin-dir ~/projetos/fabrica`), fechada no fim com um comentário dizendo que era teste.

## Passos de produção
nenhum

## Riscos e dúvidas
- O processo `claude -p` herda hooks e settings do projeto, mas não a conversa: uma etapa que hoje se apoia em algo dito antes na sessão do `avancar` perde isso. As etapas já são escritas para rodar sozinhas, então o risco é baixo.
- O `auto` no `-p` aborta quando o classificador bloqueia várias vezes seguidas. Isso aparece como parada por permissão, não como falha de qualidade, e não sobe o modelo.
- O limite de uso da assinatura é por modelo: spec e revisão de issues `opus` no Opus podem gastar a cota mais rápido. O relatório com a coluna "Modelo" ajuda a acompanhar até a #120 medir.
- O CA10 força uma falha com uma spec contraditória e pode custar algumas execuções do Haiku.

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
