# ADR 0002: Proteção da main por hooks do git, não pela análise do comando

**Status:** aceito · **Data:** 2026-10-29 · **Origem:** issue #27

## Contexto
A regra de que a `main` nunca recebe commit ou push direto é protegida pelo `hooks/protect-main.sh`, um hook PreToolUse do Claude Code. Ele lê o texto do comando Bash e tenta prever se o `git commit` ou o `git push` vai cair na `main`.

Para isso, o hook reproduz partes do shell: aspas, heredocs, `$(...)`, `bash -c`, `eval`, variáveis e subshells. As #18, #22 e #24 corrigiram formas que escapavam ou que bloqueavam por engano, e a #26 lista mais quatro. O hook chegou a 493 linhas, e cada correção abre espaço para a próxima.

A proteção no próprio GitHub (rulesets e branch protection) resolveria o push, mas exige GitHub Pro nos repositórios privados.

## Decisão
A `main` é protegida pelo próprio git, com hooks globais instalados uma vez por máquina numa pasta estável do usuário, configurada em `core.hooksPath`:
- o `pre-commit` e o `pre-merge-commit` recusam commit na `main`/`master`, salvo o commit inicial;
- o `pre-push` recusa enviar para a `main`/`master` remota que já existe.

A proteção vale para todos os commits e pushes da máquina, inclusive os feitos à mão. No terminal, o usuário passa por cima com `--no-verify`.

O PreToolUse do Claude Code fica só com checagens de texto contra o que desligaria esses hooks:
- `--no-verify` e `commit -n`;
- `core.hooksPath`, `GIT_CONFIG_*`, `HOME=` e `XDG_CONFIG_HOME=`;
- o caminho da pasta dos hooks.

Ele também bloqueia `commit`/`push` enquanto os hooks não estiverem instalados.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Continuar ampliando o leitor de shell no PreToolUse | Não fecha: o shell tem formas demais de montar um comando, e cada correção aumenta o hook e o risco de falso positivo. |
| Proteção da `main` no GitHub (rulesets) | Exige GitHub Pro nos repositórios privados. Fica como camada extra se o plano mudar. |
| Hooks em `.git/hooks` de cada repositório, instalados pelo setup | Precisa ser repetido em cada clone, e um clone novo nasce desprotegido. O global cobre todos de uma vez. |
| Valer só para comandos do Claude Code (variável `CLAUDECODE`) | O usuário escolheu, na triagem da #27, que a regra vale para todos, como diz o `CLAUDE.md` global. |

## Consequências
- Qualquer forma de chamar o git passa pela mesma verificação, porque a decisão usa a branch e as refs reais.
- O `core.hooksPath` global faz o git ignorar o `.git/hooks` de cada repositório. Os hooks da fábrica encadeiam os do repositório para não quebrá-los.
- Repositórios com `core.hooksPath` local (husky, lefthook) não passam pelos hooks da fábrica. Se surgir um projeto assim, a integração vira uma issue.
- Commits na `main` local por `cherry-pick`, `rebase`, fast-forward ou `reset` não passam pelo `pre-commit`, mas o `pre-push` impede que cheguem ao GitHub.
- Cada máquina precisa rodar `/fabrica:setup` uma vez. Até lá, o PreToolUse bloqueia `commit`/`push`.
- Na Fase 1 (GitHub Actions), o runner também precisará instalar os hooks antes de rodar os agentes.
