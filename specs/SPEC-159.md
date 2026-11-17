# SPEC-159: OpenCode: hooks de proteção da main, de produção e do ~/.claude

**Issue:** #159 · **PRD:** nenhuma F diretamente: protege no OpenCode o que a F1 e a F2 protegem no Claude Code (ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-17

## Contexto
Esta é a fase 3 do `opencode/PLANO-OPENCODE.md` (§4.5), sobre a #149. No Claude Code, os hooks `hooks/protect-main.sh` e `hooks/protect-production.sh` recusam os comandos que desligariam os hooks do git ou que citam produção. No OpenCode, o adaptador da #157 ainda não tem proteção nenhuma.

A fase 0 (#149) confirmou três coisas:
- o `deny` do `ctx.permission.hook("evaluate")` barra a ferramenta `shell`, também com `--auto`;
- o `resources` traz cada comando da linha separado, sem o encadeamento;
- a linha inteira chega antes, no `tool.execute.before`, com o mesmo id da chamada.

## Objetivo
No OpenCode, o adaptador nega o que o Claude Code nega, chamando os mesmos scripts de `hooks/` com a linha de comando inteira, e nega também a escrita no `~/.claude/` e a statusline. Nada fora de `opencode/` muda.

## Comportamento esperado
**Ponte da linha de comando.**
1. `ctx.tool.hook("execute.before")`: quando `event.tool === "shell"`, guarda `event.input.command` num `Map` indexado por `event.id`.
2. `ctx.permission.hook("evaluate")`: quando `event.action === "shell"`, busca a linha por `event.source.id`, apaga a entrada do `Map` e avalia essa linha. Sem linha no `Map`, avalia `event.resources.join(" && ")`.
3. O `Map` nunca passa de 256 entradas: ao passar, apaga a mais antiga. Uma chamada que nunca chega à permissão não deixa a memória crescer.

**Avaliação de uma linha de shell, nesta ordem, parando na primeira negativa:**

| Passo | O que roda | Quando nega |
|---|---|---|
| 1 | `bash <raiz>/hooks/protect-main.sh`, com a entrada `{"tool_input":{"command":<linha>},"cwd":<diretório>}` | a saída tem `hookSpecificOutput.permissionDecision: "deny"` |
| 2 | `bash <raiz>/hooks/protect-production.sh`, com a mesma entrada | idem |
| 3 | guarda-corpo (abaixo), se não estiver desligado | a linha cita o `~/.claude` ou o `setup-statusline.sh` |

- **Negativa:** o hook define `event.effect = "deny"`. Nos passos 1 e 2, `event.message` recebe o `permissionDecisionReason` do script, sem mudança, e no passo 3 recebe a mensagem do guarda-corpo.
- **Diretório:** é o `ctx.location.directory` da instância do plugin, o projeto em que o OpenCode está aberto.
- **Sem negativa:** o hook não mexe no evento, e vale a decisão que o OpenCode já tinha (`allow` ou `ask`).

**Guarda-corpo.** Fica ligado por padrão e é desligado com `"options": {"protectClaudeConfig": false}` na entrada do plugin, sem mexer nos passos 1 e 2.

| Ação | Nega quando | Mensagem |
|---|---|---|
| `shell` | a linha contém `~/.claude`, `$HOME/.claude`, `${HOME}/.claude` ou `<home do usuário>/.claude`, ou contém `setup-statusline.sh` | `[fabrica] No OpenCode, a fábrica não altera a configuração do Claude Code (~/.claude) nem a statusline. Esse passo é só do Claude Code.` |
| `edit` | algum item de `event.resources` é um caminho dentro de `<home do usuário>/.claude/` | a mesma |

A leitura pela ferramenta `read` continua liberada (recomendação da triagem).

**Robustez.**

| Situação | O que acontece |
|---|---|
| Um script sai com código diferente de 0, não imprime nada ou imprime algo que não é JSON | conta como "sem negativa", que é o mesmo comportamento dos scripts no Claude Code quando falta o `jq`. O erro vai para o log com o prefixo `[fabrica]` |
| Um script demora mais de 10 s | o processo é encerrado, e o caso conta como "sem negativa", com erro no log |
| O script não existe na raiz | conta como "sem negativa", com erro logado uma vez por setup |
| `ctx.tool.hook` ou `ctx.permission.hook` ausente ou com erro | erro logado. Skills e comandos continuam, e o plugin continua `active` |

O hook nunca lança exceção para fora. Ele não escreve em disco e não usa a rede. Os scripts que ele chama se comportam como no Claude Code.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `POST /api/session/<id>/permission` com `action: "shell"` e o recurso `git commit --allow-empty -m teste` mais a flag que pula a verificação do git devolve `deny`, e a mensagem é o `permissionDecisionReason` do `protect-main.sh` | manual: `opencode serve` local, com o plugin no `opencode.jsonc` de um repositório de teste numa pasta temporária, como na #157 |
| CA2 | Com um `.fabrica/producao.txt` no repositório de teste que lista `prod.exemplo.com`, a avaliação de `curl https://prod.exemplo.com` devolve `deny`, com a mensagem do `protect-production.sh` | manual: mesma sessão do CA1 |
| CA3 | A avaliação de `echo x > ~/.claude/teste` devolve `deny` com a mensagem do guarda-corpo, e a de `action: "edit"` com o recurso `<home>/.claude/settings.json` também | manual: mesma sessão do CA1 |
| CA4 | A avaliação de `git status` não devolve `deny` | manual: mesma sessão do CA1 |
| CA5 | Com `"protectClaudeConfig": false`, o caso de shell do CA3 deixa de devolver `deny`, e o do CA1 continua `deny` | manual: mesma sessão, com a entrada do plugin trocada e o servidor reiniciado |
| CA6 | Numa linha encadeada em que o comando proibido não é o primeiro (`git status && git commit` mais a flag), o agente recebe a negativa: a ponte entrega a linha inteira ao `protect-main.sh` | manual: `opencode run --auto` no repositório de teste (CA7). O log do plugin mostra a linha inteira avaliada. A reserva `resources.join(" && ")` se confere pela API, com os recursos separados |
| CA7 | Com modelo, pelo `opencode run --auto` no repositório de teste, o pedido de um commit com a flag que pula a verificação termina em erro com a mensagem do `protect-main.sh`, e a contagem de commits (`git rev-list --count HEAD`) não muda | manual: repositório de teste temporário, apagado no fim, com o modelo gratuito do gateway do OpenCode, no método da fase 0 (#149) |
| CA8 | `bash scripts/test-protect-main.sh`, `bash scripts/test-protect-production.sh` e os outros `scripts/test-*.sh` da `main` passam, menos o `test-sandbox-acceptance.sh` | manual: rodar cada script |
| CA9 | `git diff --name-only origin/main...HEAD` mostra só caminhos em `opencode/` e o `specs/SPEC-159.md` | manual: o comando, na branch |

## Fora de escopo
- Mudar os scripts de `hooks/` ou os testes deles. As regras continuam num só lugar.
- O comando de shell digitado pelo próprio usuário no OpenCode, que não passa pelo hook de permissão (limite da §4.5).
- Uma regra `deny` configurada pelo usuário, que é final e não chama o hook.
- Nota de sessão sobre os hooks do git (#160), agente revisor (#158), `test-adapter.sh` e README (#161).
- Detectar escrita no `~/.claude/` feita por dentro de um script, sem citar o caminho na linha.

## Desenho técnico
**Arquivos e módulos:** só `opencode/server.ts`. As funções `resolveRoot` e o `LOG_PREFIX`, que já existem, são reaproveitados.

**Dados:** nenhum.

**Interfaces:**
- `runHookScript(root, script, command, cwd): { deny: boolean, reason?: string }`: chama `spawnSync("bash", [join(root, "hooks", script)], { input, encoding: "utf8", timeout: 10000 })` e lê `hookSpecificOutput.permissionDecision` e `permissionDecisionReason`.
- `claudeGuard(action, command | resources, home): string | undefined`: devolve a mensagem do guarda-corpo quando nega.
- `evaluateShell(root, line, cwd, guard): { deny, reason } `: os três passos, na ordem.
- `PENDING_LIMIT = 256` e o `Map<string, string>` da ponte.
- No `setup`, dois registros novos, cada um num `try/catch`: `ctx.tool.hook("execute.before", ...)` e `ctx.permission.hook("evaluate", ...)`.

**Decisões:**
- **Alcance do guarda-corpo** (recomendação da triagem): nega a ação `edit` dentro de `~/.claude/` e as linhas de shell que citam o caminho ou o `setup-statusline.sh`, e deixa a leitura pelo `read` liberada. Uma linha de shell não diz se escreve, e negar toda linha que cita o caminho é a regra que dá para conferir por texto, como as do `protect-main.sh`. Alternativa: distinguir leitura de escrita na linha (redirecionamento, `cp`, `sed -i`), que deixa brechas.
- **`protectClaudeConfig: false` desliga só o guarda-corpo** (recomendação da triagem). Fontes: a issue e a §4.5. Alternativa: uma opção que desliga tudo, o que permitiria desligar a proteção da main pela configuração.
- **Contrato do Claude Code para os scripts** (recomendação da triagem): a entrada é `{"tool_input":{"command"},"cwd"}`, e a saída lida é `hookSpecificOutput.permissionDecision`. Fontes: a issue, a §4.5 e os scripts (`hooks/protect-main.sh:11-22`). Alternativa: o contrato do Antigravity, que os scripts também aceitam, mas que a §4.5 descarta para não criar um terceiro.
- **CA com modelo pelo `opencode run --auto` num repositório temporário** (recomendação da triagem): é o método da fase 0 (#149), e o `opencode run` executa ferramentas. Alternativa: deixar esse CA para depois do merge, pelo TUI.
- **Negativa no hook de permissão, não no `execute.before`**: o hook de permissão é o que a fase 0 viu barrar a ferramenta, e a documentação não diz como barrar pelo `execute.before`. Alternativa: lançar erro no `execute.before`, sem efeito confirmado.
- **Falha do script conta como "sem negativa"**: é o comportamento dos próprios scripts no Claude Code quando falta o `jq` (§9 do plano), e assim um script quebrado não trava toda chamada de shell do agente. Alternativa: negar quando o script falha, o que pararia o agente numa máquina sem `jq`.
- **Limite de 256 entradas no `Map`**: impede que chamadas que nunca chegam à permissão façam a memória crescer sem fim. O número fica acima de qualquer rajada de ferramentas paralelas de uma sessão. Alternativa: sem limite.
- **Timeout de 10 s por script**: os dois scripts são `bash` com `jq` e `git` locais, e terminam em menos de 1 s nos testes atuais. Alternativa: sem timeout, o que deixaria um script travado segurar o agente.

**Fontes da documentação:**
- OpenCode 2.3.0, documentação da v2: `https://opencode.ai/docs/build/plugins/server/` (`ctx.permission.hook`, `ctx.tool.hook`, `ctx.location.directory`, `ctx.options`) e `https://opencode.ai/docs/permissions/` (o `deny` vence quando a operação toca vários recursos).
- Os campos `event.source.id`, `event.input.command`, `event.resources` e a ordem `tool.execute.before` → `permission.evaluate` foram confirmados na fase 0 (#149). Não constam da documentação.
- **Não verificados:**
  - os campos do corpo de `POST /api/session/<id>/permission`. A #149 usou essa API com `action` e `resources`;
  - o formato de `event.resources` na ação `edit` (o plano supõe que traz o caminho do arquivo).
- Node (`node:child_process`, `spawnSync` com `input`, `encoding` e `timeout`): API estável do runtime do OpenCode, não verificada contra uma versão específica.
- Context7: não consultado. A documentação indexada é da v1.
- gh: a spec não cita flag nem campo do `gh`.

**ADR:** nenhum. A ponte e o uso dos scripts estão no plano mergeado (§4.5).

## Testes
Não há teste automatizado nesta issue: o `test-adapter.sh` é da #161.
- **CA1 a CA5:** num `opencode serve` local, com um repositório git temporário que tem o `opencode.jsonc` do projeto e o `.fabrica/producao.txt` de teste, só pela API de permissão, sem acionar o modelo.
- **CA6 e CA7:** `opencode run --auto` no mesmo repositório, com o modelo gratuito do gateway, pedindo primeiro o commit simples com a flag e depois a linha encadeada. O implementador anota a contagem de commits antes e depois, a mensagem que o agente recebeu e a linha que o log do plugin mostra.
- **Limpeza:** o repositório temporário é apagado no fim, e nenhum arquivo do `~/.config/opencode` é tocado.
- **CA8 e CA9:** os comandos e os resultados.

## Passos de produção
nenhum

## Riscos e dúvidas
- **O CA7 roda o agente de verdade no host.** O projeto está no modo `sem-sandbox`, e o modelo age num repositório temporário. A fase 0 fez o mesmo teste numa VM do `sbx`. Se você preferir a VM, o CA7 vira verificação sua, pelo `sbx`.
- **Ponte pelo id da chamada:** a fase 0 viu `event.id` igual a `source.id`. Se o id não bater, a reserva avalia os comandos juntos, sem perder nenhum. Um prefixo de variável como `HOME=...` continua no comando a que pertence.
- **O guarda-corpo é por texto,** e um script que escreve no `~/.claude/` por dentro passa.
- **Formato do `edit`:** se o `resources` da ação `edit` não trouxer caminhos absolutos, a parte `edit` do CA3 falha, e o desvio é reportado.
- **PRD:** o PRD lista o OpenCode em "Fora de escopo" (Fase 3). A issue e o plano mergeado tratam de portabilidade das etapas, como a #157, que foi aceita.

## Histórico
- 2026-11-17: criação.
- 2026-11-17: aprovada.
