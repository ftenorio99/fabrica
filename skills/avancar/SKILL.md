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
- **Issues:** com número, só ela. Sem número, todas as abertas com `agente`: `gh issue list --label agente --state open --json number,title,labels,url --limit 100`.
- Para cada issue, colete o estado como no passo 1 do [`/fabrica:status`](../status/SKILL.md): comentários e labels, a branch da issue (pela regra da spec da issue de [estados.md](../status/estados.md)), o PR da branch e os pedidos novos no PR. Use só o repositório atual.
- **Em andamento:** para cada issue com `em-andamento`, pegue o horário do último evento `labeled em-andamento`: `gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp`. Siga a regra de [estados.md](../status/estados.md#etapa-em-andamento).

## 2. Selecionar
- Aplique a tabela de estados de [estados.md](../status/estados.md) a cada issue.
- **Entram** só as issues nos estados em que o agente age: 2, 4, 5, 6, 8, 10, 11 e 12.
- **Ficam de fora:**
  - a issue com `em-andamento` recente, que outra sessão está avançando. Já a issue com `em-andamento` esquecida entra normalmente, com um alerta no relatório;
  - a issue com uma inconsistência de [estados.md](../status/estados.md#inconsistências), que vai para os alertas do relatório. A exceção é a `em-andamento` esquecida, que não tira a issue da seleção.
- **Com número**, se a issue estiver num estado do usuário (1, 3, 7, 9 ou 13), num estado de fora ou com `em-andamento` recente, não execute nada: mostre o estado e o que o usuário faz, e pare.
- **Ordem:** primeiro a mais perto do merge. Os estados 10, 11 e 12 vêm antes do 8, que vem antes do 6, 5, 4 e 2. No mesmo grupo, vai antes o menor número de issue.

## 3. Etapa de cada estado
| Estado | Etapa | Argumentos |
|---|---|---|
| 2 Aguardando triagem | [triagem](../triagem/SKILL.md) | `<nº>` |
| 4 Respostas recebidas | [spec](../spec/SKILL.md) se o último comentário do agente antes da resposta for de spec (`<!-- fabrica:spec -->`); senão, [triagem](../triagem/SKILL.md) | `<nº>` |
| 5 Triada | [spec](../spec/SKILL.md) | `<nº>` |
| 6 Ajuste da spec pedido | [spec](../spec/SKILL.md) | `<nº> <ajustes>`, com os ajustes tirados dos comentários do usuário posteriores ao último `<!-- fabrica:spec -->` ou, no atalho, ao comentário de triagem com a spec curta |
| 8 Em implementação | [implementar](../implementar/SKILL.md), que já segue para o `revisar` | `<nº>` |
| 10, 11 e 12 | [revisar](../revisar/SKILL.md) | `<nº>` |

**Como executar:** as etapas têm `disable-model-invocation: true`, então não as chame pela ferramenta Skill. Leia o `SKILL.md` da etapa, pelo link da tabela, e siga as instruções dele com os argumentos da tabela no lugar de `$ARGUMENTS`. Os caminhos relativos que ele cita partem da pasta da própria etapa (`<diretório base desta skill>/../<etapa>/`). Cada etapa publica o que já publica, com a própria linha de custo e as próprias lições.

**Sem conversa no chat:** a etapa não pergunta nada no chat. O que ela perguntaria vai para a issue, como as etapas já fazem. Guarde o que ela diria ao usuário no chat para o relatório.

## 4. Laço
Para cada issue selecionada, na ordem:
1. **Reler:** confira de novo as labels (`gh issue view <nº> --json labels`). Se `em-andamento` estiver na issue, compare o horário do último evento `labeled em-andamento` da timeline com o que foi coletado no passo 1. Se a label não estava lá no passo 1, ou o evento é mais novo, outra sessão a aplicou nesse meio-tempo: pule a issue e anote no relatório.
2. **Marcar:** `gh issue edit <nº> --add-label em-andamento`. Se a label já estiver na issue, esquecida, remova-a antes (`--remove-label em-andamento`) e aplique de novo, para a timeline ganhar um evento `labeled` com o horário de agora.
3. **Executar** a etapa do estado atual, como no passo 3.
4. **Desmarcar:** `gh issue edit <nº> --remove-label em-andamento`, com sucesso ou falha. Nunca deixe a label na issue ao sair da etapa.
5. **Reler** o estado como no passo 1 e anotar a passagem (estado de antes → estado de depois).
6. **Repetir** enquanto o estado novo for de agente e o teto não tiver sido atingido.

O laço da issue para quando:
- **Portão do usuário:** a issue chegou a um estado em que o usuário age (1, 3, 7, 9 ou 13). Este é o fim normal.
- **Sem avanço:** depois da etapa, a issue continua no mesmo estado. Isso cobre a etapa que parou num pré-requisito, como o limite de 3 em andamento, uma label que falta ou o ambiente incompleto. Anote o motivo que a etapa deu.
- **Falha:** a etapa terminou com erro. Anote o comando e o erro resumido.
- **Inconsistência:** o estado relido tem uma inconsistência de [estados.md](../status/estados.md#inconsistências).

Uma issue parada não interrompe as outras: siga para a próxima da ordem.

**Teto:** no máximo **4 etapas por execução**, somando todas as issues. O `implementar` encadeado com o `revisar` conta como uma etapa só. Ao chegar ao teto, termine a etapa em curso, não comece outra e anote no relatório o que ficou para a próxima execução.

## 5. Responder
No chat, neste formato:

```markdown
## Avanço
| Issue | Caminho | Parou em | O que você faz |
|---|---|---|---|
| [fabrica#62](url) Título | Aguardando triagem → Triada → Spec para aprovar | Spec para aprovar | Revisar `specs/SPEC-62.md` e aplicar `spec-aprovada` |
| [fabrica#55](url) Título | Em implementação | Em implementação (sem avanço) | Ver o motivo: limite de 3 em andamento |

**Etapas executadas:** 3 de 4.
- <alertas: inconsistências, `em-andamento` esquecida, issues puladas por outra sessão, issues que ficaram para a próxima execução>
```

Na coluna "O que você faz", use o próximo passo de [estados.md](../status/estados.md) para o estado em que a issue parou. Sem nenhuma issue de agente, diga isso e indique `/fabrica:status`.

## Regras
- **Portões:** nunca aplique `agente` nem `spec-aprovada`, nunca faça merge, nunca aprove o PR e nunca responda perguntas ou comente no lugar do usuário. Os portões são gestos do usuário.
- A única label que esta skill aplica e remove é a `em-andamento`. As outras labels são das etapas.
- Não comente na issue nem no PR em nome do `avancar`, e não publique linha de custo própria. Quem comenta é a etapa, com o marcador dela.
- Não pule nem altere passos de uma etapa para caber no teto ou para acelerar: cada etapa roda inteira, como se tivesse sido chamada pelo comando dela.
- Se `gh issue edit` falhar porque a label `em-andamento` não existe, pare antes de executar qualquer etapa e diga no chat: "A label `em-andamento` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label sozinho.
