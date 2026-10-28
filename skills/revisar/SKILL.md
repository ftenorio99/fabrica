---
name: revisar
description: Faz a revisão automática da branch de uma issue contra a spec com o subagente revisor, corrige os achados bloqueantes e importantes, abre o PR com a evidência de cada critério de aceite, espera o CI e aplica pronto-revisao. Use depois de /fabrica:implementar, ou para revisar de novo depois de mudanças pedidas no PR.
argument-hint: "<número da issue>"
disable-model-invocation: true
---

# Revisão automática e PR

Issue: #$ARGUMENTS

A revisão automática é a primeira passada antes da revisão humana. Ela confere a mudança contra a spec, não contra o gosto de quem revisa. Esta skill **nunca faz merge**.

## 1. Pré-requisitos
- Você está na branch da issue (a do comentário `<!-- fabrica:spec -->`), com commits além da `main` e tudo enviado (`git status` limpo, `git push` feito).
- `make lint` e `make test` passam. Se não passarem, volte para a etapa de implementação em vez de revisar.

## 2. Rodada de revisão
Chame o subagente `revisor` deste plugin (no Agent tool, `fabrica:revisor`). Se ele não estiver disponível, use um subagente de propósito geral e passe a ele, como instruções, o conteúdo de [../../agents/revisor.md](../../agents/revisor.md).

Passe ao revisor:
- o número da issue e o caminho da spec;
- a branch e a base (`origin/main`);
- as anotações da implementação: verificações manuais feitas e desvios da spec.

O revisor devolve, para cada critério de aceite, se está atendido e com qual evidência, e uma lista de achados com severidade `bloqueante`, `importante` ou `sugestão`.

## 3. Corrigir
- Corrija todos os achados `bloqueante` e `importante` que procedem. Se discordar de um achado, registre o motivo; ele vai para o PR.
- Depois de corrigir, rode `make lint` e `make test`, faça commit (`fix: ...` ou o tipo adequado) e push, e faça uma nova rodada de revisão.
- No máximo **duas rodadas de correção**. Se ainda restarem achados bloqueantes, abra o PR mesmo assim como rascunho (`--draft`), liste os achados pendentes e não aplique `pronto-revisao`.
- Sugestões não são aplicadas: elas vão listadas no PR para o usuário decidir.

## 4. Abrir o PR
Se já existir PR da branch (`gh pr view`), atualize a descrição em vez de abrir outro. Senão, `gh pr create`:

- **Título:** `<tipo da triagem>: <descrição curta em português>`, no padrão do `CLAUDE.md` (vira a mensagem do squash).
- **Corpo:**

  ```markdown
  ## Resumo
  <O que muda, em duas a quatro frases, citando a spec.>

  **Spec:** `specs/SPEC-<nº>.md` · **ADR:** <se houver>

  ## Critérios de aceite
  | ID | Status | Evidência |
  |---|---|---|
  | CA1 | ✅ | <teste que cobre, ou comando executado e resultado> |
  | CA2 | ✅ | <...> |

  ## Verificações manuais
  <Cada verificação da spec: comando executado e resultado observado.>

  ## Desvios da spec
  <Ajustes feitos em relação ao desenho técnico e por quê, ou "nenhum".>

  ## Revisão automática
  <Número de rodadas, achados corrigidos, achados de que discordou (com o motivo) e sugestões não aplicadas.>

  ## Para a sua revisão
  <Onde vale olhar com mais atenção: arquivos sensíveis, decisões, riscos.>

  Fixes #<nº>
  ```

## 5. CI e labels
- Espere o CI: `gh pr checks --watch`. Se falhar por causa da mudança, corrija como no passo 3 (conta como rodada). Se falhar por motivo externo (instabilidade, credencial), registre no PR e siga.
- Com CI verde e sem achados bloqueantes: `gh issue edit <nº> --add-label pronto-revisao`.
- Comente na issue com o link do PR e diga ao usuário no chat que o PR está pronto para a revisão dele.

## Regras
- Nunca faça merge, nem aprove o próprio PR.
- Não mude a spec para fazer a implementação passar. Se a spec estiver errada, comente na issue.
- O status de cada CA no PR precisa ter evidência; "implementado" sem evidência não conta.
