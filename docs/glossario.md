# Glossário

**ADR** — Registro de uma decisão de arquitetura que vale para além de uma issue, em `docs/adr/`. A spec cria um ADR quando a decisão afeta o projeto inteiro. Veja os [ADRs da fábrica](adr/).

**Backlog** — As issues abertas sem `agente`, criadas pelo `/fabrica:backlog` a partir do fatiamento do PRD. Esperam você puxá-las para o fluxo. Veja [`estados.md`](../skills/status/estados.md#backlog).

**Critério de aceite (CA)** — Comportamento observável que a spec numera como CA1, CA2…, cada um com a forma de verificação. A revisão confere a implementação critério por critério. Veja [`/fabrica:spec`](comandos.md#fabricaspec-número-da-issue-ajustes-pedidos).

**Em andamento** — Label `em-andamento`, que o `/fabrica:avancar` aplica enquanto roda uma etapa numa issue, para outra execução não pegar a mesma issue. Vale por 2 h; depois disso, é considerada esquecida. Veja [`estados.md`](../skills/status/estados.md#etapa-em-andamento).

**Escalonado** — Label que um agente aplica quando para e precisa da sua decisão: falha que não conseguiu corrigir, desvio da spec, pendência de revisão ou pedido no PR que muda a spec. Veja [Issue escalonada](guias/issue-escalonada.md).

**Fatiamento** — Seção do PRD que quebra as funcionalidades em itens de 1 a 2 dias, cada um com número fixo, agrupados em marcos. É a origem das issues de backlog. Veja [`skills/backlog/SKILL.md`](../skills/backlog/SKILL.md#formato-do-fatiamento).

**Issue de backlog** — Issue criada pelo `/fabrica:backlog`, com o marcador `<!-- fabrica:backlog item=<n> -->` no corpo, que a liga a um item do fatiamento. Veja [`estados.md`](../skills/status/estados.md#backlog).

**Janela** — O marco atual e o seguinte, os únicos que ganham issues. Ela avança quando o marco atual está perto de fechar. Veja [Planejamento em ondas](principios.md#planejamento-em-ondas).

**Lição** — Fato do fluxo que vale lembrar na retrospectiva, registrado na hora num comentário `<!-- fabrica:licao -->` da issue ou do PR, que recebe a label `licao`. Os agentes registram nos gatilhos definidos, e você registra com `/fabrica:licao`. Veja [Lições aprendidas](fluxo.md#lições-aprendidas).

**Limite de trabalho em andamento** — No máximo 3 issues abertas com `spec-aprovada` por repositório. Veja [Princípios](principios.md#limite-de-3-em-andamento).

**Marcador** — Comentário HTML invisível, como `<!-- fabrica:triagem -->`, que abre cada comentário de agente. Os agentes usam a sua conta do GitHub, e o marcador é o que distingue o comentário deles do seu. O comentário de [lição](fluxo.md#lições-aprendidas) tem marcador próprio, `<!-- fabrica:licao -->`, e não conta como comentário de agente nem seu. Veja [Tudo no GitHub](principios.md#tudo-no-github).

**Marco** — Grupo de itens do fatiamento, com título `M<n> · <nome>`, que vira uma milestone no GitHub. O marco atual é o primeiro que ainda tem issue aberta ou item sem issue. Veja [Fechar um marco](guias/fechar-marco.md).

**Portão humano** — Ponto do fluxo que só você atravessa: aprovar a spec e fazer o merge do PR. Veja [Fluxo](fluxo.md).

**PRD** — Documento de requisitos do produto, em `docs/prd.md`. Tem o problema, o público, as funcionalidades numeradas (F1, F2…) e o fatiamento. Criado e atualizado pelo `/fabrica:prd`. Veja [`/fabrica:prd`](comandos.md#fabricaprd-ideia-do-produto-em-uma-frase).

**Retrospectiva** — Leitura do que deu errado desde o último marco fechado, feita pelo `/fabrica:retro`: agrupa as lições, os escalonamentos, as rodadas e os seus pedidos nos PRs em padrões e propõe mudanças no fabrica, que viram issues só com a sua confirmação. Veja [`/fabrica:retro`](comandos.md#fabricaretro-repositório).

**Spec** — O contrato de uma issue, em `specs/SPEC-<nº>.md`: objetivo, comportamento, critérios de aceite e desenho técnico. É escrita antes do código e aprovada por você com `spec-aprovada`. Veja [`/fabrica:spec`](comandos.md#fabricaspec-número-da-issue-ajustes-pedidos).

**Triagem** — Primeira etapa de uma issue no fluxo: classifica tipo, classe e tamanho e pergunta na issue o que só você sabe. Veja [`/fabrica:triagem`](comandos.md#fabricatriagem-número-da-issue).
