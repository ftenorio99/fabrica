# Comandos

Cada etapa é uma skill, chamada como `/fabrica:<nome>`. Aqui está o resumo de cada uma; o passo a passo fica no `SKILL.md` linkado no fim de cada seção. Só você chama as skills que mudam algo; as duas que o Claude pode chamar sozinho são o `/fabrica:status` e o `/fabrica:metricas`, que só leem (veja [Princípios](principios.md#skills-só-por-comando)).

## `/fabrica:prd [ideia do produto em uma frase]`
- **Quando:** no início de um projeto, ou quando o escopo do produto mudar.
- **O que faz:** conduz uma entrevista em rodadas (problema, objetivo, escopo, restrições, riscos) e escreve o PRD, com funcionalidades numeradas (F1, F2…) e um fatiamento em marcos `M<n>`.
- **PRD que já existe:** é a baseline do produto. Antes de escrever, o `/fabrica:prd` classifica cada mudança (incluir, excluir ou alterar) e mostra o impacto nas issues do GitHub, com a ação indicada para cada uma. Para um item cuja issue foi fechada como "not planned", a ação indicada é reabri-la, se o item continua no PRD; a reabertura é sua. Você aceita, rejeita ou adia cada mudança, e só as aceitas entram no PRD. Todas, com o motivo, ficam registradas na tabela "Mudanças" do histórico.
- **Lê:** `CLAUDE.md`, `README.md` e o que existir em `docs/`. Ao atualizar, lê também as issues e os PRs do repositório.
- **Cria:** `docs/prd.md`, sem commit; oferece um PR na branch `docs/prd`. Ao criar o PRD, cria também as labels do repositório. Ao atualizar, não mexe em labels nem em issues.
- **Labels:** não aplica labels em issues. Próximo passo, depois do merge: `/fabrica:backlog`.
- Detalhes: [`skills/prd/SKILL.md`](../skills/prd/SKILL.md).

## `/fabrica:backlog`
- **Quando:** depois do merge do PRD, quando o marco atual estiver perto de fechar ou quando o PRD mudar.
- **O que faz:** compara o fatiamento do PRD com o GitHub e mostra um plano. Só aplica o que você confirmar. Se você aplicar sem os possíveis pares, cada um ganha um comentário de recusa e não volta nas execuções seguintes; para desfazer a recusa, apague o comentário.
- **Lê:** o `docs/prd.md` da `main` ou, com um PR `docs/backlog` aberto, o da branch desse PR com a `main` mesclada; as milestones e todas as issues do repositório.
- **Cria:** as milestones `M<n> · <nome>`; issues enxutas, com o marcador `fabrica:backlog`, só para o marco atual e o seguinte; e um PR `docs/backlog` que anota no PRD o número de cada issue.
- **Labels:** cria as issues com `enhancement`, se a label existir. Não aplica `agente`: puxar a issue é com você.
- Detalhes: [`skills/backlog/SKILL.md`](../skills/backlog/SKILL.md).

## `/fabrica:setup [<dono>/<repo>]`
- **Quando:** num repositório sem as labels da fábrica, quando uma etapa avisar que falta uma label ou que o `gh` está desatualizado, ou quando a sessão avisar que os hooks do git não estão instalados.
- **O que faz:** confere se o `gh` está instalado, autenticado e na versão mínima. Se ele estiver desatualizado, mostra como atualizar, sem instalar nada. Se estiver ausente ou sem login, para. Depois, cria ou corrige as labels do fluxo no repositório, sem mexer em outras. Na primeira vez em cada máquina, pede confirmação e instala os hooks do git que protegem a `main`.
- **Lê:** a tabela de labels do [`estados.md`](../skills/status/estados.md) e o `core.hooksPath` global.
- **Cria:** as labels no repositório e, com a sua confirmação, os hooks em `~/.config/fabrica/githooks/`.
- **Labels:** não aplica labels em issues.
- Detalhes: [`skills/setup/SKILL.md`](../skills/setup/SKILL.md).

## `/fabrica:triagem <número da issue>`
- **Quando:** numa issue com `agente` que ainda não foi triada, ou depois de você responder as perguntas da triagem.
- **O que faz:** classifica tipo, classe e tamanho, liga a issue ao PRD e às dependências e procura lacunas que só você pode responder. Pergunta só o que não sabe recomendar: uma escolha em aberto para a qual a triagem tem uma recomendação apoiada numa fonte (a issue, o PRD, um ADR, uma spec, o código ou uma convenção do repositório) vai no comentário como recomendação e segue para a spec, onde você a confirma ao aprovar.
- **Lê:** a issue e os comentários, `CLAUDE.md`, `docs/prd.md`, specs e ADRs e o código que a issue deve tocar.
- **Cria:** um comentário de triagem na issue, que sempre diz se a issue cabe no [atalho](fluxo.md#atalho) e por quê. No atalho, o comentário traz uma spec curta, com o objetivo, os critérios de aceite, o que fica fora do escopo e o nome da branch, e a triagem aplica `spec-pronta`. Não escreve código nem cria a branch.
- **Labels:** aplica `precisa-info` quando há perguntas e a remove quando não há. No atalho, aplica `spec-pronta`. Junto com as perguntas, registra uma [lição](#fabricalicao-donoreponúmero-texto-da-lição) e aplica `licao`.
- Detalhes: [`skills/triagem/SKILL.md`](../skills/triagem/SKILL.md).

## `/fabrica:spec <número da issue> [ajustes pedidos]`
- **Quando:** numa issue triada e sem perguntas abertas, ou para ajustar uma spec que você ainda não aprovou. Numa issue no atalho, quando você comenta antes de aprovar: o comentário tira a issue do atalho, e a spec completa substitui a spec curta.
- **O que faz:** escreve a spec com critérios de aceite verificáveis (CA1, CA2…) e o desenho técnico.
- **Lê:** a issue e a triagem, com as recomendações que ela levou para a spec, que viram decisões para você confirmar, `CLAUDE.md`, PRD, ADRs, specs, o código que será tocado e a documentação das bibliotecas (doc local ou Context7). Confere na ajuda do `gh` instalado (`gh <comando> --help`) cada flag e cada campo `--json` que a spec cita.
- **Cria:** a branch `<tipo>/<nº>-<descrição>`, `specs/SPEC-<nº>.md` (e um ADR, se a decisão vale para além da issue) e um comentário com o resumo.
- **Spec já aprovada:** para mudá-la, remova `spec-aprovada` antes. O ajuste registra no histórico da spec o tipo, o motivo e os CAs incluídos, removidos e alterados, e o comentário na issue aponta o código da branch que esses CAs tocam.
- **Labels:** aplica `spec-pronta`. Se surgir uma lacuna de negócio, aplica `precisa-info` e remove `spec-pronta`. Nunca aplica `spec-aprovada`, que é sua.
- Detalhes: [`skills/spec/SKILL.md`](../skills/spec/SKILL.md).

## `/fabrica:implementar <número da issue>`
- **Quando:** depois que você aplicou `spec-aprovada`.
- **O que faz:** implementa só o que a spec pede, com testes de cada critério, `make lint`, `make test` e as verificações manuais. Respeita o limite de 3 issues em andamento. Termina chamando a etapa de revisão.
- **Lê:** a spec aprovada (no atalho, a spec curta da triagem), o `CLAUDE.md`, o código que será tocado e a documentação das bibliotecas.
- **Cria:** commits na branch da issue. No atalho, cria também a branch, com o nome que a triagem anunciou.
- **Labels:** remove `escalonado` ao retomar. Aplica `escalonado` quando para por falha ou por um desvio da spec que você precisa decidir.
- **Lições:** registra uma na issue, com a label `licao`, quando escala, quando precisa de duas ou mais rodadas de correção e quando um desvio muda o desenho técnico ou vem de um erro da spec.
- Detalhes: [`skills/implementar/SKILL.md`](../skills/implementar/SKILL.md).

## `/fabrica:revisar <número da issue>`
- **Quando:** chamada pela implementação, ou de novo depois que você comentar pedidos no PR.
- **O que faz:** um subagente revisor confere a branch contra a spec, critério por critério. Os achados bloqueantes e importantes são corrigidos em até duas rodadas, e as sugestões vão listadas no PR para você decidir. Antes disso, trata os seus comentários no PR feitos depois do início da última revisão (os que chegam enquanto ela roda ficam para a próxima): corrige o que cabe na spec e escala o que mudaria um critério de aceite. Nunca faz merge.
- **Lê:** a spec (no atalho, a spec curta da triagem, com a linha "Fora do escopo"), os ADRs que ela cita, o `CLAUDE.md`, o diff da branch contra a `main` e os seus comentários no PR.
- **Cria:** o PR com a evidência de cada critério, ou atualiza a descrição de um PR que já existe, e um comentário no PR com o que foi feito em cada pedido seu.
- **Labels:** aplica `pronto-revisao` e remove `escalonado`. Se sobrar pendência, ou se um pedido seu mudar a spec, aplica `escalonado` em vez de `pronto-revisao`; com pendência da revisão, o PR fica como rascunho.
- **Lições:** registra uma na issue, com a label `licao`, quando escala por um pedido seu, quando o CI precisa de duas ou mais correções e para cada achado bloqueante ou importante que fica sem corrigir. Sugestões não geram lição.
- Detalhes: [`skills/revisar/SKILL.md`](../skills/revisar/SKILL.md).

## `/fabrica:avancar [número da issue]`
- **Quando:** quando você quiser que o fluxo ande sem digitar o comando de cada etapa. Rode no clone do repositório.
- **O que faz:** para cada issue com `agente` num estado em que o agente age, executa a etapa seguinte (triagem, spec, implementação ou revisão), relê o estado e repete até a issue chegar a um ponto em que você age: perguntas na issue, spec para aprovar, PR para revisar ou bloqueio. Começa pela issue mais perto do merge, roda no máximo 4 etapas por execução e, se uma issue parar ou falhar, segue para a próxima. Com um número, avança só aquela issue. Nunca aprova spec, nunca faz merge e nunca responde por você.
- **Lê:** o mesmo que o `/fabrica:status`, só no repositório atual, e o `SKILL.md` de cada etapa que executa.
- **Cria:** o que cada etapa executada cria. No fim, mostra no chat o caminho de cada issue, onde ela parou e o que você faz.
- **Labels:** aplica `em-andamento` durante cada etapa e a remove ao fim, para outra execução não pegar a mesma issue. A label vale por 2 h ([ADR 0003](adr/0003-sinal-de-etapa-em-andamento.md)). As demais labels são das etapas.
- Detalhes: [`skills/avancar/SKILL.md`](../skills/avancar/SKILL.md).

## `/fabrica:status [repositório]`
- **Quando:** a qualquer momento, para saber o que falta e quem age.
- **O que faz:** mostra o que espera você, o que espera agente (com o comando e o diretório), o avanço dos marcos, a próxima issue a puxar e os alertas. Numa issue no [atalho](fluxo.md#atalho), o próximo passo aponta para a spec curta no comentário de triagem. Um dos alertas é o de requisito instável: um F com 3 ou mais mudanças aceitas no histórico do PRD. A seção "Lições" conta, por repositório, as lições registradas desde o fechamento do último marco, ou nos últimos 30 dias num repositório sem marco fechado.
- **Lê:** as issues com `agente`, os comentários dos agentes, os PRs, o backlog, as milestones, o PRD e as issues e PRs com `licao` dos seus repositórios.
- **Cria:** nada. Só lê.
- Detalhes: [`skills/status/SKILL.md`](../skills/status/SKILL.md).

## `/fabrica:metricas [repositório] [período] [período de comparação]`
- **Quando:** para saber como a fábrica está indo, ou se uma mudança nela melhorou o fluxo.
- **O que faz:** para as issues entregues no período (por padrão, os últimos 30 dias), mostra quanto tempo cada uma levou da abertura ao merge, quanto esperou por você nos portões e quanto ficou com o agente, além das rodadas, escalonamentos e lições. Agrupa por marco e por repositório, com medianas. Com dois períodos (`AAAA-MM-DD..AAAA-MM-DD`), mostra a diferença entre eles. O tempo "com o agente" inclui a espera até você rodar o comando. Nas issues medidas, ele aparece dividido em trabalho, o tempo em que as etapas rodaram, e fila, a espera até o comando, ao lado dos tokens gastos. Essas colunas vêm da linha de custo que a triagem, a spec, a implementação e a revisão deixam, invisível, no fim do comentário que publicam, com o início, o fim e os tokens da execução, lidos do log da sessão do Claude Code. As issues entregues antes da versão 0.13.0, as etapas sem log, como as do GitHub Actions, e as issues com uma soma parcial, feita antes de o log da sessão terminar de ser gravado, aparecem como "não medido". A issue que passou pelo [atalho](fluxo.md#atalho), sem a etapa de spec, mostra `atalho` na coluna Spec, e não uma rodada zero. Numa issue reaberta, o tempo em que ela ficou fechada não conta em nenhum dos tempos, e os escalonamentos depois do fechamento também não. Com dois períodos, as tabelas por marco e por issue dizem de qual período é cada linha.
- **Lê:** as issues fechadas com `agente`, a linha do tempo das labels de cada uma, os comentários dos agentes e os PRs.
- **Cria:** nada. Só lê.
- Detalhes: [`skills/metricas/SKILL.md`](../skills/metricas/SKILL.md).

## `/fabrica:retro [repositório]`
- **Quando:** ao fechar um marco, ou quando você quiser saber o que mudar na fábrica.
- **O que faz:** desde o último marco fechado (ou nos últimos 30 dias), junta o que deu errado: as lições ainda não consideradas, os escalonamentos, as issues com mais de uma rodada de triagem ou de spec e os seus pedidos nos PRs comparados com o que o revisor tinha apontado. Agrupa em padrões, cada um com as evidências e uma proposta de mudança num arquivo do fabrica. Você escolhe quais viram issue no fabrica, revê o texto e confirma. A comparação com o revisor é um julgamento da skill e aparece como "provável".
- **Lê:** as issues com `agente`, os comentários, a linha do tempo das labels e os PRs dos seus repositórios, e as issues que retrospectivas anteriores criaram no fabrica.
- **Cria:** com a sua confirmação, as issues no fabrica, sem `agente`, e a linha `Retro` nas lições consideradas, para elas não voltarem na próxima retrospectiva. Não edita o fabrica.
- Detalhes: [`skills/retro/SKILL.md`](../skills/retro/SKILL.md).

## `/fabrica:licao [<dono>/<repo>#]<número> <texto da lição>`
- **Quando:** quando você quiser anotar algo que deu errado, ou que vale lembrar na retrospectiva, numa issue ou num PR.
- **O que faz:** organiza o seu texto no formato de lição (o que aconteceu, causa provável, ação sugerida e origem), mostra o resultado e só publica depois que você confirma. Campos que o texto não preenche ficam "não informado". Sem número, pergunta o destino. Com `<dono>/<repo>#<nº>`, registra em outro repositório, como uma lição sobre a fábrica vista no kairo.
- **Lê:** o seu texto e o título da issue ou PR de destino.
- **Cria:** um comentário de lição no destino. Ele não muda o estado da issue.
- **Labels:** aplica `licao` no destino.
- Detalhes: [`skills/licao/SKILL.md`](../skills/licao/SKILL.md) e o formato comum em [`skills/licao/formato.md`](../skills/licao/formato.md).
