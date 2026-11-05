# SPEC-54: Retrospectiva por agente observador que propõe melhorias nas skills

**Issue:** #54 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-05

## Contexto
As etapas já registram lições na hora (`label:licao`, #44), e os pedidos do usuário nos PRs já entram no fluxo (#40, #41). Quem transforma isso em melhoria da fábrica, porém, ainda é o usuário, numa retrospectiva manual que vira PRs no fabrica (ex.: #10, que saiu da retrospectiva do kairo#3). Na palestra de Zach Lloyd (Warp), a auto-melhoria é um dos quatro componentes da fábrica: um agente observador vê onde as skills falham e propõe mudanças nelas. Esta issue cria esse observador, sem dar a ele o poder de editar o fabrica.

## Objetivo
O usuário roda `/fabrica:retro` e vê os padrões do que deu errado desde o último marco fechado, cada um com as evidências e uma proposta de mudança num arquivo do fabrica. Ele escolhe quais viram issue no fabrica, e as lições consideradas não voltam na próxima retrospectiva.

## Comportamento esperado

### Chamada
`/fabrica:retro [repositório]`

| Argumentos | Resultado |
|---|---|
| nenhum | todos os repositórios do usuário que tenham issue com `agente` na janela |
| `kairo` | só esse repositório |

As propostas são sempre para o repositório `<dono>/fabrica`, qualquer que seja o repositório analisado.

### Janela
Por repositório, a mesma data de corte das lições no `/fabrica:status`:
- **Com marco fechado:** o `closedAt` mais recente das issues do último marco `M<n>` fechado.
- **Sem marco fechado:** 30 dias antes de hoje.

A data de corte de cada repositório aparece no início da saída.

### Fontes
Para cada repositório, das issues com `agente` (abertas ou fechadas) atualizadas a partir da data de corte:

| Fonte | O que conta como evidência | Onde se lê |
|---|---|---|
| Lições | cada bloco `**Lição · <data>**` com data igual ou posterior ao corte e **sem** o campo `**Retro:**` | comentários `<!-- fabrica:licao` da issue e do PR |
| Escalonamentos | cada evento `labeled escalonado` a partir do corte, com o comentário do agente que o explicou | timeline da issue |
| Rodadas de triagem e de spec | issue com 2 ou mais comentários `<!-- fabrica:triagem -->`, ou 2 ou mais `<!-- fabrica:spec -->` | comentários da issue |
| Revisor × usuário | cada pedido do usuário no PR (comentário ou review, como define `estados.md`) comparado com os achados que o revisor publicou na seção "Revisão automática" do corpo do PR e nos comentários `<!-- fabrica:revisar -->` | PR da branch do comentário de spec |

Na comparação revisor × usuário:
- **Deixou passar:** um pedido do usuário que corrige algo que nenhum achado do revisor citou.
- **Apontou à toa:** um achado do revisor de que o usuário discordou no PR, ou uma sugestão que o usuário mandou desfazer.
- Esta classificação é um julgamento da skill, e não uma contagem. Ela aparece marcada como "provável" na saída.

Uma evidência já citada no corpo de uma issue do fabrica com o marcador `<!-- fabrica:retro -->` (aberta ou fechada) aparece como "já proposta em fabrica#N" e não entra em padrão novo.

### Análise
- Agrupar as evidências por padrão: mesma causa, na mesma skill ou etapa. Cada padrão diz a etapa (`triagem`, `spec`, `implementar`, `revisar`, `revisor`, `status`, outra) e o arquivo do fabrica que a proposta muda (ex.: `skills/spec/SKILL.md`, `agents/revisor.md`, `templates/CLAUDE.md`).
- Uma evidência entra em um padrão só.
- A proposta é uma mudança concreta: qual regra acrescentar, trocar ou remover, e onde. "Melhorar a spec" não é proposta.
- Ordem: o padrão com mais evidências primeiro; no empate, o de evidência mais recente.

### Saída
No chat, nesta ordem:
1. Repositórios lidos, com a data de corte de cada um, e quantas evidências vieram de cada fonte.
2. Uma seção por padrão: título, etapa e arquivo, evidências (links para issue, PR ou comentário, com uma frase cada) e proposta.
3. Evidências "já propostas", com o link da issue do fabrica.
4. Evidências soltas, que não formaram padrão, com a lição ou o evento de origem.

Sem nenhuma evidência na janela, a skill diz isso e para.

### Decisão do usuário
- Pergunta, com o AskUserQuestion em seleção múltipla, quais padrões viram issue. São no máximo 4 opções por pergunta e 4 perguntas, então entram os 16 primeiros padrões da ordem; os demais ficam listados e para a próxima rodada.
- Para cada padrão escolhido, mostra o título e o corpo da issue e cria-a no fabrica (`gh issue create -R <dono>/fabrica --body-file <arquivo>`), com:
  - título em português, sem prefixo de tipo;
  - o marcador `<!-- fabrica:retro -->` na primeira linha do corpo;
  - as seções Contexto, Objetivo, Escopo e Fora do escopo, como as issues do fabrica, e uma seção Evidências com os links;
  - a label `enhancement` (ou `bug`, quando a proposta corrige uma regra errada). Nunca a `agente`: puxar a issue para o fluxo é do usuário.
- Depois, pergunta se as lições dos padrões não escolhidos devem ficar marcadas como consideradas (**Marcar** ou **Deixar para a próxima retro**).

### Marcar as lições consideradas
Cada bloco de lição considerado ganha, como última linha, o campo:
- `- **Retro:** <AAAA-MM-DD> · <dono>/fabrica#<nº>`, quando a lição entrou num padrão que virou issue;
- `- **Retro:** <AAAA-MM-DD> · descartada`, quando o usuário escolheu marcar os padrões não escolhidos.

A skill edita o comentário de lição com `gh api -X PATCH repos/<repo>/issues/comments/<id> -F body=@<arquivo>`, preservando o resto do corpo. Uma lição com o campo `**Retro:**` não volta nas próximas retrospectivas. As outras fontes não são marcadas: elas saem da janela quando o marco fecha, e a regra "já proposta" evita a proposta repetida.

### O que a skill não faz
- Não edita arquivo do fabrica, não abre branch nem PR.
- Não aplica nem remove label nas issues analisadas e não comenta nelas. A única escrita fora do fabrica é o campo `**Retro:**` nos comentários de lição.
- Não publica nada antes da confirmação do usuário.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/retro/SKILL.md` existe, com `description` que diz o que a skill faz e quando usar, `argument-hint` `[repositório]` e `disable-model-invocation: true`. | manual (leitura) |
| CA2 | A skill descreve a janela por repositório com a mesma regra do `/fabrica:status`, as quatro fontes da tabela de "Fontes" com os comandos `gh` de leitura e a regra "já proposta". | manual (leitura) |
| CA3 | Rodando `/fabrica:retro fabrica` antes de qualquer marcação, as 6 lições de 2026-11-04 da #53 e da #58 aparecem como evidência, com link para o comentário, e a data de corte mostrada é 30 dias antes do dia da execução. | manual: rodar a skill |
| CA4 | Na mesma execução, as duas lições `desvio` da #53 sobre flag e campo do `gh` ausentes (`--reason` e `milestone`) caem no mesmo padrão, que aponta `skills/spec/SKILL.md` e propõe conferir `gh <comando> --help` antes de pôr flag ou campo no desenho técnico. | manual: rodar a skill |
| CA5 | Cada padrão da saída tem etapa, arquivo do fabrica que existe no repositório, ao menos uma evidência com link e uma proposta que diz o que muda no arquivo. | manual: rodar a skill e conferir os caminhos com `ls` |
| CA6 | Sem confirmação, a skill não cria issue nem edita comentário: escolhendo nenhum padrão e "Deixar para a próxima retro", nenhum comentário de lição muda (`updated_at` igual ao de antes). | manual: rodar a skill e conferir `gh api repos/ftenorio99/fabrica/issues/comments/<id> -q .updated_at` |
| CA7 | Escolhendo um padrão, a issue criada no fabrica tem o marcador `<!-- fabrica:retro -->` na primeira linha, as seções Contexto, Objetivo, Escopo, Fora do escopo e Evidências, a label `enhancement` ou `bug` e não tem `agente`. | manual: `gh issue view <nº> --json body,labels` |
| CA8 | Depois do CA7, cada lição desse padrão ganha `- **Retro:** <data> · ftenorio99/fabrica#<nº>` como última linha do bloco, com o resto do comentário igual, e numa nova execução ela não aparece mais. | manual: ler o comentário e rodar a skill de novo |
| CA9 | Na nova execução do CA8, uma evidência que não é lição e foi citada na issue criada aparece como "já proposta em fabrica#<nº>". | manual: rodar a skill |
| CA10 | O `/fabrica:status` continua contando os blocos de lição marcados: a contagem de lições do fabrica é a mesma antes e depois do CA8. | manual: rodar `/fabrica:status fabrica` antes e depois |
| CA11 | `skills/licao/formato.md` descreve o campo opcional `**Retro:**`, quem o escreve e que ele não muda a contagem nem o estado. `skills/status/estados.md` cita o marcador `<!-- fabrica:retro -->` do corpo das issues criadas pela retro como fora do fluxo. | manual (leitura) |
| CA12 | O manual cobre a skill sem copiar as regras dela: seção `/fabrica:retro` em `docs/comandos.md`, a contagem de skills em `docs/README.md` (de 11 para 12), um passo de retrospectiva em `docs/guias/fechar-marco.md`, a menção em "Lições aprendidas" de `docs/fluxo.md` e o termo "Retrospectiva" em `docs/glossario.md`. | manual: leitura e `grep -rn "11 skills" docs/` sem resultado |
| CA13 | `.claude-plugin/plugin.json` sobe para `0.16.0`. | manual (leitura) |

## Fora de escopo
- Aplicar as mudanças propostas no fabrica: as issues criadas seguem o fluxo normal quando o usuário aplicar `agente`.
- Medir se a mudança melhorou a fábrica (é o papel do `/fabrica:metricas`, com a comparação de períodos).
- Rodar a retro sozinha, ao fechar um marco ou por agendamento.
- Mudar a contagem de lições do `/fabrica:status` para ignorar as já consideradas.
- Marcar as fontes que não são lição.

## Desenho técnico
**Arquivos e módulos:**
- `skills/retro/SKILL.md` (novo): coleta, análise, saída, decisão e marcação.
- `skills/licao/formato.md`: o campo `**Retro:**`.
- `skills/status/estados.md`: o marcador `<!-- fabrica:retro -->` no corpo, numa frase da introdução.
- `docs/comandos.md`, `docs/README.md`, `docs/guias/fechar-marco.md`, `docs/fluxo.md`, `docs/glossario.md`: o manual.
- `.claude-plugin/plugin.json`: `version`.

**Dados:** nada novo armazenado fora do GitHub. O estado da retro fica no campo `**Retro:**` dos blocos de lição e no marcador das issues criadas no fabrica.

**Interfaces:**
- **Coleta**, para cada repositório:
  - `gh search issues --owner <dono> --label agente --updated ">=<corte>" --json repository,number,title,url --limit 100` (com repositório, `--repo`; com mais de 100, repetir por repositório, como no `/fabrica:metricas`);
  - `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` e `gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp` por issue;
  - PR pela branch do comentário de spec: `gh pr list -R <repo> --head <branch> --state all --json number,body,url`, e `gh pr view <nº> -R <repo> --json comments,reviews` com `gh api repos/<repo>/pulls/<nº>/comments --paginate` para os comentários em linha;
  - data de corte com as mesmas chamadas do `/fabrica:status` (milestones e `gh issue list --milestone`);
  - issues da retro: `gh search issues --repo <dono>/fabrica "fabrica:retro" --match body --state all --json number,body,url --limit 100`.
- **Escrita**, só depois da confirmação: `gh issue create -R <dono>/fabrica --title <título> --label <label> --body-file <arquivo>` e `gh api -X PATCH repos/<repo>/issues/comments/<id> -F body=@<arquivo>`.
- Antes de usar uma flag ou campo `--json` novo, a implementação confere `gh <comando> --help` (lição da #53).

**Decisões:**
- **Campo `**Retro:**` no bloco da lição para marcar as consideradas.** A marca fica junto da lição, vale por bloco e leva o link da issue que saiu dela. O `/fabrica:status` conta `**Lição · ` e continua igual. Alternativa descartada: uma label nas issues, que vale para a issue inteira e não distingue uma lição nova chegada depois. Também descartada: cortar pela data da última retro, que perde a lição que o usuário deixou para depois.
- **Skill própria com `disable-model-invocation: true`.** Ela cria issues e edita comentários, então só roda pelo comando, como as outras skills que mudam algo. Alternativa descartada: ser chamável pelo Claude como o `/fabrica:status`, o que vale só para skill que só lê.
- **Mesma janela do `/fabrica:status`.** O usuário já vê "N lições desde o fechamento do M1" no status, e a retro trata as mesmas lições. Alternativa descartada: período livre como no `/fabrica:metricas`, que a issue não pede.
- **Revisor × usuário por julgamento, marcado como "provável".** Os achados do revisor e os pedidos do usuário são texto livre, sem identificador comum. Alternativa descartada: exigir um formato estruturado de achado no revisor, que muda o `revisar` e o agente revisor e fica fora do tamanho desta issue.
- **Confirmação com AskUserQuestion em seleção múltipla.** A retro é interativa, como o `/fabrica:licao`, e não roda no `/fabrica:avancar`. Alternativa descartada: criar todas as issues e deixar o usuário fechar as que não quiser, o que publica sem a decisão do usuário.
- **Issues no fabrica sem `agente`.** Aplicar `agente` é portão do usuário.

**Fontes da documentação:**
- GitHub CLI (`gh`) — `gh <comando> --help` na versão instalada, conferido na implementação. Na spec: não verificada.

**ADR:** nenhum. A decisão vale só para a retro e para o contrato da lição, que está em `skills/licao/formato.md`.

## Testes
O fabrica não tem `make test` para as skills. Os critérios são verificados à mão:
- **CA1, CA2, CA11, CA12, CA13:** leitura dos arquivos e o `grep` do CA12.
- **CA3 a CA5:** rodar `/fabrica:retro fabrica` com as lições da #53 e da #58 ainda sem `**Retro:**`.
- **CA6:** a mesma execução, sem escolher nenhum padrão, conferindo o `updated_at` dos comentários de lição.
- **CA7 a CA10:** uma segunda execução, escolhendo o padrão do CA4, e depois uma terceira. A issue criada no teste fica aberta como proposta real (o padrão do CA4 é uma melhoria verdadeira da spec).

## Riscos e dúvidas
- **Julgamento revisor × usuário:** pode errar a classificação. A marca "provável" e o link para o PR deixam a decisão com o usuário.
- **Edição do comentário de lição:** um `PATCH` com o corpo mal montado apaga outra lição. A skill monta o corpo novo a partir do corpo atual lido logo antes e só acrescenta linhas.
- **Lições sem `**Retro:**` antes do corte:** ficam de fora para sempre se o marco fechar sem retro. É o comportamento pedido ("desde o último marco"), e a busca por `label:licao` continua achando todas.
- **Volume:** muitos repositórios e issues deixam a coleta lenta. As chamadas independentes rodam em paralelo.

## Histórico
- 2026-11-05: criação.
- 2026-11-05: aprovada.
