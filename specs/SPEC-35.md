# SPEC-35: Registrar lições aprendidas na hora em que acontecem

**Issue:** #35 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-10-30

## Contexto
Para fazer uma retrospectiva, como no fechamento de um marco, hoje é preciso lembrar o que deu errado semanas atrás e garimpar issues e PRs. A issue faz cada lição ser registrada no momento em que aparece, junto da evidência, num formato que uma busca reúne em todos os repositórios. A retrospectiva em si e um eventual `/fabrica:retro` ficam para depois de uma rodada feita à mão.

Decisões da triagem:
- **Gatilhos que viram lição:**
  - na revisão, só achado `bloqueante` ou `importante` que ficou sem corrigir;
  - na implementação, só o desvio que mudou o desenho técnico ou veio de um erro ou lacuna da spec.
- **Contagem no status:** é por lição. Começa no fechamento da última issue do último marco fechado. Num repositório sem marco fechado, contam os últimos 30 dias.

## Objetivo
Cada lição relevante fica registrada na issue ou no PR em que aconteceu, num comentário `<!-- fabrica:licao -->` que a label `licao` permite reunir. Os agentes registram nos gatilhos definidos, você registra com `/fabrica:licao`, e o `/fabrica:status` mostra quantas lições surgiram desde o último marco.

## Comportamento esperado

### Formato da lição
Um comentário por issue (ou PR) e por gatilho. A primeira linha é o marcador, com o gatilho:

```markdown
<!-- fabrica:licao gatilho=<gatilho> -->
**Lição · <AAAA-MM-DD>**
- **O que aconteceu:** <fato, com a evidência: comando, achado, link>
- **Causa provável:** <por que aconteceu>
- **Ação sugerida:** <o que mudar, ou "nenhuma, só registro">
- **Origem:** <usuario | triagem | implementar | revisar>
```

- **Gatilhos:** `precisa-info`, `escalonado`, `rodadas`, `desvio`, `achado-pendente`, `usuario`.
- **Label:** a issue (ou o PR, quando a lição é de um PR sem issue do fluxo) recebe `licao`.
- **Lição repetida:** se a issue já tem um comentário `<!-- fabrica:licao gatilho=<g> -->` com o mesmo gatilho, a etapa não cria outro. Ela acrescenta um novo bloco `**Lição · <data>**` ao fim do comentário existente, separado por `---`, editando-o com `gh api -X PATCH repos/<dono>/<repo>/issues/comments/<id> -F body=@<arquivo>`. Esse é o critério verificável de "mesma causa": mesma issue e mesmo gatilho. As lições do usuário (`gatilho=usuario`) sempre criam comentário novo.
- **Um evento, uma lição:** quando um mesmo evento cai em dois gatilhos, usa-se o mais específico. Escalonamento por rodadas de correção registra `rodadas`, e escalonamento por achados pendentes registra `achado-pendente`. Os demais escalonamentos registram `escalonado`.
- **Sem efeito no fluxo:** registrar uma lição não aplica nem remove outra label, não interrompe a etapa e não muda o estado da issue. Se o registro falhar, por exemplo por falta da label `licao`, a etapa avisa no chat e segue.

### Gatilhos automáticos
| Etapa | Quando | Gatilho | Onde comenta |
|---|---|---|---|
| `triagem` | aplica `precisa-info`; a lição resume as lacunas | `precisa-info` | issue |
| `implementar` | aplica `escalonado` por desvio relevante | `escalonado` | issue |
| `implementar` | precisou de 2 ou mais rodadas de correção em `make lint`/`make test`, tenha passado ou escalado | `rodadas` | issue |
| `implementar` | um desvio que vai para "Desvios da spec" mudou o desenho técnico (arquivo, interface ou decisão) ou veio de erro ou lacuna da spec; um bloco por desvio | `desvio` | issue |
| `revisar` | aplica `escalonado` por um pedido no PR que muda a spec (#38) | `escalonado` | issue |
| `revisar` | precisou de 2 ou mais correções por CI vermelho | `rodadas` | issue |
| `revisar` | um achado `bloqueante` ou `importante` ficou sem corrigir, por discordância ou por pendência; um bloco por achado | `achado-pendente` | issue |

As sugestões do revisor e os desvios cosméticos não geram lição.

### `/fabrica:licao [<repo>#]<nº> <texto livre>`
1. **Destino:** o número é de uma issue ou de um PR, no repositório do diretório atual. A forma `<dono>/<repo>#<nº>` aponta outro repositório, por exemplo uma lição sobre a fábrica vista no kairo. Sem número, a skill pergunta o destino com o AskUserQuestion.
2. **Formatação:** organiza o texto nos quatro campos, com `Origem: usuario` e `gatilho=usuario`. Se o texto não der para um campo, como a causa, o campo fica "não informado". A skill não inventa conteúdo.
3. **Confirmação:** mostra a lição formatada e pede confirmação com o AskUserQuestion. As opções são publicar, ajustar o texto ou cancelar.
4. **Publicação:** só com a confirmação, comenta no destino (`gh issue comment` ou `gh pr comment`, com `--body-file`) e aplica a label `licao` no destino.
5. `disable-model-invocation: true`.

### `estados.md`
- **Tabela "Labels":** ganha a linha `licao`, com quem aplica (`triagem`, `implementar`, `revisar`, `licao`), cor `f9d0c4` e significado "Lição aprendida registrada num comentário fabrica:licao.". O `/fabrica:setup` passa a criar sete labels.
- **Definição de comentário:** o comentário que começa com `<!-- fabrica:licao` não conta como comentário do agente nem como comentário do usuário, e é ignorado em todas as regras de estado: resposta nova, último comentário do agente e pedido novo no PR.
- **Label `licao`:** não entra em nenhuma condição da tabela de estados.

### `/fabrica:status`
- **Coleta:** busca as issues e os PRs com a label (`gh search issues --owner <dono> --label licao --include-prs --json repository,number,url --limit 100`). Para cada um, lê os comentários (`gh api repos/<repo>/issues/<nº>/comments`) e conta os blocos `**Lição · <data>**` dos comentários `<!-- fabrica:licao`.
- **Data de corte, por repositório:**
  - **Com marco fechado:** o último marco fechado é o `M<n>` de maior `<n>` sem issue aberta e com pelo menos uma fechada. A data de corte é a do fechamento mais recente das issues dele (`gh issue list -R <repo> --milestone "<título>" --state closed --json closedAt`).
  - **Sem marco fechado:** a data de corte fica 30 dias antes de hoje.
- **Contagem:** conta as lições com data igual ou posterior à de corte.
- **Resposta:** uma seção nova `## Lições`, com uma linha por repositório que tenha lição depois do corte:
  - **Formato:** `<repo>: <N> lições desde <data> (<origem do corte>)`, onde a origem é `fechamento do M<n>` ou `últimos 30 dias`;
  - **Link:** a busca `https://github.com/search?q=owner%3A<dono>+label%3Alicao&type=issues`;
  - **Sem lição:** a seção é omitida.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | A tabela "Labels" do `estados.md` tem `licao`, com cor `f9d0c4` e significado de até 100 caracteres. O `scripts/setup-labels.sh` cria a label sem mudança no script. | manual: `awk` do script sobre o `estados.md` extrai 7 labels; `bash scripts/setup-labels.sh ftenorio99/fabrica` mostra `ok licao`; `gh label list` traz a label |
| CA2 | `triagem`, `implementar` e `revisar` registram a lição em cada gatilho da tabela "Gatilhos automáticos", no formato definido e com a label `licao`, sem alterar outras labels nem interromper a etapa. Sugestões e desvios cosméticos não geram lição. | manual (leitura de cada skill contra a tabela) |
| CA3 | Uma lição com o mesmo gatilho na mesma issue é acrescentada ao comentário existente, com o `PATCH` do comentário, e não gera comentário novo. Um evento em dois gatilhos gera uma lição só. | manual (leitura) |
| CA4 | Existe `skills/licao/SKILL.md` com `disable-model-invocation: true`. Ela aceita `<nº>` e `<dono>/<repo>#<nº>`, pergunta o destino quando falta o número, mostra a lição formatada e só comenta e aplica a label depois da confirmação. | manual (leitura) |
| CA5 | O `estados.md` exclui o comentário `<!-- fabrica:licao` das definições de comentário do agente e do usuário e de todas as regras de estado, e a label `licao` não aparece em nenhuma condição. | manual (leitura) |
| CA6 | O `/fabrica:status` coleta as lições, calcula a data de corte por repositório pelas regras acima e mostra a seção "Lições". | manual: rodar os comandos de coleta contra uma issue de teste com uma lição e conferir a contagem e a data de corte do kairo (último marco fechado) e da fábrica (30 dias) |
| CA7 | O manual (`docs/comandos.md`, `docs/fluxo.md`, `docs/glossario.md` e as menções a "seis labels"), o `README.md`, a `description` do `/fabrica:setup` e a `version` do plugin (`0.11.0`) estão atualizados. | manual: leitura e `grep -rn -i "seis labels" docs/ skills/ README.md` sem resultado |

## Fora de escopo
- A retrospectiva e o `/fabrica:retro`.
- Criar issues a partir das lições automaticamente.
- Classificar ou priorizar as lições.
- Gatilho de lição no `/fabrica:spec` (que também aplica `precisa-info`) e no `/fabrica:backlog`.
- Os casos-limite da #41.

## Desenho técnico
**Arquivos e módulos:**
- `skills/licao/SKILL.md`: skill nova.
- `skills/triagem/SKILL.md`: registro no passo 4, ao aplicar `precisa-info`.
- `skills/implementar/SKILL.md`: registro no desvio relevante, nas rodadas do passo 4 e nos desvios que vão para o PR. Uma seção "Lições" com o formato e o critério de repetição, ou remissão a um arquivo comum (veja Decisões).
- `skills/revisar/SKILL.md`: registro nos passos 2, 4 e 6.
- `skills/status/estados.md` e `skills/status/SKILL.md`.
- `skills/setup/SKILL.md`: `description` com sete labels.
- `docs/comandos.md` (seção nova `/fabrica:licao`, `setup`), `docs/fluxo.md`, `docs/glossario.md` (termos "Lição" e `licao`), `docs/primeiros-passos.md`, `docs/solucao-de-problemas.md`, `README.md` e `.claude-plugin/plugin.json`.

**Dados:** nenhum. O registro vive nos comentários e na label.

**Interfaces:**
- O marcador `<!-- fabrica:licao gatilho=<g> -->` e o bloco `**Lição · <data>**` formam o contrato entre as etapas que registram e o `/fabrica:status`, que conta.

**Decisões:**
- **Formato em arquivo único:** o formato da lição, os gatilhos e a regra de repetição ficam num arquivo só, `skills/licao/formato.md`, que a skill `licao`, a `triagem`, a `implementar` e a `revisar` citam pelo caminho relativo. Assim o formato não é copiado em quatro skills. Alternativa descartada: repetir o bloco em cada skill, que diverge na primeira mudança.
- **Repetição por gatilho:** a "mesma causa" vira "mesmo gatilho na mesma issue", que dá para conferir sem julgamento. Alternativa descartada: comparar o texto da causa, que depende de interpretação.
- **Data em cada bloco:** a contagem usa a data de cada bloco, porque um comentário editado guarda só a data de criação e a da última edição. Alternativa descartada: contar comentários, que perde os blocos acrescentados.
- **Rodadas de CI no `revisar`:** a espera do CI está no `revisar` (passo 6), então o gatilho `rodadas` por CI fica lá, e o `implementar` cuida só de `make lint`/`make test`. A issue citava os dois no `implementar`.
- **Lições automáticas sempre na issue:** a label e a contagem ficam num lugar só. Só o `/fabrica:licao` comenta em PR, quando você escolhe um PR.
- **Versão `0.11.0`:** é um minor, porque traz skill e label novas.

**Fontes da documentação:**
- GitHub CLI (`gh search issues --include-prs`): `gh search issues --help` da versão instalada. Edição de comentário (`PATCH /repos/{o}/{r}/issues/comments/{id}`): API REST do GitHub, não verificada no Context7; será conferida na execução.

**ADR:** nenhum.

## Testes
O repositório não tem `make test`, porque a mudança é texto de skill e manual. A evidência vem da leitura de cada CA e destas verificações manuais:
- **CA1:** o `awk` do `setup-labels.sh` extrai 7 labels, e rodar o script no `ftenorio99/fabrica` cria a `licao`.
- **CA6:** numa issue de teste da fábrica (criada e fechada na verificação), publicar um comentário de lição com dois blocos e aplicar `licao`. Os comandos de coleta do status devem contar 2. Conferir também a data de corte calculada para o kairo e para a fábrica.
- **CA3:** na mesma issue de teste, acrescentar um bloco por `PATCH` e conferir que o comentário continua um só.

## Riscos e dúvidas
- **Conflito com a #41:** ela mexe no `revisar` e no `estados.md`, e a que entrar depois resolve o conflito.
- **Lição que se perde:** o agente pode esquecer de registrar num gatilho. O revisor confere os gatilhos que a branch deveria ter disparado só pela leitura das skills; não existe teste automático.
- **Tamanho:** está no limite do G. Se a implementação passar disso, vale separar a skill `/fabrica:licao` e a contagem no status numa issue à parte.

## Histórico
- 2026-10-30: criação.
- 2026-10-30: aprovada.
