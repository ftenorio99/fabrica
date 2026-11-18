# SPEC-177: fix: registra o subagente revisor convertido no Antigravity para o revisar poder invocá-lo

**Issue:** #177 · **PRD:** nenhuma (suporte ao Antigravity vem do estudo #149 e dos testes da #162) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-18

## Contexto
A #162 mostrou que, depois do `agy plugin install`, o `agy` 1.5.10 reporta o agente `revisor` como instalado, mas não o registra: `agy agents` vem vazio, `--agent revisor` dá `unknown agent` e `invoke_subagent` dá `not found or not allowed`. O `/fabrica:revisar` só funciona no `agy` pelo fallback do subagente genérico (`define_subagent`), que não restringe ferramentas.

**Causa:** o carregador de agentes do `agy` exige `tools` como lista YAML, e a linha `tools: Read, Grep, Glob, Bash` de `agents/revisor.md` é uma string: o `agy` pula o agente sem avisar (`agy plugin validate . --strict` mostra `The loader skips this agent`). Além do formato, o `agy` usa nomes de ferramenta próprios (`read_file`, `run_command`, `manage_task`).

**O que a primeira implementação mostrou (escalonamento de 2026-11-18):** a decisão desta spec, de um único `agents/revisor.md` com uma lista de `tools` que junta os nomes dos dois CLIs, não serve. Com `tools: [Read, Grep, Glob, Bash, read_file, run_command, manage_task]`, o `agy` registra o agente, mas o `invoke_subagent` falha com `tool "Read" not found in registry` (o mesmo para `Grep`, `Glob` e `Bash`). Com só os nomes do `agy`, o Claude Code recusa o agente: `would be spawned with zero tools`. Nenhuma lista única serve aos dois CLIs. O `agy plugin validate` não confere nomes de ferramenta, então só a execução real prova o resultado.

## Objetivo
O `revisor` instalado pelo `agy plugin install` fica registrado e invocável por `invoke_subagent` no `agy`, com só ferramentas de leitura e shell, e o `fabrica:revisor` do Claude Code e o `fabrica/revisor` do OpenCode seguem exatamente como na `main`.

## Comportamento esperado
- **Dois arquivos de agente, um corpo:**
  - `agents/revisor.md` volta ao frontmatter da `main` (`tools: Read, Grep, Glob, Bash`, sem `subagent` nem `mainAgent`). É o arquivo do Claude Code e do OpenCode.
  - `agy-agents/revisor.md` (novo) é o arquivo do `agy`: o mesmo `name`, a mesma `description` e o mesmo corpo, com o frontmatter `tools: [read_file, run_command, manage_task]`, `subagent: true` e `mainAgent: false`. O Claude Code só lê `agents/`, então esse arquivo não aparece nele.
  - `agents.json` (novo), na raiz do plugin: `{"entries":[{"path":"agy-agents/revisor.md"}]}`. Num plugin mínimo, `agy plugin validate --strict` com esse arquivo passa, com `agents 1`. Quando o `agents/revisor.md` tem o mesmo nome, o `agy` o ignora e fica com o do `agents.json` (`skipped: agy-agents/revisor.md already defines an agent named "revisor"`).
- **Sem duplicar o texto à mão:** os dois arquivos têm o mesmo corpo, e um teste confere que o corpo depois do segundo `---` é idêntico nos dois.
- **Claude Code:** não muda. O `fabrica:revisor` tem as mesmas ferramentas do da `main`.
- **Antigravity:** o `revisar` chama o revisor com `invoke_subagent`, com o nome que o `agy` lista. O fallback do `define_subagent` fica só para quando o agente não estiver disponível.
- **OpenCode:** o `opencode/server.ts` lê só `agents/revisor.md`, que volta ao da `main`. Nada muda.
- **Sem `edit_file` nem `write_file`:** no `agy`, o revisor não tem as ferramentas de editar e criar arquivos. O shell (`run_command`) continua liberado, como o `Bash` no Claude Code, e a regra de não alterar arquivos vem das instruções.
- **`--agent revisor`:** com `mainAgent: false`, o revisor não é agente principal de sessão, e `agy --agent revisor` continua recusado. O `revisar` usa o `invoke_subagent`.
- **Primeiro passo da implementação:** confirmar que o `agy plugin install` de um plugin do Claude Code carrega o `agents.json` da raiz e registra o agente (CA5), com o `invoke_subagent` real na VM do `sbx`, não só com o `agy plugin validate`. Se o `agy` não carregar, a implementação para e comenta na issue, e o caminho passa a ser documentar o limite e manter o fallback do `revisar` (agentes de `agents/` com `tools` string continuam pulados).

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `agents/revisor.md` é igual ao da `main` (`git diff origin/main -- agents/revisor.md` vazio). `agy-agents/revisor.md` tem `tools: [read_file, run_command, manage_task]`, `subagent: true` e `mainAgent: false`, e o mesmo `name`, a mesma `description` e o mesmo corpo do `agents/revisor.md`. | unitário: `bash scripts/test-revisor-agent.sh` compara o frontmatter e o corpo depois do segundo `---` dos dois arquivos |
| CA2 | `agents.json` na raiz tem `{"entries":[{"path":"agy-agents/revisor.md"}]}`. Num plugin mínimo do `agy` (diretório temporário com `.antigravity-plugin/plugin.json`, o `agents.json`, o `agy-agents/revisor.md` e o `agents/revisor.md`), `agy plugin validate <dir> --strict` só tem o aviso de que o `agents/revisor.md` foi ignorado, e a contagem é `agents 1`. Sem o `agents.json`, o teste detecta a regressão (o `agents/revisor.md` com `tools` string falha com `The loader skips this agent`). Sem `agy` no `PATH`, o caso sai como `pulado (agy ausente)` e não conta como falha. | unitário: `bash scripts/test-revisor-agent.sh` |
| CA3 | `claude plugin validate <clone>` passa e lista `agents: fabrica:revisor`, sem aviso sobre `agents/revisor.md` nem sobre `agy-agents/`. Sem `claude` no `PATH`, o caso sai como `pulado (claude ausente)`. | unitário: `bash scripts/test-revisor-agent.sh` |
| CA4 | No Claude Code, o `fabrica:revisor` tem as mesmas ferramentas do da `main`: numa sessão `claude --plugin-dir <clone>` na branch, o Agent tool lista `fabrica:revisor`, e uma chamada a ele que pede as ferramentas disponíveis devolve a mesma lista da `main` (no Claude Code 2.1.327: `Read` e `Bash`, sem `Edit` nem `Write`). | manual: `claude --plugin-dir <clone>` na branch e na `main`, com o comando e as duas saídas no PR |
| CA5 | No `agy` 1.5.10 autenticado, numa VM do `sbx` (mesmo cenário da #162), depois de `agy plugin install <clone na branch>`: `agy plugin list` mostra a fábrica com `1 agent`, o `/agents` (ou `agy agents`) lista o revisor, e numa sessão `-p` o `invoke_subagent` com o nome listado devolve resposta do revisor, sem `not found or not allowed` e sem `tool "Read" not found in registry`. O revisor lê um arquivo e roda um comando de shell. | manual: VM do `sbx` com `agy` autenticado, com os comandos e as saídas no PR |
| CA6 | No mesmo cenário do CA5, o revisor invocado não tem `edit_file` nem `write_file`: pedido para editar um arquivo, ele recusa ou não tem a ferramenta, e `git status` fica limpo e a contagem de commits igual antes e depois. | manual: VM do `sbx` com `agy` autenticado, com os comandos e as saídas no PR |
| CA7 | O OpenCode segue registrando o `fabrica/revisor` com o prompt do `agents/revisor.md`: `bash opencode/test-adapter.sh` passa. | manual: dentro da VM do `sbx` com o agente `opencode`, como diz o `AGENTS.md` |
| CA8 | `skills/revisar/SKILL.md` diz que, no Antigravity, o revisor é chamado por `invoke_subagent` com o nome que o `agy` lista, e mantém o fallback do subagente genérico para quando ele não estiver disponível. `docs/guias/antigravity.md` move o revisor de "O que não funciona" para "O que funciona", registra a versão testada (plugin com a `version` nova e `agy` 1.5.10), explica que o `agy` lê o revisor do `agents.json` e o Claude Code, do `agents/`, troca a ressalva de restrição de ferramentas pela do CA6 e diz que `--agent revisor` segue recusado por ser subagente. | manual: leitura do diff dos dois arquivos |

## Fora de escopo
- Tornar o revisor agente principal de sessão (`mainAgent: true`, `agy --agent revisor`): o `revisar` não usa esse caminho.
- Um shell somente leitura no `agy`: o `agy` não oferece essa opção, e o shell continua liberado como no Claude Code.
- O aviso do `SessionStart` no `agy` (#178).
- Mudar o corpo do revisor ou o comportamento do `revisar` no Claude Code.
- Converter outros agentes para o `agy` ou gerar o arquivo do `agy` por script de instalação.
- Gerar o `agy-agents/revisor.md` a partir do `agents/revisor.md` por script: o teste de sincronia do corpo basta.

## Desenho técnico
**Arquivos e módulos:**
- `agents/revisor.md`: volta ao da `main` (desfaz o frontmatter em lista do commit `ce97673`).
- `agy-agents/revisor.md` (novo): o agente do `agy` (CA1).
- `agents.json` (novo): declara o agente do `agy` (CA2).
- `scripts/test-revisor-agent.sh`: ajustado para os casos dos CA1 a CA3 desta spec. Monta o plugin mínimo do `agy` com `mktemp -d`, usa só `agy plugin validate` e `claude plugin validate` (nenhum dos dois instala nada nem mexe em `~/.gemini` ou `~/.claude`) e apaga o temporário no fim. Segue o formato dos outros `scripts/test-*.sh`.
- `skills/revisar/SKILL.md`: o parágrafo "Chame o subagente `revisor` deste plugin" mantém o caminho do Antigravity (CA8).
- `docs/guias/antigravity.md`: CA8, com a explicação dos dois arquivos.
- `AGENTS.md`: a seção `agents/` cita `agy-agents/` e `agents.json`, e a linha do `scripts/test-revisor-agent.sh` passa a falar do corpo igual nos dois arquivos.
- `.claude-plugin/plugin.json`: a `version` já foi subida na branch (0.40.0); suba de novo se a `main` tiver passado dela.

**Dados:** nenhum.

**Interfaces:** `agents/revisor.md` (Claude Code e OpenCode), `agy-agents/revisor.md` mais `agents.json` (`agy`), com o corpo igual nos dois arquivos.

**Decisões:**
- Um arquivo de agente separado para o `agy`, declarado no `agents.json` da raiz (recomendação do escalonamento, que o usuário confirmou) — nenhuma lista única de `tools` serve aos dois CLIs, e o `agents.json` é o mecanismo do próprio `agy` para declarar subagentes de um plugin. Alternativa descartada: um único `agents/revisor.md` com a lista dos dois nomes, que a execução real mostrou que o `agy` recusa.
- Um teste confere que o corpo dos dois arquivos é igual, em vez de gerar um a partir do outro — o custo é um arquivo duplicado, mas sem passo a mais para o usuário. Alternativa descartada: um script de instalação que reescreve o `tools`, que foge do `agy plugin install` puro.
- `subagent: true` e `mainAgent: false`, como manda o guia de migração do próprio `agy` — o revisor é chamado pelo `revisar`, não como agente da sessão. Alternativa descartada: omitir os dois campos, que deixa o padrão do `agy` sem documentação.
- `read_file`, `run_command` e `manage_task`, sem `edit_file` e `write_file` — é o mapeamento do guia de migração do `agy` para `Read`, `Grep`, `Glob` e `Bash`. Alternativa descartada: omitir `tools`, que no `agy` não dá shell, e o revisor precisa rodar testes e `git diff`.
- Verificação estática pelo `agy plugin validate` num plugin mínimo, e a prova de verdade pelo `invoke_subagent` real na VM do `sbx` (CA5) — a lição desta issue: o `validate` não confere nomes de ferramenta.

**Fontes da documentação:**
- Antigravity CLI (`agy`) 1.5.10 — doc local: `agy plugin validate --help` e `agy changelog` (entradas sobre o `agents.json` da raiz, "so a plugin can declare its subagents the same way it declares skills and rules"), mais a saída de `agy plugin validate --strict` em plugins mínimos: o formato `{"entries":[{"path":...}]}` foi confirmado por validação (`agents 1`), e o `agents.json` em array dá erro (`cannot unmarshal array`). O formato do `agents.json` é inferido da validação, não de documentação: versão não confirmada. Sem Context7 para o `agy`.
- Claude Code 2.1.327 — Context7 `/websites/code_claude` (sub-agents, "Frontmatter reference") e `claude plugin validate`. Versão não confirmada na doc do Context7.
- gh: nenhum comando do `gh` no desenho técnico.

**ADR:** nenhum.

## Testes
- `bash scripts/test-revisor-agent.sh`: CA1 (`agents/revisor.md` igual ao da `main`, frontmatter e corpo do `agy-agents/revisor.md`, corpo igual nos dois), CA2 (validação do `agy` num plugin mínimo, com a regressão sem o `agents.json`), CA3 (validação do Claude Code). Os casos do `agy` e do `claude` saem como pulados quando o binário falta.
- Os testes existentes seguem passando, em especial `bash scripts/test-protect-main.sh`.
- Manuais: CA4 (`claude --plugin-dir`), CA5 e CA6 (VM do `sbx` com `agy` autenticado), CA7 (`bash opencode/test-adapter.sh` na VM com `opencode`), CA8 (leitura).

## Passos de produção
nenhum

## Riscos e dúvidas
- **O `agy plugin install` pode não carregar o `agents.json` de um plugin do Claude Code.** A conversão do `plugin install` não foi provada, só a validação de um plugin do `agy`. O CA5 prova na VM. Se o `agy` não carregar o arquivo, a implementação para e comenta na issue (veja "Primeiro passo da implementação").
- **Nome do agente no `agy`:** agentes de plugin podem aparecer com o prefixo do plugin (ex.: `fabrica:revisor`). Por isso o `revisar` usa o nome que o `agy` lista, e o CA5 registra qual é.
- **`agents/revisor.md` com `tools` string no `agy`:** o `agy plugin validate --strict` reclama desse arquivo quando não há `agents.json` (erro) e avisa que o ignora quando há (aviso). Nos dois casos o `agy` carrega o agente do `agents.json`. O CA2 registra a saída esperada.
- **CA5 e CA6 dependem do `agy` autenticado na VM do `sbx`.** Se a etapa não conseguir rodá-los, o `revisar` pede a verificação ao usuário.
- **Código já na branch:** a branch tem commits da primeira tentativa (frontmatter em lista, doc, versão 0.40.0). A implementação desfaz o frontmatter do `agents/revisor.md` e reaproveita o que continua valendo (teste, doc, versão).

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
- 2026-11-18: mudança (alterar) — a execução real no `agy` mostrou que nenhuma lista única de `tools` serve aos dois CLIs; o usuário pediu a opção 1 do escalonamento (arquivo de agente separado para o `agy`, declarado no `agents.json`). CAs: incluídos nenhum; removidos nenhum; alterados CA1, CA2, CA3, CA4, CA5, CA8.
