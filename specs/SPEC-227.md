# SPEC-227: docs: teste CA2 da #129 sem interface

**Issue:** #227 · **PRD:** — · **Fonte do escopo:** — · **Classe:** documentacao · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-26

## Contexto
A issue é um teste do CA2 da SPEC-129, feito sem interface. Ela não muda comportamento do plugin: acrescenta uma nota curta em duas páginas do manual, `docs/fluxo.md` e `docs/comandos.md`, para explicar a ordem das seções de cada uma. O manual é a referência de uso da fábrica ([docs/README.md](../docs/README.md)), e as duas páginas são as que mais se lêem antes de rodar uma etapa.

## Objetivo
`docs/fluxo.md` e `docs/comandos.md` trazem, logo após o título, uma nota curta que explica a ordem das seções de cada arquivo.

## Comportamento esperado
- Em `docs/fluxo.md`, logo após `# Fluxo` e antes do parágrafo de abertura, há uma nota de até três linhas. Ela diz a ordem das seções do arquivo e o que cada grupo cobre (o ciclo da issue, as regras de apoio, o planejamento).
- Em `docs/comandos.md`, logo após `# Comandos` e antes do parágrafo de abertura, há uma nota de até três linhas com a mesma função: diz a ordem das seções (uma por comando) e por que os comandos que só leem ficam depois dos que mudam algo.
- A nota está em português, no formato de parágrafo que começa com **Ordem das seções:**.
- O restante dos dois arquivos não muda: nenhuma linha existente é removida ou reescrita.
- A nota não repete regras, tabelas nem a máquina de estados das skills: ela só explica a ordem das seções do próprio arquivo, como manda o `AGENTS.md` do projeto para o manual.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Cada um dos dois arquivos tem, logo após o título e antes do parágrafo de abertura, uma nota de até três linhas que começa com **Ordem das seções:** e explica a ordem das seções | manual — leitura dos dois arquivos |
| CA2 | O restante do conteúdo dos dois arquivos fica igual: o diff traz só linhas acrescentadas, sem nenhuma linha removida ou alterada fora da nota | manual — `git diff origin/main...HEAD --numstat` mostra zero linhas removidas nos dois arquivos |

## Fora de escopo
- Mudar outras seções de `docs/fluxo.md` e `docs/comandos.md`, inclusive a ordem delas.
- Alterar as skills, os scripts, os testes ou o `README.md` de `docs/`.
- Criar spec para outra issue, ou mexer em outros documentos de `docs/`.
- Revisar o texto do manual além da nota.

## Desenho técnico
**Arquivos e módulos:**
- `docs/fluxo.md`: acrescenta a nota logo após a linha `# Fluxo` (linha 1).
- `docs/comandos.md`: acrescenta a nota logo após a linha `# Comandos` (linha 1).
- `specs/SPEC-227.md`: esta spec.

**Dados:** nenhum.

**Interfaces:** nenhuma. É texto em Markdown; nenhuma skill, script ou comando muda.

**Decisões:**
- Lugar da nota: logo depois do título de cada arquivo, antes do parágrafo de abertura, porque é ali que quem abre o arquivo lê primeiro (recomendação da triagem). Alternativa descartada: no fim de cada arquivo, em que o leitor só a veria depois de ler tudo e não saberia a ordem antes de começar.
- Conteúdo da nota: explica a ordem das seções em até três linhas e não repete regras, para não criar uma segunda fonte que possa divergir das skills. Alternativa descartada: uma tabela de seções no topo, que duplicaria o índice que o próprio arquivo já tem pelos títulos.

**Fontes da documentação:**
- Nenhuma biblioteca nem flag de `gh` é citada: a mudança é só texto em `docs/`.

**ADR:** nenhum. A mudança não afeta mais do que esta issue.

## Testes
Nenhum teste automatizado cobre o texto de `docs/`. A verificação é manual:
- CA1: ler o início de `docs/fluxo.md` e `docs/comandos.md` e confirmar que a nota vem logo após o título, tem até três linhas e explica a ordem.
- CA2: `git diff origin/main...HEAD --numstat` nos dois arquivos, conferindo que não há linha removida.

## Passos de produção
nenhum

## Riscos e dúvidas
- nenhum relevante

## Histórico
- 2026-11-26: criação a partir da spec curta do atalho da triagem; a spec curta não é editada.
