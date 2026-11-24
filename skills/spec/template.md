# SPEC-<nº>: <título da issue>

**Issue:** #<nº> · **PRD:** <F1, F2…> · **Classe:** <da triagem> · **Tamanho:** <da triagem>
**Status:** rascunho | aprovada · **Atualizada em:** <AAAA-MM-DD>

## Contexto
<Por que esta issue existe e onde ela entra no produto. Duas a quatro frases, citando o PRD.>

## Objetivo
<Uma frase: o que passa a ser verdade quando a issue terminar.>

## Comportamento esperado
<O que o usuário (ou o outro sistema) faz e o que acontece. Use passos curtos ou uma tabela de situações. Inclua os casos de erro e os casos-limite relevantes.>

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | <comportamento observável> | unitário / e2e / manual / depois do merge — <motivo> |
| CA2 | <...> | <...> |

<!-- Opcional: só numa spec com CA de ponta a ponta, e só se algum caso adversarial da lista não se aplica ao fluxo. Sem uso, apague esta linha e a de baixo. -->
**Casos adversariais não aplicáveis:** <caso> — <motivo>

## Fora de escopo
- <O que parece fazer parte, mas fica para outra issue.>

## Desenho técnico
**Arquivos e módulos:** <o que será criado ou alterado, com caminhos reais>

**Dados:** <tabelas, colunas e migrações, se houver>

**Interfaces:** <rotas, endpoints, componentes, funções públicas, com entradas e saídas>

**Decisões:**
- <decisão> — <justificativa em uma frase>. Alternativa descartada: <qual e por quê>.

**Fontes da documentação:**
- <biblioteca> <versão> — <caminho da doc local | ID do Context7 | não verificada>. <"versão não confirmada", se for o caso>
- gh <versão de `gh --version`> — <comandos de ajuda consultados, ex.: `gh search issues --help`>

**ADR:** <docs/adr/NNNN-titulo.md, ou "nenhum">

## Testes
<Como cada critério será testado: quais testes unitários e ponta a ponta, e o que cada um confere. Comandos: `make test`, `make e2e`.>

## Passos de produção
<O que precisa rodar em produção (migração, seed, troca de chave, ajuste de dado) para esta issue valer lá, um por linha, como item para o runbook executado pelo usuário. Nenhum CA depende deles. Sem passo de produção: "nenhum".>

## Riscos e dúvidas
- <O que pode dar errado na implementação, ou "nenhum relevante".>

## Histórico
- <AAAA-MM-DD>: criação.
