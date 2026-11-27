# SPEC-241: remover adaptações e overrides do Antigravity e tratá-lo como sessão genérica

**Issue:** #241 · **PRD:** F10 · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-27

## Contexto
As adaptações específicas para o Antigravity CLI (`agy`) introduzidas nas issues #216–#220 criaram orquestração própria via `run_workflow`, subagentes estáticos de etapa em `agy-agents/`, delegação a `research`/`browser` e tradução de labels `modelo:*` para tiers (`flash_lite`, `flash`, `pro`) via `scripts/stage-model.sh agy-tier`. Como `run_workflow` e `invoke_subagent` no `agy` aceitam apenas tiers genéricos em vez de modelos específicos selecionados por terminal/sessão, essas adaptações impedem o fluxo desejado de abrir um terminal por agente com o modelo fixado manualmente e executar as etapas diretamente na sessão. Esta issue remove essas adaptações específicas (F10 — execução das etapas por sessão) para alinhar o Antigravity ao caminho genérico de sessão, como já ocorre no `opencode`.

## Objetivo
O Antigravity (`antigravity`) passa a ser tratado como caminho de sessão genérica em todas as etapas da fábrica (`triagem`, `spec`, `implementar`, `revisar`, `avancar`), rodando no modelo selecionado na sessão atual, sem `run_workflow`, `/swarm`, `agy-tier`, subagentes de etapa em `agy-agents/` ou instruções específicas de `research`/`browser`, mantendo apenas `agy-agents/revisor.md` e `agents.json` para o subagente `revisor`.

## Comportamento esperado
1. **Detecção de harness (`scripts/harness.sh`):**
   - `harness.sh detect` continua retornando `antigravity` quando `FABRICA_HARNESS=antigravity`, `ANTIGRAVITY_AGENT` ou `ANTIGRAVITY_CONVERSATION_ID` estão definidos (respeitando a precedência de `CLAUDECODE` e `FABRICA_HARNESS`).
   - `scripts/stage-model.sh run` continua saindo com código `3` (harness de sessão) tanto para `opencode` quanto para `antigravity`, sem invocar `claude -p`.
2. **Remoção de `agy-tier` (`scripts/stage-model.sh` e `skills/avancar/modelos.md`):**
   - `scripts/stage-model.sh` não possui mais o subcomando `agy-tier` nem a função `agy_tier`; chamar `stage-model.sh agy-tier ...` retorna código `1` (subcomando desconhecido).
   - `skills/avancar/modelos.md` não possui mais a coluna `Tier agy` na tabela `## Modelos` nem referências a `agy-tier`.
3. **Execução das etapas e orquestração (`skills/avancar/SKILL.md`):**
   - No passo 1 (`Harness`), quando `harness.sh detect` retorna `opencode` ou `antigravity`, o `/fabrica:avancar` segue diretamente para **Etapa na sessão** (sem `run_workflow`, sem `/swarm`, sem `stage-model.sh` e sem escalonamento de modelo).
   - O teto de 4 etapas por execução não possui mais exceção para `antigravity`.
4. **Revisão e subagente `revisor` (`skills/revisar/SKILL.md`, `agents/revisor.md`, `agy-agents/revisor.md`, `agents.json`):**
   - No `/fabrica:revisar`, quando a harness é `opencode` ou `antigravity`, nenhum parâmetro `model` ou `Model` é passado ao subagente `revisor` (ele herda o modelo da sessão). No Antigravity, o subagente continua sendo chamado via `invoke_subagent` com o nome `revisor`.
   - Os subagentes de etapa `agy-agents/triador.md`, `agy-agents/especificador.md` e `agy-agents/implementador.md` são removidos.
   - `agy-agents/revisor.md` e `agents.json` (contendo apenas `{"entries": [{"path": "agy-agents/revisor.md"}]}`) são mantidos para que o `agy` continue carregando o subagente `revisor` com os nomes de ferramentas do Antigravity.
5. **Remoção de instruções específicas de `research` e `browser`:**
   - `skills/triagem/SKILL.md` e `skills/spec/SKILL.md` não possuem mais a instrução de delegar exploração ao subagente `research` no Antigravity.
   - `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md`, `agents/revisor.md` e `agy-agents/revisor.md` não possuem mais as instruções de acionar o subagente `browser` no Antigravity.
6. **Documentação e testes:**
   - `docs/adr/0013-modelo-por-etapa-e-por-issue.md`, `docs/comandos.md`, `docs/fluxo.md` e `docs/guias/antigravity.md` refletem o novo comportamento sem `run_workflow`, `agy-tier`, `research`/`browser` nem subagentes de etapa.
   - Toda a suíte `scripts/test-*.sh` passa integralmente após as alterações.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `scripts/harness.sh detect` continua retornando `antigravity` para `FABRICA_HARNESS=antigravity`, `ANTIGRAVITY_AGENT` e `ANTIGRAVITY_CONVERSATION_ID`, e `scripts/stage-model.sh run` sai com código `3` sem chamar `claude` quando a harness é `antigravity` | unitário (`bash scripts/test-harness.sh`) |
| CA2 | `scripts/stage-model.sh` não aceita mais `agy-tier` (sai com código `1`), e `skills/avancar/modelos.md` não tem a coluna `Tier agy` nem menções a `agy-tier`, mantendo `model`, `next` e `run` funcionando | unitário (`bash scripts/test-stage-model.sh`) |
| CA3 | `agy-agents/triador.md`, `agy-agents/especificador.md` e `agy-agents/implementador.md` não existem no repositório; `agy-agents/revisor.md` permanece com corpo idêntico a `agents/revisor.md`; `agents.json` lista apenas `agy-agents/revisor.md` e passa em `agy plugin validate --strict` (quando `agy` disponível) e `claude plugin validate` (quando `claude` disponível) | unitário (`bash scripts/test-revisor-agent.sh`) |
| CA4 | `skills/avancar/SKILL.md` roteia `antigravity` para "Etapa na sessão" e não contém `run_workflow`, `/swarm` nem `agy-tier` | manual (inspeção de `skills/avancar/SKILL.md` e `grep`) |
| CA5 | `skills/revisar/SKILL.md` não chama `stage-model.sh agy-tier`, não passa `Model` no `antigravity` (herda o modelo da sessão) e não contém instruções para `browser` | manual (inspeção de `skills/revisar/SKILL.md` e `grep`) |
| CA6 | `skills/triagem/SKILL.md`, `skills/spec/SKILL.md`, `skills/implementar/SKILL.md`, `agents/revisor.md` e `agy-agents/revisor.md` não contêm instruções específicas de `research` ou `browser` para Antigravity | manual (inspeção dos arquivos e `grep`) |
| CA7 | `docs/adr/0013-modelo-por-etapa-e-por-issue.md`, `docs/comandos.md`, `docs/fluxo.md` e `docs/guias/antigravity.md` estão atualizados sem referências a `run_workflow`, `agy-tier`, `research`/`browser` ou subagentes de etapa em `agy-agents/` | manual (inspeção dos arquivos e `grep`) |
| CA8 | Todos os testes unitários do plugin (`scripts/test-*.sh`, exceto `test-job-acceptance.sh`, `test-sandbox-acceptance.sh` e `test-revisor-quality.sh`) passam sem falhas | unitário (`for t in scripts/test-*.sh; do ...; done`) |

## Fora de escopo
- Remover o suporte a `PreToolUse` e `SessionStart` do Antigravity nos hooks (`hooks/protect-main.sh`, `hooks/protect-production.sh`, `hooks/session-start.sh`), que continuam necessários para proteção e aviso de hooks do git ao instalar o plugin no `agy`.
- Alterar o comportamento do `opencode` ou do caminho `claude -p` / GitHub Actions dispatcher (`scripts/dispatch.sh`).
- Remover `agy-agents/revisor.md` e `agents.json` por completo (ver Decisões).

## Desenho técnico
**Arquivos e módulos:**
- **Removidos:**
  - `agy-agents/triador.md`
  - `agy-agents/especificador.md`
  - `agy-agents/implementador.md`
- **Alterados — Scripts e configuração:**
  - `scripts/stage-model.sh`: remover `agy_tier()`, `cmd_agy_tier()`, o ramo `agy-tier)` do `case`, a 3ª coluna do `model_rows()` e a menção a `agy-tier` no cabeçalho/mensagem de uso.
  - `skills/avancar/modelos.md`: remover a coluna `Tier agy` de `## Modelos` e as referências a `agy-tier` e `Tier agy` no texto, tratando `antigravity` junto com `opencode` no caminho de sessão.
  - `agents.json`: reduzir `entries` para `[{"path": "agy-agents/revisor.md"}]`.
  - `.claude-plugin/plugin.json`: subir `version` de `0.61.0` para `0.62.0`.
- **Alterados — Skills e agentes:**
  - `skills/avancar/SKILL.md`: no passo 1 (`Harness`), agrupar `opencode` e `antigravity` indo para `Etapa na sessão`; atualizar o texto de `Etapa na sessão` para incluir `antigravity`; remover as seções `Orquestração com run_workflow (Antigravity)` e `Papel do /swarm (opcional, fora do automático)`; remover a observação de `antigravity` no teto de 4 etapas.
  - `skills/revisar/SKILL.md`: em `Modelo do revisor`, agrupar `opencode` e `antigravity` para não passar `model`/`Model` ao subagente (herdando o modelo da sessão), removendo a chamada a `stage-model.sh agy-tier`; remover o bloco `Antigravity (browser)`.
  - `skills/triagem/SKILL.md`: remover o subitem `Antigravity (research)` da seção de leitura; manter o comportamento de caminho de sessão (`opencode` ou `antigravity`) que registra `sessão` e não aplica nem troca `modelo:*`.
  - `skills/spec/SKILL.md`: remover o subitem `Antigravity (research)` do passo 3 (`Ler`).
  - `skills/implementar/SKILL.md`: remover o item `Antigravity (browser)` do passo 4 (`Verificar`).
  - `agents/revisor.md` e `agy-agents/revisor.md`: remover a frase sobre o subagente `browser` no Antigravity do item 3, mantendo os corpos dos dois arquivos idênticos.
- **Alterados — Documentação:**
  - `docs/adr/0013-modelo-por-etapa-e-por-issue.md`: adicionar emenda registrando a remoção de `run_workflow`, `agy-agents/` de etapa e `stage-model.sh agy-tier`, passando `antigravity` a seguir o caminho genérico de sessão junto com `opencode`.
  - `docs/comandos.md` e `docs/fluxo.md`: remover referências a `run_workflow` e `stage-model.sh agy-tier`, descrevendo o Antigravity no caminho de sessão (igual ao OpenCode).
  - `docs/guias/antigravity.md`: remover as seções sobre `run_workflow`, `research`/`browser`, subagentes `triador`/`especificador`/`implementador` em `agy-agents/` e `stage-model.sh agy-tier`, mantendo o guia focado em instalação, hooks, subagente `revisor` e execução no modelo da sessão.
- **Alterados — Testes:**
  - `scripts/test-stage-model.sh`: substituir os testes de `agy-tier` (linhas 160–176) por teste verificando que `stage-model.sh agy-tier triagem` sai com código `1` (subcomando desconhecido).
  - `scripts/test-revisor-agent.sh`: atualizar CA2 para verificar `agents.json` apenas com `agy-agents/revisor.md`, remover o loop por `triador`, `especificador` e `implementador`, e atualizar a asserção do `agy plugin validate --strict` para `agents 1`.
  - `scripts/test-harness.sh` e `scripts/test-dispatch.sh`: sem alteração necessária (`test-harness.sh` já valida `antigravity` saindo com 3 em `stage-model.sh run`, e `test-dispatch.sh` não referencia `antigravity`/`agy`); ambos são executados na verificação final.

**Dados:** nenhum.

**Interfaces:**
- `scripts/stage-model.sh`: subcomandos públicos passam a ser `model`, `next` e `run` (sai com `1` para `agy-tier`).
- `scripts/harness.sh detect`: mantém as saídas `claude-code | opencode | antigravity | binario`.

**Decisões:**
- Manutenção de `agy-agents/revisor.md` e `agents.json`: manter `agy-agents/revisor.md` e `agents.json` apenas com a entrada `{"path": "agy-agents/revisor.md"}`, removendo só `triador.md`, `especificador.md` e `implementador.md` — `docs/guias/antigravity.md` e `scripts/test-revisor-agent.sh` mostram que o `agy` recusa `agents/revisor.md` (pelos nomes de ferramenta do Claude Code) e ignora subagentes sem `agents.json` (recomendação da triagem). Alternativa descartada: remover toda a pasta `agy-agents/` e o `agents.json` caso `/fabrica:revisar` no Antigravity passe a rodar sem subagente dedicado.
- Detecção em `scripts/harness.sh`: manter o retorno `antigravity` em `harness.sh detect` e tratá-lo junto com `opencode` como caminho de sessão genérica — `scripts/stage-model.sh` e `docs/adr/0013-modelo-por-etapa-e-por-issue.md` já distinguem a harness para registrar corretamente o ambiente da sessão (recomendação da triagem). Alternativa descartada: colapsar a detecção de `antigravity` em um retorno genérico único.
- Versão do plugin em `.claude-plugin/plugin.json`: incrementar de `0.61.0` para `0.62.0` — `AGENTS.md` exige subir `version` a cada mudança que altere comportamento de skills/scripts. Alternativa descartada: manter `0.61.0` sem bump de versão.

**Fontes da documentação:**
- gh 2.105.0 — usado apenas para leitura da issue e publicação dos comentários da fábrica (nenhum comando novo de `gh` introduzido no desenho técnico).

**ADR:** atualização de `docs/adr/0013-modelo-por-etapa-e-por-issue.md` (sem novo ADR).

## Testes
- `bash scripts/test-harness.sh` — valida CA1 (`harness.sh detect` retorna `antigravity` e `stage-model.sh run` sai com `3`).
- `bash scripts/test-stage-model.sh` — valida CA2 (`agy-tier` removido retornando código `1` e `modelos.md` sem `Tier agy`).
- `bash scripts/test-revisor-agent.sh` — valida CA3 (`agents.json` com apenas `agy-agents/revisor.md`, ausência dos 3 subagentes de etapa e corpo igual entre `agents/revisor.md` e `agy-agents/revisor.md`).
- Suíte completa unitária (`for t in scripts/test-*.sh; do case "$t" in *acceptance*|*revisor-quality*) continue;; esac; bash "$t" || exit 1; done`) — valida CA8.
- Inspeção e `grep` nos arquivos alterados de `skills/`, `agents/`, `agy-agents/` e `docs/` — validam CA4, CA5, CA6 e CA7.

## Passos de produção
nenhum

## Riscos e dúvidas
- Se algum usuário ainda tiver uma versão anterior do plugin em cache no `agy` (`agy plugin install`), precisará reinstalar após o merge para remover os subagentes antigos (`triador`, `especificador`, `implementador`) do cache local do Antigravity.

## Histórico
- 2026-11-27: criação.
- 2026-11-27: aprovada.
