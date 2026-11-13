# ADR 0010: Isolamento do agente pelo Docker Sandboxes (`sbx`), com opção sem sandbox

**Status:** proposto · **Data:** 2026-11-12 · **Origem:** issue #141

## Contexto
A [ADR 0005](0005-isolamento-do-agente-em-sandbox.md) isolou o agente local com o sandbox nativo do Claude Code (`bwrap` e `socat`, `mask` do token e `tlsTerminate`). No uso, ele ficou frágil:
- depende de perfil do AppArmor, do token do `gh` fora do chaveiro e de um cabeçalho do git gerado à parte (`setup-git-auth.sh`), refeito a cada troca de token;
- a expressão do `mask` em `templates/sandbox-user.json` engole o `}` do `hosts.yml`;
- bloqueia o Docker e o `localhost`, o que mandou a verificação de integração para o CI ([ADR 0007](0007-verificacao-de-integracao-pelo-ci.md));
- o proxy troca o marcador do token também no corpo da requisição, o risco residual aceito na ADR 0005.

Em 2026-11-12, o Docker Sandboxes (`sbx` 0.51.0) foi testado nos projetos `ancora` e `kairo` (issue #141). Passaram: rede escopada, token-marcador, home isolado, plugin, push de branch, Docker e Compose, `/fabrica:status` e `/fabrica:setup` dentro da VM. A ADR 0005 já citava o `sbx` como alternativa que "isola mais".

A F1 do PRD pede que o agente rode em sandbox, sem ler segredos em claro.

## Decisão
O sandbox nativo do Claude Code sai da fábrica. Cada projeto escolhe um de dois modos de isolamento, gravado em `.fabrica/isolamento.txt`, versionado:
- **`sbx`** (padrão): o agente roda numa VM do Docker Sandboxes, com a rede liberada só para os hosts de uma política escopada à VM e com o token do GitHub posto pelo proxy (`sbx secret set github`), sem entrar na VM.
- **`sem-sandbox`**: o agente roda direto na máquina, sem isolamento, por decisão explícita do usuário. É uma exceção à F1 do PRD, registrada aqui. Ficam os hooks do git ([ADR 0002](0002-protecao-da-main-por-hooks-do-git.md)) e o hook de produção ([ADR 0006](0006-producao-fora-do-alcance-do-agente.md)).

O `/fabrica:setup` pergunta o modo, grava a escolha e orienta: no modo `sbx`, imprime o checklist da VM, porque a VM, a política de rede e o secret são criados pelo usuário, no host; no modo `sem-sandbox`, avisa que não há isolamento.

O bloqueio de rede dos hosts de produção da ADR 0006 (`sandbox.network.deniedDomains`) deixa de existir. No modo `sbx`, vale a política de rede escopada, que não lista os hosts de produção. No modo `sem-sandbox`, fica só o hook `protect-production.sh`.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Manter o sandbox nativo como terceiro modo | Mantém os scripts, os templates e o aceite que motivaram a troca, para um modo que o usuário não vai usar. |
| Só o `sbx`, sem modo sem sandbox | O usuário quer poder rodar direto na máquina num projeto, sabendo que não há isolamento. Gravar a escolha deixa a exceção visível. |
| Consertar o sandbox nativo (expressão do `mask`, chaveiro) | Não resolve o Docker bloqueado nem o risco residual do marcador no corpo da requisição. |
| Gravar o modo no `.claude/settings.json` | O arquivo é do Claude Code. A configuração da fábrica já fica em `.fabrica/` (`.fabrica/producao.txt`). |
| O setup criar a VM, a política e o secret | São comandos do host, e a etapa pode estar rodando dentro da VM. Mexer em política de rede e em credencial é gesto do usuário. |

## Consequências
- O `sbx` (Docker Sandboxes) passa a ser dependência do modo padrão. O `bubblewrap`, o `socat`, o perfil do AppArmor, o `tlsTerminate` e o `git-auth.gitconfig` deixam de ser.
- Os hooks do git vivem na VM e somem com `sbx rm`. O `/fabrica:setup` roda de novo dentro de cada VM nova; sem ele, o push na `main` passa.
- O plugin é instalado dentro de cada VM, porque o `~/.claude` do host não entra nela.
- O `sbx` nasce com a rede aberta. Enquanto o usuário não aplicar a política escopada do checklist, a VM alcança qualquer host.
- O `.claude/settings.json` dos projetos deixa de ter o bloco `sandbox`. Nos projetos que já o têm, o bloco esconde o `GH_TOKEN` dentro da VM até ser removido.
- Docker e Compose funcionam dentro da VM. O limite que motivou a ADR 0007 deixa de existir no modo `sbx`, e a revisão daquela ADR fica para uma issue própria.
- No modo `sem-sandbox`, o agente lê o token do `gh`, as chaves SSH e os `.env` da máquina e alcança qualquer host.
- O isolamento do job do dispatcher (#106) precisa ser revisto à luz desta decisão.
- O teste de aceite da ADR 0005 (`scripts/test-sandbox-acceptance.sh`) não vale para o `sbx`. Um aceite novo fica para a issue que remove o sandbox nativo do plugin.
