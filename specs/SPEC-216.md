# SPEC-216: agy: orquestração no /fabrica:avancar com run_workflow e /swarm

**Issue:** #216 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-25

## Contexto
Hoje [`skills/avancar/SKILL.md`](../skills/avancar/SKILL.md) trata a harness `antigravity` dentro do caminho genérico **"Etapa na sessão"**, compartilhado com o `opencode`. Nesse caminho, as etapas rodam sequencialmente na sessão principal, acumulando contexto entre issues e etapas, sem paralelismo entre issues independentes e sem usar as primitivas nativas do Antigravity (`run_workflow` e `/swarm`).

A issue #149 iniciou a portabilidade da fábrica para o `agy`. Esta spec define a separação do caminho `antigravity` no `/fabrica:avancar` para orquestrar etapas em contexto isolado via `run_workflow`, mantendo o `opencode` no caminho sequencial de sessão e deixando o `/swarm` documentado apenas para invocação explícita do usuário.

## Objetivo
O `/fabrica:avancar` passa a tratar a harness `antigravity` em um caminho próprio que usa `run_workflow` para rodar cada issue em `pipeline` (com `implementar` e `revisar` em estágios separados) e issues independentes em `parallel`, respeitando o teto de 4 etapas, o lock `em-andamento` e o isolamento por worktree, enquanto documenta o papel opcional do `/swarm`.

## Comportamento esperado
1. **Detecção da harness:** no passo 3 de `skills/avancar/SKILL.md`, `bash scripts/harness.sh detect` separa os caminhos:
   - `opencode`: mantém o caminho **"Etapa na sessão"** (sequencial na sessão principal, sem `run_workflow`).
   - `antigravity`: segue o novo caminho **"Orquestração com `run_workflow` (Antigravity)"**.
   - `claude-code` ou `binario`: mantém o caminho `claude -p` (com fallback para "Etapa na sessão" se o binário `claude` não existir).
2. **Coleta e seleção na sessão principal:** os passos 1 (`Coletar`, incluindo `issue-worktree.sh clean` e leitura de `em-andamento`) e 2 (`Selecionar`, aplicando a tabela de estados de `skills/status/estados.md` e ordenando por proximidade do merge) continuam rodando na sessão principal do `/fabrica:avancar` antes de chamar `run_workflow`.
   - **Caso 0 issues selecionadas:** `run_workflow` não é chamado; o relatório final informa que não há issues de agente e indica `/fabrica:status`.
3. **Orquestração via `run_workflow`:**
   - A sessão principal chama `run_workflow` passando apenas a lista estruturada das issues selecionadas (número, estado atual e próxima etapa — sem copiar texto de issue, PR ou comentários, conforme ADR 0008).
   - Dentro do script Python do `run_workflow`, issues independentes rodam com `parallel(issues_lote, ...)` (com `issues_lote` limitado às 4 primeiras issues da ordem de prioridade; eventuais issues além da 4ª são registradas como adiadas pelo teto).
   - Para cada issue, um helper `async def` executa um laço equivalente ao passo 4 (`pipeline` lógico de estágios: `triagem` → `spec` → `implementar` → `revisar`), onde cada estágio roda em um `agent(..., type_name="self", workspace="inherit", model="inherit")` isolado, passando apenas `<etapa>` e `<nº>` no prompt.
   - **Separação `implementar` → `revisar`:** no caminho `antigravity`, o estágio `implementar` executa até o fim da implementação (testes, verificações e criação/atualização do PR) sem chamar `revisar` por dentro, e devolve no `finish` os metadados internos de repasse (caminho `<wt>`, linha de custo do `implementar`, anotações de verificação manual, CAs "depois do merge", desvios, APIs não verificadas e verificação pendente para o CI). O estágio seguinte no `pipeline` da issue invoca `revisar` em outro `agent()` isolado com esses metadados internos, permitindo que o `revisar` chame o subagente `revisor` via `invoke_subagent` (1 nível de profundidade).
4. **Controle do teto de 4 etapas (caso-limite inclusivo):**
   - Cada execução de `agent()` (`triagem`, `spec`, `implementar` ou `revisar`) conta como 1 etapa no teto de 4 etapas por execução do `/fabrica:avancar`.
   - O script mantém um contador compartilhado `orcamento = 4` protegido por `asyncio.Lock`. Antes de iniciar cada estágio, o helper adquire o lock e consome 1 unidade; se `orcamento == 0` (no limite ou abaixo), a issue não inicia novo estágio e encerra seu laço anotando que atingiu o teto de 4 etapas. Estágios já em andamento terminam normalmente.
5. **Lock `em-andamento` e isolamento de falhas no `parallel`:**
   - Antes de iniciar o estágio de uma issue, o helper confere e aplica `em-andamento` (`gh issue edit <nº> --add-label em-andamento`, removendo e reaplicando se estava esquecida).
   - A execução do `agent()` e o desbloqueio ficam dentro de `try ... except Exception ... finally`: o `finally` sempre executa `gh issue edit <nº> --remove-label em-andamento` (inclusive em erro ou cancelamento).
   - Se o `agent()` falhar ou sair sem `finish`, o `except` captura o erro, registra `erro` para aquela issue e retorna normalmente sem propagar exceção ao `parallel`, garantindo que uma issue parada ou com erro não cancele as outras issues em execução paralela.
   - Se `issue-worktree.sh ensure` retornar código 5 (limite de 3 worktrees de issue por clone), a etapa para sem commit, o `finally` remove `em-andamento` e a issue fica registrada como `sem avanço` no relatório, sem interromper as demais.
6. **Papel do `/swarm`:**
   - O `/fabrica:avancar` **nunca** inicia `/swarm` automaticamente (a política da ferramenta `swarm` exige invocação explícita do usuário).
   - `skills/avancar/SKILL.md` e `docs/guias/antigravity.md` documentam o `/swarm` como alternativa manual para lotes amplos de issues (acima do teto de 4 etapas), quando o usuário inicia a sessão com `/swarm`, usando um worker por issue e um worker dedicado de revisão/verificação.
7. **Relatório e modelo:**
   - O relatório final do passo 5 mantém o formato padrão, exibindo `sessão` na coluna `Modelo` para as etapas rodadas no `antigravity` (sem `stage-model.sh`, sem `modelo:*` e sem escalonamento de modelo, conforme ADR 0013).

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/avancar/SKILL.md` separa explicitamente `antigravity` de `opencode` no passo 3, mantendo `opencode` no caminho sequencial "Etapa na sessão" e direcionando `antigravity` para a seção de orquestração com `run_workflow`. | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA2 | A seção de `antigravity` em `skills/avancar/SKILL.md` especifica `run_workflow` com `parallel` entre issues independentes, `agent(..., type_name="self", workspace="inherit", model="inherit")` por etapa e prompt contendo apenas a etapa e o número da issue (ADR 0008), sem copiar texto da issue/PR/comentários. | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA3 | No caminho `antigravity`, `implementar` e `revisar` são especificados como estágios separados e consecutivos do `pipeline` da issue no `run_workflow`, com repasse apenas dos metadados internos (`<wt>`, linha de custo, verificações pendentes/manuais, desvios e APIs não verificadas) do `implementar` para o `revisar`. | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA4 | Quando 0 issues são selecionadas no passo 2, `run_workflow` não é chamado e o comando responde indicando que não há issues de agente e sugerindo `/fabrica:status`. | manual (inspeção da regra em `skills/avancar/SKILL.md` e verificação com `agy` em repositório sem issues `agente`, se disponível, ou inspeção na branch) |
| CA5 | O script/instrução do `run_workflow` garante o teto inclusivo de 4 etapas por execução (cada `agent()` = 1 etapa) via `asyncio.Lock` e orçamento compartilhado; ao chegar a 0, nenhuma nova etapa começa e as restantes vão para o relatório como adiadas. | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA6 | Cada estágio no `run_workflow` aplica `em-andamento` antes de rodar o `agent()`, remove `em-andamento` em bloco `finally` mesmo em caso de erro/cancelamento, e captura exceções por issue para que uma falha ou parada (ex.: saída 5 do `issue-worktree.sh ensure` no limite de 3 worktrees) não cancele as outras issues do `parallel`. | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA7 | `skills/avancar/SKILL.md` e `docs/guias/antigravity.md` explicam que `/swarm` não é disparado automaticamente pelo `/fabrica:avancar` e documentam seu uso opcional apenas quando invocado explicitamente pelo usuário para lotes amplos com worker dedicado de revisão/verificação. | manual (inspeção de `skills/avancar/SKILL.md` e `docs/guias/antigravity.md` na branch) |
| CA8 | `.claude-plugin/plugin.json` tem a `version` incrementada e os testes existentes do repositório (`scripts/test-harness.sh`, `scripts/test-issue-worktree.sh`, `scripts/test-stage-model.sh`, `scripts/test-revisor-agent.sh`) continuam passando sem regressão. | unitário (`bash scripts/test-harness.sh && bash scripts/test-issue-worktree.sh && bash scripts/test-stage-model.sh && bash scripts/test-revisor-agent.sh` na branch) |

## Fora de escopo
- Criação de definições estáticas de agentes de etapa em `agy-agents/*.md` (#217).
- Mapeamento das labels `modelo:haiku|sonnet|opus` para tiers de modelo do `agy` (`flash_lite`, `flash`, `pro`) e escalonamento no `antigravity` (#218).
- Uso das ferramentas `research` e `browser` dentro das etapas (#219).
- Detecção automática de `antigravity` em `scripts/harness.sh` sem `FABRICA_HARNESS=antigravity` (#220).

## Desenho técnico
**Arquivos e módulos:**
- `skills/avancar/SKILL.md`: atualizar o passo 3 ("Como executar") para separar `antigravity` de `opencode`, adicionar a seção **"Orquestração com `run_workflow` (Antigravity)"** (com o contrato do script Python, schema JSON do `agent()`, controle do orçamento de 4 etapas com `asyncio.Lock`, lock `em-andamento` com `try/finally`, isolamento de erros no `parallel` e separação `implementar` → `revisar`) e uma subseção documentando o papel opcional do `/swarm`.
- `docs/guias/antigravity.md`: documentar o comportamento do `/fabrica:avancar` no `agy` (`run_workflow`, estágios separados `implementar` → `revisar`, teto de 4 etapas e uso manual de `/swarm` para lotes amplos).
- `.claude-plugin/plugin.json`: incrementar o campo `version` (ex.: `0.49.1` → `0.50.0`), conforme regra do `AGENTS.md`.

**Dados:** nenhum arquivo de estado novo; o estado continua vindo de GitHub labels, marcadores de comentário e worktrees (conforme `skills/status/estados.md`).

**Interfaces:**
- Entrada de `run_workflow`: script Python inline ou em arquivo temporário recebendo `Args` com a lista `issues` (`[{"number": int, "state": str, "stage": str}]`) e `skill_base_dir` (`str`).
- Schema de retorno de cada `agent()` de etapa:
  `{"type": "object", "properties": {"status": {"type": "string", "enum": ["ok", "sem-avanco", "erro"]}, "mensagem": {"type": "string"}, "handoff": {"type": "object"}}, "required": ["status", "mensagem"]}`.
- Comandos `gh` usados na coleta e lock:
  - `gh issue list --label agente --state open --json number,title,labels,url --limit 100`
  - `gh issue view <nº> --json labels`
  - `gh issue edit <nº> --add-label em-andamento` / `--remove-label em-andamento`

**Decisões:**
- **Orquestração padrão com `run_workflow` e `/swarm` opcional fora do automático (recomendação da triagem)** — usar `run_workflow` (`pipeline` por issue e `parallel` entre issues) como caminho padrão do `/fabrica:avancar` quando a harness for `antigravity`, porque o `run_workflow` permite controle determinístico do teto de 4 etapas e do lock `em-andamento` em Python; deixar `/swarm` apenas para invocação explícita do usuário (`/swarm`), já que a política da ferramenta `swarm` proíbe iniciá-la sem comando explícito do usuário. Alternativa descartada: tentar disparar `/swarm` automaticamente no `/fabrica:avancar`.
- **Encadeamento `implementar` → `revisar` no `pipeline` do `run_workflow` (recomendação da triagem)** — no caminho `antigravity`, modelar `implementar` e `revisar` como estágios consecutivos do `pipeline` do `run_workflow` (em vez de `implementar` invocar `revisar` por dentro), porque subagente não cria subagente por padrão (ADR 0013) e isso desacopla esta issue da #217. Alternativa descartada: aguardar `EnableSubagentTools` (#217) para manter o encadeamento dentro do `implementar`.
- **Limites de escopo da entrega (recomendação da triagem)** — deixar fora desta issue a criação de definições estáticas em `agy-agents/*.md` (#217), o mapeamento de `modelo:*` para tiers do `agy` (#218), o uso de `research`/`browser` nas etapas (#219) e a detecção automática da harness (#220), porque já possuem issues dedicadas abertas. Alternativa descartada: agrupar essas mudanças em uma única entrega, o que aumentaria o risco e acoplaria issues independentes.
- **`workspace="inherit"` nos `agent()` do `run_workflow`** — usar `workspace="inherit"` em vez de `"branch"` ou `"share"`, porque o `scripts/issue-worktree.sh` já isola cada issue em `<clone>/.worktrees/<nº>` (ADR 0014) e clonar o workspace duplicaria worktrees fora do controle do script. Alternativa descartada: `workspace="branch"` ou `"share"`, que quebraria o reaproveitamento de `.worktrees/<nº>`.

**Fontes da documentação:**
- `run-workflow` (skill nativa do Antigravity) — `/home/fernando/.gemini/antigravity-cli/builtin/skills/run-workflow/SKILL.md` (primitivas `agent`, `parallel`, `pipeline`, `workspace="inherit"`, `type_name="self"`, `model="inherit"` e comportamento de cancelamento em `parallel`).
- `gh 2.105.0` — `gh issue list --help`, `gh issue view --help`, `gh issue edit --help` (flags `--label`, `--state`, `--json`, `--limit`, `--add-label`, `--remove-label`).

**ADR:** nenhum (não altera modelo por etapa do ADR 0013 nem estrutura de worktree do ADR 0014; apenas adapta a execução em `antigravity` dentro das regras existentes).

## Testes
- **Unitários existentes:** rodar `bash scripts/test-harness.sh`, `bash scripts/test-issue-worktree.sh`, `bash scripts/test-stage-model.sh` e `bash scripts/test-revisor-agent.sh` para confirmar que nenhuma regra de detecção de harness, worktree, modelo ou revisor quebrou.
- **Verificação manual (CA1–CA7):** revisar o diff em `skills/avancar/SKILL.md`, `docs/guias/antigravity.md` e `.claude-plugin/plugin.json` conferindo cada critério de aceite, a conformidade com o ADR 0008 (sem texto externo no prompt do `agent()`), a regra de `em-andamento` em `try/finally` e o limite de 4 etapas.

## Passos de produção
nenhum

## Riscos e dúvidas
- Concorrência no `git worktree` ao rodar duas ou mais issues novas em `spec` ou `implementar` simultaneamente no `parallel`: se duas chamadas a `issue-worktree.sh ensure` rodarem ao mesmo tempo, o limite de 3 worktrees pode ser atingido (saída 5), o que é tratado como `sem avanço` sem cancelar outras issues; caso haja contenção de lock do git, o estágio falha de forma isolada e remove `em-andamento` no `finally`.
- Sem #220, a detecção automática de `antigravity` ainda depende de `FABRICA_HARNESS=antigravity` no ambiente do `agy`.

## Histórico
- 2026-11-25: criação.
