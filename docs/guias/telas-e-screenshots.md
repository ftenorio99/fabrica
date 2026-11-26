# Telas e screenshots

Numa issue com interface, a spec descreve cada tela e os estados dela, e o PR mostra um screenshot de cada tela e estado, no celular e no computador, para você aprovar junto com o código (F7 do [PRD](../prd.md)). Numa issue sem interface, nada disso acontece. A decisão de onde as imagens ficam e de quem as gera está no [ADR 0020](../adr/0020-screenshots-das-telas-numa-branch-orfa.md).

## O caminho de uma tela
1. **Triagem:** marca `Interface: sim` quando a issue muda algo que o usuário final vê. Uma issue com interface não cabe no [atalho](../fluxo.md#atalho), porque a descrição das telas é parte da spec completa.
2. **Spec:** a seção `## Telas` traz uma subseção por tela, com a rota, o que aparece, as ações e a tabela de estados (`padrao` sempre; `vazio`, `erro` e `carregando` quando a tela os tem), cada estado com `Captura: sim` ou `não — <motivo>`. Um esboço que você anexar à issue entra como referência. Numa issue sem interface, a seção diz `nenhuma (Interface: não)`. As regras de preenchimento estão em [`skills/spec/SKILL.md`](../../skills/spec/SKILL.md).
3. **Implementar:** cria no projeto o alvo `make screenshots` (pelo modelo abaixo), se ainda não existe, e o roda depois do `make e2e`.
4. **Revisor:** roda o `make screenshots` e confere que cada tela e estado com `Captura: sim` tem o par `celular` e `computador`. Um arquivo que falta é achado `importante`.
5. **Revisar:** publica as imagens do head do PR e põe a tabela na seção `## Telas` do corpo do PR, logo depois dos critérios de aceite. A cada head novo, a seção é trocada pela do head novo.
6. **Você:** confere as telas no PR. Um pedido de mudança visual segue como qualquer pedido no PR: ajuste, se cabe na spec; mudança de escopo, se muda uma tela da spec.

## O contrato do `make screenshots`
O alvo roda o Playwright e grava em `screenshots/`, na raiz do projeto, um PNG por tela, estado com `Captura: sim` e dispositivo, com o nome:

```
<tela>--<estado>--<celular|computador>.png
```

A tela e o estado são os ids da spec: minúsculas, letras, números e hífen simples (ex.: `novo-evento--padrao--celular.png`). Um nome fora desse padrão faz a publicação recusar a pasta inteira. O alvo é autossuficiente, como o `make e2e` ([guia do CI](ci-do-pr.md#o-contrato-do-make-e2e)): sobe o banco e o app que precisa. A pasta `screenshots/` fica no `.gitignore`.

## Dispositivos
Fixos pela fábrica, pelos presets do DevTools do Chrome, só no Chromium e com a página inteira:

| Dispositivo | Preset | Viewport | Escala |
|---|---|---|---|
| `celular` | iPhone 12 Pro | 390 × 844, `isMobile` e `hasTouch` | 3 |
| `computador` | Laptop L | 1440 × 900 | 1 |

O celular é emulado no Chromium, e não pelo `devices['iPhone 12 Pro']` do Playwright, que usa o WebKit: o CI só instala o Chromium.

## Modelo para o projeto
Um projeto Next.js com Playwright (`@playwright/test`) e o `playwright.config.ts` do `make e2e`. Adapte os caminhos ao projeto.

**`playwright.telas.config.ts`**, uma configuração só para as telas, que reaproveita a do e2e (o `webServer`, a `baseURL`):

```ts
import { defineConfig } from '@playwright/test';
import base from './playwright.config';

export default defineConfig({
  ...base,
  testDir: './e2e/telas',
  testIgnore: [],
  reporter: 'list',
  projects: [
    {
      name: 'celular',
      use: {
        ...base.use,
        browserName: 'chromium',
        viewport: { width: 390, height: 844 },
        deviceScaleFactor: 3,
        isMobile: true,
        hasTouch: true,
      },
    },
    {
      name: 'computador',
      use: {
        ...base.use,
        browserName: 'chromium',
        viewport: { width: 1440, height: 900 },
        deviceScaleFactor: 1,
      },
    },
  ],
});
```

No `playwright.config.ts` do e2e, acrescente `testIgnore: '**/telas/**'`, para o `make e2e` não rodar os testes das telas.

**`e2e/telas/novo-evento.spec.ts`**, um teste por tela e estado da spec, com o nome do projeto (`celular` ou `computador`) no nome do arquivo:

```ts
import { test, type Page, type TestInfo } from '@playwright/test';

async function shot(page: Page, testInfo: TestInfo, screen: string, state: string) {
  await page.screenshot({
    path: `screenshots/${screen}--${state}--${testInfo.project.name}.png`,
    fullPage: true,
  });
}

// Data e dados fixos: o screenshot não muda de uma rodada para outra.
test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-01-15T10:00:00-03:00'));
});

test('novo-evento padrao', async ({ page }, testInfo) => {
  // Monte aqui os dados da coluna "Como chegar" da spec (login, registros).
  await page.goto('/eventos/novo');
  await shot(page, testInfo, 'novo-evento', 'padrao');
});

test('novo-evento erro', async ({ page }, testInfo) => {
  await page.goto('/eventos/novo');
  await page.getByRole('button', { name: 'Salvar' }).click();
  await shot(page, testInfo, 'novo-evento', 'erro');
});
```

**`Makefile`**:

```make
screenshots: db-up
	pnpm exec playwright test -c playwright.telas.config.ts
```

**`.gitignore`**: `screenshots/`.

## Onde as imagens ficam
A etapa `revisar` grava os PNGs na branch órfã `fabrica-telas` do próprio repositório, em `issue-<nº>/<sha curto do head>/`, pelo `scripts/publish-screenshots.sh` da fábrica. O corpo do PR mostra as imagens por links `https://github.com/<dono>/<repo>/raw/<commit>/...`, que o GitHub exibe a quem tem acesso ao repositório, inclusive num repositório privado.

A branch não tem nenhum commit da `main`, e o squash do PR não leva as imagens para a `main`. Ela cresce a cada publicação, sem limpeza automática; para apagar as imagens de issues antigas, remova as pastas `issue-<nº>/` numa cópia da branch e faça push dela.

## Quando a etapa não roda o Playwright
Se o `make screenshots` falha na etapa com uma assinatura de ambiente (por exemplo, o Chromium que não baixa), ele fica pendente para o CI, como o `make e2e` ([ADR 0011](../adr/0011-verificacao-de-integracao-na-etapa.md)). O job `e2e` do [modelo do CI](ci-do-pr.md) roda o `make screenshots` depois do `make e2e`, quando o `Makefile` tem o alvo, e guarda `screenshots/` como o artefato `telas`, por 7 dias. O `revisar` baixa o artefato do run do head, publica as imagens e diz na seção `## Telas` que elas foram geradas pelo CI, com o link do run.

O token do agente precisa ler o Actions para baixar o artefato, como já lê os runs ([guia de isolamento](isolamento-do-agente.md#token-fine-grained)).

Sem o artefato, o PR fica em rascunho, com a seção `## Telas` "pendente", e a issue recebe `escalonado` e um comentário com as duas saídas: acrescentar ao CI os passos abaixo, ou rodar `! make screenshots` na sua máquina e depois `/fabrica:revisar <nº>`.

## Cópia antiga do ci.yml
O `/fabrica:setup` nunca atualiza um `ci.yml` já copiado ([ADR 0019](../adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md)). Num projeto com a cópia anterior a estas telas, acrescente ao job `e2e`, por um PR:

1. No passo `Confere o alvo e2e`, depois do `if` que grava `tem=`, as linhas que gravam `telas=`:

   ```yaml
             if [ -f Makefile ] && grep -q '^screenshots:' Makefile; then
               echo "telas=sim" >> "$GITHUB_OUTPUT"
             else
               echo "telas=nao" >> "$GITHUB_OUTPUT"
             fi
   ```

2. Depois do passo `Roda o make e2e`, e antes do upload do `playwright-report`, os dois passos:

   ```yaml
         - name: Roda o make screenshots
           if: steps.alvo.outputs.tem == 'sim' && steps.alvo.outputs.telas == 'sim'
           run: |
             rm -rf screenshots
             make screenshots

         - name: Guarda as telas
           if: steps.alvo.outputs.tem == 'sim' && steps.alvo.outputs.telas == 'sim'
           uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
           with:
             name: telas
             path: screenshots/
             retention-days: 7
             if-no-files-found: ignore
   ```

O `permissions` continua só `contents: read`: o CI só gera o artefato, e quem publica é a etapa de agente.
