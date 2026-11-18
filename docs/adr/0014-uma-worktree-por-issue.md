# ADR 0014: Uma worktree por issue

**Status:** aceito · **Data:** 2026-11-18 · **Origem:** issue #182

## Contexto
As etapas `spec` e `implementar` trocavam a branch do próprio clone com `git switch`. Com duas sessões no mesmo clone, uma trocava a branch da outra: entre 2026-11-17 e 2026-11-18 isso aconteceu três vezes no repositório da fábrica, com um commit indo para a branch errada. Rodar várias issues ao mesmo tempo, e depois um orquestrador (#16, #99), exige isolamento por issue. A solução precisa funcionar no Claude Code, no OpenCode, no `claude -p` do `/fabrica:avancar` e dentro da VM do `sbx` (ADR 0010).

## Decisão
- Cada issue com branch trabalha na worktree `<clone>/.worktrees/<nº>`, ignorada pelo `.git/info/exclude` do clone e criada com caminhos relativos. O clone principal nunca troca de branch por causa de uma etapa.
- O `scripts/issue-worktree.sh` cria ou reusa (`ensure`), remove as de PR fechado (`clean`) e lista (`list`). A primeira etapa que precisa da branch cria; as seguintes reusam.
- A remoção roda no começo das etapas e do `/fabrica:avancar`, porque o merge é do usuário e acontece fora da fábrica.
- Arquivos fora do git entram na worktree pelo `.worktreeinclude`, o mesmo formato do Claude Code.
- No máximo 3 worktrees de issue por clone.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| `claude --worktree` nativo | Branch `worktree-<nome>` fora do padrão da fábrica, remoção ao fim da sessão (a worktree precisa durar da spec ao merge) e ausente no OpenCode e no Antigravity. |
| Worktree em `../<repo>-<nº>` | Fica fora da pasta montada na VM do `sbx` e fora da pasta de trabalho da sessão. |
| Uma VM do `sbx` por issue | Multiplica VMs e políticas de rede; os caminhos relativos resolvem com a VM do projeto. |
| `/fabrica:limpar` separado | Depende de o usuário lembrar de rodar; a limpeza automática nas etapas não. |
| Uma sessão aberta por issue, na worktree | Não serve ao `/fabrica:avancar`, que roda as etapas sem o usuário abrir sessão. |

## Consequências
- Duas sessões ou dois subagentes em issues diferentes não mexem na branch um do outro, o que libera o orquestrador.
- Toda etapa que mexe na branch opera por caminho (`cd <wt> && …`, caminhos absolutos), e não pelo diretório da sessão.
- A worktree nova não tem dependências instaladas nem os arquivos fora do git que o `.worktreeinclude` não lista.
- Uma branch em uso no clone principal impede criar a worktree da issue; o usuário volta o clone para a `main` uma vez.
