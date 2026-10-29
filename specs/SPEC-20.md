# SPEC-20: Criar backlog no GitHub a partir do PRD com milestones por marco e planejamento em ondas

**Issue:** #20 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-10-29

## Contexto
O fluxo vai do PRD (`/fabrica:prd`) direto para a triagem. O fatiamento fica como uma lista no `docs/prd.md`, e cada issue é criada à mão: no `kairo`, os itens 1 e 2 viraram as issues #2 e #6 assim, sem registro no PRD. Quando não há nada no fluxo, o `/fabrica:status` manda "criar a próxima issue a partir do fatiamento", mas nenhuma skill faz isso. Falta a etapa de backlog.

## Objetivo
Um comando cria e mantém o backlog no GitHub a partir do PRD. Todas as milestones são criadas de uma vez, e as issues só para os dois marcos mais próximos. O `/fabrica:status` passa a mostrar o avanço por milestone e a indicar qual issue de backlog puxar.

## Comportamento esperado

### Formato do fatiamento no PRD
A seção "Fatiamento inicial" do `docs/prd.md` passa a se chamar "Fatiamento" e a agrupar os itens por marco:

```markdown
## Fatiamento
Itens de 1 a 2 dias de trabalho humano, agrupados por marco e em ordem de dependência dentro de cada marco. O número do item é fixo: não renumere; item novo recebe o próximo número livre.

### M1 · Base
- **1.** Criar o app Next.js com TypeScript, ESLint, Prettier, Vitest, Makefile e CI (base) · #2
- **2.** Configurar Postgres com Drizzle e ambiente local em Docker (base) · depende de 1 · #6

### M2 · Tarefas (F2, F11, F12)
- **5.** Modelo e API de tarefas (F2) · depende de 2
```

- O título do marco (`M1 · Base`) é o título da milestone no GitHub. O prefixo `M<n>` dá a ordem e identifica o marco mesmo se o nome mudar.
- Cada item tem número fixo, título, funcionalidades entre parênteses (`F2`, ou `base` quando não há F) e, quando houver, `depende de <números>`. Ao ganhar issue, recebe `· #<nº>` no fim.
- Sem `depende de`, o item não tem dependência. A ordem na lista não cria dependência implícita.

### Termos
- **Item com issue:** item que tem uma issue com o marcador `<!-- fabrica:backlog item=<n> -->` no corpo, ou cujo número está anotado no PRD. O marcador vale mesmo antes do merge do PR que anota o PRD.
- **Marco atual:** o primeiro marco, na ordem `M<n>`, que tem issue aberta ou item sem issue.
- **Perto de fechar:** o marco atual não tem item sem issue e tem no máximo 2 issues abertas. O número 2 vem do limite de 3 em andamento.
- **Janela:** o marco atual e o seguinte. Quando o marco atual está perto de fechar, a janela avança um marco, para o seguinte e o depois dele.

### `/fabrica:backlog` (skill nova)
Roda no clone do projeto, sem argumentos.

1. **Ler:** carrega o `docs/prd.md` da `main` atualizada, as milestones (`gh api repos/<repo>/milestones?state=all`) e todas as issues, abertas e fechadas, com corpo, labels e milestone.
2. **Migrar, se preciso:**
   - **PRD sem marcos** (fatiamento numa lista única, como no `kairo`): propõe o agrupamento em marcos, com nomes e as F de cada um. Mantém os números dos itens e propõe as dependências explícitas.
   - **Item sem issue registrada:** procura issue já existente sem marcador cujo título, sem diferença de maiúsculas e de espaços nas pontas, seja igual ao do item. Títulos parecidos, mas não iguais, entram como "possível par".
   - Os dois casos aparecem no plano para confirmação.
3. **Planejar:** monta o plano com:
   - milestones a criar ou atualizar (título e descrição);
   - issues de backlog a criar, só dos itens sem issue nos marcos da janela;
   - pares a vincular (issue existente ↔ item);
   - issues de backlog sem `agente` a atualizar, quando o título, a F, as dependências ou o marco mudaram no PRD;
   - issues que já estão no fluxo (com `agente`) e divergem do PRD, só listadas;
   - issues de backlog cujo item saiu do PRD, com proposta de fechamento.
4. **Confirmar:** mostra o plano no chat e pede confirmação com o AskUserQuestion: aplicar tudo, aplicar sem os possíveis pares, ou cancelar. Plano vazio: diz "backlog em dia" e para, sem criar nada.
5. **Aplicar**, em ordem:
   - **Milestones:** cria as que faltam com `gh api -X POST repos/<repo>/milestones` e atualiza a descrição das que mudaram com `PATCH`. A descrição lista os itens do marco, um por linha: `<n>. <título> (<F>)`. Nunca apaga milestone.
   - **Issues novas:** cria em ordem de número com `gh issue create --milestone "<título do marco>" --label enhancement`, no formato abaixo. Os números das dependências são resolvidos para `#<nº>` das issues já existentes ou recém-criadas.
   - **Pares confirmados:** põe a issue na milestone (`gh issue edit --milestone`), inclusive se estiver fechada, e acrescenta o marcador e as linhas do formato abaixo ao fim do corpo, sem apagar o texto que já existe.
   - **Issues de backlog sem `agente` a atualizar:** reescreve título, corpo e milestone.
   - **Fechamento:** não fecha nada sozinho. Fecha só as issues que o usuário confirmar no passo 4 (`gh issue close --reason "not planned"`).
   - **PRD:** grava no `docs/prd.md` o agrupamento, quando houve migração, e o `· #<nº>` de cada item novo ou vinculado. Faz isso na branch `docs/backlog`, criada a partir da `main` ou reaproveitada se já existir com PR aberto, com commit `docs: registra issues do backlog no prd`, e abre ou atualiza o PR. O merge é do usuário.
6. **Resumir:** lista as milestones, as issues criadas, vinculadas e atualizadas, as divergências no fluxo e o link do PR. Sugere puxar a primeira issue do marco atual com dependências fechadas (aplicar `agente`).

**Formato da issue de backlog:**
```markdown
<!-- fabrica:backlog item=5 -->
**Funcionalidade:** F2 · **Item do fatiamento:** 5 · **Marco:** M2 · Tarefas (F2, F11, F12)
**PRD:** [docs/prd.md](https://github.com/<dono>/<repo>/blob/main/docs/prd.md#fatiamento)

Depende de #12
```
A linha `Depende de` só aparece quando houver dependência, com as issues separadas por vírgula. Título da issue = título do item, sem a F e sem as dependências.

**Casos de erro e limites:**
| Situação | Resultado |
|---|---|
| Sem `docs/prd.md` ou sem seção de fatiamento | Para e indica `/fabrica:prd`. |
| Fora de um clone com remote no GitHub | Para e diz o que falta. |
| Label `enhancement` inexistente | Cria a issue sem a label e avisa no resumo. |
| Usuário cancela no passo 4 | Nada é criado nem alterado. |
| Falha no meio do passo 5 | Para, mostra o que já foi aplicado e o erro. Rodar de novo continua de onde parou, porque o marcador e as milestones existentes impedem duplicação. |
| Branch `docs/backlog` com PR já mergeado | Cria a branch de novo a partir da `main`. |

### Skill `prd`
- `skills/prd/template.md` e o passo de escrita de `skills/prd/SKILL.md` adotam o formato de fatiamento acima: marcos `M<n> · <nome> (<F>)`, números fixos e `depende de` explícito.
- Em atualização de PRD, itens novos recebem o próximo número livre, e itens removidos não têm o número reaproveitado.
- O passo final passa a indicar `/fabrica:backlog` como próximo passo, depois do merge do PR do PRD.

### `/fabrica:status`
- **Coleta:** além das issues com `agente`, busca as milestones abertas de cada repositório do dono e as issues abertas sem `agente` que tenham milestone e o marcador `<!-- fabrica:backlog`.
- **Avanço:** nova seção `## Marcos`, com uma linha por repositório que tenha milestones: marco atual com `fechadas/total` e o próximo marco com `fechadas/total`, ou "sem issues" se ainda não tiver nenhuma.
- **Próxima issue:** em cada repositório sem nenhuma issue com `agente` aberta, sugere "aplicar `agente` na #N". N é a issue de backlog do marco atual com o menor número de item cujas issues do `Depende de` estão todas fechadas. Se não houver nenhuma assim, diz que o marco atual está bloqueado por dependência e cita a issue. Repositório com PRD e sem milestones: sugere `/fabrica:backlog`.
- **Alerta:** quando o marco atual está perto de fechar e o marco depois do próximo existe no GitHub sem nenhuma issue, alerta "rode `/fabrica:backlog` em `<repo>`".
- Sem nada no fluxo nem no backlog em nenhum repositório, a frase final passa a ser: sem nada no fluxo; para um projeto novo, `/fabrica:prd`; para um PRD sem backlog, `/fabrica:backlog`.

### Máquina de estados (`skills/status/estados.md`)
- Nova seção "Backlog": uma issue aberta sem `agente`, com milestone e marcador `<!-- fabrica:backlog item=<n> -->`, está no estado **Backlog**. Quem age é o usuário, e o próximo passo é aplicar `agente`. Ela fica fora da tabela de estados do fluxo, que continua valendo só para issues com `agente`.
- Registra a ordem de sugestão (marco atual, menor número de item, dependências fechadas), as definições de marco atual, perto de fechar e janela, e o marcador `fabrica:backlog` na lista de marcadores.

### Geral
- `README.md`: o fluxo passa a começar em `prd → backlog`, ganha uma seção "Backlog" com o formato do fatiamento, as ondas e o gesto de aplicar `agente`, e a tabela "Conteúdo" cita a skill `backlog`.
- `.claude-plugin/plugin.json`: `version` 0.7.1 → 0.8.0.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Num repositório de teste com PRD de 3 marcos e 7 itens e sem milestones, `/fabrica:backlog` mostra o plano e, depois da confirmação, cria as 3 milestones com a lista de itens na descrição e as issues só do M1 e do M2, sem `agente`. Cancelar no passo 4 não cria nada. | manual |
| CA2 | Rodar de novo logo depois, com o PR do PRD ainda sem merge e sem mudanças no PRD, resulta em "backlog em dia" e nenhuma milestone ou issue nova. | manual |
| CA3 | Depois de fechar as issues do M1 até sobrarem 2 abertas, rodar de novo cria as issues do M3 e nenhuma outra. | manual |
| CA4 | Cada issue criada tem a milestone do seu marco, o marcador `item=<n>`, a F, o número do item, o link para o PRD e `Depende de #x` exatamente quando o item declara dependência, com o número certo. | manual |
| CA5 | O PR `docs/backlog` anota `· #<nº>` em cada item que ganhou issue e não muda nenhuma outra linha do PRD, salvo o agrupamento quando há migração. | manual |
| CA6 | Depois de mudar no PRD o título de um item com issue de backlog sem `agente`, o título de um item com issue em `agente` e remover um terceiro item, rodar de novo atualiza só a primeira issue, lista a segunda como divergência e propõe fechar a terceira sem fechá-la antes da confirmação. | manual |
| CA7 | Num PRD em lista única com uma issue antiga fechada de título igual a um item, o plano propõe os marcos e o par. Depois da confirmação, a issue fechada fica na milestone, com o marcador, e o item fica anotado no PRD. | manual |
| CA8 | `/fabrica:status` no repositório de teste mostra a seção "Marcos" com `fechadas/total`, sugere aplicar `agente` na issue certa (dependências fechadas, menor número de item) e mostra o alerta de `/fabrica:backlog` quando o marco atual está perto de fechar e o seguinte não tem issues. | manual |
| CA9 | `estados.md` tem a seção "Backlog", o template e a skill `prd` usam o formato novo, o README cita a skill e o fluxo, e a `version` é 0.8.0. | manual |

## Fora de escopo
- Sprints, datas de milestone e estimativas.
- Aplicar `agente` automaticamente.
- Execução paralela por marco (#16).
- Labels de prioridade: a ordem vem do fatiamento e das dependências.
- Rodar o `/fabrica:backlog` no `kairo` de verdade. É o primeiro uso real, depois do merge, por decisão do usuário.
- Mover a issue de milestone quando o item muda de marco e a issue já está em `agente` (só lista a divergência).

## Desenho técnico
**Arquivos e módulos:**
- `skills/backlog/SKILL.md` (novo): a skill descrita acima, com `disable-model-invocation: true`, `argument-hint` vazio e as regras de marcador e de não tocar issues com `agente`.
- `skills/prd/SKILL.md` e `skills/prd/template.md`: formato do fatiamento e próximo passo.
- `skills/status/SKILL.md`: coleta das milestones e do backlog, seção "Marcos", sugestão de próxima issue, alerta e frase final.
- `skills/status/estados.md`: seção "Backlog" e marcador.
- `README.md` e `.claude-plugin/plugin.json`.

**Dados:** nenhum arquivo de estado. O estado do backlog vem das milestones, do marcador no corpo das issues e da anotação no PRD.

**Interfaces:**
- `/fabrica:backlog`, sem argumentos.
- Marcador `<!-- fabrica:backlog item=<n> -->` na primeira linha do corpo da issue.
- API do GitHub: `GET/POST/PATCH repos/<repo>/milestones`, `gh issue create --milestone`, `gh issue edit --milestone/--title/--body-file`, `gh issue close --reason "not planned"`.

**Decisões:**
- **Identidade do item:** número fixo no PRD e marcador no corpo da issue. O marcador é o que garante a idempotência antes do merge do PR do PRD. Alternativa descartada: casar só por título, que quebra quando o título muda no PRD.
- **Título da milestone com prefixo `M<n> · `:** dá a ordem dos marcos sem ler o PRD, o que o `/fabrica:status` precisa para olhar vários repositórios, e permite renomear o marco. Alternativa descartada: ordenar por data de vencimento, que exigiria datas, e o escopo exclui datas.
- **Dependência explícita (`depende de`):** o `Depende de #x` da issue vem de um dado, não de um palpite. Alternativa descartada: tratar o item anterior como dependência, o que travaria itens independentes.
- **Label `enhancement` em toda issue de backlog:** o tipo real (`feat`, `fix`, `chore`…) é decidido na triagem. Alternativa descartada: inferir o tipo pelo título antes da triagem.
- **Janela de dois marcos que avança com "perto de fechar" (no máximo 2 abertas):** cumpre o CA3 sem esperar o marco fechar inteiro e mantém cada execução limitada a dois marcos. Alternativa descartada: um percentual do marco, que se comporta mal em marcos de 2 ou 3 itens.
- **Anotação do PRD num PR `docs/backlog` separado:** segue a regra de nunca commitar na `main` e mantém as issues criadas independentes do merge. Alternativa descartada: anotar só nas issues, o que perderia a rastreabilidade no próprio PRD pedida pela issue.
- **Confirmação no chat, não na issue:** o backlog roda antes de existir uma issue para conversar, e o plano é um passo único. Alternativa descartada: abrir uma issue de planejamento, o que é burocracia sem ganho.

**Fontes da documentação:**
- GitHub REST API (milestones) e `gh` 2.46.0: `gh issue create/edit/list --help` locais confirmam `--milestone` por título. Para a API de milestones (`POST/PATCH repos/{owner}/{repo}/milestones`), não verificada.

**ADR:** nenhum. O formato do fatiamento e o marcador são internos da fábrica e ficam registrados em `estados.md` e no template do PRD.

## Testes
Não há suíte automatizada para skills. Todos os critérios são verificados à mão com `claude --plugin-dir ~/projetos/fabrica` num repositório de teste:
- **Repositório:** privado e temporário, `ftenorio99/fabrica-backlog-teste`, criado com autorização do usuário e apagado no fim. Tem um `docs/prd.md` de 3 marcos e 7 itens, com dependências, e um segundo PRD em lista única para o CA7.
- **Roteiro:** CA1, depois CA2 sem mergear o PR, CA4 e CA5 conferidos com `gh issue view` e `gh pr diff`, CA3 fechando issues à mão, CA6 editando o PRD na `main` via PR, CA8 com `/fabrica:status ftenorio99/fabrica-backlog-teste` em cada ponto e CA7 num reset do repositório com o PRD em lista única.
- **CA9:** conferido no diff.

Cada verificação é registrada no PR com o comando e o resultado.

## Riscos e dúvidas
- **Repositório de teste:** criar e apagar o repositório exige autorização do usuário, como na #14, e o `gh` precisa do escopo `delete_repo` para apagar.
- **Bug do `gh` 2.46 em comandos de edição:** o `gh pr edit` falha com o erro de Projects (classic). Se o `gh issue edit --milestone` falhar igual, o caminho é o `PATCH repos/<repo>/issues/<n>` com `milestone=<número>`, a registrar como desvio.
- **Casamento por título:** pode ter falso par. Por isso, todo par passa pela confirmação, e os "possíveis pares" podem ser excluídos com uma opção própria.
- **Tamanho:** está no limite do G. Se a parte do `status` (CA8) crescer na implementação, dá para separá-la numa issue seguinte, com acordo do usuário.

## Histórico
- 2026-10-29: criação.
