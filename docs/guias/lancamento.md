# Lançamento

O projeto vai para produção pela primeira vez. Os agentes não alcançam produção ([ADR 0006](../adr/0006-producao-fora-do-alcance-do-agente.md)), então o lançamento é seu: o `/fabrica:lancamento` confere o que dá para conferir antes e deixa numa issue o roteiro do que você faz.

## Quando rodar
Quando você decidir lançar, com as issues do marco de lançamento já mescladas. Rode no clone do projeto:

```
/fabrica:lancamento
```

A etapa fica fora do `/fabrica:avancar` e do ciclo das issues. Ela usa a branch padrão atualizada e não cria branch, PR nem commit. Se houver issues com `agente` ainda abertas, o runbook avisa: ele cobre só as specs que já estão na branch padrão.

## O que o agente confere
Só no repositório e em dev ou homologação. Cada conferência sai com ✅ (passou), ❌ (falhou) ou ⚠️ (não deu para conferir), sempre com o motivo:
- se o `.fabrica/producao.txt` lista os hosts de produção, para o hook barrar o agente ([Isolamento do agente](isolamento-do-agente.md));
- se os `.env.production*` estão fora do git;
- se a configuração de deploy versionada tem chave de teste, `localhost` ou endereço de homologação;
- quais variáveis o provedor precisa ter, pelos nomes do `.env.example`;
- quais migrações existem e em que ordem, e se há alguma pendente em dev;
- se os testes e o e2e passam contra dev ou homologação;
- se há teste de isolamento entre usuários (se não houver, a etapa recomenda abrir uma issue para ele);
- quantas issues seguem no fluxo.

Um ❌ não impede o runbook: ele vira um item "Resolver antes de seguir" no topo da checklist. A correção, se precisar de código, é uma issue normal do fluxo.

## O que você faz
1. **Abra a issue de runbook** que a etapa criou, "Lançamento: runbook da primeira ida para produção". O corpo tem a tabela das conferências. O comentário de ação tem a checklist, na ordem: os bloqueios, o backup do banco, a conferência das chaves no provedor, as migrações, os passos de produção de cada spec, o teste de isolamento com duas contas e o teste de ponta a ponta com casos adversariais.
2. **Faça cada passo** em produção e marque o item, editando o comentário. O comentário cita só os nomes das variáveis, nunca os valores; não os cole na issue.
3. **Com todos marcados, rode** `/fabrica:lancamento <nº>`. A etapa tira a `acao-externa`, comenta "Lançamento concluído" e fecha a issue.

Se um passo não der para fazer como está, comente na issue e rode `/fabrica:lancamento <nº>`: a etapa publica uma checklist ajustada ou as opções, com uma recomendação. Rodar com itens desmarcados e sem comentário só mostra quantos faltam.

## Depois do primeiro lançamento
Com a issue de runbook fechada como concluída, o `/fabrica:lancamento` diz que o primeiro lançamento já aconteceu e não gera outro. Os passos de produção das releases seguintes continuam na seção "Passos de produção" de cada spec e no PR de cada issue.

Para descartar um runbook gerado cedo demais, feche a issue como "not planned": ela não conta, e a etapa pode gerar outro.

## Onde ver
O `/fabrica:status` mostra a issue de runbook em "Ações externas", com quantos passos você já marcou, e, com tudo marcado, em "Esperando agente", com o comando de retomada. Os estados estão em [`estados.md`](../../skills/status/estados.md#lançamento), e o passo a passo da etapa, em [`skills/lancamento/SKILL.md`](../../skills/lancamento/SKILL.md).
