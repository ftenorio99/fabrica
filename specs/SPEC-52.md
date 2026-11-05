# SPEC-52: Atalho na triagem para issues pequenas e sem ambiguidade

**Issue:** #52 · **PRD:** — (o fabrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-05

## Contexto
Hoje toda issue segue o mesmo caminho: triagem, `/fabrica:spec`, aprovação com `spec-aprovada`, implementação, revisão e merge. A triagem já classifica o tamanho e a classe, mas essa classificação não muda o caminho. Ajustar um texto custa a mesma etapa de spec, com branch, arquivo e commit, que uma mudança de arquitetura. A issue pede um atalho para issues pequenas e sem ambiguidade. O atalho mantém o contrato verificável (os CAs), a revisão do agente e o merge humano, e a decisão sobre o formato dele fica registrada num ADR.

## Objetivo
Uma issue pequena e sem ambiguidade vai da triagem à aprovação sem a etapa `/fabrica:spec`, com uma spec curta (objetivo e CAs) no comentário da triagem, aprovada pela mesma label `spec-aprovada`.

## Comportamento esperado
**Critério do atalho.** A triagem aplica o atalho quando a issue atende a todas estas condições:
- tamanho `P`;
- classe `implementacao-simples` ou `documentacao`;
- nenhuma lacuna (nenhuma pergunta no comentário);
- nenhum arquivo sensível entre os arquivos prováveis (autenticação, pagamentos, migrações de banco, `.github/`).

O comentário de triagem sempre traz a linha `**Atalho:** sim — <por quê>` ou `**Atalho:** não — <qual condição falhou>`.

**Caminho curto:**
1. A triagem decide pelo atalho. No mesmo comentário de triagem, ela publica a seção `### Spec curta`, com o objetivo, a tabela de CAs (ID, critério e verificação, nas mesmas regras da spec) e a linha `**Branch:** \`<tipo>/<nº>-<descricao-curta>\``. A triagem não cria a branch.
2. A triagem aplica `spec-pronta` e diz ao usuário: "aplique `spec-aprovada` para aprovar, ou comente na issue para pedir a spec completa".
3. O usuário aplica `spec-aprovada`. O `/fabrica:implementar` lê a spec curta e cria a branch a partir da `main` atualizada, se ela não existir. O passo que marca o arquivo de spec como aprovado não se aplica, porque não há arquivo.
4. O `/fabrica:revisar` e o revisor conferem a branch contra os CAs da spec curta e usam a seção "Fora do escopo" do corpo da issue como os limites. No PR, a linha `**Spec:**` aponta para o comentário de triagem.
5. O merge continua com o usuário.

**Recusa.** Qualquer comentário do usuário na issue depois da triagem com atalho, antes de `spec-aprovada`, tira a issue do atalho. Na tabela de estados, ela vai para "Ajuste da spec pedido", e o próximo passo é `/fabrica:spec <nº> <ajustes>`. O `/fabrica:spec` cria a branch, escreve `specs/SPEC-<nº>.md` completa, levando em conta o comentário, e publica o comentário `<!-- fabrica:spec -->`. A partir daí a issue segue o caminho completo. A spec curta nunca é editada.

**Spec da issue.** `skills/status/estados.md` passa a definir de onde vêm a spec e a branch de uma issue:
- com um comentário `<!-- fabrica:spec -->`, valem o arquivo e o `**Branch:**` do mais recente deles;
- sem esse comentário, vale a spec curta do comentário de triagem mais recente, quando ele tem `**Atalho:** sim`, com o `**Branch:**` dele.

As etapas, o `/fabrica:status`, o `/fabrica:avancar` e o `/fabrica:metricas` passam a ler a spec e a branch por essa regra.

| Situação | Resultado |
|---|---|
| Issue `P`, `documentacao`, sem perguntas, sem arquivo sensível | Triagem com `**Atalho:** sim`, a seção `### Spec curta` e `spec-pronta`. Estado: Spec para aprovar. |
| Issue `P` com uma pergunta aberta | Sem atalho (`**Atalho:** não — há lacunas`), `precisa-info`, fluxo atual. |
| Issue `P` que toca `.github/` | A classe já é `implementacao-complexa`, então não há atalho. |
| Issue `M` simples | Sem atalho (`**Atalho:** não — tamanho M`), fluxo atual. |
| Atalho e o usuário comenta antes de aprovar | Estado "Ajuste da spec pedido" e `/fabrica:spec <nº> <ajustes>`, que escreve a spec completa. |
| Atalho aprovado | Estado "Em implementação", com a branch do comentário de triagem. |
| Triagem de uma rodada nova depois de `precisa-info` | O critério é avaliado de novo nessa rodada. |

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/triagem/SKILL.md` define o critério do atalho com as quatro condições. O formato do comentário traz a linha `**Atalho:**` sempre e a seção `### Spec curta` (objetivo, tabela de CAs e `**Branch:**`) só no atalho. No atalho, a triagem aplica `spec-pronta`, e a regra "não escreva spec nem branch" ganha a exceção da spec curta, ainda sem criar a branch. | manual: leitura do diff |
| CA2 | `skills/status/estados.md` define a "spec da issue" pela regra das duas fontes e mostra a triagem também aplicando `spec-pronta` na tabela de labels. A linha 6 também vale para a resposta nova ao comentário de triagem com atalho quando não há comentário de spec. A inconsistência "`spec-aprovada` sem marcador de spec" passa a valer só para a issue sem spec da issue. | manual: leitura do diff |
| CA3 | O `/fabrica:implementar` e o `/fabrica:revisar` leem a spec e a branch pela regra do CA2. No atalho, o `implementar` cria a branch a partir da `main` quando ela não existe e pula a marcação da spec como aprovada e o commit dela. O `revisar` passa ao revisor o link do comentário de triagem no lugar do caminho da spec e põe esse link na linha `**Spec:**` do PR. `agents/revisor.md` aceita a spec curta como spec e, no atalho, usa o "Fora do escopo" da issue. | manual: leitura do diff |
| CA4 | O `/fabrica:spec`, numa issue com atalho e sem `spec-aprovada`, escreve a spec completa, levando em conta os comentários do usuário depois da triagem como ajustes. Ela cria a branch com o nome que a triagem anunciou e não trata a spec curta como spec aprovada antes. | manual: leitura do diff |
| CA5 | O `/fabrica:status`, o `/fabrica:avancar` e o `/fabrica:metricas` acham a branch do atalho pelo comentário de triagem. No atalho, o `status` mostra "Revisar a spec curta na triagem e aplicar `spec-aprovada`" como próximo passo. O `avancar` tira os ajustes da linha 6 dos comentários posteriores à triagem com atalho. O `metricas` mostra `atalho` na coluna Spec da issue que não teve comentário de spec. | manual: leitura do diff |
| CA6 | `docs/adr/0004-atalho-da-triagem-com-spec-curta.md` existe com status `aceito` depois do commit de aprovação. `docs/fluxo.md` mostra o atalho no diagrama e na tabela. `docs/principios.md`, `docs/comandos.md` (triagem, spec, implementar e revisar) e `docs/glossario.md` (termo "Atalho" e o verbete "Spec") explicam o atalho e remetem às skills, sem copiar as regras. | manual: leitura do diff |
| CA7 | A `version` de `.claude-plugin/plugin.json` sobe para `0.17.0`, e `bash scripts/test-protect-main.sh`, `bash scripts/test-stage-usage.sh`, `bash scripts/test-costs.sh` e `bash scripts/test-check-gh.sh` continuam passando. | manual: rodar os scripts |
| CA8 | Ponta a ponta: com o plugin carregado da branch (`claude --plugin-dir`), uma issue de teste `docs` de tamanho `P` no fabrica recebe a triagem com atalho, e o `/fabrica:status` a mostra como "Spec para aprovar" com a branch do atalho. Comentar na issue a leva a "Ajuste da spec pedido". A issue de teste é fechada sem merge no fim, com um comentário dizendo que era teste. | manual: execução na branch |

## Fora de escopo
- Mudar o merge humano: ele continua obrigatório.
- Automatizar o disparo das etapas (Fase 1).
- A opção (b) da issue, sem o portão da spec (descartada no ADR 0004).
- Levar à spec as recomendações da triagem sem `precisa-info`: é a #69.
- Mudar o `durations.py`: o tempo "esperando você" já conta `spec-pronta` sem `spec-aprovada`, que a triagem com atalho aplica.

## Desenho técnico
**Arquivos e módulos:**
- `skills/triagem/SKILL.md`:
  - na descrição do frontmatter, a menção ao atalho;
  - no passo 2, o critério do atalho;
  - no passo 4, a linha `**Atalho:**`, a seção `### Spec curta` e as labels do atalho (`spec-pronta`);
  - nas regras, a exceção da spec curta.
- `skills/spec/SKILL.md`: nos pré-requisitos e no passo 3, o caso da issue com atalho: os comentários do usuário depois da triagem entram como ajustes, a branch tem o nome do `**Branch:**` da triagem e a spec curta não é baseline.
- `skills/implementar/SKILL.md`: no passo 1, a spec e a branch pela regra da spec da issue; no passo 2, criar a branch a partir da `main` quando ela não existe e pular a marcação da spec no atalho.
- `skills/revisar/SKILL.md`: no passo 1, a branch pela regra; no passo 3, o que passar ao revisor no atalho; no corpo do PR (passo 5), a linha `**Spec:**`.
- `agents/revisor.md`: a spec pode ser a spec curta da triagem; no atalho, os limites são o "Fora do escopo" da issue.
- `skills/status/estados.md`:
  - na tabela de labels, `spec-pronta` aplicada por "triagem, spec";
  - nos Termos, antes da tabela de estados, a definição da spec da issue;
  - a linha 6 e a inconsistência de `spec-aprovada`;
  - uma seção curta "Atalho" que remete à triagem e ao ADR 0004.
- `skills/status/SKILL.md`: no passo 1, a branch pela regra da spec da issue; no passo 2, o próximo passo do atalho.
- `skills/avancar/SKILL.md`: no passo 1, a branch pela regra; no passo 3, os ajustes da linha 6 no atalho.
- `skills/metricas/SKILL.md`: a branch pela regra e a coluna Spec com `atalho`.
- `docs/adr/0004-atalho-da-triagem-com-spec-curta.md`: criado nesta etapa, com status `proposto`.
- `docs/fluxo.md`, `docs/principios.md`, `docs/comandos.md` e `docs/glossario.md`: o manual.
- `.claude-plugin/plugin.json`: a `version` vai para `0.17.0`.

**Dados:** nenhum. Não há label nova, então o `scripts/setup-labels.sh` não muda.

**Interfaces:** o comentário de triagem ganha a linha `**Atalho:** sim|não — <motivo>` e, no atalho, a seção:

```markdown
### Spec curta
**Objetivo:** <uma frase>

| ID | Critério | Verificação |
|---|---|---|
| CA1 | <comportamento observável> | unitário / e2e / manual |

**Branch:** `<tipo>/<nº>-<descricao-curta>`
```

**Decisões:**
- **Opção (a), spec curta no comentário da triagem aprovada com `spec-aprovada`:** mantém os três gestos do usuário, o limite de 3 em andamento, o pré-requisito do `implementar` e o tempo "esperando você" das métricas sem regra nova, e o usuário vê os CAs antes do código. Alternativa descartada: (b), pular o portão e levar os CAs direto para o PR. Ela tira um portão, exige outra regra para o WIP e para o `implementar`, e só mostra um CA errado depois do código pronto.
- **Recusa por comentário, sem label nova:** qualquer comentário do usuário depois da triagem com atalho leva à spec completa. Ele já é o caminho de ajuste da tabela de estados e não exige mudar o `setup-labels.sh`. Alternativa descartada: uma label `sem-atalho`, que é mais um gesto e mais uma label para criar em cada repositório.
- **Ajustar a spec curta vira spec completa:** o `/fabrica:spec` não edita o comentário de triagem, que tem histórico, e uma issue que gerou discussão já deixou de ser "sem ambiguidade". Alternativa descartada: a triagem publicar uma nova spec curta a cada ajuste, que mistura as rodadas de triagem e de spec nas métricas.
- **A branch nasce no `implementar`:** a triagem continua sem mexer no repositório e só anuncia o nome da branch. Alternativa descartada: a triagem criar a branch, o que a faria mexer no repositório só para o atalho.

**Fontes da documentação:** nenhuma biblioteca.

**ADR:** [docs/adr/0004-atalho-da-triagem-com-spec-curta.md](../docs/adr/0004-atalho-da-triagem-com-spec-curta.md)

## Testes
- O repositório não tem `make lint`, `make test` nem CI. Rode `bash scripts/test-protect-main.sh`, `bash scripts/test-stage-usage.sh`, `bash scripts/test-costs.sh` e `bash scripts/test-check-gh.sh` (CA7).
- CA1 a CA6: leitura do diff, conferindo que cada arquivo da lista "Arquivos e módulos" cita a mesma regra da spec da issue de `estados.md`, sem copiá-la. Faça também `grep -rn "comentário \`<!-- fabrica:spec -->\`" skills agents docs` para achar os lugares que ainda leem a branch só do comentário de spec.
- CA8: execução na branch, como descrito no critério. Anote no PR o número da issue de teste e o estado mostrado pelo `/fabrica:status` em cada passo.

## Riscos e dúvidas
- **Sobreposição com #69:** as duas mudam a seção "3. Procurar lacunas" e o formato do comentário de triagem. A que entrar por último faz o rebase.
- **Ponto esquecido:** a branch e a spec são lidas em muitos lugares, e um que ficar só com o comentário de spec deixa a issue do atalho sem PR no `/fabrica:status`. O `grep` da seção "Testes" e o CA8 cobrem esse risco.
- **CA8 publica no GitHub:** a issue de teste fica no histórico do fabrica, fechada e identificada como teste.

## Histórico
- 2026-11-05: criação.
