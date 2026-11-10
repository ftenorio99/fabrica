---
name: <nome curto da identidade visual>
colors:
  light:
    background: "<#rrggbb>"
    foreground: "<#rrggbb>"
    card: "<#rrggbb>"
    muted: "<#rrggbb>"
    muted-foreground: "<#rrggbb>"
    accent: "<#rrggbb>"
    primary: "<#rrggbb>"
    primary-foreground: "<#rrggbb>"
    destructive: "<#rrggbb>"
    border: "<#rrggbb>"
    ring: "<#rrggbb>"
  dark:
    background: "<#rrggbb>"
    foreground: "<#rrggbb>"
    card: "<#rrggbb>"
    muted: "<#rrggbb>"
    muted-foreground: "<#rrggbb>"
    accent: "<#rrggbb>"
    primary: "<#rrggbb>"
    primary-foreground: "<#rrggbb>"
    destructive: "<#rrggbb>"
    border: "<#rrggbb>"
    ring: "<#rrggbb>"
typography:
  sans: <fonte do texto>
  mono: <fonte monoespaçada>
rounded: <raio base em px, ou 0>
shadows: <none | descrição curta>
---

# Design system do <projeto>: <nome da identidade visual>

Fonte da verdade do visual do <projeto>. Os tokens do cabeçalho e as regras abaixo valem para todas as telas, e a implementação deve segui-los. No código, eles vivem em <arquivo de configuração de estilo, ex.: `src/app/globals.css`>, e nenhum componente usa valor solto. O arquivo muda por PR, como qualquer documento ([ADR 0009 da fábrica](https://github.com/ftenorio99/fabrica/blob/main/docs/adr/0009-aprovacao-visual-sem-ferramenta-de-design.md)).

## Marca e estilo

<Em duas ou três frases, a personalidade do produto. Depois, de três a cinco princípios visuais, cada um numa linha, como "**Estrutura por fios:** áreas separadas por fios de 1 px, nunca por sombras".>

## Cores

<Uma tabela com o uso, o valor no tema claro, o valor no tema escuro e o token. Cada token do cabeçalho aparece nela. Depois, o papel das cores de estado, o contraste mínimo (texto com pelo menos 4,5:1 sobre o fundo) e o que muda no modo escuro.>

| Uso | Claro | Escuro | Token |
| --- | --- | --- | --- |
| Fundo do app | `<#rrggbb>` | `<#rrggbb>` | `--background` |

## Tipografia

<As fontes do cabeçalho e onde cada uma entra, os pesos de títulos e de corpo e como as fontes são carregadas.>

Não use fontes da lista `overused-font` do Impeccable, que aponta as fontes mais repetidas em interfaces geradas por IA, como Inter, Geist e Plus Jakarta Sans. Registre aqui por que a fonte escolhida serve ao produto.

## Layout e espaçamento

<A grade e as larguras no computador e no celular (390 px), a navegação em cada um e a escala de espaçamento, como múltiplos de 4 e 8 px, com a distância entre itens e entre grupos.>

## Profundidade

<Como as camadas se separam: sombras, fios ou faixas de fundo, e como ficam menus, modais e o foco do teclado.>

## Formas

<O raio de canto do cabeçalho, onde ele se aplica e as exceções.>

## Componentes

<Uma subseção `###` por componente usado nas telas (botões, campos, cartões, listas), com os estados de repouso, foco, erro, desabilitado e selecionado, sempre em termos dos tokens.>

## Histórico

- <AAAA-MM-DD>: primeira versão (issue #<nº>).
