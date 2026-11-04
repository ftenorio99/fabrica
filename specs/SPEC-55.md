# SPEC-55: Comando avancar que executa as etapas de agente e para nos portões humanos

**Issue:** #55 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-04

## Contexto
Hoje o usuário move cada issue à mão: lê o `/fabrica:status` e digita o comando da etapa seguinte. A tabela de `skills/status/estados.md` já diz, para cada estado, quem age e qual é o próximo passo, e foi escrita para servir também ao dispatcher da Fase 1. O `/fabrica:metricas` mostrou o custo disso: na #49, o agente trabalhou 5 min e a issue esperou 2h44 na fila. Este é o primeiro degrau, ainda local. O disparo por label no GitHub Actions fica para outra issue e reaproveita esta lógica.

## Objetivo
`/fabrica:avancar [nº]` executa as etapas de agente pendentes no repositório atual e para sozinho quando cada issue chega a um portão do usuário.

## Comportamento esperado

### Chamada
| Chamada | O que faz |
|---|---|
| `/fabrica:avancar` | todas as issues abertas com `agente` do repositório atual, na ordem abaixo |
| `/fabrica:avancar 55` | só a #55 |
| `/fabrica:avancar 55` com a #55 num estado do usuário | não executa nada e mostra o estado e o que o usuário faz |

O repositório é o do diretório atual (`gh repo view --json nameWithOwner`). Fora de um repositório, a skill para e diz isso.

### Seleção e ordem
- O estado de cada issue sai de `estados.md`, coletado como no passo 1 do `/fabrica:status`, limitado ao repositório atual. O `avancar` não copia a tabela: ele a lê.
- Entram só os estados em que o agente age: 2, 4, 5, 6, 8, 10, 11 e 12.
- Ficam de fora:
  - issues com `em-andamento` aplicada há menos de 2 h, que outra sessão está avançando;
  - issues com inconsistência de `estados.md`, que vão para o relatório como alerta.
- **Ordem:** primeiro a mais perto do merge. Os estados 10, 11 e 12 vêm antes do 8, que vem antes do 6, 5, 4 e 2. No mesmo grupo, vai antes o menor número de issue.

### Etapa de cada estado
| Estado | Etapa executada |
|---|---|
| 2 Aguardando triagem | `triagem <nº>` |
| 4 Respostas recebidas | `spec <nº>` se o último comentário do agente antes da resposta for de spec; senão, `triagem <nº>` |
| 5 Triada | `spec <nº>` |
| 6 Ajuste da spec pedido | `spec <nº> <ajustes>`, com os ajustes tirados dos comentários do usuário posteriores ao último marcador de spec |
| 8 Em implementação | `implementar <nº>`, que já segue para o `revisar` |
| 10, 11 e 12 | `revisar <nº>` |

- **Como executar:** as etapas têm `disable-model-invocation: true` e não podem ser acionadas pela ferramenta Skill. O `avancar` lê `<diretório base desta skill>/../<etapa>/SKILL.md` e segue as instruções dele, com os argumentos da tabela, como o `implementar` já faz com o `revisar`. Cada etapa continua publicando o que já publica, com a própria linha de custo. O `avancar` não comenta na issue e não publica linha de custo.
- **Sem conversa no chat:** a etapa executada pelo `avancar` não pergunta nada no chat. O que ela perguntaria vai para a issue, como as etapas já fazem. As mensagens que ela daria ao usuário entram no relatório final.

### Laço
Para cada issue selecionada:
1. Aplica `em-andamento`, que é o sinal da etapa em curso.
2. Executa a etapa do estado atual.
3. Remove `em-andamento` e relê o estado.
4. Repete enquanto o estado novo for de agente e o teto não tiver sido atingido.

O laço da issue para quando:
- **Portão do usuário:** a issue chega a um estado em que o usuário age (1, 3, 7, 9 ou 13). Este é o fim normal.
- **Sem avanço:** depois da etapa, a issue continua no mesmo estado. Isso cobre, por exemplo, uma etapa que parou num pré-requisito, como o limite de 3 em andamento ou uma label que falta. O relatório traz o motivo que a etapa deu.
- **Falha:** a etapa terminou com erro. Mesmo assim, `em-andamento` é removida.
- **Inconsistência:** o estado relido tem uma inconsistência de `estados.md`.

Uma issue parada não interrompe as outras: o `avancar` segue para a próxima.

**Teto:** no máximo 4 etapas por execução, somando todas as issues. O `implementar` encadeado com o `revisar` conta como uma só. Ao chegar ao teto, o `avancar` termina a etapa em curso, não começa outra e diz no relatório o que ficou para a próxima execução.

### Etapa em andamento (`em-andamento`)
- **Quem aplica:** só o `avancar`, no início de cada etapa. Ele remove a label ao fim da etapa, com sucesso ou falha.
- **O que a outra sessão faz:** uma issue com `em-andamento` aplicada há menos de 2 h fica de fora. O horário é o do último evento `labeled em-andamento` da timeline.
- **Label esquecida:** com mais de 2 h, a label é considerada esquecida, por exemplo numa sessão que morreu no meio. O `avancar` pode pegar a issue e o relatório avisa.
- **Antes de começar:** o `avancar` relê as labels logo antes de aplicar `em-andamento`. Se outra sessão aplicou a label nesse meio-tempo, ele pula a issue.
- **Fora do `avancar`:** os comandos manuais (`/fabrica:triagem` etc.) não aplicam nem conferem a label. A proteção vale entre execuções do `avancar` e, depois, para o Actions.
- **No `/fabrica:status`:** a issue com `em-andamento` recente aparece como "Em andamento", sem comando sugerido. Com a label esquecida, aparece um alerta.

### Relatório
No chat, ao fim:

```markdown
## Avanço
| Issue | Caminho | Parou em | O que você faz |
|---|---|---|---|
| [fabrica#62](url) Título | Aguardando triagem → Triada → Spec para aprovar | Spec para aprovar | Revisar `specs/SPEC-62.md` e aplicar `spec-aprovada` |
| [fabrica#55](url) Título | Em implementação | Em implementação (sem avanço) | Ver o motivo: limite de 3 em andamento |

**Etapas executadas:** 3 de 4.
- <alertas: inconsistências, `em-andamento` esquecida, issues que ficaram para a próxima execução>
```

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/avancar/SKILL.md` existe, com `disable-model-invocation: true`, `argument-hint: "[número da issue]"` e um `description` que diz o que a skill faz e quando usar. | manual: leitura |
| CA2 | A skill manda ler `estados.md` e a coleta do `/fabrica:status`, sem copiar a tabela de estados. Ela tem a tabela "Etapa de cada estado" e a ordem de seleção desta spec. | manual: leitura |
| CA3 | A skill nunca aplica `agente` nem `spec-aprovada`, nunca faz merge e nunca responde no lugar do usuário. Essas regras estão escritas na seção "Regras". | manual: leitura |
| CA4 | Numa issue real com `agente` e sem triagem, escolhida pelo usuário, `/fabrica:avancar <nº>` executa a triagem e a spec e para em "Spec para aprovar" (ou em "Perguntas abertas", se a triagem tiver perguntas). A label `em-andamento` não fica na issue no fim, e o relatório mostra o caminho. | manual |
| CA5 | Numa issue num estado do usuário, `/fabrica:avancar <nº>` não executa nenhuma etapa, não muda labels e mostra o estado e o que o usuário faz. | manual |
| CA6 | As regras de parada e o teto de 4 etapas estão na skill, cobrindo portão, sem avanço, falha e inconsistência. "Sem avanço" cita o caso de pré-requisito não atendido. | manual: leitura |
| CA7 | `estados.md` tem a label `em-andamento` na tabela de labels, com quem aplica `avancar` e uma cor. Tem também a regra das 2 h e a nova inconsistência "`em-andamento` aplicada há mais de 2 h". `bash scripts/setup-labels.sh --help`, ou uma execução de teste, lê a label nova sem erro. | manual |
| CA8 | O `/fabrica:status` mostra a issue com `em-andamento` recente como "Em andamento", sem comando, e alerta a label esquecida. | manual: leitura do `skills/status/SKILL.md` e do `estados.md` |
| CA9 | `docs/comandos.md` tem a seção `/fabrica:avancar [número da issue]`. `docs/fluxo.md` cita o `avancar` como alternativa a digitar cada comando. `docs/principios.md` continua dizendo que só o `status` e o `metricas` são chamados pelo Claude. `docs/README.md` conta 11 skills. | manual: leitura |
| CA10 | `.claude-plugin/plugin.json` sobe para 0.14.0, e `bash scripts/test-protect-main.sh` continua passando. | manual |

## Fora de escopo
- GitHub Actions, runner no Hetzner e disparo por label (próximo degrau da Fase 1).
- Execução em paralelo com subagentes (#16).
- Fazer os comandos manuais aplicarem ou respeitarem `em-andamento`.
- Teto configurável por argumento.
- Mudar o comportamento das etapas (triagem, spec, implementar, revisar).

## Desenho técnico
**Arquivos e módulos:**
- `skills/avancar/SKILL.md` (novo).
- `skills/status/estados.md`: a label `em-andamento`, a regra das 2 h e a inconsistência nova. A tabela de estados não ganha linha nova: a issue continua no seu estado, e a label só marca que uma sessão está nele. As notas "(se nenhuma sessão estiver nele)" dos estados 8 e 12 passam a remeter à label.
- `skills/status/SKILL.md`: na classificação, a issue com `em-andamento` recente mostra "Em andamento" no lugar do comando, e o alerta da label esquecida.
- `docs/comandos.md`, `docs/fluxo.md`, `docs/README.md` e `docs/glossario.md` (o termo `em-andamento`).
- `.claude-plugin/plugin.json`.
- `docs/adr/0003-sinal-de-etapa-em-andamento.md` (novo, status `proposto`).

**Interfaces:** `/fabrica:avancar [nº]`. A label nova, `em-andamento`, é criada pelo `scripts/setup-labels.sh`, que já lê a tabela de labels do `estados.md`. O script não muda.

**Decisões:**
- **Etapa em andamento como label, com validade de 2 h pelo horário do evento na timeline:** o `status`, outra sessão e o Actions a leem sem esforço, e a timeline dá o horário de graça. Alternativas descartadas: um comentário de início com marcador, que entraria nas regras de "último comentário do agente" de `estados.md`; e um lock na branch, que não existe antes da spec. Essa decisão vale também para o Actions, por isso tem o [ADR 0003](../docs/adr/0003-sinal-de-etapa-em-andamento.md).
- **Mais perto do merge primeiro:** fecha ciclos e libera vagas do limite de 3 em andamento antes de abrir trabalho novo. Alternativa descartada: a ordem por número, que deixaria PRs esperando atrás de triagens.
- **Teto de 4 etapas por execução:** cobre duas issues novas até a spec, ou uma implementação com revisão e mais duas etapas curtas, sem encher o contexto da sessão. Alternativa descartada: rodar sem teto até tudo parar, que arrisca uma compactação no meio de uma implementação.
- **Uma issue parada não interrompe as outras:** a falha de uma issue não deve segurar o trabalho independente. Alternativa descartada: parar tudo na primeira falha.
- **Etapas seguidas pelo `SKILL.md`, e não pela ferramenta Skill:** a ferramenta Skill não aciona as etapas com `disable-model-invocation`, e tirar essa proteção deixaria o Claude começar etapas sozinho. É o mesmo padrão do `implementar` com o `revisar`.

**Fontes da documentação:** nenhuma biblioteca envolvida.

**ADR:** [docs/adr/0003-sinal-de-etapa-em-andamento.md](../docs/adr/0003-sinal-de-etapa-em-andamento.md)

## Testes
- CA1, CA2, CA3, CA6, CA8 e CA9: leitura dos arquivos.
- CA4: numa issue real que o usuário puxar com `agente` (por exemplo, a #62), rodar o `avancar` pelo plugin da branch (`claude --plugin-dir ~/projetos/fabrica`) e conferir os comentários, as labels e o relatório.
- CA5: rodar o `avancar` numa issue num estado do usuário, como a própria #55 em "Spec para aprovar", e conferir que nada mudou.
- CA7: `bash scripts/setup-labels.sh` num repositório de teste, ou a leitura do parser contra a linha nova.
- CA10: `bash scripts/test-protect-main.sh`.
- O repositório não tem `make lint`, `make test` nem CI.

## Riscos e dúvidas
- O CA4 publica comentários reais numa issue, então depende de o usuário escolher uma issue para o teste.
- Várias etapas na mesma sessão podem compactar o contexto. O teto reduz o risco, mas não o elimina. Se isso acontecer no meio de uma etapa, ela continua pelo resumo, como hoje.
- A label `em-andamento` precisa existir no repositório. Sem ela, o `avancar` para e indica `/fabrica:setup`, como as outras etapas fazem.
- A linha de custo das etapas pode sair incompleta enquanto a #62 não for corrigida.

## Histórico
- 2026-11-04: criação.
