# SPEC-14: Criar as labels da fábrica automaticamente em cada repositório

**Issue:** #14 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-10-28

## Contexto
O fluxo depende de seis labels (`agente`, `precisa-info`, `spec-pronta`, `spec-aprovada`, `escalonado`, `pronto-revisao`), definidas em `skills/status/estados.md`. Nenhuma skill as cria: no `kairo` foram criadas à mão, e na `fabrica` não foi possível aplicar `agente` na #13 até criá-las. Além disso, as descrições no GitHub já divergem de `estados.md` (não só a de `escalonado`), e as cores não estão registradas em lugar nenhum do repositório.

## Objetivo
Toda máquina com o plugin consegue criar ou corrigir as seis labels de um repositório com um comando idempotente, que roda sozinho no início de um projeto novo, e as skills que aplicam labels avisam como resolver quando uma label falta.

## Comportamento esperado
**Fonte da verdade:** a tabela "Labels" de `skills/status/estados.md` ganha a coluna `Cor`. A coluna `Significado` passa a ser também a descrição da label no GitHub (máximo de 100 caracteres, limite do GitHub).

**Script** `scripts/setup-labels.sh [<dono>/<repo>]`:
| Situação | Resultado |
|---|---|
| Sem argumento, dentro de um clone com remote no GitHub | Usa o repositório do diretório atual. |
| Label não existe | Cria com nome, cor e descrição da tabela. |
| Label existe com cor ou descrição diferente | Atualiza para a da tabela. |
| Label existe igual | Não muda nada; rodar de novo nunca falha. |
| Labels fora da tabela (`bug`, `enhancement` etc.) | Não são tocadas. |
| Sem argumento e fora de um repositório com remote no GitHub, `gh` não autenticado ou repositório inexistente | Sai com código diferente de zero e uma mensagem dizendo o que falta. Não cria nada pela metade sem avisar. |
| Tabela com linha malformada (sem cor, cor fora de `RRGGBB` ou descrição acima de 100 caracteres) | Sai com erro antes de chamar o GitHub, citando a label. |

Ao final, imprime uma linha por label (`ok <label>`) e o repositório alvo.

**Pontos de entrada:**
- **Projeto novo:** a skill `prd`, ao terminar de escrever o `docs/prd.md`, roda o script no repositório atual. Se ainda não houver remote no GitHub (repositório não criado), não falha: avisa que o setup roda com `/fabrica:setup` depois do `gh repo create`.
- **Repositório que já existe ou que não passa pela `prd`:** nova skill `/fabrica:setup [<dono>/<repo>]`, que só roda o script e mostra o resultado.
- **Label faltando numa etapa:** se `gh issue edit` falhar nas skills `triagem`, `spec`, `implementar` ou `revisar` porque a label não existe, a skill para, comenta na issue e diz no chat: "A label `<label>` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Ela não cria a label sozinha.

A label `agente` continua sendo aplicada só pelo usuário. O script apenas garante que ela exista.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Num repositório sem as labels, `scripts/setup-labels.sh <repo>` cria as seis, e `gh label list --json name,color,description` bate com a tabela de `estados.md` em nome, cor e descrição. | manual |
| CA2 | Rodar o script de novo sai com código 0 e mantém as seis labels, sem duplicar. Depois de mudar à mão a cor de uma label e a descrição de outra, uma nova execução restaura as duas. | manual |
| CA3 | A skill `prd` roda o script ao terminar, sem passo manual, e avisa em vez de falhar quando não há remote. `/fabrica:setup` existe e roda o script no repositório atual ou no repositório passado. | manual |
| CA4 | A descrição de `escalonado` é "O agente parou por falha e precisa do usuário. Sai quando a etapa é retomada." em `estados.md` e no GitHub da `fabrica` e do `kairo`. `git grep "modelo mais forte"` não encontra nada. | manual |
| CA5 | O README tem uma seção sobre o setup das labels (quando roda sozinho e quando rodar `/fabrica:setup`), e a `version` do plugin sobe um minor em relação à `main` no momento do merge. | manual |
| CA6 | Depois de rodar o script em `ftenorio99/kairo` e `ftenorio99/fabrica`, as seis labels de cada um batem com a tabela e as issues continuam com as labels que tinham antes. | manual |
| CA7 | Nas skills `triagem`, `spec`, `implementar` e `revisar`, uma falha por label inexistente gera a mensagem que indica `/fabrica:setup`. | manual |

## Fora de escopo
- Aplicar `agente` em issues ou criar issues.
- Labels genéricas do GitHub (`bug`, `enhancement` etc.) e labels que não estejam na tabela: o script não cria, não muda e não apaga.
- Apagar labels antigas ou renomeadas.
- Fazer o `/fabrica:status` detectar labels faltando.
- Rodar o setup no GitHub Actions (Fase 1).

## Desenho técnico
**Arquivos e módulos:**
- `skills/status/estados.md`: coluna `Cor` na tabela "Labels" e uma frase dizendo que a tabela é lida por `scripts/setup-labels.sh` e que `Significado` vira a descrição no GitHub, com no máximo 100 caracteres.
- `scripts/setup-labels.sh` (novo, executável): lê a tabela "Labels" de `estados.md` (caminho relativo ao próprio script), valida as linhas e chama `gh label create <nome> --color <cor> --description <texto> --force -R <repo>` para cada uma. Usa só `bash`, `awk` e `gh`.
- `skills/setup/SKILL.md` (novo): `/fabrica:setup [<dono>/<repo>]`, com `disable-model-invocation: true` como as demais. Roda o script a partir do diretório base da skill (`../../scripts/setup-labels.sh`) e mostra a saída.
- `skills/prd/SKILL.md`: passo final que roda o script e a regra "não altere outros arquivos" ganha a ressalva das labels.
- `skills/triagem/SKILL.md`, `skills/spec/SKILL.md`, `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md`: uma linha em "Regras" com a mensagem de label inexistente.
- `README.md`: seção "Labels" com o setup; linha de `skills/` na tabela "Conteúdo" passa a citar `setup`; nova linha para `scripts/`.
- `CLAUDE.md` da fábrica: `scripts/` na lista "Estrutura".
- `.claude-plugin/plugin.json`: próximo minor em relação à `main` (0.7.0 se a #13 entrar antes, que leva a 0.6.0).

**Dados:** valores da tabela "Labels" depois da mudança (as cores são as que já estão no GitHub da `fabrica` e do `kairo`):

| Label | Cor | Descrição no GitHub (= Significado) |
|---|---|---|
| `agente` | `5319e7` | A issue entra na fábrica. |
| `precisa-info` | `fbca04` | Há perguntas para o usuário na issue. |
| `spec-pronta` | `0e8a16` | Spec na branch, aguardando aprovação. |
| `spec-aprovada` | `1d76db` | Implementação liberada. Conta para o limite de 3 em andamento. |
| `escalonado` | `d93f0b` | O agente parou por falha e precisa do usuário. Sai quando a etapa é retomada. |
| `pronto-revisao` | `c2e0c6` | PR com CI verde e revisão automática feita, aguardando o usuário. |

**Interfaces:**
- `scripts/setup-labels.sh [<dono>/<repo>]`: saída `0` com uma linha `ok <label>` por label; diferente de `0` com mensagem em caso de erro.
- `/fabrica:setup [<dono>/<repo>]`.

**Decisões:**
- Fonte da verdade na tabela de `estados.md`, com a coluna `Cor` — as labels já estão descritas lá, e um segundo arquivo só com as labels criaria duas listas para manter em sincronia. Alternativa descartada: `templates/labels.tsv`, mais fácil de ler por script, mas duplicado.
- `Significado` vira a descrição no GitHub, e as descrições atuais (ex.: "A issue entra na fábrica e a triagem começa (aplicada pelo usuário)") são substituídas — quem aplica cada label já está na coluna `Quem aplica`, e um único texto evita divergência. Alternativa descartada: uma coluna a mais só para a descrição do GitHub.
- Pontos de entrada: `prd` automática para projeto novo e `/fabrica:setup` para os demais — a `agente` precisa existir antes da primeira issue, então rodar o setup na `triagem` chegaria tarde. Alternativa descartada: hook `SessionStart` do plugin, que mexeria nas labels de todo repositório aberto no Claude Code, mesmo os que não usam a fábrica.
- Skills de etapa só avisam quando a label falta, não rodam o setup sozinhas — é o que a issue pede, e criar labels é uma mudança de configuração do repositório que convém ficar visível. Alternativa descartada: autocorreção silenciosa.
- `gh label create --force` em vez de comparar antes e editar só o que difere — o resultado é o mesmo, o script fica menor e o custo são seis chamadas. Alternativa descartada: `gh label list` + `gh label edit` seletivo.

**Fontes da documentação:** `gh label create --force` (cria ou atualiza): manual do `gh` instalado (`gh label create --help`), a conferir na implementação.

**ADR:** nenhum (a decisão vale só para o próprio plugin e fica registrada aqui e em `estados.md`).

## Testes
A fábrica não tem `make test`; os critérios são verificados à mão e registrados no PR.
- **CA1 e CA2:** criar um repositório privado temporário (`gh repo create ftenorio99/fabrica-labels-teste --private`). Rodar o script e comparar `gh label list -R <repo> --json name,color,description` com a tabela. Rodar de novo e conferir o código de saída e a contagem. Mudar a cor de `spec-pronta` e a descrição de `escalonado` com `gh label edit`, rodar o script e conferir a restauração. No fim, apagar o repositório (`gh repo delete --yes`; se o token não tiver o escopo `delete_repo`, deixar registrado para o usuário apagar).
- **Casos de erro:** rodar o script sem argumento num diretório sem git e conferir que sai com erro e mensagem. Rodar com uma cópia de `estados.md` com uma cor inválida e conferir que falha antes de chamar o GitHub.
- **CA3:** ler o passo novo da `prd` e a skill `setup`. Rodar `/fabrica:setup` com `claude --plugin-dir` no clone da `fabrica` e conferir a saída.
- **CA4 e CA6:** rodar o script em `ftenorio99/fabrica` e `ftenorio99/kairo`. Comparar `gh label list` com a tabela. Conferir com `gh issue list --label <label>` que as issues que tinham cada label continuam com ela. Rodar `git grep "modelo mais forte"`.
- **CA5 e CA7:** ler o README, o `plugin.json` e as linhas novas das quatro skills.

## Riscos e dúvidas
- **Ações fora do repositório:** os testes criam e apagam um repositório temporário na conta, e o CA6 altera as labels do `kairo`. Os dois vão para confirmação nesta spec.
- O caminho do script dentro do plugin instalado depende do diretório base da skill, que aparece quando a skill carrega. Se a skill não conseguir resolvê-lo, usar `${CLAUDE_PLUGIN_ROOT}`, se estiver disponível em skills, e registrar o desvio.
- A `version` depende da ordem de merge com a #13.

## Histórico
- 2026-10-28: criação.
