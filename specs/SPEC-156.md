# SPEC-156: Adotar o AGENTS.md como fonte das regras do projeto, com o CLAUDE.md importando-o

**Issue:** #156 · **PRD:** nenhuma F (melhoria fora do roadmap, ligada ao estudo #149) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-17

## Contexto
O OpenCode 2.3.0 e o Antigravity carregam o `AGENTS.md` do projeto e não carregam o `CLAUDE.md`. O Claude Code lê o `AGENTS.md` quando não há `CLAUDE.md`. Com os dois arquivos, ele lê só o `CLAUDE.md`, a menos que o `CLAUDE.md` importe o `AGENTS.md` com `@AGENTS.md`. Hoje o kairo e o ankyra têm os dois arquivos sem o import, e o Claude Code perde as regras do Next que estão no `AGENTS.md`. O usuário decidiu (D3 do mnemo, §11 do `opencode/PLANO-OPENCODE.md`) que o `AGENTS.md` passa a ser a fonte das regras do projeto, e o `CLAUDE.md` fica com o import e o que é só do Claude Code.

## Objetivo
Um projeto montado com os templates da fábrica tem as regras no `AGENTS.md` e um `CLAUDE.md` que começa com `@AGENTS.md`, e as três ferramentas carregam as regras. As skills e o revisor leem as regras do projeto no `AGENTS.md`, sem quebrar num projeto ainda não migrado, e o fabrica já segue o formato novo.

## Comportamento esperado
- **Projeto novo:** o guia de projeto do zero manda copiar `templates/AGENTS.md` e `templates/CLAUDE.md` para a raiz do projeto no primeiro commit (resposta 1 da triagem). Nenhuma skill copia os arquivos.
- **Templates:**
  - `templates/AGENTS.md` traz as regras que hoje estão em `templates/CLAUDE.md`: fluxo da fábrica, idioma, git e GitHub, segredos, versões e dependências e a seção "Projeto".
  - `templates/CLAUDE.md` traz só `@AGENTS.md` na primeira linha e uma seção `## Claude Code` com o que é só do Claude Code: o plugin da fábrica, os comandos `/fabrica:*` e os hooks do plugin.
- **Leitura pelas skills:** as skills e o revisor leem "as regras do projeto": o `AGENTS.md` e, num projeto ainda não migrado (sem `AGENTS.md` ou com um `AGENTS.md` sem as regras da fábrica), o `CLAUDE.md`. Num projeto com os dois, valem os dois.
- **Bloco do Next:** o `next dev` reescreve só o trecho entre `<!-- BEGIN:nextjs-agent-rules -->` e `<!-- END:nextjs-agent-rules -->` e, sem o trecho, acrescenta-o no fim do arquivo (`generate-agent-files.js`, `upsertAgentRulesBlock`). As regras da fábrica ficam fora desse trecho, antes ou depois dele, e o guia de migração diz isso.
- **Migração:** um guia novo explica como migrar um projeto que tem só o `CLAUDE.md` e um que tem os dois arquivos (como o kairo). Kairo, ankyra e mnemo migram depois do merge, num PR cada, fora desta issue (resposta 2).
- **O próprio fabrica:** o `AGENTS.md` do fabrica traz as regras do repositório (estrutura, escrevendo skills e a referência às regras de `templates/AGENTS.md`). O `CLAUDE.md` traz `@AGENTS.md` e a seção `## Claude Code` com o "Testando localmente" (`claude --plugin-dir`).

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `templates/AGENTS.md` existe e traz todas as seções de regras do `templates/CLAUDE.md` atual (fluxo da fábrica, idioma, git e GitHub, segredos, versões e dependências, projeto), com o texto delas, sem perda de regra. | manual — comparar as seções de `git show origin/main:templates/CLAUDE.md` com `templates/AGENTS.md` |
| CA2 | `templates/CLAUDE.md` tem `@AGENTS.md` como primeira linha e só uma seção a mais, `## Claude Code`, sem nenhuma regra de git, idioma ou segredos. | manual — ler o arquivo |
| CA3 | Num projeto temporário com os dois templates copiados e uma frase-sentinela na seção "Projeto" do `AGENTS.md`, o `claude -p` responde a sentinela quando perguntado pelas regras do projeto. | manual — `claude -p` numa pasta temporária, apagada no fim |
| CA4 | No mesmo projeto temporário, o `opencode run` e o `agy -p` também respondem a sentinela. | manual — `opencode run` e `agy -p` na pasta temporária |
| CA5 | As 13 menções ao `CLAUDE.md` como fonte de regras, em `skills/{triagem,spec,implementar,revisar,prd}/SKILL.md` e `agents/revisor.md`, passam a falar das regras do projeto no `AGENTS.md`, com o `CLAUDE.md` como fonte num projeto não migrado. `grep -rn "CLAUDE.md" skills agents` só mostra menções que citam também o `AGENTS.md` ou que falam do arquivo do Claude Code. | manual — `grep -rn "CLAUDE.md" skills agents` e leitura de cada linha |
| CA6 | O exemplo de arquivo do `skills/retro/SKILL.md` cita `templates/AGENTS.md` no lugar de `templates/CLAUDE.md`. | manual — ler a linha |
| CA7 | `docs/guias/projeto-do-zero.md` manda copiar os dois templates no primeiro commit e remete ao `templates/AGENTS.md` como fonte das regras. | manual — ler o guia |
| CA8 | Um guia novo, `docs/guias/migrar-para-agents-md.md`, listado no `docs/README.md`, cobre os dois casos de migração (só `CLAUDE.md`; os dois arquivos sem import) e o bloco do Next, e diz que o projeto migra num PR `chore` próprio. | manual — ler o guia |
| CA9 | `docs/comandos.md` diz que as etapas leem as regras do projeto no `AGENTS.md` (e no `CLAUDE.md` de um projeto não migrado). | manual — `grep -n "AGENTS.md" docs/comandos.md` |
| CA10 | O fabrica segue o formato: `AGENTS.md` com as regras do repositório, `CLAUDE.md` começando com `@AGENTS.md`, só com a seção `## Claude Code`, e a referência às regras de git, idioma e segredos apontando para `templates/AGENTS.md`. | manual — ler os dois arquivos |
| CA11 | Com o fabrica migrado, o `claude -p` na raiz do repositório responde uma regra que só está no `AGENTS.md` do fabrica (por exemplo, onde fica a máquina de estados). | manual — `claude -p` na raiz da branch |
| CA12 | `.claude-plugin/plugin.json` vai para a próxima versão menor livre na `main` no momento do merge (`0.37.0` se a #95 ainda não entrou, ou `0.38.0` se já entrou). | manual — ler o `plugin.json` contra a `main` |

## Fora de escopo
- Automatizar a cópia dos templates (resposta 1 da triagem; outra issue).
- Migrar kairo, ankyra e mnemo (resposta 2; um PR em cada repositório, depois do merge).
- As regras globais do `~/.claude/CLAUDE.md`, que o OpenCode e o Antigravity não leem.
- Mudar o `opencode/PLANO-OPENCODE.md`. O resultado fica registrado no PR.

## Desenho técnico
**Arquivos e módulos:**
- `templates/AGENTS.md` (novo) e `templates/CLAUDE.md`.
- `skills/triagem/SKILL.md`, `skills/spec/SKILL.md`, `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md`, `skills/prd/SKILL.md`, `skills/retro/SKILL.md`, `agents/revisor.md`.
- `docs/guias/projeto-do-zero.md`, `docs/guias/migrar-para-agents-md.md` (novo), `docs/README.md`, `docs/comandos.md`.
- `AGENTS.md` (novo) e `CLAUDE.md` do fabrica.
- `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:** nenhuma interface de código. A frase usada nas skills é "as regras do projeto (`AGENTS.md`; num projeto ainda não migrado, `CLAUDE.md`)".

**Decisões:**
- As skills citam "as regras do projeto: o `AGENTS.md` e, num projeto ainda não migrado, o `CLAUDE.md`" (recomendação da triagem), porque kairo, ankyra e mnemo só migram depois do merge e precisam continuar funcionando até lá. Alternativa descartada: citar só o `AGENTS.md`, o que quebra a leitura das regras nesses projetos até a migração.
- O exemplo do `/fabrica:retro` passa a citar `templates/AGENTS.md` (recomendação da triagem), porque as regras passam a morar lá. Alternativa descartada: manter os dois no exemplo.
- O `templates/CLAUDE.md` usa o import `@AGENTS.md` na primeira linha, no formato da documentação do Claude Code ("Import AGENTS.md into CLAUDE.md"), que lê o importado primeiro e depois o resto. Alternativas descartadas: um symlink `CLAUDE.md -> AGENTS.md`, que não deixa lugar para o que é só do Claude Code; e a configuração `claude-md-and-agents-md`, que é por usuário e não vale no projeto.
- As regras da fábrica no `AGENTS.md` ficam fora do bloco do Next, porque o `next dev` reescreve só o trecho entre os marcadores e acrescenta o bloco no fim quando ele não existe (`upsertAgentRulesBlock` do Next 16.4.3). Alternativa descartada: pôr as regras dentro do bloco, que seria apagado.
- A verificação das três ferramentas usa uma frase-sentinela num projeto temporário e o modo não interativo de cada uma (`claude -p`, `opencode run`, `agy -p`), em vez de abrir o `/memory` numa sessão interativa. O agente consegue rodar esse modo, e a resposta mostra que a regra foi carregada. Alternativa descartada: conferir o `/memory`, que só existe na sessão interativa do Claude Code.
- No fabrica, o "Testando localmente" (`claude --plugin-dir`) fica no `CLAUDE.md`, porque é só do Claude Code. O resto vai para o `AGENTS.md`.
- Sem ADR: a decisão é do usuário, já registrada no plano do OpenCode (D3), e esta spec só a aplica nos templates e nas skills.

**Fontes da documentação:**
- Claude Code 2.1.326 — Context7 `/websites/code_claude`, página "memory": import `@AGENTS.md`, a tabela do que é lido com os dois arquivos e as opções de "Project instructions".
- Next.js 16.4.3 — doc local: `~/projetos/kairo/node_modules/next/dist/server/lib/generate-agent-files.js` (`upsertAgentRulesBlock`, marcadores `BEGIN`/`END:nextjs-agent-rules`).
- OpenCode 2.3.0 — `opencode run --help`. O carregamento do `AGENTS.md` vem da verificação registrada em `opencode/PLANO-OPENCODE.md` §4.6.
- Antigravity (`agy`) 1.5.9 — `agy --help` (`-p`/`--print`). O carregamento do `AGENTS.md` não foi verificado na documentação e é conferido pelo CA4.

**ADR:** nenhum

## Testes
Não há código novo. As verificações são manuais:
- CA1: comparar as seções (`grep -n '^## ' templates/AGENTS.md` contra `git show origin/main:templates/CLAUDE.md | grep -n '^## '`) e o texto de cada uma.
- CA3 e CA4: `d=$(mktemp -d)`, copiar os dois templates, acrescentar na seção "Projeto" do `AGENTS.md` a linha "Palavra-sentinela das regras: <palavra aleatória>", e perguntar "Qual é a palavra-sentinela das regras deste projeto? Responda só a palavra." com `claude -p`, `opencode run` e `agy -p` dentro de `$d`. Cada ferramenta responde a palavra. Apagar `$d`.
- CA5: `grep -rn "CLAUDE.md" skills agents`, linha por linha.
- CA11: `claude -p "Em que arquivo fica a máquina de estados da fábrica? Responda só o caminho."` na raiz da branch: a resposta é `skills/status/estados.md`, que aparece no `AGENTS.md` e não no `CLAUDE.md`.
- Os testes da fábrica continuam passando (`bash scripts/test-*.sh`, menos o de aceite do `sbx`).

## Passos de produção
nenhum

## Riscos e dúvidas
- **Ferramenta sem login:** se o `opencode` ou o `agy` não tiverem um modelo configurado nesta máquina, o CA4 não roda na etapa e vira verificação pedida ao usuário.
- **Respostas não determinísticas:** a pergunta da sentinela pede só a palavra para reduzir a ambiguidade. Uma resposta que traz a palavra no meio do texto conta.
- **Conflito com a #95:** as duas mexem no `CLAUDE.md` do fabrica (a #95 acrescenta um teste na lista de "Estrutura") e no `plugin.json`. Quem fizer o merge depois resolve o conflito, levando a linha do teste para o `AGENTS.md`.

## Histórico
- 2026-11-17: criação.
- 2026-11-17: aprovada.
