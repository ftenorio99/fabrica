# ADR proposto: Arquitetura multi-runtime para a Fabrica

**Status:** direção aprovada, registro proposto · **Data:** 2026-11-27 · **Origem:** planejamento da evolução multi-runtime

## Contexto

O processo já roda em mais de uma CLI. O dispatcher, a instalação e parte da telemetria ainda refletem o empacotamento inicial em Claude Code. A base `de4c39adae11` incorpora as SPECs 241 e 135, que passam a integrar os contratos de regressão.

## Decisão

- Separar conceitualmente **Process Core**, **Orchestration Core**, **Execution Contract**, **Runtime Adapters** e **Infrastructure**. Manter a disposição física atual durante a caracterização.
- Manter o modo assistido nas CLIs e o modo automatizado pelo dispatcher. O GitHub é a fonte de verdade do workflow. O resultado técnico indica como a execução terminou e a releitura do GitHub determina se houve avanço.
- Tratar Claude Code, OpenCode, Antigravity e Codex CLI como runtimes de primeira classe. Uma instalação funcional deve poder usar um único runtime, conforme suas capacidades. Claude permanece padrão do dispatcher por compatibilidade. Codex inicia local, com seleção explícita.
- Preservar a fonte compartilhada de processos e distribuir os recursos por mecanismos nativos. Separar escolha explícita de executor da detecção de sessão. Cada adaptador resolve modelo, esforço e permissões nativas. Preservar labels e políticas em vigor.
- Aplicar leitura exclusiva ao julgamento sobre um head fixo. Executar verificações no ambiente autorizado e delegar correção/publicação à coordenação competente. Preservar a verificação da base e do CI aplicável ao head.
- Permitir futuramente workers independentes por etapa, com modelo e parâmetros configuráveis, inclusive usando exclusivamente Codex CLI. Exigir posse e recuperação antes de múltiplos escritores. Infraestrutura adicional exige necessidade demonstrada.

## Alternativas consideradas

| Alternativa | Consequência |
|---|---|
| Duplicar o processo por runtime | Portões, estados e critérios passariam a divergir. |
| Usar o protocolo do Claude como API comum | Obriga outros runtimes a reproduzir convenções de uma CLI. |
| Migrar toda a coordenação em uma única entrega | Torna difícil identificar regressões e reverter o rollout. |
| Extrair contratos por incremento | Preserva os pontos de entrada e valida alterações contra a base caracterizada. |

## Consequências

A plataforma mantém uma política de processo e aceita diferenças explícitas de capacidade. O [contrato mínimo](03-spec-codex-runtime.md) entra por cortes pequenos. Os aceites de segurança e concorrência condicionam os incrementos seguintes. Produção continua sob responsabilidade humana.

## ADRs relacionados

- **0013 e 0017:** complementar na introdução do executor explícito e da releitura após resultado técnico. Preservar a emenda da SPEC-241.
- **Novo ADR de revisão:** definir julgamento, verificação e autoridade de publicação. Complementar a 0011 e preservar 0020 e SPEC-135.
- **Novo ADR de segurança para Codex no runner:** definir identidade, autenticação, mediação, rede, confiança e retenção. Complementar 0010 e 0015–0018 conforme o incremento. Preservar o escopo da 0021.
- **Novo ADR de posse e recuperação:** definir atomicidade, identidade, renovação, expiração, liberação condicionada, idempotência e rejeição de tentativas antigas. Complementar 0003 e preservar 0014.
- **Decisões preservadas:** 0002, 0004, 0006, 0008, 0012, 0014, 0019 e 0020. Diretório de [ADRs atuais](../../../adr/).
