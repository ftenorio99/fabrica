# SPEC-29: Formas de desligar os hooks do git que o protect-main não bloqueia

**Issue:** #29 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** aprovada · **Atualizada em:** 2026-10-29

## Contexto
Desde a #27 (PR #28, ADR 0002), commit e push na `main` são recusados por hooks globais do git (`core.hooksPath` → `~/.config/fabrica/githooks/`). O `hooks/protect-main.sh` é um PreToolUse que só impede o Claude de desligar esses hooks, com checagens de texto sobre o comando inteiro. A revisão do PR #28 achou cinco formas de desligá-los que passam por essas checagens. Três delas foram confirmadas com commits reais na `main`.

Na triagem, o usuário escolheu:
- **1a:** bloquear as cinco formas e registrar no ADR 0002 que outras manipulações de ambiente ficam fora do modelo de ameaça;
- **2a:** manter bloqueada a leitura `git config --get core.hooksPath`.

## Objetivo
O PreToolUse bloqueia as cinco formas conhecidas de desligar os hooks pelo ambiente, pela seção `core` do `~/.gitconfig` e por abreviação do `--no-verify`. O ADR 0002 diz o que continua fora do modelo de ameaça.

## Comportamento esperado
As checagens continuam sendo de texto sobre o comando inteiro, sem separar aspas, como hoje. A mensagem também não muda: "Este comando desligaria os hooks do git que protegem a main (<motivo>). Se for intencional, rode você mesmo no terminal."

| Situação | Exemplos | Motivo na mensagem |
|---|---|---|
| `unset` de `HOME` ou `XDG_CONFIG_HOME`, no mesmo trecho até `;`, `&`, `\|` ou o fim da linha | `unset HOME`, `unset -v HOME`, `unset FOO XDG_CONFIG_HOME` | `unset do HOME` / `unset do XDG_CONFIG_HOME` |
| `env` com opção que limpa ou tira variáveis do ambiente, antes do comando que ele chama | `env -i PATH=$PATH git commit`, `env --ignore-environment …`, `env - git commit`, `env -u HOME …`, `env --unset=HOME …`, `env -iu X …` | `env sem o ambiente` |
| Remover ou renomear uma seção da configuração do git, nas duas sintaxes | `git config --global --remove-section core`, `git config --rename-section core x`, `git config remove-section core`, `git config rename-section core x` | `remove ou renomeia seção da configuração do git` |
| Qualquer prefixo aceito de `--no-verify`, a partir de `--no-veri` | `git commit --no-veri`, `--no-verif`, `git push --no-veri` | `--no-verify` |

Com `--no-ver` e prefixos menores, o git recusa a opção por ambiguidade com `--no-verbose` (conferido com o git 2.53.0). Por isso a checagem começa em `--no-veri`.

**Continuam liberados:**
- `echo $HOME`, `cd ~`, `printenv HOME`, `env | grep PATH`, `env FOO=1 make test`;
- `git commit --no-verbose -m x`, `git config --global user.name x`, `git config --list`.

**Continua bloqueada:** a leitura `git config --global --get core.hooksPath`, porque cita `hookspath` (resposta 2a). Para conferir o estado, use `scripts/setup-githooks.sh --check`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Bloqueiam: `unset HOME; git commit -m x`, `unset -v XDG_CONFIG_HOME`, `env -i PATH=$PATH git commit -m x`, `env --ignore-environment git commit -m x`, `env - git commit -m x`, `env -u HOME git commit -m x`, `env --unset=HOME git commit -m x`. | unitário (`scripts/test-protect-main.sh`) |
| CA2 | Bloqueiam: `git config --global --remove-section core`, `git config --global --rename-section core x`, `git config --global remove-section core`, `git config rename-section core x`. | unitário |
| CA3 | Bloqueiam: `git commit --no-veri -m x`, `git commit --no-verif -m x` e `git push --no-veri origin main`. Libera `git commit --no-verbose -m x`. | unitário |
| CA4 | Liberam: `echo $HOME`, `cd ~ && ls`, `printenv HOME`, `env \| grep PATH`, `env FOO=1 make test`, `git config --global user.name x`, `git config --list`. Bloqueia: `git config --global --get core.hooksPath`. | unitário |
| CA5 | Os 62 casos atuais de `scripts/test-protect-main.sh` continuam passando. O comando de 40 KB continua abaixo de 50 ms. | unitário |
| CA6 | Contra o `protect-main.sh` da `main` atual, o script falha pelo menos nos casos `unset HOME`, `env -i`, `--remove-section` e `--no-veri` dos CA1 a CA3. | unitário |
| CA7 | Nas "Consequências" do ADR 0002, há um item com as formas cobertas a partir da #29. O mesmo item diz que outras manipulações de ambiente ou da configuração do git ficam fora do modelo de ameaça (erros e comandos inocentes, não sabotagem). Exemplos de fora: `export -n HOME`, sobrescrever o `~/.gitconfig` com `>` e a ferramenta Write. O `protect-main.sh` continua com menos de 80 linhas, e a `version` do plugin passa a 0.9.1. | manual |

## Fora de escopo
- Outras manipulações de ambiente ou da configuração que não estão na tabela: `export -n HOME`, `declare +x`, sobrescrever `~/.gitconfig` com redirecionamento, `git config --edit`, editar arquivos com as ferramentas Write/Edit. Elas ficam registradas no ADR 0002 como fora do modelo de ameaça (resposta 1a).
- Liberar a leitura de `core.hooksPath` (resposta 2a).
- Os falsos positivos por texto citado, como um corpo de PR ou issue que cite `--no-verify` ou `env -i`. O contorno continua sendo passar o texto por arquivo (`--body-file`).

## Desenho técnico
**Arquivos e módulos:**
- `hooks/protect-main.sh`: troca a checagem `*--no-verify*` por `*--no-veri*` e acrescenta três checagens no mesmo estilo das atuais (`[[ =~ ]]` ou `grep -E` sobre o comando com as linhas continuadas juntas):
  - `unset`, seguido no mesmo trecho de `HOME` ou `XDG_CONFIG_HOME` como palavra inteira;
  - `env` como palavra, seguido de opções (palavras começando com `-`) em que alguma é `-`, `--ignore-environment`, `--unset…` ou uma opção curta com `i` ou `u`;
  - `remove-section` ou `rename-section`, com ou sem `--`.
- `scripts/test-protect-main.sh`: casos dos CA1 a CA4 na parte do CA6 atual, com o rótulo `B29`.
- `docs/adr/0002-protecao-da-main-por-hooks-do-git.md`: o item novo em "Consequências" (CA7).
- `.claude-plugin/plugin.json`: 0.9.0 → 0.9.1.

**Dados:** nenhum.

**Interfaces:** a entrada e a saída do PreToolUse não mudam.

**Decisões:**
- **`env` com `-i`/`-u` bloqueia mesmo quando a variável não é `HOME`** (ex.: `env -u FOO cmd`): saber qual variável `-u` tira, ou se `-i` repõe o `HOME`, exigiria ler os argumentos como o shell. Esse uso é raro nos comandos do Claude. Alternativa descartada: só bloquear `env -u HOME`, o que deixaria `env -i HOME=… GIT_…` e combinações de opções (`-iu`) mais difíceis de pegar.
- **`remove-section`/`rename-section` bloqueiam para qualquer seção:** a checagem não sabe se a seção é `core` sem ler os argumentos, e remover seções do `~/.gitconfig` não faz parte do fluxo normal. Alternativa descartada: exigir `core` no mesmo trecho, que deixaria passar `rename-section core` montado de outra forma.
- **A checagem de `--no-verify` vira `--no-veri`:** cobre todos os prefixos que o git aceita, sem pegar `--no-verbose`. Alternativa descartada: listar os prefixos um a um.

**Fontes da documentação:**
- git 2.53.0: `git config --help` documenta `remove-section`/`rename-section` e as formas antigas `--remove-section`/`--rename-section`. A ambiguidade de `--no-ver` com `--no-verbose` e a aceitação de `--no-veri` em `commit` e `push` foram conferidas executando o git local.
- GNU coreutils `env` (`-i`, `-`, `-u`, `--unset`, `--ignore-environment`): conhecimento do modelo, não verificada. Será conferida com `env --help` na implementação.

**ADR:** atualiza o `docs/adr/0002-protecao-da-main-por-hooks-do-git.md` (item em "Consequências"), sem ADR novo.

## Testes
- **Casos novos:** `scripts/test-protect-main.sh` ganha os casos dos CA1 a CA4 com `check deny|allow`, e o script inteiro roda com `bash scripts/test-protect-main.sh` (CA5).
- **Antes e depois (CA6):** rodar o script contra o hook da `main` (`git show origin/main:hooks/protect-main.sh > <scratchpad>/old.sh; bash scripts/test-protect-main.sh <scratchpad>/old.sh`) e conferir que os casos novos falham.
- **Corpos de PR e issue:** o corpo do PR desta issue vai citar os comandos bloqueados. Ele precisa ser passado por arquivo, o que confirma o falso positivo aceito.

## Riscos e dúvidas
- **Falsos positivos de `env`:** `env -u`/`env -i` em scripts de build do usuário rodados pelo Claude passam a ser bloqueados. O contorno é rodar no terminal.
- **Palavras parecidas:** a checagem de `unset` precisa pegar `HOME` como palavra inteira, para não bloquear `unset HOMEBREW_X`.

## Histórico
- 2026-10-29: criação.
- 2026-10-29: aprovada pelo usuário.
