# SPEC-204: Risco: agente pode gravar o .git/config da worktree e escapar do protect-main

**Issue:** #204 · **PRD:** F1 · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-25

## Contexto
A `main` é protegida por hooks globais do git ([ADR 0002](../docs/adr/0002-protecao-da-main-por-hooks-do-git.md)), e o `hooks/protect-main.sh` só impede, por checagens de texto no comando Bash, que o agente desligue esses hooks. A SPEC-107 registrou, como risco aceito, que o agente pode gravar o `.git/config` da worktree com as ferramentas Edit ou Write, definir ali a pasta de hooks (a configuração local vence a global) e então commitar e fazer push na `main` sem os hooks. A ADR 0002 limita o modelo de ameaça a erros e comandos inocentes, mas no job do dispatcher ([ADR 0016](../docs/adr/0016-isolamento-do-job-do-dispatcher.md)) o agente roda sozinho sobre texto de issue, e um agente enganado é parte da ameaça. Esta issue revê aquela decisão.

## Objetivo
No job do dispatcher, nenhum push para a `main` ou a `master` chega ao GitHub, qualquer que seja a configuração do git que o agente monte; fora do job, o `protect-main` também recusa Edit e Write nos arquivos de configuração do git, e o que continua de fora fica escrito nos guias.

## Comportamento esperado
**No job (proxy):** o `scripts/egress-addon.py`, que roda como `fabrica-proxy`, fora do alcance do agente, lê a lista de comandos de todo `POST` a `github.com` cujo caminho termina em `/git-receive-pack`.

| Corpo do push | Resposta do proxy |
|---|---|
| Algum comando cria, atualiza ou apaga `refs/heads/main` ou `refs/heads/master` (mesmo junto com outros refs) | 403, sem repassar ao GitHub; o push inteiro falha |
| Só comandos para outros refs (`refs/heads/feat/x`, `refs/heads/main-old`, tags) | repassa, com a troca do marcador como hoje |
| Só um `0000` (sonda que o git manda antes de um push grande) | repassa |
| Corpo ilegível (vazio, tamanho de pkt-line inválido, sem `0000` nem `push-cert-end`, codificação que não decodifica) | 403, sem repassar (falha fechada) |

O texto do 403 diz que o dispatcher não deixa o agente enviar para a `main`/`master` (ou que o corpo do push é ilegível) e que a mudança deve ir por PR. O log do proxy ganha uma linha com o host e o motivo, nunca o corpo nem cabeçalhos.

**Fora do job (`protect-main`):** um Edit, Write ou MultiEdit cujo `file_path` é um arquivo de configuração do git é negado com a mensagem: "Este arquivo é a configuração do git; editá-lo pode desligar os hooks que protegem a main. Se for intencional, edite você mesmo no terminal." Os demais arquivos passam sem saída, e o comportamento no Bash não muda.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O addon responde 403, sem repassar a requisição, a um `POST` a `github.com` em `/<dono>/<repo>.git/git-receive-pack` (com ou sem `.git`) cujo corpo tem um comando para `refs/heads/main`: criação (old-id zero), atualização e remoção (new-id zero). Vale também para `refs/heads/master`, para ids de 40 e de 64 dígitos e quando o comando da `main` é o segundo da lista, depois de um comando para outra branch. | unitário — `scripts/test-job-isolation.sh`, com o módulo mitmproxy falso que o teste já usa |
| CA2 | Um push cujos comandos são só para outros refs passa e recebe a troca do marcador no `Authorization`, como hoje. Casos: `refs/heads/feat/x`, `refs/heads/main-old`, `refs/heads/feature/main`, `refs/tags/main`, e a remoção de uma branch de feature. | unitário — `scripts/test-job-isolation.sh` |
| CA3 | Um corpo que é só `0000` (a sonda do git) passa. | unitário — `scripts/test-job-isolation.sh` |
| CA4 | Corpo ilegível dá 403 sem repassar: corpo vazio, tamanho de pkt-line com caractere não hexadecimal, tamanho entre `0001` e `0003`, pkt-line cortada no meio, lista sem `0000` nem `push-cert-end`, e corpo cuja decodificação (`Content-Encoding`) falha. | unitário — `scripts/test-job-isolation.sh` |
| CA5 | Na forma com certificado (`push-cert`), um comando para a `main` entre o cabeçalho e o `push-cert-end` dá 403; sem comando para a `main` ou a `master`, passa. Linhas `shallow <id>` antes da lista são ignoradas. | unitário — `scripts/test-job-isolation.sh` |
| CA6 | No `requestheaders`, o addon põe `flow.request.stream = False` em todo `POST` a `github.com` em `*/git-receive-pack`, para o corpo chegar inteiro ao `request` mesmo com `stream_large_bodies` ligado. | unitário — `scripts/test-job-isolation.sh` |
| CA7 | O resto do tráfego não muda: `GET .../info/refs?service=git-receive-pack`, `POST .../git-upload-pack`, `api.github.com` e hosts fora da lista seguem as regras de hoje. A linha de log do bloqueio cita o host e o motivo e não traz o corpo nem o `Authorization`. | unitário — `scripts/test-job-isolation.sh` |
| CA8 | O cenário da issue, no runner: como `fabrica-agent`, num clone do repositório de teste, o teste grava um `core.hooksPath` apontando para uma pasta vazia no `.git/config` local, faz um commit na `main` (que passa, porque os hooks foram desligados) e tenta `git push origin main`. O push falha, o log do proxy tem a linha do bloqueio, e o sha da `main` remota (`git ls-remote`) é o mesmo de antes. Um push para `fabrica-aceite-<run id>` passa, e o teste apaga essa branch no fim. | e2e — `scripts/test-job-acceptance.sh` pelo `isolamento-aceite.yml` em `ftenorio99/fabrica-teste`, na branch desta issue |
| CA9 | Caso adversarial (entrada inválida): como `fabrica-agent`, um `curl -X POST` pelo proxy a `https://github.com/<repo>.git/git-receive-pack` com o corpo `lixo<script>` recebe 403 do proxy, com o texto do corpo ilegível. | e2e — `scripts/test-job-acceptance.sh` em `ftenorio99/fabrica-teste`, como o CA8 |
| CA10 | O `protect-main` nega Edit, Write e MultiEdit (entrada do Claude Code com `tool_name` e `tool_input.file_path`) nestes caminhos: `<repo>/.git/config`, `<repo>/.git/config.worktree`, `<repo>/.git/worktrees/<id>/config.worktree`, `<repo>/.git/modules/<m>/config`, `$HOME/.gitconfig`, `$XDG_CONFIG_HOME/git/config` (ou `$HOME/.config/git/config` sem a variável), o arquivo de `GIT_CONFIG_GLOBAL` quando a variável existe, e qualquer arquivo dentro da pasta dos hooks (`FABRICA_GITHOOKS_DEST` ou o destino padrão). A saída é o `deny` com a mensagem do Comportamento esperado. | unitário — `scripts/test-protect-main.sh` |
| CA11 | O caminho é resolvido antes da comparação: relativo vale a partir do `cwd` da entrada, `..` é normalizado, e um link simbólico que aponta para um arquivo da lista do CA10 é negado. Um caminho que ainda não existe é resolvido pelo trecho que existe. | unitário — `scripts/test-protect-main.sh` |
| CA12 | Passam sem saída: `<repo>/src/config`, `<repo>/config/app.yml`, `<repo>/.github/config`, `<repo>/.gitignore`, `<repo>/.gitmodules`, `<repo>/docs/gitconfig.md` e um arquivo cujo nome contém `commit` ou `push`, também com os hooks do git não instalados (a checagem de "hooks não instalados" só vale para o Bash). | unitário — `scripts/test-protect-main.sh` |
| CA13 | `hooks/hooks.json` ganha, no `PreToolUse`, uma entrada com o matcher `Edit\|Write\|MultiEdit` que chama só o `protect-main.sh`; a entrada do `Bash` não muda. Os casos de Bash que o `scripts/test-protect-main.sh` já tem passam sem alteração. Uma entrada do Antigravity sem `CommandLine` (`toolCall` de uma ferramenta de arquivo) sai sem saída, como hoje. | unitário — `scripts/test-protect-main.sh` (lendo o `hooks.json` com `jq`) |
| CA14 | Numa sessão com o plugin da branch, pedir ao Claude que use Write para acrescentar uma linha ao `.git/config` de um repositório temporário é recusado com a mensagem do CA10, e o arquivo fica igual. | manual — `claude --plugin-dir <wt>` na branch, num repositório temporário |
| CA15 | O `docs/guias/dispatcher.md` (seções "Isolamento do job" e "Limites do piloto") e o `docs/guias/isolamento-do-agente.md` dizem que, no job, o push para a `main` é barrado pelo proxy e que, fora dele, o `protect-main` recusa Edit e Write na configuração do git; e listam o que continua de fora (Fora de escopo). A ADR 0002 ganha, em Consequências, uma linha que remete à ADR 0021. O `opencode/README.md` e o `docs/guias/antigravity.md` dizem que a checagem de Edit e Write não vale nesses agentes. | manual — leitura do diff na revisão |
| CA16 | `.claude-plugin/plugin.json` sobe a `version` (minor). | manual — leitura do diff na revisão |

**Casos adversariais não aplicáveis:** ID de outro usuário — o push não lê registro com dono, e o token do job só alcança o repositório do projeto; sessão expirada ou ausente — o fluxo não tem login, e o token é posto pelo proxy; duplo envio — cada push é decidido sozinho, sem estado, e dois pushes para a `main` são recusados igualmente; abuso de limite — o fluxo não tem regra de tamanho, quantidade ou frequência.

## Fora de escopo
- Escritas na `main` pela API com o token do job: `PUT /repos/.../contents/...`, `PATCH /repos/.../git/refs/heads/main`, merge de PR (`PUT /repos/.../pulls/<n>/merge`) e mutations do GraphQL. Os hooks do git também nunca cobriram isso; o limite segue o escopo do token, como no guia do dispatcher. Sugestão de issue de acompanhamento.
- Formas de Bash que montam o comando por variável, escape ou script gravado com Write (`git -c core.hooks\Path=…`, `git config include.path …`), fora do modelo de texto da ADR 0002. No job, o proxy as cobre para o push.
- A checagem de Edit e Write no adaptador do OpenCode e no Antigravity.
- Alterar o `.git` do worktree (o arquivo `.git` com `gitdir:`) para apontar a outro diretório: fora do job, segue fora do modelo de ameaça; no job, o proxy cobre o push.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/egress-addon.py`: funções puras `parse_receive_pack(body: bytes) -> list[str] | None` (os refs dos comandos, ou `None` se o corpo é ilegível) e `push_to_protected_ref(refs) -> bool`; hook `requestheaders` (CA6) e o bloqueio no `request`, antes da troca do marcador.
- `scripts/test-job-isolation.sh`: casos dos CA1 a CA7, com o módulo mitmproxy falso.
- `scripts/test-job-acceptance.sh`: verificações `push-main-barrado` (CA8) e `push-corpo-ilegivel` (CA9).
- `hooks/protect-main.sh`: ramo novo para entrada com `tool_input.file_path`, antes do ramo do Bash.
- `hooks/hooks.json`: entrada nova no `PreToolUse` (CA13); a `description` cita o Edit e o Write.
- `scripts/test-protect-main.sh`: casos dos CA10 a CA13.
- `docs/guias/dispatcher.md`, `docs/guias/isolamento-do-agente.md`, `docs/guias/antigravity.md`, `opencode/README.md`, `docs/adr/0002-protecao-da-main-por-hooks-do-git.md`, `docs/adr/0021-push-na-main-barrado-pelo-proxy-do-job.md`, `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:**
- Leitura do corpo (gitprotocol-pack, "Reference Update Request"): pkt-lines de 4 dígitos hexadecimais de tamanho (incluindo os 4); lê do início até o primeiro `0000` ou a linha `push-cert-end`. Em cada linha, corta no primeiro NUL, tira o LF final e aceita como comando `^[0-9a-f]{40}([0-9a-f]{24})? [0-9a-f]{40}([0-9a-f]{24})? (\S+)$`; linhas `shallow`, o cabeçalho do certificado e `push-option` não são comandos. Refs protegidos: exatamente `refs/heads/main` e `refs/heads/master`, os mesmos dos `githooks/`.
- O corpo vem de `flow.request.content` (já decodificado do `Content-Encoding`); um `ValueError` dessa leitura conta como corpo ilegível.
- `protect-main.sh`: `file=$(jq -r '.tool_input.file_path // ""')`; com `file` não vazio, resolve com `realpath -m` a partir de `.cwd` e compara com a lista do CA10; nega ou sai 0, sem passar pelo resto do script.

**Decisões:**
- Opção 1 avaliada primeiro e descartada na forma literal (recomendação da triagem) — tornar o `.git/config` não gravável não resiste: o git grava o config por `config.lock` e renomeação, então quem escreve na pasta `.git` substitui o arquivo; com o bit sticky na pasta, a troca fica impedida, mas o `git push -u` das etapas, que grava `branch.<b>.merge` no config, quebra; e um script gravado com Write roda o git com qualquer configuração por ambiente, que nenhuma permissão de arquivo barra. Alternativa da triagem: opções 2 e 3, adotadas na decisão abaixo.
- Opção 2 com o que restar na opção 3 (recomendação da triagem) — o `protect-main` inspeciona Edit, Write e MultiEdit pelo caminho do arquivo, e o guia registra o que fica de fora; cobre o uso local, onde o agente roda com o seu usuário e não há fronteira de permissão. Alternativa descartada: só registrar a limitação (opção 3), que deixa o caminho da issue aberto também para o erro inocente.
- No job, o push para a `main` é barrado pelo proxy (decisão além da triagem; [ADR 0021](../docs/adr/0021-push-na-main-barrado-pelo-proxy-do-job.md)) — é a forma de cumprir o critério da própria issue, "não depender de o agente cumprir uma regra": o proxy roda como outro usuário, e todo push do agente passa por ele. Alternativa descartada: parar nas opções 2 e 3, que no job deixam a `main` dependendo de checagens de texto que um script gravado com Write contorna.
- Checagem por caminho, não por conteúdo — o Edit manda só o trecho trocado, e um `include.path` leva a pasta de hooks a outro arquivo sem citar `hooksPath`. Alternativa descartada: negar só quando o conteúdo cita `hooksPath`.
- Proxy sem a exceção do commit inicial que os `githooks/` têm — o job nunca cria repositório, e a regra fica mais simples de provar. Alternativa descartada: consultar no GitHub se a `main` existe, o que pede uma chamada a mais por push.
- Entrada própria no `hooks.json` para os arquivos, só com o `protect-main` — o `protect-production` lê comandos e não tem o que fazer com um caminho. Alternativa descartada: ampliar o matcher da entrada do Bash, que chamaria também o `protect-production`.
- OpenCode e Antigravity sem a checagem de Edit e Write — o job, onde está a fronteira de segurança, roda só o Claude Code; no OpenCode, a verificação só roda na VM do `sbx`, e no Antigravity o formato das ferramentas de arquivo no `PreToolUse` não foi confirmado. Alternativa descartada: estender os dois adaptadores nesta issue, que passaria do tamanho M.
- Sem sobrescrever `core.hooksPath` por ambiente no job (`GIT_CONFIG_COUNT` no `agent.env`) — o proxy já barra o push, e a sobrescrita desligaria hooks locais de projetos (husky) só no job. Alternativa descartada: usá-la como segunda camada.

**Fontes da documentação:**
- mitmproxy 12.3.1 (versão do `agente.yml`) — Context7 `/websites/mitmproxy_stable`: `request` recebe o corpo inteiro quando o streaming está desligado, e `Message.stream` só pode ser definido no `requestheaders`. Versão não confirmada: a documentação é a da versão estável.
- git 2.53.0 — `man gitprotocol-pack` ("update-requests", "command-list", "push-cert") e `man git-config` (`config.worktree` em `$GIT_DIR/worktrees/<id>/`). A sonda `0000` antes de um push grande e a renomeação por `config.lock`: não verificadas na documentação; o CA3 e o CA8 confirmam o comportamento.
- gh — o desenho técnico não cita comando nem flag do `gh`.

**ADR:** [docs/adr/0021-push-na-main-barrado-pelo-proxy-do-job.md](../docs/adr/0021-push-na-main-barrado-pelo-proxy-do-job.md) (aceito).

## Testes
- `bash scripts/test-job-isolation.sh`: CA1 a CA7, montando corpos de receive-pack em bytes (ids de 40 e 64 dígitos, várias linhas, push-cert, corpos quebrados) e chamando `requestheaders` e `request` do addon com flows falsos; confere `flow.response.status_code == 403` e que o `Authorization` não foi trocado nos bloqueados.
- `bash scripts/test-protect-main.sh`: CA10 a CA13, com entradas JSON de Edit, Write e MultiEdit, `HOME`, `XDG_CONFIG_HOME` e o destino dos hooks numa pasta temporária, links simbólicos e caminhos relativos.
- `scripts/test-job-acceptance.sh`: CA8 e CA9, rodado pelo `isolamento-aceite.yml` no `ftenorio99/fabrica-teste` com o plugin desta branch.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Escrita na `main` pela API:** continua aberta no job (Fora de escopo); o push barrado não cobre o REST nem o GraphQL.
- **Push grande:** o proxy guarda o corpo inteiro na memória antes de decidir. Num repositório com pack de centenas de MB, a memória do runner pesa; aceito pelo tamanho dos projetos atuais.
- **Formato do push:** o git pode mudar o protocolo de push (hoje v0/v1 no receive-pack); um corpo que o leitor não entende cai no 403, que falha fechado e aparece no CA8.
- **Arquivo sensível:** mexe no isolamento do job e na proteção da `main`; a revisão humana é obrigatória.

## Histórico
- 2026-11-24: criação.
- 2026-11-25: aprovada.
