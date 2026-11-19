# Dispatcher no GitHub Actions (piloto)

O dispatcher é um workflow do GitHub Actions que roda as etapas de agente sem sessão na sua máquina: a cada gesto seu na issue ou no PR, o runner instala o Claude Code e o plugin, relê o estado da issue e roda as etapas até o próximo portão em que você age ([ADR 0015](../adr/0015-dispatcher-no-github-actions.md), [ADR 0017](../adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md)). No piloto, ele vale só para o repositório de teste `ftenorio99/fabrica-teste`; a instalação nos projetos pelo `/fabrica:setup` vem depois (#108).

## Os gestos que acordam o workflow
| Gesto | Evento |
|---|---|
| Aplicar `agente` ou `spec-aprovada` numa issue aberta | `issues: labeled` |
| Comentar na issue ou na conversa do PR (responder perguntas, pedir um ajuste da spec ou do PR) | `issue_comment: created` |
| Marcar um item da checklist de um comentário de ação, numa issue com `acao-externa` | `issue_comment: edited` |
| Enviar uma review no PR | `pull_request_review: submitted` |
| Comentar numa linha do PR | `pull_request_review_comment: created` |

O evento só acorda o workflow; quem decide a etapa é o estado da issue, relido pela tabela de [estados.md](../../skills/status/estados.md). Um gesto que não muda o estado (uma review aprovada sem texto, um item marcado com outro ainda aberto) termina verde, sem chamar o Claude.

**Sem cascata:** os comentários das etapas começam com `<!-- fabrica:` e as labels que elas aplicam (`modelo:*`, `precisa-info`, `spec-pronta`, `pronto-revisao`, `em-andamento`, `acao-externa`, `escalonado`) não são `agente` nem `spec-aprovada`: o filtro do job barra esses eventos, e o run deles termina `skipped`. A única exceção é a edição de um comentário `<!-- fabrica:acao`, que é o seu gesto de marcar a checklist. Por isso, ao comentar à mão, não comece o texto com `<!-- fabrica:`: o comentário seria ignorado.

## O que ele faz
1. **Resolve a issue.** Num gesto na issue, é a própria issue. Num gesto no PR, é a issue que o PR fecha: o PR precisa estar aberto, citar **exatamente uma** issue com `Fixes #<nº>` e ter como branch a branch da issue (a do comentário de spec ou da spec curta do atalho). Fora disso, o run termina verde sem fazer nada. A issue precisa estar aberta e ter a label `agente`; a issue de runbook do `/fabrica:lancamento`, sem `agente`, fica de fora.
2. **Freio:** se a issue já recebeu 8 ou mais `em-andamento` na última hora, ele não roda nada e comenta na issue com o motivo `freio` (veja [Freio](#freio)).
3. **`em-andamento`:** respeita a label como o `/fabrica:avancar`: se outra execução a aplicou há menos de 2 h, ele não pega a issue. Esquecida (2 h ou mais), ele a renova.
4. **Estado:** relê o estado pelo `scripts/issue-state.py`. Num portão seu (Bloqueado, Ação externa pendente, Perguntas abertas, Spec para aprovar, PR com pendências, PR para revisar) ou numa inconsistência, termina verde sem mexer em nada; a inconsistência aparece no `/fabrica:status`.
5. **Laço:** aplica a `em-andamento` uma vez e roda a etapa do estado; relê o estado e roda a seguinte, até chegar a um portão seu. Para também quando a etapa não muda o estado (por exemplo, o limite de 3 em andamento), quando o estado relido tem uma inconsistência ou quando uma etapa falha. O `implementar` já encadeia o `revisar` e conta como uma etapa. No fim, remove a `em-andamento`, com sucesso ou com falha.
6. **Teto:** no máximo 4 etapas por run, como no `/fabrica:avancar`. Se a issue ainda está num estado de agente depois da 4ª, ele comenta na issue com o motivo `teto` e o estado em que ela ficou; para seguir, rode `/fabrica:avancar <nº>` na sua máquina ou faça um novo gesto.

Exemplos: aplicar `agente` numa issue nova roda a triagem e a spec e para em "Spec para aprovar"; aplicar `spec-aprovada` roda o `implementar` com o `revisar` e para em "PR para revisar"; um comentário no PR roda o `revisar`.

O dispatcher não faz o escalonamento de modelo do `/fabrica:avancar` (lição `modelo` e troca da `modelo:*`): ele usa a `modelo:*` da issue como está.

**Concorrência e tempo:** um run por número de evento de cada vez (grupo `fabrica-<nº da issue ou do PR>`, sem cancelar o que está rodando; o GitHub guarda só o pendente mais novo do grupo, e ele relê o estado). O run barrado pelo filtro fica num grupo só dele (`fabrica-ignorado-<run_id>`), para não tomar a vez do run de um gesto. A trava entre um evento da issue e um do PR é a `em-andamento`. O passo do despacho tem 100 min e o job, 110 min, abaixo das 2 h da `em-andamento`, para caber o `implementar` com o `revisar`.

## Freio
O filtro por marcador é a trava principal contra cascata, mas um comentário de etapa sem marcador (um erro da etapa) faria cada run disparar o seguinte. O freio limita essa corrente: com 8 ou mais eventos `labeled em-andamento` na issue nos últimos 60 min (3.600 s, inclusive), o dispatcher não roda a etapa e comenta na issue com `<!-- fabrica:dispatcher -->`, o motivo `freio` e o número de execuções. Confira os comentários da issue e, se estiver tudo certo, rode `/fabrica:avancar <nº>` na sua máquina. O freio sai sozinho quando a janela de 1 h passa.

O agente roda isolado (veja [Isolamento do job](#isolamento-do-job)). A lógica fica no `scripts/dispatch.sh` do plugin; o workflow só prepara o runner e chama o script. A etapa roda pelo mesmo `scripts/stage-model.sh run` do `/fabrica:avancar`, com o modelo de [modelos.md](../../skills/avancar/modelos.md) e o modo de permissão `auto`.

## Como ligar num repositório
1. **Copie o workflow:** `templates/workflows/agente.yml` do plugin vai para `.github/workflows/agente.yml` do repositório, na branch padrão (o GitHub só roda workflows de `issues` a partir dela). Como a `main` é protegida, a cópia entra por PR.
2. **Labels:** rode `bash scripts/setup-labels.sh <dono>/<repo>` do plugin, se o repositório ainda não as tem.
3. **Secret `CLAUDE_CODE_OAUTH_TOKEN`:** gere com `claude setup-token` na sua máquina (usa a sua assinatura). Copie o valor **inteiro**, começando em `sk-ant-oat01-`, e cadastre sem colar no prompt: com o valor numa variável do terminal, `printf '%s' "$TOKEN" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <dono>/<repo>`. Antes, teste o valor na sua máquina: `env -u ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" claude -p "responda ok" --output-format json` deve dar `is_error` falso.
4. **Secret `FABRICA_PLUGIN_TOKEN`:** o repositório `ftenorio99/fabrica` é privado, e o token do job só alcança o próprio repositório. Crie um token *fine-grained* em GitHub → Settings → Developer settings → Fine-grained tokens, com acesso só ao repositório `ftenorio99/fabrica` e só a permissão **Contents: read**, e cadastre com `gh secret set FABRICA_PLUGIN_TOKEN --repo <dono>/<repo>`.
5. **Secret `FABRICA_GH_TOKEN`:** é o token das escritas do job (labels, comentários, o que o agente faz pelo `gh`). Crie outro token *fine-grained* com acesso **só ao repositório do projeto**, expiração de até 90 dias e as permissões: Contents, Issues e Pull requests em leitura e escrita; Actions e Commit statuses em leitura; Metadata em leitura (obrigatória). **Não** dê Workflows. Cadastre com `gh secret set FABRICA_GH_TOKEN --repo <dono>/<repo>`. Renove-o antes de expirar: um token expirado derruba o job com erro do `gh`.

Cada secret aparece só no passo que o usa: o `FABRICA_PLUGIN_TOKEN` no passo que instala o plugin, o `CLAUDE_CODE_OAUTH_TOKEN` e o `FABRICA_GH_TOKEN` no passo que trava o isolamento, e o `FABRICA_GH_TOKEN` também nos passos que escrevem no GitHub (despacho, desmarcar e comentar a falha).

## Isolamento do job
Antes de a etapa rodar, o job fecha o agente numa caixa ([ADR 0016](../adr/0016-isolamento-do-job-do-dispatcher.md)):
- **Dois usuários.** O `claude -p` e tudo o que ele executa rodam como `fabrica-agent`, sem `sudo` e sem rede direta. Um proxy local (`mitmproxy`) roda como `fabrica-proxy` e guarda os segredos.
- **Rede.** As regras do `iptables` só deixam o `fabrica-agent` falar com a porta do proxy. O proxy libera só os hosts de `templates/workflows/dominios-liberados.txt` (a API da Anthropic e o GitHub) e responde 403 ao resto. A lista vem do plugin instalado no job: ela não é copiada para o projeto.
- **Segredos.** O agente recebe **marcadores** no lugar do `CLAUDE_CODE_OAUTH_TOKEN` e do `FABRICA_GH_TOKEN`. O proxy troca o marcador pelo valor real só no cabeçalho `Authorization` e só nos hosts daquele segredo. O valor real nunca chega ao ambiente nem aos arquivos que o agente lê.
- **Falha fechada.** Sem lista de domínios válida, ou sem um dos dois tokens, o `lock` falha e o agente não roda.

A lista cobre as etapas que só falam com a Anthropic e o GitHub. O `implementar` de um projeto que baixa dependências (npm, Docker Hub etc.) vai precisar de hosts a mais; isso fica para a #108.

**Ampliar a lista:** o log do proxy aparece no fim do run, no passo "Mostra o log do proxy": cada linha `bloqueado <host>` é um pedido que o proxy recusou. Se a etapa precisa do host, acrescente só o host exato ao `dominios-liberados.txt` **do plugin** (um PR na fábrica; a lista por projeto fica para a #108), com uma linha de comentário dizendo o motivo, e rode o aceite de novo. Não use curinga largo (`*.github.com` abre o `gist.github.com`).

**Teste de aceite:** copie também `templates/workflows/isolamento-aceite.yml` para `.github/workflows/` do repositório de teste e rode pela aba Actions (*Run workflow*). Ele repete a preparação e roda o `scripts/test-job-acceptance.sh`, que imprime `ok <verificação>` ou `falha <verificação>: <motivo>`:

| Verificação | O que confere |
|---|---|
| `agente-sem-rede-direta` | O agente não alcança um IP nem um nome sem passar pelo proxy. |
| `dominio-liberado` | `gh api user` funciona pelo proxy, com o marcador. |
| `dominio-fora-da-lista` | `example.com` recebe 403 do proxy. |
| `git-pelo-proxy` | `git ls-remote` do próprio repositório funciona, com o marcador no `Basic`. |
| `marcador-no-ambiente` | O `CLAUDE_CODE_OAUTH_TOKEN` e o `GH_TOKEN` do agente são marcadores. |
| `segredo-fora-do-alcance` | Nenhum arquivo nem `/proc/*/environ` legível pelo agente tem os valores reais. |
| `ca-privada-ilegivel` | O agente não lê a chave privada da CA do proxy. |
| `sem-sudo` | O agente não roda `sudo`. |
| `home-sem-token` | O home do agente não guarda o `FABRICA_PLUGIN_TOKEN`. |
| `proxy-so-lista` | O log do proxy mostra o bloqueio e só hosts da lista. |

Rode o aceite depois de mudar a lista de domínios, o proxy ou a versão do `mitmproxy`.

## Quando falha
O job fica vermelho e a issue resolvida recebe um comentário que começa com `<!-- fabrica:dispatcher -->`, com a etapa que falhou (`não decidida` quando a falha veio antes da primeira etapa), o motivo e o link do run. Num gesto no PR em que o dispatcher nem chegou a resolver a issue (o `gh` não leu o PR), o comentário vai para o PR:

| Motivo | O que aconteceu |
|---|---|
| `permissao` | O modo `auto` negou ferramentas à etapa; o comentário lista os nomes delas. |
| `erro` | O Claude saiu com erro, terminou com `is_error` ou não devolveu um JSON legível. |
| `labels` | A issue tem duas ou mais labels `modelo:*`; deixe uma só. |
| `sem-resultado` | A etapa não chegou a devolver resultado: tempo esgotado ou erro antes do Claude, ao ler a issue ou o PR. |

O comentário não traz o texto da resposta do Claude nem valores de secrets; os detalhes ficam no log do run. Ele não muda o estado da issue ([estados.md](../../skills/status/estados.md)): corrija a causa e rode `/fabrica:<etapa> <nº>` ou `/fabrica:avancar <nº>` na sua máquina, ou repita o gesto (comente de novo, ou remova e reaplique a label).

Uma falha na instalação do Claude Code ou do plugin (secret errado ou ausente, por exemplo) também deixa um comentário, com a etapa `não decidida` e o motivo `sem-resultado`, na issue ou, num gesto no PR, no próprio PR. Como o script que comenta vem do próprio plugin, esse comentário sai de um passo de reserva do workflow, com texto fixo e só o link do run. Veja a causa no log do run.

## Limites do piloto
- **O agente ainda age com o token do GitHub:** o marcador esconde o valor, mas um agente enganado pode pedir ao proxy qualquer operação que o `FABRICA_GH_TOKEN` permita no repositório do projeto. O limite é o escopo do token: só o repositório, sem Workflows e com expiração curta. Use o piloto só em repositório de teste, com issues escritas por você.
- **O token novo dispara workflows:** ao contrário do `GITHUB_TOKEN`, os eventos criados com o `FABRICA_GH_TOKEN` disparam outros workflows, inclusive este. Por isso a trava contra cascata é o filtro do job (marcador `<!-- fabrica:` e nome da label), seguida da releitura do estado, do teto e do [freio](#freio). As labels e os comentários das etapas geram runs que terminam `skipped`.
- **Gesto com outra execução em curso:** um gesto feito enquanto um run trabalha na mesma issue (por exemplo, um comentário no PR durante o `implementar`) vira pulo pela `em-andamento` recente. O laço em curso relê o estado depois de cada etapa e costuma pegá-lo; se ele já tinha passado desse ponto, o gesto fica sem execução até o próximo gesto ou o `/fabrica:avancar`.
- **Comentário em linha gasta dois runs:** ele gera um evento de review e um de comentário de review. Um deles roda a etapa; o outro termina em pulo depois da instalação (2 a 3 min de runner).
- **Hosts de dependências do `implementar`:** a lista de domínios ainda não tem os registros de pacotes; um `implementar` que baixa dependências falha no proxy (#108).
- **CI do PR do agente:** com o `FABRICA_GH_TOKEN`, o PR que o agente abrir dispara o CI sozinho, sem a aprovação manual do run que o `GITHUB_TOKEN` exigia.
- **Linha de custo:** depende do log da sessão no runner; sem ele, sai `tokens=nao-medido`.
