# SPEC-106: Isolamento do job do dispatcher, com token fine-grained e domínios liberados

**Issue:** #106 · **PRD:** F1 (com F2 e F4; item 6 do fatiamento, M2) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-18

## Contexto
A F1 do [PRD](../docs/prd.md) pede que o agente rode com rede restrita a uma lista de domínios e sem ler segredos em claro, **também no job do dispatcher**. A [ADR 0015](../docs/adr/0015-dispatcher-no-github-actions.md) (#99) escolheu o CLI no `ubuntu-latest` e deixou para esta issue três coisas: restringir a rede do job, trocar o `GITHUB_TOKEN` pelo token fine-grained e manter o `CLAUDE_CODE_OAUTH_TOKEN` fora do alcance de leitura do agente. A [ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) pede rever o isolamento do job à luz da troca para o `sbx`.

Esta issue **parte do workflow da #105**, ainda sem merge: a [SPEC-105](SPEC-105.md) define `templates/workflows/agente.yml`, `scripts/dispatch.sh` e `scripts/test-dispatch.sh`, e esta spec os altera. Se a #105 mudar de forma ao ser aprovada, a implementação adapta os nomes e registra o desvio no PR. A #105 só roda a triagem; as etapas que baixam dependências (`implementar`) e a retomada por evento (#107) ficam de fora.

## Objetivo
No job do dispatcher, o agente (`claude -p` e tudo o que ele executa) roda como um usuário sem rede direta, alcança só os hosts de uma lista versionada, nunca vê o `CLAUDE_CODE_OAUTH_TOKEN` nem o token do GitHub em claro, e as escritas do job no GitHub saem com um token fine-grained no lugar do `GITHUB_TOKEN`; isso fica provado por um teste de aceite no runner.

## Comportamento esperado
O job da #105 ganha, entre a instalação e o despacho, uma fase de isolamento. Em ordem:

1. **Preparar** (`scripts/job-isolation.sh prepare`, como root por `sudo`): cria os usuários `fabrica-proxy` (roda o proxy e guarda os segredos) e `fabrica-agent` (roda o agente), ambos sem shell de login e sem entrada no sudoers, e passa a pasta do checkout para o `fabrica-agent`.
2. **Instalar** o `mitmproxy` numa venv em `/opt/fabrica-mitm`, o CLI do Claude Code e o plugin, ainda com a rede aberta. O plugin é instalado **como `fabrica-agent`** (para ficar no `~/.claude` dele), com o `FABRICA_PLUGIN_TOKEN` só no `env` desse passo. Nenhum token fica gravado no home do agente depois.
3. **Travar** (`scripts/job-isolation.sh lock`, como root): grava os segredos reais num arquivo `0600` do `fabrica-proxy`, sorteia um **marcador** por segredo, sobe o `mitmdump` como `fabrica-proxy` em `127.0.0.1:8899` com o addon `scripts/egress-addon.py`, copia só o certificado público da CA para `/usr/local/share/fabrica/ca.pem` e fecha a rede do `fabrica-agent` com `iptables` e `ip6tables`: só TCP para `127.0.0.1:8899`, o resto é rejeitado (inclusive DNS).
4. **Despachar** (`dispatch.sh run`, da #105) com `FABRICA_CLAUDE_BIN=scripts/run-as-agent.sh`. O `stage-model.sh run` chama esse wrapper no lugar do `claude`, e o wrapper executa o `claude` como `fabrica-agent`, com um ambiente de lista fechada: `HTTPS_PROXY`/`HTTP_PROXY` para o proxy, `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE` e `GIT_SSL_CAINFO` para a CA, `CLAUDE_CODE_OAUTH_TOKEN` e `GH_TOKEN` com os **marcadores**, `HOME` e `PATH`. O `dispatch.sh` continua no usuário do runner e usa o token fine-grained nas próprias chamadas ao `gh` (labels, comentário de falha).

**O proxy** (`scripts/egress-addon.py`, addon do `mitmdump`):

| Situação do pedido | O que o proxy faz |
|---|---|
| Host fora da lista de domínios (no `CONNECT` ou no pedido) | responde 403 com o nome do host, sem contatar o destino, e registra `bloqueado <host>` no log |
| Host da lista, com `Authorization` que traz um marcador ligado àquele host | troca o marcador pelo valor real (em `Bearer` ou no `Basic` do git) e repassa |
| Host da lista, com marcador de um segredo que não é daquele host, ou marcador na URL, no corpo ou noutro cabeçalho | repassa sem trocar |
| Host da lista, sem marcador | repassa e registra `permitido <host>` |

O marcador é por job e aleatório. O valor real só existe no processo e no arquivo do `fabrica-proxy`.

**Falha fechada:** sem lista de domínios, com lista vazia, com mapa de marcadores inválido ou sem o valor real de um segredo no ambiente do proxy, o `lock` falha e o agente nunca roda. A falha cai no passo `if: failure()` da #105 (motivo `sem-resultado`).

**Token das escritas:** todo `GH_TOKEN` do workflow passa a vir de `secrets.FABRICA_GH_TOKEN`, um token fine-grained criado pelo usuário. As `permissions` do workflow caem para só `contents: read` (o checkout), porque o `GITHUB_TOKEN` deixa de escrever. **Efeito:** eventos criados com esse token disparam workflows, ao contrário dos do `GITHUB_TOKEN` (ADR 0015). A trava "sem cascata" passa a ser o filtro do workflow: o job só roda com `label.name == 'agente'`, e o grupo de concorrência inclui o nome da label, para a rodada pulada de outra label (`em-andamento`, `spec-pronta`, `modelo:*`) não disputar nem cancelar a rodada da `agente`. Como o PR do agente também é criado com esse token, o CI dele passa a rodar sozinho: a decisão pendente da #105 ("aprovação manual do run") deixa de valer.

**Teste de aceite:** um segundo workflow, `templates/workflows/isolamento-aceite.yml` (`workflow_dispatch`), roda a mesma fase de isolamento e depois `scripts/test-job-acceptance.sh`, que imprime `ok <verificação>` ou `falha <verificação>: <motivo>` (como o `test-sandbox-acceptance.sh` da ADR 0010) e sai com 1 se alguma falhar.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O addon libera o host que está na lista (exato, ou por `*.dominio` só para subdomínios, sem o apex e sem `outro-dominio`), sem diferenciar maiúsculas e ignorando a porta; qualquer outro host recebe 403 sem contatar o destino, no `CONNECT` e no pedido. `api.github.com.evil.com` e `github.com.` são barrados. | unitário — `scripts/test-job-isolation.sh`, com um módulo `mitmproxy` falso |
| CA2 | O marcador de um segredo em `Authorization: Bearer` é trocado pelo valor real só nos hosts ligados a esse segredo; num host da lista que não é dele, o pedido segue com o marcador; o valor real nunca é enviado a host fora do segredo. | unitário — `scripts/test-job-isolation.sh` |
| CA3 | O marcador dentro do `Authorization: Basic` do git (`x-access-token:<marcador>`) é trocado em `github.com`; o resultado volta a ser um `Basic` válido. | unitário — `scripts/test-job-isolation.sh` |
| CA4 | Só o cabeçalho `Authorization` é trocado: o marcador na URL, no corpo ou em outro cabeçalho segue intacto. O valor real não aparece no log do addon nem no corpo do 403. | unitário — `scripts/test-job-isolation.sh` |
| CA5 | O addon falha ao carregar (exceção com mensagem clara, e o `lock` sai com código diferente de 0 sem iniciar o agente) com a lista ausente, vazia ou só com comentários, com o mapa de marcadores inválido, e com um segredo sem valor real no ambiente. | unitário — `scripts/test-job-isolation.sh` |
| CA6 | `job-isolation.sh prepare` cria `fabrica-proxy` e `fabrica-agent` com shell `nologin`, não escreve em `/etc/sudoers*` e passa a pasta do checkout ao agente; rodar duas vezes não falha. | unitário — `scripts/test-job-isolation.sh`, com `useradd`, `chown` e `sudo` falsos que registram as chamadas |
| CA7 | `job-isolation.sh lock` monta as regras de `iptables` e `ip6tables` só para o uid do `fabrica-agent`: primeiro `ACCEPT` de TCP em `lo` para a porta do proxy, depois `REJECT` do resto; nenhuma regra vale para outro uid. O arquivo de segredos do proxy fica `0600` do `fabrica-proxy`, a pasta da CA fica `0700` e só o certificado público é copiado (`0644`); o ambiente do agente só tem marcadores. | unitário — `scripts/test-job-isolation.sh`, com `iptables`, `ip6tables`, `chown` e `chmod` falsos |
| CA8 | `run-as-agent.sh` passa os argumentos, a saída padrão e o código de saída do `claude` sem mudar nada, e o ambiente que entrega ao `sudo -u fabrica-agent` é a lista fechada do "Comportamento esperado": nenhum valor real de segredo e nenhuma variável do runner. | unitário — `scripts/test-job-isolation.sh`, com `sudo` e `claude` falsos que registram o ambiente |
| CA9 | `templates/workflows/agente.yml`: `permissions` é exatamente `contents: read`; todo `GH_TOKEN` vem de `secrets.FABRICA_GH_TOKEN` e `github.token` só aparece no checkout; `CLAUDE_CODE_OAUTH_TOKEN` só está no `env` do passo `lock`; a ordem é `prepare`, instalação do CLI e do plugin (como agente), `lock`, despacho com `FABRICA_CLAUDE_BIN`; o `if` do job e o grupo de concorrência (com `label.name`) valem como descrito; nenhuma linha de `run:` contém `${{`. | unitário — `scripts/test-dispatch.sh` (CA1 a CA5 da #105 ajustados, com a mudança do CA3 registrada no PR) |
| CA10 | `templates/workflows/dominios-liberados.txt` existe, com um host por linha e comentários dizendo por que cada um entra; tem `api.anthropic.com`, `github.com`, `api.github.com`, `codeload.github.com` e `uploads.github.com`; não tem `*`, nem `*.github.com`, nem `*.githubusercontent.com`. | unitário — `scripts/test-job-isolation.sh` |
| CA11 | **Aceite no runner:** no `ftenorio99/fabrica-teste`, o `isolamento-aceite.yml` termina com todas as verificações `ok`: `agente-sem-rede-direta` (um `curl --noproxy '*'` a um IP e a um nome falha), `dominio-liberado` (`gh api user` pelo proxy, com o marcador, responde com o login do dono do token), `dominio-fora-da-lista` (`curl https://example.com` pelo proxy recebe 403), `git-pelo-proxy` (`git ls-remote` do próprio repositório funciona), `marcador-no-ambiente` (o `CLAUDE_CODE_OAUTH_TOKEN` e o `GH_TOKEN` do agente são marcadores, não valores reais), `segredo-fora-do-alcance` (nenhum arquivo e nenhum `/proc/*/environ` legível pelo agente contém os valores reais, conferido por um root que lista o que o agente consegue ler), `ca-privada-ilegivel`, `sem-sudo` (`sudo -n true` falha como agente) e `home-sem-token` (o home do agente não guarda o `FABRICA_PLUGIN_TOKEN`). | e2e — repositório de teste `ftenorio99/fabrica-teste`, com o link do run no PR |
| CA12 | **Triagem de ponta a ponta sob isolamento:** no repositório de teste, aplicar `agente` numa issue nova gera um run verde que publica o comentário `<!-- fabrica:triagem -->` com a linha de custo, deixa a issue sem `em-andamento` e tem no log do proxy só hosts da lista. Se o `claude -p` precisar de um host fora da lista, o implementador o acrescenta ao arquivo com o motivo e registra no PR; a lista final é a menor que deixa o run passar. | e2e — repositório de teste |
| CA13 | **Sem cascata com o token novo:** no mesmo teste, as labels que a triagem aplica geram runs que terminam `skipped`, nenhum run termina `cancelled`, e aplicar `bug` enquanto o run da `agente` roda não o cancela nem o atrasa. | e2e — repositório de teste, com a saída do `gh run list --workflow agente.yml` no PR |
| CA14 | A [ADR 0016](../docs/adr/0016-isolamento-do-job-do-dispatcher.md) passa a `aceito` no PR; `docs/guias/dispatcher.md` ganha a seção "Isolamento do job" (os dois tokens, como criá-los, a lista de domínios e como ampliá-la, o teste de aceite, os limites); `docs/guias/isolamento-do-agente.md`, `docs/README.md` e `AGENTS.md` citam o que mudou, e a `version` do `.claude-plugin/plugin.json` sobe. | manual — leitura do diff na revisão |

## Fora de escopo
- **Etapas além da triagem** e hosts de dependências do projeto (npm, Docker Hub, Playwright), que o `implementar` precisa: a lista do projeto é da #108 ou de uma issue própria.
- **Retomada por evento** (`issue_comment`, `spec-aprovada`): #107. Ela reusa o filtro por nome de label e por marcador.
- **Instalação pelo `/fabrica:setup`:** #108. Aqui o workflow é copiado à mão para o repositório de teste.
- **Rodar o job dentro do `sbx`** e o `bypassPermissions`: o `auto` continua o modo do job.
- **Isolamento do `/fabrica:avancar` local:** é da #93, já entregue.
- **Runner self-hosted:** a ADR 0015 deixou para depois.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/job-isolation.sh` (novo): subcomandos `prepare` e `lock`. Lê `FABRICA_ISOLATION_DIR` e `FABRICA_PROXY_PORT` (padrão `8899`); em teste, `FABRICA_SUDO_BIN`, `FABRICA_IPTABLES_BIN` e afins trocam os binários por falsos. Saídas: 0 pronto; 1 erro; 2 uso inválido.
- `scripts/egress-addon.py` (novo): addon do `mitmdump`. A lógica fica em funções puras (`host_allowed`, `swap_authorization`), e os eventos `http_connect` e `request` só as chamam. Lê a lista de domínios e o mapa de marcadores (`marcador → nome do segredo e hosts`) de arquivos indicados por opções; o valor real vem do ambiente do próprio processo.
- `scripts/run-as-agent.sh` (novo): o wrapper do `FABRICA_CLAUDE_BIN`.
- `scripts/test-job-isolation.sh` (novo): CA1 a CA8 e CA10, no estilo de `scripts/test-stage-model.sh`. O addon é testado com um módulo `mitmproxy` falso injetado em `sys.modules`, para não exigir o pacote real na máquina de quem roda os testes.
- `scripts/test-job-acceptance.sh` (novo): o aceite do CA11, no estilo de `scripts/test-sandbox-acceptance.sh`; roda só no runner.
- `templates/workflows/agente.yml` (da #105, alterado): os passos novos, o `GH_TOKEN` pelo `FABRICA_GH_TOKEN`, as `permissions` e o grupo de concorrência.
- `templates/workflows/isolamento-aceite.yml` (novo) e `templates/workflows/dominios-liberados.txt` (novo).
- `scripts/test-dispatch.sh` (da #105, alterado): CA9.
- `docs/adr/0016-isolamento-do-job-do-dispatcher.md` (novo), `docs/guias/dispatcher.md` (da #105, alterado), `docs/guias/isolamento-do-agente.md`, `docs/README.md`, `AGENTS.md` e `.claude-plugin/plugin.json`.
- **Repositório de teste** `ftenorio99/fabrica-teste`, o mesmo da #105, recebe os dois workflows e os dois secrets novos. O usuário faz a parte fora do GitHub-agente ([ADR 0012](../docs/adr/0012-acao-externa-com-checklist.md)): criar o token fine-grained e cadastrá-lo com `gh secret set FABRICA_GH_TOKEN --repo ftenorio99/fabrica-teste`. O `CLAUDE_CODE_OAUTH_TOKEN` e o `FABRICA_PLUGIN_TOKEN` já foram cadastrados na #105.

**Dados:** nenhum.

**Interfaces:**
- `job-isolation.sh prepare` → 0; `job-isolation.sh lock` → 0 com o proxy de pé e a rede do agente fechada, ou 1 sem ter aberto nada.
- `run-as-agent.sh <argumentos do claude>` → o que o `claude` devolver.
- Secrets do repositório: `CLAUDE_CODE_OAUTH_TOKEN`, `FABRICA_PLUGIN_TOKEN` (da #105) e `FABRICA_GH_TOKEN` (novo).
- O token fine-grained: expiração de até 90 dias; acesso só ao repositório do projeto; Contents, Issues e Pull requests em leitura e escrita; Actions e Commit statuses em leitura; Metadata em leitura (obrigatória); **sem** Workflows.

**Decisões:**
- Proxy com `mitmproxy` em modo regular, que termina o TLS, porque uma só peça faz a lista de domínios **e** a troca do marcador, para a Anthropic e para o GitHub (git e API), como o proxy do `sbx` da ADR 0010. O padrão "o proxy injeta a credencial fora da fronteira do agente" é o que a documentação do Claude Code recomenda. Alternativa descartada: o `ANTHROPIC_BASE_URL` apontando para um proxy em HTTP puro, que serve só à API da Anthropic e deixaria o token do GitHub à vista do agente.
- Dois usuários, `fabrica-proxy` e `fabrica-agent`, com regras de `iptables` por uid, porque o `runner` tem `sudo` sem senha e o agente precisa de um uid que não leia o ambiente nem os arquivos do proxy e do runner. É o padrão que a documentação do mitmproxy usa para o modo transparente. Alternativa descartada: um único usuário com `iptables` por processo, que não esconde o segredo do agente.
- O agente só sai pela porta do proxy, e o DNS é resolvido pelo proxy: as regras rejeitam UDP e TCP direto, inclusive IPv6. Alternativa descartada: liberar DNS e filtrar por IP, que falha com os IPs rotativos de CDN.
- Marcadores aleatórios por job e troca só no `Authorization`, porque o risco residual da ADR 0005 era o proxy trocar o marcador também no corpo. Alternativa descartada: marcador fixo, que o agente poderia reconhecer em qualquer log.
- Token fine-grained em secret próprio (`FABRICA_GH_TOKEN`) no lugar do `GITHUB_TOKEN` (recomendação da triagem), porque o título da issue e a ADR 0015 pedem. Alternativa descartada: GitHub App, que exige instalar e manter o App no piloto.
- Filtro anticascata preservado e reforçado com o nome da label no grupo de concorrência (recomendação da triagem), porque o token novo dispara workflows e o filtro vira a única trava. Alternativa descartada: manter o `GITHUB_TOKEN` só para as labels das etapas, que separa dois tokens no mesmo job sem ganho, já que o agente passaria a usar o token errado para labels.
- Lista de domínios em `templates/workflows/dominios-liberados.txt`, versionada (recomendação da triagem), com hosts exatos e sem curingas largos, como o guia de isolamento recomenda. Alternativa descartada: a lista dentro do YAML, que o teste não alcança e a #108 teria de duplicar.
- `auto` continua o modo de permissão e o job não roda no `sbx` (recomendação da triagem), porque a ADR 0015 já decidiu e rodar o `sbx` no `ubuntu-latest` depende de virtualização aninhada que **não foi verificada**. Alternativa descartada: `sbx` no runner, que muda o `auto` para `bypassPermissions` pela ADR 0013.
- Dependência da #105 (recomendação da triagem): a #106 só começa a implementação com o workflow da #105 já na `main`, porque a ADR 0015 descreve esta issue como o passo entre a instalação e o `stage-model.sh run`. Alternativa descartada: scripts independentes testados sem o workflow, que deixam a ligação para a #105 e quebram o CA9.
- Falha fechada no `lock`, porque rodar o agente com a rede aberta por um erro de configuração é pior do que não rodar. Alternativa descartada: seguir sem proxy e avisar.

**Fontes da documentação:**
- mitmproxy (versão `stable`, não confirmada) — Context7 `/websites/mitmproxy_stable`: eventos `http_connect` e `request`, `http.Response.make`, `--set`, a CA em `mitmproxy-ca-cert.pem` (a `mitmproxy-ca.pem` guarda a chave privada) e o modo transparente com usuário dedicado e `block_global`. A versão a instalar na venv é a atual na data da implementação, fixada e registrada na ADR.
- Claude Code 2.1.327 — Context7 `/websites/code_claude`: `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` e `NODE_EXTRA_CA_CERTS` (sem suporte a SOCKS) e o padrão do proxy que injeta credenciais fora do agente.
- `iptables` com `-m owner --uid-owner` e `ip6tables` — não verificada (conhecimento do modelo); o CA7 testa só os argumentos, e o CA11 prova o efeito no runner.
- Permissões do token fine-grained — as do guia `docs/guias/isolamento-do-agente.md`; o implementador reconfere na documentação do GitHub ao escrever o guia.
- Concorrência do Actions com `if` que pula o job — não verificada; o CA13 prova o comportamento no runner.
- gh 2.104.0 — `gh run list --help` (`--workflow`, `--json`), `gh secret set --help` (`--repo`, `--body`), `gh auth setup-git --help`.

**ADR:** [docs/adr/0016-isolamento-do-job-do-dispatcher.md](../docs/adr/0016-isolamento-do-job-do-dispatcher.md) (proposto)

## Testes
- `bash scripts/test-job-isolation.sh`: CA1 a CA5 e CA10 importam `scripts/egress-addon.py` com um módulo `mitmproxy` falso e chamam as funções puras e os eventos com fluxos falsos (pedido, `CONNECT`, cabeçalhos); CA6 a CA8 rodam o `job-isolation.sh` e o `run-as-agent.sh` numa pasta temporária, com `sudo`, `useradd`, `chown`, `iptables`, `ip6tables` e `claude` falsos no `PATH` que gravam argumentos e ambiente, e conferem a ordem das regras, os modos dos arquivos e a ausência dos valores reais.
- `bash scripts/test-dispatch.sh` continua passando, com os casos do CA9 acrescentados e o CA3 da #105 ajustado. O `bash scripts/test-stage-model.sh` não muda.
- CA11 a CA13: no `ftenorio99/fabrica-teste`, com os três secrets cadastrados; os links dos runs e a saída do `gh run list` vão no PR. As issues de teste ficam fechadas no fim, com um comentário dizendo que eram teste.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Tamanho:** o item é G e esta spec está perto do limite de 2 dias (proxy, wrapper, regras de rede, aceite no runner e dois tokens). Se a implementação passar disso, divida em **rede e marcadores** (CA1 a CA8, CA10, CA11) e **token e concorrência** (CA9, CA12 e CA13); o corte não muda nenhum CA.
- **Marcador no Claude Code:** não está verificado que o `claude -p` aceita um `CLAUDE_CODE_OAUTH_TOKEN` que é só um marcador e funciona com o proxy terminando o TLS. O CA11 e o CA12 provam isso no runner. Se falhar, a implementação para com `escalonado` e registra o resultado na issue, em vez de devolver o token real ao agente; o plano B é o `ANTHROPIC_BASE_URL` com um proxy em HTTP puro só para a Anthropic, que a ADR registra.
- **Hosts de que o `claude -p` precisa:** a lista parte do mínimo (`api.anthropic.com` e o GitHub). O Claude Code pode tentar outros hosts (telemetria, atualização). O CA12 ajusta a lista pelo log do proxy.
- **O agente ainda age com o token do GitHub:** o marcador esconde o valor, mas o agente enganado pode pedir ao proxy qualquer operação que o token fine-grained permita no repositório do projeto. O limite é o escopo do token (só o repositório, sem Workflows, expiração curta) e os hooks do git e do `main`.
- **O proxy também lê o tráfego do agente:** a CA fica só no `fabrica-proxy` (chave) e no ambiente do agente (certificado público), mas o log do proxy lista os hosts e nunca os cabeçalhos.
- **Token de longa duração:** o `FABRICA_GH_TOKEN` expira e precisa de renovação como ação externa; um token expirado derruba o job com erro de `gh`, e o `fail` da #105 comenta `sem-resultado`.
- **Sem a #105 na `main`**, a implementação não começa; a #105 pode ainda mudar os nomes que esta spec cita.

## Histórico
- 2026-11-18: criação.
