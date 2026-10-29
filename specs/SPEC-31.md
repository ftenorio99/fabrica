# SPEC-31: Reduz os falsos positivos do protect-main ao núcleo do ADR 0002

**Issue:** #31 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-10-29

## Contexto
Desde a #27 (ADR 0002), quem recusa commit e push na `main` são os hooks globais do git. O `hooks/protect-main.sh` é um PreToolUse que só impede o Claude de desligar esses hooks, com checagens de texto sobre o comando inteiro. A #29 acrescentou checagens contra `unset`, `env` e remoção de seção do `git config`.

No kairo, durante a issue #8, essas checagens bloquearam dois comandos legítimos:
- um `env -u DATABASE_URL … pnpm build`;
- um `gh pr create` cujo corpo, montado com heredoc no Bash, citava esse comando.

O ADR 0002 diz que o modelo de ameaça cobre erros e comandos inocentes, não sabotagem. As checagens da #29 miram formas que um comando inocente não usa para fazer commit.

Na triagem, o usuário escolheu:
1. **Enxugar o hook ao núcleo do ADR 0002.**
2. **Mudar as skills nesta mesma issue,** para publicarem corpos com `--body-file` a partir de arquivo escrito com a ferramenta Write.

## Objetivo
O `protect-main.sh` volta a bloquear só o núcleo do ADR 0002, e as skills da fábrica deixam de passar corpos de issue, comentário e PR pelo texto de um comando Bash.

## Comportamento esperado
**O hook continua bloqueando**, com as mesmas mensagens de hoje:

| Checagem | Exemplos |
|---|---|
| `--no-verify` e prefixos a partir de `--no-veri` | `git commit --no-verify`, `git push --no-veri` |
| `commit` seguido de opção curta com `n` | `git commit -nm x`, `git commit -an` |
| `hookspath` em qualquer caixa | `git config --global core.hooksPath x`, `git -c core.hooksPath=x commit` |
| `GIT_CONFIG` | `GIT_CONFIG_GLOBAL=/dev/null git commit` |
| Atribuição a `HOME=` ou `XDG_CONFIG_HOME=` | `HOME=/tmp git commit -m x` |
| Pasta dos hooks | `rm -rf ~/.config/fabrica/githooks` |
| `commit`/`push` com os hooks ausentes | qualquer comando que cite `commit` ou `push` |

**O hook deixa de bloquear** as checagens trazidas pela #29:
- `unset` de `HOME`/`XDG_CONFIG_HOME`;
- `env` com `-i`, `-`, `-u`, `--unset`, `--ignore-environment`, `-S` e abreviações;
- `remove-section`/`rename-section` e `--rem`/`--ren` no `git config`.

A checagem por prefixo do `--no-verify`, também da #29, fica: é o erro plausível de um agente que tenta passar por um hook que o barrou.

**As skills publicam por arquivo.** Toda skill que publica corpo no GitHub segue o mesmo caminho:
- escreve o corpo num arquivo na pasta temporária da sessão (scratchpad), com a ferramenta Write;
- publica com `--body-file <arquivo>`, seja com `gh issue create`, `gh issue comment`, `gh pr create`, `gh pr edit` ou `gh pr comment`;
- nunca monta o corpo com heredoc, `echo`, `--body "<texto>"` ou stdin (`--body-file -`).

As skills que publicam são `triagem`, `spec`, `implementar`, `revisar` e `backlog`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Liberam: `env -u DATABASE_URL -u BETTER_AUTH_SECRET pnpm build`, `env -i PATH=$PATH make test`, `unset HOME`, `git config --global --remove-section alias` e `npx tsc -p tsconfig.json --removeComments`. | unitário (`scripts/test-protect-main.sh`) |
| CA2 | Continuam bloqueados: `git commit --no-verify -m x`, `git commit --no-veri -m x`, `git commit -nm x`, `git config --global core.hooksPath /tmp/x`, `GIT_CONFIG_GLOBAL=/dev/null git commit -m x`, `HOME=/tmp git commit -m x` e `rm -rf ~/.config/fabrica/githooks`. O teste de hooks ausentes também continua passando. | unitário |
| CA3 | `bash scripts/test-protect-main.sh` passa sem falhas. Os casos de bloqueio do grupo B29 para `unset`, `env` e seção do `git config` viram casos de liberação; os de `--no-veri` e `--get core.hooksPath` continuam como bloqueio. | unitário |
| CA4 | Em `skills/{triagem,spec,implementar,revisar,backlog}/SKILL.md`: cada uma tem, nas regras, a instrução de publicar por arquivo escrito com a Write e `--body-file <arquivo>`. Nenhuma cita `--body-file -`. `grep -rn -- '--body-file -' skills` não acha nada. | manual (grep) |
| CA5 | O ADR 0002 troca o item da #29 em "Consequências" por um que registra a volta ao núcleo e o motivo (falsos positivos no kairo, modelo de ameaça). O comentário de cabeçalho do `protect-main.sh` cita o contorno por `--body-file`. `plugin.json` vai a 0.9.2. | manual |

## Fora de escopo
- Mudar os hooks do git (`githooks/`) ou o `scripts/setup-githooks.sh`.
- Liberar a leitura `git config --get core.hooksPath` (resposta 2a da #29 continua valendo).
- Trocar a checagem de texto por análise do shell.
- Mudar a skill `prd` ou `status`, que não publicam corpos no GitHub.

## Desenho técnico
**Arquivos e módulos:**
- `hooks/protect-main.sh`: remover `unset_re`, `env_re`, a checagem de `(remove|rename)-section` e o `grep` de `--re[mn]`, com seus comentários. O `flat` continua, usado pelo `commit -n`. No cabeçalho, trocar "basta reescrever o texto" pelo contorno de escrever o corpo num arquivo e usar `--body-file`.
- `scripts/test-protect-main.sh`: no grupo B29, mover para o laço de liberação os casos de `unset`, `env` e seção do `git config`. Acrescentar os casos de CA1 e CA2 que ainda não existem.
- `skills/triagem/SKILL.md`: trocar `--body-file -` por `--body-file <arquivo>`.
- `skills/{triagem,spec,implementar,revisar,backlog}/SKILL.md`: acrescentar nas "Regras" o mesmo item:
  > Publique todo corpo de issue, comentário ou PR a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- `docs/adr/0002-protecao-da-main-por-hooks-do-git.md`: reescrever o item da #29 em "Consequências".
- `.claude-plugin/plugin.json`: `0.9.2`.

**Dados:** nenhum.

**Interfaces:** nenhuma nova. A saída do hook (JSON de `deny`) e as mensagens não mudam.

**Decisões:**
- **Manter os prefixos de `--no-verify`** — é a forma que um agente tenta quando um hook o barra. Alternativa descartada: voltar a só `--no-verify` inteiro, que reabre um erro plausível.
- **Mesma regra repetida em cada skill**, em vez de um arquivo comum referenciado — cada skill é lida sozinha pelo Claude, e uma linha repetida é mais confiável que um link. Alternativa descartada: um `skills/comum.md`, que pode não ser lido.
- **Pasta temporária da sessão**, em vez de um arquivo no repositório — evita sujar o `git status` do projeto. Alternativa descartada: `.fabrica/` no repositório.

**Fontes da documentação:** nenhuma biblioteca envolvida.

**ADR:** `docs/adr/0002-protecao-da-main-por-hooks-do-git.md` (aceito; só o item de "Consequências" muda).

## Testes
- `bash scripts/test-protect-main.sh` cobre CA1 a CA3. O repositório não tem `Makefile`; esse é o comando de teste.
- Verificação manual de CA4: `grep -rn -- '--body-file -' skills` sem resultado e leitura das cinco "Regras".
- Verificação manual de CA1 no hook instalado: num `claude -p --plugin-dir ~/projetos/fabrica`, rodar `env -u FOO true` e conferir que passa.

## Riscos e dúvidas
- **Volta das brechas da #29:** `env -i git commit` e `unset HOME` voltam a passar pelo PreToolUse. O ADR 0002 já trata isso como sabotagem, fora do modelo de ameaça. Os hooks do git continuam valendo para qualquer commit feito com o ambiente normal.
- **Pasta temporária fora do Claude Code:** no GitHub Actions (Fase 1) não há scratchpad. A regra diz "pasta temporária da sessão"; no runner, vale `$RUNNER_TEMP`, a ser tratado quando a Fase 1 chegar.

## Histórico
- 2026-10-29: criação.
- 2026-10-29: aprovada.
