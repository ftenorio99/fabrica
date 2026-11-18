# SPEC-190: docs: teste A da worktree por issue (#182)

**Issue:** #190 · **PRD:** — · **Classe:** documentacao · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-18

## Contexto
Esta é uma issue de teste do CA15 e do CA16 da #182, que introduz uma worktree por issue (`<clone>/.worktrees/<nº>`) em vez de trocar a branch do clone principal. A entrega real é pequena: um guia curto que diz como conferir esse comportamento. A issue será fechada ao fim do teste e não precisa ir para a `main`.

## Objetivo
`docs/teste-182-A.md` existe, descreve como conferir que uma worktree por issue não muda a branch do clone principal, e está listado na tabela de guias de `docs/README.md`.

## Comportamento esperado
- Quem abre `docs/README.md` vê, na tabela "Guias", uma linha que leva a `teste-182-A.md`.
- O arquivo tem três seções, nesta ordem: `## Objetivo`, `## Passos`, `## Resultado esperado`, cada uma com 3 a 5 linhas de texto (linhas não vazias, sem contar o título da seção).
- Os passos descrevem conferir a branch do clone principal (`git branch --show-current`) antes e depois de rodar uma etapa de agente, e listar as worktrees (`git worktree list`) para ver a da issue em `.worktrees/<nº>`.
- O resultado esperado diz que a branch do clone principal é a mesma antes e depois, e que a branch da issue está só na worktree dela.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `docs/teste-182-A.md` existe, em português, com as seções `## Objetivo`, `## Passos` e `## Resultado esperado`, nesta ordem, e cada uma tem de 3 a 5 linhas não vazias (limites inclusivos: 3 e 5 valem; 2 ou 6 reprovam) | manual — ler o arquivo e contar as linhas de cada seção |
| CA2 | O conteúdo descreve como conferir que a worktree da issue não muda a branch do clone principal, citando `git branch --show-current` no clone principal e `git worktree list` | manual — ler o arquivo |
| CA3 | A tabela "Guias" de `docs/README.md` ganha uma linha, no fim, com o link `[...](teste-182-A.md)` e uma descrição da situação; o link abre o arquivo | manual — abrir `docs/README.md` e seguir o link |
| CA4 | Nenhum outro arquivo muda no PR além de `docs/teste-182-A.md`, `docs/README.md` e esta spec | manual — `git diff --stat origin/main...HEAD` lista só esses três arquivos |

## Fora de escopo
- Qualquer mudança em scripts, skills, hooks, `agents/`, `templates/` ou no `.claude-plugin/plugin.json` (sem subir a versão).
- Mover o arquivo para `docs/guias/`: a issue pede `docs/teste-182-A.md`.

## Desenho técnico
**Arquivos e módulos:**
- criar `docs/teste-182-A.md`;
- alterar `docs/README.md`, só a tabela "Guias", acrescentando uma linha depois da do Antigravity.

**Dados:** nenhum.

**Interfaces:** nenhuma.

**Decisões:**
- O arquivo fica em `docs/`, não em `docs/guias/`, e o link na tabela é `teste-182-A.md` — é o caminho que a issue pede. Alternativa descartada: `docs/guias/teste-182-A.md`, que seguiria o padrão dos outros guias, mas muda o que a issue especifica.
- A linha nova entra no fim da tabela "Guias" — não altera a ordem das linhas existentes. Alternativa descartada: ordem alfabética, que mexeria em linhas fora do escopo.

**Fontes da documentação:**
- nenhuma biblioteca. O desenho não usa o `gh`; os comandos citados são do `git` (`git branch --show-current`, `git worktree list`, `git diff --stat`), de uso corrente.

**ADR:** nenhum.

## Testes
Sem teste automatizado: os quatro CAs são conferidos lendo os arquivos e com `git diff --stat origin/main...HEAD`.

## Passos de produção
nenhum

## Riscos e dúvidas
- Nenhum relevante. A issue é de teste da #182 e será fechada ao fim do teste.

## Histórico
- 2026-11-18: criação, saindo do atalho a pedido do usuário (comentário na issue). Ponto de partida: a spec curta da triagem.
