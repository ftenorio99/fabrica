# SPEC-48: Corrigir a busca de backlog do /fabrica:status, recusada como sintaxe inválida

**Issue:** #48 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-04

## Contexto
O passo 1 do `skills/status/SKILL.md` coleta as issues de backlog com `gh search issues ... -- "fabrica:backlog in:body" -label:agente`. O `gh` monta a consulta como `fabrica:"backlog in:body"`, e o GitHub lê o `fabrica:` como um qualificador desconhecido. A busca falha com "The search query contains invalid syntax", e a seção "Backlog" do `/fabrica:status` fica vazia ou depende de um contorno improvisado. A triagem testou uma consulta alternativa e conferiu o resultado contra a lista completa do `kairo`.

## Objetivo
A coleta de backlog do `/fabrica:status` roda sem erro e traz as mesmas issues de backlog que uma leitura completa das issues abertas traria.

## Comportamento esperado
- O item "Backlog" do passo 1 passa a usar:
  `gh search issues "backlog" --owner <dono> --state open --match body --json repository,number,title,body,url --limit 100 -- -label:agente`
- Com filtro de repositório, `--repo <dono>/<repositório>` entra no lugar de `--owner`, como hoje.
- O resto do item não muda: a skill fica só com as issues cujo corpo tem o marcador `<!-- fabrica:backlog item=<n> -->`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O item "Backlog" do passo 1 de `skills/status/SKILL.md` usa a consulta de "Comportamento esperado" e não contém mais `"fabrica:backlog in:body"`. | manual: leitura e `grep -n "fabrica:backlog in:body" skills/` sem resultado |
| CA2 | A consulta nova roda sem erro com `--owner ftenorio99`. Filtrada pelo marcador, ela traz as mesmas issues do `kairo` que `gh issue list -R ftenorio99/kairo --state open --limit 200` filtrado pelo marcador e sem `agente`. | manual: rodar os dois comandos e comparar os números |
| CA3 | A consulta nova roda sem erro com `--repo ftenorio99/kairo` no lugar de `--owner`, com o mesmo resultado do CA2. | manual: rodar o comando |
| CA4 | `.claude-plugin/plugin.json` sobe para `0.11.3`. | manual (leitura) |

## Fora de escopo
- As outras consultas do `/fabrica:status` (issues com `agente` e lições), que funcionam.
- Paginação além de 100 resultados.
- Mudar o formato do marcador de backlog ou a skill `/fabrica:backlog`.

## Desenho técnico
**Arquivos e módulos:**
- `skills/status/SKILL.md`: item "Backlog" do passo 1.
- `.claude-plugin/plugin.json`: `version`.

**Dados:** nenhum.

**Interfaces:** nenhuma nova. O marcador de backlog continua o mesmo.

**Decisões:**
- **Buscar o termo `backlog` no corpo (`--match body`) e filtrar pelo marcador depois:** o termo sem dois-pontos não vira qualificador, e o filtro que já existe descarta as issues que só citam a palavra. Alternativa descartada: trocar a busca por um `gh issue list` em cada repositório, que exige uma chamada por repositório. A busca resolve tudo numa chamada só, que é o padrão das outras consultas da skill.
- **Manter `-label:agente` depois do `--`:** a triagem confirmou que esse qualificador funciona assim. A forma `--label` do `gh` só inclui labels, não as exclui.

**Fontes da documentação:**
- GitHub CLI (`gh search issues`, flags `--match`, `--owner`, `--repo` e `--`): versão instalada, conferida na execução da triagem. Nenhuma biblioteca nova.

**ADR:** nenhum.

## Testes
O repositório não tem `make test`: a mudança é texto de skill. A evidência são os comandos do CA1 ao CA3, rodados de verdade, e a leitura do CA4.

## Riscos e dúvidas
- **Limite de 100 resultados:** o termo `backlog` também acerta issues sem o marcador. Se um dono tiver mais de 100 issues abertas citando a palavra, parte do backlog pode ficar de fora. Hoje são 7 resultados, então o risco é aceitável. A paginação está fora de escopo.
- **Indexação da busca:** o GitHub pode demorar a indexar uma issue recém-criada. A consulta antiga já tinha esse limite.

## Histórico
- 2026-11-04: criação.
