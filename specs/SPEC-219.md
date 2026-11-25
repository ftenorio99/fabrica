# SPEC-219: agy: uso dos subagentes built-in (research e browser) e Workspace

**Issue:** #219 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-25

## Contexto
O Antigravity (`agy`) disponibiliza os subagentes built-in `research` (somente leitura, sem acesso à rede) e `browser` (interação com navegador), além do parâmetro `Workspace` (`"inherit"`, `"branch"`, `"share"`) no `invoke_subagent` e `run_workflow`.

Atualmente as etapas da fábrica não aproveitam `research` nem `browser` quando rodam sob `antigravity`, e não há regra explícita sobre quando manter `Workspace="inherit"` (junto com o `scripts/issue-worktree.sh` do ADR 0014) versus `"branch"`/`"share"`. Esta spec define a integração condicional desses recursos, preservando os caminhos do Claude Code e OpenCode e a paridade de corpo entre `agents/revisor.md` e `agy-agents/revisor.md`.

## Objetivo
Integrar o uso condicional dos subagentes built-in `research` (em `triagem` e `spec`) e `browser` (em `implementar`, `revisar` e `revisor`) na harness `antigravity`, definindo a política de `Workspace="inherit"` com `issue-worktree.sh` (ADR 0014).

## Comportamento esperado
1. **Uso de `research` na exploração inicial (`skills/triagem/SKILL.md` e `skills/spec/SKILL.md`):**
   - No passo de leitura (`1. Ler` na triagem, `3. Ler` na spec), adicionar orientação condicional para `antigravity` (`harness.sh detect` == `antigravity`): quando a exploração exigir levantar vários arquivos, ADRs, specs ou call sites no código, delegar a busca inicial ao subagente built-in `research` via `invoke_subagent(TypeName="research", ...)`, passando apenas o objetivo da busca e caminhos/números (nunca texto externo da issue ou comentários, conforme ADR 0008).
   - Para leituras curtas e pontuais (1–2 arquivos conhecidos), a etapa continua lendo diretamente sem abrir subagente.
   - Outras harnesses (`claude-code`, `opencode`, `binario`) não são afetadas.
2. **Uso de `browser` em verificações visuais e E2E (`skills/implementar/SKILL.md`, `skills/revisar/SKILL.md`, `agents/revisor.md` e `agy-agents/revisor.md`):**
   - Nos passos de verificação (`4. Verificar` do `implementar`, `3. Rodada de revisão` do `revisar`, e item 3/4 do `revisor`), adicionar orientação condicional: quando a harness for `antigravity` (`harness.sh detect` == `antigravity`), o projeto tiver interface web local e o subagente built-in `browser` estiver disponível, é permitido delegar verificações visuais ou fluxos E2E complementares ao `browser` via `invoke_subagent(TypeName="browser", ...)` (ou `/browser`).
   - **Opcionalidade / fallback:** em ambiente headless/VM sem navegador ou se `browser` estiver ausente ou falhar com assinatura de ambiente, a etapa não bloqueia e segue o fluxo normal de `make e2e` / verificação pendente para o CI (ADR 0011).
   - **Paridade do `revisor`:** o mesmo texto condicional é inserido no corpo de `agents/revisor.md` e `agy-agents/revisor.md`, mantendo os dois corpos idênticos (exigido por `scripts/test-revisor-agent.sh`).
3. **Política de `Workspace` (`docs/guias/antigravity.md`):**
   - Documentar que as etapas da fábrica mantêm `Workspace="inherit"` porque o `scripts/issue-worktree.sh` já isola cada issue em `<clone>/.worktrees/<nº>` (ADR 0014), permitindo reaproveitar a mesma worktree entre `spec`, `implementar` e `revisar`.
   - Reservar `Workspace="share"` ou `"branch"` apenas para subagentes auxiliares temporários fora do fluxo padrão de worktrees ou para sessões explícitas de `/swarm` que editem arquivos em paralelo.
4. **Documentação e versão do plugin:**
   - Atualizar `docs/guias/antigravity.md` com o uso condicional de `research`, `browser` e a política de `Workspace`.
   - Incrementar `version` em `.claude-plugin/plugin.json`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/triagem/SKILL.md` e `skills/spec/SKILL.md` orientam delegar exploração ampla ao subagente `research` via `invoke_subagent` quando `harness.sh detect` retorna `antigravity`, sem texto externo no prompt (ADR 0008) e mantendo leitura direta para buscas pontuais. | manual (inspeção de `skills/triagem/SKILL.md` e `skills/spec/SKILL.md` na branch) |
| CA2 | `skills/implementar/SKILL.md` e `skills/revisar/SKILL.md` permitem acionar o subagente `browser` (ou `/browser`) para verificações visuais e E2E quando `harness.sh detect` retorna `antigravity` e o subagente está disponível, sem bloquear em ambiente ausente/headless. | manual (inspeção de `skills/implementar/SKILL.md` e `skills/revisar/SKILL.md` na branch) |
| CA3 | `agents/revisor.md` e `agy-agents/revisor.md` incluem a orientação condicional de uso do `browser` mantendo exatamente o mesmo corpo entre os dois arquivos. | unitário (`bash scripts/test-revisor-agent.sh`) |
| CA4 | `docs/guias/antigravity.md` documenta o uso de `research`, `browser` e a política de `Workspace="inherit"` com `scripts/issue-worktree.sh` (reservando `"share"`/`"branch"` para subagentes auxiliares fora do fluxo padrão ou `/swarm`). | manual (inspeção de `docs/guias/antigravity.md` na branch) |
| CA5 | `.claude-plugin/plugin.json` tem a `version` incrementada e os testes `scripts/test-revisor-agent.sh`, `scripts/test-issue-worktree.sh` e `scripts/test-harness.sh` passam sem regressão. | unitário (`bash scripts/test-revisor-agent.sh && bash scripts/test-issue-worktree.sh && bash scripts/test-harness.sh`) |

## Fora de escopo
- Detecção automática de `antigravity` em `scripts/harness.sh` sem `FABRICA_HARNESS=antigravity` (#220).

## Desenho técnico
**Arquivos e módulos:**
- `skills/triagem/SKILL.md`: adicionar nota no passo `1. Ler` sobre delegação de exploração ampla ao subagente `research` na harness `antigravity`.
- `skills/spec/SKILL.md`: adicionar nota no passo `3. Ler` sobre delegação de exploração ampla ao subagente `research` na harness `antigravity`.
- `skills/implementar/SKILL.md`: adicionar nota no passo `4. Verificar` sobre uso opcional de `browser` na harness `antigravity`.
- `skills/revisar/SKILL.md`: adicionar nota no passo `3. Rodada de revisão` sobre uso opcional de `browser` na harness `antigravity`.
- `agents/revisor.md` e `agy-agents/revisor.md`: adicionar a mesma instrução condicional sobre `browser` no corpo dos dois arquivos.
- `docs/guias/antigravity.md`: documentar `research`, `browser` e a política de `Workspace` (`"inherit"` vs `"branch"`/`"share"`).
- `.claude-plugin/plugin.json`: incrementar `version`.

**Dados:** nenhum dado novo persistido.

**Interfaces:**
- `invoke_subagent(TypeName="research", ...)` (somente leitura, `Workspace="inherit"`).
- `invoke_subagent(TypeName="browser", ...)` (opcional, condicionado à disponibilidade).

**Decisões:**
- **Manter `Workspace: "inherit"` com `issue-worktree.sh` (ADR 0014) (recomendação da triagem)** — manter `workspace="inherit"` nas etapas da fábrica para preservar a worktree única da issue em `<clone>/.worktrees/<nº>` (ADR 0014 e `SPEC-216`), reservando `"share"`/`"branch"` apenas para subagentes auxiliares fora do fluxo padrão ou `/swarm`. Alternativa descartada: substituir `issue-worktree.sh` por `Workspace: "branch"`/`"share"` no `agy`.
- **Ativação condicional à harness `antigravity` e paridade do `revisor` (recomendação da triagem)** — acionar `research` (`triagem` e `spec`) e `browser` (`implementar` e `revisar`) apenas quando `harness.sh detect` for `antigravity` (e `browser` disponível), mantendo o corpo de `agents/revisor.md` e `agy-agents/revisor.md` idêntico conforme `scripts/test-revisor-agent.sh`. Alternativa descartada: editar só `agy-agents/revisor.md` ou exigir `browser` incondicionalmente.
- **Limites de escopo da entrega (recomendação da triagem)** — deixar fora desta issue a detecção automática da harness (#220), porque já possui issue dedicada aberta. Alternativa descartada: incluir a detecção automática na #219.

**Fontes da documentação:**
- `invoke_subagent` (definição nativa na sessão do Antigravity) — subagentes disponíveis (`research`, `browser`, `revisor`) e modos de `Workspace` (`inherit`, `branch`, `share`).
- `scripts/test-revisor-agent.sh` — regra de paridade de corpo entre `agents/revisor.md` e `agy-agents/revisor.md`.

**ADR:** nenhum.

## Testes
- **Unitários:** rodar `bash scripts/test-revisor-agent.sh && bash scripts/test-issue-worktree.sh && bash scripts/test-harness.sh` para garantir paridade do `revisor` e ausência de regressão.
- **Verificação manual (CA1, CA2, CA4):** inspecionar os trechos adicionados em `skills/triagem/SKILL.md`, `skills/spec/SKILL.md`, `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md` e `docs/guias/antigravity.md`.

## Passos de produção
nenhum

## Riscos e dúvidas
- A disponibilidade do subagente `browser` depende do ambiente (desktop vs VM headless); por isso a spec torna seu uso estritamente opcional e com fallback para `make e2e` / CI.

## Histórico
- 2026-11-25: criação.
