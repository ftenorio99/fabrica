# SPEC-41: Fechar casos-limite no tratamento dos pedidos no PR

**Issue:** #41 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-04

## Contexto
A SPEC-38 (PR #40) fez o `/fabrica:revisar` tratar os comentários do usuário no PR. Ela usa como âncora o último comentário `<!-- fabrica:revisar -->` da conversa. A revisão automática do #40 deixou três sugestões sem aplicar:
- **Comentário durante a execução:** a coleta acontece no passo 2 e a âncora só sai no passo 6, depois do CI. Um comentário feito nesse intervalo fica mais antigo que a nova âncora. O `revisar` o perde sem aviso, e o `/fabrica:status` também não o enxerga.
- **Guia de issue escalonada:** o passo 3 não dá o caminho para o escalonamento por um pedido no PR que muda a spec.
- **Review `APPROVED` sem corpo:** o `estados.md` conta toda review do usuário como pedido novo. Num PR aberto por um bot (Fase 1), uma aprovação sem corpo deixaria o status em "Ajustes do PR pedidos".

## Objetivo
Nenhum pedido do usuário no PR se perde por chegar durante a execução do `/fabrica:revisar`. O guia de escalonamento indica o caminho certo, e uma aprovação sem corpo não conta como pedido.

## Comportamento esperado

### Instante da coleta na âncora
1. No início do passo 2 do `/fabrica:revisar`, antes de qualquer consulta ao PR, a skill guarda o instante atual em UTC: `date -u +%Y-%m-%dT%H:%M:%SZ`. Ele é o **instante da coleta** e vale para todas as execuções, com PR ou sem PR.
2. O comentário-âncora do passo 6 traz, logo abaixo do marcador, a linha `**Pedidos lidos até:** <instante da coleta>`.
3. **Pedido novo** passa a ser o comentário ou a review do usuário posterior ao instante da linha `Pedidos lidos até` da âncora. Uma âncora antiga, sem essa linha, usa a própria data de criação. Sem âncora, tudo conta, como hoje.
4. Antes de publicar a âncora, a skill coleta de novo pelos mesmos três caminhos. Os pedidos posteriores ao instante da coleta não são tratados nesta rodada. A âncora cita cada um deles com um trecho, numa seção "Chegaram durante esta rodada", e avisa que eles ficam para o próximo `/fabrica:revisar`.
5. O `/fabrica:status` lê a linha `Pedidos lidos até` da âncora e aplica a mesma regra. Um pedido feito durante a execução continua aparecendo como "Ajustes do PR pedidos" depois da resposta.

| Situação | Resultado |
|---|---|
| Comentário antes do instante da coleta | Tratado nesta rodada, como hoje. |
| Comentário entre a coleta e a âncora | Citado na âncora como "fica para a próxima rodada". O status mostra "Ajustes do PR pedidos". |
| Comentário depois da âncora | Pedido novo, como hoje. |
| Âncora antiga, sem a linha | A data da âncora é a referência, como hoje. |

### Review `APPROVED` sem corpo
- A review `APPROVED` de corpo vazio não é comentário do usuário: ela não conta como pedido novo no `estados.md` nem na coleta do `revisar`.
- A review `COMMENTED` de corpo vazio continua contando no `estados.md`, porque é por ela que o status vê um comentário em linha avulso. No `revisar`, o comentário em linha já é lido pela API REST.
- Uma review `APPROVED` com corpo continua contando, porque o corpo pode trazer um pedido.

### Guia de issue escalonada
O passo 3 de "O que fazer" em `docs/guias/issue-escalonada.md` ganha um terceiro caso. Quando a revisão parou por um pedido no PR que muda a spec, o caminho é remover `spec-aprovada`, rodar `/fabrica:spec <nº> <ajuste>`, aprovar de novo e retomar com `/fabrica:implementar <nº>`, como já diz `docs/guias/revisar-pr.md`. O caso "Se a revisão parou" fica para as pendências da revisão.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | No passo 2, o `skills/revisar/SKILL.md` manda guardar o instante da coleta antes de consultar o PR, com o comando `date -u`. O passo 6 manda a âncora trazer a linha `**Pedidos lidos até:** <instante>` logo abaixo do marcador. | manual (leitura) |
| CA2 | A definição de "pedido novo" no `revisar` usa o instante da linha `Pedidos lidos até` da âncora, com a data da âncora quando a linha falta e sem âncora tudo contando. | manual (leitura) |
| CA3 | Antes de publicar a âncora, o `revisar` coleta de novo. Ele cita na âncora, sem tratar, os pedidos posteriores ao instante da coleta, avisando que ficam para a próxima rodada. | manual (leitura) |
| CA4 | O `skills/status/estados.md` define "pedido novo no PR" pela mesma regra do CA2, e a coleta do `skills/status/SKILL.md` diz para ler a linha `Pedidos lidos até` da âncora. | manual (leitura) |
| CA5 | O `estados.md` e o `revisar` excluem a review `APPROVED` de corpo vazio. O `estados.md` mantém a review `COMMENTED` de corpo vazio contando, e a review `APPROVED` com corpo continua contando nos dois. | manual: leitura, e `gh pr view 40 --json reviews -q '.reviews[] \| [.state, .body, .submittedAt]'` para conferir os campos `state` e `body` |
| CA6 | O passo 3 de "O que fazer" em `docs/guias/issue-escalonada.md` tem o caminho do escalonamento por pedido no PR: remover `spec-aprovada`, `/fabrica:spec <nº> <ajuste>`, aprovar de novo e `/fabrica:implementar <nº>`. | manual (leitura) |
| CA7 | `docs/comandos.md` (seção `revisar`) e `docs/guias/revisar-pr.md` dizem que contam os comentários feitos depois do início da última revisão, e que os que chegam durante ela ficam para a próxima. Não sobra "depois da última resposta dela". | manual: leitura e `grep -rn "última resposta dela" docs/` sem resultado |
| CA8 | `.claude-plugin/plugin.json` sobe para `0.11.2`. | manual (leitura) |

## Fora de escopo
- Tratar na mesma execução os pedidos que chegam durante o `revisar`. Eles ficam para a próxima rodada.
- O erro de sintaxe da busca de backlog no `/fabrica:status`, que terá uma issue própria.
- Mudar o `/fabrica:implementar`, o subagente `revisor` ou o formato dos outros marcadores.
- Disparar o `/fabrica:revisar` automaticamente (dispatcher da Fase 1).

## Desenho técnico
**Arquivos e módulos:**
- `skills/revisar/SKILL.md`: "Termos" e início do passo 2 (instante da coleta, nova definição de pedido novo, `APPROVED` sem corpo), e passo 6 (linha `Pedidos lidos até`, segunda coleta e seção "Chegaram durante esta rodada").
- `skills/status/estados.md`: parágrafo da definição de comentário (exceção da `APPROVED` sem corpo e regra do pedido novo).
- `skills/status/SKILL.md`: o item da coleta de `comments,reviews` cita a linha `Pedidos lidos até`.
- `docs/guias/issue-escalonada.md`, `docs/guias/revisar-pr.md` e `docs/comandos.md`.
- `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:** a linha `**Pedidos lidos até:** <AAAA-MM-DDTHH:MM:SSZ>` no corpo da âncora `<!-- fabrica:revisar -->` passa a fazer parte do contrato entre o `/fabrica:revisar` e o `/fabrica:status`. O marcador continua igual, então a regra "comentário do agente começa com `<!-- fabrica:revisar -->`" não muda.

**Decisões:**
- **Registrar o instante da coleta na âncora e combiná-lo com a segunda coleta.** O instante fecha o caso de vez: o pedido fica posterior à referência, e tanto o status quanto o próximo `revisar` o enxergam. A segunda coleta só serve para avisar o usuário na resposta. Alternativas descartadas: (a) só conferir de novo antes da âncora, que encolhe a janela sem fechá-la e pode entrar em laço se os comentários continuarem chegando; (b) só citar na resposta, porque o pedido citado fica mais antigo que a âncora e o status deixa de vê-lo.
- **Instante numa linha do corpo, não um atributo no marcador** (`<!-- fabrica:revisar lido=... -->`): o marcador exato é o que as outras regras reconhecem como comentário do agente, e mudá-lo afetaria o `estados.md` inteiro.
- **Excluir só a `APPROVED` sem corpo:** a `COMMENTED` vazia é o sinal do comentário em linha avulso, e a `APPROVED` com corpo pode trazer um pedido.

**Fontes da documentação:**
- GitHub CLI (`gh pr view --json reviews`, campos `state`, `body` e `submittedAt`): versão instalada, conferida na execução do CA5. Nenhuma biblioteca nova.

**ADR:** nenhum.

## Testes
O repositório não tem `make test`: a mudança é texto de skill e manual. A evidência é a leitura de cada CA e os comandos do CA5 e do CA7. Depois do merge, o primeiro `/fabrica:revisar` com pedido no PR serve de teste real da linha `Pedidos lidos até`.

## Riscos e dúvidas
- **Relógio local diferente do GitHub:** o instante vem do relógio da máquina. Um relógio adiantado em segundos pode fazer um comentário feito logo antes da coleta contar de novo na próxima rodada. O efeito é tratar um pedido duas vezes, e a resposta mostra isso. Nunca se perde um pedido, e o risco é aceitável.
- **Âncoras antigas:** PRs com âncora sem a linha seguem a regra de hoje até a próxima resposta do `revisar`.

## Histórico
- 2026-11-04: criação.
