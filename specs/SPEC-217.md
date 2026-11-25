# SPEC-217: agy: subagentes especializados por etapa e EnableSubagentTools

**Issue:** #217 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-25

## Contexto
Hoje apenas [`agy-agents/revisor.md`](../agy-agents/revisor.md) está declarado em [`agents.json`](../agents.json). A #216 já separou `implementar` e `revisar` como estágios consecutivos no `pipeline` do `run_workflow` em [`skills/avancar/SKILL.md`](../skills/avancar/SKILL.md), evitando a restrição de subagente criando subagente (ADR 0013) no fluxo automático.

Falta definir os subagentes estáticos especializados por etapa (`triador`, `especificador` e `implementador`) em `agy-agents/*.md` e registrá-los em `agents.json`, garantindo validação dupla no `agy` e no `claude`, além de documentar o papel de `EnableSubagentTools`.

## Objetivo
Definir os subagentes estáticos por etapa (`triador`, `especificador`, `implementador`) em `agy-agents/*.md` registrados em `agents.json`, integrá-los ao `run_workflow` do `/fabrica:avancar` e validar a compatibilidade com `agy plugin validate --strict` e `claude plugin validate`.

## Comportamento esperado
1. **Subagentes estáticos em `agy-agents/`:** criar três arquivos de definição estática no mesmo padrão de frontmatter aceito pelo `agy` 1.5.17:
   - `agy-agents/triador.md` (`name: triador`, `subagent: true`, `mainAgent: false`, `model: inherit`, `commandExecutionPolicy: auto`, `skills: [triagem]`, `tools: [read_file, run_command, write_file]`): papel de triagem da fábrica, seguindo `skills/triagem/SKILL.md` com apenas o número da issue (ADR 0008) e sem perguntar no chat.
   - `agy-agents/especificador.md` (`name: especificador`, `subagent: true`, `mainAgent: false`, `model: inherit`, `commandExecutionPolicy: auto`, `skills: [spec]`, `tools: [read_file, write_file, edit_file, run_command]`): papel de especificação da fábrica, seguindo `skills/spec/SKILL.md` na worktree da issue (ADR 0014) e sem perguntar no chat.
   - `agy-agents/implementador.md` (`name: implementador`, `subagent: true`, `mainAgent: false`, `model: inherit`, `commandExecutionPolicy: auto`, `skills: [implementar]`, `tools: [read_file, write_file, edit_file, run_command, manage_task]`): papel de implementação da fábrica, seguindo `skills/implementar/SKILL.md` na worktree da issue e encerrando ao fim da implementação (devolvendo os metadados internos de repasse, sem chamar `revisar` por dentro no `run_workflow`).
2. **Registro em `agents.json`:** atualizar `agents.json` na raiz para declarar as 4 entradas em `entries`: `agy-agents/revisor.md`, `agy-agents/triador.md`, `agy-agents/especificador.md` e `agy-agents/implementador.md`.
3. **Integração no `/fabrica:avancar` e `EnableSubagentTools`:**
   - Na seção **"Orquestração com `run_workflow` (Antigravity)"** de `skills/avancar/SKILL.md`, mapear cada etapa para o `type_name` correspondente (`triagem` → `"triador"`, `spec` → `"especificador"`, `implementar` → `"implementador"`, `revisar` → `"revisor"`, mantendo `"self"` como fallback caso o agente estático não esteja disponível).
   - Manter `implementar` e `revisar` como estágios separados no `pipeline` do `run_workflow`, sem depender de `EnableSubagentTools: true`.
   - Documentar em `docs/guias/antigravity.md` os 4 subagentes estáticos em `agy-agents/` e registrar que `EnableSubagentTools: true` (em `define_subagent`) fica restrito a eventual uso dinâmico fora do `run_workflow`.
4. **Validação dupla (`agy` e `claude`) e versão do plugin:**
   - Atualizar `scripts/test-revisor-agent.sh` para validar os 4 arquivos em `agy-agents/*.md`, as 4 entradas em `agents.json`, `agy plugin validate --strict` reportando `agents 4` com saída `0` e `claude plugin validate` continuando com saída `0` e listando apenas `fabrica:revisor` (sem avisos sobre `agy-agents/` ou `agents.json`).
   - Incrementar `version` em `.claude-plugin/plugin.json`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `agy-agents/triador.md`, `agy-agents/especificador.md` e `agy-agents/implementador.md` existem com frontmatter válido para o `agy` (`name`, `description`, `tools` em lista com nomes do `agy`, `subagent: true`, `mainAgent: false`, `skills`, `model: inherit`, `commandExecutionPolicy: auto`) e instruções fiéis ao papel de cada etapa. | unitário (`bash scripts/test-revisor-agent.sh`) |
| CA2 | `agents.json` na raiz declara exatamente as 4 entradas (`agy-agents/revisor.md`, `agy-agents/triador.md`, `agy-agents/especificador.md`, `agy-agents/implementador.md`). | unitário (`bash scripts/test-revisor-agent.sh`) |
| CA3 | `agy plugin validate <dir> --strict` (com `agents.json` e `agy-agents/*.md`) sai com código `0`, reporta `agents 4` e não emite erros em `agy-agents/`. | unitário (`bash scripts/test-revisor-agent.sh`) |
| CA4 | `claude plugin validate <root>` sai com código `0`, lista apenas `fabrica:revisor` e não emite avisos sobre `agy-agents/` nem `agents.json`. | unitário (`bash scripts/test-revisor-agent.sh`) |
| CA5 | `skills/avancar/SKILL.md` mapeia as etapas do `run_workflow` para `type_name` especializado (`triador`, `especificador`, `implementador`, `revisor`, com fallback `"self"`), mantendo `implementar` → `revisar` em estágios separados do `pipeline`. | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA6 | `docs/guias/antigravity.md` documenta os 4 subagentes em `agy-agents/` e registra que `implementar` → `revisar` usa estágios separados no `run_workflow`, reservando `EnableSubagentTools` apenas para `define_subagent` dinâmico fora do `run_workflow`. | manual (inspeção de `docs/guias/antigravity.md` na branch) |
| CA7 | `.claude-plugin/plugin.json` tem a `version` incrementada e os testes `scripts/test-harness.sh`, `scripts/test-issue-worktree.sh`, `scripts/test-stage-model.sh` e `scripts/test-revisor-agent.sh` passam sem regressão. | unitário (`bash scripts/test-harness.sh && bash scripts/test-issue-worktree.sh && bash scripts/test-stage-model.sh && bash scripts/test-revisor-agent.sh`) |

## Fora de escopo
- Mapeamento das labels `modelo:haiku|sonnet|opus` para tiers do `agy` (`flash_lite`, `flash`, `pro`) e escalonamento no `antigravity` (#218).
- Uso das ferramentas `research` e `browser` dentro das etapas (#219).
- Detecção automática de `antigravity` em `scripts/harness.sh` sem `FABRICA_HARNESS=antigravity` (#220).

## Desenho técnico
**Arquivos e módulos:**
- `agy-agents/triador.md`, `agy-agents/especificador.md`, `agy-agents/implementador.md`: novos arquivos de definição estática de subagentes para o `agy`.
- `agents.json`: lista `entries` atualizada com os 4 caminhos em `agy-agents/`.
- `skills/avancar/SKILL.md`: atualização da seção **"Orquestração com `run_workflow` (Antigravity)"** para usar `type_name` por etapa (com fallback `"self"`).
- `scripts/test-revisor-agent.sh`: ampliação das asserções de CA1/CA2 para cobrir os 4 agentes do `agy` e manter a checagem do `claude plugin validate`.
- `docs/guias/antigravity.md`: atualização da seção de subagentes e registro de `EnableSubagentTools`.
- `.claude-plugin/plugin.json`: incremento de `version`.

**Dados:** nenhum dado novo persistido.

**Interfaces:**
- Frontmatter dos arquivos `agy-agents/*.md`:
  `name`, `description`, `tools` (lista YAML com nomes do `agy`), `subagent: true`, `mainAgent: false`, `model: inherit`, `commandExecutionPolicy: auto`, `skills: [<etapa>]`.
- Mapeamento `etapa → type_name` no `run_workflow` de `skills/avancar/SKILL.md`:
  `{"triagem": "triador", "spec": "especificador", "implementar": "implementador", "revisar": "revisor"}` (com fallback `"self"`).

**Decisões:**
- **Manter `implementar` → `revisar` separados no `run_workflow` (recomendação da triagem)** — como a #216 já separou `implementar` e `revisar` em estágios consecutivos do `pipeline` no `run_workflow`, não depender de `EnableSubagentTools: true` para subagente chamar subagente no fluxo automático, restringindo `EnableSubagentTools` a invocações dinâmicas via `define_subagent` se necessário. Alternativa descartada: alterar `implementar` para rodar via `define_subagent` com `EnableSubagentTools: true`.
- **Validação dupla `agy` e `claude` (recomendação da triagem)** — exigir que os novos `agy-agents/*.md` e `agents.json` passem tanto no `agy plugin validate --strict` quanto no `claude plugin validate`, estendendo `scripts/test-revisor-agent.sh`. Alternativa descartada: validar apenas manualmente sem atualizar os testes de plugin.
- **Limites de escopo da entrega (recomendação da triagem)** — deixar fora desta issue o mapeamento de `modelo:*` para tiers do `agy` (#218), o uso de `research`/`browser` (#219) e a detecção automática da harness (#220), porque já possuem issues dedicadas abertas. Alternativa descartada: agrupar essas frentes na #217.

**Fontes da documentação:**
- `agy 1.5.17` — validação local com `agy plugin validate <dir> --strict` confirmando aceitação de `model: inherit`, `commandExecutionPolicy: auto`, `skills: [...]`, `tools: [...]`, `subagent: true`, `mainAgent: false`.
- `claude 2.1.332 (Claude Code)` — `scripts/test-revisor-agent.sh` (`claude plugin validate`).

**ADR:** nenhum.

## Testes
- **Unitários (`scripts/test-revisor-agent.sh`):** verificar presença e frontmatter de `triador.md`, `especificador.md`, `implementador.md` e `revisor.md`, `entries` com 4 caminhos em `agents.json`, `agy plugin validate --strict` retornando `0` e `agents 4`, e `claude plugin validate` retornando `0` listando apenas `fabrica:revisor`.
- **Regressão:** rodar `bash scripts/test-harness.sh && bash scripts/test-issue-worktree.sh && bash scripts/test-stage-model.sh && bash scripts/test-revisor-agent.sh`.
- **Verificação manual (CA5–CA6):** inspecionar `skills/avancar/SKILL.md` e `docs/guias/antigravity.md` na branch.

## Passos de produção
nenhum

## Riscos e dúvidas
- Se futuras versões do `agy` alterarem o schema de frontmatter de subagentes, `agy plugin validate --strict` em `scripts/test-revisor-agent.sh` detectará imediatamente.

## Histórico
- 2026-11-25: criação.
