# Consolidação B1

**Base:** `de4c39adae11` · **Escopo:** execução Claude e integração ao dispatcher.

## Instabilidade observada em B1.3

A primeira execução completa de B1.3 teve 27 de 28 suítes com código zero. Em `test-ci-wait.sh`, a CA7 “consulta também no fim da fatia” obteve duas consultas em vez de três, com exit `6` e resultado `continua`. A repetição isolada passou 52 de 52. O resultado inicial permanece registrado como falha.

Antes da integração de B1.4, comparei `ci-wait.sh` e `test-ci-wait.sh` na base e na branch. Os arquivos eram idênticos byte a byte. Executei as cópias alternadamente em área temporária, com HOME reduzido, rede isolada, o mesmo PATH e o `gh` falso das fixtures.

| Relógio | Base | Branch anterior à integração |
|---|---|---|
| Real, rodada 1 | 52/52, exit 0 | 52/52, exit 0 |
| Real, rodada 2 | 52/52, exit 0 | 51/52, exit 1 na mesma CA7 |
| Controlado, primeira consulta no mesmo segundo da abertura | Consultas em 0, 2 e 3 s, exit 6 | Consultas em 0, 2 e 3 s, exit 6 |
| Controlado, virada de um segundo antes da primeira consulta | Consultas em 1 e 3 s, exit 6 | Consultas em 1 e 3 s, exit 6 |

A reprodução controlada usou `date`, `sleep` e `gh` falsos com intervalo de 2 s e fatia de 3 s. O prazo usa o segundo de abertura, enquanto o agendamento usa o início de cada consulta. Se os dois marcos caem em segundos diferentes, a segunda consulta já começa no fim da fatia. O exit e a consulta final continuam corretos. A instabilidade é preexistente. Para uma correção separada, proponho controlar o relógio apenas nesse cenário da CA7 e verificar a consulta no prazo, preservando a cobertura do intervalo e do número de consultas sob cada condição. Os dois scripts de espera permanecem inalterados neste lote.

## Fronteiras depois de B1

- `stage-model.sh` guarda a fachada, a tabela de modelos e o escalonamento. O módulo interno `claude-exec.sh` contém os handlers legados `cmd_run` e `permission_mode`. O primeiro valida o comando run, consulta a detecção e a política de seleção, monta a chamada e faz `exec` do binário delegado.
- [Execution Result v1](09-resultado-tecnico.md) classifica a execução fora do modelo. `dispatch.sh` valida o objeto, preserva a projeção de códigos e diagnósticos e permite releitura do GitHub somente depois de sucesso técnico. O GitHub ainda decide avanço, portão humano, inconsistência e próximo passo.
- O dispatcher ainda escolhe Claude por compatibilidade. A projeção legada usa o código observado antes de interpretar causas, inclusive exit 2. O normalizador recebe esse código sem evidência de origem. Os detalhes nativos continuam disponíveis para o comentário de falha e o artefato `stage.json`.
- O `avancar` ainda combina `result`, `modelUsage`, `permission_denials`, texto sobre hooks/classificador e sinais do fluxo para relatório e escalonamento. A skill é executada pelo agente e suas decisões de texto não têm equivalência demonstrada com V1. Substituir esse julgamento pelo motivo normalizado poderia mudar quando um modelo sobe. O caminho de sessão e o encadeamento implementação → revisão continuam intactos. Os testes determinísticos cobrem detecção, saídas da fachada e promoção por alias. O comportamento da skill em sessão com modelo real permanece como aceite.

## Rollback e publicação

O checkpoint `ffb3dc4` preserva as duas tentativas de transferir `BASH_ENV` pelo Bash intermediário. As revisões encontraram diferenças de inicialização, atributos, `allexport` e colisão de nomes herdados. O módulo interno carrega as duas funções originais na posição em que eram declaradas e mantém a preparação no Bash da fachada. Essa é uma decisão de compatibilidade do adaptador Claude. B2.3 continua livre para executar `codex exec` com seu próprio contrato.

O teste diferencial usa a fachada original de `de4c39a` como fixture congelada, inclusive em clones rasos. A base e o candidato rodam no mesmo caminho temporário com o mesmo ambiente sintético. Compara ambientes completos, incluindo o ambiente recebido pelas sondas antes da inicialização, argumentos, diretório, entrada, canais, status e o registro de inicializações. A ordem dos campos de ambiente é irrelevante. O PID do delegado é comparado ao PID da própria fachada em cada execução. Nenhuma variável é filtrada. O cenário nameref depende do suporte do Bash em teste.

### Resultado da validação local

| Linha de base | Suítes com código zero | Verificações aprovadas | Grupos nativos pulados |
|---|---:|---:|---:|
| [A2](08-baseline.md) | 27 de 27 | 1.401 | 3 |
| B1.1 | 27 de 27 | 1.422 | 3 |
| B1.2 | 27 de 27 | 1.428 | 3 |
| B1.3, primeira execução | 27 de 28 | 1.463 | 3 |
| B1.3, incluindo a repetição de ci-wait | 28 de 28 | 1.464 | 3 |
| B1.4 | 28 de 28 | 1.478 | 3 |

A execução completa de B1.4, em clone temporário com HOME reduzido e rede isolada, teve zero falhas. Em relação a B1.3, `test-dispatch.sh` passou de 162 para 174 verificações e `test-claude-result.sh` de 36 para 38. As outras suítes conservaram suas contagens, incluindo `test-harness.sh` com 34, `test-stage-model.sh` com 62, `test-job-isolation.sh` com 165 e `test-ci-wait.sh` com 52. Em relação a A2, as outras contagens permanecem as do baseline. Os três grupos pulados são duas validações Claude e uma Antigravity.

Os casos novos cobrem falha do normalizador apesar de stdout de sucesso, objeto truncado, versão desconhecida, arquivo nativo ausente, limpeza e preservação de artefatos. As fixtures de exit 2 exercitam os dois caminhos do dispatcher sem evidência de origem, além dos casos de origem comprovada no teste do normalizador. O normalizador lê UTF-8 como o dispatcher legado, rejeitando UTF-16 e BOM.

### Reversão e distribuição

Reverta primeiro a leitura normalizada do dispatcher e seus casos de teste. A fachada, o executor e o contrato continuam utilizáveis de forma independente. O rollback de B1 inteiro restaura a invocação na fachada e retira os arquivos e testes adicionados pelos incrementos. Os formatos de `stage.json` e `stage.exit` e os passos `run`, `unmark` e `fail` dispensam migração de workflows.

Antes de publicar, aprovar um aumento de versão e incluir fachada, executor, normalizador e dispatcher no mesmo pacote. O manifesto de marketplace usa a raiz e o runner copia a árvore do plugin. O aceite deve confirmar que a atualização de uma instalação 0.63.0 carrega a nova árvore completa e que o rollback restaura um pacote completo.

Em ambiente descartável e mediante autorização, validar instalação e atualização Claude, delegação ao wrapper no runner, registro e sessão Antigravity conforme a SPEC-241 e prontidão do OpenCode na VM. Separar o aceite remoto dos casos de qualidade com modelo real. Verificar gates, revisão com base atualizada conforme a SPEC-135 e retenção do artefato bruto no repositório de teste.

### Identificadores dos aceites nativos

| ID | Aceite | Estado no candidato 0.64.0 |
|---|---|---|
| N0 | Validação estrutural do plugin Claude | Aprovado com Claude CLI 2.1.332 |
| N1 | Instalação, atualização e rollback offline | Aprovado em marketplace local e configuração descartável |
| N2 | Coexistência dos hooks compartilhados | Pendente, com coordenação da SPEC-246 |
| N3 | Execução real de uma etapa Claude | Pendente de autorização específica |
| N4 | Dispatcher completo no GitHub Actions | Pendente de autorização específica |
| N5 | Isolamento em VM sbx | Pendente de autorização específica |
| N6 | Qualidade do revisor | Pendente de autorização específica |

**N3, execução local.** Preparar um repositório e uma configuração Claude descartáveis, instalar o candidato por SHA e criar uma issue de teste se a etapa precisar ler o GitHub. Com autorização de provedor, conta e orçamento, usar uma credencial Claude dedicada e um token GitHub restrito ao repositório, quando necessário. Rodar uma única etapa pela fachada e registrar a versão, o código nativo, a classificação e o estado observado. O risco principal é uma ferramenta do modelo escrever fora do escopo do cenário. Restringir a etapa e o ambiente, sanitizar os artefatos e descartar credenciais, configuração e recursos de teste.

**N4, execução automatizada.** Preparar um repositório privado descartável com workflow do dispatcher e candidato fixado por SHA, runner efêmero e job de isolamento. Usar credenciais dedicadas para leitura do pacote, acesso limitado ao repositório e Claude, conforme o cenário autorizado. Disparar a etapa pelo evento previsto, observar labels e portões, conferir delegação ao wrapper, `stage.json`, `stage.exit` e a releitura do GitHub. Usar apenas issues e branches desse repositório. Conferir logs sanitizados, revogar credenciais e remover workflow, artefatos e recursos de teste.

## Proposta preliminar para B2

B1 oferece uma fronteira suficiente para acrescentar Codex local em incrementos. Começar comparando plugin nativo e descoberta de skills na versão suportada, com instalação exclusivamente Codex. Medir invocação explícita, resolução de recursos relativos, descoberta a partir da worktree, instalação, atualização e remoção. Usar o catálogo atual como fonte canônica.

Depois da escolha de distribuição, adicionar seleção explícita independente de `harness.sh`, um executor local de `codex exec` com modelo e esforço nativos, e um leitor de JSONL que produza V1 sob suas próprias regras. Iniciar com fakes e manter o dispatcher Claude como padrão. O aceite deve demonstrar uso de worktree da Fabrica, confirmação de portões por releitura do GitHub e funcionamento sem as outras CLIs. Revisão read-only do julgador, CI Codex e workers seguem incrementos e aceites próprios.

Referências para validar o empacotamento no piloto: [Skills Codex](https://learn.chatgpt.com/docs/build-skills), [plugins](https://learn.chatgpt.com/docs/plugins) e [execução não interativa](https://learn.chatgpt.com/docs/non-interactive-mode).
