# SPEC-99: Estudo: dispatcher da Fase 1 com a claude-code-action disparada pela label agente

**Issue:** #99 · **PRD:** F4 (item 4 do fatiamento, M2) · **Classe:** documentacao · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-18

## Contexto
A F4 do PRD pede que aplicar `agente` numa issue dispare a etapa de agente no GitHub Actions, com o plugin instalado no job e sem sessão local. O item 4 do fatiamento é o estudo que decide como: o caminho de execução (`anthropics/claude-code-action` ou o CLI), o runner e a autenticação. Duas "Perguntas em aberto" do PRD (runner e autenticação) remetem a este estudo. Ele destrava a #105 (workflow), a #106 (isolamento do job) e a #108 (instalação pelo `/fabrica:setup`). A dependência, #93, está fechada, e o isolamento local hoje segue a [ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md).

## Objetivo
Existe a `docs/adr/0015-dispatcher-no-github-actions.md`, que registra o caminho de execução, o runner e a autenticação do dispatcher com as alternativas comparadas, com os fatos conferidos na documentação atual e com o que a #105, a #106 e a #108 precisam respeitar. As duas perguntas em aberto do PRD passam a apontar para ela.

## Comportamento esperado
A entrega é só documentação: nenhum workflow, script ou skill muda.

1. O implementador confere na documentação atual cada fato que a ADR cita (seção "Fatos a conferir"), registrando a fonte de cada um.
2. Se um fato conferido contradiz uma decisão desta spec, o implementador não troca a decisão sozinho: pergunta na issue, aplica `precisa-info` e para, como diz a regra "não invente requisitos".
3. Com os fatos confirmados, ele escreve a ADR 0015 com as decisões desta spec, atualiza o PRD e o manual e tira a issue do estado de ideia.

### Fatos a conferir
Cada linha vira uma linha da tabela "Fatos conferidos" da ADR, com a fonte (URL e data da consulta, ID do Context7 com a versão ou `<comando> --help` com a versão).

| Fato | Onde conferir | Resultado na data da spec |
|---|---|---|
| A `claude-code-action@v1` aceita `label_trigger`, `plugin_marketplaces`, `plugins`, `prompt`, `claude_args`, `anthropic_api_key` e `claude_code_oauth_token` | `/anthropics/claude-code-action/v1.0.248`, `docs/usage.md` | confirmado |
| Com `label_trigger` e sem `prompt`, a action entra no modo interativo (*tag mode*), que cria um comentário de acompanhamento com caixas de progresso | `docs/experimental.md` da mesma versão | confirmado |
| Sem `github_token`, a action usa o token do GitHub App da Anthropic (OIDC); com `github_token`, usa o token informado | `CLAUDE.md` e `docs/setup.md` da mesma versão | confirmado |
| Eventos criados com o `GITHUB_TOKEN` do job não disparam outros workflows (exceto `workflow_dispatch` e `repository_dispatch`); eventos criados com um PAT ou um token de GitHub App disparam | documentação do GitHub Actions ("Triggering a workflow from a workflow") | a conferir |
| Os termos de uso permitem, ou não, usar a assinatura (`claude setup-token` / `claude_code_oauth_token`) num job automatizado | termos de uso e documentação oficiais da Anthropic | a conferir |
| As flags `-p`, `--permission-mode` (com `auto`), `--output-format`, `--model` e `--max-budget-usd` existem no CLI; `--max-turns` não aparece no `claude --help` 2.1.327 | `claude --help` da versão instalada | confirmado para 2.1.327; reconferir |
| Limites e custo dos runners hospedados pelo GitHub para repositório privado (minutos inclusos no plano do usuário) | documentação de cobrança do GitHub Actions | a conferir |

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `docs/adr/0015-dispatcher-no-github-actions.md` existe, segue `skills/spec/adr-template.md`, tem status `aceito`, data e origem `issue #99`, e as seções Contexto, Decisão, Alternativas consideradas e Consequências preenchidas, sem marcador `<...>`. | manual — leitura do diff na revisão |
| CA2 | A ADR tem a tabela "Fatos conferidos" com uma linha por fato da seção "Fatos a conferir" desta spec, cada uma com o resultado e a fonte (URL com data, ID do Context7 com versão ou comando de ajuda com versão). Nenhuma linha fica como "a conferir". | manual — leitura do diff na revisão |
| CA3 | **Caminho de execução:** a ADR registra a decisão D1 desta spec e compara as três opções (action com `label_trigger` no modo interativo, action com `prompt` no modo de automação, CLI direto pelo `scripts/stage-model.sh`), dizendo para cada uma como instala o plugin, como escolhe o modelo da etapa (ADR 0013) e se cria comentários fora do protocolo de marcadores de `skills/status/estados.md`. | manual — leitura do diff na revisão |
| CA4 | **Runner:** a ADR registra a decisão D2 e compara runner hospedado pelo GitHub e self-hosted na Hetzner por quatro critérios: custo para o uso do piloto, manutenção, se a máquina é descartada a cada job e o que cabe à #106 para restringir a rede. | manual — leitura do diff na revisão |
| CA5 | **Autenticação:** a ADR registra a decisão D3 com a fonte dos termos consultada (URL e data). Se a fonte oficial não permitir de forma explícita o uso da assinatura num job automatizado, ou se não for encontrada, a escolha é a API key com `--max-budget-usd` por execução, e a ADR diz isso. | manual — leitura do diff na revisão |
| CA6 | **Sem cascata:** a ADR diz qual token faz as escritas do job (comentários, labels, push e PR), se os eventos dele disparam workflows (pelo fato conferido do CA2) e qual filtro do workflow impede uma nova execução a partir de um gesto do agente, lembrando que agente e usuário usam a mesma conta do GitHub. A ADR também diz o efeito dessa escolha sobre o CI do PR aberto pelo agente (um push feito com o `GITHUB_TOKEN` não dispara o CI). | manual — leitura do diff na revisão |
| CA7 | **Headless:** a ADR diz o modo de permissão do job e o que acontece quando o modo `auto` aborta sem usuário: a etapa termina com erro, a `em-andamento` fica até expirar (ADR 0003) e o motivo vai para a issue, a cargo da #105. Também diz se há teto de turnos, com a flag conferida no `claude --help` da versão usada; se `--max-turns` não existir, a ADR registra isso e usa só o `--max-budget-usd` (com API key) e o tempo-limite do job (`timeout-minutes`). | manual — leitura do diff na revisão |
| CA8 | A seção Consequências da ADR tem uma linha para cada uma das issues #105, #106 e #108 com o que ela precisa respeitar (ex.: o filtro de evento, os secrets que o job espera, o ponto onde o isolamento entra). | manual — leitura do diff na revisão |
| CA9 | Em `docs/prd.md`, as perguntas em aberto "Runner" e "Autenticação dos agentes" dizem a decisão e apontam para a ADR 0015. O resto do PRD não muda, e a tabela "Mudanças" não ganha linha, porque nenhuma funcionalidade nem item do fatiamento muda. | manual — leitura do diff na revisão |
| CA10 | O diff da branch não cria nem altera arquivos em `.github/`, `scripts/`, `skills/`, `hooks/`, `agents/`, `agy-agents/`, `opencode/` nem `.claude-plugin/` (a versão do plugin não sobe, porque nenhum comportamento muda). | manual — `git diff --stat origin/main...HEAD` na revisão |
| CA11 | A issue #99 fica sem a label `ideia` e sem a nota "Ideia para estudo, fora do escopo atual" do início do corpo; o resto do corpo, inclusive o marcador `<!-- fabrica:backlog item=4 -->`, continua igual. | manual — `gh issue view 99 --json labels,body` depois da etapa de implementação |

## Fora de escopo
- Escrever o workflow, mesmo de exemplo: é a #105.
- Restringir a rede do job, criar o token fine-grained e decidir se o `sbx` roda dentro do runner: é a #106. A ADR só registra a interface com ela.
- Retomada por evento (resposta, `spec-aprovada`, comentário no PR, checklist): é a #107. A ADR trata só o disparo pela label `agente`, mas o filtro anti-cascata do CA6 tem de servir de base para ela.
- Instalar o dispatcher pelo `/fabrica:setup`: é a #108.
- Telemetria por OTLP e métricas persistentes: é a F9. A ADR pode citar a `CLAUDE_CODE_ENABLE_TELEMETRY` como caminho, sem decidir.
- Teto de gasto mensal: o PRD o deixa para depois das primeiras semanas do dispatcher.

## Desenho técnico
**Arquivos e módulos:**
- `docs/adr/0015-dispatcher-no-github-actions.md` (novo): a ADR, a partir de `skills/spec/adr-template.md`, com a tabela "Fatos conferidos" acrescentada depois do Contexto.
- `docs/prd.md`: as duas linhas de "Perguntas em aberto" (runner e autenticação).
- `docs/README.md`: não muda; ele já remete a `docs/adr/`.
- Issue #99: `gh issue edit 99 --remove-label ideia` e `gh issue edit 99 --body-file <arquivo>` com o corpo sem a nota.

**Dados:** nenhum.

**Interfaces:** nenhuma interface nova. A ADR cita, como referência para a #105, a assinatura que o job vai chamar: `bash scripts/stage-model.sh run <etapa> <nº> [label...]` (D1).

**Decisões:**
- **D1 — Caminho de execução: CLI direto no job, chamando a mesma `scripts/stage-model.sh run` do `/fabrica:avancar`**, com o plugin instalado por `claude plugin marketplace add ftenorio99/fabrica` e `claude plugin install fabrica@fabrica`. Justificativa: reaproveita o roteamento de modelo da ADR 0013 e o protocolo de marcadores sem nenhuma camada a mais, e cumpre o requisito "um fluxo só" do PRD. Alternativas descartadas: a action com `label_trigger` no modo interativo, porque cria o próprio comentário de acompanhamento, fora dos marcadores `<!-- fabrica:` que o `/fabrica:status` lê; e a action com `prompt` no modo de automação, que funciona, mas repete a escolha de modelo em `claude_args` e por padrão escreve com o token do App da Anthropic, que a #106 trocaria pelo token fine-grained de qualquer forma.
- **D2 — Runner: hospedado pelo GitHub (`ubuntu-latest`) no M2; a Hetzner self-hosted fica para quando os minutos ou o tempo de fila medidos pelo `/fabrica:metricas` pedirem.** Justificativa: a VM é descartada a cada job, o que já cumpre parte da F1, e não há máquina para manter durante a validação no piloto. Alternativa descartada: self-hosted na Hetzner já no M2, porque exige manter e limpar a máquina entre jobs e isolar o runner antes do primeiro job.
- **D3 — Autenticação: API key (`ANTHROPIC_API_KEY` como secret do repositório) com `--max-budget-usd` por execução, salvo se a fonte oficial da Anthropic permitir de forma explícita a assinatura em job automatizado; nesse caso, `CLAUDE_CODE_OAUTH_TOKEN`.** Justificativa: é a mitigação que o PRD já prevê para o risco de alto impacto da assinatura, e o teto por execução só funciona cobrando por API. Alternativa descartada: escolher a assinatura sem a conferência, que o próprio risco do PRD proíbe.
- **D4 — Disparo: evento `issues` com `types: [labeled]` e filtro `github.event.label.name == 'agente'`, com grupo de concorrência por issue.** Justificativa: a label `agente` só é aplicada pelo usuário (portão do PRD), então esse evento não tem cascata, e a concorrência por issue é requisito não funcional do PRD. Alternativa descartada: o `label_trigger` da action, preso ao modo interativo da D1.
- Entrega só da ADR, sem workflow nem código (recomendação da triagem) — o item 4 do fatiamento é "Estudo do dispatcher ... com ADR", e o workflow é o item 5 (#105). Alternativa descartada: entregar já um workflow de exemplo, que invade o escopo da #105.
- A issue segue na fábrica apesar da nota "não aplicar `agente` até decidir" do corpo (recomendação da triagem) — o PRD a põe no M2 com dependência só da #93, já fechada, e o usuário aplicou `agente`. Alternativa descartada: tratar a nota como vigente e pausar a issue. Por isso o CA11 tira a label `ideia` e a nota.
- Os pontos em aberto da issue (runner e autenticação) viram critérios de decisão da ADR, e o isolamento do job fica na #106, com a ADR só registrando a interface (recomendação da triagem) — esse é o objeto do estudo. Alternativa descartada: decidir o isolamento do job aqui, que é escopo da #106.

**Fontes da documentação:**
- anthropics/claude-code-action v1.0.248 — Context7 `/anthropics/claude-code-action/v1.0.248` (`docs/usage.md`, `docs/experimental.md`, `docs/setup.md`, `CLAUDE.md`).
- Claude Code CLI 2.1.327 — `claude --help`, `claude plugin --help`.
- GitHub Actions (eventos com `GITHUB_TOKEN`, cobrança de runners) — não verificada nesta etapa; o CA2 exige a conferência na implementação.
- Termos de uso da assinatura da Anthropic — não verificada nesta etapa; o CA5 exige a conferência.
- gh 2.104.0 — `gh issue edit --help` (`--remove-label`, `--body-file`), `gh issue view --help` (campos `labels`, `body`).

**ADR:** `docs/adr/0015-dispatcher-no-github-actions.md`, escrita na implementação (é a entrega da issue).

## Testes
Não há teste automatizado: a entrega é documentação. A revisão confere o CA1 ao CA9 pela leitura do diff, o CA10 com `git diff --stat origin/main...HEAD` e o CA11 com `gh issue view 99 --json labels,body`. Os testes existentes (`bash scripts/test-*.sh`) não são afetados, porque nenhum script muda.

## Passos de produção
nenhum

## Riscos e dúvidas
- A documentação da action e do Actions muda rápido; os fatos valem na data da consulta registrada na ADR, e a #105 reconfere ao escrever o workflow.
- Se a conferência mostrar que o `stage-model.sh run` depende de algo que não existe no runner (ex.: o log da sessão para a linha de custo, que sai como `tokens=nao-medido`), a ADR registra a limitação como consequência para a #105, sem mudar a D1.
- Com a D1, a action não é usada, apesar do título da issue. Se o usuário preferir a action, a D1 muda para "action com `prompt` no modo de automação" antes da aprovação.

## Histórico
- 2026-11-18: criação.
