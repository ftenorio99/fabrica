# Isolamento do agente

Este guia é para quando você quer deixar os agentes rodando sozinhos num projeto, pelo `/fabrica:avancar`, e precisa decidir o que um comando deles pode alcançar. A decisão e as alternativas estão na [ADR 0010](../adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md), que substituiu a ADR 0005.

## Os dois modos
Cada projeto escolhe um modo, gravado em `.fabrica/isolamento.txt`:

| | `sbx` (padrão) | `sem-sandbox` |
|---|---|---|
| Onde o agente roda | Numa VM do Docker Sandboxes, com a pasta do projeto montada | Direto na sua máquina |
| Arquivos | Só a pasta do projeto e o home da VM. O seu home, as chaves SSH e os outros projetos ficam fora | Tudo o que o seu usuário lê e escreve |
| Rede | Só os hosts da política da VM | Qualquer host |
| Token do GitHub | Fica no host. Na VM, o agente vê um marcador, e o proxy põe o token real nas requisições ao GitHub | O agente lê o token do `gh` |
| Docker e Compose | Funcionam dentro da VM | Os da sua máquina |
| `main` protegida | Hooks do git, instalados dentro da VM | Hooks do git da máquina |

Nenhum dos dois modos cobre o WebFetch, que segue as regras de permissão do Claude Code, nem o tráfego do próprio Claude Code com a API.

**Escolher:** rode `/fabrica:setup` no projeto. Ele pergunta o modo na primeira vez, grava o arquivo e mostra o que fazer em seguida. Faça o commit de `.fabrica/isolamento.txt` numa branch e abra o PR, como qualquer mudança.

**Trocar:** edite o arquivo por um PR. Ele tem uma linha, `sbx` ou `sem-sandbox`; linhas vazias e começadas com `#` são ignoradas. Com o modo já gravado, o setup não pergunta de novo.

O modo não muda o `/fabrica:status` nem o `/fabrica:metricas`. Ele orienta o setup e, nas etapas, só a mensagem quando o ambiente não roda a verificação de integração (veja [Verificação de integração](#verificação-de-integração)).

## Modo `sbx`
O `sbx` é o comando do Docker Sandboxes. A fábrica não o instala nem roda: a VM, a política de rede e o secret são seus, no host. O checklist abaixo é o que o `/fabrica:setup` mostra no fim, conferido com o `sbx` 0.51.0.

**Nome da VM:** `claude-<projeto>`, com `<projeto>` sendo o nome da pasta do repositório. É o nome padrão do `sbx` (`<agente>-<pasta>`), o mesmo que um `sbx run claude .` sem `--name` daria, e o checklist o passa explícito no `sbx create`. O setup já mostra os comandos com o nome do projeto. Se a VM do projeto tem outro nome, por exemplo porque foi criada com um `--name` diferente, confira na coluna SANDBOX do `sbx ls`, no host, e use esse nome nos comandos.

**Setup no host ou dentro da VM:** o checklist muda conforme o lugar onde o setup roda. O script `scripts/sbx-context.sh` descobre isso pelos sinais que o `sbx` deixa na VM: o arquivo `/etc/sandbox-persistent.sh` ou a variável `PROXY_CA_CERT_B64`.
- **No host:** todos os itens aparecem pendentes, menos o 5 quando os hooks do git já estão instalados.
- **Dentro da VM:** os itens 1, 2 e a rede base do 3 aparecem feitos, porque a VM só existe depois deles, e o setup não manda criá-la de novo. O item 4 aparece feito quando o `GH_TOKEN` da VM é o marcador do proxy, e não um token real. Ficam pendentes a linha do Playwright, quando o projeto tem `make e2e`, e o item 6, que confere no host o que não dá para provar de dentro da VM: a política global e a regra base de rede.

Nos dois casos, a linha do Playwright só aparece quando o `Makefile` do projeto tem o alvo `e2e:`.

1. **Fechar a rede padrão (no host, uma vez por máquina).** O `sbx` nasce com a rede aberta. Confira com `sbx policy ls`: a política global deve ser a `default-deny-all`, que nega o que nenhuma regra decide. Se ela liberar tudo, refaça a inicialização:

   ```bash
   sbx policy reset
   sbx policy init deny-all
   ```

   O `reset` para as VMs que estiverem rodando e apaga as regras locais.
2. **Criar a VM (no host, na pasta do projeto).**

   ```bash
   sbx create --name claude-<projeto> claude .
   ```
3. **Liberar a rede só para a VM (no host).** A base é o GitHub, o npm e o Docker Hub:

   ```bash
   sbx policy allow network --sandbox claude-<projeto> github.com,api.github.com,codeload.github.com,uploads.github.com,*.githubusercontent.com,registry.npmjs.org,registry-1.docker.io,auth.docker.io,production.cloudflare.docker.com
   ```
   A lista base não tem a API do Claude Code, e não precisa. Toda VM criada com o agente `claude` recebe do `sbx` uma política de origem `kit`, só dela, que você não edita e que é recriada no `sbx create`. Ela libera o que o próprio Claude Code usa: `api.anthropic.com`, `mcp-proxy.anthropic.com`, `claude.com`, `platform.claude.com`, `downloads.claude.ai` e `bridge.claudeusercontent.com`, mais `deb.debian.org` e `dhi.io`. Para ver as regras de uma VM, use `sbx policy ls claude-<projeto>`.

   **Projeto com `make e2e` (Playwright):** libere também os hosts de onde o Playwright baixa os navegadores (veja [Hosts da verificação de integração](#hosts-da-verificação-de-integração)):

   ```bash
   sbx policy allow network --sandbox claude-<projeto> cdn.playwright.dev,playwright.download.prss.microsoft.com
   ```
4. **Entregar o token do GitHub ao proxy (no host).** O token não entra na VM: o proxy o põe nas requisições ao GitHub.

   ```bash
   sbx secret set github --command 'gh auth token'
   ```
5. **Instalar o plugin e os hooks do git (dentro da VM).** Abra a sessão com `sbx run --name claude-<projeto>`. O `~/.claude` do host não entra na VM, então instale o plugin nela:

   ```
   /plugin marketplace add ftenorio99/fabrica
   /plugin install fabrica@fabrica
   /fabrica:setup
   ```

   O setup lê o modo do `.fabrica/isolamento.txt`, que chega à VM pela pasta do projeto, e instala os hooks do git no home da VM. **Repita este item depois de um `sbx rm`:** os hooks somem com a VM e, sem eles, o push na `main` passa.
6. **Conferir a rede (no host).** Use `sbx policy log claude-<projeto>`, que mostra o que o proxy liberou e o que bloqueou. Não confie num `curl` de dentro da VM: o proxy responde 200 ao CONNECT mesmo para um host bloqueado.

### Ampliar os domínios
Quando uma etapa falhar com erro de rede, veja no `sbx policy log claude-<projeto>` qual host foi bloqueado. Se o projeto precisa dele (a API de um serviço de pagamento em modo de teste, as fontes que o build baixa), libere só o host exato, só para a VM do projeto:

```bash
sbx policy allow network --sandbox claude-<projeto> api.stripe.com
```

Um curinga largo (como `*.github.com`) abre caminhos para tirar dados do projeto (como o `gist.github.com`). Não libere os hosts de produção (veja [Produção fora do alcance](#produção-fora-do-alcance)).

### Teste de aceite
O `scripts/test-sandbox-acceptance.sh` do plugin confere, de dentro da VM, se o isolamento está de pé. Rode-o numa VM nova, depois de trocar a versão do `sbx` e depois de mudar a política de rede. Na sessão aberta na VM (`sbx run --name claude-<projeto>`), peça ao agente para rodar, na pasta do projeto, o script do plugin instalado (em `~/.claude/plugins/cache/fabrica/fabrica/<versão>/`):

```bash
bash <pasta do plugin>/scripts/test-sandbox-acceptance.sh
```

Ele imprime `ok <verificação>` ou `falha <verificação>: <motivo>` e sai com 1 se alguma falhar:

| Verificação | O que confere |
|---|---|
| `token-marcador` | O `GH_TOKEN` da VM existe e não tem o formato de um token real do GitHub. |
| `home-isolado` | Não há chave privada legível em `~/.ssh` nem login do `gh` no home da VM. Os arquivos públicos (`known_hosts`, `config`, `authorized_keys` e as chaves `.pub`) não contam. |
| `gh-api-user` | O `gh` funciona com o token posto pelo proxy. |
| `dominio-liberado` | A VM alcança `api.github.com`. |
| `dominio-fora-da-lista` | A VM não recebe a página de `example.com`, que não está na política. |
| `hooks-do-git` | Os hooks do git estão instalados na VM. |
| `push-na-main-recusado` | Um push de teste na `main` é recusado pelo hook. O teste usa `--dry-run`, e nada chega ao remoto. |
| `git-push` | O push de uma branch `test/sandbox-*` funciona. A branch é apagada em seguida. |

O teste olha o corpo das respostas, e não o código HTTP, pelo motivo do item 6 do checklist. Com tudo `ok`, ele lembra de conferir o `sbx policy log claude-<projeto>` no host, que é onde aparece o que o proxy bloqueou. Fora da VM, `token-marcador` e `home-isolado` falham, como devem.

## Modo sem sandbox
Neste modo, não há isolamento. Os comandos do agente rodam com o seu usuário: leem o token do `gh`, as chaves SSH e os `.env` da máquina, escrevem fora do projeto e alcançam qualquer host. É uma exceção assumida, registrada no arquivo do projeto.

O que continua valendo:
- os hooks do git, que recusam commit e push na `main`;
- o hook de produção, que recusa o comando que cita um padrão de `.fabrica/producao.txt`;
- as regras de permissão do Claude Code.

Os dois hooks cobrem o erro inocente, não um agente enganado. Use este modo em projetos sem segredo relevante na máquina, ou quando você acompanha a sessão.

## Token fine-grained
Nos dois modos, o agente age no GitHub com o seu token: no modo sem sandbox, ele o lê; no modo `sbx`, o proxy o usa por ele. Um agente enganado pode usar esse acesso contra qualquer repositório que o token alcance. Por isso, o token do `gh` deve ser **fine-grained**, com o menor estrago possível:
1. Em https://github.com/settings/personal-access-tokens/new, crie um token com:
   - **Expiração:** 90 dias ou menos;
   - **Repository access:** só os repositórios em que a fábrica trabalha (ex.: `fabrica` e `kairo`);
   - **Permissões de repositório:**
     - Contents, Issues, Pull requests e Workflows: leitura e escrita;
     - Actions e Commit statuses: leitura;
     - Metadata: leitura, que é obrigatória.
2. Troque o login do `gh` pelo token novo:

   ```bash
   gh auth logout --hostname github.com
   gh auth login --with-token   # cole o token e tecle Ctrl-D
   gh auth status
   ```

   Depois, revogue o token antigo: em https://github.com/settings/applications, *Authorized OAuth Apps* → **GitHub CLI** → *Revoke*.
3. Repita os dois passos quando o token expirar. No modo `sbx`, o secret do item 4 do checklist chama `gh auth token` no host e pega o token novo sozinho.

Um repositório novo na fábrica precisa entrar no acesso do token. O token fine-grained não lê os checks do PR, e por isso o `/fabrica:revisar` lê o CI pela API do Actions.

## Projetos com o sandbox nativo
Até a ADR 0010, o `/fabrica:setup` ligava o sandbox nativo do Claude Code, gravando um bloco `sandbox` no `.claude/settings.json` do projeto. Esse bloco ainda está nos projetos que passaram por aquele setup. Dentro da VM do `sbx`, ele liga um segundo sandbox e esconde o `GH_TOKEN` dos comandos do agente, e o `gh` e o `git push` falham.

O `/fabrica:setup` faz a migração, nos dois modos:
- **No projeto, sem perguntar:** remove a chave `sandbox` inteira do `.claude/settings.json`, na cópia de trabalho, e deixa as outras chaves como estão. Não há backup, porque o arquivo é versionado: o `git diff` mostra a mudança, e você a leva por uma branch e um PR.
- **Na máquina, com a sua confirmação:** mostra o que encontrou e pergunta antes de remover. São os restos do setup antigo:
  - no `~/.claude/settings.json`, o `tlsTerminate` e as duas entradas de `mask` (a do `hosts.yml` do `gh` e a do `git-auth.gitconfig`), só quando estão idênticas às que a fábrica gravava. O que você mudou ou acrescentou no bloco `sandbox` fica;
  - no `~/.gitconfig`, a inclusão do `~/.config/fabrica/git-auth.gitconfig`;
  - o próprio `~/.config/fabrica/git-auth.gitconfig`.

**Backups:** antes de alterar, o setup copia o `settings.json` para `settings.json.bak-fabrica-sandbox`, na mesma pasta, e o arquivo de configuração do git para `<arquivo>.bak-fabrica-sandbox` (em geral, `~/.gitconfig.bak-fabrica-sandbox`). O `git-auth.gitconfig` é apagado sem backup, porque guarda uma credencial. Apague os backups quando não precisar mais deles.

Os restos da máquina só existem no host. Dentro da VM, o `~/.claude` e o `~/.gitconfig` são os da VM, e o setup não acha nada para remover: rode-o uma vez no host.

As linhas que o setup antigo gravou no `.prettierignore` do projeto, abaixo do comentário `fabrica#116`, não fazem mal sem o sandbox nativo e podem ser apagadas à mão.

## Verificação de integração
O `/fabrica:implementar`, o `/fabrica:revisar` e o revisor rodam a verificação de integração (o `make test` com banco e, quando a spec tem CA de ponta a ponta, o `make e2e`) na própria etapa, nos dois modos ([ADR 0011](../adr/0011-verificacao-de-integracao-na-etapa.md)):
- **`sbx`:** com o Docker e o Compose de dentro da VM;
- **`sem-sandbox`:** com o Docker da sua máquina.

Um projeto sem `.fabrica/isolamento.txt` também roda a verificação: a etapa não para e avisa no chat para você rodar o `/fabrica:setup`.

**Reserva do CI:** quando o comando falha com uma assinatura de ambiente, o ambiente não roda a verificação, e a falha não conta como erro da implementação. As assinaturas são o socket do Docker negado, o daemon do Docker inacessível, o `localhost` recusado, o socket negado e o navegador do Playwright que não baixa ou não abre. A lista exata está no passo "Verificar" do [`/fabrica:implementar`](../../skills/implementar/SKILL.md#4-verificar). Nesse caso, o PR abre em rascunho, espera o CI do head e só sai do rascunho com o CI verde. Sem CI em `pull_request`, a etapa pede a verificação a você. O "Para a sua revisão" do PR diz o que conferir: no modo `sbx`, o Docker na VM e o `sbx policy log claude-<projeto>` no host; no modo sem sandbox, se o Docker está ligado na máquina.

O CI continua rodando a verificação completa em todo PR, como conferência num ambiente descartável.

### Hosts da verificação de integração
No modo `sbx`, a VM precisa alcançar o que a verificação baixa:
- **Imagens do Compose:** o Docker Hub já está no comando base do item 3 do checklist. Uma imagem de outro registry (como o `ghcr.io` ou o `quay.io`) aparece bloqueada no `sbx policy log claude-<projeto>`: libere só esse host, como em [Ampliar os domínios](#ampliar-os-domínios).
- **Navegadores do Playwright:** o Playwright os baixa de `cdn.playwright.dev`, com `playwright.download.prss.microsoft.com` como espelho. Libere os dois com a linha do item 3 para projetos com `make e2e`.
- **Bibliotecas de sistema do navegador:** se o `make e2e` falhar com `Host system is missing dependencies`, rode na VM, uma vez, o comando que instala as dependências do Playwright do projeto (ex.: `pnpm exec playwright install --with-deps chromium`). A etapa não instala pacotes de sistema. Até lá, a verificação vai para a reserva do CI.

## Texto de issue e PR fora do prompt
O texto de uma issue, de um PR ou de um comentário pode vir de qualquer pessoa, e o modelo tende a obedecer instruções plantadas em texto que chega no turno do usuário. O que chega como resultado de ferramenta ele trata como não confiável ([ADR 0008](../adr/0008-texto-externo-fora-do-prompt.md)). Por isso:
- **Etapas:** o prompt de uma etapa de agente leva só o comando e o número, como `/fabrica:spec 42`. A etapa lê a issue, os comentários e o PR com `gh`. Os ajustes da spec, por exemplo, vêm dos comentários da issue, não do argumento.
- **Dispatcher:** o workflow não põe `${{ github.event.issue.body }}`, `${{ github.event.issue.title }}`, `${{ github.event.comment.body }}` nem outro texto do evento no prompt nem num `run:`. Num `run:`, esse texto também abre caminho para injeção de comando no shell. Do evento, o workflow usa só o número e o tipo.
- **Uso manual:** o que você digita no chat é seu e pode ir no argumento, como `/fabrica:spec 42 troque o CA3`. Não cole ali o texto de um comentário de outra pessoa.

## Produção fora do alcance
As etapas de agente só usam dev ou homologação ([ADR 0006](../adr/0006-producao-fora-do-alcance-do-agente.md)). A convenção é que os `.env` da máquina só tenham valores de dev ou de homologação, e que os segredos de produção fiquem no provedor (os secrets do deploy). Não deixe um `.env.production` real na pasta do projeto: ela é montada na VM do `sbx`, e no modo sem sandbox o agente lê a máquina inteira.

Para o agente não alcançar produção por engano, liste os padrões de produção em `.fabrica/producao.txt`, na raiz do repositório, e faça commit por PR:

```
# Banco e API de produção
host db.meuapp.com
host *.prod.meuapp.com
texto sk_live_
texto PROD_DATABASE_URL
```

- **`host <domínio>`:** o hook do plugin recusa o comando Bash que cita o domínio. Aceita o curinga `*.` no início.
- **`texto <literal>`:** o hook recusa o comando que cita o literal: prefixos de chave, nomes de variáveis e trechos de URL. Literais com menos de 4 caracteres são ignorados.
- Linhas vazias e começadas com `#` são ignoradas. A comparação ignora maiúsculas e é por trecho literal, sem expressão regular.

O hook lê o arquivo da branch e o da `main` no `origin`. Apagar uma linha numa branch não libera o comando até o merge, que é seu.

O hook pega o que está escrito no comando. A barreira de rede depende do modo:
- **`sbx`:** a política da VM só libera os hosts que você listou. Enquanto nenhum host de produção entrar nela, a VM não os alcança, mesmo que o comando escape do hook.
- **`sem-sandbox`:** não há barreira de rede. Só o hook protege.

Se o hook barrar um comando legítimo (um `grep` que cita o nome da variável, por exemplo), rode-o você mesmo com `!` no prompt, ou deixe o padrão mais específico.

As regras `Read(...)` de `permissions.deny` do `.claude/settings.json` continuam valendo nos dois modos para a ferramenta Read do Claude Code. Mantenha as regras dos `.env` de produção.
