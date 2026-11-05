---
name: prd
description: Entrevista o usuário sobre a ideia de um produto e escreve ou atualiza o PRD em docs/prd.md. Use no início de um projeto ou quando o escopo do produto mudar. Não escreve código nem cria issues.
argument-hint: "[ideia do produto em uma frase]"
disable-model-invocation: true
---

# PRD do produto

Você vai conduzir uma entrevista curta e escrever o PRD (documento de requisitos do produto) em `docs/prd.md`. O PRD é a base de todas as specs e issues do projeto, então ele precisa ser concreto: cada funcionalidade deve poder virar uma ou mais issues.

Ideia inicial do usuário: $ARGUMENTS

## Regras
- Não escreva código, não crie issues e não altere outros arquivos além de `docs/prd.md`. A única ação fora dele é o setup das labels do passo 5.
- Proponha em vez de só perguntar: para cada decisão, ofereça 2 a 4 opções concretas com a sua recomendação primeiro. Use o AskUserQuestion, com no máximo 4 perguntas por rodada.
- Não pergunte o que dá para descobrir sozinho: leia antes o `CLAUDE.md`, o `README.md` e o que já existir em `docs/`.
- Se o usuário não souber responder algo, registre em "Perguntas em aberto" e siga em frente.
- Nunca altere labels nem issues, nem no modo atualização. Aplicar a mudança nas issues é do `/fabrica:backlog` e do usuário.

## 1. Contexto
- Se `docs/prd.md` já existir, o PRD é a baseline do produto: siga a seção [Mudanças de requisitos](#mudanças-de-requisitos) em vez dos passos 2 a 5. O setup de labels do passo 5 não roda no modo atualização.
- Se o projeto tiver critérios definidos para o produto (no `CLAUDE.md` ou num documento citado pelo usuário), use-os para avaliar as respostas e avise quando uma escolha os contrariar.

## 2. Entrevista
Faça as rodadas em ordem e pule o que já estiver respondido.

1. **Problema e público:** que problema resolve, para quem, e como essa pessoa resolve hoje.
2. **Objetivo e sucesso:** o que precisa ser verdade para o MVP ter dado certo e como medir.
3. **Escopo do MVP:** proponha a lista de funcionalidades a partir das respostas anteriores. Peça ao usuário para marcar cada uma como obrigatória ou desejável. Puxe o escopo para o menor produto que ainda resolve o problema.
4. **Fora de escopo e restrições:** o que fica explicitamente de fora; stack, prazo, dados sensíveis, integrações obrigatórias.
5. **Riscos:** o que pode dar errado (técnico, de produto ou de uso) e como mitigar.

Entre as rodadas, resuma em uma ou duas linhas o que você entendeu, para o usuário corrigir cedo.

## 3. Escrita
- Preencha o template em [template.md](template.md) e salve em `docs/prd.md`. Crie a pasta `docs/` se não existir.
- Escreva para quem vai implementar: frases curtas, sem jargão de marketing e sem prometer o que não foi decidido.
- Cada funcionalidade do escopo deve ter um identificador estável (F1, F2…), usado depois nas specs e nas issues.
- Em "Fatiamento", quebre as funcionalidades obrigatórias em itens de 1 a 2 dias de trabalho humano cada e agrupe-os em marcos do produto (ex.: "Base", "Tarefas (F2, F11, F12)", "Agenda (F3, F4)"), sem sprints nem datas:
  - o marco tem título `### M<n> · <nome> (<F>)`, em ordem de entrega;
  - o item tem número fixo (`**<n>.**`), título, F entre parênteses (`base` quando não há F) e `depende de <números>` quando depende de outro item. A ordem da lista não cria dependência;
  - numa atualização, item novo recebe o próximo número livre, e o número de item removido não é reaproveitado. Não apague as anotações ` · #<nº>` dos itens que já têm issue.

  Não crie as issues no GitHub; isso é do `/fabrica:backlog`.

## 4. Revisão
- Mostre ao usuário o PRD inteiro e pergunte o que ajustar. Repita até ele aprovar.
- Ao final, não faça commit. Diga que o PRD está pronto e ofereça abrir um PR na branch `docs/prd` com o commit `docs: adiciona prd do produto` (ou `docs: atualiza prd` quando for uma atualização).
- Indique o próximo passo: depois do merge do PR do PRD, rodar `/fabrica:backlog` para criar as milestones e as issues do backlog.

## 5. Labels
- **`gh`:** antes das labels, rode `bash <diretório base desta skill>/../../scripts/check-gh.sh`. Se a linha não for `ok`, não crie as labels: mostre a linha e indique `/fabrica:setup`, como diz [../setup/gh.md](../setup/gh.md). O PRD já escrito fica.
- Sem pedir confirmação, rode `bash <diretório base desta skill>/../../scripts/setup-labels.sh` no diretório do projeto, para as labels da fábrica existirem antes da primeira issue.
- Se ainda não houver remote no GitHub (repositório não criado), não trate como falha: avise que o setup roda com `/fabrica:setup` depois do `gh repo create`.
- Mostre o resultado em uma linha (repositório e labels criadas ou corrigidas).

## Mudanças de requisitos
O PRD que já existe é a baseline: toda mudança passa por análise de impacto e por uma decisão sua, registrada com o motivo, antes de ser escrita.

1. **Coletar.** Leia o PRD, mostre um resumo de três linhas e pergunte o que mudou. Para cada mudança, registre:
   - **tipo:** `incluir`, `excluir` ou `alterar`;
   - **F afetados:** um F novo recebe o próximo número livre;
   - **itens do fatiamento afetados:** inclua os que dependem (`depende de`) de um item alterado ou removido;
   - **motivo.**
2. **Analisar o impacto, antes de escrever qualquer coisa.**
   - **Consultas, agrupadas, sem uma chamada por F:**
     - `gh issue list --state all --limit 1000 --json number,title,body,state,labels,milestone`;
     - `gh pr list --state all --limit 200 --json number,state,headRefName`.

     Liste também os comentários `<!-- fabrica:spec -->` das issues afetadas, que trazem a branch.
   - **Ligação item → issue:** pela anotação ` · #<nº>` do fatiamento ou pelo marcador `<!-- fabrica:backlog item=<n> -->` no corpo.
   - **Relatório no chat:** uma linha por item afetado, com F, item, issue, marco, estado e ação, conforme a tabela:

     | Situação da issue do item | Ação indicada |
     |---|---|
     | Sem issue (só no fatiamento) | Ajustar o PRD. |
     | Issue de backlog (aberta, sem `agente`) | O `/fabrica:backlog` atualiza a issue depois do merge do PRD. |
     | No fluxo, sem PR, sem `spec-aprovada` | Rever a spec com `/fabrica:spec <nº> <ajuste>`. |
     | No fluxo, com `spec-aprovada` e sem PR | O usuário remove `spec-aprovada` e roda `/fabrica:spec <nº> <ajuste>`. |
     | PR aberto | O usuário decide: parar (fechar o PR ou pedir ajuste) ou seguir e tratar a mudança numa issue nova. |
     | Fechada | Abrir uma issue nova de `feat` ou `fix`; nunca alterar a anterior. |
   - **Rodapé do relatório:**
     - as milestones afetadas;
     - o esforço relativo de cada mudança, em `P`, `M` ou `G`, com a escala da triagem;
     - **não rastreadas:** as issues abertas com `agente` que não estão ligadas a nenhum item, com número e título, e o aviso "confira se alguma é afetada".

     Sem remote no GitHub ou sem issues, diga isso e mostre só o impacto no PRD.
3. **Decidir.** Pergunte com o AskUserQuestion, uma pergunta por mudança e no máximo 4 por rodada, com as opções `aceitar`, `rejeitar` e `adiar`. Para rejeitar ou adiar, peça o motivo.
4. **Escrever.**
   - **PRD:** altere o `docs/prd.md` só com as mudanças aceitas, mexendo apenas nas seções afetadas e seguindo as regras do fatiamento do passo 3.
   - **Histórico:** registre todas as mudanças, inclusive as rejeitadas e as adiadas, na tabela `### Mudanças` dentro de `## Histórico`:
     ```markdown
     ### Mudanças
     | Data | Tipo | F | Motivo | Decisão | Issues |
     |---|---|---|---|---|---|
     | 2026-11-02 | alterar | F2, F11 | <motivo> | aceita | #10, #11 |
     | 2026-11-02 | incluir | F21 | <motivo> | adiada: <motivo do adiamento> | — |
     ```
     - **F:** separados por vírgula.
     - **Decisão:** começa com `aceita`, `rejeitada` ou `adiada`, e as duas últimas trazem o motivo depois de `:`.
     - **Issues:** as que o relatório apontou, ou `—`.
     - **PRD sem a subseção:** crie-a na primeira mudança e deixe as linhas antigas do histórico como estão.
   - **Revisão:** mostre o diff do PRD e siga o passo 4 (revisão e oferta do PR `docs/prd`).
5. **Encerrar.** Liste os próximos passos que vêm da coluna "Ação" das mudanças aceitas:
   - `/fabrica:backlog` depois do merge do PRD;
   - o comando ou a decisão de cada issue no fluxo.

   Não altere labels nem issues.
