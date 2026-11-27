# Estratégia de testes e caracterização

O [baseline](08-baseline.md) fixa o resultado de A2. Cada incremento compara o comportamento com o SHA aprovado e registra resultado, falha e pulo separadamente.

| Grupo | Exemplos | Condição |
|---|---|---|
| Leitura e estática | Sintaxe, manifestos, catálogo, refs, regras comuns, leitura de specs e workflows. | Executar em leitura. Inspecionar ferramentas que podem atualizar caches ou gravar objetos Git. |
| Local determinístico | Suítes em clone temporário, Git com remotos locais, `gh` e executores falsos, fixtures de estado e resultado. | HOME temporário, ambiente reduzido e rede isolada. |
| Validação real de runtime e serviço local | Validadores Claude/Antigravity, instalação em ambiente limpo, servidor de aceite OpenCode e VM `sbx`. | Autorização específica antes de usar runtime real, serviço ou VM. Preservar configuração e instalação globais. |
| Efeitos remotos | Aceites do job e da VM, PRs e labels de teste, credenciais mediadas e rede real. | Autorização específica, repositório descartável e plano de limpeza. |
| Modelo real | Eval do revisor, descoberta efetiva, execução assistida e especialização por etapa. | Autorização específica de provedor, conta e orçamento. Se publicar, aplicar também as condições remotas. |

## Matriz de caracterização

- **Claude:** preservar seleção/argumentos, modelo por etapa, stdout e códigos legados, precedência de sessão aninhada, gates, custo e artefatos do dispatcher.
- **OpenCode:** validar parser, registro do catálogo e revisor, modelo da sessão e prontidão da proteção por localização antes da primeira ferramenta.
- **Antigravity:** validar conversão, hooks, revisor e modelo de sessão da SPEC-241. Cobrir migração de cache que possa manter agentes antigos.
- **Codex:** comparar plugin e descoberta de skills com instalação exclusiva. Exercitar parser JSONL, configuração nativa, worktree e execução com escrita bloqueada para julgamento.
- **Compartilhado:** preservar atalho de spec, aprovação, ação externa, CI indisponível, rascunho, novos pedidos, regras da SPEC-135 e publicação de screenshots. Testar sucesso técnico com e sem avanço. Quando houver workers, incluir perda de posse, publicação tardia e reconciliação de efeitos parciais.

Gates de aprovação exigem evidência por cenário e runtime. A revisão read-only isolada é requisito do novo caminho de julgamento. A caracterização registra a capacidade e os limites de cada runtime atual.
