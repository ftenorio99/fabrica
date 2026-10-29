# SPEC-27: Proteger a main com hooks pre-commit e pre-push do git em vez de analisar o comando

**Issue:** #27 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-10-29

## Contexto
O `hooks/protect-main.sh` protege a `main` lendo o texto do comando Bash no PreToolUse do Claude Code. Para isso, ele tenta reproduzir o shell: aspas, `$(...)`, `bash -c`, `eval`, variáveis e subshells. As #18, #22 e #24 corrigiram formas que escapavam ou bloqueavam por engano, a #26 lista mais quatro, e o hook já tem 493 linhas. O git já tem pontos de verificação que rodam na hora exata do commit e do push, depois que o shell resolveu tudo. A triagem decidiu, com a resposta (a), que a proteção vale para todos os commits e pushes da máquina, inclusive os feitos à mão. No terminal, o usuário passa por cima com `--no-verify`.

## Objetivo
Commit e push na `main` são recusados pelo próprio git, por hooks globais instalados uma vez por máquina, qualquer que seja a forma do comando. O `protect-main.sh` deixa de ler shell e só impede o Claude de desligar esses hooks.

## Comportamento esperado

### Modelo de ameaça
A proteção existe contra erros e comandos inocentes, não contra um agente que tenta sabotá-la. O hook bloqueia os jeitos conhecidos de desligar a verificação pela linha de comando. Ficam fora de escopo editar ou apagar os arquivos dos hooks com outras ferramentas, ou trocar o binário do git.

### Hooks do git (pasta `githooks/` do plugin)
| Hook | Regra | Mensagem ao recusar |
|---|---|---|
| `pre-commit` | Recusa se a branch atual (`git symbolic-ref --short -q HEAD`) for `main` ou `master` e o repositório já tiver commit (`git rev-parse -q --verify HEAD`). Sem commit, libera o commit inicial. | "Commit direto na '<branch>' bloqueado pelas práticas do usuário. Crie uma branch (ex.: git switch -c feat/<n>-descricao) e abra um PR." |
| `pre-merge-commit` | A mesma regra do `pre-commit`, para merges que criam commit (`git merge` sem fast-forward). | A mesma do `pre-commit`. |
| `pre-push` | Lê do stdin as linhas `<ref local> <sha local> <ref remota> <sha remoto>`. Recusa se alguma ref remota for `refs/heads/main` ou `refs/heads/master` e o sha remoto não for só zeros, ou seja, se a branch já existir no remoto. Isso vale também para apagar a `main` remota. Se ela ainda não existir, é o primeiro push e passa. | "Push para a main bloqueado pelas práticas do usuário. Faça push da sua branch e abra um PR (gh pr create)." |

**Encadeamento:** com `core.hooksPath` global, o git ignora o `.git/hooks` de cada repositório. Para não quebrar o que já existe, a pasta instalada tem uma entrada para cada nome de hook do git (lista de `githooks(5)`). Cada entrada:
1. roda a regra da fábrica, quando houver uma para aquele nome;
2. depois, executa o hook de mesmo nome do repositório (`$(git rev-parse --git-common-dir)/hooks/<nome>`), se ele existir e for executável, com os mesmos argumentos e o mesmo stdin;
3. termina com o código de saída dele.

O caminho vem de `--git-common-dir` e não de `--git-path hooks`, porque este último já devolve o `core.hooksPath`.

**Mudança em relação ao hook atual:** com a `main` em checkout, `git push origin feat/x` deixa de ser bloqueado. O `pre-push` olha as refs enviadas, não a branch atual.

### Instalação: `scripts/setup-githooks.sh`
- **Destino:** copia o conteúdo de `githooks/` para `${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks/`, com um arquivo `VERSION` igual à `version` do `plugin.json`. Depois, roda `git config --global core.hooksPath <destino>`.
- **Idempotente:** rodar de novo atualiza os arquivos e não muda mais nada.
- **Se já houver outro `core.hooksPath` global**, de outra ferramenta, não sobrescreve. Sai com erro e mostra o valor atual. Com `--force`, sobrescreve.
- **Modo `--check`:** não muda a configuração do git e imprime uma de três linhas:
  - `ok`, quando está instalado e na versão do plugin;
  - `atualizado <versão>`, quando a versão era antiga e os arquivos foram copiados de novo;
  - `ausente`, quando o `core.hooksPath` global não aponta para o destino.

### `/fabrica:setup`
- Continua criando as labels do repositório, como hoje.
- Depois, confere os hooks do git com `setup-githooks.sh --check`. Se estiverem ausentes, explica o que será feito e pede confirmação com o AskUserQuestion antes de rodar `setup-githooks.sh`, porque ele altera o `~/.gitconfig`.
- O `/fabrica:prd`, que roda o setup das labels sozinho, não instala os hooks do git.

### Atualização: SessionStart
O `hooks/hooks.json` ganha um hook `SessionStart` que roda `setup-githooks.sh --check`:
- com `atualizado`, os arquivos já foram copiados, e a sessão segue sem aviso;
- com `ausente`, o hook imprime um aviso para o contexto da sessão: "Os hooks do git da fábrica não estão instalados nesta máquina. Rode /fabrica:setup."

### `protect-main.sh` reduzido
Sai toda a análise de shell (`code_view`, `expand_code`, variáveis e diretórios). O hook passa a fazer só checagens de texto sobre o comando inteiro, sem separar aspas:

| Situação | Resultado |
|---|---|
| Hooks do git ausentes (o `core.hooksPath` global não aponta para o destino) e o comando contém `commit` ou `push` | Bloqueia: "Os hooks do git que protegem a main não estão instalados. Rode /fabrica:setup e repita o comando." |
| O comando contém `--no-verify` | Bloqueia. |
| O comando contém `commit` e uma opção curta com `n` depois dele, no mesmo trecho até `;`, `&` ou `\|` (ex.: `commit -n`, `commit -nm x`, `commit -an`) | Bloqueia. |
| O comando contém `hookspath`, sem diferença de maiúsculas, em qualquer forma (`-c core.hooksPath=`, `git config … core.hooksPath`, `--config-env`) | Bloqueia. |
| O comando contém `GIT_CONFIG` (`GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_*`, `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`, `GIT_CONFIG_NOSYSTEM`) | Bloqueia. |
| O comando atribui `HOME=` ou `XDG_CONFIG_HOME=` | Bloqueia, porque trocaria o arquivo de configuração global e, com ele, o `core.hooksPath`. |
| O comando cita o caminho da pasta instalada (`fabrica/githooks`) | Bloqueia, para evitar `rm`, `mv` e `chmod` nos hooks. |
| Qualquer outro comando | Libera. |

Nos bloqueios dessas checagens, a mensagem é: "Este comando desligaria os hooks do git que protegem a main (<motivo>). Se for intencional, rode você mesmo no terminal."

O `hooks.json` deixa de usar o filtro `if: Bash(*git*)`, porque `HOME=` e `GIT_CONFIG` podem aparecer sem a palavra `git`. As checagens são `grep` sobre o texto e custam poucos milissegundos.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com os hooks instalados num `HOME` de teste, um commit de verdade num repositório na `main` falha, e a `main` continua com o mesmo número de commits, em todas as formas: `git commit`, `bash -c "git -c a=\"b\" commit"`, `eval git commit`, `W=<repo>; git -C $W commit`, `timeout 5 bash -c 'git commit'`, `bash -c "$(echo git) commit"`, a concatenação com `'\''`, `git merge --no-ff feat` com a `main` em checkout e `git commit --amend`. | unitário (`scripts/test-protect-main.sh`) |
| CA2 | Um push de verdade para um remoto local que já tem a `main` falha, em todas as formas: `git push origin main` a partir de uma feature, `git push origin HEAD:main`, `git push` com a `main` em checkout e `git push origin :main`. Um push de `feat/x` com a `main` em checkout passa. | unitário |
| CA3 | As exceções continuam valendo: o commit inicial num repositório vazio passa, e o primeiro push da `main` para um remoto sem `main` passa. Commit e push numa branch ou worktree de feature passam. | unitário |
| CA4 | Encadeamento: um `pre-commit` e um `commit-msg` no `.git/hooks` do repositório rodam numa branch de feature, porque cada um grava um arquivo marcador. Um `pre-commit` local que sai com 1 faz o commit falhar. | unitário |
| CA5 | `setup-githooks.sh`: <ul><li>a instalação num `HOME` limpo define o `core.hooksPath` global e copia todos os hooks com permissão de execução;</li><li>rodar de novo não muda nada;</li><li>com outro `core.hooksPath` global, sai com erro e não o altera; com `--force`, altera;</li><li>`--check` devolve `ok`, `ausente` e `atualizado <versão>` nos três estados.</li></ul> | unitário |
| CA6 | `protect-main.sh`: bloqueia os casos da tabela (`--no-verify`, `commit -n`, `commit -nm x`, `-c core.hooksPath=/dev/null`, `git config --global --unset core.hooksPath`, `GIT_CONFIG_GLOBAL=/dev/null git commit`, `GIT_CONFIG_COUNT=1 …`, `HOME=/tmp git commit`, `rm -rf ~/.config/fabrica/githooks`). Libera comandos comuns: `git commit -m "$(cat <<'EOF' … EOF)"`, `git log -n 5`, `git push -u origin feat/x` e `echo "git commit"`. Um `gh pr create --body "…"` que cita `--no-verify` é bloqueado, e esse falso positivo é aceito. Com os hooks ausentes, bloqueia `git commit` com a mensagem de instalação. | unitário |
| CA7 | `/fabrica:setup` pede confirmação antes de instalar os hooks do git e não pede de novo quando já estão instalados. O `SessionStart` imprime o aviso quando estão ausentes e atualiza os arquivos em silêncio quando a versão mudou. | manual |
| CA8 | Numa sessão com `claude --plugin-dir ~/projetos/fabrica`, o plugin instalado desligado e os hooks do git instalados, num repositório temporário na `main`: `git commit --allow-empty -m x` falha pelo git, com a mensagem de commit na `main`; `git commit --no-verify --allow-empty -m x` é bloqueado pelo PreToolUse; numa branch de feature, o commit passa. | manual |
| CA9 | `hooks/protect-main.sh` fica com menos de 80 linhas, e `code_view` e `expand_code` não existem mais. README, `CLAUDE.md` do projeto e `templates/CLAUDE.md` (se citar o hook) descrevem os hooks do git, a instalação e o `--no-verify` no terminal. A `version` passa a 0.9.0. | manual |

## Fora de escopo
- **Proteção no GitHub** (rulesets e branch protection): nos repositórios privados, exige GitHub Pro.
- **Repositórios com `core.hooksPath` local** (husky, lefthook): a configuração local vence a global, e os hooks da fábrica não rodam neles. Não há aviso automático nesta issue, e hoje nenhum projeto usa isso.
- **Commits na `main` local que não passam pelo `pre-commit`:** `git cherry-pick`, `git rebase`, `git merge` com fast-forward e `git reset`. A `main` local pode ganhar commits por esses caminhos, mas o `pre-push` impede que eles cheguem ao GitHub, e eles podem ser movidos para uma branch.
- **Sabotagem deliberada**, como editar os hooks com as ferramentas Write/Edit ou trocar o binário do git (ver "Modelo de ameaça").
- **A regra do `CLAUDE.md` global do usuário** (`~/.claude/CLAUDE.md`), que cita `hooks/protect-main.sh`: é um arquivo privado do usuário, e o PR só aponta o texto a ajustar.

## Desenho técnico
**Arquivos e módulos:**
- `githooks/` (novo):
  - `fabrica-hook`: o script único com as regras, chamado com o nome do hook;
  - um arquivo por nome de hook do git (`pre-commit`, `pre-merge-commit`, `pre-push`, `commit-msg`, `prepare-commit-msg`, `post-commit`, `post-checkout`, `post-merge`, `pre-rebase`, `post-rewrite`, `applypatch-msg`, `pre-applypatch`, `post-applypatch`, `pre-auto-gc`, `reference-transaction`, `push-to-checkout`, `sendemail-validate`, `fsmonitor-watchman`, `post-index-change`, `p4-changelist`, `p4-prepare-changelist`, `p4-post-changelist`, `p4-pre-submit`). Cada um tem duas linhas e chama `fabrica-hook <nome> "$@"`.
- `scripts/setup-githooks.sh` (novo).
- `skills/setup/SKILL.md`: passo dos hooks do git, com confirmação.
- `hooks/protect-main.sh`: reescrito com as checagens de texto.
- `hooks/hooks.json`: hook `SessionStart` e o PreToolUse sem o `if`.
- `scripts/test-protect-main.sh`: reescrito em três partes: hooks do git com repositórios reais, `setup-githooks.sh` e checagens do PreToolUse. Os casos antigos das #18, #22 e #24 que fazem sentido viram execuções reais no CA1 e no CA2.
- `README.md`, `CLAUDE.md`, `templates/CLAUDE.md` (se citar o hook) e `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:**
- `setup-githooks.sh [--check] [--force]`;
- o PreToolUse mantém a entrada e a saída de hoje;
- o `SessionStart` imprime texto no stdout, que vai para o contexto da sessão.

**Decisões:**
- **Hooks do git com `core.hooksPath` global:** o git decide com a branch e as refs reais, então nenhuma forma de shell escapa. Alternativa descartada: continuar ampliando o leitor de shell, que não fecha (#18, #22, #24 e #26).
- **Cópia para uma pasta estável, com `VERSION`:** o cache do plugin muda de pasta a cada versão, e apontar para ele prenderia a máquina numa versão. Alternativa descartada: um `core.hooksPath` dentro do cache.
- **Atualização silenciosa no `SessionStart`, instalação com confirmação no `/fabrica:setup`:** copiar arquivos para a pasta da própria fábrica é seguro. Já mudar o `~/.gitconfig` merece uma confirmação. Alternativa descartada: instalar sozinho no `SessionStart`, que mudaria a configuração global sem o usuário saber.
- **Sem os hooks do git instalados, o PreToolUse bloqueia `commit`/`push`:** é a regra "bloquear na dúvida" da #18. Sem isso, entre a atualização do plugin e o `/fabrica:setup`, a `main` ficaria sem proteção nenhuma. Alternativa descartada: só avisar, o que deixaria essa janela aberta.
- **Checagens de texto amplas no PreToolUse**, aceitando falsos positivos raros (ex.: um `gh pr create` cujo corpo cita `--no-verify`): a lista é pequena e estável, e o falso positivo se resolve reescrevendo o texto. Alternativa descartada: separar as aspas antes de checar, o que traria de volta o leitor de shell.
- **Um único `fabrica-hook` com entradas finas por nome:** a regra e o encadeamento ficam num lugar só. Alternativa descartada: um script completo por hook, com código repetido.

**Fontes da documentação:**
- Git 2.53.0, hooks e `core.hooksPath`: conhecimento do modelo, não verificada. Os detalhes que contam, como o formato do stdin do `pre-push`, `--git-path hooks` respeitando `core.hooksPath` e o `pre-merge-commit`, serão conferidos com o git local nos testes. Fonte local: `git help githooks`.
- Claude Code, hook `SessionStart` com stdout no contexto: conhecimento do modelo, não verificada. Será conferido na verificação manual do CA7.

**ADR:** `docs/adr/0002-protecao-da-main-por-hooks-do-git.md`. A decisão muda onde a proteção da `main` mora em todas as máquinas e projetos, não só nesta issue.

## Testes
- **`scripts/test-protect-main.sh`:**
  - cria um `HOME` e um `GIT_CONFIG_GLOBAL` temporários;
  - instala os hooks com `setup-githooks.sh`;
  - executa commits e pushes reais em repositórios e remotos locais. O critério é o resultado no git (número de commits da `main`, refs do remoto), não a saída de um hook;
  - cobre os CA1 a CA6.
- **Verificações manuais:** CA7 e CA8 com `claude --plugin-dir`, como nas #22 e #24.
- **Tempo:** o PreToolUse leva menos de 50 ms num comando de 40 KB.

## Riscos e dúvidas
- **Repositórios com hooks locais:** passam a depender do encadeamento. Um hook que leia o stdin, como `pre-push` ou `reference-transaction`, precisa recebê-lo inteiro. Por isso, o `fabrica-hook` guarda o stdin num arquivo temporário antes de usá-lo.
- **Mudança para o próprio usuário:** com a resposta (a), um commit na `main` feito à mão no terminal também falha. O README precisa deixar claro o `--no-verify`.
- **`SessionStart`:** se o formato do hook ou o destino do stdout forem diferentes do esperado, o aviso pode não aparecer. Os arquivos continuam sendo atualizados, e o bloqueio do PreToolUse sem hooks instalados cobre a segurança.
- **Tamanho:** a mudança está no limite do G. Se crescer, o `SessionStart` (CA7) pode ir para uma issue seguinte, mantendo a atualização manual pelo `/fabrica:setup`.

## Histórico
- 2026-10-29: criação.
- 2026-10-29: aprovada pelo usuário.
