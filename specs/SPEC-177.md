# SPEC-177: fix: registra o subagente revisor convertido no Antigravity para o revisar poder invocá-lo

**Issue:** #177 · **PRD:** nenhuma (suporte ao Antigravity vem do estudo #149 e dos testes da #162) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-18

## Contexto
A #162 mostrou que, depois do `agy plugin install`, o `agy` 1.5.10 reporta o agente `revisor` como instalado, mas não o registra: `agy agents` vem vazio, `--agent revisor` dá `unknown agent` e `invoke_subagent` dá `not found or not allowed`. O `/fabrica:revisar` só funciona no `agy` pelo fallback do subagente genérico (`define_subagent`), que não restringe ferramentas.

**Causa (investigada nesta spec, com o `agy` 1.5.10 local):** o carregador de agentes do `agy` exige `tools` como lista YAML. A linha `tools: Read, Grep, Glob, Bash` de `agents/revisor.md` é uma string, e o carregador pula o agente sem avisar na instalação. Reprodução: uma cópia de `agents/revisor.md` num plugin mínimo do `agy` (`.antigravity-plugin/plugin.json` + `agents/revisor.md`) dá, em `agy plugin validate . --strict`:

```text
✗ agents/revisor.md: the frontmatter isn't valid YAML: failed to unmarshal frontmatter YAML: yaml: unmarshal errors:
  line 3: cannot unmarshal !!str `Read, G...` into []string. The loader skips this agent
  skills 0 · agents 0 · ...
```

Com `tools` em lista (`[Read, Grep, Glob, Bash]`), a mesma validação passa com `agents 1`. Além do formato, o `agy` usa nomes de ferramentas próprios: o guia de migração embutido no binário (skill de migrar de Claude Code) mapeia `Read`/`Glob`/`Grep` para `read_file`, `Bash` para `run_command` e `manage_task`, e pede `subagent: true` e `mainAgent: false` para um subagente. Um `tools` só com nomes do Claude Code deixaria o revisor sem ferramentas no `agy`.

## Objetivo
O `revisor` instalado pelo `agy plugin install` fica registrado e invocável por `invoke_subagent` no `agy`, com só ferramentas de leitura e shell, e o `fabrica:revisor` do Claude Code e o `fabrica/revisor` do OpenCode seguem iguais.

## Comportamento esperado
- O frontmatter de `agents/revisor.md` passa a ser:

  ```yaml
  ---
  name: revisor
  description: <sem mudança>
  tools: [Read, Grep, Glob, Bash, read_file, run_command, manage_task]
  subagent: true
  mainAgent: false
  ---
  ```

  O corpo do agente não muda.
- **Claude Code:** aceita `tools` como string ou lista YAML (doc de subagentes) e ignora entradas que não resolvem para uma ferramenta, desde que alguma resolva. O `fabrica:revisor` continua com `Read`, `Grep`, `Glob` e `Bash`. Os campos `subagent` e `mainAgent` não existem no Claude Code e são ignorados.
- **Antigravity:** o carregador lê a lista, usa `read_file`, `run_command` e `manage_task` e registra o agente como subagente. O `revisar` chama o revisor com `invoke_subagent`; o fallback do `define_subagent` fica só para quando o agente não estiver disponível.
- **OpenCode:** o `opencode/server.ts` lê só `name` e `description` do frontmatter (`parseFrontmatter`, linha a linha); a linha de `tools` em lista de uma linha não muda nada.
- **Sem `edit_file` nem `write_file`:** no `agy`, o revisor deixa de ter as ferramentas de editar e criar arquivos. O shell (`run_command`) continua liberado, como o `Bash` no Claude Code, e a regra de não alterar arquivos continua vindo das instruções.
- **`--agent revisor`:** com `mainAgent: false`, o revisor não é agente principal de sessão; `agy --agent revisor` continua recusado. A issue aceita `--agent` **ou** `invoke_subagent`, e o `revisar` usa o segundo.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `agents/revisor.md` tem `tools: [Read, Grep, Glob, Bash, read_file, run_command, manage_task]`, `subagent: true` e `mainAgent: false` no frontmatter, e o corpo é igual ao da `main` (`git diff origin/main -- agents/revisor.md` só mostra linhas do frontmatter). | unitário: `bash scripts/test-revisor-agent.sh` confere as três linhas e que o corpo depois do segundo `---` é idêntico ao de `git show origin/main:agents/revisor.md` |
| CA2 | Num plugin mínimo do `agy` montado num diretório temporário (`.antigravity-plugin/plugin.json` + cópia de `agents/revisor.md`), `agy plugin validate <dir> --strict` passa, com `agents 1` na contagem. Com o `tools` antigo em string, a mesma montagem falha com `The loader skips this agent` (o teste prova que detecta a regressão). Sem `agy` no `PATH`, o caso sai como `pulado (agy ausente)` e não conta como falha. | unitário: `bash scripts/test-revisor-agent.sh` |
| CA3 | `claude plugin validate <clone>` passa e lista `agents: fabrica:revisor`, sem aviso sobre `agents/revisor.md`. Sem `claude` no `PATH`, o caso sai como `pulado (claude ausente)`. | unitário: `bash scripts/test-revisor-agent.sh` |
| CA4 | No Claude Code, o `fabrica:revisor` continua disponível e com as mesmas ferramentas: numa sessão `claude --plugin-dir <clone>` na branch, o Agent tool lista `fabrica:revisor`, e uma chamada a ele que pede para listar as ferramentas disponíveis devolve `Read`, `Grep`, `Glob` e `Bash`, sem `Edit` nem `Write`. | manual: `claude --plugin-dir <clone>` na branch, com o comando e a saída no PR |
| CA5 | No `agy` 1.5.10 autenticado, numa VM do `sbx` (mesmo cenário da #162), depois de `agy plugin install <clone na branch>`: `agy plugin list` mostra a fábrica, o `/agents` (ou `agy agents`) lista o revisor, e numa sessão `-p` o `invoke_subagent` com o nome listado devolve resposta do revisor, sem `not found or not allowed`. | manual: VM do `sbx` com `agy` autenticado, com os comandos e as saídas no PR |
| CA6 | No mesmo cenário do CA5, o revisor invocado não tem `edit_file` nem `write_file`: pedido para editar um arquivo, ele recusa ou não tem a ferramenta, e `git status` fica limpo e a contagem de commits igual antes e depois. | manual: VM do `sbx` com `agy` autenticado, com os comandos e as saídas no PR |
| CA7 | O OpenCode segue registrando o `fabrica/revisor` com o prompt do `agents/revisor.md`: `bash opencode/test-adapter.sh` passa. | manual: dentro da VM do `sbx` com o agente `opencode`, como diz o `AGENTS.md` |
| CA8 | `skills/revisar/SKILL.md` diz que, no Antigravity, o revisor é chamado por `invoke_subagent` com o nome que o `agy` lista, e mantém o fallback do subagente genérico para quando ele não estiver disponível. `docs/guias/antigravity.md` move o revisor de "O que não funciona" para "O que funciona", registra a versão testada (plugin com a `version` nova e `agy` 1.5.10), troca a ressalva de restrição de ferramentas pela do CA6 (sem ferramentas de editar, shell liberado) e diz que `--agent revisor` segue recusado por ser subagente. | manual: leitura do diff dos dois arquivos |

## Fora de escopo
- Tornar o revisor agente principal de sessão (`mainAgent: true`, `agy --agent revisor`): o `revisar` não usa esse caminho.
- Um shell somente leitura no `agy`: o `agy` não oferece essa opção, e o shell continua liberado como no Claude Code.
- O aviso do `SessionStart` no `agy` (#178).
- Mudar o corpo do revisor ou o comportamento do `revisar` no Claude Code.
- Converter outros agentes ou criar um arquivo de agente separado para o `agy`.

## Desenho técnico
**Arquivos e módulos:**
- `agents/revisor.md`: só o frontmatter (CA1).
- `scripts/test-revisor-agent.sh` (novo): os casos dos CA1 a CA3. Monta o plugin mínimo do `agy` com `mktemp -d`, usa só `agy plugin validate` e `claude plugin validate` (nenhum dos dois instala nada nem mexe em `~/.gemini` ou `~/.claude`) e apaga o temporário no fim. Segue o formato dos outros `scripts/test-*.sh` (contagem de ok e falhas, código de saída diferente de 0 com falha).
- `skills/revisar/SKILL.md`: o parágrafo "Chame o subagente `revisor` deste plugin" ganha o caminho do Antigravity (CA8).
- `docs/guias/antigravity.md`: CA8.
- `AGENTS.md`: a seção `scripts/` cita `bash scripts/test-revisor-agent.sh`.
- `.claude-plugin/plugin.json`: sobe a `version` (muda comportamento no `agy`).

**Dados:** nenhum.

**Interfaces:** o frontmatter de `agents/revisor.md`, lido por três carregadores: Claude Code, `agy` e `opencode/server.ts`.

**Decisões:**
- Um único `agents/revisor.md` com `tools` em lista que junta os nomes do Claude Code e os do `agy` — o Claude Code ignora as entradas que não resolvem e o `agy` faz o mesmo papel com os nomes dele, sem duplicar o prompt. Alternativa descartada: um segundo arquivo de agente só para o `agy`, declarado num `agents.json` na raiz, que duplicaria o corpo do revisor e exigiria um teste de sincronia.
- `subagent: true` e `mainAgent: false`, como manda o guia de migração do próprio `agy` — o revisor é chamado pelo `revisar`, não como agente da sessão. Alternativa descartada: omitir os dois campos e deixar o padrão do `agy`, que não está documentado na ajuda e pode expor o revisor como agente principal.
- `read_file`, `run_command` e `manage_task`, sem `edit_file` e `write_file` — é o mapeamento do guia de migração para `Read`, `Grep`, `Glob` e `Bash`, e dá ao revisor no `agy` uma restrição de ferramentas que o fallback não dava. Alternativa descartada: omitir `tools`, que no `agy` dá só um conjunto pequeno de leitura sem shell, e o revisor precisa rodar `make test` e `git diff`.
- Verificação estática pelo `agy plugin validate` num plugin mínimo, não por `agy plugin install` — o `validate` não precisa de login nem altera a config do usuário, e foi ele que mostrou a causa. A instalação de verdade fica para o CA5, na VM do `sbx`.

**Fontes da documentação:**
- Antigravity CLI (`agy`) 1.5.10 — doc local: `agy --help`, `agy plugin --help`, `agy agents --help`, `agy changelog` (entradas sobre agentes em Markdown, `agents.json` e `agy plugin validate`), saída de `agy plugin validate --strict` e o guia de migração de Claude Code embutido no binário (seção "`agents/<name>.md` (Claude Code subagents)"). Sem Context7 para o `agy`.
- Claude Code 2.1.327 — Context7 `/websites/code_claude` (sub-agents, "Frontmatter reference": `tools` aceita string separada por vírgula ou lista YAML) e `claude plugin validate`. Versão não confirmada na doc do Context7.
- gh: nenhum comando do `gh` no desenho técnico.

**ADR:** nenhum.

## Testes
- `bash scripts/test-revisor-agent.sh`: CA1 (frontmatter e corpo), CA2 (validação do `agy` com o arquivo novo e regressão com o `tools` antigo), CA3 (validação do Claude Code). Os casos do `agy` e do `claude` saem como pulados quando o binário falta.
- Os testes existentes seguem passando, em especial `bash scripts/test-protect-main.sh` (nada muda nos hooks).
- Manuais: CA4 (`claude --plugin-dir`), CA5 e CA6 (VM do `sbx` com `agy` autenticado), CA7 (`bash opencode/test-adapter.sh` na VM com `opencode`), CA8 (leitura).

## Passos de produção
nenhum

## Riscos e dúvidas
- **Nomes do Claude Code no `agy`:** o `agy plugin validate` aceita `tools: [Read, Grep, Glob, Bash]`, mas não confere nomes de ferramenta. Se, no CA5, o `agy` recusar o agente por causa de `Read`, `Grep`, `Glob` ou `Bash` (o binário tem a mensagem `unknown tool name`), o desenho não serve: a implementação para e comenta na issue, e a spec volta para trocar a decisão pela alternativa do arquivo separado.
- **Nomes do `agy` no Claude Code:** a doc diz que o Claude Code falha só quando nenhuma entrada resolve. Se o CA4 mostrar erro ou aviso por `read_file`, `run_command` ou `manage_task`, vale o mesmo caminho do item anterior.
- **Nome do agente no `agy`:** agentes de plugin podem aparecer com o prefixo do plugin (ex.: `fabrica:revisor`). Por isso o `revisar` usa o nome que o `agy` lista, e o CA5 registra qual é.
- **CA5 e CA6 dependem do `agy` autenticado na VM do `sbx`.** Se a etapa não conseguir rodá-los, o `revisar` pede a verificação ao usuário.

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
