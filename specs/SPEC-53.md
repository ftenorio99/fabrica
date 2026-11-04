# SPEC-53: Métricas da fábrica a partir dos eventos do GitHub

**Issue:** #53 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-04

## Contexto
A fábrica não mede o próprio desempenho. As métricas em banco estão previstas só para a Fase 2, mas os eventos do GitHub já trazem o necessário: as labels aplicadas e removidas, com data, na timeline da issue, os comentários com marcador `<!-- fabrica:* -->`, as lições e o fechamento da issue no merge.

Na triagem, o usuário seguiu as recomendações:
- **Divisão:** o custo em tokens por etapa vira uma issue própria. Aqui, o campo fica previsto.
- **Tempo do agente:** tudo que não é portão do usuário conta como "com o agente", inclusive a espera até o comando ser rodado.
- **Comparação:** por período.

## Objetivo
O usuário roda `/fabrica:metricas` e vê, por issue entregue e por marco e repositório, quanto foi entregue, quanto tempo esperou por ele e quanto ficou com o agente. Ele pode comparar dois períodos para medir o efeito de uma mudança na fábrica.

## Comportamento esperado

### Chamada
`/fabrica:metricas [repositório] [período] [período de comparação]`

| Argumentos | Resultado |
|---|---|
| nenhum | todos os repositórios do usuário, últimos 30 dias |
| `fabrica` | só esse repositório, últimos 30 dias |
| `fabrica 2026-11-01..2026-11-04` | só esse período, com as datas inclusivas |
| `fabrica 2026-10-01..2026-10-31 2026-11-01..2026-11-30` | os dois períodos, lado a lado, com a diferença |
| período inválido (ex.: `2026-13-01..x`) | a skill para e mostra o formato esperado, `AAAA-MM-DD..AAAA-MM-DD` |

Um argumento com `..` é período, e qualquer outro é repositório.

### Quais issues entram
Entra a issue **entregue** no período: fechada como concluída (`state_reason` `completed`), com `closedAt` dentro do período e com um evento `labeled` `agente` na timeline. Uma issue fechada como "not planned" não entra.

### Métricas por issue
Os tempos saem dos eventos `labeled` e `unlabeled` da timeline (`gh api repos/<repo>/issues/<nº>/timeline --paginate`), em minutos, mostrados como `1h05` ou `12min`.

| Métrica | Cálculo |
|---|---|
| Abertura ao merge | `closedAt − createdAt` da issue |
| Antes do fluxo | da criação até o primeiro `labeled agente` |
| Esperando você | união dos intervalos em que valia um portão do usuário: `precisa-info` aplicada; `spec-pronta` aplicada sem `spec-aprovada`; `escalonado` aplicada; `pronto-revisao` aplicada. Cada intervalo vai do `labeled` até o `unlabeled` da label, a aplicação de `spec-aprovada` (no caso de `spec-pronta`) ou o fechamento, o que vier antes. |
| Com o agente | do primeiro `labeled agente` até o fechamento, menos "Esperando você". Inclui a espera até o comando ser rodado. |
| Rodadas de triagem | comentários da issue que começam com `<!-- fabrica:triagem -->` |
| Rodadas de spec | comentários da issue que começam com `<!-- fabrica:spec -->` |
| Respostas no PR | comentários do PR da issue que começam com `<!-- fabrica:revisar -->`. O PR é o que a issue cita no comentário de spec (`**Branch:**`), achado com `gh pr list --head <branch> --state merged`. |
| Escalonamentos | eventos `labeled escalonado` |
| Lições | blocos `**Lição · <data>**` nos comentários `<!-- fabrica:licao` da issue e do PR |
| Tokens | sempre "não medido", com remissão à issue do custo em tokens |

Um dado que não existe no histórico, como uma issue sem comentário de spec ou um PR não encontrado, aparece como `—`, nunca como zero.

### Métricas por marco e por repositório
- **Issues entregues:** quantas.
- **Medianas:** de "Abertura ao merge", "Esperando você" e "Com o agente".
- **Lições por issue:** total de lições dividido pelas issues entregues, com uma casa decimal.

O agrupamento por marco usa a milestone da issue. Uma issue sem milestone entra no grupo "sem marco".

### Comparação
Com dois períodos, a tabela por repositório mostra as colunas de cada período e a diferença das medianas (ex.: `−12min`). Um período sem issue entregue mostra `—`.

### Saída
No chat, nesta ordem:
1. Período ou períodos e repositórios lidos.
2. Tabela por repositório (e comparação, se houver).
3. Tabela por marco.
4. Tabela por issue, da mais recente para a mais antiga.
5. Notas fixas:
   - "Com o agente" inclui a espera até o comando ser rodado.
   - Tokens não são medidos (issue do custo em tokens).
   - Quando passar de 100 issues num repositório, a leitura parou nas 100 mais recentes.

### Só leitura
A skill não aplica labels, não comenta e não cria arquivo. Ela pode ser chamada pelo Claude quando o usuário perguntar como a fábrica está indo, como o `/fabrica:status`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/metricas/SKILL.md` existe, com `description` que diz o que a skill mede e quando usar, `argument-hint` com repositório e períodos, e sem `disable-model-invocation`. | manual (leitura) |
| CA2 | A skill descreve a chamada, a validação do período e a regra de quais issues entram, como em "Comportamento esperado". | manual (leitura) |
| CA3 | A skill descreve o cálculo de cada métrica por issue da tabela, com os comandos `gh` de leitura, a união dos intervalos de espera e `—` para dado ausente. | manual (leitura) |
| CA4 | Rodando `/fabrica:metricas fabrica 2026-11-04..2026-11-04`, a #41 aparece com "Com o agente" ≈ 9min e "Esperando você" ≈ 11min, e a #50 com ≈ 6min e ≈ 5min. Os valores conferem com a timeline (folga de 1 min por arredondamento). | manual: rodar a skill e comparar com `gh api repos/ftenorio99/fabrica/issues/<nº>/timeline` |
| CA5 | Na mesma execução, a tabela por repositório mostra pelo menos 3 issues entregues (#41, #48, #50) e as três medianas. A tabela por marco mostra o grupo "sem marco". | manual: rodar a skill |
| CA6 | Com dois períodos (`fabrica 2026-10-01..2026-10-31 2026-11-01..2026-11-30`), a saída mostra os dois lado a lado e a diferença das medianas, com `—` no período sem issue. | manual: rodar a skill |
| CA7 | Um período inválido faz a skill parar com o formato esperado, sem consultar o GitHub. | manual: rodar `/fabrica:metricas fabrica 2026-13-01..x` |
| CA8 | A saída traz as três notas fixas e a coluna Tokens com "não medido". | manual: rodar a skill |
| CA9 | O manual cobre a skill sem copiar a tabela de métricas: seção `/fabrica:metricas` em `docs/comandos.md`, a contagem de skills em `docs/README.md` (de 9 para 10) e a exceção de leitura em `docs/principios.md` e na introdução de `docs/comandos.md`, que passam a citar as duas skills que só leem. | manual: leitura e `grep -rn "9 skills\|apenas o \`/fabrica:status\`" docs/` sem resultado |
| CA10 | `.claude-plugin/plugin.json` sobe para `0.12.0`. | manual (leitura) |

## Fora de escopo
- Custo em tokens e duração real de cada etapa (issue própria).
- Rodadas de correção dentro do `/fabrica:implementar` e do `/fabrica:revisar`, que hoje não deixam registro estruturado. As "Respostas no PR" e os "Escalonamentos" servem de aproximação.
- Banco de dados, painel externo ou arquivo de métricas (Fase 2).
- Mudar o `/fabrica:status` ou as outras skills.

## Desenho técnico
**Arquivos e módulos:**
- `skills/metricas/SKILL.md` (novo): coleta, cálculo e saída.
- `docs/comandos.md`: seção nova e a introdução.
- `docs/README.md`: contagem de skills.
- `docs/principios.md`: "Skills só por comando".
- `.claude-plugin/plugin.json`: `version`.

**Dados:** nenhum armazenado. A leitura é feita a cada execução.

**Interfaces:**
- **Coleta:**
  - `gh search issues --owner <dono> --state closed --reason completed --label agente --closed <desde>..<até> --json repository,number,title,createdAt,closedAt,milestone,url --limit 100` (com repositório, `--repo`);
  - `gh api repos/<repo>/issues/<nº>/timeline --paginate` e `gh api repos/<repo>/issues/<nº>/comments --paginate` por issue;
  - `gh pr list -R <repo> --head <branch> --state merged --json number` e `gh api repos/<repo>/issues/<pr>/comments --paginate` para o PR.
- **Argumentos:** `[repositório] [AAAA-MM-DD..AAAA-MM-DD] [AAAA-MM-DD..AAAA-MM-DD]`.

**Decisões:**
- **Skill própria (`/fabrica:metricas`) em vez de seção no `/fabrica:status`.** O status é chamado a toda hora, e as métricas exigem uma chamada à timeline por issue entregue, o que o deixaria lento. As perguntas também são diferentes: "o que fazer agora" e "como a fábrica está indo". Alternativa descartada: seção no status, que pesa em toda execução.
- **Busca com `--label agente`, conferida pela timeline.** A label `agente` continua na issue fechada, então a busca já filtra o fluxo, e o evento `labeled` confirma a data de entrada. Alternativa descartada: buscar pelo marcador de triagem nos comentários, que exige ler os comentários de todas as issues fechadas.
- **Tempo de espera como união de intervalos:** `escalonado` e `pronto-revisao` podem valer ao mesmo tempo. Somar os dois contaria o mesmo minuto duas vezes.
- **`escalonado` conta como espera pelo usuário:** no `estados.md`, o estado "Bloqueado" é de quem age o usuário. Alternativa descartada: só os três portões citados na issue, que deixaria o bloqueio como tempo do agente.
- **Últimos 30 dias como período padrão:** é o mesmo corte das lições no `/fabrica:status` sem marco fechado.
- **Chamável pelo Claude:** a skill só lê, como o `/fabrica:status`. Alternativa descartada: `disable-model-invocation`, que obrigaria a digitar o comando para uma consulta sem efeito.

**Fontes da documentação:**
- GitHub CLI (`gh search issues` com `--closed`, `--reason` e `--label`; `gh api .../timeline`): versão instalada. A timeline e os campos `event`, `label.name` e `created_at` foram conferidos na triagem (#41 e #50). As flags `--reason` e `--closed` do `gh search issues` ficam para conferir na implementação: não verificadas.

**ADR:** nenhum. A decisão de uma skill só de leitura segue o padrão do `/fabrica:status`.

## Testes
O repositório não tem `make test`: a skill é texto. A evidência é a execução real do CA4 ao CA8 no repositório `fabrica`, comparada à mão com a timeline das issues #41 e #50:
- **#41:** `agente` às 11:39:02, `spec-pronta` às 11:42:37, `spec-aprovada` às 11:46:49, `pronto-revisao` às 11:52:04, fechada às 11:59:21. Esperando você: 4min12 + 7min17 ≈ 11min. Com o agente: 20min19 − 11min29 ≈ 9min.
- **#50:** `agente` às 12:28:17, `spec-pronta` às 12:32:18, `spec-aprovada` às 12:33:42, `pronto-revisao` às 12:35:46, fechada às 12:39:43. Esperando você: 1min24 + 3min57 ≈ 5min. Com o agente: 11min26 − 5min21 ≈ 6min.

## Riscos e dúvidas
- **Flags do `gh search issues`:** se `--reason` ou `--closed` não existirem na versão instalada, a coleta muda para os qualificadores de busca (`reason:completed closed:<desde>..<até>`), depois do `--`. A mudança vai para "Desvios da spec".
- **Cálculo feito pelo Claude:** os tempos são calculados pelo modelo a partir dos eventos, o que pode gerar erro de aritmética. Mitigação: a skill manda calcular com `date -d` ou `python3` no shell, não de cabeça.
- **Repositórios com muitas issues:** o limite de 100 por repositório e a nota na saída evitam uma execução sem fim.

## Histórico
- 2026-11-04: criação.
- 2026-11-04: aprovada.
