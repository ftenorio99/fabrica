---
name: licao
description: Registra uma lição aprendida do usuário numa issue ou PR, no formato fabrica:licao com a label licao, depois de mostrar a lição formatada e receber a confirmação. Aceita o número no repositório atual ou dono/repo#número para outro repositório. Use quando o usuário quiser anotar algo que deu errado ou que vale lembrar na retrospectiva.
argument-hint: "[<dono>/<repo>#]<número> <texto da lição>"
disable-model-invocation: true
---

# Registrar lição

Argumentos: $ARGUMENTS

A lição do usuário segue o mesmo formato das lições automáticas: [formato.md](formato.md). Esta skill só organiza o texto do usuário; não invente fato, causa nem ação.

## 1. Destino
- O primeiro argumento é o destino: `<nº>` é uma issue ou PR do repositório do diretório atual (`gh repo view --json nameWithOwner -q .nameWithOwner`); `<dono>/<repo>#<nº>` aponta outro repositório. O resto é o texto da lição.
- Sem número, pergunte o destino com o AskUserQuestion (por exemplo, a issue ou PR mais recente citado na conversa, ou "outro", para o usuário digitar).
- Confira que o destino existe e descubra se é issue ou PR: `gh api repos/<dono>/<repo>/issues/<nº> -q '{title: .title, pr: (.pull_request != null)}'`. Se não existir, diga isso no chat e pare.
- Sem texto, peça o texto no chat e pare.

## 2. Formatar
Organize o texto nos quatro campos de [formato.md](formato.md), com o marcador `<!-- fabrica:licao gatilho=usuario -->`, a data de hoje e `Origem: usuario`. Um campo que o texto não preenche fica "não informado"; a ação sugerida sem indicação fica "nenhuma, só registro".

## 3. Confirmar
Mostre no chat a lição formatada e o destino (repositório, número, título, issue ou PR). Pergunte com o AskUserQuestion:
- **Publicar:** segue para o passo 4.
- **Ajustar:** o usuário diz o que mudar; refaça o passo 2 e pergunte de novo.
- **Cancelar:** pare sem publicar nada.

## 4. Publicar
Só com a confirmação:
- Escreva o comentário com a ferramenta Write na pasta temporária da sessão e publique sempre como comentário novo: `gh issue comment <nº> -R <dono>/<repo> --body-file <arquivo>`, ou `gh pr comment` se o destino for um PR.
- Aplique a label `licao` como diz [formato.md](formato.md). Se a label não existir, avise que falta rodar `/fabrica:setup` no repositório; o comentário já publicado fica.
- Responda no chat com o link do comentário.

## Regras
- Não publique sem a confirmação do passo 3.
- Não mude nenhuma outra label nem o estado da issue.
- Publique o corpo a partir de um arquivo, com `--body-file`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin.
