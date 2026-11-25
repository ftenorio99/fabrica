# SPEC-218: agy: mapeamento de modelos para os tiers do Antigravity

**Issue:** #218 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-25

## Contexto
Atualmente [`skills/avancar/modelos.md`](../skills/avancar/modelos.md) mapeia os apelidos da fábrica (`haiku`, `sonnet`, `opus`) apenas para os IDs do Claude Code, [`scripts/stage-model.sh`](../scripts/stage-model.sh) não expõe tradução para os tiers do Antigravity (`flash_lite`, `flash`, `pro`, `inherit`), [`skills/revisar/SKILL.md`](../skills/revisar/SKILL.md) omite o parâmetro `model` quando `harness.sh detect` retorna `antigravity`, e [`skills/avancar/SKILL.md`](../skills/avancar/SKILL.md) fixa `model="inherit"` no `run_workflow`.

Esta spec define a tabela única de mapeamento em `skills/avancar/modelos.md`, o subcomando `agy-tier` em `scripts/stage-model.sh` e o uso do tier traduzido no `revisar` e no `run_workflow` do `/fabrica:avancar`, mantendo o `opencode` no caminho de sessão sem seleção de modelo.

## Objetivo
Traduzir os apelidos e labels `modelo:*` da fábrica para os tiers do Antigravity (`flash_lite`, `flash`, `pro`) a partir de `skills/avancar/modelos.md` e `scripts/stage-model.sh`, aplicando o tier nas chamadas de `invoke_subagent` (`revisar`) e `run_workflow` (`/fabrica:avancar`) quando a harness for `antigravity`.

## Comportamento esperado
1. **Tabela de tiers em `skills/avancar/modelos.md`:**
   - Acrescentar a coluna `Tier agy` na seção `## Modelos`:
     - `haiku` → `flash_lite`
     - `sonnet` → `flash`
     - `opus` → `pro`
   - Manter intactas as colunas `Apelido` e `ID` (`claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`) e as tabelas `## Etapas` e `## Escalonamento`.
2. **Subcomando `agy-tier` em `scripts/stage-model.sh`:**
   - Novo subcomando: `stage-model.sh agy-tier <etapa> [label...]`.
   - Reaproveita a mesma resolução de etapa e labels `modelo:*` de `cmd_model` (`triagem` → `sonnet` → `flash`, `spec` → `opus` → `pro`, `implementar` → label ou `sonnet`, `revisar` → `sonnet` ou `opus` se `modelo:opus`) e imprime apenas o tier correspondente (`flash_lite`, `flash` ou `pro`).
   - **Casos de erro:** sem `<etapa>` ou etapa/label desconhecida sai com código `1`; com duas ou mais labels `modelo:*` sai com código `2`.
   - Os subcomandos existentes (`model`, `next`, `run`) mantêm exatamente o comportamento atual (incluindo `run` saindo com código `3` para `opencode` e `antigravity`).
3. **Uso no `/fabrica:revisar` (`skills/revisar/SKILL.md`):**
   - No passo 3 ("Modelo do revisor"), separar `opencode` de `antigravity`:
     - `opencode`: continua sem passar `model` ao subagente (herda o modelo da sessão).
     - `antigravity`: roda `bash <diretório base desta skill>/../../scripts/stage-model.sh agy-tier revisar <labels modelo:* da issue>` e passa a saída (`flash` ou `pro`) no parâmetro `Model` do `invoke_subagent` (ou no fallback `define_subagent`). Se o script sair com código diferente de `0`, não passa `Model` (cai em `inherit`).
     - `claude-code` ou `binario`: mantém o comportamento atual (`stage-model.sh model revisar ...`).
4. **Uso no `/fabrica:avancar` (`skills/avancar/SKILL.md`):**
   - Na seção **"Orquestração com `run_workflow` (Antigravity)"**, para cada estágio executado no `pipeline`, resolver o tier via `bash <skill_base_dir>/../../scripts/stage-model.sh agy-tier <etapa> <labels modelo:* da issue>` e passar o valor no parâmetro `model` de `agent(..., type_name=..., workspace="inherit", model=tier)` (com fallback `"inherit"` se o script falhar).
   - Na coluna `Modelo` do relatório do passo 5, exibir o tier usado em cada etapa (`flash_lite`, `flash`, `pro`, ou `sessão` se caiu em `inherit`).
   - O caminho `opencode` permanece em "Etapa na sessão", sem `stage-model.sh` e sem seleção de modelo.
5. **Documentação e versão do plugin:**
   - Atualizar `docs/guias/antigravity.md` e `docs/comandos.md` documentando o mapeamento para tiers do `agy` no `revisar` e no `run_workflow`.
   - Incrementar `version` em `.claude-plugin/plugin.json`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/avancar/modelos.md` inclui a coluna `Tier agy` na tabela `## Modelos` mapeando `haiku` → `flash_lite`, `sonnet` → `flash` e `opus` → `pro`, sem quebrar a leitura de `stage-model.sh model`. | unitário (`bash scripts/test-stage-model.sh`) |
| CA2 | `scripts/stage-model.sh agy-tier <etapa> [label...]` retorna `flash` para `triagem`, `pro` para `spec`, `flash_lite`/`flash`/`pro` para `implementar` conforme a label `modelo:*` (`flash` sem label), e `flash` para `revisar` (subindo para `pro` apenas com `modelo:opus`, sem rebaixar com `modelo:haiku`). | unitário (`bash scripts/test-stage-model.sh`) |
| CA3 | `scripts/stage-model.sh agy-tier` sai com código `2` quando recebe duas ou mais labels `modelo:*`, e com código `1` para etapa desconhecida, label `modelo:*` fora da tabela ou ausência de argumentos. | unitário (`bash scripts/test-stage-model.sh`) |
| CA4 | `skills/revisar/SKILL.md` passa o tier retornado por `stage-model.sh agy-tier revisar ...` no parâmetro `Model` do `invoke_subagent` quando `harness.sh detect` retorna `antigravity` (mantendo fallback `inherit` se o script falhar), e mantém `opencode` sem `model`. | manual (inspeção de `skills/revisar/SKILL.md` na branch) |
| CA5 | `skills/avancar/SKILL.md` usa `stage-model.sh agy-tier` para definir `model=tier` (fallback `"inherit"`) nos `agent(...)` do `run_workflow` em `antigravity`, mantendo `opencode` em "Etapa na sessão". | manual (inspeção de `skills/avancar/SKILL.md` na branch) |
| CA6 | `docs/guias/antigravity.md` e `docs/comandos.md` refletem o mapeamento de `modelo:*` para tiers do `agy`, `.claude-plugin/plugin.json` tem `version` incrementada e as suítes `test-stage-model.sh` e `test-harness.sh` passam sem regressão. | unitário (`bash scripts/test-stage-model.sh && bash scripts/test-harness.sh`) e manual (inspeção dos docs) |

## Fora de escopo
- Uso das ferramentas `research` e `browser` dentro das etapas (#219).
- Detecção automática de `antigravity` em `scripts/harness.sh` sem `FABRICA_HARNESS=antigravity` (#220).

## Desenho técnico
**Arquivos e módulos:**
- `skills/avancar/modelos.md`: adicionar coluna `Tier agy` na tabela `## Modelos`.
- `scripts/stage-model.sh`: adicionar `agy_tier()` (lendo a 4ª coluna da seção `## Modelos`) e o subcomando `agy-tier`, reutilizando a lógica de seleção de `cmd_model` (extraindo helper compartilhado para não duplicar o `case $rule`).
- `scripts/test-stage-model.sh`: adicionar os testes do subcomando `agy-tier` (CA1–CA3).
- `skills/revisar/SKILL.md`: atualizar a seção **Modelo do revisor** (linha 65) para chamar `stage-model.sh agy-tier revisar ...` quando a harness for `antigravity`.
- `skills/avancar/SKILL.md`: atualizar a seção **Orquestração com `run_workflow` (Antigravity)** para resolver e passar `model=tier` por etapa.
- `docs/guias/antigravity.md` e `docs/comandos.md`: documentar o uso dos tiers no `antigravity`.
- `.claude-plugin/plugin.json`: incrementar `version`.

**Dados:** nenhum arquivo de estado novo.

**Interfaces:**
- CLI `scripts/stage-model.sh agy-tier <etapa> [label...]` → stdout: `flash_lite` | `flash` | `pro`; códigos de saída: `0` sucesso, `1` erro de uso/etapa/label, `2` duas ou mais labels `modelo:*`.
- Parâmetro `Model` de `invoke_subagent` e `model` de `run_workflow` (`agent(...)`): valores `"flash_lite"`, `"flash"`, `"pro"` ou `"inherit"`.

**Decisões:**
- **Fonte única em `skills/avancar/modelos.md` e `scripts/stage-model.sh` (recomendação da triagem)** — manter o mapeamento `modelo:*` → tier do `agy` em `skills/avancar/modelos.md` (conforme ADR 0013) e expor a tradução em `scripts/stage-model.sh` (com cobertura em `scripts/test-stage-model.sh`), preservando o contrato atual de `claude -p`. Alternativa descartada: duplicar a tabela de mapeamento dentro das skills.
- **Uso no `revisar` e no `run_workflow` do `/fabrica:avancar` (recomendação da triagem)** — aplicar o tier traduzido tanto no `invoke_subagent` de `skills/revisar/SKILL.md` quanto no parâmetro `model` do `agent(...)` do `run_workflow` em `skills/avancar/SKILL.md`, mantendo `opencode` sem `model`. Alternativa descartada: aplicar apenas no `revisar/SKILL.md`.
- **Limites de escopo da entrega (recomendação da triagem)** — deixar fora desta issue o uso de `research`/`browser` nas etapas (#219) e a detecção automática da harness (#220), porque já possuem issues dedicadas abertas. Alternativa descartada: agrupar essas frentes na #218.
- **Mapeamento `haiku → flash_lite`, `sonnet → flash`, `opus → pro`** — alinha os três níveis de capacidade/custo da fábrica aos três tiers explícitos do `agy`, mantendo `inherit` apenas como fallback em erro. Alternativa descartada: mapear `sonnet` para `inherit`, o que deixaria o modelo depender da sessão atual do usuário em vez da tabela.

**Fontes da documentação:**
- `invoke_subagent` e `run_workflow` (definições das ferramentas nativas do Antigravity na sessão) — valores aceitos para `Model`/`model`: `"inherit"`, `"flash_lite"`, `"flash"`, `"pro"`.
- `scripts/stage-model.sh` — código existente (`model_rows`, `cmd_model`, `label_alias`).

**ADR:** nenhum.

## Testes
- **Unitários (`scripts/test-stage-model.sh` e `scripts/test-harness.sh`):** rodar `bash scripts/test-stage-model.sh && bash scripts/test-harness.sh` cobrindo o novo subcomando `agy-tier`, códigos de saída `0`/`1`/`2` e não regressão de `model`, `next`, `run` e `harness.sh`.
- **Verificação manual (CA4–CA6):** inspecionar `skills/revisar/SKILL.md`, `skills/avancar/SKILL.md`, `docs/guias/antigravity.md` e `docs/comandos.md` na branch.

## Passos de produção
nenhum

## Riscos e dúvidas
- Se futuras versões do `agy` renomearem os tiers `flash_lite`/`flash`/`pro`, bastará atualizar a coluna `Tier agy` em `skills/avancar/modelos.md`.

## Histórico
- 2026-11-25: criação.
- 2026-11-25: aprovada.
