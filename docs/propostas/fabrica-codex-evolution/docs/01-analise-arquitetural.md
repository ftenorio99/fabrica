# Análise arquitetural

A implementação já separa partes compartilháveis do processo. O leitor de estado é puro, a checklist tem parser próprio e o Git gerencia uma worktree por issue. A coordenação em Actions ainda lê o resultado do Claude diretamente. No modo local, as skills também coordenam etapas em prosa. A primeira extração deve ocorrer na fronteira entre seleção, execução e interpretação do resultado.

| Responsabilidade | Contrato e código atual |
|---|---|
| Process Core | Etapas, portões humanos, regras de transição, critérios de aceite e interpretação do estado GitHub. [Tabela](../../../../skills/status/estados.md), [avaliador](../../../../scripts/issue-state.py), [checklist](../../../../scripts/acao-status.py), [regras comuns](../../../../skills/etapas/regras.md). |
| Orchestration Core | No assistido, operador e [avançar](../../../../skills/avancar/SKILL.md). No automatizado, [dispatcher](../../../../scripts/dispatch.sh) resolve a issue, escolhe a etapa, marca atividade, limita chamadas e relê o estado. A coordenação da [revisão](../../../../skills/revisar/SKILL.md) separa julgamento, verificação e correção/publicação. |
| Execution Contract | [Fachada de modelo e execução](../../../../scripts/stage-model.sh), stdout e código nativos, hoje interpretados pelo dispatcher e pelo avançar. Preservar a interface legada ao introduzir um resultado técnico interno. |
| Runtime Adapters | [Detecção](../../../../scripts/harness.sh), distribuição de skills, agentes, hooks, modelos e interpretação de saída. Claude usa o manifesto do plugin, [OpenCode](../../../../opencode/server.ts) registra recursos no servidor e [Antigravity](../../../../agents.json) converte o plugin e registra o revisor. |
| Infrastructure | [Worktrees](../../../../scripts/issue-worktree.sh), GitHub, [workflow](../../../../templates/workflows/agente.yml), [isolamento](../../../../scripts/job-isolation.sh), proxy, credenciais, evidências e [publicação de telas](../../../../scripts/publish-screenshots.sh). |

## Modos de operação

- **Assistido:** operador inicia etapas na interface nativa. OpenCode e Antigravity usam o modelo da sessão. Claude oferece sessão e processo próprio via avançar. O piloto Codex terá skills nativas e execução local explícita.
- **Automatizado:** o dispatcher reage aos fatos do GitHub, executa até um portão e mantém Claude como padrão. O suporte a outros executores depende de aceite no ambiente correspondente. O orquestrador futuro deve suportar workers especializados em instalação exclusivamente Codex.

## Riscos que orientam a migração

- A label `em-andamento` tem validade e sinaliza atividade. Aquisição e limpeza atuais são operações separadas. Eventos de PR e issue podem chegar em grupos distintos. Uma worktree por issue isola branches entre issues e ainda requer coordenação para múltiplos escritores na mesma issue.
- Resultado técnico, publicação e avanço são fatos distintos. O coordenador deve reler o GitHub. O coletor local e o do dispatcher podem ter acesso diferente aos dados de CI.
- A etapa de revisão pode escrever ao corrigir, atualizar a branch e publicar. O julgador recebe o head e trabalha em somente leitura. A verificação pode gerar artefatos próprios. A SPEC-135 exige conferir a atualidade da base antes de aplicar `pronto-revisao`.
- O isolamento do job depende de usuário separado, rede restrita e mediação de credenciais. Hooks são uma camada adicional. JSON bruto e logs do runtime requerem uma política de retenção própria.
