---
name: revisar
description: Faz a revisão automática da branch de uma issue contra a spec com o subagente revisor, corrige os achados bloqueantes e importantes, abre o PR com a evidência de cada critério de aceite, espera o CI e aplica pronto-revisao. Também trata os comentários do usuário no PR: corrige o que cabe na spec, escala o que muda a spec e responde no PR. Use depois de /fabrica:implementar, ou depois de comentar pedidos no PR.
argument-hint: "<número da issue>"
disable-model-invocation: true
---

# Revisão automática e PR

Issue: #$ARGUMENTS

A revisão automática é a primeira passada antes da revisão humana. Ela confere a mudança contra a spec, não contra o gosto de quem revisa. Esta skill **nunca faz merge**.

## 1. Pré-requisitos
- **`gh`:** rode `bash <diretório base desta skill>/../../scripts/check-gh.sh`. Se a linha não for `ok`, pare antes de ler ou escrever no GitHub, como diz [../setup/gh.md](../setup/gh.md). Seguida a partir do `/fabrica:implementar`, que já fez a checagem, não a repita.
- **Worktree da issue** ([ADR 0014](../../docs/adr/0014-uma-worktree-por-issue.md)): seguida a partir do `/fabrica:implementar`, use o `<wt>` dele. Rodada sozinha, pegue a branch pela regra da spec da issue de [estados.md](../status/estados.md) (o comentário `<!-- fabrica:spec -->` ou, no atalho, a spec curta da triagem) e rode `bash <diretório base desta skill>/../../scripts/issue-worktree.sh ensure <nº> <branch>`, que reusa a worktree criada pelo `implementar`; guarde a última linha impressa como `<wt>`. Saída 3, 4 ou 5: pare sem commit e repita no chat a mensagem do script. Daqui em diante, rode todo comando `git`, `make` e `gh pr` como `cd <wt> && …`, no mesmo comando, e leia e escreva os arquivos pelo caminho absoluto dentro de `<wt>`. Não troque a branch do clone principal.
- A branch da issue, em `<wt>`, tem commits além da `main` e tudo enviado (`git status` limpo, `git push` feito).
- **Modo de isolamento:** seguida a partir do `/fabrica:implementar`, use o modo que ele já leu. Rodada sozinha, leia-o com `bash <diretório base desta skill>/../../scripts/setup-isolation.sh --check` e siga a tabela "Modo de isolamento" do passo "Verificar" do [`/fabrica:implementar`](../implementar/SKILL.md#4-verificar): o modo não muda o caminho, só a anotação e a orientação, e a saída `ausente` ou `inválido` não para a etapa.
- **Ação externa:** se a issue tiver `acao-externa`, é uma retomada depois de uma ação externa: siga a seção "Retomar" de [../status/acao-externa.md](../status/acao-externa.md). Só continue nesta etapa se ela mandar seguir.
- `make lint` e `make test` passam, ou falham só com as assinaturas de ambiente do [`/fabrica:implementar`](../implementar/SKILL.md#4-verificar), com a verificação pendente para o CI anotada. Se falharem por outro motivo, volte para a etapa de implementação em vez de revisar.

## 2. Pedidos no PR
Antes de qualquer consulta ao PR, guarde o **instante da coleta** em UTC: `date -u +%Y-%m-%dT%H:%M:%SZ`. Guarde-o sempre, com PR ou sem PR: ele vai na âncora do passo 6 e é o início desta etapa na linha de custo. Quando esta skill é seguida a partir do `/fabrica:implementar`, o instante da coleta é o `fim` da linha de custo que o `implementar` trouxe, sem um `date` novo.

Se já existir PR da branch (`gh pr view`), trate os pedidos do usuário antes da revisão. Sem PR, ou sem pedido novo, siga para o passo 3.

**Termos:**
- **Comentário do usuário no PR:** comentário da conversa, review com corpo ou comentário em linha que não começa com um marcador `<!-- fabrica:<etapa> -->` nem com `<!-- fabrica:licao`. Review sem corpo não conta, inclusive a `APPROVED`; a review `APPROVED` com corpo conta.
- **Âncora:** o último comentário com `<!-- fabrica:revisar -->` na conversa do PR.
- **Referência:** o instante da linha `**Pedidos lidos até:**` da âncora. Numa âncora antiga, sem essa linha, a referência é a data de criação da própria âncora.
- **Pedido novo:** comentário do usuário no PR posterior à referência, pela data de criação do comentário ou de envio da review (`submittedAt`). Sem âncora, todo comentário do usuário no PR conta.

**Coletar:**
- `gh pr view <nº do PR> --json comments,reviews`: conversa e reviews;
- `gh api repos/<dono>/<repo>/pulls/<nº do PR>/comments`: comentários em linha, com arquivo e linha.

**Classificar** cada pedido novo:
- **Ajuste:** resolve-se sem incluir, remover ou alterar um CA nem um item de "Fora de escopo" da spec (bug, caso-limite que um CA já cobre, nome, mensagem, teste faltando, documentação, estilo).
- **Mudança de escopo:** exige incluir, remover ou alterar um CA, ou fazer algo de "Fora de escopo". Na dúvida, é mudança de escopo. No atalho, o "Fora de escopo" é a linha `**Fora do escopo:**` da spec curta.

**Tratar:**
- **Ajuste:** corrija na branch, rode `make lint` e `make test`, faça commit (`fix: ...` ou o tipo adequado) e push. Essas correções não contam como rodada de revisão.
- **Mudança de escopo:** não altere o código para ela nem edite a spec. Aplique `escalonado` na issue (`gh issue edit <nº> --add-label escalonado`) e registre uma lição com o gatilho `escalonado`, citando o pedido e o CA afetado ([../licao/formato.md](../licao/formato.md)). Na resposta, indique o caminho: o usuário remove `spec-aprovada`, roda `/fabrica:spec <nº> <ajuste>`, aprova de novo e retoma com `/fabrica:implementar <nº>`. Os ajustes do mesmo lote continuam sendo corrigidos.
- **Não procede:** se discordar de um pedido, não o aplique e registre o motivo na resposta.

Guarde, para cada pedido, um trecho dele e o que foi feito: o commit da correção, "mudança de escopo, escalado" ou "não procede", com o motivo. Isso vai para a resposta do passo 6.

## 3. Rodada de revisão
**Verificação pedida ao usuário:** a etapa pede ao usuário uma verificação que o agente não consegue fazer em dois casos: a verificação de integração num projeto sem CI (item 1 abaixo) e um CA de verificação manual fora do alcance do agente: ele depende do usuário, ou a tentativa de rodá-lo falhou com assinatura de ambiente (veja "CA manual fora do alcance" no passo 4).
- **Pedido:** comente na issue, com o marcador `<!-- fabrica:revisar -->`, cada CA envolvido, o comando exato a rodar com `!` (ex.: `! make test && make e2e`) e o que conferir na saída. Peça ao usuário que responda **na issue** com o comando e a saída e depois rode `/fabrica:revisar <nº>`, sem tirar o `escalonado`: a retomada tira a label. Aplique `escalonado` e pare.
- **Retomada:** se, depois do último comentário `<!-- fabrica:revisar -->` da issue com esse pedido, há uma resposta do usuário na issue com o resultado, remova `escalonado` e use a resposta como verificação manual de cada CA do pedido: passe ao revisor o comando e a saída que o usuário mostrou, e cite-os em "Verificações manuais" no PR. Se a resposta mostra falha, volte ao `/fabrica:implementar`. Sem resposta nova, a issue continua esperando o usuário: diga isso no chat e pare.

**Verificação pendente para o CI** ([ADR 0011](../../docs/adr/0011-verificacao-de-integracao-na-etapa.md)): a verificação de integração roda na etapa. O CI é a reserva para quando o ambiente não a roda: se o `implementar` anotou comandos que o ambiente não roda, ou se o `make test` que você rodou falhou só com as assinaturas de ambiente, o CI do PR faz essa verificação antes do revisor:
1. **Sem CI:** se nenhum workflow em `.github/workflows/` dispara em `pull_request`, não há quem verifique.
   - **Primeira vez:** faça o "Pedido" da verificação pedida ao usuário, com os comandos que o ambiente não roda e a orientação do modo.
   - **Retomada:** siga a "Retomada" da verificação pedida ao usuário. Sem PR em rascunho e sem esperar CI, siga a partir do revisor.
2. **PR em rascunho:** sem PR, abra-o já como rascunho (`gh pr create --draft --body-file <arquivo>`), com o corpo do passo 5 e os CAs que dependem da verificação que o ambiente não roda com ⏳ "aguardando o CI". Em "Para a sua revisão", liste a anotação de cada comando e a orientação do modo. Com PR, use-o e, se ele não estiver em rascunho, converta com `gh pr ready --undo`.
3. **CI:** espere o CI do head como no passo 6 ("Ler o CI").
4. **Revisor:** passe a ele, além do que vem abaixo, os comandos que o ambiente não roda e o resultado do CI: nome, `conclusion` e link de cada run.

Sem verificação pendente, o PR só é aberto no passo 5 e não nasce em rascunho por causa da verificação de integração: o revisor roda a verificação, e a evidência dos CAs de integração é a dele. O CI do passo 6 continua sendo esperado, como em todo PR.

Chame o subagente `revisor` deste plugin: no Claude Code, pelo Agent tool, como `fabrica:revisor`; no Antigravity (`agy`), pelo `invoke_subagent`, com o nome que o `agy` lista para ele. Se ele não estiver disponível, use um subagente de propósito geral e passe a ele, como instruções, o conteúdo de [../../agents/revisor.md](../../agents/revisor.md).

**Modelo do revisor** ([ADR 0013](../../docs/adr/0013-modelo-por-etapa-e-por-issue.md)): o julgamento da revisão roda no modelo que [../avancar/modelos.md](../avancar/modelos.md) dá para a etapa `revisar` e a issue. Antes de chamar o subagente, rode `bash <diretório base desta skill>/../../scripts/stage-model.sh model revisar <labels modelo:* da issue>` (só as labels que começam com `modelo:`, de `gh issue view <nº> --json labels`: o nome de uma label vem do GitHub e não vai ao shell) e passe o primeiro campo da saída (`sonnet` ou `opus`) no parâmetro `model` do Agent tool. Se o script sair com código diferente de 0 (labels `modelo:*` inconsistentes, por exemplo), não passe `model`: o revisor herda o modelo da sessão. No subagente de propósito geral, passe o mesmo `model`.

Passe ao revisor:
- o número da issue e o caminho da spec ou, no atalho, o link do comentário de triagem com a spec curta;
- a branch, a base (`origin/main`) e o caminho `<wt>` da worktree da issue, onde ele lê o código e roda as verificações;
- as anotações da implementação (verificações manuais feitas e desvios da spec), rotuladas como "afirmações do `implementar`, a conferir": o revisor só aceita como evidência o que ele mesmo encontra ou roda;
- na retomada de uma verificação pedida ao usuário, o comando e a saída da resposta dele, com os CAs a que ela se refere;
- a saída do `setup-isolation.sh --check`;
- com verificação pendente para o CI, os comandos que o ambiente não roda e o resultado do CI do head.

O revisor devolve, para cada critério de aceite, se está atendido e com qual evidência, e uma lista de achados com severidade `bloqueante`, `importante` ou `sugestão`.

## 4. Corrigir
- **Assinatura de ambiente só no revisor:** se o revisor anotou "o ambiente não roda a verificação (<assinatura>)" num comando que não estava na verificação pendente para o CI (por exemplo, o `make e2e` passou no `implementar` e falhou com assinatura no revisor), isso não é achado a corrigir nem conta como rodada. Acrescente o comando à verificação pendente e siga os itens da "Verificação pendente para o CI" do passo 3: sem CI, o "Pedido" ao usuário; com CI, o PR em rascunho, a espera do CI do head e uma nova chamada ao revisor com o resultado. Os demais achados seguem as regras abaixo antes disso.
- Um CA que o revisor devolve como `depois do merge` não é achado nem pendência: ele vai para o PR com ⏳ (passo 5).
- **CA manual fora do alcance:** um CA de verificação manual que o revisor devolve como não feito por um destes motivos, sem retomada com a resposta do usuário, não é achado a corrigir nem conta como rodada: a verificação depende do usuário (outra sessão, conta externa, passo interativo), ou a tentativa de rodá-la falhou com assinatura de ambiente. Um CA que precisa do app rodando com banco não entra aqui só por isso: o revisor tenta rodá-lo antes. Abra ou atualize o PR como rascunho (`gh pr create --draft --body-file <arquivo>` ou, com PR, `gh pr ready --undo`), com o corpo do passo 5 e esse CA com ⏳ "aguardando a sua verificação", e faça o "Pedido" da verificação pedida ao usuário do passo 3. Os demais achados seguem as regras abaixo antes do pedido.
- **Ação externa:** se a revisão, a correção ou o CI só podem seguir depois de uma ação do usuário fora do GitHub (por exemplo, um secret que o CI do PR precisa), pare como diz a seção "Parar" de [../status/acao-externa.md](../status/acao-externa.md), com `etapa=revisar` no marcador. Ela não gera lição nem conta como rodada de correção. Um CI vermelho só por falta do secret também não conta como rodada.
- Corrija todos os achados `bloqueante` e `importante` que procedem. Se discordar de um achado, registre o motivo; ele vai para o PR.
- Depois de corrigir, rode `make lint` e `make test`, faça commit (`fix: ...` ou o tipo adequado) e push, e faça uma nova rodada de revisão. Com verificação pendente para o CI, espere antes o CI do head novo e passe o resultado ao revisor. Um CI vermelho por causa da mudança é achado `bloqueante` e conta como rodada.
- No máximo **duas rodadas de correção**. Se ainda restarem achados bloqueantes, abra o PR mesmo assim como rascunho (`--draft`), liste os achados pendentes, aplique `escalonado` na issue e não aplique `pronto-revisao`.
- Para cada achado `bloqueante` ou `importante` que ficou sem corrigir, por discordância ou por pendência depois das duas rodadas, registre uma lição com o gatilho `achado-pendente`, um bloco por achado ([../licao/formato.md](../licao/formato.md)). No escalonamento por achados pendentes, essa é a única lição: não registre também `escalonado`.
- Sugestões não são aplicadas nem geram lição: elas vão listadas no PR para o usuário decidir.

## 5. Abrir o PR
Se já existir PR da branch (`gh pr view`), inclusive o rascunho do passo 3, atualize a descrição em vez de abrir outro. Senão, `gh pr create --body-file <arquivo>`:

- **Título:** `<tipo da triagem>: <descrição curta em português>`, no padrão de commits das regras do projeto (`AGENTS.md`; num projeto ainda não migrado, `CLAUDE.md`), porque vira a mensagem do squash.
- **Corpo:**

  ```markdown
  ## Resumo
  <O que muda, em duas a quatro frases, citando a spec.>

  **Spec:** `specs/SPEC-<nº>.md` (no atalho, o link do comentário de triagem com a spec curta) · **ADR:** <se houver>

  ## Critérios de aceite
  | ID | Status | Evidência |
  |---|---|---|
  | CA1 | ✅ | <teste que cobre, ou comando executado e resultado> |
  | CA2 | ✅ | <...> |
  | CA3 | ⏳ | confere depois do merge: <o quê> |
  | CA4 | ✅ | verificado pelo CI: [<nome do run>](<link>) |

  ## Verificações manuais
  <Cada verificação da spec: comando executado e resultado observado.>

  ## Desvios da spec
  <Ajustes feitos em relação ao desenho técnico e por quê, ou "nenhum".>

  ## Revisão automática
  <Número de rodadas, achados corrigidos, achados de que discordou (com o motivo) e sugestões não aplicadas.>

  ## Para a sua revisão
  <Onde vale olhar com mais atenção: arquivos sensíveis, decisões, riscos. Cite cada CA ⏳ e o que você confere depois do merge.>

  Fixes #<nº>
  ```

## 6. CI, labels e resposta no PR
- **Ler o CI:** o `gh pr checks` não funciona com o token fine-grained do [guia de isolamento](../../docs/guias/isolamento-do-agente.md#token-fine-grained), que não lê checks. Leia os runs do head pela API do Actions, repetindo a consulta até o fim:
  ```
  gh api "repos/<dono>/<repo>/actions/runs?head_sha=$(git rev-parse HEAD)" -q '.workflow_runs[] | [.name, .status, .conclusion, .html_url] | @tsv'
  ```
  - **Terminou:** todos os runs do head estão com `status` `completed`.
  - **Verde:** todo run tem `conclusion` `success`, `skipped` ou `neutral`.
  - **Sem CI:** nenhum run do head depois de 10 minutos. Registre no PR e siga, como com um PR sem CI. Com verificação pendente para o CI, isso equivale a não ter CI: siga o item 1 da "Verificação pendente para o CI" do passo 3. Depois da "Retomada" desse item, a verificação já está atendida pela resposta do usuário: trate o PR como sem CI, sem esperar os 10 minutos.
- Espere o CI. Se falhar por causa da mudança, corrija como no passo 4 (conta como rodada). Se precisou de duas ou mais correções por CI vermelho, registre uma lição com o gatilho `rodadas`, com os checks que falharam e o que os resolveu ([../licao/formato.md](../licao/formato.md)). Se falhar por motivo externo (instabilidade, credencial), registre no PR e siga.
- Com CI verde e sem achados bloqueantes, mesmo com CAs ⏳ "depois do merge": se o PR está em rascunho só por causa do passo 3 ou de um "CA manual fora do alcance" do passo 4, já atendido na retomada, tire o rascunho (`gh pr ready`). Depois, `gh issue edit <nº> --add-label pronto-revisao --remove-label escalonado`. Nos CAs verificados pelo CI, a evidência no corpo é o nome e o link do run, e o resumo ganha a linha "Verificação de integração pelo CI (ADR 0011)". Se o passo 2 escalou uma mudança de escopo, remova `pronto-revisao` se estiver aplicada (`gh issue edit <nº> --remove-label pronto-revisao`) e mantenha `escalonado`: o PR espera a mudança da spec, não a revisão do usuário.
- **Resposta no PR:** comente no PR (`gh pr comment <nº do PR> --body-file <arquivo>`) com o marcador `<!-- fabrica:revisar -->`. Esse comentário vira a nova âncora do passo 2, então publique-o sempre que aplicar `pronto-revisao` e sempre que tratar pedidos, mesmo com rascunho ou escalado:
  - **instante da coleta:** logo abaixo do marcador, a linha `**Pedidos lidos até:** <instante da coleta do passo 2>`;
  - **sem pedidos:** uma linha, "PR pronto para a sua revisão", com o resumo da revisão automática;
  - **evidência por critério:** quando esta execução rodou o revisor e aplica `pronto-revisao` ou deixa o PR em rascunho, acrescente a seção `### Evidência por critério`, com a tabela de critérios do revisor (ID, Atendido, Evidência) e a lista "Não encontrado" dele. A tabela do corpo do PR continua com o resumo. A resposta que só trata pedidos, sem nova rodada do revisor, não leva a seção;
  - **com pedidos:** uma linha por pedido, com o trecho e o que foi feito (commit, escalado ou não procede, com o motivo);
  - **chegaram durante esta rodada:** antes de publicar, colete de novo pelos mesmos caminhos do passo 2, aplicando os "Termos" do passo 2: só conta comentário do usuário no PR posterior ao instante da coleta, que aqui faz o papel da referência, com o mesmo critério de data (criação do comentário ou `submittedAt` da review). Esses pedidos não são tratados agora: cite cada um com um trecho numa seção "Chegaram durante esta rodada" e avise que ficam para o próximo `/fabrica:revisar`. Sem nenhum, omita a seção.
  - **linha de custo:** por último, logo antes de publicar, acrescente ao fim do arquivo do corpo a linha do `implementar`, se ele trouxe uma, e em seguida a desta execução: `python3 <diretório base desta skill>/../../scripts/stage-usage.py --stage revisar --since <instante da coleta> >> <arquivo>`. O script nunca falha: sem log da sessão, a linha sai com `tokens=nao-medido`. Só esta resposta no PR leva a linha; o comentário na issue com o link do PR e o de lição não levam. A exceção é a etapa que para numa ação externa: a linha vai no comentário de ação.
- Comente na issue com o link do PR e diga ao usuário no chat que o PR está pronto para a revisão dele, ou o que ficou escalado.

## Regras
- Nunca faça merge, nem aprove o próprio PR.
- Não mude a spec para fazer a implementação passar, nem por um pedido feito no PR. Se a spec estiver errada, comente na issue.
- Todo comentário seu, na issue ou no PR, começa com o marcador `<!-- fabrica:revisar -->` numa linha própria, exceto o comentário de lição, que segue [../licao/formato.md](../licao/formato.md), e o comentário de ação, que segue [../status/acao-externa.md](../status/acao-externa.md). Os comentários do agente e do usuário saem da mesma conta do GitHub, e o marcador é o que os distingue (veja [estados.md](../status/estados.md)).
- Publique todo corpo de issue, comentário ou PR a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- O status de cada CA no PR precisa ter evidência; "implementado" sem evidência não conta. A exceção é o CA marcado `depois do merge — <motivo>` na spec, que vai com ⏳ e "confere depois do merge: <o quê>".
- Se um `gh pr edit` ou um `gh issue edit` falhar por um erro do próprio `gh`, use o plano B de [../setup/gh.md](../setup/gh.md#plano-b-por-rest) e avise no chat. Uma label que não existe não é erro do `gh`: vale a regra abaixo.
- Se `gh issue edit` falhar porque uma label não existe, pare, comente na issue e diga no chat: "A label `<label>` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label sozinho. A exceção é a `licao`: sem ela, a etapa avisa e segue, como diz [../licao/formato.md](../licao/formato.md).
