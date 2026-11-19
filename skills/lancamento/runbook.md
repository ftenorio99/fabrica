# Modelos do runbook de lançamento

Modelos usados pelo [`/fabrica:lancamento`](SKILL.md). Troque o que está entre `<>` e apague as linhas que não se aplicam. Nenhum texto traz o valor de um segredo: só nomes e onde cadastrar.

## Corpo da issue de runbook
Título: `Lançamento: runbook da primeira ida para produção`. A primeira linha do corpo é o marcador, que identifica a issue de runbook.

```markdown
<!-- fabrica:lancamento -->
## Runbook da primeira ida para produção

Conferido em <AAAA-MM-DD>, no commit `<hash curto>` da branch `<padrão>`, só no repositório e em dev ou homologação. O agente não alcança produção: os passos de produção estão na checklist do comentário de ação abaixo e são seus.

| # | Conferência | Resultado | Motivo |
|---|---|---|---|
| V1 | Padrões de produção (`.fabrica/producao.txt`) | <✅, ❌ ou ⚠️> | <uma frase> |
| V2 | `.env` de produção fora do git | <...> | <...> |
| V3 | Chaves de teste na configuração de produção | <...> | <arquivo:linha de cada achado, sem o valor> |
| V4 | Variáveis que o provedor precisa ter | <...> | <os nomes, ou o motivo do ⚠️> |
| V5 | Migrações em ordem | <...> | <quantas, da primeira à última, e se há pendente em dev> |
| V6 | Testes contra dev | <...> | <comando e resumo> |
| V7 | Isolamento de dados | <...> | <arquivos de teste, ou a recomendação de abrir uma issue `feat`> |
| V8 | Ponta a ponta contra dev ou homologação | <...> | <comando e resumo> |
| V9 | Trabalho em andamento | <...> | <N issues com `agente` abertas> |

Com todos os passos marcados, rode `/fabrica:lancamento <nº>` para fechar o runbook. Para descartar este runbook (por exemplo, gerado cedo demais), feche a issue como "not planned": a etapa poderá gerar outro.
```

## Comentário de ação
Segue o formato de [../status/acao-externa.md](../status/acao-externa.md), com a etapa `lancamento`. Os bloqueios vêm primeiro, um por ❌; o P3 só entra com migrações em V5; os passos das specs vêm depois do P3, em ordem crescente do número da spec.

```markdown
<!-- fabrica:acao etapa=lancamento -->
## Ação externa pendente

**Por que:** primeira ida para produção; o agente não alcança produção. Os passos abaixo são seus, na ordem. As conferências que o agente fez estão no corpo da issue.

**Passos:**
- [ ] Resolver antes de seguir: <V#> — <motivo>
- [ ] P1 Backup: faça o backup do banco de produção no <provedor, se o projeto o cita> e confira que ele restaura (restaure numa base à parte e abra uma tabela).
- [ ] P2 Chaves: no painel do provedor de deploy (<onde cadastrar, se o projeto o cita>), confira que estas variáveis têm valores de produção, e não de teste ou de homologação: `<NOME_1>`, `<NOME_2>`.
- [ ] P3 Migrações: aplique em produção as <N> migrações, em ordem, de `<primeira>` a `<última>`, com `<comando de migração do projeto>`, depois do P1.
- [ ] <linha da seção "Passos de produção" da spec> (SPEC-<nº>)
- [ ] P4 Isolamento: em produção, com duas contas, confira que a conta A não lê nem altera dados da conta B, abrindo a URL de um registro de B logado como A e chamando a API com o ID de B.
- [ ] P5 Ponta a ponta adversarial: em produção, percorra o fluxo principal e os casos adversariais: ID de outro usuário na URL, entrada inválida ou vazia, sessão expirada e duplo envio.

Marque cada item aqui mesmo quando concluir, editando este comentário. Com todos marcados, rode `/fabrica:lancamento <nº>`. Se um passo não der para fazer como está descrito, comente na issue e rode `/fabrica:lancamento <nº>`: a etapa propõe outro caminho ou as opções.
```

Sem variáveis em V4, o P2 diz: "confira que nenhuma variável de produção tem valor de teste ou de homologação; o projeto não tem `.env.example` para listar os nomes".

## Comentário de conclusão
Publicado na retomada com a checklist concluída, logo antes de fechar a issue como `completed`.

```markdown
<!-- fabrica:lancamento -->
## Lançamento concluído

Em <AAAA-MM-DD>, os <N> passos da checklist foram marcados. A issue fecha como concluída, e o `/fabrica:lancamento` passa a dizer que o primeiro lançamento já aconteceu.
```
