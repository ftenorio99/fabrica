---
name: triagem
description: Faz a triagem de uma issue do GitHub antes da spec - classifica tipo, classe e tamanho, liga ao PRD e pede na própria issue o que faltar (label precisa-info). Numa issue pequena e sem ambiguidade, publica uma spec curta e aplica spec-pronta, pulando o /fabrica:spec (atalho). Use quando uma issue receber a label agente ou depois que as perguntas da triagem forem respondidas.
argument-hint: "<número da issue>"
disable-model-invocation: true
---

# Triagem da issue

Issue: #$ARGUMENTS

A triagem decide se a issue está pronta para virar spec. Ela não escreve código e só escreve spec no atalho, a spec curta do passo 4. Toda comunicação com o usuário acontece **na issue** (comentários e labels), para que esta skill funcione igual rodando no terminal ou no GitHub Actions.

**Regras comuns:** antes de seguir, leia [../etapas/regras.md](../etapas/regras.md) e aplique as regras dele com `<etapa>` = `triagem`: corpo por arquivo; plano B; label inexistente; marcador; linha de custo.

## 1. Ler
- **Início da etapa:** antes de qualquer outro comando, guarde o instante em UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`). Ele vai na linha de custo do passo 4.
- **`gh`:** rode `bash <diretório base desta skill>/../../scripts/check-gh.sh`. Se a linha não for `ok`, pare antes de ler ou escrever no GitHub, como diz [../setup/gh.md](../setup/gh.md).
- `gh issue view <nº> --json number,title,body,labels,comments,state`
- Se a issue estiver fechada ou não tiver a label `agente`, pare e avise o usuário no chat.
- As regras do projeto (`AGENTS.md`; num projeto ainda não migrado, `CLAUDE.md`) e `docs/prd.md`: identifique as funcionalidades do PRD (F1, F2…) ligadas à issue.
- **Fonte do escopo:** se as regras do projeto disserem que o escopo de cada issue vem de um documento além do PRD (ex.: uma story em `docs/stories/`), identifique o caminho que o corpo da issue aponta para ele. Confira que o arquivo existe na `main` com `gh api repos/{owner}/{repo}/contents/<caminho> --jq .path`. Se as regras pedem essa fonte e a issue não aponta nenhuma, ou o caminho não existe, é lacuna (passo 3). Sem essa regra no projeto, a fonte é `—`.
- Specs e ADRs existentes (`specs/`, `docs/adr/`) e o código que a issue provavelmente vai tocar. Leia o suficiente para estimar, não para implementar.
- Se já houver um comentário de triagem anterior, esta é uma nova rodada: leia as respostas que vieram depois dele. Ignore os comentários de lição (`<!-- fabrica:licao`), que não são resposta (veja [estados.md](../status/estados.md)).

## 2. Classificar
- **Tipo:** `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci` ou `perf`.
- **Classe da tarefa:**
  - `implementacao-simples`: ajuste de UI, CRUD, textos, testes unitários;
  - `implementacao-complexa`: arquitetura, autenticação, migrações, integrações, recorrência, agendamento;
  - `documentacao`: README, changelog, comentários.

  Se a issue tocar arquivos sensíveis (autenticação, pagamentos, migrações de banco, `.github/`), a classe é sempre `implementacao-complexa` e a revisão humana é obrigatória.
- **Tamanho**, em trabalho humano: `P` (até meio dia), `M` (até 1 dia), `G` (1 a 2 dias). Acima de 2 dias, proponha a divisão (passo 3).
- **Dependências:** outras issues que precisam estar concluídas antes (`gh issue list --state open`).
- **Interface:** `sim` quando a issue muda algo que o usuário final vê na tela (página, componente, estilo, texto da interface); `não` nos outros casos (back-end, CLI, documentação, CI, skills da fábrica). Na dúvida, `sim`: uma descrição de tela a mais custa menos que uma tela sem descrição. A spec usa o campo para criar o `docs/design.md` do projeto ([ADR 0009](../../docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md)).
- **Modelo da implementação** ([ADR 0013](../../docs/adr/0013-modelo-por-etapa-e-por-issue.md)): escolha um apelido de [../avancar/modelos.md](../avancar/modelos.md) pela complexidade, com a razão em uma linha:
  - `haiku`: classe `documentacao`, chore, renomeação ou teste simples, sem arquivo sensível;
  - `opus`: classe `implementacao-complexa` que toca arquivo sensível (autenticação, pagamentos, migrações de banco, `.github/`), decisão de arquitetura ou ambiguidade que a spec vai resolver;
  - `sonnet`: os demais casos.

  Se a issue já tem uma label `modelo:*` (do usuário ou de uma rodada anterior), mantenha-a e só registre o valor na tabela, sem a trocar. Com duas ou mais labels `modelo:*`, não aplique nenhuma: registre os valores como estão e avise no chat, que é uma inconsistência de [estados.md](../status/estados.md#inconsistências).

  Antes de escolher, rode `bash <diretório base desta skill>/../../scripts/harness.sh detect`. Se a harness for `opencode` ou `antigravity`, a etapa roda no modelo da sessão: registre `Modelo | sessão — a etapa roda no modelo da sessão (<harness>)` e **não aplique nem troque** label `modelo:*`. Uma label que já estava na issue permanece; ela vale se a issue for retomada pelo Claude Code.
- **Atalho:** a issue cabe no atalho quando atende a todas estas condições ([ADR 0004](../../docs/adr/0004-atalho-da-triagem-com-spec-curta.md)):
  - tamanho `P`;
  - classe `implementacao-simples` ou `documentacao`;
  - nenhuma lacuna (passo 3). As recomendações levadas para a spec não contam como lacuna;
  - nenhum arquivo sensível entre os arquivos prováveis (autenticação, pagamentos, migrações de banco, `.github/`).
  - não é `Interface: sim`, mesmo num projeto com `docs/design.md`: a descrição das telas é parte da spec completa, e a spec curta não tem lugar para ela ([ADR 0020](../../docs/adr/0020-screenshots-das-telas-numa-branch-orfa.md)). Nesse caso, escreva `**Atalho:** não — issue com interface precisa da descrição das telas na spec completa`.

  Em cada rodada de triagem, avalie o critério de novo.

## 3. Procurar lacunas
A issue está pronta para spec quando dá para responder, sem chutar:
- qual comportamento muda e para quem;
- como saber que terminou (pelo menos uma ideia de critério de aceite);
- quais limites ela tem (o que não faz parte dela).

Uma escolha que a issue deixa em aberto **não** é lacuna quando você tem uma **recomendação defensável** para ela: uma opção recomendada e uma justificativa tirada de uma fonte que dá para citar, entre estas:
- o corpo ou os comentários da issue;
- o PRD;
- um ADR;
- uma spec anterior;
- o código existente;
- uma convenção já seguida no repositório.

Isso vale para escolhas de comportamento: nelas, a sua preferência, sem uma fonte dessas, não basta. Decisões técnicas (biblioteca, nome de rota, estrutura de pastas) continuam não sendo lacuna mesmo sem fonte: a spec as decide. Com uma fonte para citar, leve-as também como recomendação. Essas escolhas vão para a spec como recomendações (passo 4), e o usuário as confirma ou muda no portão `spec-aprovada`.

Continuam sendo lacuna, e viram pergunta:
- o documento de escopo que o projeto manda usar (ex.: a story) não está apontado na issue ou não existe na `main`;
- a divisão de uma issue maior que 2 dias, mesmo com uma divisão recomendada;
- a regra de negócio, a prioridade ou o comportamento sem recomendação defensável;
- uma escolha em que as fontes se contradizem, por exemplo a issue contra o PRD.

Se a issue for maior que 2 dias, a lacuna é a divisão: proponha as partes (títulos e escopo de cada uma) no comentário e pergunte se o usuário quer dividir. Não crie as issues.

## 4. Registrar
Publique um comentário na issue (`gh issue comment <nº> --body-file <arquivo>`) neste formato:

```markdown
<!-- fabrica:triagem -->
## Triagem

| Campo | Valor |
|---|---|
| Tipo | feat |
| Classe | implementacao-complexa |
| Tamanho | G |
| PRD | F7 |
| Fonte do escopo | `docs/stories/...` ou `—` |
| Depende de | #12 |
| Interface | sim |
| Modelo | sonnet — <razão em uma linha> |
| Arquivos prováveis | `src/...` |

**Resumo:** <uma ou duas frases do que a issue pede, nas palavras da triagem>

**Riscos:** <o que pode complicar, ou "nenhum relevante">

**Recomendações levadas para a spec:** (só se houver recomendações)
1. <escolha em aberto>: <opção recomendada>, porque <justificativa, citando a fonte>. Alternativa: <opção descartada>.

**Atalho:** <sim — por que a issue cabe | não — qual condição falhou>

**Perguntas** (só se houver lacunas):
1. <pergunta objetiva, com opções e, quando couber, uma recomendação ainda sem fonte para citar (com fonte, ela não seria pergunta: passo 3)>
```

A linha `**Atalho:**` vai sempre. Com `**Atalho:** sim`, acrescente ao fim do comentário a spec curta, que é a spec da issue até ela ganhar um comentário de spec ([estados.md](../status/estados.md#atalho)):

```markdown
### Spec curta
**Objetivo:** <uma frase: o que passa a ser verdade quando a issue terminar>

| ID | Critério | Verificação |
|---|---|---|
| CA1 | <comportamento observável> | unitário / e2e / manual / depois do merge — <motivo> |

**Fora do escopo:** <o que não faz parte da issue>

**Branch:** `<tipo>/<nº>-<descricao-curta>`

Para aprovar, aplique a label `spec-aprovada`, que confirma também as recomendações acima. Para pedir a spec completa, comente na issue.
```

A seção `**Recomendações levadas para a spec:**` só aparece quando há recomendações (passo 3), com um item por escolha. Sem recomendações, omita-a. As perguntas, quando houver, ficam na seção `**Perguntas**`. No atalho, os CAs da spec curta já seguem as recomendações. Na frase final da spec curta, omita "que confirma também as recomendações acima" quando não houver recomendações.

Os CAs seguem as mesmas regras da [spec](../spec/SKILL.md#4-escrever): numerados, observáveis e cada um com a forma de verificação. A linha `**Fora do escopo:**` traz os limites da issue por escrito: vem da seção "Fora do escopo" do corpo da issue quando ela existe e, quando não existe, dos limites que a triagem leu na issue. Se a triagem não consegue escrever nenhum limite a partir da issue, falta responder "quais limites ela tem" (passo 3): é uma lacuna, e então não há atalho. A branch usa o tipo da triagem e um resumo curto do título, mas não a crie: ela nasce no `/fabrica:implementar`.

**Linha de custo:** ela vai no comentário de triagem com ou sem perguntas, e não no de lição.

Depois, ajuste as labels. Em qualquer dos três casos abaixo, aplique também o modelo escolhido, se a issue ainda não tem uma `modelo:*`, **exceto no caminho de sessão** (`opencode` ou `antigravity`), em que nenhuma label de modelo é aplicada (`gh issue edit <nº> --add-label modelo:<apelido>`):
- **Com lacunas:** `gh issue edit <nº> --add-label precisa-info` e registre uma lição com o gatilho `precisa-info`, resumindo as lacunas e por que a issue não as respondia, como diz [../licao/formato.md](../licao/formato.md). Pare aqui e diga ao usuário que as perguntas estão na issue. Depois de respondidas, a triagem deve ser rodada de novo. As recomendações do mesmo comentário seguem para a spec na rodada seguinte, se o usuário não as contestar.
- **Sem lacunas e sem atalho:** vale também para a issue que só tem recomendações, que não abrem `precisa-info` nem geram lição. `gh issue edit <nº> --remove-label precisa-info` (se estiver lá). Se a issue tiver `spec-pronta` e nenhum comentário de spec, sobra de uma rodada anterior com atalho, remova também `spec-pronta`. Diga que a issue está pronta para `/fabrica:spec <nº>`.
- **Atalho:** `gh issue edit <nº> --add-label spec-pronta --remove-label precisa-info`. Diga que a spec curta está no comentário de triagem e que o usuário aplica `spec-aprovada` para aprovar ou comenta na issue para pedir a spec completa.

## Regras
- Não escreva código nem branch, e não escreva spec fora da spec curta do atalho.
- Não pergunte no chat o que pode ser perguntado na issue.
- Exceção ao marcador: o comentário de lição, que segue [../licao/formato.md](../licao/formato.md).
- Não invente requisitos: se o PRD e a issue não dizem e você não tem uma recomendação defensável (passo 3), é uma pergunta.
- Em rodadas seguintes, publique um novo comentário de triagem completo (com o mesmo marcador); não edite os anteriores, para manter o histórico.
- A exceção à regra da label inexistente é a `licao`: sem ela, a etapa avisa e segue, como diz [../licao/formato.md](../licao/formato.md).
