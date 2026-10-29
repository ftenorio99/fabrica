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
- **Causa:** as seis labels do fluxo ainda não foram criadas nesse repositório.
- **O que fazer:** rode `/fabrica:setup` no clone e repita a etapa. As etapas não criam labels sozinhas, de propósito.

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
- **O que fazer:** rode `/fabrica:setup` e confirme a instalação. Para conferir o estado, use `bash scripts/setup-githooks.sh --check` neste repositório. A resposta é `ok`, `ausente` ou `atualizado <versão>`.

## "Commit direto na 'main' bloqueado" ou "Push para a main bloqueado"
- **Sintoma:** o git recusa um commit ou um push.
- **Causa:** os hooks globais recusam commit na `main`/`master` e push para a `main`/`master` remota. Isso vale para qualquer repositório da máquina, inclusive comandos feitos à mão.
- **O que fazer:**
  - **Commit:** crie uma branch e abra um PR. Se o commit já foi feito na `main` local, mova-o:
    ```
    git switch -c <tipo>/<nº>-<descricao>
    git branch -f main origin/main
    ```
  - **Exceção de verdade, num repositório seu:** use `--no-verify` no seu terminal.

  O commit inicial e o primeiro push de um repositório novo passam sem bloqueio.
