# Princípios

As decisões que dão forma à fábrica, e por que cada uma existe. Quando há ADR, ele traz o contexto completo.

## Você decide, os agentes executam
A fábrica tem três gestos seus: puxar uma issue (aplicar `agente`), aprovar a spec (`spec-aprovada`) e fazer o merge. Os agentes nunca dão esses passos sozinhos. A spec aprovada é o contrato: a implementação e a revisão são conferidas contra ela, e uma mudança de escopo depois da aprovação volta para você. Numa issue pequena, a spec pode ser a spec curta da triagem ([atalho](fluxo.md#atalho)), mas o gesto de aprovar continua seu: o atalho tira uma etapa do agente, não um portão ([ADR 0004](adr/0004-atalho-da-triagem-com-spec-curta.md)).

## `main` protegida
A `main` é sempre estável e nunca recebe commit ou push direto. Toda mudança nasce numa branch e entra por PR com squash.

Quem garante isso é o próprio git. Hooks globais, instalados uma vez por máquina pelo `/fabrica:setup`, recusam commit e push na `main` nos repositórios da máquina, inclusive os feitos à mão. As únicas exceções são o commit inicial e o primeiro push de um repositório novo.

Duas ressalvas:
- **Hooks do próprio repositório:** o `core.hooksPath` global faz o git ignorar o `.git/hooks` de cada repositório. Por isso os hooks da fábrica chamam, em seguida, o hook de mesmo nome do repositório.
- **Repositórios com `core.hooksPath` local** (husky, lefthook): não passam pelos hooks da fábrica.

Dentro do Claude Code, um hook do plugin impede o Claude de desligar essa proteção com `--no-verify` ou mexendo no `core.hooksPath`. A proteção cobre erros e comandos inocentes, não sabotagem; essa fronteira está no [ADR 0002](adr/0002-protecao-da-main-por-hooks-do-git.md).

## Produção fora do alcance do agente
As etapas de agente só usam dev ou homologação. Os `.env` da máquina só têm valores de dev ou de homologação, e os segredos de produção ficam no provedor. O que precisa rodar em produção (uma migração, um ajuste de dado) vira um passo do runbook, que você executa.

Cada projeto lista em `.fabrica/producao.txt` os hosts e os literais de produção. Um hook do plugin recusa o comando que os cita, e o sandbox bloqueia os hosts na rede, para pegar o que escapa do texto. Como na `main` protegida, o hook cobre o erro inocente, e a barreira de verdade é a outra. Detalhes no [ADR 0006](adr/0006-producao-fora-do-alcance-do-agente.md) e no [guia](guias/isolamento-do-agente.md#produção-fora-do-alcance).

## Limite de 3 em andamento
No máximo 3 issues com `spec-aprovada` ficam abertas ao mesmo tempo em cada repositório, contando as que aguardam merge. Trabalho parado no meio custa mais que trabalho não começado: é PR para revisar, branch para rebasear e contexto para recuperar. O `/fabrica:implementar` recusa começar a quarta, e o `/fabrica:status` alerta.

## Marcos sem sprints
O PRD agrupa os itens em marcos do produto (`M1 · Base`, `M2 · Tarefas`…), sem datas nem sprints. Um marco termina quando as issues dele fecham, não quando o calendário manda. Para um projeto pessoal, data de sprint seria só cerimônia.

## Planejamento em ondas
O `/fabrica:backlog` cria todas as milestones de uma vez, mas issues só para o marco atual e o seguinte. O detalhe de cada issue vem na triagem e na spec, quando ela é puxada. Assim, uma mudança no PRD não deixa dezenas de issues velhas para trás.

Isso é diferente da **execução** em ondas, com várias issues implementadas em paralelo por subagentes. Essa ideia está em estudo na issue #16 e ainda não faz parte da fábrica.

## Idioma
O código é em inglês: nomes de variáveis, funções, arquivos e pastas. Comentários, documentação, issues, PRs e a descrição dos commits são em português. Os commits seguem Conventional Commits, com o prefixo em inglês: `feat: adiciona tela de login`.

## Skills só por comando
Todas as skills que mudam algo têm `disable-model-invocation: true`: só rodam quando você digita o comando. Assim o Claude não começa uma spec ou uma implementação por conta própria a partir de uma frase solta. As exceções são o `/fabrica:status` e o `/fabrica:metricas`, que só leem e podem ser chamados pelo Claude quando você pergunta "o que falta?" ou "como a fábrica está indo?".

## Tudo no GitHub
O estado de cada issue está nas labels, nos comentários dos agentes e no PR, sem arquivo de estado à parte. Os agentes usam a mesma conta que você, então cada comentário de agente começa com um marcador (`<!-- fabrica:<etapa> -->`) para ser distinguido dos seus. O mesmo fluxo pode rodar no terminal hoje e no GitHub Actions depois.

## Context7 por usuário
O Context7 é instalado na máquina de cada usuário, não declarado no plugin, para a API key nunca entrar num repositório. Detalhes no [ADR 0001](adr/0001-context7-instalado-por-usuario.md).
