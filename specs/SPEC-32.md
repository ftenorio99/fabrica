# SPEC-32: Escrever o manual de uso da fábrica em docs/

**Issue:** #32 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** documentacao · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-10-29

## Contexto
O README da fábrica (63 linhas) junta instalação, fluxo, backlog, labels e proteção da `main` numa página. Não existe manual de uso, e várias dúvidas já apareceram no uso real:
- em que diretório rodar cada comando;
- por que as skills só podem ser chamadas pelo usuário;
- como atualizar o plugin;
- labels que não existem num repositório novo;
- o que fazer quando não há nada no fluxo;
- o hook que barra um comando ou um corpo de PR.

A issue define a estrutura do manual e os limites dele: o manual remete às skills e ao `skills/status/estados.md`, que continuam sendo a fonte da verdade, e não copia regras. A triagem não deixou perguntas.

## Objetivo
A fábrica tem um manual em `docs/`, em português, que explica como usar cada etapa e por quê. O README da raiz aponta para ele, e o `CLAUDE.md` e o `revisor` passam a cobrar que ele seja atualizado junto com as mudanças de comportamento.

## Comportamento esperado
Quem abre o repositório lê um README curto e segue para `docs/README.md`, o índice do manual. Cada página responde a uma pergunta de uso e, para o detalhe operacional, linka o `SKILL.md`, o `estados.md` ou o ADR correspondente.

| Arquivo | Conteúdo |
|---|---|
| `docs/README.md` | Índice com uma linha por página e uma visão geral da fábrica que caiba numa tela, em até 40 linhas. |
| `docs/primeiros-passos.md` | <ul><li>Pré-requisitos: `gh` autenticado e Context7 (ADR 0001).</li><li>Instalação do plugin, `/fabrica:setup` (labels e hooks do git) e atualização (`/plugin marketplace update fabrica` + `/reload-plugins`).</li><li>Em que diretório rodar cada comando: no clone do repositório da issue; `/fabrica:status` e `/fabrica:setup <dono>/<repo>` rodam de qualquer lugar.</li></ul> |
| `docs/fluxo.md` | Do PRD ao merge, com um diagrama Mermaid. Diz quem age em cada etapa, marca os dois portões humanos (aprovar a spec e fazer o merge) e marca também o gesto de aplicar `agente`. Para os estados, remete ao `estados.md`. |
| `docs/comandos.md` | Uma seção por skill, as 8: `prd`, `backlog`, `setup`, `triagem`, `spec`, `implementar`, `revisar`, `status`. Cada seção diz quando usar, quais argumentos aceita, o que lê, o que cria e quais labels aplica ou remove, e termina com o link para o `SKILL.md`. |
| `docs/guias/` | Cinco receitas, uma por arquivo: `projeto-do-zero.md` (do `/fabrica:prd` até a primeira issue no fluxo), `mudanca-no-prd.md`, `issue-escalonada.md`, `revisar-pr.md` e `fechar-marco.md` (fechar um marco e puxar o próximo). |
| `docs/principios.md` | As decisões e seus porquês, com link para `docs/adr/` quando houver ADR: <ul><li>`main` protegida pelos hooks do git e modelo de ameaça (ADR 0002);</li><li>limite de 3 em andamento;</li><li>milestones sem sprints;</li><li>planejamento em ondas do backlog, que não é a execução em ondas da #16, ainda em estudo;</li><li>idioma;</li><li>skills chamadas só por comando (`disable-model-invocation`), com a exceção do `status`, que só lê;</li><li>Context7 por usuário (ADR 0001).</li></ul> |
| `docs/solucao-de-problemas.md` | Um caso por seção, cada um com sintoma, causa e o que fazer. Cobre pelo menos as 5 dúvidas do Contexto da issue, mais 3 casos: o hook do Claude que barra um comando ou um corpo de PR (usar `--body-file`), os hooks do git ausentes (`/fabrica:setup`) e o commit recusado na `main`. |
| `docs/glossario.md` | Termos em ordem alfabética, cada um com uma ou duas frases e um link: backlog, escalonado, issue de backlog, janela, limite de trabalho em andamento, marcador, marco, portão humano, PRD, spec, triagem. |

**Mudanças fora de `docs/`:**
- **`README.md` da raiz:** fica com no máximo 30 linhas. Mantém o que é a fábrica, a instalação em 2 comandos e o link para `docs/README.md`. As seções Backlog, Labels, Proteção da main e Pré-requisitos passam para o manual.
- **`CLAUDE.md`:** ganha a regra "PR que muda comportamento de uma skill, label, estado ou comando atualiza o manual em `docs/` no mesmo PR".
- **`agents/revisor.md`:** a lista "Procure problemas" ganha um item. Um PR que muda comportamento de skill, label, estado ou comando sem atualizar `docs/` é achado `importante`.
- **`.claude-plugin/plugin.json`:** sobe para 0.9.3, por causa da mudança no `revisor`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Existem as 7 páginas da tabela e os 5 guias, todos em português. Todo link relativo em `docs/**/*.md` e no `README.md` aponta para um arquivo que existe. | manual (script de checagem de links rodado na implementação, sem ser commitado) |
| CA2 | `docs/comandos.md` tem uma seção para cada uma das 8 skills. Os argumentos, as labels e os artefatos de cada seção batem com o `argument-hint` e o corpo do `SKILL.md` na versão da branch. | manual (comparação skill a skill) |
| CA3 | `docs/fluxo.md` traz um diagrama em bloco ` ```mermaid ` com as etapas `prd` → `backlog` → `agente` → `triagem` → `spec` → aprovação → `implementar` → `revisar` → merge. Os dois portões humanos estão marcados de forma distinta, e a página linka o `estados.md`. | manual |
| CA4 | `docs/solucao-de-problemas.md` cobre as 5 dúvidas do Contexto da issue mais os 3 casos da proteção da `main`, cada um com sintoma, causa e o que fazer. | manual |
| CA5 | O manual não copia a tabela de labels nem a de estados do `estados.md`: `grep -rE '5319e7\|Avalie de cima para baixo' docs --include='*.md' --exclude-dir=adr` não acha nada. Também não reproduz passos internos das skills: cada seção de `comandos.md` resume o que a skill faz em até 8 linhas e linka o `SKILL.md`. | manual (grep e leitura) |
| CA6 | O `CLAUDE.md` tem a regra de atualizar o manual, e o `agents/revisor.md` traz o item novo em "Procure problemas", com severidade `importante`. | manual |
| CA7 | O `README.md` da raiz tem no máximo 30 linhas e linka `docs/README.md`. O `plugin.json` está em 0.9.3. | manual (`wc -l`) |

## Fora de escopo
- Tradução, CHANGELOG, roadmap e guia de contribuição.
- Mudar o comportamento das skills. Uma inconsistência achada durante a escrita vira issue separada e vai listada no PR.
- Checagem automática de links ou CI de documentação.
- Mudar os ADRs existentes.

## Desenho técnico
**Arquivos e módulos:**
- **Criados:**
  - `docs/README.md`, `docs/primeiros-passos.md`, `docs/fluxo.md`, `docs/comandos.md`, `docs/principios.md`, `docs/solucao-de-problemas.md`, `docs/glossario.md`;
  - `docs/guias/projeto-do-zero.md`, `docs/guias/mudanca-no-prd.md`, `docs/guias/issue-escalonada.md`, `docs/guias/revisar-pr.md`, `docs/guias/fechar-marco.md`.
- **Alterados:** `README.md`, `CLAUDE.md`, `agents/revisor.md`, `.claude-plugin/plugin.json`.
- **`docs/adr/`:** fica onde está; o manual linka os ADRs.

**Dados:** nenhum.

**Interfaces:** nenhuma.

**Decisões:**
- **Diagrama em Mermaid** — o GitHub renderiza, e o texto fica no diff e é fácil de editar. Alternativa descartada: diagrama em ASCII, como o do README atual, que fica ilegível com os portões e os responsáveis.
- **Links para o `SKILL.md` em vez de copiar passos** — o comportamento muda com frequência (#27, #29 e #31 numa semana), e a cópia desatualiza. Alternativa descartada: um manual completo e autocontido.
- **Limites de tamanho:** README da raiz com até 30 linhas, índice com até 40, até 8 linhas por skill em `comandos.md`. Isso dá números verificáveis ao "enxuto" e ao "sem copiar". Alternativa descartada: deixar o tamanho a critério da escrita.
- **Achado do revisor como `importante`, não `bloqueante`** — é cobrado e corrigido na revisão automática sem travar o PR por uma vírgula de documentação. Alternativa descartada: `bloqueante`.
- **Versão 0.9.3** — a mudança de comportamento é pequena (um item no revisor). Alternativa descartada: 0.10.0.

**Fontes da documentação:** nenhuma biblioteca. O Mermaid no GitHub foi conferido no conhecimento do modelo: o GitHub renderiza blocos ` ```mermaid ` em Markdown. Fonte não verificada.

**ADR:** nenhum.

## Testes
O repositório não tem `Makefile` nem testes de documentação. `bash scripts/test-protect-main.sh` deve continuar passando (nenhum arquivo dele muda).

Verificações manuais, que vão para o PR:
- **CA1:** um script descartável, que fica no scratchpad, extrai os links relativos `](...)` de `docs/**/*.md` e do `README.md` e confere que cada destino existe, sem considerar âncoras.
- **CA2:** tabela no PR com cada skill, o `argument-hint` e as labels, conferida contra o `SKILL.md`.
- **CA5:** o `grep` do critério, sem resultado.
- **CA7:** `wc -l README.md`.

## Riscos e dúvidas
- **Tamanho:** são 12 arquivos novos. Se a escrita passar de 2 dias de trabalho humano, os guias viram uma issue separada, e a implementação para e reporta antes de cortar.
- **Mermaid:** se o GitHub não renderizar o diagrama, o texto continua legível no bloco de código.
- **Inconsistências entre skills e README atual:** as que aparecerem na escrita vão para a seção "Para a sua revisão" do PR, sem serem corrigidas nas skills.

## Histórico
- 2026-10-29: criação.
