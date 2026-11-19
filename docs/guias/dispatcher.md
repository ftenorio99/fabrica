# Dispatcher no GitHub Actions (piloto)

O dispatcher é um workflow do GitHub Actions que roda a etapa de agente sem sessão na sua máquina: você aplica a label `agente` numa issue, e o runner instala o Claude Code e o plugin e roda o `/fabrica:triagem` ([ADR 0015](../adr/0015-dispatcher-no-github-actions.md)). No piloto, ele vale só para o repositório de teste `ftenorio99/fabrica-teste`; a instalação nos projetos pelo `/fabrica:setup` vem depois (#108).

## O que ele faz
- Dispara só quando a label aplicada é `agente` e a issue está aberta. As labels que as etapas aplicam (`modelo:*`, `precisa-info`, `spec-pronta`, `em-andamento`) não disparam nada, então não há cascata.
- Roda só a **triagem**, e só numa issue em "Aguardando triagem" (sem comentário de triagem). Numa issue já triada, ele termina verde sem chamar o Claude e sem comentar. As etapas seguintes continuam pela sua máquina (`/fabrica:avancar`) até a retomada por evento (#107).
- Respeita a `em-andamento` como o `/fabrica:avancar`: se outra execução aplicou a label há menos de 2 h, ele não pega a issue. Quando é ele quem aplica a label, ele a remove no fim, com sucesso ou com falha.
- Uma execução por issue de cada vez (grupo de concorrência `fabrica-<nº>-<label>`: o nome da label no grupo faz a rodada pulada de outra label não disputar com a rodada da `agente`), com 30 min para a etapa e 40 min para o job.

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

O isolamento cobre a **triagem**. As etapas que baixam dependências (`implementar`) vão precisar de hosts a mais na lista; isso fica para a #108.

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
O job fica vermelho e a issue recebe um comentário que começa com `<!-- fabrica:dispatcher -->`, com a etapa, o motivo e o link do run:

| Motivo | O que aconteceu |
|---|---|
| `permissao` | O modo `auto` negou ferramentas à etapa; o comentário lista os nomes delas. |
| `erro` | O Claude saiu com erro, terminou com `is_error` ou não devolveu um JSON legível. |
| `labels` | A issue tem duas ou mais labels `modelo:*`; deixe uma só. |
| `sem-resultado` | A etapa não chegou a devolver resultado: tempo esgotado ou erro antes do Claude, ao ler a issue. |

O comentário não traz o texto da resposta do Claude nem valores de secrets; os detalhes ficam no log do run. Ele não muda o estado da issue ([estados.md](../../skills/status/estados.md)), que continua em "Aguardando triagem": corrija a causa e reaplique `agente` (remova e aplique de novo), ou rode `/fabrica:triagem <nº>` na sua máquina.

Uma falha na instalação do Claude Code ou do plugin (secret errado ou ausente, por exemplo) também deixa um comentário, com o motivo `sem-resultado`. Como o script que comenta vem do próprio plugin, esse comentário sai de um passo de reserva do workflow, com texto fixo e só o link do run. Veja a causa no log do run.

## Limites do piloto
- **O agente ainda age com o token do GitHub:** o marcador esconde o valor, mas um agente enganado pode pedir ao proxy qualquer operação que o `FABRICA_GH_TOKEN` permita no repositório do projeto. O limite é o escopo do token: só o repositório, sem Workflows e com expiração curta. Use o piloto só em repositório de teste, com issues escritas por você.
- **O token novo dispara workflows:** ao contrário do `GITHUB_TOKEN`, os eventos criados com o `FABRICA_GH_TOKEN` disparam outros workflows. Por isso a única trava contra cascata é o filtro do workflow (só a label `agente`) e o nome da label no grupo de concorrência. As labels aplicadas pelas etapas geram runs que terminam `skipped`.
- **CI do PR do agente:** com o `FABRICA_GH_TOKEN`, o PR que o agente abrir dispara o CI sozinho, sem a aprovação manual do run que o `GITHUB_TOKEN` exigia.
- **Linha de custo:** depende do log da sessão no runner; sem ele, sai `tokens=nao-medido`.
