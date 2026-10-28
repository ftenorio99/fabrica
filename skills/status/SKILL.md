---
name: status
description: Mostra o quadro do fluxo da fábrica em todos os repositórios do usuário (ou em um só) - o que espera aprovação ou revisão do usuário, o que espera agente e com qual comando, e alertas como limite de trabalho em andamento, CI vermelho e itens parados. Só lê, não altera nada. Use quando o usuário perguntar o que falta, o que fazer agora ou como estão as issues.
argument-hint: "[repositório]"
---

# Quadro da fábrica

Filtro: $ARGUMENTS (vazio = todos os repositórios do usuário)

Esta skill é o orquestrador em modo leitura: lê o estado de cada issue no GitHub e diz o próximo passo e quem age. As regras de estado estão em [estados.md](estados.md); siga-as à risca e não invente estados.

## Regras
- **Só leitura:** não aplique nem remova labels, não comente, não crie branch, não rode skills de outra etapa. Para executar o próximo passo, o usuário roda o comando indicado.
- Não decida por um portão humano: aprovar spec e fazer merge são sempre do usuário.

## 1. Coletar
- Dono: `gh api user -q .login`.
- Issues: `gh search issues --owner <dono> --label agente --state open --json repository,number,title,labels,updatedAt,url --limit 100`. Com filtro, use `--repo <dono>/<repositório>`.
- Para cada issue, `gh issue view <nº> -R <repo> --json comments,labels` e localize os comentários mais recentes com `<!-- fabrica:triagem -->` e `<!-- fabrica:spec -->`. A branch da issue está no comentário de spec (`**Branch:**`).
- Com a branch, procure o PR: `gh pr list -R <repo> --head <branch> --state all --json number,state,isDraft,url,reviewDecision,statusCheckRollup,updatedAt,body`.
- PRs abertos fora do fluxo (sem issue com `agente`): `gh search prs --owner <dono> --state open --json repository,number,title,url,updatedAt`.

Rode as consultas independentes em paralelo.

## 2. Classificar
- Aplique a tabela de [estados.md](estados.md) a cada issue e anote estado, quem age e próximo passo.
- **Diretório:** o comando de agente roda no clone do repositório. Use `~/projetos/<repositório>` se existir; senão, indique `gh repo clone <repo> ~/projetos/<repositório>`.
- **Alertas:**
  - limite de trabalho em andamento: 3 ou mais issues abertas com `spec-aprovada` no mesmo repositório;
  - CI falhando em PR aberto;
  - item parado: sem atualização há mais de 3 dias;
  - inconsistências listadas em estados.md.

## 3. PRs para revisar
Para cada PR no estado "PR para revisar", leia o corpo e `gh pr diff <nº> -R <repo> --name-only` e liste os pontos de atenção, sem fazer a revisão completa:
- arquivos sensíveis tocados (`.github/`, migrações, autenticação, segredos, dependências novas no `package.json` ou equivalente);
- o que o PR traz em "Desvios da spec", sugestões não aplicadas da revisão automática e "Para a sua revisão";
- CI e tamanho do diff.

## 4. Responder
No chat, neste formato, omitindo seções vazias:

```markdown
## Esperando você
| Item | Estado | O que fazer |
|---|---|---|
| [kairo#6](url) Título curto | Spec para aprovar | Revisar `specs/SPEC-6.md` e aplicar `spec-aprovada` |

## Esperando agente
| Item | Estado | Comando | Onde |
|---|---|---|---|
| [kairo#7](url) Título curto | Triada | `/fabrica:spec 7` | `~/projetos/kairo` |

## PRs para revisar
### [kairo#8](url) título do PR
- <ponto de atenção>

## Alertas
- <alerta>

## Fora do fluxo
- [repo#nº](url) PR aberto sem issue da fábrica
```

Termine com uma linha de recomendação: o que fazer primeiro, priorizando o que destrava agentes (aprovar spec, responder perguntas) antes do que só fecha ciclos (merge). Sem nenhum item, diga que não há nada no fluxo e sugira criar a próxima issue a partir do fatiamento do PRD.
