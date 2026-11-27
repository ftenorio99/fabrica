# SPEC-245: empacota a fabrica para codex e configura a seleção por etapa

**Issue:** [#245](https://github.com/ftenorio99/fabrica/issues/245) · **PRD:** F10 como antecedente · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-27

## Contexto

B1 separou seleção, invocação Claude, resultado técnico e coordenação. B2.1 confirmou a descoberta de um plugin portátil na worktree com Codex CLI 0.172.0. O escopo novo de B2 é local e opt-in, conforme a issue e o [backlog](../docs/propostas/fabrica-codex-evolution/docs/04-plano-de-implementacao.md). A história F10 descreve a seleção Claude vigente.

A branch `feat/245-distribuicao-configuracao-codex` parte de `7d28c7cf6f4cfa005a052d26c99cf66ba8d69a7d`, que inclui `856f2f6` e `4232072`. Planeje integrar B1 antes de B2: depois de B1 incorporado, confira se a base de B2 contém o resultado de B1 e se o diff de B2 contém apenas esta issue. Qualquer publicação ou adequação de base fica para uma rodada autorizada.

## Objetivo

Gerar um plugin nativo Codex instalável por marketplace local e resolver uma seleção explícita de runtime e modelo para as quatro etapas de agente.

## Comportamento esperado

1. O operador informa a origem canônica e um diretório novo, fora da árvore da origem. O gerador escreve uma árvore portátil com manifesto de marketplace, manifesto de plugin, catálogo e recursos necessários. Entradas iguais produzem os mesmos caminhos, bytes e modos.
2. Instale no Codex por marketplace local. A skill aparece no catálogo com seu namespace mesmo ao listar a partir de uma worktree. A política de invocação é derivada da skill canônica.
3. A seleção usa um comando local separado. A opção explícita habilita apenas a resolução de configuração. O retorno é JSON para um futuro executor. A presença de uma CLI na máquina não muda a seleção.
4. Uma fonte inválida, um recurso faltante ou externo, um destino ocupado ou uma configuração inválida produzem diagnóstico em stderr e exit diferente de zero. O gerador publica o diretório final somente após validar toda a árvore. O resolvedor deixa stdout vazio no erro.

## Telas

nenhuma (Interface: não)

## Critérios de aceite

| ID | Critério | Verificação |
|---|---|---|
| CA1 | Entradas equivalentes geram caminhos, bytes e modos iguais. As fontes ficam intactas. Recurso obrigatório ausente ou destino existente gera erro e o destino fica intacto. | Unitário com duas gerações, hashes, recurso removido e destino com sentinela. |
| CA2 | As referências autorizadas entre skills, regras, scripts, agentes e templates resolvem no pacote. O frontmatter canônico determina a invocação implícita de cada skill. | Unitário com inventário completo, comparação dos conteúdos e verificação de `agents/openai.yaml` para cada skill. |
| CA3 | Credenciais, caches, configurações locais, worktrees e hooks de outros runtimes ficam fora do pacote. | Unitário com sentinelas em clone descartável e comparação do inventário. |
| CA4 | Instalar expõe o catálogo na worktree; repetir a instalação após gerar uma revisão de fixture atualiza o catálogo sem duplicá-lo; remover elimina as entradas do plugin. | Aceite local antes do merge com Codex CLI 0.172.0, marketplace local e `skills/list` no clone, na worktree e em subpasta dela. |
| CA5 | A seleção exige `--runtime codex` e preserva a semântica de `harness.sh detect`. A mera presença de Codex no PATH não seleciona runtime. | Unitário com executáveis falsos, chamadas com e sem seleção e suíte `test-harness.sh`. |
| CA6 | Cada etapa aceita ID nativo e esforço opcional. Esforço ausente fica omitido no retorno. A configuração exige `version: 1`. Configurações inválidas falham com stdout vazio. Labels e aliases Claude não influenciam a resolução. | Unitário com quatro etapas, versão ausente ou incompatível, campos ausentes, tipos errados, chaves desconhecidas ou repetidas e divergência de runtime. |
| CA7 | As suítes determinísticas dos runtimes atuais preservam os resultados do baseline B1, com falhas e pulos reportados separadamente. | Suíte isolada do CI. Usar 28 suítes e 1.478 verificações aprovadas como referência e registrar os três grupos nativos que ficaram pulados. |
| CA8 | Geração, instalação e configuração funcionam sem binários, credenciais ou configurações dos outros três runtimes. | Aceite local em HOME e CODEX_HOME temporários, com PATH reduzido e sem credenciais. |
| CA9 | O empacotador valida origem e destino, rejeita links simbólicos, referências locais externas e recursos fora do inventário. Diagnósticos omitem dados sensíveis. | Unitário com links na origem, no destino e nos recursos, traversal, caminhos absolutos, URLs de arquivo externas, alvo local fora do inventário e sentinelas sensíveis, em árvore descartável. |
| CA10 | Instalação, atualização e desinstalação preservam arquivos e configurações de Claude Code, OpenCode e Antigravity. | Aceite local com sentinelas em um segundo ambiente temporário. Comparar caminhos, modos e hashes depois de cada operação. |

**Casos adversariais não aplicáveis:** ID de outro usuário — não há API com registros de usuário. Sessão expirada — o fluxo local é offline e sem login. Abuso de limite — o fluxo não define cotas ou limites de entrada. Entrada inválida e repetição do ciclo estão cobertas em CA1, CA4, CA6 e CA9.

## Fora de escopo

- Executor definitivo, normalizador JSONL, aceites com modelo real e integração com dispatcher ou `avancar`.
- Hooks Codex ativos, agentes personalizados instaláveis definitivos e mudanças em harnesses existentes, autenticação, isolamento, máquina de estados, gates, labels e worktrees.
- Publicação do plugin, aumento da versão publicada e operações remotas de aceite.

## Desenho técnico

**Arquivos e módulos:** criar `codex/build-plugin.py`, `codex/resources.json`, `codex/plugin.json` e `codex/resolve-stage.py`. Manter `skills/`, `agents/`, `scripts/` e `templates/` como fonte editorial. Criar `scripts/test-codex.sh` para suites determinísticas e um roteiro separado em `codex/` para o aceite local com o binário real. Atualizar o manual em `docs/`. A árvore abaixo é saída gerada.

```text
<destino>/
  .agents/plugins/marketplace.json
  plugins/fabrica/
    plugin.json
    skills/<skill>/SKILL.md
    skills/<skill>/agents/openai.yaml
    skills/etapas/regras.md
    agents/revisor.md
    codex/resolve-stage.py
    scripts/...
    templates/...
    docs/...
```

Inventarie cada `skills/*/SKILL.md` canônico e copie somente os documentos, arquivos auxiliares e fontes operacionais autorizados. `agents/revisor.md` é referência compartilhada, sem registro de agente Codex. Inclua o resolvedor no pacote para que o operador possa chamá-lo a partir da instalação. O inventário cobre os diretórios que os Markdown referenciam, sem importar hooks de outras harnesses. Um caminho mencionado por código ou por placeholder, como `<diretório base desta skill>/../../scripts/stage-usage.py`, também consta da lista de dependências da skill. Documente a tradução ainda pendente de perguntas interativas, chamadas ao revisor, tokens de contexto/argumento e verificações opcionais ligadas a Claude. A prova de descoberta não promete execução integral do fluxo.

**Dados:** nenhum banco. Configuração por projeto em `.fabrica/codex-models.json`.

```json
{
  "version": 1,
  "triagem": {"runtime": "codex", "model": "id-triagem-disponivel"},
  "spec": {"runtime": "codex", "model": "id-spec-disponivel", "reasoning_effort": "medium"},
  "implementar": {"runtime": "codex", "model": "id-implementacao-disponivel"},
  "revisar": {"runtime": "codex", "model": "id-revisao-disponivel", "reasoning_effort": "high"}
}
```

Os IDs no exemplo são ilustrativos. Exija um objeto com `version` e exatamente as quatro etapas. `version` é o inteiro `1` e identifica a versão do formato de configuração, independente da versão publicada do plugin ou do contrato de resultado V1. Rejeite versão ausente, incompatível ou de outro tipo, inclusive booleano, para evitar interpretar dados com uma estrutura futura como se fossem da versão 1. Cada etapa tem `runtime: "codex"`, `model` como string não vazia sem espaços ou controles e, quando presente, `reasoning_effort` como uma string de esforço reconhecida pela configuração nativa da versão de referência. Rejeite campos desconhecidos, chaves duplicadas e `null` explícito. A verificação de disponibilidade do modelo e do esforço para a conta pertence ao aceite futuro.

**Interfaces:**

- `python3 codex/build-plugin.py --source <clone-fabrica> --output <diretorio-novo>`. Em sucesso, exit 0 e caminho do marketplace em stdout. Em erro, exit diferente de zero e diagnóstico em stderr. Use um temporário vizinho do destino e publique a árvore somente depois de completar as validações. Rejeite saída dentro da fonte, destino existente e componentes simbólicos nos caminhos de origem e saída. Uma falha descarta apenas a árvore temporária e preserva qualquer pacote anterior.
- `python3 codex/resolve-stage.py --runtime codex --stage <etapa> --project <diretorio>`. Em sucesso, exit 0 e um objeto com `runtime`, `stage`, `model` e `reasoning_effort` apenas quando configurado. A opção explícita seleciona o runtime. O arquivo indicado pelo diretório do projeto fornece os valores e o runtime de cada etapa deve coincidir com a opção. Ausência de opção, arquivo inválido ou runtime divergente sai com código diferente de zero e diagnóstico. A mesma entrada produz a mesma saída. O resolvedor apenas lê a configuração e emite o resultado. A resolução dispensa chamadas a modelos ou provedores e escritas no workflow. Sem fontes de ambiente, fallback global, aliases ou configuração por issue.

**Algoritmo e segurança de caminhos:**

1. Use um inventário explícito de arquivos regulares locais e dependências por skill. Valide nomes relativos, componentes de caminho e ausência de links em cada componente selecionado. Rejeite nomes absolutos, `..` em caminhos do inventário, links e arquivos especiais. Nomes ocultos autorizados no artefato são gerados separadamente.
2. Confira links Markdown locais e referências operacionais declaradas. Resolva a partir do arquivo onde aparecem. `../` é válido em referência documental apenas quando a normalização fica dentro da origem e o alvo está no inventário. Remova o fragmento da URL para validar o arquivo. Links HTTP(S) permanecem texto e o gerador não os segue. Rejeite recursos locais absolutos, esquemas de arquivo e alvos que escapem.
3. Abra os arquivos selecionados sem seguir links. Use travessia a partir do diretório raiz e abertura sem seguir links em cada componente em Linux, com leitura de arquivo regular. A árvore do pacote pode reproduzir caminhos apenas a partir dos nomes já validados. Preserve bytes dos arquivos canônicos e modos executáveis necessários, com modos normalizados para os demais.
4. Leia o frontmatter plano de cada skill registrada. `disable-model-invocation: true` gera `policy.allow_implicit_invocation: false`. Ausência ou valor `false` preserva invocação implícita. Campo duplicado ou valor inválido falha com diagnóstico. Gere JSON/YAML fixo, ordene nomes e use UTF-8 sem timestamps, nomes de máquina ou caminhos absolutos no conteúdo. Valide o inventário e as referências novamente no layout final antes de publicar.
5. Em erros, use diagnósticos por categoria. Identifique apenas etapas, campos conhecidos ou recursos já autorizados. Omita conteúdo de arquivos, valores inválidos, caminhos externos absolutos, credenciais e rastreamentos de exceção. Cubra stderr com sentinelas sensíveis.

**Instalação, atualização e rollback:** use `codex plugin marketplace add <destino>` e `codex plugin add fabrica@fabrica-local`, com manifesto apontando para `./plugins/fabrica`. Para atualizar, gere em um novo diretório, remova a inscrição anterior pelo procedimento de remoção e registre a nova fonte com o mesmo nome antes de instalar e conferir o catálogo. A remoção usa `codex plugin remove fabrica@fabrica-local` e `codex plugin marketplace remove fabrica-local`. Preserve a árvore anterior para reinstalação em caso de rollback. O aceite usa somente configuração descartável.

**Decisões:**

- Plugin portátil gerado e marketplace local (recomendação da triagem), com inventário explícito. A descoberta direta por links continua opção de desenvolvimento.
- CLI separada e um arquivo JSON por projeto (recomendação da triagem), preservando `harness.sh` e a política Claude. Alternativa considerada: compartilhar a tabela Claude, que acoplaria IDs de provedores.
- Usar a biblioteca padrão do Python, já presente em B1, para caminhos, JSON, subprocessos de teste e hashes. Os metadados YAML são emitidos a partir de valores fixos.

**Fontes da documentação:**

- Codex CLI 0.172.0, help local e experimentos B2.1. [Manifesto e marketplace](https://developers.openai.com/plugins/build/plugins), [skills](https://learn.chatgpt.com/docs/build-skills) e [configuração de esforço](https://learn.chatgpt.com/docs/config-file/config-reference).
- Python 3.14.4 no ambiente de referência. Biblioteca padrão, sem nova dependência.

**ADR:** [ADR 0022](../docs/adr/0022-distribuicao-e-selecao-codex.md), proposta para o contrato compartilhado por B2.1b a B2.5.

## Testes

- Unitários com fixtures em temporários para CA1–CA3, CA5–CA7 e CA9. Acione `bash scripts/test-codex.sh` e o filtro da suíte determinística de `.github/workflows/ci.yml`, preservando seus pulos. Teste links maliciosos de arquivo e diretório, entrada relativa externa, destino existente, JSON duplicado e dependência removida.
- Aceites locais para CA4, CA8 e CA10 com dois ambientes independentes: um exclusivamente Codex e outro com sentinelas de configuração. Use clone e worktree descartáveis, HOME e CODEX_HOME vazios, rede isolada e catálogo local. Exercite instalação, reinstalação e remoção, sem iniciar turnos.
- Preserve o registro da instabilidade preexistente de `test-ci-wait.sh`. Se reaparecer, informe a primeira falha e o resultado da repetição.

## Passos de produção

nenhum

## Riscos e dúvidas

- O mantenedor confirmou `.fabrica/codex-models.json`, as interfaces do empacotador e do resolvedor, o manifesto portátil e os nomes `fabrica-local` e `fabrica`.
- A implementação inventaria os recursos das skills existentes. A revisão deve conferir referências dinâmicas que a análise de links não captura.
- O cache pode mostrar uma revisão anterior. A atualização precisa comprovar no catálogo a versão de teste e a reversão precisa reinstalar a árvore anterior.
- Aceites de execução, agentes nativos, hooks e modelo efetivo permanecem etapas posteriores.

## Histórico

- 2026-11-27: criação a partir da issue #245, da triagem e da aprovação da estratégia de B2.1.
- 2026-11-27: incorpora as escolhas de interface, a versão do formato de configuração e os complementos de segurança aprovados para revisão no portão humano.
