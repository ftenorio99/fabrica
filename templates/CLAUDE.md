# CLAUDE.md

Regras deste projeto para o Claude Code. Base mantida no repositório `fabrica` (`templates/CLAUDE.md`); ajustes específicos do projeto ficam na seção "Projeto", no fim do arquivo.

## Fluxo da fábrica
Toda tarefa segue o mesmo loop, com duas aprovações humanas: a spec antes de qualquer código e o PR antes do merge.

1. Issue com a label `agente` → triagem (`/fabrica:triagem`). Se faltar informação: perguntas na issue + `precisa-info`.
2. Spec em `specs/SPEC-<nº>.md` com critérios de aceite (`/fabrica:spec`), gravada na branch da issue → `spec-pronta`. A implementação continua na mesma branch, e spec e código chegam juntos no PR. Numa issue pequena e sem ambiguidade (atalho), a própria triagem publica uma spec curta no comentário dela e aplica `spec-pronta`, sem `/fabrica:spec`.
3. O usuário aplica `spec-aprovada`. Sem essa label, não escreva código para a issue.
4. Implementação (`/fabrica:implementar`) com `make test` e `make lint` verdes. Falhou duas vezes → pare e reporte na issue.
5. Revisão automática contra a spec (`/fabrica:revisar`) → PR com `Fixes #<nº>` → `pronto-revisao`.
6. O usuário revisa e aprova o merge.

Documentos: `docs/prd.md` (produto), `specs/` (uma spec por issue), `docs/adr/` (decisões de arquitetura).

## Idioma
- Código em **inglês**: nomes de variáveis, funções, classes, arquivos e pastas.
- Em **português**: comentários, documentação, issues, specs, PRs e descrições de commit.

## Git e GitHub
- A `main` nunca recebe commit ou push direto; toda mudança entra por PR a partir de uma branch da `main` atualizada.
- Branches: `<tipo>/<nº-da-issue>-<descricao-curta>`, em minúsculas e com hífens (ex.: `feat/12-tela-login`). Sem issue, omita o número.
- Todo `feat` e `fix` começa por uma issue. `chore`, `docs` e `style` pequenos podem ir sem issue.
- Commits no padrão Conventional Commits, prefixo em inglês e descrição em português, no imperativo, minúsculas e sem ponto final: `feat: adiciona tela de login`.
- Tipos: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`.
- O título do PR segue o mesmo padrão (vira a mensagem do squash). Merge com squash, apagando a branch, só depois da confirmação do usuário.

## Segredos
- Nunca commitar credenciais, tokens ou `.env`. Versione um `.env.example` sem valores reais.
- Antes de cada commit, revise o que está em stage (`git diff --staged`).

## Versões e dependências
- Projeto novo nasce na **LTS mais recente** do runtime (ex.: Node) e na versão estável atual de cada dependência principal. Confira na hora, pela fonte oficial (ex.: `https://nodejs.org/dist/index.json`) ou pelo Context7; nunca use a versão de memória do modelo.
- Fixe a versão do runtime num lugar só, lido pelo CI e pelo Docker (ex.: `.nvmrc`), e repita a faixa em `engines` do `package.json`.
- Quando sair uma LTS nova, a atualização entra por um PR `chore` com lint, testes e build verdes.

## Projeto
<!-- Stack, comandos (make test, make lint, make e2e), arquitetura e convenções deste projeto. -->
