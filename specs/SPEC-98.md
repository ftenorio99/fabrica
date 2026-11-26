# SPEC-98: Skills e revisor definem esforço, contexto e ferramentas proibidas no frontmatter

**Issue:** #98 · **PRD:** F10 · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-26

## Contexto
Hoje nenhuma skill do plugin nem o agente `revisor` usam os campos de frontmatter do Claude Code: tudo herda a sessão. O `/fabrica:avancar` diz "sem conversa no chat" só no texto, o `/fabrica:status` e o `/fabrica:metricas` despejam a saída do `gh` na sessão principal, as etapas mecânicas gastam o esforço da sessão e o revisor não tem teto de turnos. A F10 do PRD já escolhe o modelo por etapa ([ADR 0013](../docs/adr/0013-modelo-por-etapa-e-por-issue.md)); esta issue usa o frontmatter para o que o ADR 0013 não cobre, sem mexer nas etapas da tabela de `skills/avancar/modelos.md`.

## Objetivo
O `avancar` não consegue perguntar no chat, `status` e `metricas` rodam num subagente e devolvem só o resultado final, as etapas mecânicas rodam em esforço médio e o revisor para em um teto de turnos que o `revisar` não confunde com aprovação.

## Comportamento esperado
| Skill ou agente | Campo novo no frontmatter | Efeito |
|---|---|---|
| `skills/avancar/SKILL.md` | `disallowed-tools: AskUserQuestion` | Enquanto o `avancar` roda (até a próxima mensagem do usuário), a ferramenta `AskUserQuestion` não está disponível. |
| `skills/status/SKILL.md` | `context: fork`, `agent: general-purpose`, `background: false`, `effort: medium` | A skill roda num subagente com o corpo da skill como prompt; a sessão principal espera o resultado no mesmo turno e recebe o quadro completo, sem a saída dos comandos `gh`. |
| `skills/metricas/SKILL.md` | os mesmos quatro do `status` | Igual ao `status`: o relatório volta completo, os comandos ficam no subagente. |
| `skills/setup/SKILL.md` | `effort: medium` | O setup roda em esforço médio no turno em que foi chamado. Ele continua na sessão principal, porque pergunta e confirma com o usuário. |
| `agents/revisor.md` | `maxTurns: 80` | O revisor para depois de 80 turnos; o Claude Code devolve a saída marcada como parcial. |
| `triagem`, `spec`, `implementar`, `revisar` | nenhum | Ficam como estão: o esforço delas é o da tabela de `modelos.md` no `claude -p`, ou o da sessão. |

**Saída completa no `status` e no `metricas`:** como o resultado do subagente é a última mensagem dele, cada uma das duas skills ganha, no fim do corpo, a instrução de que a resposta final é o quadro (ou o relatório) inteiro, no formato que a skill já define, sem resumir nem dizer "veja acima".

**Revisão parcial no `revisar`** (passo 3, logo depois de "O revisor devolve..."):

| Resultado do revisor | O que o `revisar` faz |
|---|---|
| Completo | Segue como hoje. |
| Marcado como parcial (atingiu o `maxTurns`), 1ª vez nesta rodada | Não é aprovação nem lista de achados. Chama o revisor de novo, uma vez, numa chamada nova, com as mesmas entradas e a lista dos CAs que a saída parcial já cobriu com evidência. A nova chamada não conta como rodada de correção. |
| Parcial de novo | Abre ou atualiza o PR como rascunho, sem `pronto-revisao`, com "revisão incompleta: o revisor atingiu o teto de turnos" nos achados pendentes, aplica `escalonado` e registra uma lição com o gatilho `escalonado` ([formato.md](../skills/licao/formato.md)). |

Um CA atendido na saída parcial só vale como evidência se aparecer de novo na saída completa: o `revisar` não junta as duas.

**Ordem do teto:** o limite é inclusivo. No 80º turno o revisor ainda age; a saída parcial é a que o Claude Code devolve depois dele.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O frontmatter de `skills/avancar/SKILL.md` tem a linha `disallowed-tools: AskUserQuestion` e não tem `effort` nem `model`. | unitário — `scripts/test-skill-frontmatter.sh` |
| CA2 | Os frontmatters de `skills/status/SKILL.md` e `skills/metricas/SKILL.md` têm `context: fork`, `agent: general-purpose`, `background: false` e `effort: medium`, cada um numa linha `chave: valor`, e nenhum tem `model`. | unitário — `scripts/test-skill-frontmatter.sh` |
| CA3 | O frontmatter de `skills/setup/SKILL.md` tem `effort: medium` e não tem `context` nem `model`. | unitário — `scripts/test-skill-frontmatter.sh` |
| CA4 | Os frontmatters de `triagem`, `spec`, `implementar` e `revisar` não têm `effort`, `model` nem `context`. | unitário — `scripts/test-skill-frontmatter.sh` |
| CA5 | O frontmatter de `agents/revisor.md` é o da `origin/main` mais a linha `maxTurns: 80`, e nada mais muda nele. O `agy-agents/revisor.md` segue com o mesmo corpo e sem `maxTurns`. | unitário — `scripts/test-revisor-agent.sh` (CA1 ajustado) |
| CA6 | O `claude plugin validate` aceita o plugin sem aviso sobre as skills alteradas nem sobre o `agents/revisor.md`. | unitário — `scripts/test-revisor-agent.sh` (CA3) e `scripts/test-skill-frontmatter.sh`, pulado sem o binário `claude` |
| CA7 | O adaptador do OpenCode continua registrando `status`, `metricas`, `setup` e `avancar` com o mesmo `name`, `description` e `autoinvoke` de antes: o `parseFrontmatter` de `opencode/server.ts` lê os campos novos sem erro. | unitário — `scripts/test-skill-frontmatter.sh` chama o `parseFrontmatter` com `node --experimental-strip-types` sobre os quatro arquivos; pulado sem `node` ≥ 22.6 |
| CA8 | Com `claude --plugin-dir <wt>` na branch, `/fabrica:status ftenorio99/fabrica` mostra na sessão principal o quadro com todas as seções da skill e a linha de recomendação, e o transcript da sessão principal não tem nenhuma chamada `Bash` com `gh`: elas estão só no transcript do subagente. | manual — `claude -p --plugin-dir <wt> --output-format json "/fabrica:status ftenorio99/fabrica"` e leitura dos `.jsonl` da sessão e de `subagents/` em `~/.claude/projects/` |
| CA9 | Igual ao CA8 para `/fabrica:metricas ftenorio99/fabrica`: o relatório completo, com a tabela por issue e as notas, chega à sessão principal, e as chamadas `gh` e os scripts ficam só no subagente. | manual — mesmo caminho do CA8 |
| CA10 | Com `claude --plugin-dir <wt>`, `/fabrica:avancar` num repositório de teste sem issue `agente` termina sem chamar `AskUserQuestion`, e a lista de ferramentas da sessão durante o turno não tem `AskUserQuestion`. | manual — `claude -p --plugin-dir <wt> --output-format stream-json --verbose "/fabrica:avancar"` num clone de teste; o evento `system/init` ou as ferramentas disponíveis no turno mostram a ausência |
| CA11 | O passo 3 do `skills/revisar/SKILL.md` tem a tabela da revisão parcial: saída parcial não é aprovação, uma segunda chamada nova sem contar rodada, e na segunda parcial PR em rascunho, `escalonado`, lição `escalonado` e sem `pronto-revisao`. | manual — leitura do passo 3 pelo revisor contra esta spec |
| CA12 | `docs/comandos.md` diz que `status` e `metricas` rodam num subagente e devolvem só o resultado, que as etapas mecânicas rodam em esforço médio pelo frontmatter, e que o revisor tem teto de 80 turnos; `docs/fluxo.md` cita a revisão parcial. Nenhum dos dois copia a tabela desta spec. | manual — leitura dos dois arquivos |
| CA13 | A `version` de `.claude-plugin/plugin.json` sobe de `0.59.1` para `0.60.0`. | unitário — `scripts/test-skill-frontmatter.sh` compara com a `origin/main` |
| CA14 | A comparação de um período antes e um depois da mudança no `/fabrica:metricas` (repositório `kairo`, ao menos 3 issues entregues em cada período) vai para um comentário na #98 com tokens e tempo com o agente por issue, e a contagem manual de devoluções do `revisar` ao `implementar` e de achados de mudança fora do escopo. | depois do merge — precisa de issues do `kairo` entregues com a versão nova instalada, e o período "depois" só começa no merge |

## Fora de escopo
- `effort` ou `model` em `triagem`, `spec`, `revisar` e no agente `revisor` (resposta **a** à pergunta 1 da triagem).
- Mudar o esforço do `implementar` ou qualquer linha de `skills/avancar/modelos.md`.
- `permissionMode`, `hooks` e `mcpServers` no revisor: são ignorados em subagentes de plugin.
- `maxTurns` no `agy-agents/revisor.md` e campos equivalentes no Antigravity e no OpenCode.
- Novas contagens nos scripts do `/fabrica:metricas` (devoluções e fora do escopo).
- Isolamento em sandbox (#93) e worktrees (#16).

## Desenho técnico
**Arquivos e módulos:**
- `skills/avancar/SKILL.md`, `skills/status/SKILL.md`, `skills/metricas/SKILL.md`, `skills/setup/SKILL.md`: campos novos no frontmatter, um por linha, no formato `chave: valor` (o `parseFrontmatter` do OpenCode só lê esse formato; nada de lista YAML em várias linhas). No `status` e no `metricas`, uma linha no fim do corpo sobre a resposta final completa.
- `agents/revisor.md`: `maxTurns: 80` no frontmatter. Corpo inalterado, então o `agy-agents/revisor.md` não muda.
- `skills/revisar/SKILL.md`: tabela da revisão parcial no passo 3.
- `scripts/test-revisor-agent.sh`: o CA1 compara o frontmatter da `origin/main` com o atual sem a linha `maxTurns:` e confere que ela é `maxTurns: 80`.
- `scripts/test-skill-frontmatter.sh` (novo): CA1 a CA4, CA6, CA7 e CA13, no estilo `check`/`skip` do `test-revisor-agent.sh`. Entra no CI sozinho, pelo padrão `scripts/test-*.sh` do `.github/workflows/ci.yml`.
- `AGENTS.md`: a lista de testes cita o `scripts/test-skill-frontmatter.sh`.
- `docs/comandos.md`, `docs/fluxo.md`: o manual (CA12).
- `.claude-plugin/plugin.json`: `0.60.0`.

**Dados:** nenhum.

**Interfaces:** nenhuma função nova. O `parseFrontmatter` de `opencode/server.ts` não muda.

**Decisões:**
- `effort: medium` em `status`, `metricas` e `setup`, sem `model` (recomendação da triagem) — o `effort` tende a render mais dentro do Claude Code, e o ADR 0013 deixa a escolha de modelo em `modelos.md`. Alternativa descartada: `model: sonnet`.
- `implementar` não muda (recomendação da triagem) — o ADR 0013 fixa o esforço dele em `modelos.md`, e um `effort` no frontmatter passaria por cima do `--effort` do `stage-model.sh run`. Alternativa descartada: baixar o esforço já agora.
- `avancar` só com `disallowed-tools: AskUserQuestion`, sem `effort` nem `model` (recomendação da triagem) — o "Primeiro passo" da issue não o lista, e o mapa que o inclui é hipótese a medir. Alternativa descartada: Haiku ou Sonnet em médio.
- Devoluções do `revisar` e achados fora do escopo contados à mão na comparação do CA14 (recomendação da triagem) — o "Escopo" pede medir com a skill existente. Alternativa descartada: incluir as contagens no `/fabrica:metricas`.
- Sem `effort` nas etapas de julgamento nem no revisor — resposta **a** do usuário à pergunta 1 da triagem; o ADR 0013 não precisa de emenda. Alternativa descartada: `high` nas três e no revisor, como no "Escopo" original.
- `background: false` no `status` e no `metricas` — sem ele, o subagente de `context: fork` roda em segundo plano e o quadro chega depois do turno, contra o que o usuário espera de um comando de leitura. Alternativa descartada: o padrão em segundo plano.
- `agent: general-purpose` explícito — o subagente precisa de `Bash` para o `gh` e os scripts, e o tipo fica declarado em vez de depender do padrão. Alternativa descartada: omitir o campo.
- `context: fork` só em `status` e `metricas`, não no `setup` — o subagente não conversa com o usuário, e o `setup` pergunta e confirma. Alternativa descartada: fork no `setup` também.
- `maxTurns: 80` — nas 200 chamadas do `fabrica:revisor` registradas em `~/.claude/projects/` desta máquina, a maior usou 52 mensagens com ferramenta e 95% ficaram em até 30; 80 deixa folga para uma branch grande e corta um laço. Alternativa descartada: 50, que já cortaria a maior revisão observada.
- Revisão parcial: uma chamada nova, não a retomada do mesmo subagente — o `revisar` também roda fora do Claude Code (Antigravity, OpenCode), onde a retomada não existe, e uma chamada nova é igual nos três. Alternativa descartada: retomar o subagente pelo `SendMessage`.
- Sem ADR — a decisão de modelo e esforço por etapa continua a do ADR 0013; esta issue só usa campos do frontmatter em etapas fora da tabela dele.

**Fontes da documentação:**
- Claude Code 2.1.332 — Context7 `/websites/code_claude` (páginas `skills` — campos `effort`, `context`, `agent`, `disallowed-tools`, `background` e "Run skills in a subagent"; `sub-agents` — `maxTurns` e saída parcial, que exige v2.1.246 ou posterior; `plugins/components` — campos aceitos e ignorados em agentes de plugin). Versão não confirmada: o Context7 serve a doc atual, sem versão.
- gh 2.105.0 — nenhum comando nem flag novos no desenho; os comandos do CA14 são os que o `/fabrica:metricas` já usa.

**ADR:** nenhum.

## Testes
- `bash scripts/test-skill-frontmatter.sh`: lê o frontmatter de cada `SKILL.md` com o mesmo `awk` do `test-revisor-agent.sh` e confere as linhas exatas dos CA1 a CA4; roda `claude plugin validate` (CA6) e o `parseFrontmatter` do OpenCode via `node` (CA7), pulando cada um sem o binário; compara a `version` com a da `origin/main` (CA13).
- `bash scripts/test-revisor-agent.sh`: CA5 e CA6.
- CA8 a CA10: o implementar roda os comandos do CA e anota a saída e os trechos dos transcripts nas verificações manuais.
- O projeto não tem `make`: as suítes rodam direto com `bash`, como no CI.

## Passos de produção
nenhum

## Riscos e dúvidas
- O `effort` do frontmatter vale "para o resto do turno": no `setup`, depois que o usuário responde a uma pergunta, o turno seguinte volta ao esforço da sessão. É aceito: o trabalho pesado do `setup` são scripts.
- O `disallowed-tools` some na próxima mensagem do usuário. No caminho `claude -p` do `avancar` não há mensagem nova, então ele vale a execução inteira; numa sessão interativa, vale até o usuário falar.
- O subagente do `context: fork` não vê a conversa: o `status` e o `metricas` só recebem `$ARGUMENTS`. Um pedido como "o status daquele repo de antes" não é entendido; o argumento precisa ser explícito.
- Se o Antigravity ou o OpenCode passarem a ler `context: fork` de outro jeito, o comportamento neles muda; hoje o adaptador do OpenCode ignora campos que não conhece.
- O CA14 só fecha depois do merge, com issues do `kairo`.

## Histórico
- 2026-11-26: criação.
