# SPEC-58: Custo em tokens e duração real por etapa nos comentários da fábrica

**Issue:** #58 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-04

## Contexto
O `/fabrica:metricas` (#53) mede o tempo de cada issue pelos eventos do GitHub. Dois dados ainda faltam. O custo em tokens aparece como "não medido". O tempo "com o agente" mistura a fila, que é a espera até o comando ser rodado, com o trabalho, porque só o fim de cada etapa fica registrado. A triagem da #58 confirmou uma fonte no terminal: o log da sessão do Claude Code traz o `timestamp` e o `usage` de cada resposta do modelo, e os subagentes têm logs próprios na pasta da sessão.

## Objetivo
Cada execução de etapa registra no próprio comentário o início, o fim e os tokens que consumiu. Com isso, o `/fabrica:metricas` mostra os tokens por issue, marco e repositório e divide "Com o agente" em fila e trabalho.

## Comportamento esperado

### Registro de custo
Cada execução de `triagem`, `spec`, `implementar` e `revisar` termina com uma **linha de custo** no comentário com marcador que ela publica. A linha é um comentário HTML, numa linha própria, no fim do corpo:

```
<!-- fabrica:custo etapa=<etapa> inicio=<ISO UTC> fim=<ISO UTC> entrada=<n> saida=<n> cache_escrita=<n> cache_leitura=<n> -->
```

Sem fonte de tokens, a linha mantém `inicio` e `fim` e troca os quatro contadores por `tokens=nao-medido`.

| Etapa | Onde vai a linha |
|---|---|
| `triagem` | no comentário `<!-- fabrica:triagem -->`, com ou sem perguntas |
| `spec` | no comentário `<!-- fabrica:spec -->` |
| `implementar` | se escalar, no comentário de escalonamento na issue. Se seguir para a revisão, na resposta `<!-- fabrica:revisar -->` do PR publicada nessa mesma execução, antes da linha do `revisar` |
| `revisar` | na resposta `<!-- fabrica:revisar -->` do PR (a âncora), uma por execução |

Regras do intervalo:
- **Início:** é o primeiro passo de cada skill, `date -u +%Y-%m-%dT%H:%M:%SZ`, guardado para o fim. No `revisar`, é o mesmo instante da coleta, o da linha `**Pedidos lidos até:**`. Quando o `implementar` passa para o `revisar`, o início do `revisar` é o fim do `implementar`, e os intervalos não se sobrepõem.
- **Fim:** o instante logo antes de publicar o comentário.
- **Fora do registro:**
  - comentários de lição;
  - o comentário `<!-- fabrica:revisar -->` na issue que só avisa do PR aberto, para não contar a etapa duas vezes;
  - execuções que param nos pré-requisitos sem comentar.
- Cada execução gera uma linha nova. Uma etapa rodada duas vezes na mesma issue tem duas linhas, em comentários diferentes.

### Script de soma
`scripts/stage-usage.py --stage <etapa> --since <ISO>` imprime a linha de custo:
- **Arquivos lidos:** procura `$CLAUDE_CODE_SESSION_ID.jsonl` nas pastas de `~/.claude/projects/` e lê também `<pasta da sessão>/subagents/*.jsonl`.
- **O que entra:** as mensagens com `message.usage` e `timestamp` entre `--since` e o instante da chamada, que vira o `fim`.
- **Uma resposta, uma contagem:** a mesma resposta aparece em várias linhas com o mesmo `message.id` e o mesmo `usage`, então cada `message.id` conta uma vez.
- **Contadores:**
  - `entrada` = `input_tokens`;
  - `saida` = `output_tokens`;
  - `cache_escrita` = `cache_creation_input_tokens`;
  - `cache_leitura` = `cache_read_input_tokens`.

  Um campo ausente conta 0.
- **Sem log:** sem a variável `CLAUDE_CODE_SESSION_ID`, sem o arquivo da sessão ou sem nenhuma mensagem legível no intervalo, imprime a linha com `tokens=nao-medido`. Sai com código 0 em todos esses casos, para nunca derrubar a etapa.
- Só lê. Não grava nada fora da saída padrão.

### Métricas
O `/fabrica:metricas` lê as linhas de custo nos comentários da issue e do PR, que ele já coleta, com um script novo, `skills/metricas/costs.py`.

| Coluna | Cálculo |
|---|---|
| Tokens | soma de entrada, saída e cache das linhas da issue e do PR, no formato `1,2M` ou `850k` |
| Trabalho | soma de `fim − inicio` das linhas |
| Fila | "Com o agente" menos o trabalho |

- **Issue medida:** cada comentário `<!-- fabrica:triagem -->` e `<!-- fabrica:spec -->` da issue e cada resposta `<!-- fabrica:revisar -->` do PR tem uma linha de custo com tokens. Numa issue que não é medida, as três colunas mostram "não medido". Isso vale para as issues entregues antes desta mudança e para as que têm alguma linha `tokens=nao-medido`.
- **Agregados:** por repositório e por marco, Tokens é a soma das issues medidas e Trabalho e Fila são medianas. As tabelas ganham uma coluna "Medidas", com quantas issues entraram nessas três colunas.
- **Comparação:** ganha as linhas Tokens e Trabalho.
- **Nota de tokens:** troca o texto atual por "Tokens e trabalho só contam as issues medidas: as etapas registradas a partir da versão 0.13.0 da fábrica, rodadas no terminal. Etapas no GitHub Actions ainda não são medidas."

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com um log de exemplo que repete o mesmo `message.id` em 3 linhas, mais um subagente com 2 respostas e uma resposta fora do intervalo, `stage-usage.py` soma cada `message.id` uma vez, inclui o subagente, exclui a resposta fora do intervalo e imprime a linha no formato da spec. | unitário (`scripts/test-stage-usage.sh`) |
| CA2 | Sem `CLAUDE_CODE_SESSION_ID`, com o arquivo da sessão ausente ou com uma linha de JSON inválida, o script sai com código 0. Sem dado aproveitável, imprime `tokens=nao-medido`; uma linha inválida é ignorada e o resto é somado. | unitário |
| CA3 | Os `SKILL.md` de `triagem`, `spec`, `implementar` e `revisar` guardam o início no primeiro passo e terminam o comentário da tabela "Onde vai a linha" com a saída do script. O `implementar` encadeado passa o seu fim como início do `revisar`. | manual: leitura dos quatro arquivos |
| CA4 | Numa execução real de `/fabrica:triagem` nesta sessão de teste, o comentário publicado tem a linha de custo com tokens maiores que zero. | manual |
| CA5 | `costs.py`, com os comentários de uma issue medida e de uma não medida, devolve os tokens e o trabalho da primeira e `null` na segunda. O critério de issue medida segue a spec. | unitário (`scripts/test-costs.sh`) |
| CA6 | A saída do `/fabrica:metricas` mostra as colunas Tokens, Trabalho e Fila, a coluna Medidas nos agregados e a nota nova de tokens. As issues antigas aparecem como "não medido". | manual: rodar a skill |
| CA7 | `skills/status/estados.md` cita a linha `<!-- fabrica:custo` e diz que ela não muda o estado nem o tipo do comentário. `docs/comandos.md` descreve as colunas novas do `/fabrica:metricas` e o registro de custo. | manual: leitura |
| CA8 | `.claude-plugin/plugin.json` sobe para 0.13.0. | manual |

## Fora de escopo
- Custo em dinheiro, que depende do plano e do modelo.
- Medir etapas no GitHub Actions, que ainda não existe (Fase 1). A limitação fica na nota do `/fabrica:metricas`.
- `/fabrica:backlog`: uma execução cuida de vários itens, e não de uma issue. O custo dela fica para quando houver métrica por repositório, fora da tabela por issue.
- Reconstruir o custo de issues já entregues a partir de logs antigos.
- Banco de dados ou painel externo (Fase 2).

## Desenho técnico
**Arquivos e módulos:**
- `scripts/stage-usage.py` (novo) e `scripts/test-stage-usage.sh` (novo, com logs de exemplo criados numa pasta temporária).
- `skills/metricas/costs.py` (novo) e `scripts/test-costs.sh` (novo).
- `skills/triagem/SKILL.md`, `skills/spec/SKILL.md`, `skills/implementar/SKILL.md` e `skills/revisar/SKILL.md`: guardam o início e acrescentam a linha de custo. As skills chamam o script pelo caminho `<diretório base desta skill>/../../scripts/stage-usage.py`, como o `setup` faz com os seus.
- `skills/metricas/SKILL.md`: a coleta das linhas, as colunas novas e a nota.
- `skills/status/estados.md`, `docs/comandos.md` e `.claude-plugin/plugin.json`.

**Interfaces:**
- `python3 stage-usage.py --stage <triagem|spec|implementar|revisar> --since <ISO UTC>`. Imprime uma linha de custo e sai com código 0.
- `python3 costs.py <comentarios-issue.json> <comentarios-pr.json | ->`. Imprime um JSON com `tokens`, `trabalho_min` e `medida`, em que tokens e trabalho valem `null` quando `medida` é `false`. O `-` indica que não há PR.

**Decisões:**
- **Linha de custo em comentário HTML** no fim do comentário da etapa: a leitura por script fica estável e o comentário continua limpo para quem lê. Alternativa descartada: uma linha visível como "**Custo:** 12min · 1,2M tokens", que polui as respostas e é mais frágil de ler.
- **Intervalo de tempo, e não o campo `attributionSkill` do log:** o campo existe, mas não é documentado e não separa duas issues da mesma etapa na mesma sessão. O intervalo separa. Alternativa descartada: filtrar pelo `attributionSkill`.
- **Subagentes contam na etapa que os chamou:** o revisor é parte do custo do `revisar`. Alternativa descartada: medir só a sessão principal, o que subestima a revisão.
- **Backlog fora do registro**, como diz "Fora de escopo". A issue citava o backlog. Ele é tirado porque não há issue a que atribuir o custo, e esta decisão precisa da sua confirmação.
- **Issue medida só com todas as etapas registradas:** somar etapas parciais misturaria issues meio medidas com as completas nas medianas. Alternativa descartada: somar o que houver e marcar "parcial".

**Fontes da documentação:**
- Formato do log do Claude Code (`~/.claude/projects/<pasta>/<sessão>.jsonl`, `subagents/`): não verificada. Não há documentação pública. O formato foi conferido no log desta máquina em 2026-11-04 (Claude Code com `version` no próprio log).

**ADR:** nenhum.

## Testes
- `bash scripts/test-stage-usage.sh`: cobre CA1 e CA2, com `HOME` apontando para uma pasta temporária com logs de exemplo.
- `bash scripts/test-costs.sh`: cobre CA5.
- Verificações manuais: CA3, CA4, CA6, CA7 e CA8, e um `bash scripts/test-protect-main.sh` para conferir que nada quebrou.
- O repositório não tem `make lint`, `make test` nem CI.

## Riscos e dúvidas
- O formato do `.jsonl` pode mudar entre versões do Claude Code. O script tolera campos ausentes e linhas inválidas e cai em `tokens=nao-medido`.
- A resposta que roda o `date` do início tem `timestamp` anterior a ele e fica de fora da etapa. A perda é de uma resposta por execução, e o trabalho em minutos não muda.
- Uma conversa compactada continua no mesmo arquivo de sessão. Uma retomada em outro processo, como `claude --resume`, pode trocar de `CLAUDE_CODE_SESSION_ID`. Nesse caso, a etapa só soma o que estiver no arquivo da sessão atual.
- O `implementar` encadeado publica duas linhas na mesma resposta do PR. O `costs.py` soma as linhas sem tratá-las como duplicadas.

## Histórico
- 2026-11-04: criação.
- 2026-11-04: aprovada.
