# SPEC-34: Analisar impacto e registrar a decisão nas mudanças de requisitos do PRD e da spec

**Issue:** #34 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-10-29

## Contexto
Hoje, para mudar um requisito, basta reabrir o `/fabrica:prd`: ele pergunta o que mudou, atualiza as seções e acrescenta uma linha livre ao histórico (`skills/prd/SKILL.md`, passo 1). Ninguém olha o impacto nas issues, a decisão fica sem o motivo e a mudança fica sem classificação. Na spec, mudar uma versão aprovada pede só que o usuário remova `spec-aprovada` e rode `/fabrica:spec <nº> <ajustes>`.

A issue aproveita o núcleo da gestão de mudanças do IREB CPRE, sem comitê de mudanças:
- o PRD e a spec aprovada passam a ser tratados como baseline;
- cada mudança é classificada por tipo;
- o impacto é analisado pela rastreabilidade;
- o usuário decide se aceita, rejeita ou adia;
- o sistema avisa quando um mesmo F muda demais.

A rastreabilidade já existe:
- **F → item:** o fatiamento do `docs/prd.md` traz o F entre parênteses em cada item;
- **item → issue:** a anotação ` · #<nº>` no item e o marcador `<!-- fabrica:backlog item=<n> -->` no corpo da issue (#20);
- **item → milestone:** o marco `M<n>`;
- **issue → branch → PR:** a branch citada no comentário `<!-- fabrica:spec -->`.

## Objetivo
Mudar o PRD ou uma spec aprovada passa a exigir uma análise de impacto e uma decisão registrada com o motivo. O `/fabrica:status` avisa quando um F acumula mudanças.

## Comportamento esperado

### `/fabrica:prd` em modo atualização (o `docs/prd.md` já existe)
1. **Coletar as mudanças.** Mostre o resumo de três linhas do PRD, como hoje, e pergunte o que mudou. Para cada mudança pedida, registre:
   - o tipo: `incluir`, `excluir` ou `alterar`;
   - os F afetados (para um F novo, o próximo número livre);
   - os itens do fatiamento afetados;
   - o motivo.

   Uma mudança que altera dependências entre itens (`depende de`) também lista os itens que dependem do item alterado.
2. **Gerar o relatório de impacto, antes de escrever qualquer coisa.**
   - **Consultas:** issues abertas e fechadas, com labels, milestone, corpo e comentários, e PRs do repositório. Faça as consultas agrupadas, sem uma chamada por F.
   - **Ligação item → issue:** pela anotação ` · #<nº>` no fatiamento ou pelo marcador de backlog.
   - **Linhas do relatório:** uma por item afetado, com F, item, issue, marco, estado e ação. O estado e a ação seguem a tabela abaixo.

     | Situação da issue do item | Ação indicada |
     |---|---|
     | Sem issue (só no fatiamento) | Ajustar o PRD. |
     | Issue de backlog (aberta, sem `agente`) | O `/fabrica:backlog` atualiza a issue depois do merge do PRD. |
     | No fluxo, sem PR, sem `spec-aprovada` (até `spec-pronta`) | Rever a spec com `/fabrica:spec <nº> <ajuste>`. |
     | No fluxo, com `spec-aprovada` e sem PR | Você remove `spec-aprovada` e roda `/fabrica:spec <nº> <ajuste>`. |
     | PR aberto | Você decide: parar (fechar o PR ou pedir ajuste) ou seguir e tratar a mudança numa issue nova. |
     | Fechada (merged) | Abrir uma issue nova de `feat` ou `fix`. Nunca alterar a anterior. |
   - **Rodapé:** as milestones afetadas e o esforço relativo de cada mudança, `P`, `M` ou `G`, com a mesma escala da triagem.
   - **Não rastreadas:** issues abertas com `agente` que não estão ligadas a nenhum item ficam numa linha à parte, "não rastreadas: confira se alguma é afetada", com número e título. Em repositório sem GitHub ou sem issues, o relatório diz isso e mostra só o impacto no PRD.
3. **Pedir a decisão.** Use o AskUserQuestion, com uma pergunta por mudança e no máximo 4 por rodada. As opções são `aceitar`, `rejeitar` e `adiar`.
4. **Escrever.** Altere o `docs/prd.md` só com as mudanças aceitas. Registre todas as mudanças, inclusive as rejeitadas e as adiadas, na tabela "Mudanças" do histórico (formato abaixo). As regras de numeração do fatiamento continuam valendo.
5. **Encerrar.** Não altere labels nem issues. Liste os próximos passos que vêm da coluna "Ação" das mudanças aceitas: `/fabrica:backlog` depois do merge, e os comandos e decisões de cada issue no fluxo. A oferta de PR na branch `docs/prd` continua igual.

**Formato do histórico do PRD:** a seção `## Histórico` mantém as linhas livres, como criação e aprovação, e ganha uma subseção:

```markdown
### Mudanças
| Data | Tipo | F | Motivo | Decisão | Issues |
|---|---|---|---|---|---|
| 2026-11-02 | alterar | F2, F11 | <motivo> | aceita | #10, #11 |
| 2026-11-02 | incluir | F21 | <motivo> | adiada: <motivo do adiamento> | — |
```
- **Tipo:** `incluir`, `excluir` ou `alterar`.
- **F:** lista separada por vírgula.
- **Decisão:** começa com `aceita`, `rejeitada` ou `adiada`. As duas últimas trazem o motivo depois de `:`.
- **Issues:** as issues impactadas que o relatório apontou.

O template `skills/prd/template.md` ganha a subseção vazia. Num PRD sem a subseção, a skill a cria na primeira mudança e deixa as linhas antigas como estão.

### `/fabrica:spec` ao ajustar uma spec aprovada
**Quando vale:** a spec já existe e já foi aprovada antes, ou seja, tem `**Status:** aprovada` ou uma linha "aprovada" no histórico. A issue está sem `spec-aprovada`, porque o usuário a removeu.

**Na spec:**
- o status volta para `rascunho`;
- o histórico ganha a linha `<data>: mudança (<tipo>) — <motivo>. CAs: incluídos <…>; removidos <…>; alterados <…>.`

**No comentário `<!-- fabrica:spec -->`:** antes de "Critérios de aceite", entra o bloco:
```markdown
**Mudança na spec aprovada:** <tipo> — <motivo>
- CAs incluídos: <…> · removidos: <…> · alterados: <…>
- Implementação afetada: <arquivos ou "sem código na branch">
```
- **Tipo:** `incluir`, `excluir` ou `alterar`.
- **Motivo:** vem dos ajustes passados no argumento ou do comentário do usuário.
- **Implementação afetada:** existe código na branch quando há commits além de `origin/main` fora os commits `docs:` da spec. Nesse caso, liste os arquivos que os CAs alterados ou removidos tocam, a partir do `git diff origin/main...HEAD --stat` e dos testes que citam esses CAs.

### `/fabrica:status`
- **Novo alerta:** um F com 3 ou mais linhas cuja Decisão começa com `aceita`, na tabela "Mudanças" do `docs/prd.md`.
  - Texto do alerta: "`<repo>`: F<n> mudou <k> vezes; vale revisitar esse requisito com `/fabrica:prd`."
  - Uma linha da tabela com vários F conta para cada um deles.
  - Um PRD sem a subseção não gera alerta.
- **Leitura:** o PRD já é baixado para os marcos e serve também para este alerta.

### Fora do PRD e da spec
- O `estados.md` não muda: nenhuma label, estado ou marcador é criado.
- O README ganha um parágrafo "Mudanças de requisitos" na seção do fluxo.
- Se `docs/` já tiver o manual da #32 quando a branch for rebaseada, o manual também é atualizado: `comandos.md` (prd, spec, status) e um guia de mudança no PRD.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/prd/SKILL.md` manda, no modo atualização, classificar cada mudança e mostrar o relatório de impacto, com uma linha por item afetado (F, item, issue, marco, estado e ação), **antes** de qualquer escrita no `docs/prd.md`. | manual (leitura) e verificação no kairo (Testes) |
| CA2 | O relatório usa o GitHub (issues, labels, milestones, PRs). A tabela de ações da skill cobre as 6 situações desta spec. A skill traz ainda as linhas de não rastreadas, as milestones afetadas e o esforço `P`/`M`/`G`. | manual e verificação no kairo |
| CA3 | A skill pede `aceitar`/`rejeitar`/`adiar` por mudança antes de escrever e só escreve as aceitas. Todas entram na tabela "Mudanças" com data, tipo, F, motivo, decisão e issues. `skills/prd/template.md` traz a subseção vazia. | manual |
| CA4 | A skill proíbe alterar labels e issues, inclusive no modo atualização. Na verificação no kairo, nenhuma label ou issue muda: as labels e o `updatedAt` das issues são iguais antes e depois. | verificação no kairo |
| CA5 | `skills/spec/SKILL.md` define quando uma spec foi aprovada antes e manda registrar tipo, motivo e CAs no histórico da spec e no comentário de spec, com a implementação afetada quando houver código na branch. | manual |
| CA6 | `skills/status/SKILL.md` traz o alerta de F com 3 ou mais mudanças aceitas, com a regra de contagem desta spec. `/fabrica:status kairo` roda sem esse alerta, já que o PRD do kairo não tem a subseção. | manual e execução |
| CA7 | O README tem o parágrafo "Mudanças de requisitos". O manual é atualizado se já existir. `plugin.json` está em `0.10.0`. | manual |

## Fora de escopo
- Comitê de mudanças, vários interessados e versionamento formal por requisito.
- Aplicar a mudança nas issues: continua com o `/fabrica:backlog` e com o usuário.
- Uma skill nova, label nova ou estado novo.
- Migrar as linhas antigas do histórico dos PRDs existentes para a tabela.
- Lembrete automático de mudanças adiadas.

## Desenho técnico
**Arquivos e módulos:**
- `skills/prd/SKILL.md`:
  - o passo 1 passa a dizer só "modo atualização: siga a seção Mudanças de requisitos";
  - entra uma seção nova com os passos 1 a 5 acima e a tabela de ações;
  - a regra de não alterar labels nem issues entra nas "Regras".
- `skills/prd/template.md`: a subseção `### Mudanças` vazia, só com o cabeçalho, dentro de `## Histórico`.
- `skills/spec/SKILL.md`: no passo 4, a frase "Em rodada de ajuste…" ganha o caso da spec aprovada antes. O passo 5 ganha o bloco "Mudança na spec aprovada".
- `skills/status/SKILL.md`: o alerta novo na lista de alertas do passo 2.
- `README.md`: o parágrafo novo.
- `docs/` (manual da #32): só se existir na `main` no momento da implementação.
- `.claude-plugin/plugin.json`: `0.10.0`.

**Dados:** a tabela "Mudanças" do `docs/prd.md` de cada projeto, com o formato acima.

**Interfaces:** nenhum comando ou argumento novo.

**Decisões:**
- **Tabela Markdown no histórico,** em vez de linhas livres. A contagem do `/fabrica:status` fica confiável, e a tabela continua legível. Alternativa descartada: linhas livres com prefixo (`- 2026-11-02 · alterar · F2 · …`), mais frágeis de ler e de manter.
- **Relatório só no chat, não num arquivo.** A decisão e as issues impactadas ficam no histórico do PRD, e o relatório completo é material de trabalho. Alternativa descartada: um `docs/mudancas/<data>.md` por mudança, que cria arquivos que ninguém mantém.
- **"Aprovada antes" pela própria spec** (status ou histórico), e não pelo histórico de labels do GitHub. A informação já está na branch e não exige consultar os eventos da issue. Alternativa descartada: `gh api .../issues/<nº>/events` para achar a remoção de `spec-aprovada`.
- **Issues não rastreadas listadas, não ignoradas.** Uma issue aberta à mão pode ser afetada, e só o usuário sabe. Alternativa descartada: buscar F no título ou no corpo, o que daria falso positivo.
- **Versão 0.10.0,** porque é uma funcionalidade nova em três skills. Se a #32 entrar antes (0.9.3), 0.10.0 continua sendo a próxima versão.

**Fontes da documentação:** nenhuma biblioteca.

**ADR:** nenhum. As decisões valem para as skills desta issue, e o formato do histórico fica documentado no template do PRD.

## Testes
O repositório não tem `Makefile`. `bash scripts/test-protect-main.sh` deve continuar passando.

Verificações manuais, que vão para o PR:
- **Verificação no kairo (CA1, CA2, CA4):**
  - antes, salve as labels e o `updatedAt` das issues abertas do kairo;
  - em `~/projetos/kairo`, siga os passos 1 a 3 da skill nova com uma mudança hipotética: "alterar F2: tarefas passam a ter data de vencimento obrigatória";
  - anote o relatório gerado, que deve ligar F2 aos itens 5 e 6 do M2 e às issues #10 e #11, com o estado de cada uma;
  - responda `rejeitar` e confira que o `git status` do kairo segue limpo, já que o PRD não é escrito na verificação;
  - confira que labels e `updatedAt` não mudaram.
- **CA6:** rode `/fabrica:status kairo` e confira que não há alerta de F.
- **CA3 e CA5:** leitura das skills alteradas contra esta spec.

## Riscos e dúvidas
- **Contagem sujeita à escrita manual:** se alguém editar a tabela à mão fora do formato, a linha não conta. É aceitável, porque o alerta é um sinal, não uma regra.
- **Tamanho:** se a seção nova do `/fabrica:prd` passar de umas 40 linhas, o alerta do `/fabrica:status` (CA6) pode sair para uma issue separada, como previsto na triagem.
- **Ordem com a #32:** a que entrar por último atualiza a parte da outra. Esta spec já prevê atualizar o manual se ele existir.

## Histórico
- 2026-10-29: criação.
