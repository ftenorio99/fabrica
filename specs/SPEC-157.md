# SPEC-157: OpenCode: adaptador server.ts com as skills e os comandos /fabrica:*

**Issue:** #157 · **PRD:** nenhuma (fora das F1 a F9; ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-17

## Contexto
Esta é a fase 1 do `opencode/PLANO-OPENCODE.md` (§4.1 a §4.3, §7), sobre a #149. O OpenCode 2.3.0 não lê o `plugin.json` nem as convenções do Claude Code, então as 12 etapas da fábrica não existem nele. As APIs de plugin em que o adaptador se apoia foram verificadas na #149, incluindo a fase 0 com modelo real (§0 do plano). O plano é aditivo: o plugin do Claude Code continua como está, e o adaptador lê os arquivos existentes em tempo de execução, sem copiá-los.

## Objetivo
Um plugin de servidor do OpenCode (`opencode/server.ts`) registra as 12 skills da fábrica e um comando `/fabrica:<etapa>` por skill, com o corpo lido do `SKILL.md` a cada reload, e nada fora de `opencode/` muda por causa dele.

## Comportamento esperado
**Carga.** No `setup`, o plugin descobre a raiz da fábrica, lê `skills/*/SKILL.md`, e registra para cada skill uma skill (`ctx.skill.transform`) e um comando (`ctx.command.transform`). A raiz é `ctx.options.root`, quando a configuração o traz, ou a pasta pai da pasta de `server.ts`. O plugin se chama `fabrica`.

**Skill registrada.**

| Campo | Valor |
|---|---|
| ID | `fabrica-<pasta>` (ex.: `fabrica-triagem`) |
| `name` | o `name` do frontmatter |
| `description` | o `description` do frontmatter |
| `autoinvoke` | `false` quando o frontmatter tem `disable-model-invocation: true`; `true` nas outras (`status` e `metricas`) |
| `path` | o caminho absoluto do `SKILL.md` real |
| `content` | o corpo do `SKILL.md`, sem o frontmatter |

**Comando registrado.** `fabrica:<pasta>`, com a `description` do frontmatter, precedida do `argument-hint` quando ele existir. Ao ser executado com `{sessionID, prompt, delivery}`:
1. lê o `SKILL.md` de novo (sem cache entre execuções);
2. troca cada `$ARGUMENTS` do corpo pelo `prompt.text` (sem espaços nas pontas), como texto literal; sem argumento, a troca é por texto vazio;
3. monta `preâmbulo + corpo` e o envia com `ctx.session.prompt({ ...prompt, sessionID, text, delivery })`, na mesma sessão.

**Preâmbulo.** O texto da §4.3 do plano, igual para todas as etapas, com `<raiz>/skills/<pasta>` no lugar do diretório base da skill:
- começa com `<!-- fabrica:opencode -->`;
- diz que `AskUserQuestion` é a ferramenta `question`;
- diz que `fabrica:revisor` é o subagente `fabrica/revisor`, chamado pela ferramenta `subagent`, com o fallback que a própria skill descreve se ele não estiver disponível;
- manda não executar os passos de statusline, `~/.claude/settings.json` e `setup-statusline.sh`, que são do Claude Code: avisar que não se aplicam e seguir.

**Robustez.**

| Situação | O que acontece |
|---|---|
| `SKILL.md` sem frontmatter, sem `name` ou sem `description` | a skill e o comando dela são ignorados; um erro é logado; as outras 11 carregam |
| pasta de `skills/` sem `SKILL.md` | ignorada, sem erro |
| raiz sem pasta `skills/` | nenhuma skill nem comando é registrado; um erro é logado; o plugin continua ativo |
| `SKILL.md` apagado ou ilegível depois do registro, na hora de executar o comando | o comando devolve o erro à sessão, sem derrubar o servidor |
| argumento com `$&`, `$1`, `$$` ou `$ARGUMENTS` | entra no texto como veio, sem interpretação |

O plugin nunca impede o OpenCode de iniciar, não escreve em disco e não usa a rede.

**Instalação.** Pela entrada de pasta em `"plugins"` do `opencode.jsonc` (global: `~/.config/opencode/opencode.jsonc`), apontando para `<clone>/opencode`. Não há `install.sh` nem `package.json`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `GET /api/plugin` lista o plugin `fabrica` com `status: "active"`, carregado de uma entrada de pasta em `"plugins"` | manual — `opencode serve` numa VM do `sbx`, como na #149, com a entrada `"plugins": ["<clone>/opencode"]` no `opencode.jsonc` e `curl` na API |
| CA2 | `GET /api/command` lista 12 comandos, `fabrica:avancar`, `fabrica:backlog`, `fabrica:implementar`, `fabrica:licao`, `fabrica:metricas`, `fabrica:prd`, `fabrica:retro`, `fabrica:revisar`, `fabrica:setup`, `fabrica:spec`, `fabrica:status` e `fabrica:triagem`. Cada um traz a `description` da skill | manual — mesma sessão do CA1 |
| CA3 | `GET /api/skill` lista as 12 skills com ID `fabrica-<pasta>`; `autoinvoke` é `false` nas 10 com `disable-model-invocation: true` e `true` em `status` e `metricas` | manual — mesma sessão do CA1 |
| CA4 | Executar `fabrica:status` com o texto `kairo` (`POST /api/session/<id>/command`) envia à sessão uma mensagem que começa com `<!-- fabrica:opencode -->`, traz o corpo de `skills/status/SKILL.md` e tem `kairo` no lugar de todo `$ARGUMENTS`. A mensagem não contém `$ARGUMENTS` nem o frontmatter | manual — mesma sessão do CA1, lendo a mensagem enviada à sessão pela API |
| CA5 | Executar `fabrica:status` sem argumento deixa o lugar de `$ARGUMENTS` vazio, sem a palavra `undefined` nem o texto `$ARGUMENTS` | manual — mesma sessão do CA1 |
| CA6 | Executar um comando com o texto `a$&b $1 $$` põe esse texto, igual, no lugar de `$ARGUMENTS` | manual — mesma sessão do CA1 |
| CA7 | O corpo vem do arquivo a cada execução e a cada reload: trocar uma frase do `skills/status/SKILL.md` e recarregar muda a mensagem do CA4 sem tocar em `opencode/`. O plugin não tem cópia do texto das skills | manual — mesma sessão do CA1; depois, `git checkout` do arquivo. A ausência de cópia: leitura de `opencode/server.ts` |
| CA8 | Com `"options": {"root": "<cópia>"}` na entrada do plugin, apontando para uma cópia da fábrica em que uma skill tem o frontmatter quebrado (sem `description`), a API lista 11 skills e 11 comandos, o plugin segue `active` e o log traz o erro dessa skill | manual — mesma sessão do CA1, com a cópia em pasta temporária |
| CA9 | Sem `options.root`, a raiz é a pasta pai da pasta de `server.ts`: com o plugin carregado do clone, os caminhos `path` das skills começam por `<clone>/skills/` | manual — mesma sessão do CA1, pelo campo `path` do `GET /api/skill` |
| CA10 | `/fabrica:status` digitado no TUI roda a skill, e `/fabrica:status kairo` passa o argumento. Se o TUI recusar o nome com `:`, o separador muda para `/` (uma constante em `server.ts`) | depois do merge — o TUI é uma sessão interativa, que os agentes não rodam sem o usuário. O usuário pode antecipar o teste no PR, com `opencode` na branch |
| CA11 | `git diff --name-only origin/main...HEAD` mostra só caminhos em `opencode/` e `specs/SPEC-157.md` (a spec da própria issue, que o fluxo leva na mesma branch). Nenhum arquivo de `skills/`, `agents/`, `hooks/`, `githooks/`, `scripts/`, `templates/`, `docs/` ou `.claude-plugin/` muda | manual — o comando, na branch |
| CA12 | Os testes bash atuais passam: todo `scripts/test-*.sh` que existe na `main`, menos o `test-sandbox-acceptance.sh` (`bash scripts/test-protect-main.sh`, `test-protect-production.sh` etc.) | manual — rodar cada `scripts/test-*.sh` (menos o `test-sandbox-acceptance.sh`, que só roda na VM) e ver todos sem falha |

## Fora de escopo
- Agente `fabrica/revisor` (#158), hooks de proteção da main, de produção e do `~/.claude` (#159), nota de sessão e regras do projeto (#160), `test-adapter.sh` e `opencode/README.md` (#161).
- Qualquer mudança em `skills/`, `agents/`, `hooks/`, `githooks/`, `scripts/`, `templates/`, `docs/`, `.claude-plugin/` e `CLAUDE.md`. Por isso não há subida de `version` no `plugin.json` nem entrada no manual: o plugin do Claude Code não muda de comportamento.
- Medição de tokens no OpenCode, statusline e checklist do `sbx` para o agente `opencode`.
- Publicar o adaptador como pacote npm, e a instalação por projeto em `.opencode/plugins/`.
- Rodar etapa de agente por `opencode run "/fabrica:..."`, que não executa comandos (fase 0).

## Desenho técnico
**Arquivos e módulos:** um arquivo novo, `opencode/server.ts`, sem `package.json` e sem dependências além de `@opencode/plugin` e dos módulos `node:` (`node:fs`, `node:path`, `node:url`). Comentários em português, nomes em inglês.

**Interfaces:**
- `export default Plugin.define({ id: "fabrica", async setup(ctx) { ... } })`.
- `parseFrontmatter(text): { fields: Record<string, string>, body: string } | undefined`: lê o bloco entre as duas primeiras linhas `---`; cada linha é `chave: valor`, dividida no primeiro `:`; aspas simples ou duplas em volta do valor são tiradas. O frontmatter das 12 skills é plano, de uma linha por campo. Devolve `undefined` sem o bloco.
- `loadSkills(root): SkillSource[]`, com `{ folder, name, description, argumentHint?, autoinvoke, path }`, ignorando e logando as skills inválidas.
- `buildText(root, folder, args): string`: lê o `SKILL.md`, tira o frontmatter, troca `$ARGUMENTS` por `args` com `split("$ARGUMENTS").join(args)` e concatena o preâmbulo.
- `COMMAND_SEPARATOR = ":"`: a única constante que muda se o TUI recusar o `:`.

**Decisões:**
- **Nome do comando `/fabrica:<etapa>`, com `/fabrica/<etapa>` de reserva** (recomendação da triagem) — a API aceita o `:`, e o teste no TUI decide. Alternativa: começar por `/fabrica/<etapa>`.
- **Instalação global em `~/.config/opencode/opencode.jsonc`** (recomendação da triagem) — tem o mesmo alcance do plugin do Claude Code. Alternativa: `.opencode/plugins/` por projeto.
- **README só em `opencode/README.md`** (recomendação da triagem) — esta issue só decide, e o arquivo nasce na #161, sem editar o `README.md` da raiz. Alternativa: seção no `README.md` da raiz.
- **Skills registradas por `ctx.skill.transform` com ID `fabrica-<pasta>`** (recomendação da triagem) — o prefixo evita colisão com skills do usuário. Alternativa: apontar a chave `skills` da configuração para `<raiz>/skills`, que deixaria o ID sem prefixo.
- **Frontmatter lido por um parser próprio de poucas linhas**, em vez de uma biblioteca YAML — o plugin não tem `package.json` nem `node_modules`, e os campos são chaves planas de uma linha. Alternativa descartada: dependência de YAML, que exigiria `package.json` e quebraria o contrato do plano.
- **`$ARGUMENTS` trocado por `split/join`** — o `String.replace` com string interpreta `$&`, `$1` e `$$` no argumento (CA6). Alternativa descartada: `replace` com função, que serve igual, mas o `split/join` dispensa a explicação.
- **O `argument-hint` entra na `description` do comando**, antes do texto — a `description` é o único texto que o comando oferece para dizer como usá-lo. Não é critério de aceite: o formato é livre.
- **Sem cache do corpo** — o plano pede que a mudança na skill valha sem sincronizar nada. Alternativa descartada: ler uma vez no `setup`, que exigiria reload a cada edição.

**Fontes da documentação:**
- OpenCode 2.3.0 (`opencode --version`) — documentação da v2 em `https://opencode.ai/docs/build/plugins/server/` e `https://opencode.ai/docs/plugins`, lidas nesta etapa: confirmam `ctx.skill.transform` (editor com `add`, `update`, `list`, `get`, `remove`; `Skill.ID.make`, `Skill.Name.make`), `ctx.command.transform` (`name`, `description?`, `execute({ sessionID, prompt, delivery })`), `ctx.session.prompt`, `ctx.options` e a pasta local em `"plugins"` com `server.ts` na raiz. Não confirmam: os campos completos de `Skill.Info`, o formato do nome do comando e o `$ARGUMENTS`. Esses três vêm da verificação da #149 (§0 do plano) e do código da issue, e ficam marcados como **não verificados na documentação**.
- Context7 — não consultado: a documentação indexada descreve a v1 do OpenCode (§0 do plano), que a v2 não traduz.
- gh — a spec não cita flag nem campo do `gh`.

**ADR:** nenhum. A escolha de adaptar o OpenCode já está no plano mergeado; as decisões acima valem só para esta issue.

## Testes
Não há teste automatizado nesta issue: o `test-adapter.sh` é da #161. A verificação é manual, numa VM do `sbx` com `opencode serve` e `curl`, no método da #149 (CA1 a CA9), mais o TUI (CA10, depois do merge) e as provas do contrato (CA11 e CA12). O que o implementador roda e anota no PR: a saída dos três `GET`, a mensagem do CA4, a do CA6, o `git diff --name-only` e a lista dos testes bash com o resultado.

## Passos de produção
nenhum

## Riscos e dúvidas
- **PRD:** o PRD lista "OpenCode" em "Fora de escopo" (Fase 3, roteamento entre modelos). A issue e o plano mergeado tratam de portabilidade das etapas, e o usuário os abriu e aprovou; esta spec segue a issue. Fica aqui para você confirmar ao aprovar.
- **Wording da issue:** a issue diz que `git diff --name-only main` só mostra `opencode/`. A branch leva também `specs/SPEC-157.md`, como toda issue da fábrica, e o CA11 o admite.
- **CA10 só depois do merge:** se o TUI recusar o `:`, o comando fica inutilizável até um PR de uma linha (a constante). O usuário pode antecipar o teste no PR.
- **`prompt.text`:** a #149 confirma que ele traz os argumentos, mas não que vem limpo de espaços ou do nome do comando. O CA4 e o CA5 pegam as duas coisas.
- **API V2 pode mudar.** O adaptador é pequeno e isolado, e o `test-adapter.sh` da #161 acusa a quebra.

## Histórico
- 2026-11-17: criação.
- 2026-11-17: aprovada.
