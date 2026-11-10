# SPEC-45: Design system versionado e campo de interface na triagem

**Issue:** #45 · **PRD:** F7 (item 10 do fatiamento) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-10

## Contexto
A F7 do `docs/prd.md` pede aprovação visual: cada projeto com interface tem um design system versionado em `docs/design.md`. O fatiamento divide a F7 em dois itens: o item 10 (esta issue), com o design system e o campo de interface na triagem, e o item 11, com a descrição das telas na spec e os screenshots no PR, que depende do item 9 (CI com Playwright). Na triagem de 10/11 você escolheu dividir a issue e deixar o kairo como está. A decisão sobre o Impeccable (comentário de 10/11) entra na ADR desta issue, e o uso dele no fluxo fica para o item 11.

## Objetivo
Todo projeto com interface tem um `docs/design.md` no formato da fábrica, criado pelo fluxo na primeira issue com interface, e a triagem diz se cada issue tem interface.

## Comportamento esperado
**Formato do `docs/design.md`:** cabeçalho YAML com os tokens e corpo em Markdown com as regras. O formato é o do arquivo do kairo, que já está em uso:
- cabeçalho: `name`, `colors.light` e `colors.dark` (mapa de nome do token para cor hexadecimal), `typography` (`sans`, `mono`), `rounded` e `shadows`;
- corpo: as seções `Marca e estilo`, `Cores`, `Tipografia`, `Layout e espaçamento`, `Profundidade`, `Formas`, `Componentes` e `Histórico`;
- o arquivo é a fonte da verdade do visual e muda por PR.

**Template:** `templates/design.md` traz esse formato com marcadores (`<...>`) no lugar dos valores e uma frase de instrução em cada seção. Na seção `Tipografia`, a regra é não escolher fontes da lista `overused-font` do Impeccable. O piloto de 30/10 citou Inter, Geist e Plus Jakarta Sans.

**Campo "Interface" na triagem:** a tabela do comentário de triagem ganha a linha `| Interface | sim |` ou `| Interface | não |`.

| Situação | Valor |
|---|---|
| A issue muda algo que o usuário final vê na tela: página, componente, estilo, texto da interface | `sim` |
| Qualquer outro caso: back-end, CLI, documentação, CI, skills da fábrica | `não` |
| Dúvida | `sim`. Uma descrição de tela a mais custa menos que uma tela sem descrição |

**Nascimento do `docs/design.md`:** na primeira spec com interface.

| Situação ao rodar `/fabrica:spec` | O que acontece |
|---|---|
| Triagem com `Interface: sim` e o projeto sem `docs/design.md` | A spec copia `templates/design.md` para `docs/design.md` na branch da issue e preenche os tokens e as regras. Ela lista as escolhas (cores, fontes, arredondamento) em "Decisões para você confirmar" e cita o arquivo no desenho técnico. O commit da spec inclui o arquivo. |
| Triagem com `Interface: sim` e o projeto com `docs/design.md` | O arquivo existente vale como está; a spec não o recria nem o reformata. |
| Triagem com `Interface: não` ou sem o campo (triagem antiga) | Nada muda no `docs/design.md`. |

**Atalho:** uma issue com `Interface: sim` num projeto sem `docs/design.md` não cabe no atalho. A spec curta pularia o nascimento do arquivo.

**Kairo:** o `docs/design.md` do kairo já segue o formato e fica como está, sem mudança nesta issue.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md` registra: nenhuma ferramenta de design externa no fluxo (Stitch, Figma), com o motivo da #42; o `docs/design.md` como fonte do visual, sem `DESIGN.md` nem `PRODUCT.md` paralelos; e a adoção do Impeccable como decidida em 10/11 (só a skill, de uso manual; a CLI `detect` com versão fixada e `DO_NOT_TRACK=1`, como alerta que não reprova o CI e com os achados na revisão; o uso fica para o item 11). Status `proposto`, que passa a `aceito` na aprovação. | revisão do diff |
| CA2 | `templates/design.md` existe, com o cabeçalho YAML de chaves `name`, `colors.light`, `colors.dark`, `typography.sans`, `typography.mono`, `rounded` e `shadows`, e com as oito seções do formato. A seção `Tipografia` proíbe as fontes da lista `overused-font` do Impeccable e cita Inter, Geist e Plus Jakarta Sans. | revisão do diff |
| CA3 | As chaves do cabeçalho e os títulos das seções `##` do template são os mesmos do `docs/design.md` do kairo (`gh api repos/ftenorio99/kairo/contents/docs/design.md`). Lá, `Componentes` pode ter subseções `###` próprias. | manual: comparar as chaves e os títulos |
| CA4 | `skills/triagem/SKILL.md` tem a linha `Interface` na tabela do comentário, com a regra da tabela "Campo Interface" acima, inclusive `sim` na dúvida, e a condição de atalho nova: `Interface: sim` num projeto sem `docs/design.md` não cabe no atalho. | revisão do diff |
| CA5 | `skills/spec/SKILL.md` tem as três situações da tabela "Nascimento do `docs/design.md`": criar o arquivo a partir de `templates/design.md` com as escolhas em "Decisões para você confirmar", não tocar no arquivo existente, e nada fazer com `Interface: não` ou sem o campo. | revisão do diff |
| CA6 | Numa issue de teste neste repositório, com uma triagem de teste com `Interface: sim`, `claude -p "/fabrica:spec <nº>" --plugin-dir <esta branch>`, rodado numa worktree da `main` sem `docs/design.md`, cria na branch da issue um `docs/design.md` com o cabeçalho do template preenchido, sem marcador `<...>` sobrando, e lista as escolhas no comentário de spec. No fim, a issue de teste é fechada com um comentário dizendo que era teste, e a branch é apagada. | manual: `claude --plugin-dir <clone>` na branch, com issue de teste |
| CA7 | `docs/comandos.md` (triagem e spec), `docs/fluxo.md` (a linha da triagem e a da spec) e o `CLAUDE.md` (estrutura de `templates/`) descrevem o campo e o nascimento do `docs/design.md`. A `version` do `.claude-plugin/plugin.json` sobe uma minor em relação à `main` no momento do PR. | revisão do diff |

## Fora de escopo
- Item 11 do fatiamento: a descrição das telas na spec, os screenshots e o HTML das páginas logadas pelo Playwright, o `make design-lint` com o `impeccable detect` no CI e no `/fabrica:revisar`, a conferência visual na revisão e a instalação da checagem pelo `/fabrica:setup`. Esse item vira uma issue nova, criada pelo `/fabrica:backlog`.
- Mudar o `docs/design.md` do kairo, inclusive as fontes.
- A aplicação dos tokens no código (`globals.css`, tema do Tailwind) e a escolha da biblioteca de componentes, que são decisões de cada projeto na spec da primeira issue com interface.
- Ferramentas de design externas no fluxo e testes de regressão visual por pixel.

## Desenho técnico
**Arquivos e módulos:**
- `docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md`: novo. O número 0008 está reservado pela #119 (PR #125).
- `templates/design.md`: novo.
- `skills/triagem/SKILL.md`: passo 2 (critério de atalho e o campo), passo 4 (a tabela do comentário).
- `skills/spec/SKILL.md`: passo 3 (ler o campo `Interface` da triagem e conferir se `docs/design.md` existe) e passo 4 (criar o arquivo a partir do template). O caminho do template a partir da skill é `../../templates/design.md`.
- `docs/comandos.md`, `docs/fluxo.md`, `CLAUDE.md`, `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:** a linha `| Interface | sim/não |` do comentário de triagem, que o `/fabrica:spec` lê. As triagens antigas não têm a linha, e a spec trata a falta como `não`.

**Decisões:**
- `docs/design.md` como fonte do design, sem `DESIGN.md`/`PRODUCT.md` paralelos (recomendação da triagem). Alternativa descartada: adotar os arquivos do Impeccable.
- A ADR desta issue registra também a adoção do Impeccable decidida em 10/11, e o uso fica para o item 11 (recomendação da triagem). Alternativa descartada: uma ADR própria no item 11.
- Template sem fontes da lista `overused-font` (recomendação da triagem). Alternativa descartada: escolha livre.
- O `docs/design.md` do kairo vale como está (recomendação da triagem, a partir da sua resposta de 10/11). Alternativa descartada: rever as fontes nesta issue.
- Campo `Interface` com `sim`/`não`, e `sim` na dúvida (recomendação da triagem). Alternativa descartada: `sim`/`não`/`parcial`.
- O item 11 vira uma issue nova pelo `/fabrica:backlog` (recomendação da triagem). Alternativa descartada: criar a issue à mão.
- O `docs/design.md` nasce na primeira spec com interface, porque a spec já tem o portão `spec-aprovada`, onde você confirma as escolhas visuais, e o planejamento em ondas deixa o detalhe para quando a issue é puxada (`docs/principios.md`). Alternativas descartadas: uma rodada na `/fabrica:prd`, que trata do produto e não do visual e rodaria antes de existir qualquer tela; uma skill nova, que acrescenta um comando para um passo que acontece uma vez por projeto.
- Formato igual ao do kairo, porque ele já está em uso e a issue manda aproveitá-lo. Alternativa descartada: um formato novo, que obrigaria a converter o kairo.
- A issue com interface num projeto sem `docs/design.md` sai do atalho, porque a spec curta não cria arquivos. Alternativa descartada: a triagem criar o arquivo, o que a triagem não faz (ela não escreve código nem branch).

**Fontes da documentação:**
- gh 2.103.3 — `gh api --help` (leitura do arquivo do kairo pelo endpoint `contents`).
- Impeccable (lista `overused-font`) — não verificada além do piloto de 30/10 (versão 4.8.0).

**ADR:** `docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md`

## Testes
- CA1, CA2, CA4, CA5 e CA7: revisão do diff.
- CA3: comparar as chaves do cabeçalho e os títulos `##` do template com os do arquivo do kairo.
- CA6: issue de teste, sem a label `agente`, com um comentário de triagem de teste com `Interface: sim`. Rodar `claude -p "/fabrica:spec <nº>" --plugin-dir <esta branch>` numa worktree da `main` e conferir o `docs/design.md` da branch de teste e o comentário de spec. Depois, fechar a issue e apagar a branch.
- Os scripts de teste do `CLAUDE.md` continuam passando.

## Passos de produção
nenhum

## Riscos e dúvidas
- A lista `overused-font` pode mudar entre versões do Impeccable. O template cita a regra e os exemplos do piloto, e a checagem automática chega no item 11, com a versão fixada.
- O PR #125 (#119) também mexe no `skills/spec/SKILL.md`. Quem fizer o merge depois vai precisar de um rebase simples.

## Histórico
- 2026-11-10: criação.
- 2026-11-10: aprovada.
