# ADR 0020: Screenshots das telas numa branch órfã do projeto, publicados pela etapa de agente

**Status:** aceito · **Data:** 2026-11-24 · **Origem:** issue #129

## Contexto
A F7 do [PRD](../prd.md) pede que a implementação anexe ao PR screenshots reais das telas, no celular e no computador, para o usuário aprovar. O GitHub não tem API para subir imagem num comentário ou no corpo de um PR: o upload só existe pelo navegador. A imagem precisa ficar em algum lugar que o PR mostre, inclusive num repositório privado, sem serviço externo e sem secret novo.

Quem gera as imagens também precisa de uma regra: a etapa `implementar` roda o Playwright no ambiente dela ([ADR 0011](0011-verificacao-de-integracao-na-etapa.md)), mas esse ambiente pode não rodá-lo (assinatura de ambiente), e o CI do PR já roda o Playwright num runner descartável ([ADR 0019](0019-ci-do-pr-pelo-modelo-da-fabrica.md)).

## Decisão
- **Geração pelo `Makefile`:** o projeto com interface tem o alvo `make screenshots`, que roda o Playwright e grava em `screenshots/` um PNG por tela, estado e dispositivo, com o nome `<tela>--<estado>--<celular|computador>.png`. Como o `make e2e`, o alvo é o contrato entre a fábrica e o projeto.
- **Hospedagem:** as imagens vão para a branch órfã `fabrica-telas` do próprio repositório, na pasta `issue-<nº>/<sha curto do head>/`. O corpo do PR as mostra por links `https://github.com/<dono>/<repo>/raw/<sha do commit da fabrica-telas>/<caminho>`, que o GitHub exibe a quem tem acesso ao repositório.
- **Publicação pela etapa de agente:** o script `scripts/publish-screenshots.sh` da fábrica grava e envia a branch e imprime a tabela em markdown. O `/fabrica:revisar` o chama antes de abrir ou atualizar o PR.
- **CI como reserva:** quando o ambiente da etapa não roda o Playwright, o job `e2e` do modelo do CI roda o `make screenshots` e guarda a pasta como o artefato `telas`. O `/fabrica:revisar` baixa o artefato do run do head e publica do mesmo jeito. O CI continua só com `contents: read`.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Só o artefato do Actions | O PR não mostra a imagem: o usuário baixa um zip para ver cada tela. |
| Imagens commitadas na branch da issue | Com o squash, os PNGs entram na `main` e ficam para sempre no histórico do projeto. |
| CI publicando direto na `fabrica-telas` e comentando no PR | O CI do projeto passaria a ter `contents: write` e `pull-requests: write`, e não roda com permissão de escrita num PR de fork. |
| Serviço externo de imagens (Imgur, bucket) | Conta e secret novos, e a tela de um projeto privado ficaria pública. |
| Release ou gist com as imagens | Release polui a lista de versões do projeto; gist não é privado de verdade e pede outro token. |

## Consequências
- Todo projeto com interface ganha o alvo `make screenshots` na primeira issue com interface, escrito pelo `/fabrica:implementar`.
- A branch `fabrica-telas` cresce a cada rodada de publicação. A limpeza das pastas de issues fechadas fica para depois.
- O link com o SHA do commit não muda quando a branch avança, então um PR antigo continua mostrando as imagens da rodada dele.
- Um projeto que já copiou o `ci.yml` não ganha a reserva do CI sozinho: o guia diz que passos acrescentar.
