# Spec preliminar: executor Codex local

**Status:** proposta para as etapas B2 e B3 · **Base:** `de4c39adae11`

## Objetivo

Executar uma etapa em Codex CLI de forma explícita, com instalação independente dos demais runtimes e descoberta nativa da skill. B2 entrega um caminho local funcional. B3 cobre o ciclo assistido e a fronteira da revisão. CI fica condicionado ao aceite de C1.

## Contrato mínimo

| Elemento | Campos e semântica |
|---|---|
| Seleção | Executor explícito em entrada própria. `harness.sh detect` mantém precedência, saídas e precedência de sessão aninhada. |
| Pedido | Identificador, repositório, issue, etapa, executor, diretório validado, perfil de permissões e prazo. Modelo e esforço nativos são opcionais. A skill vem de catálogo confiável. A etapa busca texto externo pelo `gh`. |
| Resultado técnico | `succeeded`, `failed`, `blocked`, `cancelled` ou `timed_out`. Motivo estável, runtime, código nativo quando disponível e duração. Uso, modelo efetivo e sessão são opcionais. |
| Decisão do workflow | Releitura do GitHub pelo coordenador. Avanço, sem avanço, portão humano e inconsistência são decisões de processo. |
| Julgamento | Spec e head fixo. Achados e evidências associados ao SHA. Permissão de julgamento somente leitura, com verificação e publicação sob permissões próprias. |

## Critérios de aceite

| ID | Critério | Verificação |
|---|---|---|
| CA1 | Seleção explícita usa Codex. Instalação exclusiva funciona sem outras CLIs no PATH. | Fixture de seleção e aceite em ambiente limpo. |
| CA2 | Skill nativa resolve regras, scripts, templates e agente a partir da worktree. A política de invocação explícita é preservada. | Comparar plugin Codex e Skills descobertas com build suportado e documentação oficial. Registrar descoberta, versão, atualização e remoção. |
| CA3 | O executor respeita worktree, modelo, esforço, prazo e permissões. | Binário falso para argumentos e ambiente, seguido de aceite controlado. |
| CA4 | Parser distingue término coerente, falha, cancelamento, timeout e saída incompleta. | Fixtures JSONL, incluindo evento desconhecido e evento terminal ausente. |
| CA5 | Sucesso técnico sem alteração no GitHub encerra sem avanço. | Fixtures do coordenador e teste de portões. |
| CA6 | Em B3, o julgador opera sem escrita. Verificação produz evidência separada e a coordenação preserva a SPEC-135. | Aceite com head e base controlados. |

Use Codex CLI 0.172.0 como versão de referência observada na auditoria. Declare suporte depois do aceite. Compare distribuição nativa com a documentação oficial de [plugins](https://learn.chatgpt.com/docs/plugins), [skills](https://learn.chatgpt.com/docs/build-skills) e [execução não interativa](https://learn.chatgpt.com/docs/non-interactive-mode). Adie fixar um mecanismo de distribuição até obter os resultados de CA2.
