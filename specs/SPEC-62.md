# SPEC-62: Linha de custo sai incompleta porque o log da sessão é gravado com atraso

**Issue:** #62 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-04

## Contexto
O `scripts/stage-usage.py` (SPEC-58) soma os tokens da etapa lendo o log da sessão do Claude Code no instante em que é chamado. A linha de custo sai incompleta por duas perdas:
- **Atraso na gravação:** o Claude Code grava as respostas no `.jsonl` com atraso, mas com o `timestamp` original. Na triagem da #55, as entradas das 20:36:34 às 20:36:47 ainda não estavam no arquivo às 20:36:49, e a linha saiu `tokens=nao-medido`. Rodado de novo 30 s depois, o mesmo comando somou ~960k tokens.
- **Primeira resposta:** a resposta que roda o `date` do início tem `timestamp` anterior a ele e fica fora do intervalo. Na triagem da #55, essa resposta tinha toda a leitura da issue.

## Objetivo
A linha de custo passa a contar todas as respostas da etapa, da primeira à que chama o script, sem somar a etapa anterior quando duas etapas rodam em sequência.

## Comportamento esperado

### Espera pelo log
- Depois de fixar o `fim`, o instante da chamada, o script espera o log principal da sessão ter uma entrada com `timestamp` de no máximo 10 s antes do `fim`. Essa entrada é a da própria resposta que chamou o script. Ele confere de 0,5 em 0,5 s, até 30 s no máximo.
- Quando a entrada aparece, o script soma. Se os 30 s acabam antes, ele soma o que houver e acrescenta `parcial=sim` à linha.
- Sem variável de sessão, sem arquivo ou com `--since` inválido, ele não espera: imprime `tokens=nao-medido` na hora, como hoje.
- O código de saída continua sempre 0.
- **Limite configurável para os testes:** a variável `FABRICA_STAGE_USAGE_TIMEOUT` troca os 30 s, em segundos.

### Início efetivo
O script recua o `inicio` para o marco mais recente que não seja posterior a `--since`, dentre:
- a última mensagem do usuário que não é resultado de ferramenta, ou seja, o comando ou o pedido que disparou a etapa;
- a última chamada anterior do próprio `stage-usage.py` na sessão, que é o fim da etapa anterior. Isso cobre o `implementar` → `revisar` e o `/fabrica:avancar`, em que várias etapas rodam no mesmo turno.

Regras do recuo:
- O recuo é de no máximo 30 min. Sem marco nessa janela, vale o próprio `--since`.
- A linha mostra em `inicio` o início efetivo, e é dele que contam os tokens e o trabalho.
- `--exact` desliga o recuo. O `revisar` encadeado continua recebendo o `fim` do `implementar` como `--since`, e o recuo pela chamada anterior já impede a sobreposição. Por isso o `--exact` existe só para os testes e para casos manuais.

### Métricas
Uma linha com `parcial=sim` conta tokens e trabalho, mas a issue deixa de ser medida, como acontece com `tokens=nao-medido`, porque a soma pode estar abaixo do real. Assim, o `costs.py` só considera medida a issue sem nenhuma linha `parcial=sim`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com um log em que as últimas entradas são escritas 2 s depois de o script começar, por um processo em segundo plano no teste, o script espera e soma tudo, sem `parcial`. | unitário (`scripts/test-stage-usage.sh`) |
| CA2 | Com `FABRICA_STAGE_USAGE_TIMEOUT=1` e um log sem entrada recente, o script termina em até 3 s, soma o que há e imprime `parcial=sim`, com código 0. | unitário |
| CA3 | Sem variável de sessão ou sem arquivo, o script imprime `tokens=nao-medido` em menos de 1 s, sem esperar. | unitário |
| CA4 | Uma resposta com `timestamp` entre a mensagem do usuário que disparou a etapa e o `--since` entra na soma, e o `inicio` impresso é o da mensagem do usuário. | unitário |
| CA5 | Com uma chamada anterior de `stage-usage.py` no log depois da mensagem do usuário, as respostas anteriores a essa chamada ficam de fora, e o `inicio` é o da chamada. Com `--exact`, o recuo não acontece. | unitário |
| CA6 | `costs.py` trata uma linha com `parcial=sim` como issue não medida. | unitário (`scripts/test-costs.sh`) |
| CA7 | Os casos atuais de `test-stage-usage.sh` (11) e de `test-costs.sh` (4) continuam passando. | unitário |
| CA8 | A nota de tokens do `skills/metricas/SKILL.md` cita a linha `parcial=sim`, e a versão do plugin sobe um patch sobre a da `main` no momento do merge. | manual: leitura |

## Fora de escopo
- Corrigir as linhas já publicadas, como a da triagem da #55.
- Mudar as instruções das skills de etapa: elas continuam passando o `date` do início como `--since`.
- Medir etapas no GitHub Actions.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/stage-usage.py`: a espera, o recuo do início, `--exact` e `parcial=sim`.
- `scripts/test-stage-usage.sh`: os casos novos.
- `skills/metricas/costs.py` e `scripts/test-costs.sh`: o tratamento de `parcial=sim`.
- `skills/metricas/SKILL.md`: a nota de tokens e a regra de issue medida.
- `.claude-plugin/plugin.json`.

**Interfaces:**
- `python3 stage-usage.py --stage <etapa> --since <ISO UTC> [--exact]`.
- A linha de custo ganha o campo opcional `parcial=sim`, depois dos contadores.
- O resto do formato não muda.

**Decisões:**
- **Esperar uma entrada com `timestamp` de até 10 s antes do `fim`:** essa entrada é a da resposta que chamou o script, e só é gravada depois das anteriores, então é um sinal direto de que o log alcançou o presente. Alternativa descartada: esperar o arquivo parar de crescer, porque na #55 a gravação atrasou mais de 10 s sem nenhuma escrita no meio.
- **Recuar até a mensagem do usuário ou até a chamada anterior do script:** os dois marcos estão no próprio log, sem estado novo fora dele. A chamada anterior evita somar a etapa anterior no `implementar` → `revisar` e no `avancar`. Alternativa descartada: uma tolerância fixa antes do `--since`, que somaria parte da etapa anterior quando duas rodam em sequência.
- **`parcial=sim` tira a issue da medição:** uma soma abaixo do real deslocaria as medianas sem aviso. Alternativa descartada: contar a linha parcial normalmente.

**Fontes da documentação:** formato do log do Claude Code, não documentado. Ele foi conferido no log desta máquina em 2026-11-04: entradas `type: user`, mensagens com `tool_result` no `content` e entradas `assistant` com `message.content[].type == "tool_use"` e `input.command`.

**ADR:** nenhum.

## Testes
- `bash scripts/test-stage-usage.sh`: os 11 casos atuais e os novos casos de CA1 a CA5. O CA1 usa um processo em segundo plano que acrescenta as últimas linhas ao log de exemplo depois de 2 s.
- `bash scripts/test-costs.sh`: os 4 casos atuais e o caso de `parcial=sim`.
- `bash scripts/test-protect-main.sh`.
- O repositório não tem `make lint`, `make test` nem CI.

## Riscos e dúvidas
- Se o comando Bash que chama o script demorar mais de 10 s antes da chamada, por exemplo com um `sleep` ou um passo longo antes, a entrada da resposta fica mais velha que a janela. Nesse caso, o script espera até o limite e marca `parcial=sim`, sem errar a soma. As skills já chamam o script logo antes de publicar.
- O formato do log pode mudar. O script tolera campos ausentes e cai em `parcial=sim` ou `tokens=nao-medido`.
- Esta branch sai da `main` sem o #63. A versão do plugin é acertada no merge.

## Histórico
- 2026-11-04: criação.
