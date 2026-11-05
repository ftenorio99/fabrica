---
name: retro
description: Faz a retrospectiva da fábrica - lê as lições, os escalonamentos, as rodadas de triagem e de spec e os pedidos do usuário nos PRs comparados com os achados do revisor desde o último marco fechado, agrupa tudo em padrões com as evidências e propõe uma mudança concreta num arquivo do fabrica para cada padrão. Com a confirmação do usuário, cria as issues no fabrica e marca as lições consideradas. Não edita o fabrica. Use ao fechar um marco ou quando o usuário quiser saber o que melhorar na fábrica.
argument-hint: "[repositório]"
disable-model-invocation: true
---

# Retrospectiva da fábrica

Filtro: $ARGUMENTS (vazio = todos os repositórios do usuário)

Esta skill é o observador da fábrica: ela vê onde as etapas falharam e propõe mudanças nas skills, mas não as aplica. Quem decide o que vira issue é o usuário, e as issues criadas entram no fluxo só quando ele aplicar `agente`.

## 1. Coletar
- **Dono:** `gh api user -q .login`. As propostas vão sempre para `<dono>/fabrica`, qualquer que seja o repositório analisado.
- **Repositórios:** com filtro, só `<dono>/<filtro>`. Sem filtro, os que têm issue com `agente`: `gh search issues --owner <dono> --label agente --json repository --limit 100`, sem repetir. O limite de 100 vale para todos os repositórios somados: se a busca trouxer 100 issues, liste os repositórios do dono (`gh repo list <dono> --no-archived --limit 1000 --json nameWithOwner`) e use todos, como no [`/fabrica:metricas`](../metricas/SKILL.md). Os que não tiverem issue com `agente` na janela ficam de fora no passo seguinte.
- **Data de corte** de cada repositório: a mesma das lições no [`/fabrica:status`](../status/SKILL.md) (passo 2, "Lições"). Com marco `M<n>` fechado, o `closedAt` mais recente das issues do último marco fechado. Sem marco fechado, 30 dias antes de hoje (`date -u -d '30 days ago' +%F`).
- **Issues** de cada repositório: `gh search issues --repo <repo> --label agente --updated ">=<corte>" --json number,title,url --limit 100`. Sem `--state`, a busca traz abertas e fechadas. Se trouxer 100, anote o repositório como cortado no limite.
- Para cada issue, numa pasta temporária da sessão:
  - **Comentários:** `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp > <pasta>/ci-<repo>-<nº>.json`. Guarde o `id`, o `html_url` e o `body` de cada um.
  - **Timeline:** `gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp > <pasta>/tl-<repo>-<nº>.json`.
  - **PR:** a branch está no comentário `<!-- fabrica:spec -->` mais recente (`**Branch:**`). Com ela, `gh pr list -R <repo> --head <branch> --state all --json number,url,body`. Para o PR, `gh pr view <nº> -R <repo> --json comments,reviews`, `gh api repos/<repo>/pulls/<nº>/comments --paginate` (comentários em linha) e `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` (para o `id` dos comentários de lição do PR).
- **Issues já propostas:** `gh search issues --repo <dono>/fabrica "fabrica:retro" --match body --json number,body,url --limit 100`. Fique só com as que têm `<!-- fabrica:retro -->` na primeira linha do corpo, e guarde os links da seção Evidências de cada uma.

Rode as consultas independentes em paralelo.

## 2. Separar as evidências
Uma evidência é um fato com link: issue, PR ou comentário. Para cada repositório, a partir da data de corte:

| Fonte | Evidência |
|---|---|
| Lições | Cada bloco `**Lição · <data>**` de um comentário que começa com `<!-- fabrica:licao`, na issue ou no PR, com data igual ou posterior ao corte e **sem** a linha `- **Retro:**`. O link é o `html_url` do comentário; guarde também o `id` e o gatilho do marcador. |
| Escalonamentos | Cada evento `labeled` com a label `escalonado` na timeline. O motivo é o comentário do agente mais próximo, anterior ao evento. |
| Rodadas | Issue com 2 ou mais comentários que começam com `<!-- fabrica:triagem -->`, ou 2 ou mais com `<!-- fabrica:spec -->`. O motivo é o que mudou entre uma rodada e outra (as perguntas, os ajustes pedidos). |
| Revisor × usuário | Cada pedido do usuário no PR: comentário da conversa, review ou comentário em linha que não começa com `<!-- fabrica:` (a review `APPROVED` de corpo vazio não conta, como em [estados.md](../status/estados.md)). Compare com os achados do revisor na seção "Revisão automática" do corpo do PR e nos comentários `<!-- fabrica:revisar -->`. |

Na comparação revisor × usuário:
- **Deixou passar:** o usuário pediu para corrigir algo que nenhum achado do revisor citou.
- **Apontou à toa:** o usuário discordou de um achado do revisor no PR, ou mandou desfazer uma sugestão aplicada.
- Pedidos que só acrescentam escopo, ou que não têm relação com nenhum achado nem com um erro, não são evidência.
- Esta classificação é um julgamento seu. Marque cada uma como "provável" na saída.

Uma evidência que não é lição e cujo link já está nas Evidências de uma issue já proposta vai para a lista "já proposta em fabrica#N" e não entra em padrão novo. A regra não vale para lições: um comentário de lição pode ter vários blocos com o mesmo link, e a lição considerada já ficou de fora pela linha `**Retro:**`. Um bloco sem `**Retro:**` é evidência nova, mesmo que o link do comentário esteja numa issue já proposta.

Sem nenhuma evidência em nenhum repositório, diga isso no chat, com as datas de corte, e pare.

## 3. Agrupar em padrões
- **Padrão:** evidências com a mesma causa, na mesma skill ou etapa (`triagem`, `spec`, `implementar`, `revisar`, `revisor`, `status`, `avancar`, outra). Uma evidência entra num padrão só.
- **Arquivo:** o arquivo do fabrica que a proposta muda, com o caminho real neste repositório (ex.: `skills/spec/SKILL.md`, `agents/revisor.md`, `templates/CLAUDE.md`, `skills/status/estados.md`). Confira que ele existe (`gh api repos/<dono>/fabrica/contents/<caminho> --silent`).
- **Proposta:** a regra a acrescentar, trocar ou remover, e em que seção do arquivo. "Melhorar a spec" não é proposta. Aproveite a "Ação sugerida" das lições, mas não a copie quando ela não diz o que mudar.
- Uma evidência sem par forma padrão sozinha só se ela já apontar uma mudança concreta. Senão, vai para as evidências soltas.
- **Ordem:** o padrão com mais evidências primeiro; no empate, o de evidência mais recente.

## 4. Mostrar
No chat, neste formato, omitindo as seções vazias:

```markdown
**Repositórios:** fabrica (corte 2026-10-06, últimos 30 dias) · kairo (corte 2026-10-12, fechamento do M1)
**Evidências:** 6 lições · 1 escalonamento · 2 rodadas · 3 revisor × usuário (prováveis)

## 1. A spec cita flag ou campo do `gh` que não existe
- **Etapa:** spec · **Arquivo:** `skills/spec/SKILL.md`
- **Evidências:**
  - [fabrica#53 · lição desvio](url): `--reason` não existe no `gh search issues`.
  - [fabrica#53 · lição desvio](url): campo `milestone` ausente no `--json`.
- **Proposta:** em "Desenho técnico", exigir que toda flag ou campo `--json` do `gh` citado na spec seja conferido em `gh <comando> --help`.

## Já propostas
- [fabrica#53 · escalonamento](url) → [fabrica#70](url)

## Evidências soltas
- [kairo#9 · rodadas de spec](url): 2 rodadas, ajuste de texto.
```

## 5. Decidir
- **Quais viram issue:** pergunte com o AskUserQuestion em seleção múltipla, uma opção por padrão (rótulo curto, descrição com o arquivo e o número de evidências). São no máximo 4 opções por pergunta e 4 perguntas por chamada, então entram os 16 primeiros padrões da ordem. Os demais ficam listados no chat para a próxima retro.
- **Para cada padrão escolhido**, escreva o corpo com a ferramenta Write na pasta temporária da sessão:

  ```markdown
  <!-- fabrica:retro -->
  ## Contexto
  <o que aconteceu, em duas a quatro frases, citando os repositórios e a retrospectiva de <AAAA-MM-DD>>

  ## Objetivo
  <a mudança que a proposta faz, em uma frase>

  ## Escopo
  - <a regra a acrescentar, trocar ou remover, em `<arquivo>`>

  ## Fora do escopo
  - <o que parece parte, mas não é>

  ## Evidências
  - [<repo>#<nº> · <fonte>](<link>): <uma frase>
  ```

  Mostre os títulos e os corpos no chat e pergunte com o AskUserQuestion: **Criar**, **Ajustar** (o usuário diz o que mudar, e você mostra de novo) ou **Cancelar** (nada é criado, e as lições desses padrões ficam sem a linha `Retro`, como se o padrão não tivesse sido oferecido).
- **Criar:** `gh issue create -R <dono>/fabrica --title "<título>" --label <label> --body-file <arquivo>`, com:
  - título em português, sem prefixo de tipo, como as outras issues do fabrica;
  - label `enhancement`, ou `bug` quando a proposta corrige uma regra que está errada. Nunca `agente`: puxar a issue para o fluxo é do usuário.
- **Padrões não escolhidos:** são os oferecidos na pergunta e não marcados. Os que passaram dos 16 e os cancelados no **Cancelar** não entram aqui e nunca recebem `descartada`. Se sobrou algum padrão não escolhido, pergunte com o AskUserQuestion se as lições deles ficam marcadas como consideradas: **Marcar** (não voltam na próxima retro) ou **Deixar para a próxima retro**.

## 6. Marcar as lições
Só depois da confirmação, para cada lição considerada:
- **Linha:** `- **Retro:** <AAAA-MM-DD> · <dono>/fabrica#<nº>`, quando a lição entrou num padrão que virou issue, ou `- **Retro:** <AAAA-MM-DD> · descartada`, quando o usuário escolheu **Marcar** os padrões não escolhidos. A data é a de hoje.
- **Onde:** como última linha do bloco da lição, logo depois da linha `- **Origem:**`, como diz [../licao/formato.md](../licao/formato.md).
- **Como:** leia o corpo atual do comentário logo antes de editar (`gh api repos/<repo>/issues/comments/<id> -q .body`), acrescente as linhas sem mudar nenhuma outra, grave o corpo novo com a ferramenta Write e edite com `gh api -X PATCH repos/<repo>/issues/comments/<id> -F body=@<arquivo>`. Um comentário com várias lições consideradas é editado uma vez só, com todas as linhas.
- Só as lições são marcadas. As outras fontes saem da janela quando o marco fecha, e as que já viraram issue aparecem como "já propostas".

## 7. Responder
No chat: as issues criadas, com o link de cada uma, as lições marcadas (quantas e em quais comentários) e os padrões que ficaram para a próxima retro. Termine dizendo que, para puxar uma proposta para o fluxo, o usuário aplica `agente` nela.

## Regras
- Não edite arquivo do fabrica nem de outro repositório, não crie branch nem PR.
- Não aplique nem remova labels nas issues analisadas e não comente nelas. A única escrita fora das issues novas do fabrica é a linha `**Retro:**` nos comentários de lição.
- Nada é publicado antes da confirmação do passo 5. Sem escolha nenhuma e com **Deixar para a próxima retro**, a skill termina sem escrever no GitHub.
- Não invente evidência: todo item da saída tem link. A proposta pode ser sua, mas a causa sai das evidências.
- Publique todo corpo de issue ou comentário a partir de um arquivo, com `--body-file` ou `-F body=@<arquivo>`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- Se `gh issue create` falhar porque a label `enhancement` ou `bug` não existe no fabrica, crie a issue sem label e avise no chat. Não crie a label.
