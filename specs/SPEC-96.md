# SPEC-96: Runbook de lançamento gerado pelo agente antes da produção

**Issue:** #96 · **PRD:** F8 (com F2 e F3) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-18

## Contexto
A F8 do [PRD](../docs/prd.md) pede que, antes da primeira ida de um projeto para produção, o agente gere numa issue um runbook com checklist (migrações com backup, chaves de teste, isolamento de dados, teste em produção) e confira o que dá para conferir. O usuário executa os passos de produção. A F2 e a [ADR 0006](../docs/adr/0006-producao-fora-do-alcance-do-agente.md) deixam produção fora do alcance do agente e dizem que o runbook parte da seção "Passos de produção" das specs. A F3 e a [ADR 0012](../docs/adr/0012-acao-externa-com-checklist.md) já definem como o usuário executa passos fora do GitHub e os marca numa checklist. O primeiro uso previsto é o M8 do kairo.

## Objetivo
Existe a etapa manual `/fabrica:lancamento`, que confere o projeto sem tocar em produção, abre uma issue de runbook com a checklist da ação externa e fecha essa issue quando o usuário marca todos os passos.

## Comportamento esperado
A etapa roda no clone principal do projeto, na branch padrão atualizada (`git switch <padrão> && git pull`). Ela não cria branch nem worktree e não faz commit: o resultado fica só no GitHub.

**Sem argumento: gerar o runbook.**
1. Procura as issues de runbook do repositório: `gh search issues "fabrica:lancamento" --repo <dono>/<repo> --match body --json number,state,body,url`, e fica só com as que têm `<!-- fabrica:lancamento -->` na primeira linha do corpo. Nas fechadas, lê o motivo com `gh issue view <nº> --json stateReason`.

   | Situação | O que fazer |
   |---|---|
   | Há issue de runbook aberta | Não cria outra. Diz no chat o link e que a retomada é `/fabrica:lancamento <nº>`. Para. |
   | Há issue de runbook fechada com `stateReason` `COMPLETED` | O primeiro lançamento já aconteceu. Diz isso no chat, com o link, e para sem escrever no GitHub. |
   | Só há issues de runbook fechadas como `NOT_PLANNED` (descartadas), ou nenhuma | Segue. |

2. Faz as conferências da tabela abaixo, só no repositório e no ambiente de dev ou homologação. Cada uma tem um de três resultados: ✅ passou, ❌ falhou ou ⚠️ não deu para conferir, sempre com uma frase de motivo.

   | # | Conferência | Como |
   |---|---|---|
   | V1 | Padrões de produção | `.fabrica/producao.txt` existe e tem pelo menos uma linha `host`. Sem o arquivo ou sem `host`: ❌. |
   | V2 | `.env` de produção fora do git | `git ls-files` não lista `.env.production` nem `.env.production.local`, e o `.gitignore` os cobre (`git check-ignore`). Arquivo versionado: ❌. Não ignorado, mas ausente: ⚠️. |
   | V3 | Chaves de teste na configuração de produção | Procura `sk_test_`, `pk_test_`, `rk_test_`, `localhost`, `127.0.0.1`, `homolog` e `staging` nos arquivos versionados de configuração de deploy: `.env.production.example`, `vercel.json`, `netlify.toml`, `fly.toml`, `render.yaml`, `Dockerfile*`, `docker-compose*.prod*.yml` e `.github/workflows/*deploy*`. Achado: ❌, com o arquivo e a linha, sem repetir valor que pareça segredo. Nenhum desses arquivos no projeto: ⚠️. |
   | V4 | Variáveis que o provedor precisa ter | Lista os nomes das variáveis do `.env.example` (só os nomes). Sem `.env.example`: ⚠️. Não é ❌ em nenhum caso: os nomes viram o passo P2. |
   | V5 | Migrações em ordem | Lista os arquivos de migração na ordem de aplicação, procurando em `prisma/migrations/`, `supabase/migrations/`, `drizzle/`, `migrations/`, `db/migrate/` e `alembic/versions/`. Se o `AGENTS.md` (ou o `CLAUDE.md`) do projeto documenta um comando de status das migrações contra dev, roda-o e mostra se há migração pendente em dev. Nenhuma pasta encontrada: ⚠️ "projeto sem migrações encontradas". |
   | V6 | Testes | Roda o comando de teste do projeto (o do `AGENTS.md`, senão `make test`) contra dev. Falha: ❌ com o resumo. Sem comando: ⚠️. |
   | V7 | Isolamento de dados | Procura nos testes nomes ou descrições com isolamento entre usuários (`isolation`, `isolamento`, `other user`, `outro usuário`, `rls`, `forbidden`, `403`, `404` com outro dono). Achou: ✅ com os arquivos. Não achou: ⚠️ "nenhum teste de isolamento encontrado" e a recomendação de abrir uma issue `feat` para ele. |
   | V8 | Ponta a ponta | Roda o comando de e2e do projeto (o do `AGENTS.md`, senão `make e2e`) contra dev ou homologação. Falha: ❌. Sem comando: ⚠️. |
   | V9 | Trabalho em andamento | Conta as issues abertas com `agente` no repositório. Mais de zero: ⚠️ "o runbook cobre só as specs na branch padrão; N issues seguem no fluxo". |

3. Monta os passos do usuário, nesta ordem:
   - **Bloqueios:** um item `- [ ] Resolver antes de seguir: <V#> — <motivo>` para cada ❌.
   - **P1 Backup:** fazer o backup do banco de produção e conferir que ele restaura.
   - **P2 Chaves:** conferir no provedor que as variáveis de V4 têm valores de produção e não de teste, citando só os nomes e onde cadastrar.
   - **P3 Migrações:** aplicar em produção as migrações de V5, em ordem, com o comando do projeto. Sem migrações em V5, o item não entra.
   - **Passos das specs:** um item por linha da seção "Passos de produção" de cada `specs/SPEC-*.md` da branch padrão, em ordem crescente do número da spec, com `(SPEC-<nº>)` no fim. Seções com "nenhum", seções ausentes e specs sem a seção não geram item.
   - **P4 Isolamento:** em produção, com duas contas, conferir que a conta A não lê nem altera dados da conta B (pela URL com o ID de B e pela API).
   - **P5 Ponta a ponta adversarial:** em produção, percorrer o fluxo principal e os casos adversariais: ID de outro usuário na URL, entrada inválida ou vazia, sessão expirada e duplo envio.
4. Cria a issue de runbook com `gh issue create --title "Lançamento: runbook da primeira ida para produção" --label acao-externa --body-file <arquivo>`. O corpo começa com `<!-- fabrica:lancamento -->` e traz a tabela das conferências V1 a V9 com resultado e motivo, a data e o commit da branch padrão conferido.
5. Publica na issue nova o comentário de ação, no formato de [acao-externa.md](../skills/status/acao-externa.md), com o marcador `<!-- fabrica:acao etapa=lancamento -->`, o **Por que** ("primeira ida para produção; o agente não alcança produção") e os passos do item 3. A linha de custo vai no fim desse comentário. A instrução final diz para rodar `/fabrica:lancamento <nº>` com todos marcados.
6. Diz no chat o link da issue, quantos ❌ e ⚠️ saíram e quantos passos há.

**Com o número da issue de runbook: retomar.**
- A issue precisa ter `<!-- fabrica:lancamento -->` na primeira linha do corpo e estar aberta. Senão, diz no chat que não é uma issue de runbook aberta e para.
- Lê o estado com `gh api repos/<dono>/<repo>/issues/<nº>/comments --paginate --slurp > <arquivo>` e `python3 <diretório base>/../../scripts/acao-status.py --lancamento <arquivo>`:

  | Situação | O que fazer |
  |---|---|
  | `estado=pendente`, sem comentário do usuário depois do comentário de ação | Nada na issue. Diz no chat quantos itens faltam e para. |
  | `estado=pendente`, com comentário do usuário depois do comentário de ação | Lê o comentário. Se der para seguir por outro caminho, publica um novo comentário de ação só com os passos que faltam, ajustados. Se não der, comenta as opções com uma recomendação. Nos dois casos, mantém `acao-externa`. |
  | `estado=concluida` | Remove `acao-externa`, comenta `<!-- fabrica:lancamento -->` com "Lançamento concluído", a data e o número de passos, com a linha de custo, e fecha a issue com `gh issue close <nº> --reason completed`. |
  | `sem-comentario`, `sem-itens` ou `etapa-invalida` | Inconsistência: diz no chat o que o script devolveu e para. |

**`acao-status.py --lancamento`:** com a opção, a única etapa válida no marcador é `lancamento`; sem ela, o script se comporta como hoje (só `implementar` e `revisar`). Assim uma issue de agente com `etapa=lancamento` continua sendo `etapa-invalida`.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `acao-status.py --lancamento` devolve `estado=pendente etapa=lancamento` para um comentário `<!-- fabrica:acao etapa=lancamento -->` com 1 de 3 itens marcados e `estado=concluida` com os 3 marcados. | unitário — casos novos em `scripts/test-acao-status.sh` |
| CA2 | Sem a opção, o mesmo comentário com `etapa=lancamento` sai `estado=etapa-invalida`; com a opção, um comentário `etapa=implementar` sai `estado=etapa-invalida`. Os casos existentes do teste continuam passando. | unitário — `bash scripts/test-acao-status.sh` |
| CA3 | Rodar `/fabrica:lancamento` sem argumento num repositório sem issue de runbook cria uma issue com `<!-- fabrica:lancamento -->` na primeira linha do corpo, a label `acao-externa`, a tabela V1 a V9 (cada linha com ✅, ❌ ou ⚠️ e motivo) e um comentário `<!-- fabrica:acao etapa=lancamento -->` com os itens P1, P2, P4 e P5 e a linha de custo. | manual — `claude --plugin-dir <clone>` na branch, no próprio fabrica; a issue de teste é fechada como `not planned` no fim, com um comentário dizendo que era teste |
| CA4 | Cada ❌ das conferências vira um item "Resolver antes de seguir" antes do P1. No fabrica (sem `.fabrica/producao.txt` com `host`), V1 sai ❌ e o primeiro item é o bloqueio de V1. | manual — mesma execução do CA3 |
| CA5 | Uma spec da branch padrão com dois passos na seção "Passos de produção" gera dois itens terminados em `(SPEC-<nº>)`, em ordem crescente de número; specs com "nenhum" ou sem a seção não geram item. | manual — mesma execução do CA3, conferindo contra `grep -A5 "## Passos de produção" specs/SPEC-*.md` |
| CA6 | Com uma issue de runbook aberta, `/fabrica:lancamento` sem argumento não cria outra e mostra o link e o comando de retomada. | manual — `claude --plugin-dir <clone>`, com a issue de teste do CA3 ainda aberta |
| CA7 | Com uma issue de runbook fechada como `completed`, `/fabrica:lancamento` sem argumento para sem escrever no GitHub e diz que o primeiro lançamento já aconteceu. | manual — `claude --plugin-dir <clone>`, logo depois do CA10, com a issue de teste fechada como `completed` |
| CA8 | Uma issue de runbook fechada como `not planned` não bloqueia: `/fabrica:lancamento` sem argumento cria uma issue nova. | manual — `claude --plugin-dir <clone>`, depois de fechar a issue do CA3 como `not planned` |
| CA9 | `/fabrica:lancamento <nº>` com item desmarcado e sem comentário do usuário não escreve na issue e diz quantos itens faltam. | manual — `claude --plugin-dir <clone>`, na issue de teste |
| CA10 | `/fabrica:lancamento <nº>` com todos os itens marcados remove `acao-externa`, publica o comentário `<!-- fabrica:lancamento -->` "Lançamento concluído" e fecha a issue como `completed`. | manual — `claude --plugin-dir <clone>`, na issue de teste com os itens marcados |
| CA11 | `/fabrica:lancamento <nº>` numa issue sem o marcador no corpo para sem escrever no GitHub. | manual — `claude --plugin-dir <clone>`, com o número de uma issue comum do fabrica |
| CA12 | Nenhum comando da etapa alcança produção: a skill não roda migração, seed nem e2e contra produção, e o texto dela manda usar só dev ou homologação. | manual — leitura do `SKILL.md` no PR, conferindo que todo comando que roda migração ou teste cita dev ou homologação |
| CA13 | O `/fabrica:status` lista a issue de runbook com `acao-externa` pendente na seção "Ações externas" e, com a checklist concluída, mostra `/fabrica:lancamento <nº>` em "Esperando agente". | manual — `claude --plugin-dir <clone>`, rodando `/fabrica:status fabrica` com a issue de teste pendente e depois concluída |
| CA14 | O adaptador do OpenCode registra 13 skills e 13 comandos, inclusive `fabrica:lancamento`. | e2e — `bash opencode/test-adapter.sh` na VM do `sbx` com o agente `opencode` |

## Fora de escopo
- Runbook para as idas seguintes a produção (cada release): depois do primeiro lançamento a etapa para. Fica para outra issue, se o uso pedir.
- Rodar qualquer coisa em produção, ler os secrets do provedor ou ler `.env.production*` (F2, ADR 0006).
- Disparo pelo `/fabrica:avancar` ou pelo dispatcher do GitHub Actions: a issue de runbook não tem `agente` e fica fora da tabela de estados.
- Criar o teste de isolamento que faltar: a etapa só aponta a falta (V7).
- Medir a etapa no `/fabrica:metricas`.

## Desenho técnico
**Arquivos e módulos:**
- `skills/lancamento/SKILL.md` (novo): a etapa, com `disable-model-invocation: true`, as duas formas (gerar e retomar), as conferências, o check do `gh`, a linha de custo pelo `scripts/stage-usage.py --stage lancamento` e as regras de comentário por arquivo, como nas outras skills.
- `skills/lancamento/runbook.md` (novo): os modelos do corpo da issue de runbook, do comentário de ação com os passos P1 a P5 e do comentário de conclusão.
- `scripts/acao-status.py`: opção `--lancamento`, que troca o conjunto de etapas válidas por `{"lancamento"}`.
- `scripts/test-acao-status.sh`: casos do CA1 e do CA2.
- `skills/status/estados.md`: seção nova "Lançamento", fora da tabela de estados como a seção "Backlog", com o marcador do corpo, os dois estados (Runbook pendente, do usuário; Runbook concluído, do agente, com `/fabrica:lancamento <nº>`) e as inconsistências; `lancamento` na coluna "Quem aplica" da `acao-externa`; o marcador `<!-- fabrica:lancamento -->` na lista de comentários do agente.
- `skills/status/acao-externa.md`: a etapa `lancamento` como terceira etapa que usa o comentário de ação, só em issue de runbook e lida com `--lancamento`.
- `skills/status/SKILL.md`: busca das issues de runbook abertas (`gh search issues "fabrica:lancamento" --owner <dono> --label acao-externa --state open --match body --json repository,number,title,body,url -- -label:agente`, filtrando pelo marcador na primeira linha) e encaixe nas seções "Ações externas" e "Esperando agente".
- `docs/comandos.md` (seção nova), `docs/fluxo.md` (onde o lançamento entra), `docs/guias/lancamento.md` (guia novo: quando rodar, o que o agente confere, o que você faz) e `docs/README.md` (linha do guia e "13 skills").
- `opencode/README.md` e `opencode/test-adapter.sh`: as contagens de 12 para 13 skills e comandos.
- `.claude-plugin/plugin.json`: `version` de 0.42.0 para 0.43.0.

**Dados:** nenhum.

**Interfaces:**
- `/fabrica:lancamento` (gera) e `/fabrica:lancamento <nº da issue de runbook>` (retoma). O argumento é só o número ([ADR 0008](../docs/adr/0008-texto-externo-fora-do-prompt.md)).
- `python3 scripts/acao-status.py [--lancamento] <comentários.json>`: mesma saída de hoje.
- Marcadores: `<!-- fabrica:lancamento -->` na primeira linha do corpo da issue de runbook e dos comentários da etapa; `<!-- fabrica:acao etapa=lancamento -->` no comentário de ação.

**Decisões:**
- Uma skill `/fabrica:lancamento`, com o modelo do runbook ao lado do `SKILL.md`, e não só um template em `docs/guias/` — a F8 pede que o agente gere o runbook e confira o que dá para conferir, o que um template estático não faz. Alternativa descartada: só o template em `docs/guias/`. (recomendação da triagem)
- Disparo manual pelo usuário, fora do `/fabrica:avancar` — a F8 é "antes da primeira ida para produção", um momento que só o usuário decide, e os passos de produção são dele (F2, F8). Alternativa descartada: o dispatcher aplicar a etapa sozinho em algum marco. (recomendação da triagem)
- O runbook parte dos itens de base da issue mais a seção "Passos de produção" de cada spec da branch padrão — a ADR 0006 diz que o runbook parte deles, e as specs já os listam. Alternativa descartada: só os itens de base. (recomendação da triagem)
- A checklist usa o formato e a retomada da ação externa, com a etapa `lancamento` no marcador — a #95 já resolveu "o usuário executa passos fora do GitHub e marca numa checklist", e o `/fabrica:status` já sabe mostrar a `acao-externa`. Alternativa descartada: um formato novo de checklist. (recomendação da triagem)
- O runbook mora numa issue nova do projeto, criada pela etapa — o PRD diz "gera numa issue", e a issue #96 pede "o runbook numa issue, com uma checklist". Alternativa descartada: um comentário numa issue existente. (recomendação da triagem)
- A issue de runbook nasce sem `agente` e é identificada pelo marcador no corpo, como a da `/fabrica:retro` — com `agente`, a triagem e o dispatcher a pegariam como uma issue de trabalho. Alternativa descartada: aplicar `agente` e ensinar a tabela de estados a pular a triagem nela.
- `--lancamento` no `acao-status.py` em vez de aceitar `lancamento` sempre — mantém `etapa-invalida` para uma issue de agente com marcador de lançamento, sem mudar a linha 1b da tabela. Alternativa descartada: somar `lancamento` ao conjunto padrão.
- "Primeiro lançamento feito" é uma issue de runbook fechada como `completed`; fechada como `not planned` é descartada e não conta — deixa o usuário descartar um runbook gerado cedo demais, e é o que torna possível o teste no próprio fabrica. Alternativa descartada: qualquer issue de runbook fechada bloquear.
- Um ❌ não impede a criação do runbook: vira um bloqueio no topo da checklist — o usuário vê tudo de uma vez e decide, e a etapa não corrige nada sozinha. Alternativa descartada: parar sem criar a issue até os ❌ sumirem.

**Fontes da documentação:**
- gh 2.104.0 — `gh search issues --help` (`--repo`, `--owner`, `--label`, `--state`, `--match`, campos `body`, `number`, `repository`, `state`, `title`, `url`; `stateReason` não existe no `search`), `gh issue view --help` (campo `stateReason`), `gh issue create --help` (`--title`, `--label`, `--body-file`), `gh issue close --help` (`--reason {completed|not planned|duplicate}`), `gh issue comment --help` (`--body-file`).

**ADR:** nenhum. A etapa aplica a ADR 0006 e a ADR 0012 sem mudar as decisões delas; o uso da ação externa fora de `implementar` e `revisar` fica registrado em `acao-externa.md` e em `estados.md`.

## Testes
- `bash scripts/test-acao-status.sh`: casos novos do CA1 e do CA2, com fixtures JSON de comentários.
- `bash opencode/test-adapter.sh` na VM do `sbx`: CA14.
- CA3 a CA11 e CA13: uma rodada manual com `claude --plugin-dir <clone>` no próprio fabrica, numa sessão com o usuário presente ou num `claude -p`, seguindo a ordem CA3 → CA4/CA5 (mesma issue) → CA6 → CA9 → marcar os itens → CA10 → CA7 → reabrir e fechar como `not planned` → CA8 → CA11. Todas as issues de teste terminam fechadas como `not planned`, com um comentário dizendo que eram teste. O PR lista os links.
- CA12: leitura do `SKILL.md` na revisão.

## Passos de produção
nenhum

## Riscos e dúvidas
- As conferências V3, V5, V7 e V8 dependem de convenções (nomes de arquivo, comandos no `AGENTS.md`) que variam por stack. O ⚠️ com motivo evita um ✅ falso, mas o primeiro uso no kairo pode pedir ajustar as listas.
- O fabrica não tem produção, então o CA3 exercita quase tudo como ⚠️. O teste prova o fluxo no GitHub, não a qualidade das conferências num projeto real.
- A issue ainda tem a label `ideia`, que a triagem sugeriu retirar. Não muda o estado; o usuário decide.

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
