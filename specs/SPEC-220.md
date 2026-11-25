# SPEC-220: agy: detecção automática da harness, governança e testes

**Issue:** #220 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-25

## Contexto
Atualmente [`scripts/harness.sh`](../scripts/harness.sh) detecta apenas `CLAUDECODE`, `FABRICA_HARNESS` e `OPENCODE_SESSION_ID`, exigindo que o usuário defina `FABRICA_HARNESS=antigravity` manualmente no Antigravity (`agy`). Entretanto, o ambiente de shell do `agy` já exporta nativamente as variáveis `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID`.

Além disso, após as entregas de orquestração (`#216`), subagentes estáticos (`#217`) e mapeamento de tiers (`#218`), a [`ADR 0013`](../docs/adr/0013-modelo-por-etapa-e-por-issue.md) e o guia [`docs/guias/antigravity.md`](../docs/guias/antigravity.md) precisam ser atualizados para consolidar o fluxo completo e a detecção automática.

## Objetivo
Detectar a harness `antigravity` automaticamente em `scripts/harness.sh` pelas variáveis nativas `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID`, emendar a ADR 0013 e atualizar a documentação e os testes do repositório.

## Comportamento esperado
1. **Detecção automática em `scripts/harness.sh`:**
   - Ordem de precedência de `harness.sh detect`:
     1. `CLAUDECODE` não vazio → `claude-code` (garante que um `claude -p` aberto de dentro do OpenCode ou do Antigravity continue sendo Claude Code);
     2. `FABRICA_HARNESS` não vazio → `opencode` | `antigravity` | `claude-code` (saída `2` se inválido);
     3. `OPENCODE_SESSION_ID` não vazio → `opencode`;
     4. `ANTIGRAVITY_AGENT` ou `ANTIGRAVITY_CONVERSATION_ID` não vazios → `antigravity`;
     5. sem nenhum sinal → `binario`.
   - Variáveis vazias contam como ausentes.
2. **Higiene e novos casos em `scripts/test-harness.sh` e `scripts/test-stage-model.sh`:**
   - Limpar `-u ANTIGRAVITY_AGENT -u ANTIGRAVITY_CONVERSATION_ID` nos helpers que isolam o ambiente para testar o caminho `binario` (`run_detect` e `run_stage` em `scripts/test-harness.sh`, e as chamadas equivalentes em `scripts/test-stage-model.sh`), garantindo que os testes passem mesmo quando executados dentro de uma sessão `agy`.
   - Adicionar casos em `scripts/test-harness.sh` cobrindo:
     - `ANTIGRAVITY_AGENT=1` → `antigravity`;
     - `ANTIGRAVITY_CONVERSATION_ID=conv_123` → `antigravity`;
     - `CLAUDECODE=1` vencendo `ANTIGRAVITY_AGENT=1` e `ANTIGRAVITY_CONVERSATION_ID=conv_123` (`claude-code`);
     - `FABRICA_HARNESS=claude-code` vencendo `ANTIGRAVITY_AGENT=1` (`claude-code`);
     - `ANTIGRAVITY_AGENT=` e `ANTIGRAVITY_CONVERSATION_ID=` vazias → `binario`;
     - `stage-model.sh run triagem 12` com `ANTIGRAVITY_AGENT=1` saindo com código `3` sem chamar `claude`.
3. **Emenda da ADR 0013 e atualização de documentação:**
   - Emendar `docs/adr/0013-modelo-por-etapa-e-por-issue.md` registrando a detecção automática do `antigravity` via `ANTIGRAVITY_AGENT`/`ANTIGRAVITY_CONVERSATION_ID`, a orquestração com `run_workflow` (`#216`), os subagentes estáticos em `agy-agents/` (`#217`) e o mapeamento de tiers via `stage-model.sh agy-tier` (`#218`).
   - Atualizar `docs/guias/antigravity.md` removendo a ressalva de que `FABRICA_HARNESS=antigravity` precisa ser definida manualmente (mantendo-a apenas como override opcional).
   - Atualizar `docs/comandos.md` e `docs/fluxo.md` onde ainda condicionam o fluxo do Antigravity a `FABRICA_HARNESS=antigravity`.
4. **Versão do plugin e regressão:**
   - Incrementar `version` em `.claude-plugin/plugin.json`.
   - Manter `scripts/test-revisor-agent.sh` passando sem regressão.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `scripts/harness.sh detect` retorna `antigravity` quando `ANTIGRAVITY_AGENT` ou `ANTIGRAVITY_CONVERSATION_ID` estão definidos (não vazios), mantendo `CLAUDECODE` e `FABRICA_HARNESS` com maior precedência e variáveis vazias como ausentes. | unitário (`bash scripts/test-harness.sh`) |
| CA2 | `scripts/stage-model.sh run` sai com código `3` e não chama `claude` quando `ANTIGRAVITY_AGENT` ou `ANTIGRAVITY_CONVERSATION_ID` está ativo, enquanto `CLAUDECODE=1` vence e executa `claude`. | unitário (`bash scripts/test-harness.sh`) |
| CA3 | `scripts/test-harness.sh` e `scripts/test-stage-model.sh` limpam `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID` nos casos de caminho `binario`, passando integralmente mesmo dentro de uma sessão `agy`. | unitário (`bash scripts/test-harness.sh && bash scripts/test-stage-model.sh`) |
| CA4 | `docs/adr/0013-modelo-por-etapa-e-por-issue.md` inclui emenda consolidando a detecção automática do `antigravity`, `run_workflow` (#216), `agy-agents/` (#217) e `stage-model.sh agy-tier` (#218). | manual (inspeção de `docs/adr/0013-modelo-por-etapa-e-por-issue.md` na branch) |
| CA5 | `docs/guias/antigravity.md`, `docs/comandos.md` e `docs/fluxo.md` refletem a detecção automática do Antigravity sem exigir `FABRICA_HARNESS=antigravity` manual. | manual (inspeção dos arquivos em `docs/` na branch) |
| CA6 | `.claude-plugin/plugin.json` tem a `version` incrementada e `scripts/test-revisor-agent.sh` passa sem regressão. | unitário (`bash scripts/test-revisor-agent.sh`) |

## Fora de escopo
- Alteração de lógica de orquestração (`#216`), novos subagentes (`#217`), mapeamento de tiers (`#218`) ou subagentes built-in (`#219`).

## Desenho técnico
**Arquivos e módulos:**
- `scripts/harness.sh`: adicionar verificação de `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID` após `OPENCODE_SESSION_ID` e atualizar o comentário de precedência.
- `scripts/test-harness.sh`: limpar `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID` em `run_detect` e `run_stage`, e adicionar casos CA1–CA3 para Antigravity.
- `scripts/test-stage-model.sh`: limpar `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID` nas chamadas `env -u ...` dos casos `binario`/`claude`.
- `docs/adr/0013-modelo-por-etapa-e-por-issue.md`: adicionar emenda de `2026-11-25, issue #220`.
- `docs/guias/antigravity.md`, `docs/comandos.md`, `docs/fluxo.md`: atualizar menções a `FABRICA_HARNESS=antigravity`.
- `.claude-plugin/plugin.json`: incrementar `version`.

**Dados:** nenhum dado novo persistido.

**Interfaces:**
- `scripts/harness.sh detect` → stdout: `claude-code` | `opencode` | `antigravity` | `binario`; códigos de saída: `0`, `1`, `2`.

**Decisões:**
- **Detecção automática via variáveis nativas `ANTIGRAVITY_*` (recomendação da triagem)** — detectar `antigravity` quando `ANTIGRAVITY_AGENT` ou `ANTIGRAVITY_CONVERSATION_ID` estiverem definidas, mantendo `CLAUDECODE` em 1º lugar e `FABRICA_HARNESS` em 2º (mesma precedência de `OPENCODE_SESSION_ID` na ADR 0013). Alternativa descartada: injetar `FABRICA_HARNESS=antigravity` apenas via hook `SessionStart`.
- **Emenda da ADR 0013 e remoção da ressalva manual em `docs/guias/antigravity.md` (recomendação da triagem)** — emendar a ADR 0013 registrando detecção automática, `run_workflow` (#216), subagentes estáticos (#217) e `stage-model.sh agy-tier` (#218), e remover a dependência de `FABRICA_HARNESS=antigravity` manual nos guias. Alternativa descartada: manter a ADR 0013 sem emenda.
- **Cobertura em `scripts/test-harness.sh` e higiene de ambiente nos testes (recomendação da triagem)** — adicionar casos para `ANTIGRAVITY_AGENT`/`ANTIGRAVITY_CONVERSATION_ID` e precedência em `scripts/test-harness.sh`, limpar essas variáveis nos testes de caminho `binario` e manter `scripts/test-revisor-agent.sh` verde. Alternativa descartada: testar apenas manualmente.

**Fontes da documentação:**
- Ambiente de execução do Antigravity (`agy 1.5.17`) — variáveis exportadas no shell (`ANTIGRAVITY_AGENT`, `ANTIGRAVITY_CONVERSATION_ID`).
- `scripts/harness.sh` e `scripts/test-harness.sh` — contrato e precedência existentes.

**ADR:** emenda na `docs/adr/0013-modelo-por-etapa-e-por-issue.md`.

## Testes
- **Unitários:** rodar `bash scripts/test-harness.sh && bash scripts/test-stage-model.sh && bash scripts/test-revisor-agent.sh` dentro da sessão do `agy` (com `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID` presentes no ambiente pai) para comprovar que tanto a detecção automática quanto o isolamento dos testes `binario` funcionam.
- **Verificação manual (CA4–CA5):** inspecionar `docs/adr/0013-modelo-por-etapa-e-por-issue.md`, `docs/guias/antigravity.md`, `docs/comandos.md` e `docs/fluxo.md`.

## Passos de produção
nenhum

## Riscos e dúvidas
- Caso uma versão futura do `agy` renomeie `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID`, o usuário ainda conta com `FABRICA_HARNESS=antigravity` como fallback explícito.

## Histórico
- 2026-11-25: criação.
