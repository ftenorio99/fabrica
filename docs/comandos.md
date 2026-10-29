# Comandos

Cada etapa é uma skill, chamada como `/fabrica:<nome>`. Aqui está o resumo de cada uma; o passo a passo fica no `SKILL.md` linkado no fim de cada seção. Só você chama as skills que mudam algo; o Claude pode chamar sozinho apenas o `/fabrica:status`, que só lê (veja [Princípios](principios.md#skills-só-por-comando)).

## `/fabrica:prd [ideia do produto em uma frase]`
- **Quando:** no início de um projeto, ou quando o escopo do produto mudar.
- **O que faz:** conduz uma entrevista em rodadas (problema, objetivo, escopo, restrições, riscos) e escreve `docs/prd.md`. O PRD tem funcionalidades numeradas (F1, F2…) e um fatiamento em marcos `M<n>`. Se o PRD já existir, atualiza só o que mudou e registra no histórico.
- **Cria:** `docs/prd.md`. Não faz commit: oferece um PR na branch `docs/prd`. Ao final, cria as labels do repositório.
- **Labels:** não aplica labels em issues.
- **Próximo passo:** depois do merge do PRD, `/fabrica:backlog`.
- Detalhes: [`skills/prd/SKILL.md`](../skills/prd/SKILL.md).

## `/fabrica:backlog`
- **Quando:** depois do merge do PRD, quando o marco atual estiver perto de fechar ou quando o PRD mudar.
- **O que faz:** compara o fatiamento do PRD com o GitHub e mostra um plano. Só aplica o que você confirmar.
- **Cria:**
  - todas as milestones `M<n> · <nome>`;
  - issues enxutas (com o marcador `fabrica:backlog`) só para o marco atual e o seguinte;
  - um PR `docs/backlog` que anota no PRD o número de cada issue.
- **Labels:** não aplica `agente`; puxar a issue é com você.
- Detalhes: [`skills/backlog/SKILL.md`](../skills/backlog/SKILL.md).

## `/fabrica:setup [<dono>/<repo>]`
- **Quando:** num repositório sem as labels da fábrica, quando uma etapa avisar que falta uma label, ou quando a sessão avisar que os hooks do git não estão instalados.
- **O que faz:** cria ou corrige as seis labels do fluxo no repositório, sem mexer em outras. Na primeira vez em cada máquina, pede confirmação e instala os hooks do git que protegem a `main`.
- **Labels:** não aplica labels em issues.
- Detalhes: [`skills/setup/SKILL.md`](../skills/setup/SKILL.md).

## `/fabrica:triagem <número da issue>`
- **Quando:** numa issue com `agente` que ainda não foi triada, ou depois de você responder as perguntas da triagem.
- **O que faz:** classifica tipo, classe e tamanho, liga a issue ao PRD e às dependências e procura lacunas que só você pode responder.
- **Cria:** um comentário de triagem na issue. Não escreve spec, código nem branch.
- **Labels:** aplica `precisa-info` quando há perguntas e a remove quando não há.
- Detalhes: [`skills/triagem/SKILL.md`](../skills/triagem/SKILL.md).

## `/fabrica:spec <número da issue> [ajustes pedidos]`
- **Quando:** numa issue triada e sem perguntas abertas, ou para ajustar uma spec que você ainda não aprovou.
- **O que faz:** escreve a spec com critérios de aceite verificáveis (CA1, CA2…) e o desenho técnico. Consulta a documentação das bibliotecas pelo Context7.
- **Cria:**
  - a branch `<tipo>/<nº>-<descrição>`;
  - o arquivo `specs/SPEC-<nº>.md` e, quando a decisão vale para além da issue, um ADR;
  - um comentário com o resumo da spec.
- **Labels:** aplica `spec-pronta`. Nunca aplica `spec-aprovada`, que é sua.
- Detalhes: [`skills/spec/SKILL.md`](../skills/spec/SKILL.md).

## `/fabrica:implementar <número da issue>`
- **Quando:** depois que você aplicou `spec-aprovada`.
- **O que faz:** implementa só o que a spec pede, com testes de cada critério, `make lint`, `make test` e as verificações manuais. Respeita o limite de 3 issues em andamento. Termina chamando a etapa de revisão.
- **Cria:** commits na branch da issue.
- **Labels:** remove `escalonado` ao retomar. Aplica `escalonado` quando para por falha ou por um desvio da spec que você precisa decidir.
- Detalhes: [`skills/implementar/SKILL.md`](../skills/implementar/SKILL.md).

## `/fabrica:revisar <número da issue>`
- **Quando:** chamada pela implementação, ou de novo depois de mudanças pedidas no PR.
- **O que faz:** um subagente revisor confere a branch contra a spec, critério por critério. Os achados bloqueantes e importantes são corrigidos em até duas rodadas, e as sugestões vão listadas no PR para você decidir. Nunca faz merge.
- **Cria:** o PR com a evidência de cada critério, ou atualiza a descrição de um PR que já existe.
- **Labels:** aplica `pronto-revisao` e remove `escalonado`. Se sobrar pendência, abre o PR como rascunho e aplica `escalonado`.
- Detalhes: [`skills/revisar/SKILL.md`](../skills/revisar/SKILL.md).

## `/fabrica:status [repositório]`
- **Quando:** a qualquer momento, para saber o que falta e quem age.
- **O que faz:** lê todas as issues com `agente`, os PRs, o backlog e as milestones dos seus repositórios. Mostra o que espera você, o que espera agente (com o comando e o diretório), o avanço dos marcos, a próxima issue a puxar e os alertas.
- **Cria:** nada. Só lê.
- Detalhes: [`skills/status/SKILL.md`](../skills/status/SKILL.md).
