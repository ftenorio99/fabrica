# SPEC-128: CI do PR sobe o app e o banco no job e roda o Playwright, e a spec pede casos adversariais nos CAs de ponta a ponta

**Issue:** #128 · **PRD:** F6 (item 9 do fatiamento, M3) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-23

## Contexto
A F6 do [PRD](../docs/prd.md) pede que o CI do PR suba o app e o banco no próprio job e rode o Playwright, com casos adversariais além do caminho feliz. A [ADR 0011](../docs/adr/0011-verificacao-de-integracao-na-etapa.md) já torna o CI em `pull_request` obrigatório nos projetos, como reserva e conferência, mas a fábrica não entrega esse CI: cada projeto escreveu o seu (o `kairo` roda `make e2e` num job próprio; o `ankyra`, com um Postgres de `services:`; o `mnemo` e o `skopia` não têm CI). E a spec não pede casos adversariais: o único lugar onde eles aparecem é o item P5 do runbook de lançamento ([skills/lancamento/runbook.md](../skills/lancamento/runbook.md)), já em produção.

## Objetivo
A fábrica tem um modelo de CI do PR (`templates/workflows/ci.yml`) que roda `make lint`, `make test` e `make e2e` num job descartável, o `/fabrica:setup` o instala num projeto sem CI e avisa quando o CI existente não roda o `make e2e`, e toda spec com CA de ponta a ponta traz CAs adversariais próprios.

## Comportamento esperado

### Contrato do `make e2e` ([ADR 0019](../docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md))
O `make e2e` de um projeto é autossuficiente: sobe o banco (pelo Docker Compose do projeto, em geral com o alvo `db-up` como dependência) e o app (pelo `webServer` do Playwright ou pelo Compose) e roda o Playwright. É o mesmo comando que a etapa roda localmente (ADR 0011), e o CI só o chama. O contrato fica escrito no guia do CI e no comentário de comandos do `templates/AGENTS.md`.

### Modelo `templates/workflows/ci.yml`
- **Gatilhos:** `pull_request` e `push` na `main`. `permissions: contents: read` no topo, sem outra permissão. `concurrency` por PR (ou ref), com `cancel-in-progress: true`.
- **Ações fixadas pelo SHA do commit**, com a versão num comentário (`# v7.0.1`), como no CI do `kairo`. Nenhuma ação por tag ou branch.
- **Nenhum secret:** o modelo não cita `secrets.`. Valores de teste vêm do `.env.example` (abaixo).
- **Preparação, igual nos dois jobs:**
  1. `actions/checkout`;
  2. com `.nvmrc`, `actions/setup-node` com `node-version-file: .nvmrc`; sem `.nvmrc`, o passo é pulado (`if: hashFiles('.nvmrc') != ''`);
  3. com `pnpm-lock.yaml`, `pnpm/action-setup` (a versão vem do `packageManager` do `package.json`); sem ele, pulado;
  4. instalação das dependências por um passo de shell, pela primeira situação que valer:

     | Situação | Comando |
     |---|---|
     | `pnpm-lock.yaml` existe | `pnpm install --frozen-lockfile` |
     | `package-lock.json` existe | `npm ci` |
     | o `Makefile` tem o alvo `install:` | `make install` |
     | nenhuma | nada, com a linha `ci: sem lockfile nem alvo install; dependências não instaladas` |
  5. `.env` de teste: se não existe `.env` e existe `.env.example`, copia `.env.example` para `.env`. Os valores do `.env.example` são os locais de desenvolvimento, sem valor real (regra de segredos do `templates/AGENTS.md`), e o guia diz que eles precisam bastar para o `make test` e o `make e2e`.
- **Job `verificacao`:** preparação, `make lint`, `make test`.
- **Job `e2e`**, em paralelo ao `verificacao`:
  1. preparação;
  2. um passo confere se o `Makefile` tem uma linha que começa com `e2e:`. Sem o alvo, imprime `ci: o Makefile não tem o alvo e2e; nada a rodar` e os passos seguintes são pulados: o job termina verde;
  3. com o alvo, instala o Chromium e as dependências do sistema do Playwright (`<pnpm exec|npx> playwright install --with-deps chromium`), com cache de `~/.cache/ms-playwright` pela versão do `@playwright/test` resolvida; com o cache, roda só `playwright install-deps chromium`;
  4. `make e2e`;
  5. em falha, envia `playwright-report/` como artefato `playwright-report`, por 7 dias.
- O cabeçalho do arquivo diz, em comentários em português, de onde ele vem (SPEC-128, ADR 0019), o contrato do `make e2e`, o papel do `.env.example` e que o projeto pode editar a cópia (por exemplo, para outros navegadores ou outra stack).

### No `/fabrica:setup` (novo passo 7, "CI do PR")
Roda depois do passo 6, só dentro de um repositório git. Fora dele, o passo é pulado e o resumo diz "CI do PR: por projeto, não conferido fora de um repositório git".

O setup roda `bash <diretório base>/../../scripts/setup-ci.sh --check` e segue a linha impressa:

| Saída do `--check` | Quando | O que o setup faz |
|---|---|---|
| `ausente` | nenhum arquivo `.yml`/`.yaml` em `.github/workflows/` dispara em `pull_request` | Explica que a ADR 0011 exige um CI em `pull_request` e o que o modelo roda. Pergunta com o AskUserQuestion se instala, com "Não instalar" como primeira opção. Com um sim, roda `setup-ci.sh --apply` (estado `instalado agora`). Com um não, nada é gravado (estado `ausente, não instalado a pedido do usuário`). |
| `sem-e2e` | há workflow em `pull_request`, o `Makefile` tem o alvo `e2e:` e nenhum workflow em `.github/workflows/` contém `make e2e` | Não grava nada. Avisa que o CI não roda o Playwright e remete ao guia do CI (estado `existe, sem make e2e`). |
| `ok` | há workflow em `pull_request` e, se o `Makefile` tem `e2e:`, algum workflow contém `make e2e` | Não pergunta nada (estado `já existe`). |
| saída 1 | erro (fora de um repositório git, modelo ausente, `ci.yml` já existe no `--apply`) | Leva a mensagem para o resumo e segue. |

- **"Dispara em `pull_request`":** o arquivo tem a chave `pull_request` dentro de `on:` (em lista, mapa ou valor único). `pull_request_target`, `pull_request_review` e `pull_request_review_comment` não contam, e o `agente.yml` do dispatcher não conta como CI.
- **O `--apply` nunca sobrescreve:** grava `.github/workflows/ci.yml` igual ao modelo, criando a pasta se faltar, e sai com 1, sem gravar, se `.github/workflows/ci.yml` já existe.
- **Sem commit:** como no dispatcher, o setup não faz commit nem abre PR; o resumo diz para levar o arquivo por uma branch e um PR. Diferente do `agente.yml`, a cópia é do projeto: o setup não compara com o modelo nem oferece atualização.

### Casos adversariais na spec (recomendação da triagem)
O passo "Escrever" de `skills/spec/SKILL.md` ganha a regra, junto dos casos de borda:
- **Quando vale:** a spec tem ao menos um CA com verificação `e2e`. Sem CA de ponta a ponta, a regra não se aplica e a spec não ganha CA nem linha nova.
- **O que pede:** para cada fluxo coberto por um CA de ponta a ponta, um CA próprio, também verificado por `e2e`, para cada caso da lista de referência que se aplica ao fluxo, dizendo a entrada e o resultado observável (mensagem, status, nada gravado):

  | Caso | Aplica-se quando o fluxo |
  |---|---|
  | ID de outro usuário na URL ou na API | lê ou altera um registro que tem dono |
  | entrada vazia ou inválida (inclusive texto malicioso, como HTML ou script num campo) | recebe dado digitado ou enviado pelo usuário |
  | sessão expirada ou ausente | exige login |
  | duplo envio | cria ou altera dados num envio |
  | abuso de limite (acima do tamanho, da quantidade ou da frequência permitidos) | tem uma regra com limite |

- **Casos que não se aplicam:** a spec lista na linha `**Casos adversariais não aplicáveis:** <caso> — <motivo>`, logo abaixo da tabela de CAs, para quem revisa ver que o caso foi pensado. Com todos aplicados, a linha não aparece.
- Um caso adversarial que também é caso de borda de limite vira um CA só, que atende as duas regras.
- A lista é a mesma do item P5 do runbook de lançamento, mais o abuso de limite da F6.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `templates/workflows/ci.yml` é YAML válido, dispara em `pull_request` e em `push` na `main`, tem `permissions: contents: read` e nada mais nas permissões, `concurrency` com `cancel-in-progress: true`, e não cita `secrets.` | unitário — `scripts/test-setup-ci.sh` |
| CA2 | Toda ação (`uses:`) do modelo é fixada por um SHA de 40 caracteres hexadecimais, seguido de um comentário de versão | unitário — `scripts/test-setup-ci.sh` |
| CA3 | O job `verificacao` roda, na ordem, `make lint` e `make test`; o job `e2e` roda `make e2e` só depois do passo que confere o alvo `e2e:` e envia `playwright-report/` só em falha, com `retention-days: 7` | unitário — `scripts/test-setup-ci.sh` |
| CA4 | Num repositório de teste com `.nvmrc`, `package-lock.json`, `.env.example`, `docker-compose.yml` com Postgres, e um `Makefile` cujo `make e2e` sobe o banco e roda um teste Playwright que abre o app e lê um dado do banco, o PR com o modelo deixa os dois jobs verdes, e o log do `e2e` mostra o banco subindo e o Playwright passando | e2e — repositório de teste privado criado para isso (ou PR de teste num repositório existente), fechado no fim com um comentário dizendo que era teste; o link do run vai no PR |
| CA5 | No mesmo repositório de teste, uma mudança que quebra o teste Playwright deixa o job `e2e` vermelho e o artefato `playwright-report` disponível no run | e2e — mesmo repositório de teste do CA4 |
| CA6 | Num repositório de teste cujo `Makefile` não tem `e2e:`, o job `e2e` termina verde, com a linha `ci: o Makefile não tem o alvo e2e; nada a rodar`, sem rodar o Playwright | e2e — mesmo repositório de teste, num segundo PR |
| CA7 | A instalação das dependências escolhe `pnpm install --frozen-lockfile`, `npm ci`, `make install` ou a linha de aviso, nesta precedência, conforme os arquivos presentes; e o `.env` só é copiado do `.env.example` quando não existe `.env` | unitário — `scripts/test-setup-ci.sh`, rodando o script do passo de shell extraído do YAML em pastas temporárias |
| CA8 | `setup-ci.sh --check` imprime `ausente` sem `.github/workflows/`, com só o `agente.yml` e com um workflow que só dispara em `pull_request_target` | unitário — `scripts/test-setup-ci.sh` |
| CA9 | `--check` imprime `sem-e2e` com um workflow em `pull_request` sem `make e2e` e um `Makefile` com `e2e:`; e `ok` quando o `Makefile` não tem `e2e:` ou quando algum workflow contém `make e2e`; aceita `on: pull_request`, `on: [push, pull_request]` e `on:` em mapa | unitário — `scripts/test-setup-ci.sh` |
| CA10 | `setup-ci.sh --apply` grava `.github/workflows/ci.yml` igual, byte a byte, ao modelo, criando a pasta; com o arquivo já existente, sai com 1 e não muda o arquivo; fora de um repositório git, as duas opções saem com 1 | unitário — `scripts/test-setup-ci.sh` |
| CA11 | O passo 7 do `skills/setup/SKILL.md` segue a tabela de saídas, pergunta com "Não instalar" como primeira opção, não faz commit e leva o estado final ao resumo, nos cinco estados | manual — leitura do `SKILL.md` contra esta spec, e `claude --plugin-dir <clone>` na branch rodando `/fabrica:setup` numa cópia do repositório de teste sem CI, respondendo "Não instalar" e depois instalando |
| CA12 | O `skills/spec/SKILL.md` traz a regra dos casos adversariais (quando vale, a tabela da lista de referência, a linha de não aplicáveis, a junção com os casos de borda), e o `skills/spec/template.md` traz a linha `**Casos adversariais não aplicáveis:**` comentada como opcional abaixo da tabela de CAs | manual — leitura do diff |
| CA13 | Uma spec escrita com o plugin da branch para uma issue de teste com um fluxo de ponta a ponta (ex.: "usuário logado cria uma nota com título até 100 caracteres") traz CAs `e2e` para outro usuário, entrada vazia ou maliciosa, sessão expirada, duplo envio e título com 101 caracteres; uma issue de teste sem CA de ponta a ponta não ganha CA adversarial nem a linha de não aplicáveis | e2e — `claude --plugin-dir <clone>` na branch, com issues de teste no repositório de teste do CA4, fechadas no fim com um comentário dizendo que eram teste |
| CA14 | O manual fica em dia: `docs/guias/ci-do-pr.md` novo (o que o modelo roda, o contrato do `make e2e`, o `.env.example`, como instalar e adaptar), listado em `docs/README.md`; `docs/comandos.md` cita os casos adversariais na spec e o passo do CI no setup; o `description` do setup cita o CI; o `AGENTS.md` da raiz lista `scripts/setup-ci.sh` e o comando `bash scripts/test-setup-ci.sh`; e a `version` do `plugin.json` sobe | manual — leitura do diff |

## Fora de escopo
- Trocar o CI do `kairo` ou do `ankyra` pelo modelo, ou instalar CI no `mnemo` e no `skopia`: cada projeto faz isso pelo `/fabrica:setup`, com o usuário.
- Atualizar uma cópia do `ci.yml` quando o modelo mudar: a cópia é do projeto.
- Stacks fora do Node com lockfile do npm ou do pnpm além do `make install`: o projeto adapta a cópia.
- O preview protegido da Vercel (#97) e testes contra homologação.
- Mudar o revisor, o `implementar` ou o `revisar`: os CAs adversariais são CAs como os outros e já são cobrados por eles.
- A spec curta do atalho da triagem: o atalho é para issues `P`, e a regra fica para uma issue própria se aparecer um atalho com CA de ponta a ponta.

## Desenho técnico
**Arquivos e módulos:**
- `templates/workflows/ci.yml` (novo): o modelo.
- `scripts/setup-ci.sh` (novo): `--check | --apply`, no molde de `scripts/setup-dispatcher.sh` (mesma checagem de repositório git, mesmas saídas 0 e 1, mensagens com o prefixo `setup-ci:`). A leitura de `on:` usa `python3 -I` com PyYAML quando disponível; sem PyYAML, cai para `grep` das formas aceitas no CA9. Atenção: o PyYAML lê a chave `on` como `True`; o script trata as duas.
- `scripts/test-setup-ci.sh` (novo): testes dos CAs 1, 2, 3, 7, 8, 9 e 10, com repositórios temporários (`git init` em `mktemp -d`) e o padrão `wf` de `scripts/test-dispatch.sh` para ler o YAML. Exige PyYAML, como o `test-dispatch.sh`.
- `skills/setup/SKILL.md`: passo 7 "CI do PR", linha no "Responder", regras ("não sobrescreva nem edite o `ci.yml`", "não faça o commit") e o `description`.
- `skills/spec/SKILL.md` e `skills/spec/template.md`: a regra dos casos adversariais.
- `templates/AGENTS.md`: o comentário de comandos diz que o `make e2e` sobe o banco e o app sozinho.
- `docs/guias/ci-do-pr.md` (novo), `docs/README.md`, `docs/comandos.md`, `AGENTS.md`, `.claude-plugin/plugin.json`.
- `docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md` (novo, `proposto`).

**Dados:** nenhum.

**Interfaces:**
- `scripts/setup-ci.sh --check` → stdout `ausente | sem-e2e | ok`, saída 0; erro → stderr `setup-ci: <mensagem>`, saída 1.
- `scripts/setup-ci.sh --apply` → grava `.github/workflows/ci.yml`, saída 0; arquivo existente ou erro → saída 1, nada gravado.

**Decisões:**
- O CI mora num modelo `templates/workflows/ci.yml` copiado para `.github/workflows/` do projeto, como o `agente.yml` (recomendação da triagem) — é a convenção dos workflows da fábrica (ADR 0015). Alternativa descartada: workflow reutilizável chamado de dentro da fábrica, porque acopla o CI do projeto a um repositório externo.
- O job roda `make e2e`, que sobe o banco pelo Docker Compose do projeto e o app, igual à etapa local (recomendação da triagem) — o CI fica igual ao que a etapa roda (ADR 0011). O modelo não chama `docker compose` direto: quem sobe o banco é o `make e2e`, porque um Compose com o serviço do app brigaria pela porta com o `webServer` do Playwright. Alternativa descartada: passos de Playwright e `services:` escritos no workflow, que duplicariam o comando de cada projeto.
- Todo CA de ponta a ponta ganha CAs adversariais da lista de referência do runbook (P5) mais o abuso de limite, com a linha dos não aplicáveis (recomendação da triagem) — o PRD pede casos explícitos, e a linha evita inflar a spec com casos que não cabem no fluxo. Alternativa descartada: deixar os casos livres para a spec.
- A cópia do `ci.yml` é do projeto: o setup instala só quando não há CI em `pull_request` e nunca sobrescreve — o CI de cada projeto tem variáveis e passos próprios (o `kairo` e o `ankyra` já têm o seu). Alternativa descartada: gerenciar o arquivo byte a byte como o `agente.yml`, que apagaria esses ajustes a cada atualização.
- Valores de teste pelo `.env.example` copiado para `.env` — a fábrica já exige o `.env.example` versionado, sem valor real, e o modelo fica sem secret. Alternativa descartada: bloco `env:` a preencher no modelo, que deixaria marcadores para o usuário e quebraria o CI recém-instalado.
- Dois jobs em paralelo (`verificacao` e `e2e`) — o Playwright é o passo mais lento e o resultado de lint e testes chega antes. Alternativa descartada: um job só, mais simples, mas com o retorno do lint esperando o build do app.

**Fontes da documentação:**
- GitHub Actions — `/websites/github_en_actions` (Context7): `hashFiles()` devolve string vazia sem arquivo e vale em `jobs.<id>.steps[*].if`. Versão: serviço hospedado, sem versão.
- `actions/checkout` v7.0.1, `pnpm/action-setup` v6.0.10, `actions/setup-node` v7.1.0, `actions/cache` v6.1.0, `actions/upload-artifact` v7.0.2 — SHAs e uso tirados do CI do `kairo` (`~/projetos/kairo/.github/workflows/ci.yml`), em uso no projeto; o implementador confere os SHAs nas tags dos repositórios das ações antes do commit. Docs das ações: não verificadas.
- Playwright (`playwright install --with-deps`, `install-deps`) — não verificada; mesmo uso do CI do `kairo`.
- gh 2.105.0 — nenhum comando novo do `gh` nesta spec (o `setup-ci.sh` não usa o `gh`).

**ADR:** [docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md](../docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md)

## Testes
- `bash scripts/test-setup-ci.sh`: CA1, CA2, CA3 (estrutura do YAML), CA7 (passo de instalação e `.env` em pastas temporárias), CA8 a CA10 (`setup-ci.sh` em repositórios temporários).
- Repositório de teste no GitHub com o modelo: CA4 (verde com banco e Playwright), CA5 (vermelho com artefato), CA6 (sem alvo `e2e`).
- `claude --plugin-dir <clone>` na branch: CA11 (setup) e CA13 (spec com casos adversariais).
- Leitura do diff: CA12 e CA14.
- Os testes existentes continuam passando, em especial `bash scripts/test-setup-dispatcher.sh` e `bash scripts/test-dispatch.sh`.

## Passos de produção
nenhum

## Riscos e dúvidas
- O workflow é arquivo sensível (`.github/`): o PR pede revisão humana do modelo, em especial das permissões e dos SHAs.
- Um projeto cujo `.env.example` tem valores vazios (ex.: `BETTER_AUTH_SECRET=`) terá o CI vermelho logo depois de instalar; o guia avisa, e o projeto põe ali um valor local sem uso real.
- O repositório de teste dos CAs 4 a 6 e 13 precisa de um app mínimo com Postgres e Playwright; criá-lo é parte da verificação, não do código da fábrica.

## Histórico
- 2026-11-23: criação.
