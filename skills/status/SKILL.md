---
name: status
description: Mostra o quadro do fluxo da fábrica em todos os repositórios do usuário (ou em um só) - o que espera aprovação ou revisão do usuário, o que espera agente e com qual comando, o avanço por marco, a próxima issue de backlog a puxar, as lições registradas desde o último marco e alertas como limite de trabalho em andamento, CI vermelho e itens parados. Só lê, não altera nada. Use quando o usuário perguntar o que falta, o que fazer agora ou como estão as issues.
argument-hint: "[repositório]"
---

# Quadro da fábrica

Filtro: $ARGUMENTS (vazio = todos os repositórios do usuário)

Esta skill é o orquestrador em modo leitura: lê o estado de cada issue no GitHub e diz o próximo passo e quem age. As regras de estado estão em [estados.md](estados.md); siga-as à risca e não invente estados.

## Regras
- **Só leitura:** não aplique nem remova labels, não comente, não crie branch, não rode skills de outra etapa. Para executar o próximo passo, o usuário roda o comando indicado.
- Não decida por um portão humano: aprovar spec e fazer merge são sempre do usuário.

## 1. Coletar
- Dono: `gh api user -q .login`.
- Issues: `gh search issues --owner <dono> --label agente --state open --json repository,number,title,labels,updatedAt,url --limit 100`. Com filtro, use `--repo <dono>/<repositório>`.
- Para cada issue, `gh issue view <nº> -R <repo> --json comments,labels` e localize os comentários mais recentes com `<!-- fabrica:triagem -->` e `<!-- fabrica:spec -->`. A branch da issue está no comentário de spec (`**Branch:**`).
- Com a branch, procure o PR: `gh pr list -R <repo> --head <branch> --state all --json number,state,isDraft,url,reviewDecision,statusCheckRollup,updatedAt,body`.
- Para cada PR aberto de issue do fluxo, `gh pr view <nº> -R <repo> --json comments,reviews`, para achar pedidos novos no PR (linha 11 de [estados.md](estados.md)). A referência é a linha `**Pedidos lidos até:**` do último comentário `<!-- fabrica:revisar -->`, ou a data dele quando a linha falta.
- PRs abertos fora do fluxo (sem issue com `agente`): `gh search prs --owner <dono> --state open --json repository,number,title,url,updatedAt`.
- Backlog: `gh search issues "backlog" --owner <dono> --state open --match body --json repository,number,title,body,url --limit 100 -- -label:agente`. Fique só com as que têm o marcador `<!-- fabrica:backlog item=<n> -->`. Com filtro, use `--repo`.
- Repositórios com PRD: `gh repo list <dono> --no-archived --json nameWithOwner --limit 100` (com filtro, só o repositório) e, para cada um, `gh api repos/<repo>/contents/docs/prd.md --silent` (sucesso = tem PRD).
- Milestones de cada repositório com PRD: `gh api "repos/<repo>/milestones?state=all&per_page=100"`, que traz `title`, `open_issues` e `closed_issues`. Considere só as de título `M<n> · <nome>`, na ordem de `<n>`.
- Para as issues citadas no `Depende de` das issues de backlog do marco atual, confira se estão fechadas (`gh issue view <nº> -R <repo> --json state`).
- Lições: `gh search issues --owner <dono> --label licao --include-prs --json repository,number,url --limit 100` (com filtro, use `--repo`) e, para cada resultado, `gh api repos/<repo>/issues/<nº>/comments --paginate`. Nos comentários que começam com `<!-- fabrica:licao`, anote a data de cada bloco `**Lição · <AAAA-MM-DD>**` ([formato](../licao/formato.md)). Para cada repositório com lição, use as milestones `M<n>` já coletadas, ou colete-as se o repositório não tiver PRD.

Rode as consultas independentes em paralelo.

## 2. Classificar
- Aplique a tabela de [estados.md](estados.md) a cada issue e anote estado, quem age e próximo passo.
- **Diretório:** o comando de agente roda no clone do repositório. Use `~/projetos/<repositório>` se existir; senão, indique `gh repo clone <repo> ~/projetos/<repositório>`.
- **Alertas:**
  - limite de trabalho em andamento: 3 ou mais issues abertas com `spec-aprovada` no mesmo repositório;
  - CI falhando em PR aberto;
  - item parado: sem atualização há mais de 3 dias;
  - inconsistências listadas em estados.md;
  - backlog acabando: o marco atual está perto de fechar e o marco depois do próximo existe no GitHub sem nenhuma issue. Sugira "rode `/fabrica:backlog` em `<repo>`".
  - requisito instável: na tabela `### Mudanças` do histórico do `docs/prd.md` (o mesmo PRD lido para os marcos), um F com 3 ou mais linhas cuja coluna Decisão começa com `aceita`. Uma linha com vários F conta para cada um, e um PRD sem a tabela não gera alerta. Texto: "`<repo>`: F<n> mudou <k> vezes; vale revisitar esse requisito com `/fabrica:prd`."
- **Marcos:** para cada repositório com milestones `M<n>`, ache o marco atual e o próximo e conte `fechadas/total` de cada um, conforme a seção "Backlog" de [estados.md](estados.md). Para saber se há item sem issue, leia o fatiamento do PRD: `gh api repos/<repo>/contents/docs/prd.md -q .content | base64 -d`.
- **Lições:** para cada repositório com lição, calcule a data de corte:
  - **Com marco fechado:** o último marco fechado é o `M<n>` de maior `<n>` sem issue aberta e com pelo menos uma fechada. Confira pelas issues, do maior `<n>` para o menor, com `gh issue list -R <repo> --milestone "<título>" --state all --json state,closedAt --limit 500`, e não pelos contadores da milestone, que podem ficar desatualizados. A data de corte é o `closedAt` mais recente das issues desse marco.
  - **Sem marco fechado:** 30 dias antes de hoje.

  Conte os blocos com data igual ou posterior à de corte. Um repositório sem bloco depois do corte fica fora da seção.
- **Próxima issue:** em cada repositório sem nenhuma issue aberta com `agente`, aplique a ordem de sugestão de [estados.md](estados.md):
  - com uma issue de backlog liberada, sugira "aplicar `agente` na #N";
  - se todas as issues de backlog do marco atual dependerem de issues abertas, diga que o marco está bloqueado por dependência e cite a issue que bloqueia;
  - num repositório com `docs/prd.md` e sem milestones `M<n>`, sugira `/fabrica:backlog`.

## 3. PRs para revisar
Para cada PR no estado "PR para revisar", leia o corpo e `gh pr diff <nº> -R <repo> --name-only` e liste os pontos de atenção, sem fazer a revisão completa:
- arquivos sensíveis tocados (`.github/`, migrações, autenticação, segredos, dependências novas no `package.json` ou equivalente);
- o que o PR traz em "Desvios da spec", sugestões não aplicadas da revisão automática e "Para a sua revisão";
- CI e tamanho do diff.

## 4. Responder
No chat, neste formato, omitindo seções vazias:

```markdown
## Esperando você
| Item | Estado | O que fazer |
|---|---|---|
| [kairo#6](url) Título curto | Spec para aprovar | Revisar `specs/SPEC-6.md` e aplicar `spec-aprovada` |

## Marcos
| Repositório | Marco atual | Próximo marco |
|---|---|---|
| kairo | M2 · Tarefas: 1/4 | M3 · Agenda: sem issues |

## Backlog
Uma linha por repositório sem nada no fluxo: a próxima issue a puxar, ou o bloqueio.

| Item | Marco | O que fazer |
|---|---|---|
| [kairo#12](url) Título curto | M2 · Tarefas | Aplicar `agente` (dependências fechadas) |

## Esperando agente
| Item | Estado | Comando | Onde |
|---|---|---|---|
| [kairo#7](url) Título curto | Triada | `/fabrica:spec 7` | `~/projetos/kairo` |

## PRs para revisar
### [kairo#8](url) título do PR
- <ponto de atenção>

## Alertas
- <alerta>

## Lições
- kairo: 3 lições desde 2026-10-12 (fechamento do M1)
- fabrica: 1 lição desde 2026-09-30 (últimos 30 dias)

[Todas as lições](https://github.com/search?q=owner%3A<dono>+label%3Alicao&type=issues)

## Fora do fluxo
- [repo#nº](url) PR aberto sem issue da fábrica
```

Termine com uma linha de recomendação: o que fazer primeiro, priorizando o que destrava agentes (aprovar spec, responder perguntas) antes do que só fecha ciclos (merge). Sem nada no fluxo nem no backlog em nenhum repositório, diga isso e indique `/fabrica:prd` para um projeto novo e `/fabrica:backlog` para um PRD que ainda não tem backlog.
