# Comandos

Cada etapa é uma skill, chamada como `/fabrica:<nome>`. Aqui está o resumo de cada uma; o passo a passo fica no `SKILL.md` linkado no fim de cada seção. Só você chama as skills que mudam algo; o Claude pode chamar sozinho apenas o `/fabrica:status`, que só lê (veja [Princípios](principios.md#skills-só-por-comando)).

## `/fabrica:prd [ideia do produto em uma frase]`
- **Quando:** no início de um projeto, ou quando o escopo do produto mudar.
- **O que faz:** conduz uma entrevista em rodadas (problema, objetivo, escopo, restrições, riscos) e escreve o PRD, com funcionalidades numeradas (F1, F2…) e um fatiamento em marcos `M<n>`. Se o PRD já existir, atualiza só o que mudou e registra no histórico.
- **Lê:** `CLAUDE.md`, `README.md` e o que existir em `docs/`.
- **Cria:** `docs/prd.md`, sem commit; oferece um PR na branch `docs/prd`. Ao final, cria as labels do repositório.
- **Labels:** não aplica labels em issues. Próximo passo, depois do merge: `/fabrica:backlog`.
- Detalhes: [`skills/prd/SKILL.md`](../skills/prd/SKILL.md).

## `/fabrica:backlog`
- **Quando:** depois do merge do PRD, quando o marco atual estiver perto de fechar ou quando o PRD mudar.
- **O que faz:** compara o fatiamento do PRD com o GitHub e mostra um plano. Só aplica o que você confirmar.
- **Lê:** o `docs/prd.md` da `main`, as milestones e todas as issues do repositório.
- **Cria:** as milestones `M<n> · <nome>`; issues enxutas, com o marcador `fabrica:backlog`, só para o marco atual e o seguinte; e um PR `docs/backlog` que anota no PRD o número de cada issue.
- **Labels:** cria as issues com `enhancement`, se a label existir. Não aplica `agente`: puxar a issue é com você.
- Detalhes: [`skills/backlog/SKILL.md`](../skills/backlog/SKILL.md).

## `/fabrica:setup [<dono>/<repo>]`
- **Quando:** num repositório sem as labels da fábrica, quando uma etapa avisar que falta uma label, ou quando a sessão avisar que os hooks do git não estão instalados.
- **O que faz:** cria ou corrige as seis labels do fluxo no repositório, sem mexer em outras. Na primeira vez em cada máquina, pede confirmação e instala os hooks do git que protegem a `main`.
- **Lê:** a tabela de labels do [`estados.md`](../skills/status/estados.md) e o `core.hooksPath` global.
- **Cria:** as labels no repositório e, com a sua confirmação, os hooks em `~/.config/fabrica/githooks/`.
- **Labels:** não aplica labels em issues.
- Detalhes: [`skills/setup/SKILL.md`](../skills/setup/SKILL.md).

## `/fabrica:triagem <número da issue>`
- **Quando:** numa issue com `agente` que ainda não foi triada, ou depois de você responder as perguntas da triagem.
- **O que faz:** classifica tipo, classe e tamanho, liga a issue ao PRD e às dependências e procura lacunas que só você pode responder.
- **Lê:** a issue e os comentários, `CLAUDE.md`, `docs/prd.md`, specs e ADRs e o código que a issue deve tocar.
- **Cria:** um comentário de triagem na issue. Não escreve spec, código nem branch.
- **Labels:** aplica `precisa-info` quando há perguntas e a remove quando não há.
- Detalhes: [`skills/triagem/SKILL.md`](../skills/triagem/SKILL.md).

## `/fabrica:spec <número da issue> [ajustes pedidos]`
- **Quando:** numa issue triada e sem perguntas abertas, ou para ajustar uma spec que você ainda não aprovou.
- **O que faz:** escreve a spec com critérios de aceite verificáveis (CA1, CA2…) e o desenho técnico.
- **Lê:** a issue e a triagem, `CLAUDE.md`, PRD, ADRs, specs, o código que será tocado e a documentação das bibliotecas (doc local ou Context7).
- **Cria:** a branch `<tipo>/<nº>-<descrição>`, `specs/SPEC-<nº>.md` (e um ADR, se a decisão vale para além da issue) e um comentário com o resumo.
- **Labels:** aplica `spec-pronta`. Se surgir uma lacuna de negócio, aplica `precisa-info` e remove `spec-pronta`. Nunca aplica `spec-aprovada`, que é sua.
- Detalhes: [`skills/spec/SKILL.md`](../skills/spec/SKILL.md).

## `/fabrica:implementar <número da issue>`
- **Quando:** depois que você aplicou `spec-aprovada`.
- **O que faz:** implementa só o que a spec pede, com testes de cada critério, `make lint`, `make test` e as verificações manuais. Respeita o limite de 3 issues em andamento. Termina chamando a etapa de revisão.
- **Lê:** a spec aprovada, o `CLAUDE.md`, o código que será tocado e a documentação das bibliotecas.
- **Cria:** commits na branch da issue.
- **Labels:** remove `escalonado` ao retomar. Aplica `escalonado` quando para por falha ou por um desvio da spec que você precisa decidir.
- Detalhes: [`skills/implementar/SKILL.md`](../skills/implementar/SKILL.md).

## `/fabrica:revisar <número da issue>`
- **Quando:** chamada pela implementação, ou de novo depois que os ajustes pedidos no PR forem corrigidos na branch.
- **O que faz:** um subagente revisor confere a branch contra a spec, critério por critério. Os achados bloqueantes e importantes são corrigidos em até duas rodadas, e as sugestões vão listadas no PR para você decidir. Nunca faz merge.
- **Lê:** a spec, os ADRs que ela cita, o `CLAUDE.md` e o diff da branch contra a `main`.
- **Cria:** o PR com a evidência de cada critério, ou atualiza a descrição de um PR que já existe.
- **Labels:** aplica `pronto-revisao` e remove `escalonado`. Se sobrar pendência, abre o PR como rascunho e aplica `escalonado`.
- Detalhes: [`skills/revisar/SKILL.md`](../skills/revisar/SKILL.md).

## `/fabrica:status [repositório]`
- **Quando:** a qualquer momento, para saber o que falta e quem age.
- **O que faz:** mostra o que espera você, o que espera agente (com o comando e o diretório), o avanço dos marcos, a próxima issue a puxar e os alertas.
- **Lê:** as issues com `agente`, os comentários dos agentes, os PRs, o backlog, as milestones e o PRD dos seus repositórios.
- **Cria:** nada. Só lê.
- Detalhes: [`skills/status/SKILL.md`](../skills/status/SKILL.md).
