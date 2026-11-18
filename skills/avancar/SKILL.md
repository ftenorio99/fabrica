---
name: avancar
description: Avança sozinho as issues da fábrica no repositório atual - executa a próxima etapa de agente de cada issue (triagem, spec, implementar, revisar), relê o estado e repete até a issue chegar a um portão do usuário, com no máximo 4 etapas por execução. Nunca aprova spec, nunca faz merge e nunca responde no lugar do usuário. Use quando o usuário quiser que o fluxo ande sem digitar cada comando.
argument-hint: "[número da issue]"
disable-model-invocation: true
---

# Avançar o fluxo

Issue: $ARGUMENTS (vazio = todas as issues com `agente` do repositório atual)

Esta skill executa as etapas em que o agente age e para nos portões do usuário. Ela não tem regras de estado próprias: o estado de cada issue sai de [estados.md](../status/estados.md), e cada etapa segue o próprio `SKILL.md`.

## 1. Coletar
- **Repositório:** `gh repo view --json nameWithOwner -q .nameWithOwner`. Fora de um clone com remote no GitHub, pare e diga que o comando roda dentro do clone do repositório.
- **Worktrees:** antes de coletar, rode `bash <diretório base desta skill>/../../scripts/issue-worktree.sh clean` no repositório atual ([ADR 0014](../../docs/adr/0014-uma-worktree-por-issue.md)). Guarde as linhas `removida <nº> <branch>` e `mantida <nº> <branch> trabalho-local` para os alertas do relatório. Se ele sair com 1 (o `gh` falhou), nada foi removido: anote isso nos alertas e siga.
- **Issues:** com número, só ela. Sem número, todas as abertas com `agente`: `gh issue list --label agente --state open --json number,title,labels,url --limit 100`.
- Para cada issue, colete o estado como no passo 1 do [`/fabrica:status`](../status/SKILL.md): comentários e labels, a branch da issue (pela regra da spec da issue de [estados.md](../status/estados.md)), o PR da branch e os pedidos novos no PR. Use só o repositório atual.
- **Em andamento:** para cada issue com `em-andamento`, pegue o horário do último evento `labeled em-andamento`: `gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp`. Siga a regra de [estados.md](../status/estados.md#etapa-em-andamento).

## 2. Selecionar
- Aplique a tabela de estados de [estados.md](../status/estados.md) a cada issue.
- **Entram** só as issues nos estados em que o agente age: 1b, 2, 4, 5, 6, 8, 10, 11 e 12. O estado da ação externa (1a e 1b) sai do `acao-status.py`, como no passo 1 do [`/fabrica:status`](../status/SKILL.md).
- **Ficam de fora:**
  - a issue com `em-andamento` recente, que outra sessão está avançando. Já a issue com `em-andamento` esquecida entra normalmente, com um alerta no relatório;
  - a issue com uma inconsistência de [estados.md](../status/estados.md#inconsistências), que vai para os alertas do relatório. A exceção é a `em-andamento` esquecida, que não tira a issue da seleção.
- **Com número**, se a issue estiver num estado do usuário (1, 1a, 3, 7, 9 ou 13), num estado de fora ou com `em-andamento` recente, não execute nada: mostre o estado e o que o usuário faz, e pare.
- **Ordem:** primeiro a mais perto do merge. Os estados 10, 11 e 12 vêm antes do 8, que vem antes do 6, 5, 4 e 2. O 1b vai junto do grupo da etapa do marcador: com `etapa=revisar`, no grupo do 10 ao 12; com `etapa=implementar`, no do 8. No mesmo grupo, vai antes o menor número de issue.

## 3. Etapa de cada estado
| Estado | Etapa | Argumentos |
|---|---|---|
| 1b Ação concluída | a etapa do marcador do comentário de ação: [implementar](../implementar/SKILL.md) (que já segue para o `revisar`) ou [revisar](../revisar/SKILL.md). A etapa retoma pela seção "Retomar" de [acao-externa.md](../status/acao-externa.md) | `<nº>` |
| 2 Aguardando triagem | [triagem](../triagem/SKILL.md) | `<nº>` |
| 4 Respostas recebidas | [spec](../spec/SKILL.md) se o último comentário do agente antes da resposta for de spec (`<!-- fabrica:spec -->`); senão, [triagem](../triagem/SKILL.md) | `<nº>` |
| 5 Triada | [spec](../spec/SKILL.md) | `<nº>` |
| 6 Ajuste da spec pedido | [spec](../spec/SKILL.md) | `<nº>`. A spec lê os ajustes nos comentários da issue; nunca copie o texto deles para o argumento ([ADR 0008](../../docs/adr/0008-texto-externo-fora-do-prompt.md)) |
| 8 Em implementação | [implementar](../implementar/SKILL.md), que já segue para o `revisar` | `<nº>` |
| 10, 11 e 12 | [revisar](../revisar/SKILL.md) | `<nº>` |

**Como executar:** cada etapa roda num processo `claude -p` próprio, com o modelo que [modelos.md](modelos.md) dá para a etapa e para a issue ([ADR 0013](../../docs/adr/0013-modelo-por-etapa-e-por-issue.md)). O `implementar` encadeia o `revisar` dentro do mesmo processo.
1. **Binário:** confira que o `claude` existe (`command -v "${FABRICA_CLAUDE_BIN:-claude}"`). Se não existir, vá para "Sem o `claude`" abaixo.
2. **Rodar:** `bash <diretório base desta skill>/../../scripts/stage-model.sh run <etapa> <nº> <labels da issue> > <arquivo>`, com o nome da etapa da tabela acima (`triagem`, `spec`, `implementar` ou `revisar`) e **só as labels `modelo:*`** da issue que você coletou no passo 1, separadas por espaço (o script não lê as outras, e o nome de uma label vem do GitHub: não passe nenhuma outra ao shell). Rode o comando em segundo plano (a etapa pode passar do tempo de um comando em primeiro plano) e espere o aviso de que ele terminou, sem consultar o arquivo no meio. O script escolhe o modelo, monta o `claude -p` e repassa o JSON dele para o arquivo. O prompt leva só `/fabrica:<etapa> <nº>` ([ADR 0008](../../docs/adr/0008-texto-externo-fora-do-prompt.md)): nunca monte o comando do `claude` à mão nem copie texto da issue para ele. Uma saída 2 do script é inconsistência de labels (duas ou mais `modelo:*`): trate como no passo 4, sem executar a etapa.
3. **Ler o resultado:** do JSON em `<arquivo>`, guarde `is_error`, o texto de `result` (o que a etapa diria no chat) e as chaves de `modelUsage`, que são os modelos usados. O relatório do passo 5 mostra o modelo.
4. **Falha:** saída diferente de 0, `is_error` verdadeiro ou JSON ilegível é a falha do passo 4 do laço. Se `permission_denials` não está vazio, ou o `result` cita bloqueio do classificador ou de um hook, a etapa parou por permissão: anote o motivo, sem contar como falha de qualidade.

**Sem o `claude`:** as etapas têm `disable-model-invocation: true`, então não as chame pela ferramenta Skill. Leia o `SKILL.md` da etapa, pelo link da tabela, e siga as instruções dele com os argumentos da tabela no lugar de `$ARGUMENTS`. Os caminhos relativos que ele cita partem da pasta da própria etapa (`<diretório base desta skill>/../<etapa>/`). Cada etapa publica o que já publica, com a própria linha de custo e as próprias lições. Neste caminho a etapa roda no modelo da sessão, a coluna "Modelo" do relatório mostra `sessão` e não há escalonamento de modelo. É o caminho do OpenCode e do Antigravity.

**Sem conversa no chat:** a etapa não pergunta nada no chat. O que ela perguntaria vai para a issue, como as etapas já fazem. Guarde o que ela diria ao usuário no chat para o relatório.

## 4. Laço
Para cada issue selecionada, na ordem:
1. **Reler:** confira de novo as labels (`gh issue view <nº> --json labels`). Se `em-andamento` estiver na issue, compare o horário do último evento `labeled em-andamento` da timeline com o que foi coletado no passo 1. Se a label não estava lá no passo 1, ou o evento é mais novo, outra sessão a aplicou nesse meio-tempo: pule a issue e anote no relatório.
2. **Marcar:** `gh issue edit <nº> --add-label em-andamento`. Se a label já estiver na issue, esquecida, remova-a antes (`--remove-label em-andamento`) e aplique de novo, para a timeline ganhar um evento `labeled` com o horário de agora.
3. **Executar** a etapa do estado atual, como no passo 3. Antes, nas etapas `implementar` e `revisar`, conte as linhas de lição do [escalonamento de modelo](#escalonamento-de-modelo).
4. **Desmarcar:** `gh issue edit <nº> --remove-label em-andamento`, com sucesso ou falha. Nunca deixe a label na issue ao sair da etapa.
   Em seguida, nas etapas `implementar` e `revisar` rodadas pelo `claude -p`, aplique o [escalonamento de modelo](#escalonamento-de-modelo).
5. **Reler** o estado como no passo 1 e anotar a passagem (estado de antes → estado de depois).
6. **Repetir** enquanto o estado novo for de agente e o teto não tiver sido atingido.

O laço da issue para quando:
- **Portão do usuário:** a issue chegou a um estado em que o usuário age (1, 1a, 3, 7, 9 ou 13). Este é o fim normal.
- **Sem avanço:** depois da etapa, a issue continua no mesmo estado. Isso cobre a etapa que parou num pré-requisito, como o limite de 3 em andamento, o limite de 3 worktrees de issue (saída 5 do `issue-worktree.sh ensure`), uma label que falta ou o ambiente incompleto. Anote o motivo que a etapa deu.
- **Falha:** a etapa terminou com erro. Anote o comando e o erro resumido.
- **Inconsistência:** o estado relido tem uma inconsistência de [estados.md](../status/estados.md#inconsistências).

Uma issue parada não interrompe as outras: siga para a próxima da ordem.

**Teto:** no máximo **4 etapas por execução**, somando todas as issues. O `implementar` encadeado com o `revisar` conta como uma etapa só. Ao chegar ao teto, termine a etapa em curso, não comece outra e anote no relatório o que ficou para a próxima execução.

## 5. Responder
No chat, neste formato:

```markdown
## Avanço
| Issue | Caminho | Modelo | Parou em | O que você faz |
|---|---|---|---|---|
| [fabrica#62](url) Título | Aguardando triagem → Triada → Spec para aprovar | triagem `sonnet`, spec `opus` | Spec para aprovar | Revisar `specs/SPEC-62.md` e aplicar `spec-aprovada` |
| [fabrica#55](url) Título | Em implementação | implementar `haiku` → `sonnet` (subiu) | Em implementação (sem avanço) | Ver o motivo: limite de 3 em andamento |

**Etapas executadas:** 3 de 4.
- <alertas: inconsistências, `em-andamento` esquecida, issues puladas por outra sessão, issues que ficaram para a próxima execução, worktrees `removida` e `mantida … trabalho-local` do `clean`>
```

Na coluna "Modelo", ponha o apelido de cada etapa executada, lido das chaves de `modelUsage` do JSON de cada etapa (`sonnet` para `claude-sonnet-5-5`, e assim por diante), `sessão` nas etapas do caminho sem o `claude` e a seta e "(subiu)" quando o escalonamento trocou a label. Na coluna "O que você faz", use o próximo passo de [estados.md](../status/estados.md) para o estado em que a issue parou. Sem nenhuma issue de agente, diga isso e indique `/fabrica:status`.

## Regras
- **Portões:** nunca aplique `agente` nem `spec-aprovada`, nunca faça merge, nunca aprove o PR e nunca responda perguntas ou comente no lugar do usuário. Os portões são gestos do usuário.
- As únicas labels que esta skill aplica e remove são a `em-andamento` e, no [escalonamento de modelo](#escalonamento-de-modelo), as `modelo:*`. As outras labels são das etapas.
- Não comente na issue nem no PR em nome do `avancar`, e não publique linha de custo própria. Quem comenta é a etapa, com o marcador dela. A exceção é a lição `modelo` do escalonamento de modelo, que segue [../licao/formato.md](../licao/formato.md).
- O comando do `claude` sai sempre do `scripts/stage-model.sh`, com só o nome da etapa e o número da issue ([ADR 0008](../../docs/adr/0008-texto-externo-fora-do-prompt.md)).
- Não pule nem altere passos de uma etapa para caber no teto ou para acelerar: cada etapa roda inteira, como se tivesse sido chamada pelo comando dela.
- Se `gh issue edit` falhar porque a label `em-andamento` não existe, pare antes de executar qualquer etapa e diga no chat: "A label `em-andamento` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label sozinho.

## Escalonamento de modelo
Vale só para as etapas `implementar` e `revisar` rodadas pelo `claude -p`, e a tabela de [modelos.md](modelos.md) define as subidas. A subida não retoma a etapa: a issue segue no estado em que a etapa a deixou (em geral `escalonado`), e a próxima execução já usa o modelo novo.

**Antes da etapa**, guarde o número de blocos de lição de cada gatilho que mede qualidade:
`gh api repos/<repo>/issues/<nº>/comments --paginate -q '.[] | select(.body | startswith("<!-- fabrica:licao gatilho=<gatilho> -->")) | .body' | grep -c '^\*\*Lição · '`, para `rodadas` e para `achado-pendente`.

**Depois da etapa**, repita a contagem. Há **falha de qualidade** quando um dos dois números aumentou, ou quando a etapa terminou com erro (`is_error` ou saída diferente de 0) **sem** parada por permissão. Não contam como falha, mesmo com erro: a parada por permissão (`permission_denials` não vazio, ou o resultado cita bloqueio do classificador ou de um hook), o `precisa-info`, a `acao-externa` e o escalonamento por mudança de escopo.

**Em cada falha de qualidade:**
1. Registre uma lição com o gatilho `modelo`, como diz [../licao/formato.md](../licao/formato.md), com a linha `**Falha:** modelo=<apelido> etapa=<etapa> motivo=<rodadas|achado-pendente|erro>` no campo `O que aconteceu`. O `<apelido>` é o modelo que a etapa usou.
2. Conte as linhas `**Falha:** modelo=<apelido> ` desse modelo na lição `modelo` da issue: `gh api repos/<repo>/issues/<nº>/comments --paginate -q '.[] | select(.body | startswith("<!-- fabrica:licao gatilho=modelo -->")) | .body' | grep -c '\*\*Falha:\*\* modelo=<apelido> '`.
3. `bash <diretório base desta skill>/../../scripts/stage-model.sh next <apelido> <falhas>`. Se o resultado for outro apelido, troque a label: `gh issue edit <nº> --add-label modelo:<para>` e, se a issue tinha a `modelo:<de>`, `--remove-label modelo:<de>`. Acrescente `**Troca:** <de> → <para>` ao campo `Ação sugerida` do bloco da falha.
4. Anote a subida no relatório. Se o resultado for o mesmo apelido, só a lição fica registrada.

O `opus` não sobe. Uma issue com `escalonado` depois de uma falha segue a regra normal: o usuário decide, e a retomada já usa o modelo novo.
