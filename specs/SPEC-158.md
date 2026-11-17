# SPEC-158: OpenCode: agente fabrica/revisor

**Issue:** #158 · **PRD:** nenhuma (fora das F1 a F9; ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-17

## Contexto
Esta é a fase 2 do `opencode/PLANO-OPENCODE.md` (§4.4), sobre a #149. A fase 1 (#157, PR #167) já registra as skills e os comandos `/fabrica:*` no OpenCode. O preâmbulo do comando também já diz que `fabrica:revisor` é o subagente `fabrica/revisor`, chamado pela ferramenta `subagent`. Esse agente ainda não existe no OpenCode, e por isso o `/fabrica:revisar` cai no fallback da skill, um subagente genérico com o texto do `agents/revisor.md`. O plano é aditivo: o plugin do Claude Code continua como está.

## Objetivo
O adaptador `opencode/server.ts` registra o subagente `fabrica/revisor`, com o prompt lido do `agents/revisor.md` e sem permissão de editar arquivos, e nada fora de `opencode/` muda por causa dele.

## Comportamento esperado
**Registro.** No `setup`, depois das skills e dos comandos, o plugin chama `ctx.agent.transform` e cria o agente com `editor.update("fabrica/revisor", ...)`. O callback lê o `agents/revisor.md` da raiz da fábrica (a mesma raiz da #157: `options.root` ou a pasta pai de `opencode/`), e o transform roda de novo a cada reload.

| Campo | Valor |
|---|---|
| `id` | `fabrica/revisor` |
| `name` | o `name` do frontmatter do `agents/revisor.md` (`revisor`) |
| `description` | o `description` do frontmatter |
| `mode` | `subagent` |
| `hidden` | `false` |
| `system` | o corpo do `agents/revisor.md`, sem o frontmatter |
| `model` | não definido: o subagente herda o modelo da sessão pai |
| `permissions` | as regras abaixo, nesta ordem |

**Permissões.** A documentação da v2 diz que vale a última regra que casa e que, sem nenhuma regra, o resultado é `ask`.

| # | `action` | `resource` | `effect` | Por quê |
|---|---|---|---|---|
| 1 | `*` | `*` | `allow` | a base de todo agente do OpenCode, como no `build` e no `general` |
| 2 | `read` | `*.env` | `ask` | a mesma proteção de `.env` da base |
| 3 | `read` | `*.env.*` | `ask` | idem |
| 4 | `read` | `*.env.example` | `allow` | idem |
| 5 | `edit` | `*` | `deny` | o revisor não altera arquivos (`agents/revisor.md`: "Só lê e executa verificações") |
| 6 | `question` | `*` | `deny` | o revisor não pergunta ao usuário: devolve o parecer à etapa |
| 7 | `subagent` | `*` | `deny` | o revisor não abre outro subagente, como o `general` |

O shell fica liberado pela regra 1, como o `Bash` do revisor do Claude Code (recomendação da triagem).

**Robustez.**

| Situação | O que acontece |
|---|---|
| `agents/revisor.md` ausente, ilegível, sem frontmatter ou sem `description` | o agente não é registrado e um erro é logado com o prefixo `[fabrica]`. Skills e comandos continuam registrados, e o plugin continua `active` |
| `ctx.agent.transform` ausente ou com erro | idem: erro logado, o resto do plugin segue |
| `editor.update` de um ID novo não cria o agente | o `GET /api/agent` não lista `fabrica/revisor`. A implementação para e escala na issue, com o caminho 2 da §4.4 (arquivo gerado) como opção. Ela não gera arquivo por conta própria |

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `GET /api/agent` lista `fabrica/revisor`, com `mode: "subagent"`, a `description` do `agents/revisor.md` e um `system` igual ao corpo do arquivo sem o frontmatter | manual: `opencode serve` local, com o plugin numa entrada `"plugins"` de um `opencode.jsonc` de projeto numa pasta temporária, como na #157. Só chamadas `GET` |
| CA2 | As `permissions` do agente são as 7 regras da tabela, na ordem. A última regra que casa com `edit` é `deny`, e a última que casa com `shell` é `allow` | manual: na mesma sessão do CA1, pelo `GET /api/agent` |
| CA3 | Para uma sessão com o agente `fabrica/revisor`, a avaliação de `action: edit` devolve `deny`, e a de `action: shell` com `git status` devolve `allow` | manual: na mesma sessão do CA1, pelo `POST /api/session/<id>/permission`. Se a API não deixar escolher o agente da sessão ou da avaliação, o CA vira verificação pedida ao usuário pelo TUI (ver Riscos) |
| CA4 | O `system` vem do arquivo: depois de trocar uma frase do `agents/revisor.md` e chamar `POST /api/location/reload`, o `system` do `GET /api/agent` traz a frase nova. O plugin não guarda cópia do texto | manual: na mesma sessão do CA1, e depois `git checkout` do arquivo. A falta de cópia se confere lendo o `opencode/server.ts` |
| CA5 | Com `options.root` apontando para uma cópia da fábrica em que o `agents/revisor.md` não existe, o plugin fica `active`, os 12 comandos e as 12 skills continuam listados, o `fabrica/revisor` não aparece e o log traz o erro com `[fabrica]` | manual: na mesma sessão do CA1, com a cópia numa pasta temporária |
| CA6 | Numa revisão real, o `/fabrica:revisar <nº>` digitado no TUI chama o subagente `fabrica/revisor` e recebe o parecer | depois do merge: o TUI é uma sessão interativa, que os agentes não rodam sem o usuário (mesmo motivo do CA10 da SPEC-157). O usuário pode antecipar o teste no PR, com `opencode` na branch |
| CA7 | `git diff --name-only origin/main...HEAD` mostra só caminhos em `opencode/` e o `specs/SPEC-158.md` | manual: o comando, na branch |
| CA8 | Os testes bash atuais passam: todo `scripts/test-*.sh` da `main`, menos o `test-sandbox-acceptance.sh` | manual: rodar cada script e ver todos sem falha |

## Fora de escopo
- Hooks de proteção (#159), nota de sessão e regras do projeto (#160), `test-adapter.sh` e `opencode/README.md` (#161).
- Gerar um arquivo de agente (caminho 2 da §4.4). Se o caminho 1 falhar, ele vira decisão do usuário (ver Comportamento esperado).
- Restringir o shell do revisor a uma lista de comandos (a lista da §4.4: `make`, `git`, `gh`).
- Mudanças em `agents/`, `skills/`, `hooks/`, `scripts/`, `docs/`, `templates/`, `.claude-plugin/` e nos arquivos de regras. Por isso não há subida de `version` no `plugin.json`.
- Fixar o modelo do revisor.

## Desenho técnico
**Arquivos e módulos:** só `opencode/server.ts`. As funções `parseFrontmatter` e `resolveRoot`, que já existem, são reaproveitadas.

**Dados:** nenhum.

**Interfaces:**
- `loadReviewer(root): { name, description, system } | undefined`: lê `<root>/agents/revisor.md`, separa o frontmatter com `parseFrontmatter` e devolve `undefined`, com erro logado, nos casos da tabela de robustez.
- `REVIEWER_ID = "fabrica/revisor"` e `REVIEWER_PERMISSIONS`, a lista das 7 regras.
- No `setup`, um bloco novo:
  ```ts
  await ctx.agent.transform((editor) => {
    const reviewer = loadReviewer(root)
    if (!reviewer) return
    editor.update(REVIEWER_ID, (agent) => { /* campos da tabela */ })
  })
  ```
  O bloco fica dentro de um `try/catch` que loga o erro e não o propaga.

**Decisões:**
- **Shell liberado e edição negada** (recomendação da triagem): o revisor do Claude Code tem `tools: Read, Grep, Glob, Bash` (`agents/revisor.md`) e roda verificações como os `bash scripts/test-*.sh` do fabrica, que não tem Makefile. Alternativa: a lista da §4.4 (só `make *`, `git *` e `gh *`), que impede o revisor de rodar os testes do próprio fabrica.
- **Corpo lido do `agents/revisor.md` a cada setup e reload, sem cópia** (recomendação da triagem): segue a §4.4 ("o corpo do agente continua num só lugar") e a decisão "sem cache" da SPEC-157. Alternativa: um texto próprio no adaptador, que duplicaria a regra.
- **Registro pelo `ctx.agent.transform` (caminho 1), com o caminho 2 escalonado** (recomendação da triagem): segue o escopo da issue e a §4.4. Alternativa: gerar o arquivo de agente já de saída, o que exige um passo de instalação e escrita em `~/.config/opencode/agents/`.
- **Verificação de "não edita" pela API de permissão, e da revisão real depois do merge** (recomendação da triagem): segue a §8 do plano, sem acionar o modelo. Alternativa: testar uma revisão com modelo pela API, que na #157 fez o modelo padrão responder sozinho.
- **Regras 6 e 7, que negam `question` e `subagent`**: o revisor devolve um parecer e não conversa com o usuário. O `general` do próprio OpenCode nega as duas pelo mesmo motivo. Alternativa: deixar as duas liberadas, o que permite ao revisor parar a etapa com uma pergunta.
- **Sem `model`**: o subagente herda o modelo da sessão pai (documentação da v2), como o revisor do Claude Code, que não fixa modelo. Alternativa: fixar um modelo, que amarra o adaptador a um provedor.
- **ID com `/`**: o plano escolheu `fabrica/revisor`, e o preâmbulo da #157 já usa esse nome. A documentação aceita `/` no ID (`team/reviewer`, vindo de subpasta), mas não diz se a ferramenta `subagent` aceita. O CA6 confere isso depois do merge.

**Fontes da documentação:**
- OpenCode 2.3.0 (`opencode --version`), documentação da v2 lida nesta etapa:
  - `https://opencode.ai/docs/build/plugins/server/`: `ctx.agent.transform`, com o editor `list`, `get`, `default`, `update` e `remove`, sem `add`.
  - `https://opencode.ai/docs/agents/`: campos `id`, `name`, `system`, `description`, `mode`, `hidden` e `permissions`, e o subagente que herda o modelo da sessão pai.
  - `https://opencode.ai/docs/permissions/`: o formato `{action, resource, effect}`, "the last matching rule wins" e o `ask` quando nenhuma regra casa.
- Formato real de `GET /api/agent`, conferido nesta etapa num `opencode serve` local, só com `GET`: os agentes `build`, `general` e `plan` trazem `permissions` nesse formato, com a base `*`/`*`/`allow` e as regras de `.env`. O `plan` nega `edit`.
- **Não verificados na documentação:**
  - que o `update` de um ID novo cria o agente (o plano diz que sim, pelo código interno);
  - os campos do corpo de `POST /api/session/<id>/permission`;
  - se a ferramenta `subagent` aceita um ID com `/`.
- Context7: não consultado. A documentação indexada é da v1 (§0 do plano).
- gh: a spec não cita flag nem campo do `gh`.

**ADR:** nenhum. A escolha de adaptar o OpenCode já está no plano mergeado.

## Testes
Não há teste automatizado nesta issue: o `test-adapter.sh` é da #161. A verificação é manual, num `opencode serve` local, no método da #157: uma pasta temporária com o `opencode.jsonc` do projeto, Basic auth com o usuário `opencode` e a senha do log, e `?directory=<pasta>` em cada chamada.
- **Sem acionar o modelo:** o implementador usa só `GET`, `POST /api/location/reload` e `POST /api/session/<id>/permission`. Ele não executa comandos `/fabrica:*` e para o servidor pelo PID no fim.
- **CA1, CA2 e CA5:** a saída do `GET /api/agent`, do `GET /api/command` e do `GET /api/skill`, e o trecho do log.
- **CA3:** a requisição e a resposta da avaliação de permissão.
- **CA4:** o `system` antes e depois da troca da frase.
- **CA7 e CA8:** o `git diff --name-only` e a lista dos testes bash, com o resultado.

## Passos de produção
nenhum

## Riscos e dúvidas
- **O `update` pode não criar o agente.** A documentação não diz que um `update` de ID novo cria o agente. Se ele não criar, a implementação escala com o caminho 2 da §4.4, que gera o arquivo `~/.config/opencode/agents/fabrica/revisor.md`.
- **O CA3 depende de a API escolher o agente.** O corpo do `POST /api/session/<id>/permission` não está documentado. Se não der para avaliar a permissão como o `fabrica/revisor`, as regras ainda ficam provadas pelo CA2, e o teste de edição negada vai para o usuário, pelo TUI.
- **O shell pode escrever.** Com o shell liberado, o revisor ainda consegue escrever num arquivo pelo shell (por exemplo, com `>`), como o `Bash` do revisor no Claude Code. A regra 5 nega só a ferramenta de edição, e o "só lê" continua dependendo também do prompt.
- **PRD:** o PRD lista o OpenCode em "Fora de escopo" (Fase 3). A issue e o plano mergeado tratam de portabilidade das etapas, como a #157, que foi aceita.

## Histórico
- 2026-11-17: criação.
