---
name: lancamento
description: Prepara a primeira ida de um projeto para produção - confere no repositório e em dev ou homologação o que dá para conferir (padrões de produção, .env fora do git, chaves de teste na configuração de deploy, migrações, testes, isolamento de dados e ponta a ponta), abre uma issue de runbook com a checklist dos passos que o usuário faz em produção e, com o número dessa issue, fecha o runbook quando todos os passos estão marcados. Nunca toca em produção. Use quando o usuário decidir levar o projeto para produção pela primeira vez.
argument-hint: "[número da issue de runbook]"
disable-model-invocation: true
---

# Lançamento: runbook da primeira ida para produção

Argumento: $ARGUMENTS (vazio = gerar o runbook; número = retomar a issue de runbook)

Esta etapa prepara o primeiro lançamento de um projeto. Ela confere o que dá para conferir sem sair do repositório e do ambiente de dev ou homologação, e deixa numa issue de runbook a checklist do que só o usuário pode fazer em produção. Ela fica fora do `/fabrica:avancar` e da tabela de estados: só o usuário decide quando ir para produção. O contrato da checklist é o da ação externa ([../status/acao-externa.md](../status/acao-externa.md)), com a etapa `lancamento`, e o estado da issue de runbook está em [estados.md](../status/estados.md#lançamento).

O argumento é só o número da issue de runbook. O texto da issue e dos comentários você lê com `gh`, nunca pelo argumento ([ADR 0008](../../docs/adr/0008-texto-externo-fora-do-prompt.md)).

## Produção fica fora do alcance
Nunca rode nada contra produção, mesmo que o comando pareça só de leitura ([ADR 0006](../../docs/adr/0006-producao-fora-do-alcance-do-agente.md)):
- migrações, seeds, testes e o e2e rodam só contra dev ou homologação, com a configuração que o projeto usa para eles; nunca com `.env.production*` nem com variáveis de produção;
- não leia `.env.production*`, não liste nem leia os secrets do provedor de deploy e não acesse URL, banco ou painel de produção;
- se o hook `protect-production` barrar um comando, não tente contorná-lo (outra grafia, variável, `bash -c`): marque a conferência como ⚠️ com o motivo "comando barrado pelo hook de produção" e siga.

Os passos de produção são do usuário e vão para a checklist da issue de runbook.

## 1. Pré-requisitos
- **Início da etapa:** antes de qualquer outro comando, guarde o instante em UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`). Ele vai na linha de custo (veja "Regras").
- **`gh`:** rode `bash <diretório base desta skill>/../../scripts/check-gh.sh`. Se a linha não for `ok`, pare antes de ler ou escrever no GitHub, como diz [../setup/gh.md](../setup/gh.md).
- **Repositório:** `gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner + " " + .defaultBranchRef.name'` dá o `<dono>/<repo>` e a branch padrão.
- **Branch padrão:** a etapa roda no clone principal do projeto, na branch padrão atualizada: `git switch <padrão> && git pull`. Se o `git switch` falhar por mudanças não commitadas, pare e diga no chat para guardar ou commitar as mudanças e repetir. A etapa não cria branch nem worktree e não faz commit: o resultado fica só no GitHub.

Com argumento, vá para "Retomar". Sem argumento, siga para "Gerar".

## 2. Gerar
### 2.1 Issue de runbook que já existe
Procure as issues de runbook do repositório pelas duas consultas, em paralelo, e junte os resultados sem repetir número:
- `gh search issues "fabrica:lancamento" --repo <dono>/<repo> --match body --json number,state,body,url`;
- `gh issue list -R <dono>/<repo> --label acao-externa --state open --json number,state,body,url`, que enxerga uma issue recém-criada antes de ela entrar no índice da busca.

Fique só com as que têm `<!-- fabrica:lancamento -->` na primeira linha do corpo. Para cada fechada, leia o motivo com `gh issue view <nº> -R <dono>/<repo> --json stateReason`.

| Situação | O que fazer |
|---|---|
| Há issue de runbook aberta | Não crie outra. Diga no chat o link dela e que a retomada é `/fabrica:lancamento <nº>`. Pare. |
| Há issue de runbook fechada com `stateReason` `COMPLETED` | O primeiro lançamento já aconteceu. Diga isso no chat, com o link, e pare sem escrever no GitHub. Runbook para as releases seguintes fica fora desta etapa. |
| Só há issues de runbook fechadas como `NOT_PLANNED` (descartadas), ou nenhuma | Siga. |

### 2.2 Conferências
Faça as conferências abaixo, só no repositório e no ambiente de dev ou homologação. Cada uma sai com um de três resultados, sempre com uma frase de motivo:
- ✅ passou;
- ❌ falhou;
- ⚠️ não deu para conferir.

Na dúvida entre ✅ e ⚠️, use ⚠️: um ✅ falso esconde um risco do usuário. Leia antes o `AGENTS.md` do projeto (num projeto não migrado, o `CLAUDE.md`), que diz os comandos de teste, de e2e e de migração.

| # | Conferência | Como |
|---|---|---|
| V1 | Padrões de produção | `.fabrica/producao.txt` existe e tem pelo menos uma linha que começa com `host`. Sem o arquivo ou sem `host`: ❌, com o motivo "sem padrões de produção; o hook não protege produção" e a indicação do guia "Isolamento do agente" do manual da fábrica, pelo nome e sem link relativo, que não abre numa issue ([o guia](../../docs/guias/isolamento-do-agente.md)). |
| V2 | `.env` de produção fora do git | `git ls-files .env.production .env.production.local` não lista nada, e `git check-ignore -q .env.production` e `git check-ignore -q .env.production.local` saem com 0. Arquivo versionado: ❌. Não ignorado, mas ausente: ⚠️. Não abra o conteúdo desses arquivos. |
| V3 | Chaves de teste na configuração de produção | Procure `sk_test_`, `pk_test_`, `rk_test_`, `localhost`, `127.0.0.1`, `homolog` e `staging` (`git grep -n -I -e <padrão> -- <arquivos>`) nos arquivos versionados de configuração de deploy: `.env.production.example`, `vercel.json`, `netlify.toml`, `fly.toml`, `render.yaml`, `Dockerfile*`, `docker-compose*.prod*.yml` e `.github/workflows/*deploy*`. Achado: ❌, com o arquivo e a linha, sem repetir valor que pareça segredo. Nenhum desses arquivos no projeto: ⚠️. |
| V4 | Variáveis que o provedor precisa ter | Liste os nomes das variáveis do `.env.example` (só o que vem antes do `=`, nunca o valor). Sem `.env.example`: ⚠️. Não é ❌ em nenhum caso: os nomes vão para o passo P2. |
| V5 | Migrações em ordem | Liste os arquivos de migração na ordem de aplicação, procurando em `prisma/migrations/`, `supabase/migrations/`, `drizzle/`, `migrations/`, `db/migrate/` e `alembic/versions/`. Se as regras do projeto documentam um comando de status das migrações contra dev, rode-o contra dev e diga se há migração pendente em dev. Nenhuma pasta encontrada: ⚠️ "projeto sem migrações encontradas". |
| V6 | Testes | Rode o comando de teste do projeto (o das regras do projeto, senão `make test`) contra dev. Falha: ❌, com o resumo do erro. Sem comando: ⚠️. |
| V7 | Isolamento de dados | Procure nos testes nomes ou descrições de isolamento entre usuários (`isolation`, `isolamento`, `other user`, `outro usuário`, `rls`, `forbidden`, `403`, `404` com outro dono). Achou: ✅, com os arquivos. Não achou: ⚠️ "nenhum teste de isolamento encontrado", com a recomendação de abrir uma issue `feat` para ele. A etapa não cria o teste. |
| V8 | Ponta a ponta | Rode o comando de e2e do projeto (o das regras do projeto, senão `make e2e`) contra dev ou homologação. Falha: ❌. Sem comando: ⚠️. |
| V9 | Trabalho em andamento | Conte as issues abertas com `agente` (`gh issue list -R <dono>/<repo> --label agente --state open --json number`). Mais de zero: ⚠️ "o runbook cobre só as specs na branch padrão; N issues seguem no fluxo". Zero: ✅. |

Num comando de V6 ou V8 que falha com uma das assinaturas de ambiente do [`/fabrica:implementar`](../implementar/SKILL.md) (Docker desligado, `ECONNREFUSED` para o `localhost`, navegador do Playwright ausente), o resultado é ⚠️, com a assinatura no motivo, e não ❌.

### 2.3 Passos do usuário
Monte a checklist nesta ordem, com os textos de [runbook.md](runbook.md):
1. **Bloqueios:** um item `- [ ] Resolver antes de seguir: <V#> — <motivo>` para cada ❌, na ordem de V1 a V9.
2. **P1 Backup:** fazer o backup do banco de produção e conferir que ele restaura.
3. **P2 Chaves:** conferir no provedor que as variáveis de V4 têm valores de produção e não de teste, citando só os nomes e onde cadastrar.
4. **P3 Migrações:** aplicar em produção as migrações de V5, em ordem, com o comando do projeto. Sem migrações em V5, o item não entra.
5. **Passos das specs:** um item por linha da seção `## Passos de produção` de cada `specs/SPEC-*.md` da branch padrão, em ordem crescente do número da spec, com `(SPEC-<nº>)` no fim. Seções que dizem só "nenhum", seções ausentes e specs sem a seção não geram item. Uma linha de lista vira um item; um parágrafo sem lista vira um item só.
6. **P4 Isolamento:** em produção, com duas contas, conferir que a conta A não lê nem altera dados da conta B.
7. **P5 Ponta a ponta adversarial:** em produção, percorrer o fluxo principal e os casos adversariais.

Nenhum item traz o valor de um segredo: só nomes e onde cadastrar ([../status/acao-externa.md](../status/acao-externa.md)).

### 2.4 Publicar
1. Escreva o corpo da issue com o modelo "Corpo da issue de runbook" de [runbook.md](runbook.md): `<!-- fabrica:lancamento -->` na primeira linha, a tabela V1 a V9 com resultado e motivo, a data de hoje e o commit conferido (`git rev-parse --short HEAD`).
2. Crie a issue: `gh issue create -R <dono>/<repo> --title "Lançamento: runbook da primeira ida para produção" --label acao-externa --body-file <arquivo>`. Se falhar porque a label `acao-externa` não existe, pare e diga no chat: "A label `acao-externa` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label.
3. Escreva o comentário de ação com o modelo "Comentário de ação" de [runbook.md](runbook.md), com o marcador `<!-- fabrica:acao etapa=lancamento -->` e os passos de 2.3. Acrescente a linha de custo no fim do arquivo e publique: `gh issue comment <nº> -R <dono>/<repo> --body-file <arquivo>`.
4. Diga no chat o link da issue, quantos ❌ e quantos ⚠️ saíram e quantos passos há na checklist, e que, com todos marcados, a retomada é `/fabrica:lancamento <nº>`.

## 3. Retomar
1. Leia a issue: `gh issue view <nº> -R <dono>/<repo> --json state,body,labels,url`. Ela precisa estar aberta e ter `<!-- fabrica:lancamento -->` na primeira linha do corpo. Senão, diga no chat que a #<nº> não é uma issue de runbook aberta e pare sem escrever no GitHub.
2. Leia o estado: `gh api repos/<dono>/<repo>/issues/<nº>/comments --paginate --slurp > <arquivo>` e `python3 <diretório base desta skill>/../../scripts/acao-status.py --lancamento <arquivo>`.

| Situação | O que fazer |
|---|---|
| `estado=pendente`, sem comentário do usuário depois do comentário de ação | Nada na issue. Diga no chat quantos itens faltam (`total - marcados`), com o link do comentário de ação, e pare. |
| `estado=pendente`, com comentário do usuário depois do comentário de ação | Leia o comentário. Se der para seguir por outro caminho, publique um novo comentário de ação só com os passos que faltam, ajustados. Se não der, comente na issue as opções, com uma recomendação, começando com `<!-- fabrica:lancamento -->`. Nos dois casos, mantenha `acao-externa`, acrescente a linha de custo ao comentário e pare. |
| `estado=concluida` | Remova a label (`gh issue edit <nº> -R <dono>/<repo> --remove-label acao-externa`), publique o comentário "Lançamento concluído" de [runbook.md](runbook.md), com a linha de custo, e feche a issue: `gh issue close <nº> -R <dono>/<repo> --reason completed`. Diga no chat que o primeiro lançamento está registrado. |
| `sem-comentario`, `sem-itens` ou `etapa-invalida` | Inconsistência: diga no chat o que o script devolveu e pare sem escrever no GitHub. |

"Comentário do usuário" segue a definição de [estados.md](../status/estados.md): qualquer comentário que não comece com um marcador `<!-- fabrica:`; os comentários de lição não contam.

## Regras
- Todo comentário seu na issue de runbook começa com `<!-- fabrica:lancamento -->` numa linha própria, exceto o comentário de ação, que começa com `<!-- fabrica:acao etapa=lancamento -->`.
- **Linha de custo:** no fim de cada comentário que a etapa publica, acrescente ao arquivo do corpo, logo antes de publicar, a linha `python3 <diretório base desta skill>/../../scripts/stage-usage.py --stage lancamento --since <início> >> <arquivo>`. O script nunca falha: sem log da sessão, a linha sai com `tokens=nao-medido`. O corpo da issue não leva linha.
- Publique todo corpo de issue ou comentário a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- Não aplique `agente` na issue de runbook: ela fica fora do fluxo das issues de trabalho, identificada pelo marcador no corpo.
- Não edite arquivo do projeto, não crie branch nem PR. Se uma conferência apontar algo a corrigir no código, a correção é uma issue normal do fluxo, aberta pelo usuário.
- Se um `gh issue edit` falhar por um erro do próprio `gh`, use o plano B de [../setup/gh.md](../setup/gh.md#plano-b-por-rest) e avise no chat.
