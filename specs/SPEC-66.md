# SPEC-66: Recuo da linha de custo ignora a chamada anterior por causa do fim cortado em segundos

**Issue:** #66 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** aprovada · **Atualizada em:** 2026-11-05

## Contexto
O `scripts/stage-usage.py` recua o início da etapa até o marco mais recente que não seja posterior ao `--since` (SPEC-62). Os marcos são a mensagem do usuário que disparou a etapa e a chamada anterior do próprio script. Quando o `implementar` segue para o `revisar`, o `--since` do `revisar` é o `fim` da linha do `implementar`, e esse `fim` é cortado para segundos. No PR #65, a chamada que fechou o `implementar` ficou no log às 02:39:00.195, e o `--since` do `revisar` foi 02:39:00. A chamada ficou fora da janela, o recuo foi até a mensagem do usuário, às 02:35:34, e a linha do `revisar` somou o `implementar` de novo.

## Objetivo
Na segunda de duas etapas seguidas, a linha de custo começa logo depois da chamada que fechou a primeira, mesmo com o `--since` cortado em segundos.

## Comportamento esperado
- **Margem para a chamada anterior:** o recuo aceita como marco uma chamada do `stage-usage.py` com `timestamp` até 1 s depois do `--since`.
- **Mensagem do usuário:** continua valendo como marco só até o `--since`, sem margem.
- **Escolha do marco:** continua valendo o mais recente. O início é o da chamada mais 1 ms, como hoje. Ele pode ficar até 1 s depois do `--since`. Nesse caso, a soma deixa de fora a resposta que fechou a etapa anterior, que pertence a ela.
- **Chamada fora da margem:** uma chamada mais de 1 s depois do `--since` não vira marco. Ela é da própria etapa, e não da anterior.
- **`--exact`:** continua desligando o recuo.
- **Linha impressa:** o `inicio` continua cortado em segundos. O formato da linha não muda.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com `--since` em segundos inteiros e uma chamada anterior do script 0,2 s depois dele, o `inicio` é o segundo da chamada. A soma inclui só as respostas posteriores à chamada, e não as anteriores nem a mensagem do usuário de antes. | unitário (`scripts/test-stage-usage.sh`) |
| CA2 | Uma chamada do script 2 s depois do `--since` não vira marco, e o recuo vai até o marco anterior. | unitário |
| CA3 | Uma mensagem do usuário 0,5 s depois do `--since` não vira marco. | unitário |
| CA4 | Os 26 casos atuais de `test-stage-usage.sh` continuam passando, e a versão do plugin sobe um patch sobre a da `main` no momento do merge. | unitário e manual: leitura |

## Fora de escopo
- Gravar o `inicio` e o `fim` com milissegundos.
- Corrigir linhas já publicadas.
- Mudar as instruções das skills de etapa.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/stage-usage.py`: em `effective_start`, a janela da chamada do script vai até `since + 1 s`, e a da mensagem do usuário continua até `since`. Uma constante `CALL_MARGIN = timedelta(seconds=1)` e o docstring explicam o motivo.
- `scripts/test-stage-usage.sh`: os casos de CA1 a CA3.
- `.claude-plugin/plugin.json`: um patch.

**Interfaces:** não mudam.

**Decisões:**
- **Margem de 1 s só para a chamada do script:** o `fim` é cortado para segundos, então a chamada que fechou a etapa anterior fica no máximo 1 s depois dele. A mensagem do usuário não tem esse problema e continua sem margem. Alternativa descartada: imprimir o `fim` com milissegundos, que muda o formato da linha e o `costs.py`.
- **Margem fixa, e não ler o `fim` original:** o script não tem como saber os milissegundos que o `fim` da etapa anterior perdeu. Alternativa descartada: guardar o `fim` exato num arquivo, que cria estado fora do log.

**Fontes da documentação:** nenhuma biblioteca nova. O formato do log foi conferido no log desta sessão, nas entradas das 02:38:57 às 02:39:01 de 2026-11-05.

**ADR:** nenhum.

## Testes
- `bash scripts/test-stage-usage.sh`: os casos atuais e os novos de CA1 a CA3, com `timestamp` em milissegundos no log de exemplo.
- `bash scripts/test-costs.sh` e `bash scripts/test-protect-main.sh` continuam passando.
- O repositório não tem `make lint`, `make test` nem CI.

## Riscos e dúvidas
- **Etapa de menos de 1 s:** se uma etapa durasse menos de 1 s, a própria chamada que a fecha cairia na margem, e a soma sairia vazia. Isso não acontece numa etapa real, que tem pelo menos uma resposta antes da chamada.
- **Conflito com o PR #65:** o PR #65 sobe a `version` para 0.15.0. Esta issue acerta a versão no merge.

## Histórico
- 2026-11-05: criação.
- 2026-11-05: aprovada.
