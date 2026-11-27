# SPEC-246: fix: impede downgrade e janela sem proteção na atualização dos hooks do git

**Issue:** #246 · **PRD:** base (proteção da `main`, ADR 0002) · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-27

## Contexto
Os hooks globais do git da fábrica ([ADR 0002](../docs/adr/0002-protecao-da-main-por-hooks-do-git.md), SPEC-27) ficam numa pasta única por usuário, `${XDG_CONFIG_HOME:-~/.config}/fabrica/githooks`, apontada pelo `core.hooksPath` global. O Claude Code e o Antigravity rodam `scripts/setup-githooks.sh --check` em toda sessão; o OpenCode e o Codex, pelo `/fabrica:setup`.

Desde a #28, o `--check` recopia sempre que o `VERSION` difere da versão da origem, inclusive para uma versão menor (`setup-githooks.sh:49-51`). Ele também troca os arquivos com `rm -f` seguido de `cp` (`:36-42`). Uma fixture descartável reproduziu três efeitos:
- duas distribuições alternam os hooks a cada sessão;
- uma distribuição antiga reinstala um `fabrica-hook` sem a regra do `pre-merge-commit`, e o merge na `main` passa;
- uma cópia interrompida deixa a pasta sem `pre-commit` e sem `VERSION`, e o commit direto na `main` passa, sem aviso nenhum.

## Objetivo
Uma atualização dos hooks nunca deixa de ter as entradas de proteção, mesmo quando é interrompida. Uma execução automática nunca volta a uma versão anterior. A pasta só é reescrita quando o conteúdo precisa mudar. O rollback é sempre um gesto explícito do usuário.

## Comportamento esperado

### Termos
- **Origem:** a pasta `githooks/` da distribuição que roda o script. A versão dela é **S**, lida pela função `source_version` a partir de `.claude-plugin/plugin.json`. A leitura de `codex/githooks-version` entra nessa função na readequação da SPEC-245.
- **Destino:** `${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks`. O caminho e o `core.hooksPath` não mudam.
- **Entradas:** os arquivos sem ponto inicial no destino, exceto `VERSION` e `CONTENTS.sha256`. As entradas com ponto inicial são internas: `.lock`, `.break`, `.publicando`, `.publicando.<token>` e `.stage.<token>/`. O `rm -f "$dest"/*` do script antigo não as atinge.
- **Conjunto de proteção:** `fabrica-hook`, `pre-commit`, `pre-merge-commit` e `pre-push`.
- **Invólucro:** toda entrada exceto o `fabrica-hook`. O conteúdo é exatamente o modelo atual de três linhas: `#!/usr/bin/env bash`, `# Entrada do hook <nome>: regra da fábrica e hook do repositório.` e `exec "${0%/*}/fabrica-hook" "${0##*/}" "$@"`.
- **`CONTENTS.sha256`:** a primeira linha é `fabrica-githooks-contents v1 <versão>`; as seguintes são `<sha256>  <nome>`, uma por entrada, em ordem de nome.
- **Diário (`.publicando`):** um arquivo de texto com:
  - a linha `fabrica-githooks-journal v1`;
  - `dono <token da trava>`;
  - `de <versão|desconhecida>`, a versão I antes da publicação;
  - `para <versão>`, a versão T que está sendo publicada;
  - uma linha `anterior <sha256> <nome>` por entrada presente antes da publicação;
  - uma linha `alvo <sha256> <nome>` por entrada da origem.

  Ele não guarda conteúdo de arquivos, caminhos nem dados do ambiente.

### Ciclo de vida do diário
| Momento | O que acontece |
|---|---|
| Criação | No passo 3 da publicação, dentro da trava: escrito em `.publicando.<token>` e movido com `mv` para `.publicando`. Não existe diário parcialmente escrito com o nome final. |
| Durante a publicação | Não muda. Ele descreve o estado de partida e o de chegada, não o progresso; o progresso é lido nos hashes das entradas. |
| Fim normal | Apagado no passo 9, depois do `VERSION` e da remoção das obsoletas. |
| Falha num `mv` | Fica no lugar. A saída é `falha publicacao`. |
| Execução seguinte | Dentro da trava, o diário é **válido** quando o formato confere, o `fabrica-hook` está presente e cada entrada presente tem o hash `anterior` ou o `alvo` do próprio nome. Válido, ele leva ao estado `interrompida`; inválido, é apagado e o estado é lido sem ele. |
| `.publicando.<token>` órfão | É um diário que não chegou a ser publicado. Apagado no passo 1 da publicação seguinte. |
| Script antigo | Não lê nem apaga o diário, porque o `rm -f "$dest"/*` não pega nomes com ponto. Se ele reescrever a pasta, o diário fica inválido e é apagado na execução nova seguinte. |

### Estado da instalação
O script relê o estado sem escrever nada, e de novo dentro da trava antes de decidir.

| Estado | Condição |
|---|---|
| `ausente` | O `core.hooksPath` global é diferente do destino. |
| `interrompida` | Existe um `.publicando` **válido**: cada entrada presente tem o hash `anterior` ou o `alvo` do próprio nome, e o `fabrica-hook` está presente. |
| `integra` | `VERSION` válido; `CONTENTS.sha256` válido com a mesma versão; o conjunto de entradas e os hashes são exatamente os do `CONTENTS.sha256`; todas as entradas são arquivos regulares executáveis. |
| `legada` | `VERSION` válido, sem `CONTENTS.sha256`, com o conjunto de proteção presente e executável. |
| `danificada` | Qualquer outro caso. |

Um `.publicando` inválido está obsoleto (por exemplo, quando um script antigo reescreveu a pasta). Ele é ignorado na leitura e apagado dentro da trava.

**Versão instalada comprovada (I):** a maior versão válida entre o `VERSION`, a versão do `CONTENTS.sha256` e, no estado `interrompida`, o `para` do diário. Quando nenhuma é válida, I é `desconhecida`.

### Instalação protegida ou com integridade não garantida
- **Protegida:** o estado é `integra`. O conjunto de proteção está presente e executável, o `fabrica-hook` tem os bytes registrados, os invólucros seguem o modelo, e as regras em vigor são exatamente as da versão registrada.
- **Integridade não garantida:** qualquer outro estado com `core.hooksPath` apontado para o destino (`legada`, `interrompida` ou `danificada`). A pasta pode até estar protegida, mas o script não consegue provar isso a partir dos registros:
  - na `legada`, os bytes do `fabrica-hook` não têm registro;
  - na `interrompida`, as regras são as da versão anterior ou as da alvo;
  - na `danificada`, nada está garantido.
- As saídas refletem essa distinção:
  - `ok`, `atualizado`, `mais-novo` e `divergente` só saem de um estado protegido, ou que ficou protegido nesta execução;
  - `reparado` diz que a instalação não estava garantida e agora está;
  - `falha danificada`, `falha versao-desconhecida`, `falha interrompida` e `ocupado incerta` dizem que a integridade continua sem garantia;
  - `ocupado integra` diz que outra execução tem a trava, mas a leitura sem escrita encontrou um estado protegido.

### Combinações de `VERSION`, `CONTENTS.sha256` e diário
Leitura feita dentro da trava. T é o `para` do diário.

| `VERSION` | `CONTENTS.sha256` | Diário | Interpretação | I |
|---|---|---|---|---|
| válido = v | v, hashes conferem | ausente | `integra` | v |
| válido = v | ausente | ausente | `legada` (script antigo) | v |
| válido = v | v, hashes não conferem | ausente | `danificada` (edição, falha parcial ou script antigo no meio) | v |
| válido = v | versão w ≠ v | ausente | `danificada` (metadados de publicações diferentes) | max(v, w) |
| ausente ou inválido | válido = w | ausente | `danificada` | w |
| ausente ou inválido | ausente ou inválido | ausente | `danificada` | desconhecida |
| qualquer | qualquer | válido, todas as entradas com hash `anterior` | publicação que não trocou nada: o diário é descartado e a leitura recomeça sem ele | conforme a nova leitura |
| v = de | de | válido, alguma entrada com hash `alvo` | `interrompida` antes dos metadados | max(v, T) = T |
| de | T | válido | `interrompida` entre o `CONTENTS.sha256` e o `VERSION` | T |
| T | T | válido | `interrompida` antes da remoção das obsoletas ou do diário | T |
| qualquer | qualquer | inválido | diário apagado; leitura pelas linhas sem diário | conforme a linha |

A versão I é sempre a **maior** evidência válida. Uma evidência inválida nunca baixa I. Por isso nenhuma combinação de metadados velhos com um diário mais novo, ou o inverso, permite que uma origem menor que a maior versão registrada sobrescreva o `fabrica-hook`.

### Decisão das execuções automáticas
Valem para o `--check` e para a instalação sem `--allow-downgrade`.

| Estado | Condição | Ação | Saída |
|---|---|---|---|
| ausente | — | nenhuma no `--check`; a instalação segue as regras de hoje e publica | `ausente` |
| integra | entradas iguais às da origem | nada | `ok` |
| integra | S > I | publica S | `atualizado S` |
| integra | S < I | nada | `mais-novo I` |
| integra | S = I com conteúdo diferente | nada | `divergente I` |
| legada | S > I | publica S | `atualizado S` |
| legada | S = I com entradas iguais às da origem | grava só o `CONTENTS.sha256`, sem tocar nos hooks | `ok` |
| legada | S = I com conteúdo diferente | nada | `divergente I` |
| legada | S < I | nada | `mais-novo I` |
| interrompida | S ≥ I | publica S | `reparado S` |
| interrompida | S < I | conclui com os bytes da origem que são **iguais** aos `alvo` do diário, mais os metadados do diário (`CONTENTS.sha256`, `VERSION`, remoção das obsoletas) | `reparado I` |
| interrompida | S < I e falta um arquivo cujo `alvo` a origem não tem igual | nada nos hooks | `falha interrompida` |
| interrompida | nenhuma entrada foi trocada ainda (todas com o hash `anterior`) | descarta o diário e decide de novo como integra ou legada | conforme a nova decisão |
| danificada | I conhecido e S ≥ I | publica S | `reparado S` |
| danificada | I conhecido e S < I | só cria os invólucros **ausentes**, se o `fabrica-hook` estiver presente; nunca sobrescreve | `falha danificada` |
| danificada | I desconhecido e `fabrica-hook` com os mesmos bytes da origem | publica S | `reparado S` |
| danificada | I desconhecido nos outros casos | só cria os invólucros ausentes, se o `fabrica-hook` estiver presente | `falha versao-desconhecida` |

A linha "nenhuma entrada foi trocada ainda" é avaliada antes das demais linhas de `interrompida`.

**Regra de segurança da recuperação:** uma execução automática só sobrescreve um arquivo existente com conteúdo diferente em dois casos: quando S ≥ I e I é conhecido, ou quando os bytes novos são iguais aos que o diário registrou como alvo. Ela pode criar um invólucro ausente, porque todo invólucro só repassa para o `fabrica-hook` presente. Pode também devolver o modo 0755 a uma entrada cujos bytes conferem com o registro (`CONTENTS.sha256` ou diário), porque isso não muda nenhuma regra. Essa devolução é feita antes da decisão da tabela: se a instalação fica `integra` depois dela, a saída é `reparado I`; senão, a decisão segue com o estado relido. O `fabrica-hook` nunca é criado nem trocado sem que S ≥ I seja provado.

### `fabrica-hook` ausente, danificado ou não executável
| Situação | Efeito no git | Estado | Recuperação automática |
|---|---|---|---|
| Ausente | Os invólucros presentes falham no `exec` e o git recusa a operação (falha fechada). Sem invólucro, a operação passa sem hook. | `danificada` (o diário fica inválido) | Com I conhecido e S ≥ I, publica S (`reparado S`). Senão, nada é criado (`falha danificada` ou `falha versao-desconhecida`), porque criar o `fabrica-hook` a partir de uma origem menor ou de versão não comprovada seria um downgrade possível. |
| Presente, com bytes diferentes do registrado | Comportamento desconhecido: pode deixar passar | `danificada` | Com I conhecido e S ≥ I, publica S. Com I desconhecido e bytes iguais aos da origem, publica S. Nos outros casos, não toca no arquivo e responde com `falha`: a integridade não é garantida, e o aviso do `SessionStart` pede o setup da versão I ou mais nova, ou um `--allow-downgrade` explícito. |
| Presente, com bytes registrados, mas sem permissão de execução ou sem ser arquivo regular | Os invólucros falham no `exec` e o git recusa a operação (falha fechada) | `danificada` | Bytes conferem e é arquivo regular: devolve o modo 0755 sem trocar o conteúdo, em qualquer versão de origem, e responde `reparado I`. Não é arquivo regular (pasta, symlink): segue a linha anterior. |

A mesma tabela vale para um invólucro ausente, alterado ou sem execução, com uma diferença: o invólucro ausente pode sempre ser criado, porque o modelo dele é fixo e ele só repassa para o `fabrica-hook`.

**Recuperação segura ou rollback intencional:**
- A recuperação é automática e nunca baixa a versão.
- O rollback, que também cobre a troca de uma instalação de versão desconhecida, só acontece com `setup-githooks.sh --allow-downgrade <S>`. Ele roda só na instalação, com `<S>` igual à versão da origem, como confirmação. Publica S pelo mesmo algoritmo e responde `revertido S`.
- O `--check` recusa a opção com saída 2.
- O `/fabrica:setup` só a oferece depois de confirmar com o usuário pelo AskUserQuestion.

### Publicação
A publicação roda sempre dentro da trava.
1. Apaga os `.stage.*` e `.publicando.*` órfãos, que pertenciam a donos de trava anteriores.
2. **Prepara** a origem em `.stage.<token>/`, dentro do próprio destino, o que garante o mesmo sistema de arquivos para o `rename`. Copia, aplica modo 0755, calcula os hashes e confere:
   - os nomes seguem `^[a-z0-9-]+$`;
   - o conjunto de proteção está completo;
   - cada invólucro segue o modelo;
   - os hashes da cópia batem com os da origem lidos antes da cópia.

   Grava `CONTENTS.sha256` e `VERSION` no stage. Qualquer falha aqui apaga o stage e sai com `falha preparacao`, sem tocar no destino.
3. Confere que ainda é dono da trava e grava o diário em `.publicando.<token>`, depois `mv` para `.publicando`.
4. `mv` do `fabrica-hook` do stage para o destino.
5. `mv` de cada invólucro, em ordem de nome.
6. Confere de novo que ainda é dono da trava e faz `mv` do `CONTENTS.sha256`.
7. `mv` do `VERSION`.
8. Remove as entradas que não estão no alvo. O alvo sempre contém o conjunto de proteção, então nenhuma entrada de proteção é removida.
9. Apaga o diário e o stage.

Uma falha num `mv` interrompe nesse ponto, preserva o diário e sai com `falha publicacao`. A execução seguinte encontra o estado `interrompida`.

**Por que os estados mistos são seguros:**
- Nenhum nome é removido antes do passo 8, e o `rename` troca o arquivo no lugar. Assim, toda entrada que existia antes continua existindo e executável em qualquer instante.
- O `fabrica-hook` vai antes dos invólucros e nunca é removido. Todo invólucro presente chama um `fabrica-hook` presente, com o conteúdo completo de uma das duas versões, porque o stage está no mesmo sistema de arquivos e o `rename(2)` é atômico.
- Todos os invólucros têm o mesmo contrato (`fabrica-hook <nome> [args]`). Por isso um invólucro novo junto de um antigo dá o mesmo resultado. Um nome novo que ainda não chegou só deixa de rodar, como na versão anterior.
- Do passo 4 em diante, as regras em vigor são as da versão alvo. Antes dele, são as da anterior.

| Ponto da interrupção | Estado observado | Proteção | Próxima execução |
|---|---|---|---|
| antes do diário (passos 1–3) | destino intacto, stage órfão | anterior | apaga o stage e decide normalmente |
| diário gravado, nada trocado | `interrompida`, todas as entradas com hash `anterior` | anterior | descarta o diário e decide de novo |
| depois do `fabrica-hook` | `interrompida`, regra alvo, invólucros mistos | alvo | conclui (S ≥ T) ou conclui com bytes iguais |
| durante os invólucros | idem | alvo | idem |
| antes do `CONTENTS.sha256` ou do `VERSION` | entradas todas alvo, metadados antigos | alvo | conclui só com os metadados do diário, sem tocar nos hooks |
| antes de remover as obsoletas ou o diário | alvo completo, obsoletas presentes | alvo | conclui a remoção |

### Trava
- **Trava:** o symlink `.lock` no destino, criado com `ln -s <identidade> .lock`. A criação é atômica e falha se o nome já existir, então não há trava parcialmente inicializada: a identidade nasce junto com o nome.
- **Identidade:** `fabrica-githooks-lock v1 host=<uname -n> pid=<pid> start=<marca> token=<aleatório>`. A marca de início vem do campo 22 de `/proc/<pid>/stat` ou, sem `/proc`, de `LC_ALL=C ps -o lstart= -p <pid>`.
- **Dono vivo:** mesmo host, `kill -0` bem-sucedido (ou recusado por permissão) e marca de início igual. Com o host diferente, sem como obter a marca ou com qualquer dúvida, o dono conta como vivo. A trava nunca é removida por idade.
- **Dono morto:** mesmo host e processo inexistente, ou PID reutilizado (processo vivo com outra marca de início).
- **Quebra de trava de dono morto:**
  1. criar o symlink `.break` com a própria identidade;
  2. reler o `.lock` e conferir que continua com a mesma identidade morta;
  3. remover o `.lock`;
  4. remover o próprio `.break`, conferindo a identidade;
  5. tentar de novo a aquisição normal.

  Um `.break` existente bloqueia outras quebras. Um `.break` de dono morto **não** é removido automaticamente: a saída é `ocupado incerta`, e o stderr diz para seguir o procedimento manual abaixo.
- **Liberação:** remove o `.lock` só se ele contiver a própria identidade. Um dono que encontre outra identidade não remove nada e sai com `falha trava`.
- **Condições de corrida entre conferir a identidade e remover:**
  - *Na quebra:* enquanto existe um `.lock`, ninguém mais consegue criar outro (`ln -s` falha), e enquanto existe o `.break`, ninguém mais quebra. Assim, entre reler o `.lock` (passo 2) e removê-lo (passo 3), só o dono do `.break` pode mexer nele, e o próprio dono morto não volta. A conferência e a remoção ficam serializadas pelo `.break`.
  - *Na liberação:* entre ler a própria identidade e remover o `.lock`, outro processo só poderia trocar a trava se a quebrasse, e isso exige julgar o dono morto. Um dono vivo, no mesmo host, com a mesma marca de início, nunca é julgado morto.
  - *Resíduo:* a regra falha se dois ambientes compartilharem o destino e o mesmo nome de host com espaços de PID diferentes (contêineres com a home montada). Nesse caso, um dono vivo pode parecer morto. Isso fica nos limites do modelo.
  - *Conferência a cada fase:* o dono confere que ainda tem a trava antes de gravar o diário (passo 3) e antes dos metadados (passo 6). Se a perdeu, para sem continuar a publicação e sai com `falha trava`. O diário permite à execução seguinte concluir ou descartar.

### Recuperação manual de um `.break` abandonado
Um `.break` só fica abandonado se um processo morrer entre os passos 1 e 4 da quebra, que duram milissegundos. O `protect-main.sh` recusa comandos do agente que citam a pasta dos hooks, por isso o procedimento é **do usuário**, no terminal:
1. Confirme que nenhum setup está rodando: `pgrep -af setup-githooks.sh` não deve listar nada.
2. Leia a identidade: `readlink ~/.config/fabrica/githooks/.break` (ou o caminho com `XDG_CONFIG_HOME`). Confira que o host é esta máquina e que o PID não existe (`kill -0 <pid>` falha) ou é de outro processo.
3. Remova o `.break`: `rm ~/.config/fabrica/githooks/.break`.
4. Rode `bash <clone>/scripts/setup-githooks.sh --check`. Com um `.lock` de dono morto, ele é quebrado pelo caminho normal.

O mesmo procedimento vale para um `.lock` de outro host ou de dono que não dá para conferir, que o script nunca quebra: confirme que o dono não está rodando e remova o `.lock` à mão. O guia `docs/solucao-de-problemas.md` traz esses passos.
- **Espera:** tenta a cada 0,2 s, até 5 s no `--check` e 30 s na instalação. O `SessionStart` tem timeout de 15 s. Esgotado o prazo, faz a leitura sem escrita e responde `ocupado integra` ou `ocupado incerta`.

### Diagnósticos
O formato da saída do `--check` não muda: uma linha no stdout. A saída é 0, exceto `falha <código>` (1) e uso inválido (2). Os códigos de `falha` são `origem-invalida`, `preparacao`, `publicacao`, `interrompida`, `danificada`, `versao-desconhecida` e `trava`. O detalhe vai para o stderr, sem conteúdo de arquivos.

| Saída | `session-start.sh` (Claude: texto; Antigravity: `injectSteps`) |
|---|---|
| `ok`, `atualizado`, `mais-novo`, `ocupado integra` | silencioso |
| `reparado <v>` | informa a recuperação |
| `ocupado incerta` | informa que não deu para garantir a integridade |
| `divergente <v>` | aviso |
| `ausente` | aviso, como hoje |
| `falha <código>`, saída diferente de 0 ou linha não reconhecida | aviso |

As mensagens são fixas, por saída, e só interpolam versões. O `/fabrica:setup` (passo 4) mostra cada saída ao usuário e só pergunta pela instalação em `ausente`. Em `falha versao-desconhecida`, `falha danificada` e `divergente`, explica as opções e só roda `--allow-downgrade <S>` com a confirmação do usuário.

### Distribuições legadas
Uma distribuição com o script anterior (o cache de um plugin antigo, uma cópia do `agy`, um pacote Codex anterior a esta issue, um clone numa branch antiga) **não** respeita a trava, o diário nem a monotonicidade:
- recopia sempre que o `VERSION` difere da versão dela;
- apaga o `CONTENTS.sha256`;
- abre a janela do `rm`/`cp`.

O script novo não impede isso. Ele detecta o resultado como `legada` ou `danificada` e volta para a versão maior na execução seguinte. A proteção completa só vale depois que todas as distribuições ativas da máquina forem atualizadas.

### Limites do modelo de segurança
O modelo cobre falhas acidentais e operacionais, como interrupção, disco cheio, execuções simultâneas e distribuições de versões diferentes. Não cobre sabotagem nem processos que ignoram o protocolo, como já faz a ADR 0002.

| Limite | O que continua possível | O que a spec garante |
|---|---|---|
| Distribuições legadas | Downgrade, apagar o `CONTENTS.sha256`, abrir a janela do `rm`/`cp` e ignorar a trava | A execução nova seguinte detecta o resultado, volta para a maior versão comprovada e avisa quando não consegue |
| Processos que ignoram a trava (edição manual, outras ferramentas, mesmo UID) | Qualquer mudança na pasta, inclusive no meio de uma publicação | O resultado é lido como `danificada` ou diário inválido e segue a regra de segurança da recuperação |
| `root` ou processos com o mesmo UID com intenção hostil | Tudo | Nada; fora do modelo |
| Home em rede (NFS) ou compartilhada entre máquinas | `rename` e `symlink` dependem do servidor; a vida do dono não é verificável de outro host | A trava de outro host nunca é quebrada: no pior caso, `ocupado` até a remoção manual. A atomicidade vale só se o servidor a garantir. |
| Contêineres com o mesmo nome de host e outro espaço de PIDs sobre o mesmo destino | Um dono vivo pode parecer morto | Nenhuma; documentado como resíduo |
| macOS | Sem `/proc`: a marca de início vem de `ps -o lstart`, com resolução de segundo, e o hash do `shasum -a 256`. O CI (Ubuntu) não testa esse caminho. | Sem a marca, o dono conta como vivo (nunca quebra); sem ferramenta de hash, `falha preparacao` sem escrita |
| Sistema de arquivos que não cumpra o `rename` atômico | Estado parcial de um arquivo | O stage fica dentro do destino para usar o mesmo sistema de arquivos; fora disso, nada |
| Janela entre a criação do `.break` e sua remoção | `.break` abandonado se o processo morrer ali | Bloqueia de forma segura (`ocupado`); recuperação manual documentada |
| Repositórios com `core.hooksPath` local, `--no-verify` pelo humano | Passam sem os hooks da fábrica | Inalterado (ADR 0002) |

## Telas
nenhuma (Interface: não)

## Critérios de aceite
Todos os testes rodam com HOME, `XDG_CONFIG_HOME`, `GIT_CONFIG_GLOBAL` e `GIT_CONFIG_NOSYSTEM` temporários, com duas ou mais cópias da distribuição em versões diferentes.

| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com a instalação íntegra e entradas iguais às da origem, o `--check` responde `ok` sem escrever nada (inode, modo e mtime de todas as entradas inalterados), mesmo com a versão de plugin da origem diferente da instalada. | unitário |
| CA2 | Com a instalação íntegra, S < I e conteúdo diferente, responde `mais-novo I` e não muda nenhum arquivo. | unitário |
| CA3 | Com S > I, responde `atualizado S`. Antes de cada `rename`, o conjunto de proteção está presente e executável, e o resultado final é `integra` em S. | unitário com um `mv` falso no PATH que registra o estado antes de chamar o real |
| CA4 | Falha na preparação (arquivo ilegível na origem, invólucro fora do modelo, entrada de proteção ausente na origem, ferramenta de hash ausente, versão da origem inválida) deixa o destino byte a byte igual, sai com 1 e responde `falha preparacao` ou `falha origem-invalida`. | unitário com hashes antes e depois |
| CA5 | Uma instalação danificada (entrada editada ou ausente, `VERSION` ou `CONTENTS.sha256` ausente) com I conhecido e S ≥ I responde `reparado S` e termina íntegra. Uma entrada com os bytes registrados mas sem permissão de execução tem o modo 0755 devolvido, sem troca de conteúdo, em qualquer versão de origem, e a saída é `reparado I`. | unitário |
| CA6 | Com a instalação íntegra, S = I e conteúdo diferente, responde `divergente I` e não escreve nada. | unitário |
| CA7 | Vinte pares de `--check` simultâneos de duas versões terminam com a instalação íntegra na versão maior, e nenhuma execução sai com `atualizado` para a menor depois que a maior foi publicada. | unitário com laço concorrente |
| CA8 | Uma instalação legada (só `VERSION`, no formato atual) com S > V responde `atualizado S`. Com S = V e bytes iguais, responde `ok`, grava só o `CONTENTS.sha256` (inode das entradas inalterado), e a execução seguinte responde `ok` sem escrever nada. | unitário com fixture gerada pelo script da `main` |
| CA9 | Na instalação, `--allow-downgrade <S>` publica S menor que I pelo mesmo algoritmo e responde `revertido S`. Com `<S>` diferente da versão da origem, ou no `--check`, sai com 2 sem escrever nada. | unitário |
| CA10 | Depois de cada caminho dos CAs 1–9 e de cada interrupção do CA13, estes casos continuam recusados num repositório temporário: commit na `main`, `merge --no-ff` na `main` e push para a `main` de um remoto local. O hook de mesmo nome do repositório continua encadeado. | unitário |
| CA11 | O `session-start.sh` segue a tabela de diagnósticos, saída por saída, no formato do Claude (texto) e do Antigravity (`{"injectSteps":…}`). Fica silencioso em `ok`, `atualizado`, `mais-novo` e `ocupado integra`; informa em `reparado` e `ocupado incerta`; avisa em `divergente`, `ausente`, `falha`, saída diferente de 0 e linha não reconhecida. | unitário com um `setup-githooks.sh` falso por saída |
| CA12 | Uma instalação danificada com I > S, comprovada pelo `VERSION` ou só pelo `CONTENTS.sha256`, não sofre downgrade: o `fabrica-hook` e todo arquivo existente ficam byte a byte iguais. Só os invólucros ausentes são criados, e a saída é `falha danificada`. Com I desconhecido e um `fabrica-hook` diferente do da origem, a saída é `falha versao-desconhecida`, com a mesma restrição. Um `fabrica-hook` ausente só é criado quando S ≥ I com I conhecido. Nas combinações de `VERSION`, `CONTENTS.sha256` e diário da tabela da spec, I é sempre a maior evidência válida. | unitário |
| CA13 | Uma interrupção depois do k-ésimo `rename`, para cada k da publicação (com o `mv` falso, que mata o script após k chamadas), deixa o conjunto de proteção presente e executável. O `fabrica-hook` fica com os bytes da versão anterior ou da alvo, e nenhuma entrada que existia antes some. | unitário |
| CA14 | Para cada ponto de interrupção do CA13, a execução seguinte identifica o estado `interrompida`. Com S ≥ T, responde `reparado S` e termina íntegra. Com S < T, conclui só usando bytes iguais aos alvos do diário (`reparado T`), ou responde `falha interrompida` sem tocar nos hooks. Com o diário gravado e nada trocado, descarta o diário e decide de novo. Em nenhum caso o `VERSION` termina abaixo de T sem `--allow-downgrade`. | unitário |
| CA15 | Um `.lock` de processo vivo (PID e marca de início iguais) não é removido, mesmo com o mtime recuado em uma hora: o `--check` espera até 5 s e responde `ocupado integra` ou `ocupado incerta`, com o `.lock` intacto. Um `.lock` de processo encerrado, ou de PID reutilizado com outra marca de início, é quebrado e adquirido. Um `.lock` de outro host não é quebrado. | unitário com um `sleep` como dono vivo e um PID de processo já terminado |
| CA16 | Um dono cuja trava foi trocada por outra identidade não remove o `.lock` novo ao liberar e sai com `falha trava`. Duas quebras simultâneas da mesma trava morta resultam em uma única aquisição. Um `.break` de dono morto não é removido automaticamente e resulta em `ocupado incerta`. Um dono que perde a trava antes do diário ou dos metadados para a publicação e sai com `falha trava`. | unitário |
| CA17 | A emenda à ADR 0002, `docs/solucao-de-problemas.md` e `docs/comandos.md` descrevem as saídas, o rollback com `--allow-downgrade`, o procedimento de migração por runtime, a recuperação manual de um `.break` ou `.lock` abandonado e os limites de coexistência com distribuições legadas, sem prometer proteção contra elas. | manual, na revisão |

## Fora de escopo
- Ler `codex/githooks-version` e validar a paridade entre `codex/plugin.json` e `.claude-plugin/plugin.json`: entram na readequação da SPEC-245, sobre a função `source_version`.
- Proteções do agente no Codex (C1); a conferência dos arquivos pelo `protect-main.sh` (hoje ele só confere o `core.hooksPath`); repositórios com `core.hooksPath` local; o runner do dispatcher (ADR 0021).
- Impedir que distribuições legadas façam downgrade.
- Posse de issues e recuperação de execução (D1/D2).
- Mudar o contrato dos invólucros. Uma mudança futura precisa de um novo desenho de publicação, porque a prova dos estados mistos depende desse contrato.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/setup-githooks.sh`: reescrito em funções:
  - `source_version`;
  - `semver_valid` e `semver_cmp`;
  - `hash_file` (`sha256sum`; sem ele, `shasum -a 256`);
  - `read_state`;
  - `lock_acquire`, `lock_release`, `lock_owner_alive` e `lock_break`;
  - `stage`, `publish`, `recover` e `decide`.

  As opções passam a ser `[--check] [--force] [--allow-downgrade <versão>]`. O texto de instalação de hoje continua.
- `hooks/session-start.sh`: troca o `== ausente` pela tabela de diagnósticos, com mensagens fixas por saída e as duas formas de saída de hoje.
- `skills/setup/SKILL.md`: o passo 4 trata as saídas novas.
- `scripts/test-setup-githooks.sh` (novo): CA1–CA9 e CA12–CA16, mais o `mv` falso. O CI já pega `scripts/test-*.sh` sem mudança no workflow.
- `scripts/test-protect-main.sh`: o CA5 do SPEC-27 é ajustado às saídas novas, e o CA10 é acrescentado.
- `scripts/test-session-start.sh`: o CA11.
- `AGENTS.md`: cita a suíte nova na lista de testes.
- `docs/adr/0002-protecao-da-main-por-hooks-do-git.md` (emenda), `docs/solucao-de-problemas.md` e `docs/comandos.md`.
- `.claude-plugin/plugin.json`: a versão sobe no PR. O número é definido na preparação da integração.

**Dados:** os arquivos `CONTENTS.sha256`, `.publicando` e `.lock` no destino, nos formatos de "Termos". O `VERSION` continua com uma linha.

**Interfaces:**
- `setup-githooks.sh --check`: uma linha no stdout, conforme os diagnósticos.
- `setup-githooks.sh [--force]`: instalação, como hoje, com as mesmas regras de decisão.
- `setup-githooks.sh --allow-downgrade <versão>`: instalação explícita.

**Política de comparação de versões:**
- Formato `^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$`: sem prefixo, sem zeros à esquerda e no máximo 9 dígitos por campo, para caber na aritmética do bash.
- Comparação numérica campo a campo.
- Uma versão da origem fora do formato é `falha origem-invalida`, sem escrita.
- Uma versão instalada fora do formato não conta como evidência; nunca é tratada como zero.
- Não há versão própria dos hooks: a versão do plugin dá a ordem, e o `CONTENTS.sha256` dá a identidade.

**Decisões:**
- Publicar por stage e `rename` arquivo a arquivo, dentro do próprio destino, mantendo caminho e `core.hooksPath`, porque o `protect-main.sh:67` e o `session-start.sh` conferem esse caminho, e um stage dentro do destino garante o mesmo sistema de arquivos (recomendação da triagem). Alternativa descartada: diretórios versionados com symlink, porque a troca de pasta para symlink numa instalação existente não é atômica.
- Trava por symlink criado com `ln -s`, com a identidade no próprio alvo (recomendação da triagem). Alternativa descartada: `mkdir` com um arquivo de dono, que deixa uma trava sem dono entre as duas operações; e `flock`, que não existe no macOS.
- Sem versão própria dos hooks (recomendação da triagem). Alternativa descartada: uma terceira versão, que seria mais uma fonte para manter em paridade.
- A ordem do `fabrica-hook` primeiro, depois os invólucros, depois os metadados, porque assim as regras novas valem a partir do primeiro `rename` e a falta dos metadados marca a publicação incompleta. Alternativa descartada: metadados primeiro, que declararia uma versão ainda não instalada.
- Uma suíte nova `test-setup-githooks.sh`, porque o `test-protect-main.sh` já tem 162 casos de outro assunto (PreToolUse). Alternativa descartada: estender só o CA5 dele.
- Injeção de falha por um `mv` falso no PATH, como os falsos de `gh` e `claude` das suítes atuais. Alternativa descartada: uma variável de ambiente de teste no script de produção.

**Fontes da documentação:**
- git 2.53 (`man githooks`): `core.hooksPath` substitui `.git/hooks`, e uma entrada ausente faz o hook não rodar — confirmado na fixture.
- `rename(2)` e `symlink(2)`: atômicos no mesmo sistema de arquivos; o `symlink` falha com `EEXIST` — conhecimento do modelo, conferido no Linux com GNU bash 5.3 e uutils coreutils 0.10.0 (`ln`). No macOS, não verificado.
- `/proc/<pid>/stat`, campo 22 (`starttime`) — `man 5 proc`, conhecimento do modelo, não verificado nesta etapa.
- gh 2.105.0 — o desenho não cita nenhum comando do `gh`.

**ADR:** emenda à [ADR 0002](../docs/adr/0002-protecao-da-main-por-hooks-do-git.md), nas consequências, sobre a atualização monotônica e protegida. Não há ADR nova.

## Testes
- `bash scripts/test-setup-githooks.sh`:
  - fixtures geradas a partir de cópias do plugin com `.claude-plugin/plugin.json` em versões diferentes e um `fabrica-hook` marcado por versão;
  - o `mv` falso no PATH registra o estado antes de cada `rename` e mata o script na k-ésima chamada (CA3, CA13, CA14);
  - um `sleep` em segundo plano serve de dono vivo, o PID de um processo já encerrado de dono morto, e uma marca de início trocada simula PID reutilizado (CA15, CA16);
  - laços concorrentes (CA7);
  - uma fixture legada é gerada com o script da `origin/main` por `git show` (CA8).
- **Testes de reprodução que falham hoje e passam com a correção:** CA2 (downgrade), CA4 e CA13 (janela) e CA7.
- `bash scripts/test-protect-main.sh` (CA5 ajustado, CA10) e `bash scripts/test-session-start.sh` (CA11).
- **Regressão:** a suíte determinística completa do CI e `claude plugin validate .`.
- Nenhum teste toca o HOME real.

## Passos de produção
nenhum

## Migração e rollback
**Migração de uma máquina:**
1. Atualizar todas as distribuições ativas:
   - Claude Code: `claude plugin marketplace update fabrica` e depois `claude plugin update fabrica@fabrica`;
   - Antigravity: reinstalar com `agy plugin install`;
   - OpenCode: atualizar o adaptador, conforme `opencode/README.md`;
   - clones usados com `--plugin-dir`: rebase sobre a `main`;
   - Codex: depois da readequação da SPEC-245, gerar o pacote de novo.
2. Abrir uma sessão ou rodar `/fabrica:setup`. O `--check` migra a instalação legada e grava o `CONTENTS.sha256`.
3. Conferir que `setup-githooks.sh --check` responde `ok`.

Enquanto houver uma distribuição legada ativa, ela pode reintroduzir o downgrade e a janela. O script novo detecta isso e volta para a versão maior na execução seguinte. O manual registra esse limite.

**Rollback do código:** reverter o PR. O `VERSION` de uma linha continua legível pelo script antigo, que apaga o `CONTENTS.sha256` na primeira cópia e ignora as entradas internas que sobrarem.

**Rollback dos hooks de uma máquina:** `setup-githooks.sh --allow-downgrade <versão>` a partir da distribuição desejada, com a confirmação do `/fabrica:setup`.

## Riscos e dúvidas
- **Distribuições legadas:** fora do controle deste script. Mitigação: migração documentada e retorno automático à versão maior.
- **Processos que ignoram a trava:** scripts antigos e edição manual. Uma execução nova que encontre o resultado repara, ou responde `falha`, pela regra de segurança.
- **Home em rede (NFS) ou host diferente:** a trava de outro host nunca é quebrada, o que no pior caso deixa a saída em `ocupado` até a remoção manual.
- **`.break` de dono morto:** exige remoção manual. Isso é raro, porque só ocorre se um processo morrer durante a quebra.
- **Timeout do `SessionStart`:** a espera de 5 s mais a publicação ficam abaixo dos 15 s.
- **macOS:** o `ps -o lstart` e o `shasum -a 256` são o caminho alternativo, não testados no CI (Ubuntu).
- **Integração com o B2:** a SPEC-245 reencaixa `codex/githooks-version` na `source_version`. O B1 e esta issue são pré-requisitos da integração final do B2.

## Histórico
- 2026-11-27: criação.
- 2026-11-27: antes da publicação, detalha o ciclo de vida do diário, as combinações de metadados, o `fabrica-hook` ausente, danificado ou sem execução, a distinção entre instalação protegida e integridade não garantida, as corridas da trava, a recuperação manual do `.break` e os limites do modelo de segurança.
