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
- Você está na branch da issue (a do comentário `<!-- fabrica:spec -->`), com commits além da `main` e tudo enviado (`git status` limpo, `git push` feito).
- `make lint` e `make test` passam. Se não passarem, volte para a etapa de implementação em vez de revisar.

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
- **Mudança de escopo:** exige incluir, remover ou alterar um CA, ou fazer algo de "Fora de escopo". Na dúvida, é mudança de escopo.

**Tratar:**
- **Ajuste:** corrija na branch, rode `make lint` e `make test`, faça commit (`fix: ...` ou o tipo adequado) e push. Essas correções não contam como rodada de revisão.
- **Mudança de escopo:** não altere o código para ela nem edite a spec. Aplique `escalonado` na issue (`gh issue edit <nº> --add-label escalonado`) e registre uma lição com o gatilho `escalonado`, citando o pedido e o CA afetado ([../licao/formato.md](../licao/formato.md)). Na resposta, indique o caminho: o usuário remove `spec-aprovada`, roda `/fabrica:spec <nº> <ajuste>`, aprova de novo e retoma com `/fabrica:implementar <nº>`. Os ajustes do mesmo lote continuam sendo corrigidos.
- **Não procede:** se discordar de um pedido, não o aplique e registre o motivo na resposta.

Guarde, para cada pedido, um trecho dele e o que foi feito: o commit da correção, "mudança de escopo, escalado" ou "não procede", com o motivo. Isso vai para a resposta do passo 6.

## 3. Rodada de revisão
Chame o subagente `revisor` deste plugin (no Agent tool, `fabrica:revisor`). Se ele não estiver disponível, use um subagente de propósito geral e passe a ele, como instruções, o conteúdo de [../../agents/revisor.md](../../agents/revisor.md).

Passe ao revisor:
- o número da issue e o caminho da spec;
- a branch e a base (`origin/main`);
- as anotações da implementação: verificações manuais feitas e desvios da spec.

O revisor devolve, para cada critério de aceite, se está atendido e com qual evidência, e uma lista de achados com severidade `bloqueante`, `importante` ou `sugestão`.

## 4. Corrigir
- Corrija todos os achados `bloqueante` e `importante` que procedem. Se discordar de um achado, registre o motivo; ele vai para o PR.
- Depois de corrigir, rode `make lint` e `make test`, faça commit (`fix: ...` ou o tipo adequado) e push, e faça uma nova rodada de revisão.
- No máximo **duas rodadas de correção**. Se ainda restarem achados bloqueantes, abra o PR mesmo assim como rascunho (`--draft`), liste os achados pendentes, aplique `escalonado` na issue e não aplique `pronto-revisao`.
- Para cada achado `bloqueante` ou `importante` que ficou sem corrigir, por discordância ou por pendência depois das duas rodadas, registre uma lição com o gatilho `achado-pendente`, um bloco por achado ([../licao/formato.md](../licao/formato.md)). No escalonamento por achados pendentes, essa é a única lição: não registre também `escalonado`.
- Sugestões não são aplicadas nem geram lição: elas vão listadas no PR para o usuário decidir.

## 5. Abrir o PR
Se já existir PR da branch (`gh pr view`), atualize a descrição em vez de abrir outro. Senão, `gh pr create`:

- **Título:** `<tipo da triagem>: <descrição curta em português>`, no padrão do `CLAUDE.md` (vira a mensagem do squash).
- **Corpo:**

  ```markdown
  ## Resumo
  <O que muda, em duas a quatro frases, citando a spec.>

  **Spec:** `specs/SPEC-<nº>.md` · **ADR:** <se houver>

  ## Critérios de aceite
  | ID | Status | Evidência |
  |---|---|---|
  | CA1 | ✅ | <teste que cobre, ou comando executado e resultado> |
  | CA2 | ✅ | <...> |

  ## Verificações manuais
  <Cada verificação da spec: comando executado e resultado observado.>

  ## Desvios da spec
  <Ajustes feitos em relação ao desenho técnico e por quê, ou "nenhum".>

  ## Revisão automática
  <Número de rodadas, achados corrigidos, achados de que discordou (com o motivo) e sugestões não aplicadas.>

  ## Para a sua revisão
  <Onde vale olhar com mais atenção: arquivos sensíveis, decisões, riscos.>

  Fixes #<nº>
  ```

## 6. CI, labels e resposta no PR
- Espere o CI: `gh pr checks --watch`. Se falhar por causa da mudança, corrija como no passo 4 (conta como rodada). Se precisou de duas ou mais correções por CI vermelho, registre uma lição com o gatilho `rodadas`, com os checks que falharam e o que os resolveu ([../licao/formato.md](../licao/formato.md)). Se falhar por motivo externo (instabilidade, credencial), registre no PR e siga.
- Com CI verde e sem achados bloqueantes: `gh issue edit <nº> --add-label pronto-revisao --remove-label escalonado`. Se o passo 2 escalou uma mudança de escopo, remova `pronto-revisao` se estiver aplicada (`gh issue edit <nº> --remove-label pronto-revisao`) e mantenha `escalonado`: o PR espera a mudança da spec, não a revisão do usuário.
- **Resposta no PR:** comente no PR (`gh pr comment <nº do PR> --body-file <arquivo>`) com o marcador `<!-- fabrica:revisar -->`. Esse comentário vira a nova âncora do passo 2, então publique-o sempre que aplicar `pronto-revisao` e sempre que tratar pedidos, mesmo com rascunho ou escalado:
  - **instante da coleta:** logo abaixo do marcador, a linha `**Pedidos lidos até:** <instante da coleta do passo 2>`;
  - **sem pedidos:** uma linha, "PR pronto para a sua revisão", com o resumo da revisão automática;
  - **com pedidos:** uma linha por pedido, com o trecho e o que foi feito (commit, escalado ou não procede, com o motivo);
  - **chegaram durante esta rodada:** antes de publicar, colete de novo pelos mesmos caminhos do passo 2, aplicando os "Termos" do passo 2: só conta comentário do usuário no PR posterior ao instante da coleta, que aqui faz o papel da referência, com o mesmo critério de data (criação do comentário ou `submittedAt` da review). Esses pedidos não são tratados agora: cite cada um com um trecho numa seção "Chegaram durante esta rodada" e avise que ficam para o próximo `/fabrica:revisar`. Sem nenhum, omita a seção.
  - **linha de custo:** por último, logo antes de publicar, acrescente ao fim do arquivo do corpo a linha do `implementar`, se ele trouxe uma, e em seguida a desta execução: `python3 <diretório base desta skill>/../../scripts/stage-usage.py --stage revisar --since <instante da coleta> >> <arquivo>`. O script nunca falha: sem log da sessão, a linha sai com `tokens=nao-medido`. Só esta resposta no PR leva a linha; o comentário na issue com o link do PR e o de lição não levam.
- Comente na issue com o link do PR e diga ao usuário no chat que o PR está pronto para a revisão dele, ou o que ficou escalado.

## Regras
- Nunca faça merge, nem aprove o próprio PR.
- Não mude a spec para fazer a implementação passar, nem por um pedido feito no PR. Se a spec estiver errada, comente na issue.
- Todo comentário seu, na issue ou no PR, começa com o marcador `<!-- fabrica:revisar -->` numa linha própria, exceto o comentário de lição, que segue [../licao/formato.md](../licao/formato.md). Os comentários do agente e do usuário saem da mesma conta do GitHub, e o marcador é o que os distingue (veja [estados.md](../status/estados.md)).
- Publique todo corpo de issue, comentário ou PR a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- O status de cada CA no PR precisa ter evidência; "implementado" sem evidência não conta.
- Se um `gh pr edit` ou um `gh issue edit` falhar por um erro do próprio `gh`, use o plano B de [../setup/gh.md](../setup/gh.md#plano-b-por-rest) e avise no chat. Uma label que não existe não é erro do `gh`: vale a regra abaixo.
- Se `gh issue edit` falhar porque uma label não existe, pare, comente na issue e diga no chat: "A label `<label>` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label sozinho. A exceção é a `licao`: sem ela, a etapa avisa e segue, como diz [../licao/formato.md](../licao/formato.md).
