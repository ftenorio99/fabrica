# PRD: fabrica

**Status:** aprovado · **Atualizado em:** 2026-11-09

## Resumo
A fabrica é uma fábrica de software pessoal, empacotada como plugin do Claude Code. O usuário entra com requisitos e revisão, e os agentes fazem triagem, spec, implementação e revisão. Este PRD cobre as Fases 1 e 2 do plano: o fluxo passa a rodar sozinho no GitHub Actions, com isolamento e verificação, e o usuário só age nos portões.

## Problema
Um desenvolvedor solo gasta o próprio tempo executando, e não decidindo. Na Fase 0, a fábrica já tira a execução das mãos dele, mas cada etapa ainda depende de uma sessão local do Claude Code aberta por ele (`/fabrica:avancar` ou o comando da etapa). Com isso, o fluxo para sempre que o usuário não está no terminal, e o agente roda na máquina dele com acesso a `~/.ssh`, ao `gh` pessoal e aos `.env`, protegido só pelos hooks do git.

## Público
O próprio usuário, dono dos repositórios, desenvolvedor e único revisor. Ele aprova a spec e o PR e decide o que entra no fluxo. O projeto piloto é o kairo.

## Objetivos e métricas de sucesso
| Objetivo | Como medir | Meta do MVP |
|---|---|---|
| Autonomia: o usuário só age nos portões | Issues entregues no kairo em que todas as etapas de agente rodaram no GitHub Actions, sem sessão local | 5 issues seguidas |
| O fluxo anda sem esperar o usuário abrir o terminal | Fila do `/fabrica:metricas`: tempo entre o gesto do usuário e o início da etapa seguinte | mediana abaixo de 10 min |
| Rodar sem supervisão não abre brecha | Teste de aceite do isolamento (F1) e da regra de credenciais (F2) passando, e nenhum acesso a produção nem segredo exposto pelos agentes | 100% e zero incidentes |
| A qualidade não piora com a automação | Escalonamentos e respostas no PR por issue, comparando um período do fluxo local com um do dispatcher no `/fabrica:metricas` | igual ou menor |

## Escopo do MVP
| ID | Funcionalidade | Prioridade | Descrição |
|---|---|---|---|
| F1 | Isolamento do agente | obrigatória | O agente roda em sandbox, com sistema de arquivos e rede restritos a uma lista de domínios liberados e sem ler segredos em claro, tanto no `/fabrica:avancar` local quanto no job do dispatcher. |
| F2 | Credenciais só de dev ou homologação | obrigatória | As etapas de agente nunca alcançam o banco nem os serviços de produção. O que é de produção vira passo de um runbook executado pelo usuário. |
| F3 | Ação externa com checklist | obrigatória | Quando o agente depende de uma ação do usuário fora do GitHub (criar conta, cadastrar secret, gerar chave), ele publica uma checklist passo a passo na issue e retoma sozinho quando o usuário conclui. |
| F4 | Dispatcher pela label `agente` | obrigatória | Aplicar `agente` numa issue dispara a etapa de agente no GitHub Actions, com o plugin instalado no job, sem sessão local. |
| F5 | Retomada a cada gesto do usuário | obrigatória | Cada gesto do usuário (resposta a perguntas, `spec-aprovada`, comentário no PR, checklist de ação externa concluída) dispara a etapa seguinte, até o próximo portão. |
| F6 | Testes de ponta a ponta no CI do PR | obrigatória | O CI do PR sobe o app e o banco no próprio job e roda o Playwright, com casos adversariais (entradas maliciosas, abuso de limite) além do caminho feliz. |
| F7 | Aprovação visual | obrigatória | Cada projeto com interface tem um design system versionado (`docs/design.md`). A spec descreve as telas, e a implementação anexa ao PR screenshots reais, no celular e no computador, para o usuário aprovar. |
| F8 | Runbook de lançamento | obrigatória | Antes da primeira ida para produção, o agente gera numa issue o runbook com checklist (migrações com backup, chaves de teste, isolamento de dados, teste em produção) e verifica o que dá para verificar. O usuário executa os passos de produção. |
| F9 | Métricas persistentes | desejável | Tokens, custo e tempos guardados fora do GitHub (Postgres ou exportador OTLP), para comparar períodos longos sem refazer as consultas. |

## Fora de escopo
- **Roteamento entre modelos e ferramentas (Fase 3, OpenRouter e OpenCode):** o foco é só o Claude Code.
- **Fase 4 (melhoria):** a melhoria contínua já acontece pela trilha da retro (veja "Restrições e premissas").
- **Execução em ondas com subagentes paralelos (#16):** o dispatcher roda um job por issue, o que pode dar o paralelismo sozinho. Vale rever só se as métricas mostrarem gargalo no meio do fluxo.
- **Preview protegido da Vercel (#97):** os testes do MVP rodam contra o app subido no CI. O preview da Vercel fica para quando um projeto usar a Vercel.
- **Automatizar a própria ação externa:** a F3 dá instruções. Ela não cria contas nem projetos pelo usuário.
- **Executar passos de produção:** quem executa é o usuário (F2, F8).

## Requisitos não funcionais
- **Segurança:** nenhum segredo no repositório, nos comentários nem nos logs do Actions. Os secrets entram como secrets do GitHub ou por um proxy, e o token do job é fine-grained, restrito ao repositório e aos escopos necessários.
- **Um fluxo só:** as mesmas skills rodam no terminal e no Actions, e o estado continua só no GitHub (labels, marcadores e PR), conforme `skills/status/estados.md`.
- **Concorrência:** no máximo uma execução por issue ao mesmo tempo (label `em-andamento` e grupo de concorrência do Actions por issue), e o limite de 3 em andamento por repositório continua valendo.
- **Sem cascata:** um comentário ou uma label aplicada pelo próprio agente não dispara outra execução. Só os gestos do usuário disparam.
- **Custo medido:** toda execução publica a linha de custo da etapa, como no fluxo local.
- **Idioma:** código em inglês; skills, comentários, issues, PRs e manual em português.

## Restrições e premissas
- **Claude Code e GitHub:** a fábrica usa só o Claude Code, as Issues, as labels e o GitHub Actions. Nada de Linear nem de GitHub Projects.
- **Os portões não mudam:** aplicar `agente`, aprovar a spec e fazer o merge continuam sendo do usuário.
- **Piloto:** o kairo valida cada marco antes de a mudança valer para outros projetos.
- **Melhorias da retro fora deste PRD:** as propostas do `/fabrica:retro` e das lições (ex.: #91, #92, #98) seguem a ordem da retro, com no máximo 1 em andamento junto com 1 item do roadmap.
- **Ordem:** o isolamento (F1) e as credenciais (F2) vêm antes do dispatcher (F4).

## Riscos
| Risco | Impacto | Mitigação |
|---|---|---|
| A assinatura não permite uso automatizado no Actions | alto | Conferir os termos no estudo do dispatcher (item 4). Se não permitir, usar API key com teto por execução (`--max-budget-usd`). |
| Injeção de prompt vinda de docs ou pacotes leva a exfiltração de credenciais ou a um comando destrutivo | alto | F1 e F2 antes do dispatcher, com domínios liberados, sem segredos em claro e com o token restrito. |
| Disparo em cascata: o comentário do agente dispara outro job, em laço | médio | O workflow ignora eventos de comentários com marcador `<!-- fabrica:` e de labels aplicadas pelas etapas. Teto de etapas por disparo, como no `/fabrica:avancar`. |
| No modo headless, o auto mode aborta sem usuário a quem recorrer, e a etapa para no meio | médio | A `em-andamento` e o alerta de label esquecida do `/fabrica:status`. A etapa que aborta registra o motivo na issue. |
| Dois jobs na mesma issue | médio | Grupo de concorrência por issue no Actions, além da `em-andamento`. |
| Custo sobe sem ninguém ver | médio | Linha de custo por etapa e `/fabrica:metricas`. Teto mensal definido depois de medir. |

## Perguntas em aberto
- **Runner:** Hetzner self-hosted ou runners do GitHub. Decide o estudo do dispatcher (item 4).
- **Autenticação dos agentes:** assinatura (`claude_code_oauth_token`) ou API key, conforme os termos de uso automatizado. Decide o estudo do dispatcher (item 4).
- **Teto de gasto mensal:** definido pelo usuário depois das primeiras semanas do dispatcher, com os tokens medidos pelo `/fabrica:metricas`.

## Fatiamento
Itens de 1 a 2 dias de trabalho humano, agrupados por marco e em ordem de dependência dentro de cada marco. O número do item é fixo: não renumere; item novo recebe o próximo número livre.

### M1 · Segurança antes da automação (F1, F2, F3)
- **1.** Isolamento do `/fabrica:avancar` local em sandbox, com domínios liberados, ADR e teste de aceite (F1)
- **2.** Regra e hook de credenciais só de dev ou homologação nas etapas de agente (F2)
- **3.** Bloqueio de ação externa com checklist e retomada pelo `/fabrica:avancar` (F3)

### M2 · Primeiro loop (F4, F5, F1)
- **4.** Estudo do dispatcher: claude-code-action, runner e autenticação, com ADR (F4) · depende de 1
- **5.** Workflow que roda a etapa de agente quando a label `agente` é aplicada, validado num repositório de teste (F4) · depende de 2, 4
- **6.** Isolamento do job do dispatcher, com token fine-grained e domínios liberados (F1) · depende de 1, 4
- **7.** Retomada por evento: resposta, `spec-aprovada`, comentário no PR e checklist concluída disparam a etapa seguinte, sem cascata (F5) · depende de 3, 5
- **8.** Dispatcher instalado num projeto pelo `/fabrica:setup`, com o workflow e o guia dos secrets, e ligado no kairo (F4) · depende de 5, 6, 7

### M3 · Verificação (F6, F7, F8)
- **9.** CI do PR sobe o app e o banco no job e roda o Playwright, e a spec pede casos adversariais nos CAs de ponta a ponta (F6) · depende de 8
- **10.** Design system versionado por projeto (`docs/design.md`) e campo de interface na triagem (F7)
- **11.** Spec descreve as telas, e a implementação anexa screenshots no celular e no computador ao PR (F7) · depende de 9, 10
- **12.** Runbook de lançamento gerado numa issue com checklist antes da primeira ida para produção (F8) · depende de 2, 3

## Histórico
- 2026-11-09: criação; PRD aprovado.

### Mudanças
| Data | Tipo | F | Motivo | Decisão | Issues |
|---|---|---|---|---|---|
