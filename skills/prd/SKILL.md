---
name: prd
description: Entrevista o usuário sobre a ideia de um produto e escreve ou atualiza o PRD em docs/prd.md. Use no início de um projeto ou quando o escopo do produto mudar. Não escreve código nem cria issues.
argument-hint: "[ideia do produto em uma frase]"
disable-model-invocation: true
---

# PRD do produto

Você vai conduzir uma entrevista curta e escrever o PRD (documento de requisitos do produto) em `docs/prd.md`. O PRD é a base de todas as specs e issues do projeto, então ele precisa ser concreto: cada funcionalidade deve poder virar uma ou mais issues.

Ideia inicial do usuário: $ARGUMENTS

## Regras
- Não escreva código, não crie issues e não altere outros arquivos além de `docs/prd.md`. A única ação fora dele é o setup das labels do passo 5.
- Proponha em vez de só perguntar: para cada decisão, ofereça 2 a 4 opções concretas com a sua recomendação primeiro. Use o AskUserQuestion, com no máximo 4 perguntas por rodada.
- Não pergunte o que dá para descobrir sozinho: leia antes o `CLAUDE.md`, o `README.md` e o que já existir em `docs/`.
- Se o usuário não souber responder algo, registre em "Perguntas em aberto" e siga em frente.

## 1. Contexto
- Se `docs/prd.md` já existir, leia-o, mostre um resumo de três linhas e pergunte o que mudou. Atualize as seções afetadas, sem reescrever o resto, e registre a mudança no histórico no fim do arquivo.
- Se o projeto tiver critérios definidos para o produto (no `CLAUDE.md` ou num documento citado pelo usuário), use-os para avaliar as respostas e avise quando uma escolha os contrariar.

## 2. Entrevista
Faça as rodadas em ordem e pule o que já estiver respondido.

1. **Problema e público:** que problema resolve, para quem, e como essa pessoa resolve hoje.
2. **Objetivo e sucesso:** o que precisa ser verdade para o MVP ter dado certo e como medir.
3. **Escopo do MVP:** proponha a lista de funcionalidades a partir das respostas anteriores. Peça ao usuário para marcar cada uma como obrigatória ou desejável. Puxe o escopo para o menor produto que ainda resolve o problema.
4. **Fora de escopo e restrições:** o que fica explicitamente de fora; stack, prazo, dados sensíveis, integrações obrigatórias.
5. **Riscos:** o que pode dar errado (técnico, de produto ou de uso) e como mitigar.

Entre as rodadas, resuma em uma ou duas linhas o que você entendeu, para o usuário corrigir cedo.

## 3. Escrita
- Preencha o template em [template.md](template.md) e salve em `docs/prd.md`. Crie a pasta `docs/` se não existir.
- Escreva para quem vai implementar: frases curtas, sem jargão de marketing e sem prometer o que não foi decidido.
- Cada funcionalidade do escopo deve ter um identificador estável (F1, F2…), usado depois nas specs e nas issues.
- Em "Fatiamento inicial", quebre as funcionalidades obrigatórias em candidatas a issue de 1 a 2 dias de trabalho humano cada, em ordem de dependência. Não crie as issues no GitHub; essa é a próxima etapa do fluxo.

## 4. Revisão
- Mostre ao usuário o PRD inteiro e pergunte o que ajustar. Repita até ele aprovar.
- Ao final, não faça commit. Diga que o PRD está pronto e ofereça abrir um PR na branch `docs/prd` com o commit `docs: adiciona prd do produto` (ou `docs: atualiza prd` quando for uma atualização).

## 5. Labels
- Sem pedir confirmação, rode `bash <diretório base desta skill>/../../scripts/setup-labels.sh` no diretório do projeto, para as labels da fábrica existirem antes da primeira issue.
- Se ainda não houver remote no GitHub (repositório não criado), não trate como falha: avise que o setup roda com `/fabrica:setup` depois do `gh repo create`.
- Mostre o resultado em uma linha (repositório e labels criadas ou corrigidas).
