# Migrar para o AGENTS.md

O projeto tem as regras da fábrica só no `CLAUDE.md`, ou tem o `CLAUDE.md` e o `AGENTS.md` sem ligação entre eles.

**Por que migrar:** o OpenCode e o Antigravity leem o `AGENTS.md` e não leem o `CLAUDE.md`. Já o Claude Code, quando o projeto tem os dois arquivos, lê só o `CLAUDE.md`, a menos que ele importe o `AGENTS.md` com `@AGENTS.md`. No formato da fábrica, o `AGENTS.md` é a fonte das regras e o `CLAUDE.md` só o importa, com o que é do Claude Code. As etapas leem as regras no `AGENTS.md` e, enquanto o projeto não migra, continuam lendo o `CLAUDE.md`.

A migração entra num PR `chore` próprio, sem issue, como qualquer mudança: branch a partir da `main` atualizada (ex.: `chore/agents-md`), commit e merge com squash.

## Projeto só com o CLAUDE.md
1. **Mova as regras:** renomeie o arquivo, para o git guardar o histórico: `git mv CLAUDE.md AGENTS.md`.
2. **Ajuste o cabeçalho:** no topo do `AGENTS.md`, troque o título e a frase inicial pelos do [`templates/AGENTS.md`](../../templates/AGENTS.md). As seções de regras e a seção "Projeto" ficam como estão.
3. **Crie o `CLAUDE.md`:** copie o [`templates/CLAUDE.md`](../../templates/CLAUDE.md) para a raiz. Ele começa com `@AGENTS.md` e tem só a seção `## Claude Code`. Se o projeto tinha alguma instrução que só vale para o Claude Code, ela vai para essa seção.

## Projeto com os dois arquivos, sem o import
É o caso do Next.js, que cria um `AGENTS.md` com as regras dele, enquanto as regras da fábrica ficam no `CLAUDE.md`.
1. **Junte as regras:** leve as seções do `CLAUDE.md` (do `## Fluxo da fábrica` até o fim da seção "Projeto") para o `AGENTS.md`, depois do bloco do Next. Ponha antes do bloco o título e a frase inicial do [`templates/AGENTS.md`](../../templates/AGENTS.md).
2. **Troque o `CLAUDE.md`:** substitua o conteúdo dele pelo do [`templates/CLAUDE.md`](../../templates/CLAUDE.md), mantendo na seção `## Claude Code` o que for só do Claude Code.

## O bloco do Next
O `next dev` mantém no `AGENTS.md` um bloco entre `<!-- BEGIN:nextjs-agent-rules -->` e `<!-- END:nextjs-agent-rules -->`. A cada execução, ele reescreve só o que está entre os dois marcadores e, se o bloco não existe, acrescenta-o no fim do arquivo.
- **Regras da fábrica fora do bloco:** antes ou depois dele, nunca entre os marcadores, onde seriam apagadas.
- **Marcadores intactos:** não apague nem edite as linhas `BEGIN` e `END`. Sem elas, o `next dev` acrescenta um bloco novo no fim e o arquivo fica com as regras do Next duplicadas.

## Conferir
- O `CLAUDE.md` começa com `@AGENTS.md`.
- Nenhuma regra de git, idioma ou segredos ficou no `CLAUDE.md`.
- No Claude Code, o `/memory` lista o `AGENTS.md` entre os arquivos carregados. Fora da sessão interativa, pergunte por uma regra que só está no `AGENTS.md`: `claude -p "Qual é o padrão de nome de branch deste projeto?"`.
- Num projeto Next, rode o `next dev` uma vez e confira com `git diff` que só o bloco do Next mudou, se mudou.
