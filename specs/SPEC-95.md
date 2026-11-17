# SPEC-95: Bloqueio de ação externa com checklist passo a passo, separado do precisa-info

**Issue:** #95 · **PRD:** F3 (prepara a F5) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-17

## Contexto
Hoje, quando uma etapa precisa de algo do usuário, ela usa o `precisa-info`, para perguntas, ou o `escalonado`, para falhas e decisões. Falta o caso em que o agente depende de uma **ação externa** do usuário: criar uma conta ou um projeto num serviço, cadastrar um secret no GitHub, gerar uma chave de API. A resposta para isso não é um texto, é uma ação feita fora do GitHub. A F3 do PRD pede que, nesse caso, o agente publique uma checklist passo a passo na issue e retome sozinho quando o usuário concluir. A F5 conta "checklist de ação externa concluída" como um dos gestos que disparam a etapa seguinte no dispatcher (#107).

## Objetivo
O `implementar` e o `revisar` podem parar numa ação externa publicando uma checklist na issue, com a label `acao-externa`. O `/fabrica:status` e o `/fabrica:avancar` reconhecem a ação pendente e a concluída, a etapa que parou retoma quando todos os itens estão marcados, e o `/fabrica:metricas` conta a espera como tempo do usuário.

## Comportamento esperado
**Ao precisar de uma ação externa** (no `implementar` ou no `revisar`):
1. A etapa faz commit e push do que já existe.
2. Ela publica na issue um comentário de ação no formato de `skills/status/acao-externa.md`: o marcador `<!-- fabrica:acao etapa=<implementar|revisar> -->` na primeira linha, o motivo e uma checklist com pelo menos um item `- [ ]`. Cada item diz o que fazer, onde fazer (com link quando houver) e qual nome de secret, variável ou recurso usar, **nunca o valor**.
3. Ela aplica `acao-externa` e para. A linha de custo vai no fim do comentário de ação.

**O usuário** faz cada passo fora do GitHub e marca o item na própria checklist, editando o comentário. Ele não precisa comentar.

**Estados**, lidos do comentário de ação mais recente pelo `scripts/acao-status.py`:

| Situação | Estado | Quem age | Próximo passo |
|---|---|---|---|
| `acao-externa` e algum item desmarcado | 1a Ação externa pendente | usuário | Fazer os passos da checklist e marcar cada item |
| `acao-externa` e todos os itens marcados | 1b Ação concluída | agente | `/fabrica:<etapa do marcador> <nº>` |
| `acao-externa` sem comentário de ação, comentário sem itens ou com etapa fora de `implementar` e `revisar` | inconsistência | usuário | alerta no `/fabrica:status` |

As linhas 1a e 1b ficam logo depois do `escalonado` (linha 1) e antes da linha 2. Com `escalonado` e `acao-externa` ao mesmo tempo, vale o `escalonado`.

**Retomada** (a etapa do marcador, rodada pelo comando dela ou pelo `/fabrica:avancar`, com `acao-externa` na issue):

| Situação | O que a etapa faz |
|---|---|
| Todos os itens marcados | Confere o que dá para conferir sem ler valores (ex.: o nome em `gh secret list` ou `gh variable list`). Se a conferência passar, ou se não houver o que conferir, remove `acao-externa` e segue do ponto em que parou |
| Todos marcados, mas a conferência falha | Publica um novo comentário de ação só com os passos que faltam, mantém `acao-externa` e para |
| Algum item desmarcado e nenhum comentário do usuário depois do comentário de ação | Não faz nada na issue: diz no chat que a ação está pendente e para |
| Algum item desmarcado e um comentário do usuário depois do comentário de ação (por exemplo, "não consigo fazer o passo 2") | Lê o comentário. Se der para seguir por outro caminho, publica um novo comentário de ação. Se não der, trata como desvio relevante: remove `acao-externa`, aplica `escalonado` e comenta as opções, com uma recomendação |

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/status/estados.md` tem a label `acao-externa` (quem aplica: implementar e revisar; cor; significado) na tabela de labels, as linhas 1a e 1b na tabela de estados, logo depois da linha 1, e as três inconsistências da tabela acima. O comentário que começa com `<!-- fabrica:acao` conta como comentário do agente nas regras de estado. | manual — ler o diff de `estados.md` |
| CA2 | `scripts/acao-status.py <comentários.json>` lê a saída de `gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` e imprime uma linha `estado=<pendente\|concluida\|sem-comentario\|sem-itens\|etapa-invalida> etapa=<etapa ou -> marcados=<k> total=<n> url=<html_url ou ->`, usando o comentário de ação mais recente pela data de criação. | unitário — `bash scripts/test-acao-status.sh` |
| CA3 | Contagem: `- [ ]` conta como desmarcado; `- [x]` e `- [X]` contam como marcados; `*` no lugar de `-` e indentação também contam; linhas dentro de blocos de código cercados por ` ``` ` são ignoradas. Com `total=0` sai `sem-itens`. Com `total>0` e `marcados=total` sai `concluida`, e com `marcados<total` sai `pendente`. | unitário — casos em `scripts/test-acao-status.sh` |
| CA4 | Com dois comentários de ação, vale o mais recente: um antigo concluído e um novo pendente dão `pendente`, com o `url` do novo. Sem nenhum comentário de ação sai `sem-comentario`. Uma etapa fora de `implementar` e `revisar` no marcador dá `etapa-invalida`. A entrada pode vir em páginas (lista de listas, do `--slurp`) ou como lista simples. Arquivo ausente ou JSON inválido sai com código 2. | unitário — casos em `scripts/test-acao-status.sh` |
| CA5 | `skills/status/acao-externa.md` define o formato do comentário de ação: marcador com a etapa, motivo, checklist, frase final que manda marcar os itens e rodar `/fabrica:avancar <nº>`, e a regra de que nenhum item, motivo ou comentário de retomada traz o valor de um segredo, só o nome e onde cadastrar. | manual — ler o arquivo |
| CA6 | `skills/implementar/SKILL.md` e `skills/revisar/SKILL.md` têm o passo de parar por ação externa (commit e push, comentário no formato do CA5, `acao-externa`, linha de custo) e a retomada das quatro situações da tabela "Retomada". Uma ação externa não gera lição nem conta como rodada de correção. | manual — ler o diff das duas skills |
| CA7 | `/fabrica:status` coleta o estado da ação com o `acao-status.py` para cada issue com `acao-externa`, mostra a seção `## Ações externas` (item, etapa, `marcados/total` e link do comentário de ação) para as pendentes, mostra a concluída em "Esperando agente" com o comando da etapa do marcador e alerta as inconsistências do CA1. | issue de teste no fabrica com um comentário de ação e `acao-externa`, verificada com `claude --plugin-dir` na branch nos três casos (pendente, concluída, sem comentário) e fechada no fim com um comentário dizendo que era teste |
| CA8 | `/fabrica:avancar`: 1b entra na seleção e executa a etapa do marcador; 1a é estado do usuário; na ordem, 1b vai junto do grupo da etapa do marcador (`revisar` com 10 a 12, `implementar` com 8). | manual — ler o diff do `avancar` |
| CA9 | `skills/metricas/durations.py` conta `acao-externa` como portão do usuário em `esperando_voce`, e `skills/metricas/SKILL.md` diz isso. | unitário — novo caso em `bash scripts/test-durations.sh` |
| CA10 | `scripts/statusline.sh` conta a issue com `acao-externa` entre as que esperam o usuário. | unitário — novo caso em `bash scripts/test-statusline.sh` |
| CA11 | `scripts/setup-labels.sh` cria a label `acao-externa` a partir da tabela de `estados.md`, sem mudança no script, e a `description` do `/fabrica:setup` lista a label. | manual — `bash scripts/setup-labels.sh ftenorio99/fabrica` na branch imprime `ok acao-externa`, e a label aparece em `gh label list` |
| CA12 | O manual explica a ação externa: `docs/fluxo.md`, `docs/comandos.md` (implementar, revisar, status, avancar), `docs/glossario.md` e um guia novo `docs/guias/acao-externa.md`, listado no `docs/README.md`. O manual remete a `estados.md` e ao formato, sem copiar as tabelas. | manual — ler o diff de `docs/` |
| CA13 | `docs/adr/0012-acao-externa-com-checklist.md` registra a decisão, e `.claude-plugin/plugin.json` vai para a versão `0.37.0`. | manual — ler o ADR e o `plugin.json` |
| CA14 | A retomada de uma ação concluída, rodada de verdade, remove `acao-externa` e segue a etapa do marcador. | depois do merge — rodar a retomada exige uma issue com spec aprovada parada numa ação real; o primeiro caso previsto é o deploy da homologação do kairo |

## Fora de escopo
- Automatizar a própria ação externa (por exemplo, criar o projeto na Vercel pelo MCP).
- O disparo pelo dispatcher quando a checklist fica completa: a edição do comentário gera `issue_comment.edited`, e o tratamento dele fica para a #107 (veja "Riscos").
- A triagem e a spec publicarem comentário de ação. Elas continuam apontando uma ação prevista em "Riscos" ou num passo da spec.
- Trocar a "verificação pedida ao usuário" do `revisar`, que pede a saída de um comando, pela ação externa. Lá a resposta é um texto, e ela continua no `escalonado`.
- Contar ações externas no `/fabrica:retro` ou como coluna própria no `/fabrica:metricas`.

## Desenho técnico
**Arquivos e módulos:**
- `skills/status/estados.md`: label, linhas 1a e 1b, comentário de ação como comentário do agente, inconsistências.
- `skills/status/acao-externa.md` (novo): formato do comentário de ação, com exemplo.
- `scripts/acao-status.py` (novo) e `scripts/test-acao-status.sh` (novo).
- `skills/implementar/SKILL.md` e `skills/revisar/SKILL.md`: parar e retomar.
- `skills/status/SKILL.md`: coleta, classificação, seção "Ações externas", alertas.
- `skills/avancar/SKILL.md`: seleção, ordem e tabela de etapas.
- `skills/metricas/durations.py`, `skills/metricas/SKILL.md` e `scripts/test-durations.sh`.
- `scripts/statusline.sh` e `scripts/test-statusline.sh`.
- `skills/setup/SKILL.md`: só a `description`.
- `docs/fluxo.md`, `docs/comandos.md`, `docs/glossario.md`, `docs/README.md`, `docs/guias/acao-externa.md` (novo).
- `docs/adr/0012-acao-externa-com-checklist.md` (novo), `.claude-plugin/plugin.json`, `CLAUDE.md` (cita o novo teste em "Estrutura").

**Dados:** nenhum. O estado continua todo no GitHub.

**Interfaces:**
- `python3 scripts/acao-status.py <arquivo>`: entrada é o JSON de comentários da issue (lista de páginas ou lista simples, com `body`, `created_at` e `html_url`); saída é uma linha no formato do CA2, com código de saída 0. Um arquivo ausente ou JSON inválido sai com código 2 e mensagem no stderr.
- Marcador: `<!-- fabrica:acao etapa=<implementar|revisar> -->`, na primeira linha do corpo.

**Decisões:**
- Label nova `acao-externa`, aplicada e removida pela etapa (recomendação da triagem). O estado sai das labels, as linhas do `precisa-info` dependem de "resposta nova", que marcar a checklist não produz, e o `durations.py` e a statusline medem o portão pelas labels. Alternativa descartada: reusar o `precisa-info` e diferenciar pelo marcador, o que mexe nas linhas 3 e 4 e obriga o metricas a ler comentários.
- Só o `implementar` e o `revisar` publicam a ação (recomendação da triagem). São as etapas que executam comandos e já têm o padrão de parar e pedir algo ao usuário. Alternativa descartada: a spec também publicar a checklist antes da aprovação.
- A etapa vai no marcador, `etapa=<implementar|revisar>` (recomendação da triagem), no padrão dos marcadores com parâmetro (`fabrica:backlog item=<n>`, `fabrica:licao gatilho=<g>`). Alternativa descartada: inferir pelo último comentário do agente.
- As linhas novas ficam logo depois do `escalonado` (recomendação da triagem), numeradas 1a e 1b, para o bloqueio valer sobre o estado da etapa por baixo dele. A numeração com letra mantém os números 2 a 13, citados no `avancar`, no `status` e nas specs anteriores. Alternativas descartadas: inserir perto do `precisa-info`, o que deixaria a ação de fora quando a issue já tem `spec-aprovada` ou PR; e renumerar a tabela, o que muda referências em vários arquivos sem ganho.
- A contagem dos itens fica num script (`acao-status.py`) em vez de um texto de instrução: o `status`, o `avancar` e as duas etapas leem o mesmo resultado, e os casos de borda do CA3 e do CA4 ganham teste. Alternativa descartada: cada skill contar com `jq` e `grep`, com o risco de regras diferentes.
- O comentário de ação conta como comentário do agente. Senão, numa ação do `revisar`, a regra de retomada da verificação pedida ao usuário ("resposta do usuário depois do último comentário `<!-- fabrica:revisar -->`") leria o comentário de ação como resposta.
- Ação externa não gera lição. Ela não é uma falha da etapa, e uma ação previsível já aparece nos riscos da spec. Alternativa descartada: um gatilho `acao-externa` no formato de lição.
- O tempo entre o último item marcado e a retomada conta como espera do usuário, porque a label só sai na retomada. É a mesma aproximação do `precisa-info` (a label sai quando a triagem roda de novo).
- Registrar num ADR (recomendação da triagem), como a `em-andamento` (ADR 0003) e o atalho (ADR 0004).

**Fontes da documentação:**
- gh 2.104.0 — `gh api --help` (`--paginate`, `--slurp`), `gh issue edit --help` (`--add-label`, `--remove-label`), `gh secret list --help`, `gh variable list --help`.
- Python 3, só a biblioteca padrão (`json`, `re`, `sys`) — não verificada; o uso é básico.

**ADR:** [docs/adr/0012-acao-externa-com-checklist.md](../docs/adr/0012-acao-externa-com-checklist.md)

## Testes
- `bash scripts/test-acao-status.sh`: um caso por linha dos CA2 a CA4: pendente, concluída com `[x]` e com `[X]`, `*` e indentação, item dentro de bloco de código ignorado, sem itens, sem comentário, dois comentários de ação (vale o mais recente), etapa inválida, entrada paginada e simples, arquivo ausente (código 2).
- `bash scripts/test-durations.sh`: caso novo com `acao-externa` aplicada e removida, conferindo `esperando_voce` (CA9).
- `bash scripts/test-statusline.sh`: caso novo com uma issue com `acao-externa` (CA10).
- Os demais testes da fábrica continuam passando: `test-protect-main.sh`, `test-setup-isolation.sh`, `test-sbx-context.sh`, `test-protect-production.sh`, `test-migrate-native-sandbox.sh`, `test-costs.sh`, `test-stage-usage.sh`, `test-check-gh.sh`.
- Manual (CA7): numa issue de teste no fabrica, publicar um comentário de ação com dois itens e aplicar `acao-externa`. Rodar `/fabrica:status fabrica` com `claude --plugin-dir` na branch: a issue aparece em "Ações externas" com `0/2`. Marcar os dois itens: aparece em "Esperando agente" com `/fabrica:implementar <nº>`. Apagar o comentário: aparece o alerta de inconsistência. Fechar a issue com um comentário dizendo que era teste.
- Manual (CA11): `bash scripts/setup-labels.sh ftenorio99/fabrica` na branch.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Dispatcher (#107):** marcar o item edita o comentário de ação e gera `issue_comment.edited` num comentário com marcador `<!-- fabrica:`, que a regra contra cascata do PRD ignora. A #107 precisa tratar esse evento como gesto do usuário quando o `acao-status.py` passar a dar `concluida`.
- **Edição do comentário:** o GitHub não registra na timeline quando cada item é marcado. O estado depende só do conteúdo atual do comentário, e o tempo da ação é medido pela label.
- **Segredo colado por engano:** se o usuário colar um valor num comentário, a etapa não o repete em comentário, commit nem log. O formato pede isso explicitamente.
- **Tamanho:** a mudança passa por muitos arquivos. Se a implementação crescer além do estimado, separar o manual num PR `docs` seguinte é a saída menos arriscada.

## Histórico
- 2026-11-17: criação.
- 2026-11-17: aprovada.
