# ADR 0009: Aprovação visual sem ferramenta de design no fluxo

**Status:** aceito · **Data:** 2026-11-10 · **Origem:** issue #45

## Contexto
A F7 do PRD pede aprovação visual: cada projeto com interface tem um design system versionado, e o usuário aprova telas reais. A tentativa de usar o Stitch por MCP (#42) foi abandonada: `edit_screens` e `generate_screen_from_text` respondiam sucesso sem gravar as telas. O pen.dev tem o mesmo risco, e o MCP dele só funciona com o app desktop aberto, sem CI nem dispatcher.

O Impeccable (Apache-2.0) tem um detector determinístico de vícios de interface gerada por IA. No piloto no kairo (30/10, versão 4.8.0), ele só achou algo nas páginas renderizadas, deu falsos positivos e contradisse as fontes do design system de então. Os hooks do plugin dele rodam o binário fora do sandbox, mesmo com comandos negados.

## Decisão
- **Sem ferramenta de design no fluxo:** nem Stitch, nem Figma, nem pen.dev. O usuário pode usá-las à mão e anexar screenshots à issue como referência.
- **`docs/design.md` como fonte do visual:** cabeçalho YAML com os tokens e regras em texto, no formato de `templates/design.md`, mudando por PR. Não há `DESIGN.md` nem `PRODUCT.md` paralelos. Se uma ferramenta exigir o `DESIGN.md`, ele só aponta para o `docs/design.md`.
- **Nascimento:** o arquivo nasce na primeira spec de uma issue com interface, e as escolhas visuais são confirmadas no portão `spec-aprovada`.
- **Impeccable:**
  - só a skill (`npx skills add pbakaus/impeccable`), não o plugin;
  - as skills (`critique`, `audit`, `polish`) são de uso manual e não reprovam PR;
  - a CLI `impeccable detect`, com versão fixada e `DO_NOT_TRACK=1`, roda sobre as páginas renderizadas como alerta que não reprova o CI, e cada achado vira item da revisão;
  - o template não usa fontes da lista `overused-font`.

  A instalação e o uso no fluxo ficam para o item 11 do fatiamento.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Stitch por MCP | Respondia sucesso sem gravar as telas (#42). |
| pen.dev | Canvas proprietário, MCP só com o app desktop aberto, sem CI. |
| `DESIGN.md` e `PRODUCT.md` do Impeccable | Duplicariam o `docs/design.md` e o `docs/prd.md`. |
| Plugin do Impeccable | Os hooks rodam fora do sandbox ([ADR 0005](0005-isolamento-do-agente-em-sandbox.md)). |
| `detect` reprovando o CI | O piloto achou falsos positivos. |
| Rodada de design na `/fabrica:prd` ou skill nova | A PRD roda antes de existir tela, e uma skill nova seria um comando a mais para um passo que acontece uma vez por projeto. |

## Consequências
- Todo projeto com interface passa a ter `docs/design.md`, criado pela primeira spec com interface.
- A triagem marca se a issue tem interface, e a spec usa essa marca.
- A verificação visual automática depende do item 11 e do CI com Playwright (item 9).
