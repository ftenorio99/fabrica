# SPEC-200: roda a etapa no modelo da sessão quando a harness é o OpenCode

**Issue:** #200 · **PRD:** F10 (item do fatiamento não vinculado) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-19

## Contexto
O `/fabrica:avancar` escolhe entre `claude -p` e a sessão pela presença do binário `claude` ([ADR 0013](../docs/adr/0013-modelo-por-etapa-e-por-issue.md)). Numa máquina com o Claude Code instalado e a sessão no OpenCode, essa regra manda a etapa para um `claude -p` aninhado e aplica a tabela de [modelos.md](../skills/avancar/modelos.md). A #20 do ankyra mostrou o efeito: a triagem tentou aplicar `modelo:opus` num repositório sem a label e parou. A escolha precisa ser pela harness, não pelo binário. O adaptador do OpenCode já entrega `OPENCODE_SESSION_ID` ao shell das ferramentas e pode injetar uma variável própria.

## Objetivo
O `/fabrica:avancar` detecta a harness antes do binário e, no OpenCode ou no Antigravity, executa a etapa na sessão, sem `claude -p`, sem label `modelo:*` e sem escalonamento; o Claude Code e o dispatcher continuam iguais.

## Comportamento esperado

### 1. Detecção (`scripts/harness.sh detect`)
A detecção imprime uma única linha: `claude-code`, `opencode`, `antigravity` ou `binario`, nesta ordem de precedência:

| Ordem | Condição | Resultado |
|---|---|---|
| 1 | `CLAUDECODE` existe e não é vazia | `claude-code` |
| 2 | `FABRICA_HARNESS` é `opencode`, `antigravity` ou `claude-code` | o valor normalizado |
| 3 | `OPENCODE_SESSION_ID` existe e não é vazia | `opencode` |
| 4 | nenhuma das anteriores | `binario` |

- `CLAUDECODE` vem primeiro porque as variáveis do OpenCode passam para um `claude` aberto de dentro dele; o processo filho precisa se reconhecer como Claude Code, não como OpenCode.
- Variáveis vazias contam como ausentes. `FABRICA_HARNESS` com qualquer outro valor sai com código 2 e uma mensagem com os valores aceitos; uma configuração inválida não pode virar silenciosamente um caminho.
- `FABRICA_HARNESS=antigravity` é o sinal manual do Antigravity enquanto o #149 não define o sinal automático. Sem ele, o Antigravity continua no caminho de `binario`.
- Sem nenhum sinal, `binario` preserva o comportamento atual: o `avancar` confere o binário `claude` e, se ele não existir, executa a etapa na sessão.

### 2. Caminho da etapa no `avancar`
- **`opencode` ou `antigravity`:** a etapa roda na sessão. O `avancar` não chama `stage-model.sh run`, não lê nem aplica `modelo:*`, não faz escalonamento de modelo, e a coluna "Modelo" do relatório mostra `sessão`.
- **`claude-code` ou `binario`:** vale o caminho atual. O `avancar` confere o binário `claude`; se existir, usa `stage-model.sh run` e a tabela de modelos; se não existir, usa a sessão, como hoje.
- O caminho de sessão continua lendo o `SKILL.md` da etapa e seguindo as instruções com a pasta da própria etapa, como a seção atual "Sem o `claude`". Ela passa a se chamar **Etapa na sessão** e continua sendo o destino quando o binário não existe.
- No caminho de sessão, a triagem registra `sessão` na linha `Modelo` do comentário e **não aplica nem troca** label `modelo:*`. Uma label que já estava na issue permanece: ela vale se a issue for retomada pelo Claude Code, e retirar seria uma decisão do usuário.

### 3. Guarda no `stage-model.sh`
Como a instrução do `avancar` é texto lido por um modelo, `stage-model.sh run` ganha uma segunda trava: depois de validar os argumentos, chama `harness.sh detect`. Se a harness for `opencode` ou `antigravity`, sai com **3**, sem chamar o `claude` e sem aplicar nenhuma label. `claude-code`, `binario` e o dispatcher, que não têm os sinais de sessão, seguem exatamente como hoje. Um valor inválido de `FABRICA_HARNESS` faz o `run` sair com 1, sem chamar o `claude`.

### 4. Injeção pelo adaptador do OpenCode
O `opencode/server.ts` registra `ctx.shell.hook("create.before")` e, quando `event.env` existe e `FABRICA_HARNESS` está vazia, define `FABRICA_HARNESS="opencode"`. Um valor já definido pelo usuário é preservado. Erro ao registrar o hook ou ao ajustar o ambiente é logado e não derruba o plugin; nesse caso, `OPENCODE_SESSION_ID` continua sendo a reserva.

### 5. O que não muda
O Claude Code não recebe `FABRICA_HARNESS` nem `OPENCODE_SESSION_ID`, então continua em `claude-code` pelo `CLAUDECODE` ou em `binario`. O dispatcher do GitHub Actions não tem nenhum dos dois sinais e continua usando `stage-model.sh run`. As tabelas de [modelos.md](../skills/avancar/modelos.md) e o escalonamento continuam valendo só para o caminho `claude -p`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `harness.sh detect` devolve `claude-code` com `CLAUDECODE` não vazia, inclusive quando `FABRICA_HARNESS=opencode` e `OPENCODE_SESSION_ID` também estão presentes; devolve o valor de `FABRICA_HARNESS` quando ele é `opencode`, `antigravity` ou `claude-code` e `CLAUDECODE` está ausente; devolve `opencode` com só `OPENCODE_SESSION_ID`; devolve `binario` sem nenhum sinal. | unitário — `scripts/test-harness.sh` |
| CA2 | `harness.sh detect`: variáveis vazias contam como ausentes; `FABRICA_HARNESS=OPenCode` e qualquer valor fora da lista saem com 2, sem imprimir uma harness; a mensagem de erro lista os três valores aceitos. | unitário — `scripts/test-harness.sh` |
| CA3 | `stage-model.sh run` com `FABRICA_HARNESS=opencode` ou `antigravity` sai com 3, não chama o `claude` e não cria JSON; com `CLAUDECODE` não vazia e `OPENCODE_SESSION_ID` presente, chama o `claude` normalmente; sem sinais, mantém o comportamento atual; com `FABRICA_HARNESS` inválida, sai com 1 sem chamar o `claude`. | unitário — `scripts/test-harness.sh`, com `claude` falso que registra a chamada |
| CA4 | `opencode/server.ts` registra `ctx.shell.hook("create.before")`, define `FABRICA_HARNESS="opencode"` quando a variável está vazia e preserva um valor já definido; um erro no hook é logado sem derrubar o `setup`. | unitário — `scripts/test-harness.sh` lê o `server.ts` e confere o hook e a atribuição condicional |
| CA5 | `skills/avancar/SKILL.md` manda detectar a harness antes de conferir o binário; em `opencode` e `antigravity` manda para "Etapa na sessão", proíbe `stage-model.sh run`, label `modelo:*` e escalonamento, e manda o relatório mostrar `sessão`; em `binario`, se o `claude` não existir, continua para a sessão; em `claude-code`/`binario` com o binário, mantém o caminho atual. | manual — leitura do diff na revisão |
| CA6 | `skills/triagem/SKILL.md` detecta a harness antes de escolher o modelo; em `opencode` ou `antigravity`, registra `sessão` na tabela e não aplica nem troca label `modelo:*`; uma label já presente permanece e não gera erro. | manual — leitura do diff na revisão |
| CA7 | `skills/avancar/modelos.md` diz que a tabela e o escalonamento valem só para o caminho `claude -p`; o ADR 0013 registra a detecção por harness, a precedência de `CLAUDECODE`, o caminho de sessão e o Antigravity; `docs/comandos.md` reflete o mesmo nos verbetes da triagem e do `avancar`; `opencode/README.md` cita a injeção de `FABRICA_HARNESS` e a reserva por `OPENCODE_SESSION_ID`. | manual — leitura do diff na revisão |
| CA8 | `bash scripts/test-harness.sh`, `bash scripts/test-stage-model.sh`, `bash scripts/test-dispatch.sh` e os demais testes listados no `AGENTS.md` passam; os testes que simulam o runner limpam `CLAUDECODE`, `FABRICA_HARNESS` e `OPENCODE_SESSION_ID`, então continuam passando quando são chamados de dentro do OpenCode; o Claude Code e o dispatcher não recebem comportamento novo quando não há sinal de sessão. | unitário — as suítes locais |

## Fora de escopo
- Definir o sinal automático do Antigravity: fica com o #149; aqui só o `FABRICA_HARNESS=antigravity` manual.
- Mudar o modelo da sessão do OpenCode ou o modelo padrão do Claude Code.
- Levar o custo/tokens do OpenCode para o `stage-usage.py`.
- Corrigir a label ausente que parou a #20 do ankyra: a correção é não tentar aplicá-la no caminho de sessão.
- Mudar o isolamento do dispatcher ou o modelo das etapas no GitHub Actions.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/harness.sh` (novo): `detect` com a precedência e as saídas da seção 1.
- `scripts/test-harness.sh` (novo): CA1 a CA4 e CA8; `claude` falso para provar que o `run` não chama o binário no caminho de sessão.
- `scripts/test-stage-model.sh` e `scripts/test-dispatch.sh`: limpam `CLAUDECODE`, `FABRICA_HARNESS` e `OPENCODE_SESSION_ID` nas chamadas que simulam o runner, senão os testes rodados de dentro do OpenCode cairiam na guarda de sessão.
- `scripts/stage-model.sh`: guarda de harness no `cmd_run`, antes de `cmd_model`, com a saída 3 documentada no cabeçalho; as saídas atuais 1 e 2 não mudam.
- `skills/avancar/SKILL.md`: passo 3, seção "Sem o `claude`" renomeada para "Etapa na sessão", coluna "Modelo" e regra de escalonamento.
- `skills/triagem/SKILL.md`: escolha do modelo e aplicação da label; o caminho de sessão não aplica nem troca `modelo:*`.
- `skills/avancar/modelos.md`: nota de que a tabela vale só para o caminho `claude -p`.
- `opencode/server.ts`: hook `shell.create.before` que injeta `FABRICA_HARNESS=opencode` sem sobrescrever valor existente.
- `docs/adr/0013-modelo-por-etapa-e-por-issue.md`: emenda com a detecção por harness.
- `docs/comandos.md`, `opencode/README.md`, `AGENTS.md` (o teste novo na lista de scripts) e `.claude-plugin/plugin.json` (próxima versão livre; na branch, 0.46.0, reajustada se outra issue subir antes do merge).

**Dados:** nenhum.

**Interfaces:**
- `scripts/harness.sh detect` → `claude-code`, `opencode`, `antigravity` ou `binario`, com código 0; código 2 e mensagem para `FABRICA_HARNESS` inválido.
- `scripts/stage-model.sh run` → 0 sucesso; 1 uso/configuração inválida; 2 labels `modelo:*` inconsistentes; 3 etapa de sessão, sem chamar o `claude`.

**Decisões:**
- Detectar por `FABRICA_HARNESS`, injetada pelo `opencode/server.ts`, com `OPENCODE_SESSION_ID` como reserva, porque a variável própria não depende de uma variável interna do OpenCode e a reserva já existe no ambiente observado. Alternativa descartada: só `OPENCODE_SESSION_ID`, que fica presa a um detalhe do OpenCode (recomendação da triagem).
- `CLAUDECODE` tem precedência sobre tudo, porque um `claude -p` aberto de dentro do OpenCode herda as variáveis do OpenCode e precisa continuar sendo Claude Code. Alternativa descartada: só `FABRICA_HARNESS`/`OPENCODE_SESSION_ID`, que fariam o filho se declarar OpenCode e recusar o próprio modelo.
- Antigravity usa o mesmo caminho da sessão, com `FABRICA_HARNESS=antigravity` manual, e o sinal automático fica com o #149, como a issue pede (recomendação da triagem). Alternativa descartada: adivinhar o Antigravity por variável de terceiros.
- No `avancar`, `FABRICA_HARNESS` ou `OPENCODE_SESSION_ID` mandam para a sessão; sem eles, vale a regra atual do binário, mantendo o Claude Code e o dispatcher inalterados (recomendação da triagem). Alternativa descartada: exigir `FABRICA_HARNESS=claude-code` para o Claude Code.
- `stage-model.sh run` recusa a harness de sessão com código 3, porque o `avancar` é texto e a guarda impede um `claude -p` aninhado mesmo se a instrução for ignorada. Alternativa descartada: confiar só no texto da skill.
- A triagem não aplica `modelo:*` no caminho de sessão, nem remove uma label anterior, porque a label é uma escolha para o caminho Claude Code e remover apagaria uma decisão do usuário. Alternativa descartada: remover todas as labels de modelo no OpenCode.
- A tabela de modelos e o escalonamento só valem no caminho `claude -p`, porque no OpenCode o modelo é o da sessão e o `stage-model.sh` não participa. Alternativa descartada: manter a tabela e só esconder a coluna do relatório.
- O teste automatizado cobre a detecção e a guarda; a aderência do `avancar` e da `triagem` às instruções é conferida na leitura do diff, porque o texto da skill é interpretado pelo modelo. Alternativa descartada: um teste que simule o agente, que não existe no repositório.

**Fontes da documentação:**
- OpenCode v2.3.2 — `opencode --version`; [documentação de plugins do servidor](https://opencode.ai/docs/build/plugins/server/), seção `Shell`, confirma o hook `create.before` e o `event.env` mutável. Versão do site não confirmada: a documentação não é versionada.
- gh 2.104.0 — `gh issue view --help` (campos `labels`, `comments`), usado apenas nos comandos que a etapa já executa. Nenhuma flag nova de `gh` entra nesta issue.

**ADR:** [docs/adr/0013-modelo-por-etapa-e-por-issue.md](../docs/adr/0013-modelo-por-etapa-e-por-issue.md) (emenda; não há ADR novo).

## Testes
- `bash scripts/test-harness.sh`: CA1 a CA4 e CA8, com matrizes de ambiente (`env -u` para limpar `CLAUDECODE`, `FABRICA_HARNESS` e `OPENCODE_SESSION_ID`), um `claude` falso que registra se foi chamado e leitura do `opencode/server.ts` para o hook.
- `bash scripts/test-stage-model.sh`: os casos de modelo e permissão continuam passando com `CLAUDECODE`, `FABRICA_HARNESS` e `OPENCODE_SESSION_ID` removidos nas chamadas que simulam o runner; o teste novo cobre a saída 3 e a ausência da chamada ao `claude`.
- `bash scripts/test-dispatch.sh`: continua passando, porque o `dispatch()` de teste remove os sinais de sessão antes de chamar o `dispatch.sh`, como o runner do Actions.
- `bash opencode/test-adapter.sh`: continua sendo o aceite no VM do `sbx`; a injeção do `FABRICA_HARNESS` é conferida pela leitura do `server.ts` no teste de harness, e a sessão real não depende dela por causa da reserva `OPENCODE_SESSION_ID`.

## Passos de produção
nenhum

## Riscos e dúvidas
- **O texto da skill é interpretado por um modelo.** O teste não prova que o `avancar` deixa de chamar o `stage-model.sh`; a guarda do CA3 garante que, se chamar, a etapa não roda no caminho errado. A leitura do diff cobre o texto.
- **`FABRICA_HARNESS` vazada para um filho Claude Code:** se uma futura ferramenta abrir o Claude Code sem `CLAUDECODE`, ela será tratada como `opencode`; por isso `CLAUDECODE` tem precedência e o teste do CA3 cobre o caso.
- **Antigravity sem sinal automático:** até o #149, o usuário precisa definir `FABRICA_HARNESS=antigravity`; sem isso, o caminho continua sendo o do binário.
- **Label existente:** uma issue com `modelo:*` vinda do Claude Code mantém a label no OpenCode; ela não atrapalha a sessão e volta a valer numa execução no Claude Code.
- **Versão do plugin:** a branch parte de 0.45.0, mas a primeira issue que subir a versão define o número; o reajuste é uma linha.

## Histórico
- 2026-11-19: criação.
