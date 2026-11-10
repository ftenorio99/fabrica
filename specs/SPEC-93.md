# SPEC-93: Agente roda isolado em sandbox, com rede restrita e sem segredos em claro

**Issue:** #93 · **PRD:** F1 (item 1 do fatiamento, M1) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-10

## Contexto
As etapas da fábrica rodam na máquina do usuário. Hoje elas têm acesso a `~/.ssh`, ao token do `gh` em `~/.config/gh/hosts.yml` e aos `.env`, e só o git está protegido, pelos hooks da ADR 0002. O PRD pede, na F1, que o agente rode em sandbox, com o sistema de arquivos e a rede restritos e sem ler segredos em claro. Isso vale antes do dispatcher (restrição "F1 e F2 vêm antes do F4") e cobre o risco "injeção de prompt leva a exfiltração de credenciais ou a um comando destrutivo". Esta issue faz isso para a execução local, com o sandbox nativo do Claude Code. O job do dispatcher fica com a #106.

## Objetivo
O `/fabrica:setup` liga o sandbox nativo do Claude Code num projeto. Depois disso, os comandos Bash das sessões nesse projeto não escrevem fora do projeto, só alcançam os domínios liberados e não leem em claro o token do `gh`, as chaves SSH nem os `.env`. Um teste de aceite comprova as três coisas.

## Comportamento esperado
1. O usuário roda `/fabrica:setup` num projeto. O passo novo **Sandbox** confere as dependências e o estado (`scripts/setup-sandbox.sh --check`):
   - **Dependências:** sem o `bwrap` ou o `socat` no `PATH`, o setup mostra `sudo apt-get install bubblewrap socat` (ou o `dnf` equivalente), não roda `sudo` e não instala o sandbox. Os outros passos do setup continuam. Com o `sysctl` `kernel.apparmor_restrict_unprivileged_userns` em `1`, o setup também exige o perfil `/etc/apparmor.d/bwrap` e o `bwrap-userns-restrict` do Ubuntu desligado, e remete aos comandos do guia.
   - **`ok`:** o sandbox já está instalado. O setup não pergunta nada.
   - **`ausente` ou `incompleto <o que falta>`:** o setup explica o que muda (os itens 2 e 3) e pede confirmação com o AskUserQuestion.
2. Com a confirmação, o script grava no `.claude/settings.json` do projeto o bloco `sandbox` de base:
   - `enabled: true` e `allowUnsandboxedCommands: false`;
   - os domínios de base em `network.allowedDomains` e `network.allowLocalBinding: true`;
   - `filesystem.allowWrite` no cache do npm (`~/.npm`);
   - `credentials` com `deny` em `~/.ssh` e nos `.env*` do projeto, e nas variáveis `GH_TOKEN` e `GITHUB_TOKEN`.
3. Também com a confirmação, o script grava no `~/.claude/settings.json` do usuário o que só vale nesse escopo:
   - `sandbox.network.tlsTerminate: {}`;
   - a entrada `mask` de `~/.config/gh/hosts.yml`, com `extract` do `oauth_token`, `maskDuplicates: true`, `onExtractNoMatch: "deny"` e `injectHosts` em `api.github.com` e `github.com`;
   - a entrada `mask` de `~/.config/fabrica/git-auth.gitconfig`, com `extract` do valor depois de `Basic`, e `injectHosts` só em `github.com`.

   Antes de mudar, ele guarda o settings anterior em `~/.claude/settings.json.bak-fabrica`, como a statusline.
4. O usuário roda, fora do sandbox, `scripts/setup-git-auth.sh`. Ele grava em `~/.config/fabrica/git-auth.gitconfig`, com permissão `600`, o cabeçalho `Authorization: Basic` do token do `gh` para `https://github.com/` e inclui o arquivo no `~/.gitconfig`. O agente não roda esse script, porque ele grava uma credencial. O usuário o roda de novo quando o token mudar.
5. Na sessão seguinte, aberta no projeto, os comandos Bash rodam no sandbox:
   - escrever ou apagar fora do projeto e da pasta temporária falha;
   - um domínio fora da lista falha;
   - o `gh` e o `git push` funcionam com o token posto pelo proxy, que o comando nunca vê.
6. Para ampliar a lista, o repositório acrescenta domínios no próprio `.claude/settings.json`. Rodar o setup de novo mantém os domínios e as entradas acrescentados, porque as listas são somadas e não substituídas.

**Casos de borda:**

| Situação | Comportamento |
|---|---|
| O `git-auth.gitconfig` falta ou tem um token velho | O `git push` falha no sandbox, e com o token velho também fora dele. O `setup-git-auth.sh --check` responde `ausente` ou `sem-include`, e o teste de aceite indica o script. |
| `.claude/settings.json` do projeto ou `~/.claude/settings.json` não existe | O script cria o arquivo só com o bloco da fábrica. |
| Algum desses arquivos tem JSON inválido | O script não grava nada em nenhum dos dois, imprime `setup-sandbox: JSON inválido em <arquivo>` e sai com código 1. |
| Já existe bloco `sandbox`, de outra origem ou da fábrica | O script soma as listas sem repetir e preserva as chaves que não são da fábrica. Nas chaves escalares da fábrica (`enabled`, `allowUnsandboxedCommands`, `allowLocalBinding`), ele grava o valor da fábrica e lista no `--check` as que divergiam (`incompleto enabled=false`). |
| Uma entrada de `credentials` para o mesmo `path` ou `name` já existe com outro modo | Vale a regra do Claude Code: `deny` vence `mask`. O script não duplica a entrada e mantém a que já existe. Se ela não é a da fábrica, o `--check` reporta `incompleto credentials:<path>`. |
| O `hosts.yml` não tem `oauth_token` (ex.: token no chaveiro do sistema) | O `onExtractNoMatch: "deny"` deixa o arquivo ilegível no sandbox, e o `gh` falha dentro dele. O guia diz para guardar o token no arquivo (`gh auth login --insecure-storage`) ou usar `GH_TOKEN` mascarado. O teste de aceite reporta `falha gh` com essa dica. |
| A sessão já roda em sandbox e o script tenta gravar no `~/.claude/settings.json` | A gravação falha por estar fora do projeto. O script detecta o erro de escrita, sai com código 2 e imprime o comando para o usuário rodar com `!` no prompt, fora do sandbox. O `/fabrica:setup` repassa essa linha. |

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `setup-sandbox.sh`, num projeto e num `HOME` vazios, cria o `.claude/settings.json` do projeto com o bloco de base do item 2 e o `~/.claude/settings.json` com o bloco do item 3, com as chaves exatas deste documento. | unitário — `scripts/test-setup-sandbox.sh`, com `HOME` e projeto temporários |
| CA2 | Com settings já existentes (ex.: o `permissions.deny` do kairo e uma `statusLine`), o script preserva todas as chaves que não são da fábrica, guarda o `~/.claude/settings.json.bak-fabrica` antes de mudar o arquivo do usuário e não repete itens das listas. | unitário — `scripts/test-setup-sandbox.sh` |
| CA3 | A segunda execução não muda nenhum arquivo (mesmo hash). Um domínio acrescentado pelo repositório antes dela continua na lista. | unitário — `scripts/test-setup-sandbox.sh` |
| CA4 | `--check` imprime `ausente` sem bloco da fábrica, `ok` com os dois blocos completos e `incompleto <itens>` quando falta ou diverge uma chave, e não grava nada. | unitário — `scripts/test-setup-sandbox.sh` |
| CA5 | Com JSON inválido em qualquer um dos dois arquivos, o script sai com código 1, imprime a mensagem da tabela e não muda nenhum dos dois. | unitário — `scripts/test-setup-sandbox.sh` |
| CA6 | O `/fabrica:setup` tem o passo **Sandbox**: confere o `bwrap` e o `socat` e mostra o comando de instalação sem rodá-lo, pede confirmação antes de instalar e relata no resumo `instalado`, `já estava instalado`, `não instalado, a pedido do usuário` ou `faltam dependências: <lista>`. | manual — `claude --plugin-dir <clone>` na branch, num repositório de teste |
| CA7 | **Aceite 1:** numa sessão no projeto com o sandbox ligado, `scripts/test-sandbox-acceptance.sh` mostra que criar e apagar um arquivo em `~` falha, que escrever em `.claude/settings.json` falha e que criar e apagar um arquivo dentro do projeto funciona. | manual — `claude --plugin-dir <clone>` num repositório de teste com o sandbox instalado, rodando o script pelo Bash do agente |
| CA8 | **Aceite 2:** o mesmo script mostra que um `curl` para `https://example.com` falha e que um `curl` para `https://api.github.com` responde. | manual — como no CA7 |
| CA9 | **Aceite 3:** o mesmo script mostra quatro coisas. O `hosts.yml` lido no sandbox não contém um token do GitHub (`gh[opsu]_` nem `github_pat_`). `GH_TOKEN` e `GITHUB_TOKEN` estão vazias. `~/.ssh` não pode ser lido. Um `.env` de teste do projeto também não pode ser lido. | manual — como no CA7 |
| CA10 | O fluxo continua funcionando no sandbox: o mesmo script roda `gh api user`, faz `git push` de uma branch de teste e a apaga em seguida, e roda `npm view npm version`, e os três funcionam. | manual — como no CA7, com a branch de teste no repositório de teste |
| CA11 | A ADR 0005, o guia `docs/guias/isolamento-do-agente.md` (o que o sandbox protege, como ampliar os domínios, o caso do token no chaveiro, como rodar o aceite e como desligar) e as entradas no `docs/README.md` e no `/fabrica:setup` de `docs/comandos.md` existem. O `plugin.json` passa para a 0.27.0. | manual — leitura do diff na revisão |

## Fora de escopo
- O isolamento do job do dispatcher, com token fine-grained no runner (#106).
- A regra de credenciais só de dev ou homologação (#94).
- Rodar as etapas numa worktree descartável, para que apagar dentro do projeto também não afete o clone. O sandbox nativo libera a escrita no projeto, e o git recupera o que ficar ali.
- Limitar o WebFetch: o sandbox vale só para os comandos Bash, e o WebFetch segue as regras de permissão.
- Ligar o sandbox no kairo. Fica com o usuário, rodando `/fabrica:setup` lá depois do merge.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/setup-sandbox.sh` (novo): instala, com `--check`, o bloco de base no projeto e o bloco do usuário. A mescla de JSON é feita em Python (`python3 -I`), que já é dependência da fábrica (`stage-usage.py`).
- `templates/sandbox-project.json` e `templates/sandbox-user.json` (novos): os dois blocos da fábrica, lidos pelo script. São a fonte única das chaves.
- `scripts/setup-git-auth.sh` (novo): grava o `git-auth.gitconfig` e o `include.path` no `~/.gitconfig`, com `--check` (`ok`, `ausente` ou `sem-include`).
- `scripts/test-setup-sandbox.sh` (novo): os testes dos CA1 a CA5 e os do `setup-git-auth.sh`, no estilo dos `scripts/test-*.sh`.
- `scripts/test-sandbox-acceptance.sh` (novo): as verificações dos CA7 a CA10. Imprime `ok <verificação>` ou `falha <verificação>: <motivo>`, uma por linha, e sai com 1 se alguma falhar.
- `skills/setup/SKILL.md`: o passo novo **Sandbox**, entre os hooks do git e a statusline, e a linha dele no "Responder".
- `docs/adr/0005-isolamento-do-agente-em-sandbox.md` (novo), `docs/guias/isolamento-do-agente.md` (novo), `docs/README.md`, `docs/comandos.md`, `.claude-plugin/plugin.json`, `CLAUDE.md` (a linha dos testes em `scripts/`).

**Dados:** nenhum banco. Os blocos gravados:

```json
// .claude/settings.json do projeto (templates/sandbox-project.json)
{
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "allowedDomains": ["github.com", "api.github.com", "codeload.github.com", "uploads.github.com", "*.githubusercontent.com", "registry.npmjs.org"],
      "allowLocalBinding": true
    },
    "filesystem": { "allowWrite": ["~/.npm"] },
    "credentials": {
      "files": [
        { "path": "~/.ssh", "mode": "deny" },
        { "path": ".env", "mode": "deny" },
        { "path": ".env.local", "mode": "deny" },
        { "path": ".env.development", "mode": "deny" },
        { "path": ".env.test", "mode": "deny" },
        { "path": ".env.production", "mode": "deny" }
      ],
      "envVars": [
        { "name": "GH_TOKEN", "mode": "deny" },
        { "name": "GITHUB_TOKEN", "mode": "deny" }
      ]
    }
  }
}
```

```json
// ~/.claude/settings.json do usuário (templates/sandbox-user.json)
{
  "sandbox": {
    "network": { "tlsTerminate": {} },
    "credentials": {
      "files": [
        {
          "path": "~/.config/gh/hosts.yml",
          "mode": "mask",
          "extract": "oauth_token:\\s*(\\S+)",
          "maskDuplicates": true,
          "onExtractNoMatch": "deny",
          "injectHosts": ["api.github.com", "github.com"]
        },
        {
          "path": "~/.config/fabrica/git-auth.gitconfig",
          "mode": "mask",
          "extract": "Basic\\s+(\\S+)",
          "maskDuplicates": true,
          "onExtractNoMatch": "deny",
          "injectHosts": ["github.com"]
        }
      ]
    }
  }
}
```

**Interfaces:**
- `scripts/setup-sandbox.sh [--check] [--project <dir>]`:
  - o projeto padrão é a raiz do repositório atual (`git rev-parse --show-toplevel`);
  - o `--check` imprime `ok`, `ausente` ou `incompleto <itens separados por espaço>`;
  - os códigos de saída são 0 para sucesso, 1 para JSON inválido ou opção desconhecida e 2 para escrita negada no settings do usuário.

  O caminho do settings do usuário respeita `CLAUDE_CONFIG_DIR`, como o `setup-statusline.sh`.
- `scripts/test-sandbox-acceptance.sh [--remote <nome>]`: roda as verificações no projeto atual. O `git push` usa o remote dado (padrão `origin`) e uma branch `test/sandbox-<data>`, apagada no fim.

**Decisões:**
- **Token do `gh`:** o `mode: "mask"` de `sandbox.credentials` em `~/.config/gh/hosts.yml`, com `injectHosts` em `api.github.com` e `github.com` (recomendação da triagem). O comando no sandbox vê só um marcador, e o proxy põe o token real na saída, o que atende à F1 ("sem ler segredos em claro"). O `github.com` entra para o `git push` por HTTPS, que pega a senha pelo `gh auth git-credential`. Alternativas descartadas:
  - o `gh` em `excludedCommands`: ele roda fora do sandbox, e um `gh auth token` devolve o token em claro;
  - aceitar o risco com um token fine-grained: contraria a F1.
- **Outros segredos:** `deny` em `~/.ssh`, nos `.env*` do projeto e em `GH_TOKEN` e `GITHUB_TOKEN` (recomendação da triagem). Diferente do `permissions.deny` do kairo#78, o `deny` do sandbox vale para todo subprocesso do Bash. Alternativa descartada: só o `permissions.deny`, que não alcança os subprocessos.
- **Onde gravar:** a base vai no `.claude/settings.json` do projeto (recomendação da triagem), e o `tlsTerminate` e a entrada `mask` vão no `~/.claude/settings.json` do usuário. A triagem recomendava tudo no projeto, mas a documentação do sandbox diz que o Claude Code ignora o `mask` e o `tlsTerminate` no settings de um repositório. Eles só valem no settings do usuário, no gerenciado ou no `--settings`, o que impede um repositório de redirecionar um token para um host dele. No usuário, os dois só agem quando o sandbox está ligado, então os projetos sem o bloco de base não mudam. Alternativas descartadas:
  - tudo no usuário: liga o sandbox em todas as sessões da máquina;
  - `claude --settings <arquivo>` só para o `/fabrica:avancar`: exige lembrar da flag a cada sessão e deixa a sessão interativa no mesmo projeto sem proteção.
- **Domínios de base:** `github.com`, `api.github.com`, `codeload.github.com`, `uploads.github.com`, `*.githubusercontent.com` e `registry.npmjs.org`, com `allowLocalBinding` ligado (recomendação da triagem). A triagem citava também os hosts do Claude Code, mas eles saem da lista: o sandbox vale só para os comandos Bash e os filhos deles, e não para o tráfego do próprio Claude Code com a API. A lista começa vazia e é somada entre os escopos, e por isso cada repositório amplia a dele no próprio settings. Alternativa descartada: `*.github.com`, que libera hosts que as etapas não usam (ex.: `gist.github.com`, uma rota de exfiltração).
- **`allowUnsandboxedCommands: false`:** sem isso, um comando barrado pelo sandbox pode ser repetido fora dele, depois de uma permissão. No `/fabrica:avancar`, em auto mode, quem dá essa permissão é o classificador, e uma injeção de prompt poderia pedi-la. O que precisa sair do sandbox (gravar o settings do usuário, instalar os hooks do git) o usuário roda com `!` no prompt. Alternativa descartada: manter o padrão (`true`), que deixa a saída do sandbox à mercê do classificador.
- **Verificação 1 do aceite:** escrever ou apagar fora do projeto falha (recomendação da triagem). O sandbox nativo libera a escrita no diretório do projeto. Alternativa descartada: a worktree descartável, que vai para "Fora de escopo".
- **`git push` por um cabeçalho pronto:** o proxy só troca um marcador que aparece literalmente na requisição, e o git codifica em base64 a senha do Basic auth. Por isso, o `git push` usa um cabeçalho já codificado, mascarado à parte, e roda dentro do sandbox (decisão do usuário na implementação, em 2026-11-10). Alternativas descartadas:
  - `git push` em `excludedCommands`: o `git push --receive-pack=<cmd>` executa comandos fora do sandbox, como mostrou a revisão automática;
  - o push pelo usuário, com `!`: o `/fabrica:avancar` pararia a cada push.
- **Mescla em Python:** `python3 -I`, já usado pelo `stage-usage.py`, soma listas e preserva as chaves sem depender do `jq`, que o setup trata como opcional (falta do `jq` só desliga a statusline). Alternativa descartada: o `jq`.

**Fontes da documentação:**
- Claude Code 2.1.321 (`claude --version`). O `mask` exige a 2.1.221 ou mais nova.
  - Context7 `/websites/code_claude`: `sandbox.credentials`, `mask` e `extract` de `hosts.yml`, `tlsTerminate` ("Scope: User or managed"), `denyRead` e `excludedCommands`.
  - https://code.claude.com/docs/en/sandboxing:
    - o `mask` e o `tlsTerminate` são honrados só no settings do usuário, no gerenciado e no `--settings`;
    - os domínios são somados entre os escopos, e a lista começa vazia;
    - o sandbox cobre os comandos Bash e os filhos deles;
    - a escrita padrão vai no diretório atual e na pasta temporária, e os `.claude` settings ficam protegidos mesmo dentro dele;
    - no Linux, o sandbox depende do `bubblewrap` e do `socat`.
  - A documentação não diz se a troca do marcador funciona no Basic auth do `git push`. Veja "Riscos".
- gh 2.103.3 — `gh api --help` (`gh api user`).

**ADR:** [docs/adr/0005-isolamento-do-agente-em-sandbox.md](../docs/adr/0005-isolamento-do-agente-em-sandbox.md)

## Testes
- `bash scripts/test-setup-sandbox.sh`: CA1 a CA5, com `HOME`, `CLAUDE_CONFIG_DIR` e projeto em pastas temporárias. Confere as chaves por `python3 -c 'import json…'`, o hash dos arquivos na segunda execução, a saída do `--check` e os códigos de saída.
- `bash scripts/test-sandbox-acceptance.sh`, numa sessão `claude --plugin-dir <clone>` num repositório de teste com o sandbox instalado e um `.env` de teste: CA7 a CA10. A saída vai para o corpo do PR.
- CA6 e CA11: verificação manual descrita no PR.

## Riscos e dúvidas
- **`git push` com o token mascarado:** confirmado na implementação, o proxy não troca o marcador dentro do Basic auth. O caminho ficou o cabeçalho pronto do `git-auth.gitconfig` (veja "Decisões").
- **Reflexão do marcador (risco aceito):** o aceite mostrou que o proxy troca o marcador também no corpo das requisições a `api.github.com`. Um agente enganado pode obter o token pelo próprio GitHub (ex.: `POST /markdown`). O usuário aceitou esse risco em 2026-11-10, com a mitigação do token fine-grained: só os repositórios da fábrica e com expiração. O aceite mostra esse caso como `aviso reflexao-token-gh` e confere a expiração do token (`token-com-expiracao`).
- **CA efêmera do `tlsTerminate`:** a documentação não diz como os comandos no sandbox passam a confiar na CA do proxy (`SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS` e `GIT_SSL_CAINFO` não são citados). O `gh api`, o `git push` e o `npm view` do CA10 cobrem os três clientes das etapas.
- **`!` fora do sandbox:** a spec supõe que um comando rodado pelo usuário com `!` no prompt não passa pelo sandbox. O CA7 confere isso, com o usuário rodando `! touch ~/fabrica-sandbox-probe && rm ~/fabrica-sandbox-probe`. Se não for assim, o guia indica rodar o script num terminal comum.
- **Domínio esquecido:** um domínio que falta na lista para a etapa no meio, com um erro de rede. O guia mostra como ler o erro e ampliar a lista no projeto.
- **`tlsTerminate` experimental:** o recurso pode mudar entre versões do Claude Code, e o `claude doctor` avisa quando ele não está disponível. O aceite é rodado de novo a cada atualização que o guia citar.

## Histórico
- 2026-11-09: criação.
- 2026-11-10: aprovada.
- 2026-11-10: mudança (alterar) na implementação, com decisão do usuário. Motivos: o proxy não troca o marcador no Basic auth do `git push`, o npm precisa gravar no cache e o Ubuntu 26.04 exige o ajuste do AppArmor. Entraram o `setup-git-auth.sh` e o `mask` do `git-auth.gitconfig`, o `allowWrite` do `~/.npm` e a checagem do AppArmor no setup. Os CAs não mudam.
- 2026-11-10: mudança (alterar) na implementação, com decisão do usuário. Motivo: a reflexão do marcador pelo GitHub, encontrada pela revisão automática. Entraram o token fine-grained no guia e na ADR e, no aceite, a verificação `token-com-expiracao` e o aviso de reflexão. O CA9 passa a valer para a leitura direta do token, e não para o vazamento pelo próprio GitHub.
