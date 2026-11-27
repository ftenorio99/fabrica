# Solução de problemas

Problemas que já apareceram no uso real e como resolver cada um.

## O comando agiu no repositório errado ou não achou a issue
- **Sintoma:** o `/fabrica:triagem 12` lê outra issue 12, ou diz que a issue não existe.
- **Causa:** as etapas usam o repositório do diretório em que o Claude Code foi aberto.
- **O que fazer:** abra o Claude Code no clone do repositório da issue, por exemplo `~/projetos/kairo`, e rode de novo. O `/fabrica:status` mostra o diretório de cada passo. Veja [Onde rodar cada comando](primeiros-passos.md#onde-rodar-cada-comando).

## "Esta skill só pode ser chamada por você"
- **Sintoma:** você pede em texto livre "faça a spec da 12", e o Claude responde que não pode chamar a skill.
- **Causa:** as skills que mudam algo têm `disable-model-invocation: true` e só rodam quando você digita o comando. Veja [Skills só por comando](principios.md#skills-só-por-comando).
- **O que fazer:** digite o comando, por exemplo `/fabrica:spec 12`. O único que o Claude chama sozinho é o `/fabrica:status`.

## A fábrica se comporta como na versão antiga
- **Sintoma:** um PR da fábrica já foi mergeado, mas as skills ainda seguem as regras de antes.
- **Causa:** o plugin instalado não foi atualizado.
- **O que fazer:**
  ```
  /plugin marketplace update fabrica
  /reload-plugins
  ```
  A versão em uso aparece no caminho da skill (`.../fabrica/<versão>/skills/...`).

## "A label `<label>` não existe neste repositório"
- **Sintoma:** uma etapa para com essa mensagem, comum num repositório novo.
- **Causa:** as labels do fluxo ainda não foram criadas nesse repositório.
- **O que fazer:** rode `/fabrica:setup` no clone e repita a etapa. As etapas não criam labels sozinhas, de propósito.

## "O `gh` <versão> está abaixo da mínima da fábrica" ou "Não consegui ler a versão do `gh`"
- **Sintoma:** uma etapa para com uma dessas mensagens antes de mexer no GitHub, ou o `gh pr edit` falha com "Projects (classic) is being deprecated".
- **Causa:** o `gh` instalado é anterior à correção do bug dos Projects clássicos (cli/cli#11983). Isso é comum com o `gh` do repositório do Ubuntu. Na segunda mensagem, o `gh --version` não devolveu uma versão legível, e o `gh` precisa ser reinstalado.
- **O que fazer:** rode `/fabrica:setup`, que mostra a versão atual, a mínima e o comando para instalar pelo repositório oficial. Atualize e repita a etapa. Se a falha aparecer mesmo assim, a etapa refaz a edição pela API REST e avisa no chat, como diz [`skills/setup/gh.md`](../skills/setup/gh.md).

## "O `gh` não está autenticado" ou "O `gh` não está instalado"
- **Sintoma:** o setup ou uma etapa para com uma dessas mensagens.
- **O que fazer:** rode `gh auth login`, ou instale o `gh` pelas [instruções oficiais](https://github.com/cli/cli#installation), e repita o comando.

## Não há nada no fluxo
- **Sintoma:** o `/fabrica:status` não mostra nenhuma issue esperando você ou um agente.
- **Causa:** nenhuma issue tem `agente` aberta.
- **O que fazer:**
  - Com backlog, o `/fabrica:status` sugere a próxima issue: aplique `agente` nela e rode `/fabrica:triagem <nº>`.
  - Com PRD mas sem backlog, rode `/fabrica:backlog`.
  - Sem PRD, comece com `/fabrica:prd`. Veja [Projeto do zero](guias/projeto-do-zero.md).

## "Este comando desligaria os hooks do git que protegem a main"
- **Sintoma:** um comando Bash do Claude é bloqueado com essa mensagem, às vezes num comando inofensivo.
- **Causa:** o hook `protect-main.sh` lê o texto do comando e bloqueia o que citar as formas de desligar a proteção:
  - `--no-verify` e `commit -n`;
  - `core.hooksPath` e `GIT_CONFIG*`;
  - atribuições a `HOME=` ou `XDG_CONFIG_HOME=`;
  - a pasta `fabrica/githooks`.

  Ele bloqueia mesmo quando o texto só cita essas formas, como o corpo de um PR montado num heredoc.
- **O que fazer:**
  - **Corpo de issue, comentário ou PR:** escreva-o num arquivo com a ferramenta Write e passe `--body-file <arquivo>` ao `gh`. As skills já fazem assim.
  - **Comando que você quer mesmo rodar:** rode você mesmo no terminal, com `!` no prompt do Claude Code.

## "Os hooks do git da fábrica não estão instalados nesta máquina"
- **Sintoma:** a sessão abre com esse aviso, ou o Claude é bloqueado em qualquer `commit` ou `push`.
- **Causa:** a máquina ainda não tem os hooks globais do git, ou o `core.hooksPath` foi alterado.
- **O que fazer:** rode `/fabrica:setup` e confirme a instalação. Para conferir o estado, use `bash scripts/setup-githooks.sh --check` no clone da fábrica, onde o script fica. O `--check` não muda a configuração do git, mas não é só leitura: quando a origem é mais nova ou a pasta está danificada, ele publica os hooks e diz o que fez. As outras respostas estão na seção seguinte.

## Os hooks do git da fábrica avisam de outro estado
A pasta dos hooks é uma só por máquina e é compartilhada pelo Claude Code, pelo Antigravity, pelo OpenCode, pelo Codex e pelos clones usados com `--plugin-dir`, cada um na sua versão. O `setup-githooks.sh` nunca volta sozinho para uma versão menor, troca os arquivos sem deixar faltar as entradas de proteção e usa uma trava para duas sessões não escreverem ao mesmo tempo ([SPEC-246](../specs/SPEC-246.md), emenda da [ADR 0002](adr/0002-protecao-da-main-por-hooks-do-git.md)).
- **Sintoma:** a sessão abre com um aviso sobre os hooks do git, ou o `--check` responde algo além de `ok`, `atualizado <versão>`, `mais-novo <versão>` e `ocupado integra`, que são as respostas sem aviso.
- **O que cada resposta quer dizer:**
  - `reparado <versão>`: a pasta estava danificada, ou uma atualização tinha sido interrompida, e foi recuperada nessa versão. Não precisa fazer nada.
  - `mais-novo <versão> incerta`: a pasta é de uma versão mais nova que a deste plugin, gravada por um script antigo, e o script não consegue provar que ela está íntegra. Nada foi trocado.
  - `divergente <versão>` ou `divergente <versão> incerta`: a pasta tem a mesma versão do plugin, mas outro conteúdo. Nada foi trocado. A saída é rodar o setup de uma distribuição de versão maior; o `--allow-downgrade` não troca conteúdo da mesma versão.
  - `falha danificada` ou `falha versao-desconhecida`: a pasta está danificada e é de uma versão maior que a deste plugin, ou de uma versão que não dá para provar. Só os invólucros que faltavam foram recriados, e as permissões perdidas, devolvidas; nada foi sobrescrito.
  - `falha interrompida` ou `falha danificada` depois de uma atualização interrompida: este plugin é mais antigo que a versão que estava sendo instalada, que o diário da pasta registra. Rode o setup de uma distribuição dessa versão ou mais nova; o diário fica até lá.
  - `falha rollback-interrompido`: um rollback ou uma substituição foi interrompido. Ele não continua sozinho: rode o rollback de novo, com uma nova confirmação, ou, depois de um rollback, o setup de uma distribuição de versão maior ou igual à que estava instalada antes dele (o `de` do diário), que sobe pelo caminho normal.
  - `ocupado incerta`: outro setup está rodando, ou a trava da pasta ficou num estado que o script não decide sozinho. Se o aviso se repetir, siga a recuperação manual abaixo.
  - `falha <outro código>`: `origem-invalida` (versão do plugin fora do formato), `destino-invalido` (a pasta dos hooks virou um symlink ou um arquivo, ou tem uma subpasta, que o script não remove; confira o conteúdo e remova-a à mão), `preparacao` ou `publicacao` (cópia ou troca dos arquivos falhou, sem perder as entradas de proteção) e `trava` (o setup perdeu a trava no meio). O detalhe sai no erro do script.
- **O que fazer:**
  - O caminho normal é rodar o `/fabrica:setup` de uma distribuição na versão indicada ou mais nova, ou atualizar todas, como em "Migração" abaixo.
  - **Rollback:** para voltar de propósito para uma versão menor, rode o `/fabrica:setup` dessa distribuição e confirme o rollback, ou rode `bash scripts/setup-githooks.sh --allow-downgrade <versão do plugin>` no clone dela. A versão repetida é a confirmação. Sem nada a reverter (a mesma versão, mesmo com conteúdo diferente, ou uma versão maior), o script sai com 2, diz por quê e não altera nada. A versão menor pode ter menos proteções que a instalada, e o rollback dura até uma distribuição mais nova rodar o setup, que sobe a versão de novo. Para mantê-lo, atualize ou desative as distribuições mais novas. Se o rollback for interrompido, ele só continua com um novo `--allow-downgrade` confirmado.
  - **Recuperação manual da trava**, no terminal, porque o `protect-main.sh` recusa comandos do agente que citam a pasta dos hooks:
    1. Confirme que nenhum setup está rodando: `pgrep -af setup-githooks.sh` não deve listar nada.
    2. Inspecione a pasta com `ls -la ~/.config/fabrica/githooks/` (ou o caminho com `XDG_CONFIG_HOME`) e o `readlink` do `.lock` e do `.break`. Confira o host e se o PID não existe mais (`kill -0 <pid>` falha) ou é de outro processo.
    3. Remova o que estiver abandonado: `rm` no `.break` e no `.lock`, ou `rm -r` no `.lock` se ele for uma pasta criada por engano.
    4. Rode `bash <clone>/scripts/setup-githooks.sh --check`.
- **Migração:** a proteção completa só vale depois que todas as distribuições ativas na máquina tiverem o script novo. Uma distribuição antiga ainda pode trocar a pasta por uma versão menor ou abrir a janela sem as entradas de proteção; o script novo detecta isso na sessão seguinte e volta para a versão maior quando pode. Para atualizar:
  - Claude Code: `claude plugin marketplace update fabrica` e `claude plugin update fabrica@fabrica`;
  - Antigravity: reinstale com `agy plugin install`;
  - OpenCode: atualize o adaptador, como diz o [`opencode/README.md`](../opencode/README.md);
  - clones usados com `--plugin-dir`: rebase sobre a `main`;
  - Codex: gere o pacote de novo depois da readequação da SPEC-245.

  Depois, abra uma sessão ou rode o `/fabrica:setup` e confira que o `--check` responde `ok`. Numa máquina com umask 002, a pasta gravada pelo script antigo tem permissões 0775 e conta como danificada: a primeira execução nova a republica (`reparado`) ou, se este plugin for mais antigo que ela, avisa sem trocar nada.
- **Limites:** a proteção cobre interrupções, disco cheio, sessões simultâneas e distribuições de versões diferentes. Ela não cobre distribuições antigas, edição manual da pasta, processos do mesmo usuário que ignoram a trava, pasta em NFS ou compartilhada entre contêineres com o mesmo nome de host, nem o macOS, que não foi testado. A lista completa está na SPEC-246.

## "Commit direto na 'main' bloqueado" ou "Push para a main bloqueado"
- **Sintoma:** o git recusa um commit ou um push.
- **Causa:** os hooks globais recusam commit na `main`/`master` e push para a `main`/`master` remota. Isso vale para os repositórios da máquina, inclusive comandos feitos à mão, exceto os que têm `core.hooksPath` local (veja [`main` protegida](principios.md#main-protegida)).
- **O que fazer:**
  - **Commit:** crie uma branch e abra um PR. Se o commit já foi feito na `main` local, mova-o:
    ```
    git switch -c <tipo>/<nº>-<descricao>
    git branch -f main origin/main
    ```
  - **Exceção de verdade, num repositório seu:** use `--no-verify` no seu terminal.

  O commit inicial e o primeiro push de um repositório novo passam sem bloqueio.

## A etapa parou no `issue-worktree.sh ensure`
- **Sintoma:** o `/fabrica:spec`, o `/fabrica:implementar` ou o `/fabrica:revisar` para antes de qualquer commit e repete no chat uma mensagem do `issue-worktree.sh` ([Uma worktree por issue](fluxo.md#uma-worktree-por-issue)).
- **O que fazer**, conforme a mensagem:
  - **A worktree está noutra branch (saída 3):** a pasta `<clone>/.worktrees/<nº>` existe com uma branch diferente da issue, ou não é uma worktree. Confira se a branch da issue mudou; se a pasta não serve mais, remova-a com `git worktree remove <pasta>` e repita a etapa.
  - **A branch está em uso noutra pasta (saída 4):** em geral, o clone principal está na branch da issue, como numa issue que começou antes das worktrees. Troque essa pasta de branch uma vez (`git -C <pasta> switch main`) e repita a etapa.
  - **Limite de worktrees (saída 5):** o clone já tem 3 worktrees de issue. Termine uma (merge ou fechamento do PR) e rode o `/fabrica:avancar`, ou a próxima etapa, que remove as de PR fechado.
- **`gh pr merge --delete-branch` avisa que não apagou a branch local:** rodado no clone, o `gh` não consegue apagar a branch que está presa numa worktree. O merge acontece mesmo assim, e a próxima etapa ou o `/fabrica:avancar` remove a worktree e a branch local.
- **Uma worktree de PR fechado não some:** ela tem mudança não commitada ou commit que não chegou ao PR, e aparece como `mantida … trabalho-local` no relatório do `/fabrica:avancar`. Decida você: envie o trabalho ou remova a worktree com `git worktree remove --force <pasta>`.
