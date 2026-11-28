# Backlog da evolução multi-runtime

**Base:** `de4c39adae11` · **Estado:** backlog local. A1 e A2 autorizados. As próximas histórias seguem triagem, spec, aprovação, implementação e revisão pelo fluxo da Fabrica.

## Objetivos por marco

| Marco | Objetivo | Condição de saída |
|---|---|---|
| A · Fundação | Registrar arquitetura e caracterizar a base efetiva. | Contratos documentados, resultados por suíte e pendências identificadas. |
| B · Runtime local | Separar execução e integrar Codex nativamente, com instalação independente. | Ciclo assistido Codex validado e regressão dos demais runtimes caracterizada. |
| C · Automação | Aceitar Codex no dispatcher em ambiente isolado. | Piloto explícito e reversível, com aceite de segurança. |
| D · Concorrência | Coordenar escritores e recuperar tentativas interrompidas. | Posse verificável, repetição segura e publicação protegida contra tentativas antigas. |
| E · Workers | Executar etapas especializadas com modelos configuráveis, inclusive em instalação exclusivamente Codex. | Coordenação sequencial validada antes de expandir para paralelismo. |

## Histórias, aceite e rollback

| ID e história | Dependências | Critérios de aceite verificáveis | Risco e rollback | ADRs |
|---|---|---|---|---|
| **A1 · Consolidar a arquitetura** | Aprovação do marco | Os documentos registram a base, as cinco fronteiras, os modos, o contrato mínimo, a independência e os gates futuros. | Risco de misturar decisões vigentes e planejadas. Revisar o registro em PR próprio. | Novo multi-runtime. |
| **A2 · Caracterizar a base** | SHA confirmado e ambiente temporário autorizado | SHA e versões registrados. Suítes comparadas caso a caso. Pulos e aceites reais têm motivo e condição para execução. | Risco de baseline parcial parecer paridade. Registrar pendências explicitamente. | 0013, 0014, 0017 e SPECs 241/135. |
| **B1 · Isolar o contrato legado Claude** | A1, A2 e spec aprovada | Preservar `stage-model.sh` byte a byte. Normalizar o resultado técnico e usá-lo no dispatcher com os mesmos gates, artefatos e comportamento padrão. Sucesso técnico sem avanço termina no mesmo estado observado. | Risco para workflows instalados. Reverter a integração do normalizador e restaurar o pacote anterior. | Multi-runtime, 0013 e 0017. |
| **B2a · Caracterizar distribuição Codex** | A2 e autorização para aceites aplicáveis | Comparar plugin nativo e descoberta de Skills na versão suportada, em ambiente exclusivamente Codex. Registrar invocação explícita, recursos relativos, origem, atualização e remoção. Decidir com evidência e documentação oficial. | Risco de cache e precedência de catálogos. Descartar a instalação de prova. | Multi-runtime. |
| **B2b · Entregar o executor local Codex** | B1, B2a | Rodar uma etapa com skill nativa, opção explícita, modelo e esforço próprios, diretório gerenciado e parser JSONL. Testar saída truncada, permissão negada, timeout e cancelamento. A ausência das demais CLIs não impede o piloto. | Risco de variar por versão. Desativar opt-in e remover só a instalação Codex. | Multi-runtime e 0013. |
| **B3 · Completar ciclo assistido e revisão** | B2b e ADR de revisão | Executar as quatro etapas com portões preservados. Provar julgamento sem escrita, verificação com evidência por head e publicação pela coordenação. Testar os casos da SPEC-135. | Risco de invalidar testes ou evidência. Desativar a etapa Codex e manter os caminhos existentes. | Novo de revisão, 0011, 0020 e SPEC-135. |
| **C1 · Aceitar isolamento e autenticação Codex no runner** | B3 e ADR de segurança | No runner de teste autorizado, provar ausência de rede direta, credenciais mediadas, falha fechada, cobertura IPv4/IPv6 e artefatos sem segredos. | Risco de vazamento ou perda de isolamento. Desativar o piloto e revogar suas credenciais. | Novo de segurança, 0015, 0016, 0018 e 0021. |
| **C2 · Habilitar dispatcher Codex opt-in** | C1 | Eventos issue/PR, gates, retomadas e resultado funcionam no projeto de teste. Repositórios com configuração anterior continuam no Claude. | Risco de alterar workflows copiados. Reverter a seleção e a alteração do template correspondente. | 0015 e 0017. |
| **D1 · Coordenar posse por issue** | ADR de posse e prova do mecanismo | Aquisição atômica por repositório/issue. Renovação, expiração e liberação condicionadas à posse. Testar disputa e tentativa antiga tardia, inclusive entre evento de PR e issue. | Risco de duas autoridades. Retornar à coordenação serial. | Novo de posse, 0003 e 0014. |
| **D2 · Recuperar execução interrompida** | D1 | Após interrupções antes/depois de push, comentário e PR, reler estado/head, reaproveitar efeitos válidos e impedir duplicação e publicação antiga. | Risco de duplo efeito. Desativar recuperação automática e retomar manualmente. | Novo de posse e 0017. |
| **E1 · Executar workers especializados em sequência** | B3 e D2. C2 para execução no runner | Instalação exclusivamente Codex coordena processos independentes por etapa com modelos/esforços diferentes, mantendo spec, head, evidência e portões. | Risco de repasse insuficiente ou custo. Voltar à execução em sessão ou processo único. | Multi-runtime, revisão e posse. |
| **E2 · Liberar paralelismo entre issues** | E1, D1, D2 | Issues distintas avançam em paralelo sob limites definidos. A mesma issue tem um escritor válido. Cancelamento, renovação e retomada são testados sob disputa. | Risco de saturação e efeitos concorrentes. Reduzir concorrência para um. | Posse, 0003, 0014 e 0017. |

## Ordem recomendada

A1 e A2 em paralelo, depois B1. B2a pode avançar separadamente da mudança B1, após autorizações de teste. Seguir com B2b, B3 e C1/C2. Preparar D1/D2 quando houver requisito de escritores independentes. E1 precede E2. Uma fila, banco ou novo serviço exige justificativa observada em um desses incrementos.

Mudanças de comportamento atualizam manual e versão do plugin conforme `AGENTS.md`. Adoção e rollback preservam as labels e as worktrees existentes.
