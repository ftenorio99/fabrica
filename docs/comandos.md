# Comandos

Cada etapa é uma skill, chamada como `/fabrica:<nome>`. Aqui está o resumo de cada uma; o passo a passo fica no `SKILL.md` linkado no fim de cada seção. Só você chama as skills que mudam algo; o Claude pode chamar sozinho apenas o `/fabrica:status`, que só lê (veja [Princípios](principios.md#skills-só-por-comando)).

## `/fabrica:prd [ideia do produto em uma frase]`
- **Quando:** no início de um projeto, ou quando o escopo do produto mudar.
- **O que faz:** conduz uma entrevista em rodadas (problema, objetivo, escopo, restrições, riscos) e escreve o PRD, com funcionalidades numeradas (F1, F2…) e um fatiamento em marcos `M<n>`.
- **PRD que já existe:** é a baseline do produto. Antes de escrever, o `/fabrica:prd` classifica cada mudança (incluir, excluir ou alterar) e mostra o impacto nas issues do GitHub, com a ação indicada para cada uma. Você aceita, rejeita ou adia cada mudança, e só as aceitas entram no PRD. Todas, com o motivo, ficam registradas na tabela "Mudanças" do histórico.
- **Lê:** `CLAUDE.md`, `README.md` e o que existir em `docs/`. Ao atualizar, lê também as issues e os PRs do repositório.
- **Cria:** `docs/prd.md`, sem commit; oferece um PR na branch `docs/prd`. Ao criar o PRD, cria também as labels do repositório. Ao atualizar, não mexe em labels nem em issues.
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
- **O que faz:** cria ou corrige as sete labels do fluxo no repositório, sem mexer em outras. Na primeira vez em cada máquina, pede confirmação e instala os hooks do git que protegem a `main`.
- **Lê:** a tabela de labels do [`estados.md`](../skills/status/estados.md) e o `core.hooksPath` global.
- **Cria:** as labels no repositório e, com a sua confirmação, os hooks em `~/.config/fabrica/githooks/`.
- **Labels:** não aplica labels em issues.
- Detalhes: [`skills/setup/SKILL.md`](../skills/setup/SKILL.md).

## `/fabrica:triagem <número da issue>`
- **Quando:** numa issue com `agente` que ainda não foi triada, ou depois de você responder as perguntas da triagem.
- **O que faz:** classifica tipo, classe e tamanho, liga a issue ao PRD e às dependências e procura lacunas que só você pode responder.
- **Lê:** a issue e os comentários, `CLAUDE.md`, `docs/prd.md`, specs e ADRs e o código que a issue deve tocar.
- **Cria:** um comentário de triagem na issue. Não escreve spec, código nem branch.
- **Labels:** aplica `precisa-info` quando há perguntas e a remove quando não há. Junto com as perguntas, registra uma [lição](#fabricalicao-donoreponúmero-texto-da-lição) e aplica `licao`.
- Detalhes: [`skills/triagem/SKILL.md`](../skills/triagem/SKILL.md).

## `/fabrica:spec <número da issue> [ajustes pedidos]`
- **Quando:** numa issue triada e sem perguntas abertas, ou para ajustar uma spec que você ainda não aprovou.
- **O que faz:** escreve a spec com critérios de aceite verificáveis (CA1, CA2…) e o desenho técnico.
- **Lê:** a issue e a triagem, `CLAUDE.md`, PRD, ADRs, specs, o código que será tocado e a documentação das bibliotecas (doc local ou Context7).
- **Cria:** a branch `<tipo>/<nº>-<descrição>`, `specs/SPEC-<nº>.md` (e um ADR, se a decisão vale para além da issue) e um comentário com o resumo.
- **Spec já aprovada:** para mudá-la, remova `spec-aprovada` antes. O ajuste registra no histórico da spec o tipo, o motivo e os CAs incluídos, removidos e alterados, e o comentário na issue aponta o código da branch que esses CAs tocam.
- **Labels:** aplica `spec-pronta`. Se surgir uma lacuna de negócio, aplica `precisa-info` e remove `spec-pronta`. Nunca aplica `spec-aprovada`, que é sua.
- Detalhes: [`skills/spec/SKILL.md`](../skills/spec/SKILL.md).

## `/fabrica:implementar <número da issue>`
- **Quando:** depois que você aplicou `spec-aprovada`.
- **O que faz:** implementa só o que a spec pede, com testes de cada critério, `make lint`, `make test` e as verificações manuais. Respeita o limite de 3 issues em andamento. Termina chamando a etapa de revisão.
- **Lê:** a spec aprovada, o `CLAUDE.md`, o código que será tocado e a documentação das bibliotecas.
- **Cria:** commits na branch da issue.
- **Labels:** remove `escalonado` ao retomar. Aplica `escalonado` quando para por falha ou por um desvio da spec que você precisa decidir.
- **Lições:** registra uma na issue, com a label `licao`, quando escala, quando precisa de duas ou mais rodadas de correção e quando um desvio muda o desenho técnico ou vem de um erro da spec.
- Detalhes: [`skills/implementar/SKILL.md`](../skills/implementar/SKILL.md).

## `/fabrica:revisar <número da issue>`
- **Quando:** chamada pela implementação, ou de novo depois que você comentar pedidos no PR.
- **O que faz:** um subagente revisor confere a branch contra a spec, critério por critério. Os achados bloqueantes e importantes são corrigidos em até duas rodadas, e as sugestões vão listadas no PR para você decidir. Antes disso, trata os seus comentários no PR feitos depois do início da última revisão (os que chegam enquanto ela roda ficam para a próxima): corrige o que cabe na spec e escala o que mudaria um critério de aceite. Nunca faz merge.
- **Lê:** a spec, os ADRs que ela cita, o `CLAUDE.md`, o diff da branch contra a `main` e os seus comentários no PR.
- **Cria:** o PR com a evidência de cada critério, ou atualiza a descrição de um PR que já existe, e um comentário no PR com o que foi feito em cada pedido seu.
- **Labels:** aplica `pronto-revisao` e remove `escalonado`. Se sobrar pendência, ou se um pedido seu mudar a spec, aplica `escalonado` em vez de `pronto-revisao`; com pendência da revisão, o PR fica como rascunho.
- **Lições:** registra uma na issue, com a label `licao`, quando escala por um pedido seu, quando o CI precisa de duas ou mais correções e para cada achado bloqueante ou importante que fica sem corrigir. Sugestões não geram lição.
- Detalhes: [`skills/revisar/SKILL.md`](../skills/revisar/SKILL.md).

## `/fabrica:status [repositório]`
- **Quando:** a qualquer momento, para saber o que falta e quem age.
- **O que faz:** mostra o que espera você, o que espera agente (com o comando e o diretório), o avanço dos marcos, a próxima issue a puxar e os alertas. Um dos alertas é o de requisito instável: um F com 3 ou mais mudanças aceitas no histórico do PRD. A seção "Lições" conta, por repositório, as lições registradas desde o fechamento do último marco, ou nos últimos 30 dias num repositório sem marco fechado.
- **Lê:** as issues com `agente`, os comentários dos agentes, os PRs, o backlog, as milestones, o PRD e as issues e PRs com `licao` dos seus repositórios.
- **Cria:** nada. Só lê.
- Detalhes: [`skills/status/SKILL.md`](../skills/status/SKILL.md).

## `/fabrica:licao [<dono>/<repo>#]<número> <texto da lição>`
- **Quando:** quando você quiser anotar algo que deu errado, ou que vale lembrar na retrospectiva, numa issue ou num PR.
- **O que faz:** organiza o seu texto no formato de lição (o que aconteceu, causa provável, ação sugerida e origem), mostra o resultado e só publica depois que você confirma. Campos que o texto não preenche ficam "não informado". Sem número, pergunta o destino. Com `<dono>/<repo>#<nº>`, registra em outro repositório, como uma lição sobre a fábrica vista no kairo.
- **Lê:** o seu texto e o título da issue ou PR de destino.
- **Cria:** um comentário de lição no destino. Ele não muda o estado da issue.
- **Labels:** aplica `licao` no destino.
- Detalhes: [`skills/licao/SKILL.md`](../skills/licao/SKILL.md) e o formato comum em [`skills/licao/formato.md`](../skills/licao/formato.md).
