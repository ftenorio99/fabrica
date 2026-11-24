# SPEC-203: Identidade de commit do agente no job do dispatcher

**Issue:** #203 · **PRD:** F1, F4 · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-24

## Contexto
O job do dispatcher roda o `claude` como `fabrica-agent`, com ambiente fechado (`env -i` no `scripts/run-as-agent.sh`) e com `GIT_CONFIG_GLOBAL` apontando para `/opt/fabrica-gitconfig` (SPEC-107, CA22). Esse arquivo só tem `[core] hooksPath`, e o `~/.gitconfig` do agente deixa de ser lido. O git do agente fica sem `user.name` e `user.email`, e no runner (usuário de sistema sem GECOS, hostname sem domínio) o `git commit` pode falhar com "Author identity unknown". A falha foi vista na revisão da #107 (PR #202). Ainda não se sabe se ela explica o commit que não saiu no CA15 parte 2.

## Objetivo
O git do `fabrica-agent` no job tem uma identidade de commit fixa, lida do arquivo de configuração que o `prepare` grava, e um commit real do agente no runner sai com ela.

## Comportamento esperado
- `job-isolation.sh prepare` grava `/opt/fabrica-gitconfig` com duas seções: `[core]` com `hooksPath` (como hoje) e `[user]` com `name = <agent_user>` e `email = <agent_user>@users.noreply.github.com`. No runner, `<agent_user>` é `fabrica-agent`.
- O arquivo continua root-owned e `0644`, e o `lock` não muda: o `agent.env` já traz `GIT_CONFIG_GLOBAL`.
- Um `git commit` do agente numa branch de feature, sem `-c user.*` e sem variáveis `GIT_AUTHOR_*`, `GIT_COMMITTER_*` ou `EMAIL`, sai com autor e committer `fabrica-agent <fabrica-agent@users.noreply.github.com>`. O commit na `main` continua recusado pelo hook.
- Um `[user]` no `~/.gitconfig` do agente não vale, porque o git dele lê só o arquivo do `prepare`.
- O teste de aceite do runner ganha a verificação `commit-do-agente`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `job-isolation.sh prepare` grava no arquivo de `FABRICA_GITCONFIG_FILE` a seção `[user]` com `name = fabrica-agent` e `email = fabrica-agent@users.noreply.github.com`, derivados de `agent_user` (`FABRICA_AGENT_USER`), além do `[core] hooksPath` que já existe. `git config --file <arquivo> --get user.name` e `--get user.email` devolvem esses valores, e o arquivo segue com modo `644`. | unitário — `scripts/test-job-isolation.sh`, no caso do `prepare` |
| CA2 | Com `HOME` numa pasta cujo `.gitconfig` tem `[user] name = outro` e `email = outro@exemplo.com`, e com `GIT_CONFIG_GLOBAL` no arquivo do CA1, rodando o git com `env -i` (só `PATH`, `HOME` e `GIT_CONFIG_GLOBAL`) e sem `-c user.*`, um `git commit --allow-empty` numa branch de feature sai com 0. `git log -1 --format='%an <%ae>|%cn <%ce>'` devolve `fabrica-agent <fabrica-agent@users.noreply.github.com>\|fabrica-agent <fabrica-agent@users.noreply.github.com>`. | unitário — `scripts/test-job-isolation.sh`, com git real num repositório temporário |
| CA3 | Controle negativo do CA2: com uma cópia do arquivo sem a seção `[user]` e `-c user.useConfigOnly=true`, o mesmo commit falha (saída diferente de 0) e o `rev-list --count` da branch não muda. Isso prova que, no CA2, a identidade veio do arquivo e não de um palpite do git. | unitário — `scripts/test-job-isolation.sh` |
| CA4 | O helper `agent_git` dos testes do CA23 da SPEC-107 deixa de passar `-c user.name` e `-c user.email` e passa a usar o arquivo do `prepare`. Os checks do CA23 (main recusada, feature aceita, `git config --global` sem efeito) seguem passando. O commit inicial do repositório de teste, feito fora do ambiente do agente, pode manter o `-c`. | unitário — `bash scripts/test-job-isolation.sh` sai com 0 |
| CA5 | `scripts/test-job-acceptance.sh` ganha a verificação `commit-do-agente`, entre `git-pelo-proxy` e `marcador-no-ambiente`. Ela cria um repositório numa pasta temporária do agente (dono `fabrica-agent`, fora do `$work` de root, apagada no fim), roda como agente pelo `as_agent` o `git init -b main`, o `git switch -c feat/aceite` e o `git commit --allow-empty -m aceite` sem `-c user.*` e confere o `%an <%ae>` do CA2. Imprime `ok commit-do-agente`, ou `falha commit-do-agente: <primeiros 200 bytes do stderr do git>`. | e2e — `ftenorio99/fabrica-teste`, com o `isolamento-aceite.yml` copiado e a linha `claude plugin marketplace add ftenorio99/fabrica#fix/203-identidade-commit-agente`; link do run no PR |
| CA6 | No ponta a ponta com esta versão do plugin, um comentário do usuário pedindo ajuste numa issue de teste em "Spec para aprovar" roda a `spec`. O commit `docs: ajusta spec da issue #<nº>` aparece na branch da issue com autor `fabrica-agent <fabrica-agent@users.noreply.github.com>`, conferido com `gh api repos/ftenorio99/fabrica-teste/commits/<branch> --jq '.commit.author'`. Se o commit não sair, o CA fica reprovado e o PR registra, a partir do `gh run view <id> --log` e do `stage.json`, a mensagem do git ou de outra causa. | e2e — `ftenorio99/fabrica-teste`, com o `agente.yml` copiado e o `marketplace add` apontando para esta branch; a issue de teste é fechada no fim com um comentário dizendo que era teste |
| CA7 | `docs/guias/dispatcher.md` ganha a linha `commit-do-agente` na tabela do teste de aceite e uma frase dizendo que os commits do agente no job saem como `fabrica-agent <fabrica-agent@users.noreply.github.com>`, pelo arquivo de configuração do `prepare`. | manual — leitura do diff na revisão |

**Casos adversariais não aplicáveis:** ID de outro usuário na URL ou na API — os fluxos não leem nem alteram registro com dono; entrada vazia ou inválida — a identidade é fixa no script e não vem de dado do usuário, e o texto do comentário de ajuste segue a SPEC-107 e o ADR 0008, que esta spec não muda; sessão expirada ou ausente — não há login de usuário, e a falta de token já faz o `lock` falhar fechado (SPEC-106); duplo envio — o gesto repetido fica com a concorrência do dispatcher (SPEC-107, CA19), que esta spec não muda; abuso de limite — os fluxos não têm regra com limite.

## Fora de escopo
- Assinar commits do agente (GPG/SSH) ou exigir commit verificado.
- Impedir o agente de trocar a identidade por `-c user.name=…` ou pela `.git/config` do checkout. A identidade é um padrão para o histórico, não uma barreira de segurança: o que limita o agente é o token e os hooks.
- Mudar o `prepare` fora do arquivo de configuração do git, ou o `run-as-agent.sh`.
- Identidade do git na sessão local do usuário ou no `sbx`.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/job-isolation.sh`: no `cmd_prepare`, o bloco que grava `"$gitconfig_dst"` acrescenta `[user]` com `name = $agent_user` e `email = $agent_user@users.noreply.github.com`. O comentário do bloco passa a citar a SPEC-203.
- `scripts/test-job-isolation.sh`: checks do CA1 no caso do `prepare` e do CA2 e do CA3 junto aos do CA23 (mesmo `$g`, mesmo `$cfg`), e o `agent_git` sem `-c user.*` (CA4).
- `scripts/test-job-acceptance.sh`: verificação `commit-do-agente` (CA5), numerada como as outras.
- `docs/guias/dispatcher.md`: linha da tabela e frase sobre a identidade (CA7).
- `.claude-plugin/plugin.json`: sobe a `version` (0.49.0 → 0.49.1).

**Dados:** nenhum.

**Interfaces:** sem mudança de uso. O arquivo `/opt/fabrica-gitconfig` fica assim (com `<hooks>` = `$hooks_dst`):

```ini
[core]
	hooksPath = <hooks>
[user]
	name = fabrica-agent
	email = fabrica-agent@users.noreply.github.com
```

**Decisões:**
- A identidade fica numa seção `[user]` do arquivo que o `prepare` já grava em `/opt/fabrica-gitconfig`, porque ele é o único arquivo global que o git do agente lê (SPEC-107, CA22) e já é o ponto único da configuração do git dele. Alternativa descartada: `GIT_AUTHOR_*` e `GIT_COMMITTER_*` no `agent.env`, que espalharia a configuração do git por dois lugares (recomendação da triagem).
- Nome `fabrica-agent` e e-mail `fabrica-agent@users.noreply.github.com`, derivados de `agent_user`, porque o repositório já usa o domínio `noreply` do GitHub, ele não expõe e-mail real e o histórico distingue o que o agente fez. Alternativa descartada: reaproveitar a identidade do usuário (recomendação da triagem).
- O e-mail não é o `noreply` com ID numérico de uma conta (`<id>+<login>@…`), porque o `fabrica-agent` não é uma conta do GitHub. Por isso o commit aparece sem avatar e sem link de perfil. Alternativa descartada: criar uma conta de máquina, que é decisão maior que esta issue.
- O CA de prova roda no teste de aceite do runner (CA5) e numa etapa real (CA6), e não só no teste unitário, porque o defeito depende do usuário de sistema e do hostname do runner, que o teste local não reproduz.

**Fontes da documentação:**
- git 2.53.0 — doc local: `git help config` (`user.name`, `user.email`, `user.useConfigOnly`, precedência das variáveis `GIT_AUTHOR_*`, `GIT_COMMITTER_*` e `EMAIL`) e `git help commit` (seção COMMIT INFORMATION).
- Claude Code 2.1.331 — `claude plugin marketplace add --help` (a ajuda não cita o `#ref`) e Context7 `/websites/code_claude` (o `owner/repo#ref` fixa branch ou tag; com `source: "./"` no `marketplace.json`, o plugin vem do mesmo ref). Versão não confirmada no Context7.
- gh 2.105.0 — `gh run view --help` (`--log`) e `gh api --help` (`--jq`).

**ADR:** nenhum.

## Testes
- `bash scripts/test-job-isolation.sh`: CA1 a CA4, com os destinos numa pasta temporária e git real. Para o CA2 e o CA3, rode o git com `env -i PATH="$PATH" HOME=… GIT_CONFIG_GLOBAL=…`, para que nenhuma variável de identidade do ambiente de quem roda o teste vaze para o commit.
- `scripts/test-job-acceptance.sh` no `ftenorio99/fabrica-teste` (CA5): pela aba Actions, com o `isolamento-aceite.yml` apontando para a branch.
- Ponta a ponta (CA6): no `ftenorio99/fabrica-teste`, com o `agente.yml` copiado e o `marketplace add` na branch. O ajuste de spec é feito numa issue de teste. Depois do teste, o `marketplace add` dos dois workflows de teste volta para `ftenorio99/fabrica`.
- O repositório não tem `make test` nem `make e2e`. Os testes rodam pelos scripts acima.

## Passos de produção
nenhum

## Riscos e dúvidas
- O CA6 pode mostrar que a identidade não era a causa do commit que não saiu no CA15 parte 2 da #107. Nesse caso, a correção vale do mesmo jeito (o CA5 prova que o commit sai no runner), e o PR registra a causa encontrada no log para uma issue nova.
- A triagem diz que o agente "não troca a própria identidade". Isso só vale para o arquivo global: com `-c` ou com a `.git/config` do checkout, ele troca. Fica fora de escopo, porque o autor do commit é metadado e não dá acesso.
- O `#ref` do `marketplace add` não aparece na ajuda do CLI instalado. Se falhar no runner, o caminho antes do merge do CA5 e do CA6 é um fork do marketplace num repositório de teste, e o PR registra isso.

## Histórico
- 2026-11-24: criação.
