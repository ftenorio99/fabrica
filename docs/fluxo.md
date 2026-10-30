# Fluxo

Uma ideia vira produto em duas camadas:
- **Planejamento:** o PRD e o backlog, feitos uma vez e revistos quando o produto muda.
- **Ciclo de cada issue:** triagem, spec, implementação, revisão e merge, uma issue por vez.

```mermaid
flowchart TD
    prd["/fabrica:prd<br/>PRD em docs/prd.md"] --> backlog["/fabrica:backlog<br/>milestones e issues"]
    backlog --> puxar{{"Você aplica agente"}}
    puxar --> triagem["/fabrica:triagem"]
    triagem -->|perguntas| info{{"Você responde na issue"}}
    info --> triagem
    triagem --> spec["/fabrica:spec<br/>spec-pronta"]
    spec --> aprovar[["Portão: você aprova a spec<br/>spec-aprovada"]]
    aprovar --> implementar["/fabrica:implementar"]
    implementar --> revisar["/fabrica:revisar<br/>PR e pronto-revisao"]
    revisar --> merge[["Portão: você revisa e faz o merge"]]

    classDef gate fill:#fde68a,stroke:#b45309,color:#000
    classDef user fill:#dbeafe,stroke:#1d4ed8,color:#000
    class aprovar,merge gate
    class puxar,info user
```

Os retângulos são etapas de agente, que você dispara com o comando. Os hexágonos são ações suas que destravam o fluxo. Os retângulos duplos em amarelo são os **portões humanos**: nenhum agente passa deles sem você.

## Quem age em cada etapa
| Etapa | Quem age | O que sai |
|---|---|---|
| PRD | você e o agente, em entrevista | `docs/prd.md` com funcionalidades (F1, F2…) e fatiamento em marcos |
| Backlog | agente, com a sua confirmação | milestones `M<n> · <nome>` e issues enxutas do marco atual e do seguinte |
| Puxar | você | a label `agente` numa issue de backlog |
| Triagem | agente | comentário de triagem; perguntas na issue se faltar informação |
| Spec | agente | `specs/SPEC-<nº>.md` na branch da issue e a label `spec-pronta` |
| **Aprovar a spec** | **você** | a label `spec-aprovada` |
| Implementação | agente | código e testes na branch, verificações registradas |
| Revisão | agente | revisão contra a spec, PR com evidências e a label `pronto-revisao` |
| **Merge** | **você** | squash na `main`; a issue fecha sozinha |

Quando algo dá errado, o agente para, comenta na issue e aplica `escalonado`. Veja o guia [Issue escalonada](guias/issue-escalonada.md).

## Onde está o estado
Não existe arquivo de estado. O estado de cada issue é lido de três lugares no GitHub:
- as labels;
- os comentários dos agentes, que começam com um marcador como `<!-- fabrica:spec -->`;
- o PR da branch da issue.

A tabela completa de estados, com quem age e o próximo passo de cada um, fica em [`skills/status/estados.md`](../skills/status/estados.md). O `/fabrica:status` aplica essa tabela e mostra o quadro.

## Planejamento em ondas
O backlog não cria todas as issues de uma vez:
- **Milestones:** todas existem desde o início.
- **Issues:** só o marco atual e o seguinte ganham issues.
- **Avanço:** quando o marco atual está perto de fechar, o `/fabrica:status` avisa para rodar o `/fabrica:backlog` de novo, e a janela avança.

Veja [Fechar um marco](guias/fechar-marco.md) e a seção "Backlog" de [`estados.md`](../skills/status/estados.md).
