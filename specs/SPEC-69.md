# SPEC-69: Triagem leva à spec as escolhas que já sabe recomendar, sem abrir precisa-info

**Issue:** #69 · **PRD:** — (o fabrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-06

## Contexto
Na retrospectiva de 2026-11-05, 6 das 24 issues do período tiveram duas rodadas de triagem, e em todas o usuário respondeu seguindo a recomendação que a própria triagem já trazia ("seguir as recomendações", "(a) Recomendado"). Cada rodada custa um portão a mais (`precisa-info`) e uma execução de triagem, sem mudar o resultado. Hoje o passo 3 da triagem já tira das lacunas as decisões técnicas, mas a regra "Não invente requisitos: se o PRD e a issue não dizem, é uma pergunta" transforma em pergunta toda escolha de comportamento, mesmo quando a triagem tem uma recomendação bem fundamentada. O portão `spec-aprovada` já existe para o usuário confirmar ou mudar escolhas, então ele pode receber essas recomendações.

## Objetivo
A triagem só abre `precisa-info` quando há uma lacuna sem recomendação defensável. As escolhas que ela sabe recomendar aparecem no comentário de triagem e chegam à spec como decisões para o usuário confirmar no portão `spec-aprovada`.

## Comportamento esperado
**Recomendação defensável.** Uma escolha que a issue deixa em aberto deixa de ser lacuna quando a triagem tem, para ela, uma opção recomendada e uma justificativa tirada de uma fonte que dá para citar: o corpo ou os comentários da issue, o PRD, um ADR, uma spec anterior, o código existente ou uma convenção já seguida no repositório. A preferência da própria triagem, sem uma fonte dessas, não basta.

**Continuam sendo pergunta**, com `precisa-info`:
- a divisão de uma issue maior que 2 dias;
- a regra de negócio, a prioridade ou o comportamento sem recomendação defensável;
- uma escolha em que as fontes se contradizem, por exemplo a issue contra o PRD.

**Comentário de triagem.** Quando há recomendações, o comentário ganha a seção `**Recomendações levadas para a spec:**`, depois de `**Riscos:**` e antes de `**Atalho:**`, com um item por escolha:

```markdown
**Recomendações levadas para a spec:**
1. <escolha em aberto>: <opção recomendada>, porque <justificativa, citando a fonte>. Alternativa: <opção descartada>.
```

Sem recomendações, a seção não aparece. As perguntas, quando houver, continuam na seção `**Perguntas**`, no formato atual.

| Situação | Resultado |
|---|---|
| Só recomendações, nenhuma pergunta | Sem `precisa-info` e sem lição `precisa-info`. A issue vai para `/fabrica:spec` ou, se couber, para o atalho. |
| Recomendações e perguntas | `precisa-info` e lição, como hoje. As recomendações ficam no comentário e seguem para a spec na rodada seguinte, se o usuário não as contestar. |
| Issue maior que 2 dias | A divisão continua sendo pergunta, mesmo com uma divisão recomendada. |
| Regra de negócio sem fonte que apoie uma opção | Pergunta, como hoje. |

**Atalho.** Recomendações não tiram a issue do atalho: a condição "nenhuma lacuna" continua valendo só para perguntas. No atalho, os CAs da spec curta já seguem as recomendações, e a frase de aprovação da spec curta passa a dizer que aplicar `spec-aprovada` confirma também as recomendações acima dela. Comentar na issue tira a issue do atalho, como hoje.

**Spec.** O `/fabrica:spec` lê a seção de recomendações do comentário de triagem mais recente. Cada recomendação vira um item de "Decisões para você confirmar" no comentário de spec e uma decisão no desenho técnico da spec, marcada como "(recomendação da triagem)". Se o usuário contestou uma recomendação num comentário depois da triagem, vale o comentário, e a decisão segue o que ele pediu. Na saída do atalho, as recomendações da triagem também entram na spec completa.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | No passo 3 de `skills/triagem/SKILL.md`, uma escolha com recomendação defensável (opção recomendada e justificativa com uma das fontes listadas em "Comportamento esperado") não é lacuna. Continuam sendo lacuna a divisão de uma issue maior que 2 dias, a regra de negócio sem recomendação defensável e a escolha com fontes contraditórias. | manual: leitura do diff |
| CA2 | O formato do comentário no passo 4 traz a seção opcional `**Recomendações levadas para a spec:**` entre `**Riscos:**` e `**Atalho:**`, com escolha, opção, justificativa com a fonte e alternativa. Uma issue só com recomendações segue o ramo "Sem lacunas" das labels, sem `precisa-info` nem lição. | manual: leitura do diff |
| CA3 | A regra "Não invente requisitos" da triagem passa a dizer que, sem resposta no PRD e na issue e sem recomendação defensável, a escolha é pergunta. Nenhuma outra regra da skill continua mandando perguntar uma escolha que tenha recomendação defensável. | manual: leitura do diff |
| CA4 | No passo 2 de `skills/triagem/SKILL.md`, a condição "nenhuma lacuna" do atalho diz que recomendações não contam como lacuna. A frase final da spec curta diz que `spec-aprovada` confirma também as recomendações do comentário. | manual: leitura do diff |
| CA5 | Em `skills/spec/SKILL.md`, o passo 3 manda ler as recomendações do comentário de triagem mais recente. O passo 4 põe cada recomendação nas decisões do desenho técnico com "(recomendação da triagem)", salvo se um comentário do usuário depois da triagem a contestou. O comentário do passo 5 lista as recomendações em "Decisões para você confirmar". A saída do atalho também leva as recomendações. | manual: leitura do diff |
| CA6 | `docs/comandos.md` (triagem e spec) e `docs/fluxo.md` (linha da triagem na tabela de etapas) explicam que a triagem pergunta só o que não sabe recomendar e que as recomendações chegam à spec, remetendo às skills sem copiar as regras. A `version` de `.claude-plugin/plugin.json` sobe para `0.18.0`, e `bash scripts/test-protect-main.sh`, `bash scripts/test-stage-usage.sh`, `bash scripts/test-costs.sh` e `bash scripts/test-check-gh.sh` continuam passando. | manual: leitura do diff e rodar os scripts |
| CA7 | Ponta a ponta: com o plugin carregado da branch (`claude --plugin-dir ~/projetos/fabrica`), uma issue de teste no fabrica que deixa em aberto uma escolha com resposta num ADR existente recebe a triagem com a seção de recomendações, citando o ADR, e sem `precisa-info`. No fim, a issue de teste é fechada como "not planned", com um comentário dizendo que era teste. | manual: execução na branch |

## Fora de escopo
- Pular a spec em issues pequenas: é a #52, já entregue.
- Mudar o formato das perguntas que continuam existindo.
- Mudar o critério do atalho além da condição "nenhuma lacuna".
- Mudar a lição `precisa-info`, o `/fabrica:metricas` ou a tabela de estados: não há label, marcador nem estado novo.

## Desenho técnico
**Arquivos e módulos:**
- `skills/triagem/SKILL.md`:
  - passo 2, critério do atalho: a condição "nenhuma lacuna" diz que recomendações não contam;
  - passo 3: o parágrafo das decisões técnicas passa a valer para toda escolha com recomendação defensável, com a lista de fontes e a lista do que continua sendo pergunta;
  - passo 4: a seção opcional `**Recomendações levadas para a spec:**` no formato do comentário, a frase final da spec curta e, no ramo "Sem lacunas e sem atalho", a menção de que recomendações não abrem `precisa-info`;
  - regras: a nova redação de "Não invente requisitos".
- `skills/spec/SKILL.md`:
  - passo 1, saída do atalho: as recomendações da triagem entram na spec completa;
  - passo 3: ler a seção de recomendações do comentário de triagem mais recente;
  - passo 4, "Decisões": cada recomendação vira decisão marcada "(recomendação da triagem)", salvo contestação do usuário;
  - passo 5: o modelo do comentário lista essas decisões em "Decisões para você confirmar".
- `docs/comandos.md`: as entradas `/fabrica:triagem` (O que faz) e `/fabrica:spec` (Lê).
- `docs/fluxo.md`: a linha "Triagem" da tabela de etapas.
- `.claude-plugin/plugin.json`: `version` para `0.18.0`.

**Dados:** nenhum. Não há label, marcador nem estado novo, então `skills/status/estados.md` e `scripts/setup-labels.sh` não mudam.

**Interfaces:** a seção `**Recomendações levadas para a spec:**` do comentário de triagem, no formato de "Comportamento esperado". O `/fabrica:spec` a lê pelo título em negrito, no comentário `<!-- fabrica:triagem -->` mais recente.

**Decisões:**
- Recomendações não tiram a issue do atalho — no atalho, elas ficam no mesmo comentário da spec curta, e o usuário as vê no mesmo gesto de aprovação. Alternativa descartada: tirar do atalho toda issue com recomendação, o que poria de volta a etapa de spec que o atalho evita, só para repetir as recomendações num arquivo.
- A justificativa precisa citar uma fonte (issue, PRD, ADR, spec, código ou convenção do repositório) — é o que separa "recomendar" de "inventar requisito" e dá ao usuário como conferir. Alternativa descartada: aceitar qualquer recomendação da triagem, que transferiria regra de negócio para o agente sem nada que o usuário possa checar.
- A seção fica entre `**Riscos:**` e `**Atalho:**` — assim a spec curta, que vem no fim do comentário, aparece logo depois das recomendações que ela segue. Alternativa descartada: pôr as recomendações dentro da spec curta, o que as esconderia nas triagens sem atalho.
- Sem ADR — a mudança refina uma regra das duas skills e não muda princípio, label nem estado.

**Fontes da documentação:** nenhuma biblioteca envolvida.

**ADR:** nenhum.

## Testes
- CA1 a CA6: leitura do diff, conferindo cada trecho citado no desenho técnico, e os quatro scripts de teste do CA6.
- CA7: execução real com `claude --plugin-dir`, numa issue de teste criada para isso e fechada depois.

## Riscos e dúvidas
- **Conflito com #70, #71 e #79:** as três mudam `skills/spec/SKILL.md` ou o formato da spec curta. A que entrar depois resolve o conflito com rebase.
- **Recomendação errada aprovada sem leitura:** com menos perguntas, uma recomendação ruim pode passar no portão `spec-aprovada`. A exigência da fonte e a marcação "(recomendação da triagem)" na spec deixam esses pontos visíveis na revisão.

## Histórico
- 2026-11-06: criação.
