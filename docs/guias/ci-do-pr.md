# CI do PR

A [ADR 0011](../adr/0011-verificacao-de-integracao-na-etapa.md) exige em todo projeto um CI que roda em cada PR: ele repete a verificação que a etapa `implementar` rodou, e é a evidência quando o ambiente da etapa não roda a verificação de integração. A fábrica entrega um modelo desse CI, `templates/workflows/ci.yml`, que o `/fabrica:setup` instala no projeto ([ADR 0019](../adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md)).

## O que o modelo roda
Em cada PR e em cada push na `main`, dois jobs em paralelo, num runner descartável do GitHub Actions:
- **`verificacao`:** `make lint` e `make test`;
- **`e2e`:** `make e2e`, o Playwright. Quando falha, o relatório fica no run como o artefato `playwright-report`, por 7 dias. Sem o alvo `e2e:` no `Makefile`, o job termina verde com a linha `ci: o Makefile não tem o alvo e2e; nada a rodar`.

Antes dos comandos, os dois jobs preparam o ambiente do mesmo jeito: o Node da versão do `.nvmrc`, o pnpm se há `pnpm-lock.yaml` (na versão do `packageManager`) e as dependências, pela primeira situação que valer: `pnpm install --frozen-lockfile`, `npm ci` ou `make install`. Sem lockfile nem alvo `install`, o job segue sem instalar e avisa no log.

O modelo só lê o repositório (`contents: read`), não usa nenhum secret e fixa cada ação pelo SHA do commit. Um push novo no mesmo PR cancela o run anterior.

## O contrato do `make e2e`
O CI não sobe banco nem app: ele só chama `make e2e`. O alvo precisa ser autossuficiente, como já é para a etapa local:
- sobe o banco pelo Docker Compose do projeto, em geral com um alvo `db-up` como dependência (`e2e: db-up`);
- sobe o app, pelo `webServer` do Playwright ou pelo Compose;
- roda o Playwright.

Se o `make e2e` passa na sua máquina a partir de um clone limpo, com o Docker ligado, ele passa no CI.

## Os valores de teste vêm do `.env.example`
Quando o repositório não tem `.env`, o CI copia o `.env.example` para `.env` antes dos comandos. Por isso, o `.env.example` precisa trazer valores locais que bastem para o `make test` e o `make e2e`: a URL do banco do Compose, a porta do app, um segredo de sessão qualquer. Esses valores não protegem nada real, e a regra de segredos continua: nenhuma chave de verdade entra no `.env.example`.

Um `.env.example` com valores vazios (ex.: `BETTER_AUTH_SECRET=`) deixa o CI vermelho logo depois de instalado. Preencha com um valor local sem uso real, como `segredo-local-de-teste`.

## Como instalar
Rode o `/fabrica:setup` no projeto. O passo "CI do PR" confere `.github/workflows/`:
- **sem nenhum workflow que rode em `pull_request`:** explica o modelo e pergunta se instala. Com o sim, grava `.github/workflows/ci.yml` na cópia de trabalho. Leve o arquivo por uma branch e um PR: o CI roda já no próprio PR que o adiciona;
- **com um CI que não roda o `make e2e`, num projeto que tem o alvo:** só avisa (veja abaixo);
- **com um CI que já roda tudo:** não faz nada.

O workflow do dispatcher (`agente.yml`) não conta como CI.

## Projeto que já tem CI
O setup nunca sobrescreve um workflow. Se o seu CI não roda o `make e2e`, escolha uma das saídas, por um PR:
- acrescente ao seu CI um job igual ao `e2e` do modelo (`templates/workflows/ci.yml` no repositório da fábrica);
- ou troque o seu CI pelo modelo: apague o workflow atual, rode o `/fabrica:setup` de novo e responda que instala.

Se o seu CI sobe o banco por `services:`, confira que o `make e2e` não tenta subir o mesmo banco pelo Compose na mesma porta.

## Adaptar a cópia
O `ci.yml` do projeto é seu: o setup não o compara com o modelo nem oferece atualização quando o modelo muda. Edite-o quando precisar, por exemplo:
- outros navegadores no Playwright: troque `chromium` nos dois passos de instalação;
- outra stack (Python, Go): troque a preparação do Node pela da sua stack e mantenha os `make`;
- variáveis que o `.env.example` não cobre: um bloco `env:` no job, sem secrets de produção.
