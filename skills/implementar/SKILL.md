---
name: implementar
description: Implementa uma issue com spec aprovada (label spec-aprovada) na branch da issue - código, testes de cada critério de aceite, make lint e make test verdes e verificações manuais registradas - e encadeia a revisão automática. Use quando o usuário aprovar a spec.
argument-hint: "<número da issue>"
disable-model-invocation: true
---

# Implementação da issue

Issue: #$ARGUMENTS

A spec aprovada é o contrato. Implemente o que ela pede, só o que ela pede, e prove cada critério de aceite. Toda comunicação de bloqueio acontece **na issue**, para esta skill funcionar igual no terminal e no GitHub Actions.

## 1. Pré-requisitos
Pare e explique o motivo (no chat e, quando indicado, na issue) se algum destes falhar:
- **Spec aprovada:** `gh issue view <nº> --json labels,comments` precisa mostrar `spec-aprovada`. Pegue a branch e o caminho da spec no comentário `<!-- fabrica:spec -->` mais recente.
- **Limite de trabalho em andamento:** toda issue aberta com `spec-aprovada` está em andamento, inclusive as que aguardam merge (a issue só fecha no merge). Conte com `gh issue list --label spec-aprovada --state open`. Se houver 3 ou mais além desta, pare: a fábrica só aceita 3 tarefas em andamento.
- **Ambiente:** confira as ferramentas que o projeto exige (versões em `.nvmrc`, `packageManager`, `engines`, `CLAUDE.md` e na seção de riscos da spec). Se faltar alguma, pare e diga exatamente o que instalar. Não instale ferramentas do sistema por conta própria.

## 2. Preparar a branch
- `git fetch origin`, `git switch <branch>` e `git pull`. Se a `main` avançou desde a spec, faça `git rebase origin/main` e resolva conflitos simples; se o conflito mexer no escopo, pare e reporte.
- Na spec, mude o status para `aprovada` e registre a data no histórico. Nos ADRs citados pela spec, mude o status de `proposto` para `aceito`.
- Commit: `docs: marca spec da issue #<nº> como aprovada`.
- Se a branch já tiver commits de implementação, é uma retomada depois de um ajuste da spec: eles continuam valendo. Leia o histórico da spec para ver o que mudou e implemente só a diferença.

## 3. Implementar
- Leia a spec inteira, o `CLAUDE.md` e o código que será tocado antes de escrever.
- Siga o desenho técnico da spec: os arquivos, interfaces e decisões descritos nela. Pequenos ajustes forçados pela realidade (uma API de biblioteca diferente da prevista, um nome de arquivo gerado pela ferramenta) são permitidos e vão para a seção "Desvios da spec" do PR.
- **Desvio relevante** é qualquer mudança de comportamento, de critério de aceite, de escopo ou de decisão listada para o usuário confirmar. Nesse caso, pare: comente na issue o que encontrou e as opções, com uma recomendação. Não decida sozinho.
- **Pedido de mudança do usuário:** se o próprio usuário pedir, no chat ou na issue, uma mudança desse tipo depois da `spec-aprovada`, não a aplique direto nem edite a spec por conta própria. A spec aprovada é o contrato. Faça commit e push do que já existe, registre o pedido na issue e indique o caminho: o usuário remove `spec-aprovada`, roda `/fabrica:spec <nº> <ajuste>` (que ajusta a spec na mesma branch), aprova de novo e retoma com `/fabrica:implementar <nº>`.
- Escreva os testes de cada critério marcado como unitário ou e2e junto com o código que ele cobre.
- Commits pequenos, cada um com uma mudança lógica, no padrão do `CLAUDE.md` (Conventional Commits, descrição em português). Antes de cada commit, revise o stage (`git diff --staged`) e confira que nada gerado ou secreto entrou.
- Não faça nada fora do escopo da spec, nem melhorias "de passagem". Se notar algo que merece atenção, anote para o PR.

## 4. Verificar
- Rode `make lint` e `make test` (e `make e2e` se a spec pedir). Conte como **uma rodada de verificação** cada vez que a implementação estiver pronta e você rodar os comandos.
- Se falhar, corrija e rode de novo. Depois de **duas rodadas de correção** ainda com falha, pare: comente na issue o comando, o erro resumido e o que já foi tentado, faça push do que existe e avise o usuário. Não siga para a revisão.
- Execute cada verificação manual descrita na seção "Testes" da spec (por exemplo, introduzir um erro, conferir que o comando falha e reverter). Anote o comando e o resultado de cada uma; isso vai para o PR.
- Confira que o diff final contra a `main` (`git diff origin/main...HEAD --stat`) só contém o que a spec prevê.
- `git push`.

## 5. Revisar
Com tudo verde, siga as instruções de [../revisar/SKILL.md](../revisar/SKILL.md) para a mesma issue, levando junto as anotações de verificações manuais e desvios.
