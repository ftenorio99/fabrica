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
Uma atualização dos hooks nunca deixa de ter as entradas de proteção, mesmo quando é interrompida. Uma execução automática nunca volta a uma versão anterior. A pasta só é reescrita quando o conteúdo precisa mudar. O rollback é sempre um gesto explícito do usuário e é confirmado de novo quando é interrompido.

## Comportamento esperado

### Termos
- **Origem:** a pasta `githooks/` da distribuição que roda o script. A versão dela é **S**, lida pela função `source_version` a partir de `.claude-plugin/plugin.json`. A leitura de `codex/githooks-version` entra nessa função na readequação da SPEC-245.
- **Destino:** `${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks`. O caminho e o `core.hooksPath` não mudam. O destino precisa ser uma pasta real (não um symlink); senão, a saída é `falha destino-invalido`, sem escrita.
- **Entradas:** os nomes sem ponto inicial no destino, exceto `VERSION` e `CONTENTS.sha256`.
- **Nomes internos:** os que começam com ponto: `.lock`, `.break`, `.publicando`, `.publicando.<token>` e `.stage.<token>/`. O `rm -f "$dest"/*` do script antigo não os atinge.
- **Conjunto de proteção:** `fabrica-hook`, `pre-commit`, `pre-merge-commit` e `pre-push`.
- **Invólucro:** toda entrada exceto o `fabrica-hook`. O conteúdo é exatamente o modelo atual de três linhas, sem nada a mais:
  - `#!/usr/bin/env bash`
  - `# Entrada do hook <nome>: regra da fábrica e hook do repositório.`
  - `exec "${0%/*}/fabrica-hook" "${0##*/}" "$@"`
- **Arquivo válido:** um arquivo regular (conferido com `lstat`, sem seguir symlink) com modo 0755. Um symlink, uma pasta ou qualquer outro tipo de arquivo nunca é válido, nem como entrada nem como `VERSION` ou `CONTENTS.sha256`.
- **`CONTENTS.sha256`:** a primeira linha é `fabrica-githooks-contents v1 <versão>`; as seguintes são `<sha256>  <nome>`, uma por entrada, em ordem de nome, sem nomes repetidos.
- **Evidência de versão:** uma versão no formato da política de versões, lida de um arquivo válido. Uma versão fora do formato não é evidência.

### Instalação comprovadamente íntegra
O estado `integra` exige **todas** as condições abaixo. É o único estado em que a instalação está comprovadamente protegida.
1. O `VERSION` é um arquivo regular com uma única linha, uma evidência de versão v.
2. O `CONTENTS.sha256` é um arquivo regular no formato acima, com a versão v.
3. O conjunto registrado no `CONTENTS.sha256` contém todo o conjunto de proteção. Todos os nomes seguem `^[a-z0-9-]+$`.
4. As entradas do destino são exatamente os nomes registrados: nenhuma a mais, nenhuma a menos.
5. Cada entrada é um arquivo válido (regular, sem symlink, modo 0755) com o hash registrado.
6. Cada invólucro tem exatamente os bytes do modelo, com o próprio nome. A conferência é feita contra o modelo, além do hash, para que um registro feito sobre um invólucro errado não valha como íntegro.

Qualquer condição que falhe tira a instalação de `integra`. Uma correspondência com o `CONTENTS.sha256` sozinha não basta.

### Diário de publicação
**Conteúdo do `.publicando`** (texto, sem conteúdo de arquivos, caminhos nem dados do ambiente):
- `fabrica-githooks-journal v1`;
- `dono <token da trava>`;
- `modo <atualizacao|reparo|rollback|substituicao>`;
- `de <versão|desconhecida>`, a versão I antes da publicação;
- `para <versão>`, a versão T publicada;
- uma linha `anterior <sha256> <nome>` por entrada presente antes da publicação;
- uma linha `alvo <sha256> <nome>` por entrada da origem.

O `modo` é conferido contra `de` e `para`:

| `modo` | Quando | Relação exigida |
|---|---|---|
| `atualizacao` | publicação automática com T maior | `de` conhecida e T > `de` |
| `reparo` | publicação automática da mesma versão, ou de versão comprovada maior | `de` desconhecida ou T ≥ `de` |
| `rollback` | `--allow-downgrade` | `de` conhecida e T < `de` |
| `substituicao` | `--allow-downgrade` sobre uma versão desconhecida | `de` desconhecida |

Um diário cujo `modo` não respeite a relação é inválido.

**O diário não comprova autorização humana.** Qualquer processo do mesmo usuário pode escrevê-lo, então o `modo rollback` e o `modo substituicao` servem para diagnóstico, não como permissão. A recuperação automática nunca continua um `rollback` ou uma `substituicao`: retomar exige uma nova confirmação, com um novo `--allow-downgrade`.

**Ciclo de vida:**

| Momento | O que acontece |
|---|---|
| Criação | No passo 4 da publicação, dentro da trava: escrito em `.publicando.<token>` e movido com `mv` para `.publicando`. Não existe diário parcialmente escrito com o nome final. |
| Durante a publicação | Não muda. Ele descreve o estado de partida e o de chegada; o progresso é lido nos hashes das entradas. |
| Fim normal | Apagado no passo 10, depois do `VERSION` e da remoção das obsoletas. |
| Falha num `mv` ou sinal capturado | Fica no lugar. A saída é `falha publicacao`. |
| Execução seguinte | Dentro da trava, o diário é **válido** quando: o formato e a relação do `modo` conferem; o `fabrica-hook` existe e é um arquivo válido; cada entrada presente é um arquivo válido com o hash `anterior` ou o `alvo` do próprio nome. Válido, ele leva ao estado `interrompida`; inválido, é apagado, e o estado é lido sem ele. |
| `.publicando.<token>` órfão | É um diário que não chegou a ser publicado. Apagado no passo 2 da publicação seguinte. |
| Script antigo | Não lê nem apaga o diário. Se ele reescrever a pasta, o diário em geral fica inválido e é apagado. Se o diário continuar válido, a regra do máximo (abaixo) impede que ele baixe a versão. |

### Estado da instalação
O script lê o estado sem escrever nada e lê de novo dentro da trava antes de decidir.

| Estado | Condição |
|---|---|
| `ausente` | O `core.hooksPath` global é diferente do destino. |
| `interrompida` | Existe um diário válido. |
| `integra` | Todas as condições de "Instalação comprovadamente íntegra". |
| `legada` | Sem `CONTENTS.sha256` e sem diário, mas com: o `VERSION` sendo uma evidência v; o conjunto de proteção presente, com arquivos válidos; todos os invólucros presentes com os bytes do modelo; nenhuma entrada que não seja arquivo válido. Só o `fabrica-hook` fica sem registro de bytes. |
| `danificada` | Qualquer outro caso. |

**Versão instalada comprovada (I):** o **máximo** das evidências válidas entre o `VERSION`, a versão do `CONTENTS.sha256` e, com diário válido, o `de` e o `para`. Sem nenhuma evidência, I é `desconhecida`. Nunca se presume T ≥ `VERSION` nem o contrário: o máximo é calculado sempre.

### Instalação protegida ou com integridade não garantida
- **Comprovadamente íntegra:** só o estado `integra`.
- **Integridade não garantida:** `legada`, `interrompida` e `danificada`, com o `core.hooksPath` apontado para o destino. A pasta pode estar protegida, mas o script não consegue provar isso:
  - na `legada`, os bytes do `fabrica-hook` não têm registro;
  - na `interrompida`, as regras em vigor são as da versão anterior ou as da alvo;
  - na `danificada`, nada está garantido.
- Cada saída diz em que lado a execução terminou. Uma saída que vem de um estado não garantido e não o corrige leva o qualificador `incerta`.

| Saída | Estado ao terminar | `session-start.sh` |
|---|---|---|
| `ok` | íntegra | silencioso |
| `atualizado <S>` | íntegra | silencioso |
| `mais-novo <I>` | íntegra (`integra` com S < I) | silencioso |
| `mais-novo <I> incerta` | não garantida (`legada` com S < I; nada foi escrito) | informa: não houve downgrade, mas a integridade não está comprovada; rode o setup da versão I ou mais nova |
| `reparado <v>` | íntegra, depois de partir de um estado não garantido | informa a recuperação |
| `divergente <I>` | íntegra, com o conteúdo diferente da origem na mesma versão | aviso |
| `divergente <I> incerta` | não garantida (`legada` na mesma versão, com o `fabrica-hook` diferente) | aviso |
| `ausente` | — | aviso, como hoje |
| `ocupado integra` | íntegra pela leitura sem escrita; outro processo tem a trava | silencioso |
| `ocupado incerta` | não garantida, ou trava em estado que o script não decide sozinho | informa |
| `falha <código>` | não garantida | aviso |
| `revertido <S>` | íntegra em S < versão anterior (só na instalação explícita) | — |

Os códigos de `falha` são:

| Código | Quando |
|---|---|
| `origem-invalida` | versão da origem fora do formato |
| `destino-invalido` | o destino não é uma pasta real |
| `preparacao` | falha na preparação do stage |
| `publicacao` | um `mv` falhou ou um sinal interrompeu a publicação |
| `interrompida` | publicação automática interrompida que esta origem não pode concluir |
| `rollback-interrompido` | `rollback` ou `substituicao` interrompidos; exige nova confirmação |
| `danificada` | instalação danificada com I > S |
| `versao-desconhecida` | instalação danificada sem nenhuma evidência de versão |
| `trava` | o script perdeu a própria trava ou não conseguiu liberá-la |

O `--check` imprime uma única linha no stdout e sai com 0, exceto em `falha` (1) e em uso inválido (2). O detalhe vai para o stderr, sem conteúdo de arquivos. As mensagens do `session-start.sh` são fixas por saída e só interpolam versões. O formato é texto puro no Claude Code e `{"injectSteps":[…]}` no Antigravity. Uma saída diferente de 0 ou uma linha não reconhecida gera aviso.

### Combinações de `VERSION`, `CONTENTS.sha256` e diário
A leitura é feita dentro da trava. `de` e `para` (T) vêm do diário; v e w são evidências válidas. Em todas as linhas, I é o máximo das evidências válidas da linha.

| `VERSION` | `CONTENTS.sha256` | Diário | Interpretação | I |
|---|---|---|---|---|
| v | v, conferido | ausente | `integra` | v |
| v | ausente | ausente | `legada` se cumpre a definição; senão, `danificada` | v |
| v | v, não conferido | ausente | `danificada` | v |
| v | w ≠ v | ausente | `danificada` | max(v, w) |
| ausente ou inválido | w | ausente | `danificada` | w |
| ausente ou inválido | ausente ou inválido | ausente | `danificada` | desconhecida |
| qualquer | qualquer | válido, todas as entradas com o hash `anterior` | publicação que não trocou nada: o diário é apagado e a leitura recomeça sem ele | conforme a nova leitura |
| qualquer | qualquer | válido, alguma entrada com o hash `alvo` | `interrompida` | max(`VERSION`, `CONTENTS.sha256`, `de`, T) |
| qualquer | qualquer | inválido | diário apagado; leitura pelas linhas sem diário | conforme a linha |

O máximo só não precisa ser calculado quando está demonstrado. Na publicação automática, o `modo atualizacao` exige T > `de`, e o `VERSION` fica igual a `de` até o passo 8 e igual a T depois dele; nesse caso, I = T. No `rollback`, T < `de`, então I = `de`. Fora desses casos, quando um processo alheio mudou o `VERSION`, vale o máximo geral.

### Decisão das execuções automáticas
Vale para o `--check` e para a instalação sem `--allow-downgrade`. As linhas são avaliadas na ordem.

| Estado | Condição | Ação | Saída |
|---|---|---|---|
| ausente | — | nenhuma no `--check`; a instalação segue as regras de hoje e publica (`modo reparo` ou `atualizacao`) | `ausente` |
| integra | entradas iguais às da origem | nada | `ok` |
| integra | S > I | publica S (`atualizacao`) | `atualizado S` |
| integra | S < I | nada | `mais-novo I` |
| integra | S = I com conteúdo diferente | nada | `divergente I` |
| legada | S > I | publica S (`atualizacao`) | `atualizado S` |
| legada | S = I com todas as entradas iguais às da origem | grava só o `CONTENTS.sha256` (com o `rename`), sem tocar nos hooks; depois relê e confere `integra` | `ok` |
| legada | S = I com conteúdo diferente | nada | `divergente I incerta` |
| legada | S < I | nada | `mais-novo I incerta` |
| interrompida | `modo rollback` ou `substituicao` | nada nos hooks | `falha rollback-interrompido` |
| interrompida | `modo atualizacao` ou `reparo` e S ≥ I | publica S (`reparo`) | `reparado S` |
| interrompida | `modo atualizacao` ou `reparo`, S < I, e todos os arquivos que faltam trocar têm, na origem, bytes iguais aos `alvo` | troca esses arquivos e conclui com os metadados de T | `reparado T` |
| interrompida | `modo atualizacao` ou `reparo`, S < I nos outros casos | nada nos hooks | `falha interrompida` |
| danificada | I conhecido e S ≥ I | publica S (`reparo`) | `reparado S` |
| danificada | I conhecido e S < I | só a recuperação mínima | `falha danificada` |
| danificada | I desconhecido e um `fabrica-hook` válido com os mesmos bytes da origem | publica S (`reparo`) | `reparado S` |
| danificada | I desconhecido nos outros casos | só a recuperação mínima | `falha versao-desconhecida` |

**Recuperação mínima:** cria os invólucros **ausentes** com os bytes do modelo, se o `fabrica-hook` presente for um arquivo válido, e devolve o modo 0755 a um arquivo regular cujos bytes conferem com o registro (`CONTENTS.sha256` ou modelo). Não sobrescreve nada e não grava `VERSION`, `CONTENTS.sha256` nem diário.

**Regra de segurança da recuperação:** uma execução automática só troca o conteúdo de um arquivo existente em dois casos: quando S ≥ I com I conhecido (inclusive no `reparo`), ou quando os bytes novos são iguais aos `alvo` de um diário válido de `modo atualizacao` ou `reparo`. O `fabrica-hook` nunca é criado nem trocado sem provar S ≥ I. Uma publicação interrompida nunca vira, sozinha, autorização para baixar a versão.

### `fabrica-hook` ausente, danificado ou não executável
| Situação | Efeito no git | Estado | Recuperação automática |
|---|---|---|---|
| Ausente | Os invólucros presentes falham no `exec` e o git recusa a operação (falha fechada). Sem invólucro, a operação passa sem hook. | `danificada` (um diário existente fica inválido) | Com I conhecido e S ≥ I, publica S. Senão, nada é criado, porque criar o `fabrica-hook` a partir de uma origem menor ou de versão não comprovada pode ser um downgrade. |
| Presente, com bytes diferentes do registrado | Comportamento desconhecido; pode deixar passar | `danificada` | Com I conhecido e S ≥ I, publica S. Com I desconhecido e bytes iguais aos da origem, publica S. Nos outros casos, não toca nele e responde `falha`. |
| Arquivo regular com os bytes registrados, mas sem modo 0755 | Os invólucros falham no `exec` (falha fechada) | `danificada` | A recuperação mínima devolve o modo, em qualquer versão de origem. A saída é `reparado I` se a instalação ficar `integra`; senão, a decisão segue com o estado relido. |
| Symlink, pasta ou outro tipo | Indefinido | `danificada` | Tratado como "bytes diferentes": nunca é seguido nem substituído sem S ≥ I. |

A mesma tabela vale para um invólucro alterado ou sem execução, com uma diferença: um invólucro **ausente** sempre pode ser criado, porque o modelo dele é fixo e ele só repassa para o `fabrica-hook`.

### Rollback e garantias de proteção
- **Rollback:** `setup-githooks.sh --allow-downgrade <S>` roda só na instalação, com `<S>` igual à versão da origem, como confirmação.
  - Grava o diário com `modo rollback`, ou `substituicao` quando I é desconhecida.
  - Publica S pelo mesmo algoritmo e responde `revertido S`.
  - O `--check` recusa a opção com saída 2.
  - O `/fabrica:setup` só roda a opção depois de confirmar com o usuário pelo AskUserQuestion. A pergunta diz que a versão S pode ter menos proteções que a instalada.
- **Rollback interrompido:** a execução seguinte, automática ou não, responde `falha rollback-interrompido` e não mexe nos hooks.
  - Para continuar, o usuário confirma de novo e roda `--allow-downgrade <S>` a partir da distribuição desejada. Esse novo rollback parte do estado misto, com um diário novo.
  - Ou o usuário roda o setup de uma versão ≥ `de`, que publica pelo caminho normal.
  - Enquanto isso, a proteção é a da versão anterior ou a da alvo, pela prova dos estados mistos.
- **Duração do rollback:** ele vale enquanto nenhuma distribuição de versão maior rodar. A primeira que rodar sobe a versão de novo, pela regra automática. Para manter o rollback, o usuário precisa atualizar ou desativar as distribuições mais novas. O manual registra isso.
- **O que a publicação garante:** em qualquer publicação, inclusive no rollback, nenhuma entrada que existia antes some, e o conjunto de proteção fica presente e executável a cada instante.
- **O que a versão alvo garante:** depois da publicação, as regras em vigor são as do `fabrica-hook` da versão alvo, e só elas. Uma versão anterior pode não ter regras que só vieram depois. O rollback pode, então, **reduzir intencionalmente** a proteção, e é por isso que exige confirmação humana e é registrado (`revertido S`).

### Publicação
A publicação roda dentro da trava, com uma rotina para `TERM`, `INT` e `HUP`.
1. Instala a rotina dos sinais:
   - antes do diário: apaga o próprio stage, libera a trava e sai com `falha publicacao`;
   - depois do diário: para no ponto seguro seguinte (os `mv` são atômicos), mantém o diário, libera a trava e sai com `falha publicacao`.
2. Apaga os `.stage.*` e `.publicando.*` órfãos. Só o dono da trava cria stage, então os que existem pertencem a donos anteriores.
3. **Prepara** a origem em `.stage.<token>/`, dentro do próprio destino, o que garante o mesmo sistema de arquivos para o `rename`.
   - Copia, aplica modo 0755 e calcula os hashes.
   - Confere: nomes no formato; conjunto de proteção completo; cada invólucro igual ao modelo; nenhum symlink nem arquivo de outro tipo; hashes da cópia iguais aos da origem lidos antes da cópia.
   - Grava `CONTENTS.sha256` e `VERSION` no stage.
   - Qualquer falha apaga o stage e sai com `falha preparacao`, sem tocar no destino.
4. Confere que ainda é dono da trava e grava o diário em `.publicando.<token>`; depois faz `mv` para `.publicando`.
5. `mv` do `fabrica-hook`.
6. `mv` de cada invólucro, em ordem de nome.
7. Confere de novo a posse da trava e faz `mv` do `CONTENTS.sha256`.
8. `mv` do `VERSION`.
9. Remove as entradas que não estão no alvo. O alvo sempre contém o conjunto de proteção, então nenhuma entrada de proteção é removida.
10. Apaga o diário e o stage, e libera a trava.

Uma falha num `mv` para nesse ponto, mantém o diário, libera a trava e sai com `falha publicacao`.

**Por que os estados mistos são seguros:**
- Nenhum nome é removido antes do passo 9, e o `rename` troca o arquivo no lugar. Assim, toda entrada que existia antes continua existindo e executável em qualquer instante.
- O `fabrica-hook` vai antes dos invólucros e nunca é removido. Todo invólucro presente chama um `fabrica-hook` presente, completo, de uma das duas versões, porque o stage está no mesmo sistema de arquivos e o `rename(2)` é atômico.
- Todos os invólucros têm os mesmos bytes, pelo modelo. Um invólucro novo e um antigo do mesmo nome são, portanto, idênticos. Um nome novo que ainda não chegou só deixa de rodar, como na versão anterior.
- Até o passo 5, as regras em vigor são as da versão anterior; a partir dele, as da alvo.

| Ponto da interrupção | Estado observado | Regras em vigor | Próxima execução |
|---|---|---|---|
| esperando a trava | nada mudou | anterior | decide normalmente |
| com a trava, antes do diário (passos 1–3) | destino intacto, stage órfão, `.lock` do processo | anterior | quebra a trava se o dono morreu (`KILL`) ou a encontra liberada (`TERM`); apaga o stage; decide normalmente |
| diário gravado, nada trocado | diário válido, todas as entradas com o hash `anterior` | anterior | apaga o diário e decide de novo |
| depois do `fabrica-hook` ou durante os invólucros | `interrompida`, invólucros mistos e idênticos | alvo | pela tabela de decisão, conforme o `modo` |
| antes do `CONTENTS.sha256` ou do `VERSION` | entradas todas com o hash `alvo`, metadados antigos | alvo | idem; no `modo atualizacao` ou `reparo`, conclui só com os metadados, sem trocar hooks |
| antes de remover as obsoletas, o diário ou a trava | alvo completo; obsoletas, diário ou `.lock` presentes | alvo | idem; conclui a remoção |

### Tempo do `SessionStart`
O `SessionStart` tem timeout de 15 s. Nada garante que preparação, publicação e limpeza caibam nesse tempo, por exemplo num disco lento ou numa pasta em rede. O comportamento não depende disso:
- **Espera pela trava:** no máximo 5 s no `--check` e 30 s na instalação. Esgotado o prazo, o `--check` responde `ocupado integra` ou `ocupado incerta`, pela leitura sem escrita.
- **Prazo do `--check`:** depois da espera, o `--check` só começa uma publicação se tiver passado menos de 8 s desde o início da execução. Senão, responde pela leitura sem escrita, e a próxima execução publica.
- **Interrupção no meio:** o encerramento pelo timeout (`TERM` ou `KILL`, conforme o runtime; não verificado) para o script em algum ponto da tabela acima.
  - Com `TERM`, a rotina dos sinais libera a trava.
  - Com `KILL`, a trava fica com um dono morto e é quebrada na execução seguinte.
  - Nos dois casos, o diário e os nomes internos levam à recuperação descrita, e o conjunto de proteção nunca fica incompleto.

### Trava
- **Nome:** o symlink `.lock` no destino.
- **Identidade:** `fabrica-githooks-lock v1 host=<h> pid=<p> start=<s> token=<t>`.
  - `<h>` é o `uname -n`, sem espaço, `/` nem controle.
  - `<p>` é um número.
  - `<s>` é o campo 22 de `/proc/<pid>/stat` ou, sem `/proc`, a saída de `LC_ALL=C ps -o lstart= -p <pid>`, com os espaços trocados por `_`.
  - `<t>` tem 16 caracteres hexadecimais aleatórios.

  Qualquer identidade que não siga exatamente esse formato é **malformada**.
- **Aquisição:**
  1. Se o nome `.lock` existe, em qualquer forma (conferido com `lstat`), não tenta criar.
  2. Senão, roda `ln -sn <identidade> .lock`. O `-n` impede que um symlink já existente para uma pasta seja seguido. Conferido no Linux: sem o `-n`, o `ln -s` sobre um symlink para pasta "tem sucesso" e cria o link dentro da pasta.
  3. Depois do `ln`, só considera a trava adquirida se o `.lock` for um symlink e o `readlink` devolver exatamente a própria identidade.
  4. Se o `ln` saiu com 0 mas a conferência falhou (o `.lock` virou uma pasta entre o passo 1 e o 2), remove o link que acabou de criar dentro dela, só se ele for um symlink com a própria identidade, e considera a trava **ambígua**.
- **Classificação de um `.lock` existente:**

  | Situação | Classificação |
  |---|---|
  | Não é symlink (pasta, arquivo, outro tipo) | ambígua |
  | Identidade malformada | ambígua |
  | Host diferente do atual | viva |
  | Mesmo host, `kill -0` com sucesso ou recusado por permissão, e marca de início igual | viva |
  | Mesmo host, processo existe, marca de início **obtida** e diferente | morta (PID reutilizado) |
  | Mesmo host, `kill -0` com "No such process" (lido com `LC_ALL=C`) | morta |
  | Marca de início indisponível, resultado do `kill -0` não reconhecido ou qualquer outro caso | viva |

  **Só uma trava classificada como morta pode ser quebrada.** Uma trava viva ou ambígua nunca é adquirida nem quebrada automaticamente, e nenhuma trava é removida por idade. Com uma trava viva, o script espera; com uma ambígua, responde `ocupado incerta` na hora, e o stderr remete ao procedimento manual.
- **Quebra de uma trava morta:**
  1. cria o `.break` pelo mesmo protocolo de aquisição (`lstat`, `ln -sn`, conferência);
  2. relê o `.lock` e confere que continua um symlink com exatamente a mesma identidade julgada morta;
  3. remove o `.lock`;
  4. remove o próprio `.break`, depois de conferir a identidade;
  5. tenta de novo a aquisição normal.

  Se o `.break` já existe, em qualquer forma, a quebra não acontece e o script espera. Um `.break` nunca é removido automaticamente, nem de dono morto: depois da espera, a saída é `ocupado incerta`.
- **Liberação:** remove o `.lock` só se ele for um symlink com a própria identidade. Com outra identidade ou outra forma, não remove nada e sai com `falha trava`.
- **Corridas entre conferir e remover:**
  - *Na quebra:* enquanto o `.lock` existe, nenhum outro processo consegue criar outro, e enquanto o `.break` existe, nenhum outro quebra. Entre o passo 2 e o 3, então, só o dono do `.break` mexe no `.lock`, e o dono morto não volta.
  - *Recuperação concorrente:* dois processos que julgam a mesma trava morta disputam o `.break`. Só um o cria; o outro espera e, quando adquire, encontra a trava já trocada.
  - *Na liberação:* entre ler a própria identidade e remover, outro processo só trocaria a trava se a quebrasse, e isso exige julgar morto um dono vivo. No mesmo host, com a mesma marca de início, isso não acontece.
  - *Conferência a cada fase:* a posse é conferida antes do diário (passo 4) e antes dos metadados (passo 7). Se o script perdeu a trava, ele para e sai com `falha trava`; o diário permite à execução seguinte concluir ou recusar.
  - *Resíduo:* dois ambientes que compartilham o destino e o mesmo nome de host, com espaços de PID diferentes (contêineres com a home montada), podem julgar morto um dono vivo. Isso fica nos limites do modelo.

### Recuperação manual de uma trava ambígua ou de um `.break`
O `protect-main.sh` recusa comandos do agente que citam a pasta dos hooks, então este procedimento é **do usuário**, no terminal:
1. Confirme que nenhum setup está rodando: `pgrep -af setup-githooks.sh` não deve listar nada.
2. Inspecione: `ls -la ~/.config/fabrica/githooks/` (ou o caminho com `XDG_CONFIG_HOME`) e `readlink` do `.lock` e do `.break`. Confira o host e que o PID não existe (`kill -0 <pid>` falha) ou é de outro processo.
3. Remova o que estiver abandonado: `rm ~/.config/fabrica/githooks/.break`; para o `.lock`, `rm` se for um symlink, ou `rm -r` se for uma pasta criada por engano.
4. Rode `bash <clone>/scripts/setup-githooks.sh --check`.

O `docs/solucao-de-problemas.md` traz esses passos.

### Diagnósticos no `/fabrica:setup`
O passo 4 mostra cada saída ao usuário e só pergunta pela instalação em `ausente`.
- Em `falha danificada`, `falha versao-desconhecida`, `falha rollback-interrompido`, `divergente` e `mais-novo … incerta`, explica as opções: rodar o setup de uma versão maior ou igual, ou rodar `--allow-downgrade <S>`.
- Só roda o `--allow-downgrade <S>` com a confirmação do usuário, que inclui o aviso de que a versão S pode ter menos proteções.
- Em `ocupado incerta`, mostra o procedimento manual.

### Distribuições legadas
Uma distribuição com o script anterior não respeita a trava, o diário nem a monotonicidade. Exemplos: o cache de um plugin antigo, uma cópia do `agy`, um pacote Codex anterior a esta issue, um clone numa branch antiga. Ela:
- recopia sempre que o `VERSION` difere da versão dela;
- apaga o `CONTENTS.sha256`;
- abre a janela do `rm`/`cp`.

O script novo não impede isso. Ele lê o resultado como `legada` ou `danificada`, volta para a versão maior quando a origem permite e avisa quando não consegue. A proteção completa só vale depois que todas as distribuições ativas da máquina forem atualizadas.

### Limites do modelo de segurança
O modelo cobre falhas acidentais e operacionais: interrupção, disco cheio, execuções simultâneas e distribuições de versões diferentes. Não cobre sabotagem nem processos que ignoram o protocolo, como já faz a ADR 0002.

| Limite | O que continua possível | O que a spec garante |
|---|---|---|
| Distribuições legadas | Downgrade, apagar o `CONTENTS.sha256`, abrir a janela do `rm`/`cp`, ignorar a trava | A execução nova seguinte detecta, volta para a maior versão comprovada quando pode e avisa quando não pode |
| Processos que ignoram a trava (edição manual, outras ferramentas) | Qualquer mudança na pasta, inclusive no meio de uma publicação | O resultado é lido como `danificada` ou como diário inválido e segue a regra de segurança da recuperação |
| `root` ou processos do mesmo UID com intenção hostil | Tudo, inclusive forjar o diário | Nada; fora do modelo. Mesmo assim, um diário forjado de `rollback` não é continuado sem confirmação. |
| Home em rede (NFS) ou compartilhada | O `rename` e o `symlink` dependem do servidor; o dono não é verificável de outro host | A trava de outro host nunca é quebrada (no pior caso, `ocupado` até a remoção manual). A atomicidade só vale se o servidor a garantir. |
| Contêineres com o mesmo nome de host e outro espaço de PIDs | Um dono vivo pode parecer morto | Nenhuma; resíduo documentado |
| macOS | Sem `/proc`, a marca de início vem do `ps -o lstart` (resolução de segundo), e o hash, do `shasum -a 256`. O CI (Ubuntu) não testa esse caminho. | Sem marca, o dono conta como vivo (nunca quebra). Sem ferramenta de hash, `falha preparacao` sem escrita. O `ln -sn` existe no BSD, mas não foi verificado. |
| Sistema de arquivos sem `rename` atômico | Um arquivo parcial | O stage dentro do destino usa o mesmo sistema de arquivos; fora disso, nada |
| Timeout ou `KILL` em qualquer ponto | Trava de dono morto, diário pendente | Recuperação pela execução seguinte, sem perder entradas |
| Repositórios com `core.hooksPath` local; `--no-verify` pelo humano | Passam sem os hooks da fábrica | Inalterado (ADR 0002) |

## Telas
nenhuma (Interface: não)

## Critérios de aceite
Todos os testes rodam com HOME, `XDG_CONFIG_HOME`, `GIT_CONFIG_GLOBAL` e `GIT_CONFIG_NOSYSTEM` temporários, com duas ou mais cópias da distribuição em versões diferentes. As versões de teste têm um `fabrica-hook` marcado por versão. Uma delas é a "versão reduzida", sem a regra do `pre-merge-commit`.

| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com a instalação `integra` e as entradas iguais às da origem, o `--check` responde `ok` sem escrever nada (inode, modo e mtime de todas as entradas e dos metadados inalterados), mesmo com a versão de plugin da origem diferente da instalada. | unitário |
| CA2 | Com a instalação `integra`, S < I e conteúdo diferente, responde `mais-novo I` e não muda nenhum arquivo. | unitário |
| CA3 | Com S > I, responde `atualizado S`. Antes de cada `rename`, o conjunto de proteção está presente, com arquivos válidos, e o resultado final cumpre as 6 condições de `integra` em S. | unitário com um `mv` falso no PATH que registra o estado antes de chamar o real |
| CA4 | Uma falha na preparação deixa o destino byte a byte igual, sai com 1 e responde com o código correspondente. Casos: arquivo ilegível na origem, invólucro fora do modelo, entrada de proteção ausente na origem, symlink na origem, ferramenta de hash ausente, versão da origem inválida (`origem-invalida`) e destino que é um symlink (`destino-invalido`). | unitário com hashes antes e depois |
| CA5 | Uma instalação `danificada` com I conhecido e S ≥ I responde `reparado S` e termina cumprindo as 6 condições de `integra`. Casos: entrada editada, entrada ausente, `VERSION` ausente, `CONTENTS.sha256` ausente, `CONTENTS.sha256` sem uma entrada do conjunto de proteção, invólucro registrado com bytes fora do modelo, entrada trocada por symlink e entrada extra não registrada. Um arquivo regular com os bytes registrados mas sem modo 0755 recebe o modo de volta, sem troca de conteúdo, em qualquer versão de origem, com `reparado I`. | unitário |
| CA6 | Com a instalação `integra`, S = I e conteúdo diferente, responde `divergente I` e não escreve nada. | unitário |
| CA7 | Vinte pares de `--check` simultâneos de duas versões terminam com a instalação `integra` na versão maior, e nenhuma execução sai com `atualizado` para a menor depois que a maior foi publicada. | unitário com laço concorrente |
| CA8 | Uma instalação `legada` (só `VERSION`, gerada pelo script da `main`) segue a tabela de decisão: S > V responde `atualizado S`; S = V com bytes iguais grava só o `CONTENTS.sha256` (inode das entradas inalterado), responde `ok`, e a execução seguinte responde `ok` sem escrever; S = V com `fabrica-hook` diferente responde `divergente V incerta` sem escrever; S < V responde `mais-novo V incerta` sem escrever. Uma pasta legada com um invólucro fora do modelo ou uma entrada de proteção ausente é `danificada`, não `legada`. | unitário |
| CA9 | Na instalação, `--allow-downgrade <S>` publica S < I pelo mesmo algoritmo, com o diário em `modo rollback` (ou `substituicao` com I desconhecida), e responde `revertido S`. Com `<S>` diferente da versão da origem, ou no `--check`, sai com 2 sem escrever nada. Depois de um rollback concluído, uma execução automática de versão maior volta a subir (`atualizado`). | unitário |
| CA10 | Em toda publicação, inclusive no rollback e em cada interrupção do CA13, o conjunto de proteção fica presente e executável. Depois de cada publicação concluída, o comportamento é o do `fabrica-hook` da versão alvo. Com uma versão alvo que tem as regras atuais, commit na `main`, `merge --no-ff` na `main` e push para a `main` de um remoto local são recusados, e o hook do repositório continua encadeado. Com o rollback para a versão reduzida, o `merge --no-ff` passa, mostrando que o rollback pode reduzir a proteção e que essa redução só ocorre pelo `--allow-downgrade`. | unitário |
| CA11 | O `session-start.sh` segue a tabela de saídas, uma por uma, em texto (Claude) e em `{"injectSteps":…}` (Antigravity). Fica silencioso em `ok`, `atualizado`, `mais-novo` sem qualificador e `ocupado integra`. Informa em `reparado`, `mais-novo … incerta` e `ocupado incerta`. Avisa em `divergente` (com e sem qualificador), `ausente`, cada código de `falha`, saída diferente de 0 e linha não reconhecida. | unitário com um `setup-githooks.sh` falso por saída |
| CA12 | Uma instalação `danificada` com I > S não sofre downgrade: o `fabrica-hook` e todo arquivo existente ficam byte a byte iguais, só a recuperação mínima é aplicada, e a saída é `falha danificada`. Isso vale com I vindo do `VERSION`, só do `CONTENTS.sha256` ou do máximo entre os dois quando divergem. Com I desconhecido e um `fabrica-hook` diferente do da origem, a saída é `falha versao-desconhecida`, com a mesma restrição. Um `fabrica-hook` ausente só é criado com S ≥ I e I conhecido. | unitário |
| CA13 | Uma interrupção em cada ponto da publicação deixa o conjunto de proteção presente e executável. O `fabrica-hook` fica com os bytes da versão anterior ou da alvo, e nenhuma entrada que existia antes some. Os pontos são: depois do k-ésimo `rename`, para cada k (com o `mv` falso que mata o script na chamada k), e por `TERM` e por `KILL` durante a espera pela trava, a preparação, a publicação e a limpeza. | unitário com o `mv` falso, que pode atrasar cada chamada, e `timeout -s TERM` e `-s KILL` |
| CA14 | Para cada ponto do CA13, a execução seguinte encontra o estado esperado na tabela de interrupção e decide pela tabela de decisão. `modo atualizacao` ou `reparo` com S ≥ I: `reparado S` e `integra`. S < I: conclui só com bytes iguais aos `alvo` (`reparado T`) ou responde `falha interrompida` sem tocar nos hooks. Diário gravado sem nada trocado: o diário é apagado e a decisão é refeita. Com `modo rollback` ou `substituicao`, a execução automática responde `falha rollback-interrompido` sem tocar nos hooks, e só um novo `--allow-downgrade <S>` conclui. Em nenhum caso o `VERSION` termina abaixo de I sem `--allow-downgrade`, e I é sempre o máximo das evidências. | unitário |
| CA15 | Um `.lock` de processo vivo (PID e marca de início iguais) não é removido, mesmo com o mtime recuado em uma hora: o `--check` espera até 5 s e responde `ocupado integra` ou `ocupado incerta`, com o `.lock` intacto. Um `.lock` de processo encerrado (inclusive morto por `KILL` no CA13), ou de PID reutilizado com outra marca obtida, é quebrado e adquirido. Um `.lock` de outro host não é quebrado. Com a marca de início indisponível (sem `/proc` e com um `ps` falso que falha), o dono conta como vivo. O `--check` não começa uma publicação depois de 8 s de execução. | unitário com um `sleep` como dono vivo, o PID de um processo encerrado e `/proc` e `ps` simulados |
| CA16 | Situações que nunca resultam em aquisição ou quebra automática: `.lock` com identidade malformada; `.lock` que é uma pasta, um arquivo ou um symlink para pasta (o `ln -sn` não cria nada dentro dela e o `.lock` fica intacto); resultado do `kill -0` não reconhecido; e qualquer `.break` existente, mesmo de dono morto. Todas respondem `ocupado incerta`. Um dono cuja trava foi trocada não remove o `.lock` novo ao liberar e sai com `falha trava`. Um dono que perde a trava antes do diário ou dos metadados para e sai com `falha trava`. Duas quebras simultâneas da mesma trava morta resultam em uma única aquisição. | unitário |
| CA17 | A emenda à ADR 0002, `docs/solucao-de-problemas.md` e `docs/comandos.md` descrevem as saídas, o rollback com `--allow-downgrade` (inclusive a nova confirmação depois de uma interrupção, a possível redução de proteção e a duração dele), o procedimento de migração por runtime, a recuperação manual de uma trava ambígua ou de um `.break` e os limites do modelo, sem prometer proteção contra distribuições legadas. | manual, na revisão |

## Fora de escopo
- Ler `codex/githooks-version` e validar a paridade entre `codex/plugin.json` e `.claude-plugin/plugin.json`: entram na readequação da SPEC-245, sobre a função `source_version`.
- Proteções do agente no Codex (C1); a conferência dos arquivos pelo `protect-main.sh` (hoje ele só confere o `core.hooksPath`); repositórios com `core.hooksPath` local; o runner do dispatcher (ADR 0021).
- Impedir que distribuições legadas façam downgrade.
- Posse de issues e recuperação de execução (D1/D2).
- Mudar o contrato ou os bytes dos invólucros. Uma mudança futura precisa de um novo desenho de publicação, porque a prova dos estados mistos depende deles.
- Comprovar autorização humana por meio de arquivos: a confirmação continua sendo o gesto do usuário no `/fabrica:setup` ou no terminal.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/setup-githooks.sh`, reescrito em funções:
  - `source_version`;
  - `semver_valid` e `semver_cmp`;
  - `hash_file` (`sha256sum` ou, na falta dele, `shasum -a 256`);
  - `valid_file` (`lstat`, regular, 0755);
  - `wrapper_ok`;
  - `read_state` e `proven_version`;
  - `lock_acquire`, `lock_classify`, `lock_break` e `lock_release`;
  - `stage`, `publish`, `recover`, `minimal_recovery` e `decide`;
  - a rotina dos sinais.

  As opções passam a ser `[--check] [--force] [--allow-downgrade <versão>]`. O texto de instalação de hoje continua.
- `hooks/session-start.sh`: troca o `== ausente` pela tabela de saídas, com mensagens fixas e as duas formas de saída de hoje.
- `skills/setup/SKILL.md`: o passo 4 segue "Diagnósticos no `/fabrica:setup`".
- `scripts/test-setup-githooks.sh` (novo): CA1–CA9 e CA12–CA16, mais os falsos de `mv` e de `ps`. O CI já pega `scripts/test-*.sh` sem mudança no workflow.
- `scripts/test-protect-main.sh`: o CA5 do SPEC-27 é ajustado às saídas novas, e o CA10 é acrescentado.
- `scripts/test-session-start.sh`: o CA11.
- `AGENTS.md`: cita a suíte nova na lista de testes.
- `docs/adr/0002-protecao-da-main-por-hooks-do-git.md` (emenda), `docs/solucao-de-problemas.md` e `docs/comandos.md`.
- `.claude-plugin/plugin.json`: a versão sobe no PR. O número é definido na preparação da integração.

**Dados:** `CONTENTS.sha256`, `.publicando`, `.lock` e `.break` no destino, nos formatos de "Termos", "Diário de publicação" e "Trava". O `VERSION` continua com uma linha.

**Interfaces:**
- `setup-githooks.sh --check`: uma linha no stdout, conforme a tabela de saídas.
- `setup-githooks.sh [--force]`: instalação como hoje, com as mesmas regras de decisão.
- `setup-githooks.sh --allow-downgrade <versão>`: instalação explícita, com rollback ou substituição.

**Política de comparação de versões:**
- Formato `^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$`: sem prefixo, sem zeros à esquerda e no máximo 9 dígitos por campo, para caber na aritmética do bash.
- Comparação numérica campo a campo.
- Uma versão da origem fora do formato é `falha origem-invalida`, sem escrita.
- Uma versão instalada fora do formato não é evidência; nunca vale como zero.
- I é sempre o máximo das evidências válidas.
- Não há versão própria dos hooks: a versão do plugin dá a ordem, e o `CONTENTS.sha256` dá a identidade.

**Decisões:**
- Publicar por stage e `rename` arquivo a arquivo, dentro do próprio destino, mantendo o caminho e o `core.hooksPath`, porque o `protect-main.sh:67` e o `session-start.sh` conferem esse caminho, e o stage dentro do destino garante o mesmo sistema de arquivos (recomendação da triagem). Alternativa descartada: diretórios versionados com symlink, porque a troca de pasta para symlink numa instalação existente não é atômica.
- Trava por symlink criado com `ln -sn`, depois de um `lstat` e com uma conferência por `readlink`, e a identidade no próprio alvo (recomendação da triagem). Alternativas descartadas: `mkdir` com arquivo de dono, que deixa uma trava sem dono entre as duas operações; e `flock`, que não existe no macOS.
- Sem versão própria dos hooks (recomendação da triagem). Alternativa descartada: uma terceira versão, que seria mais uma fonte para manter em paridade.
- O `fabrica-hook` primeiro, depois os invólucros, depois os metadados, porque assim as regras novas valem a partir do primeiro `rename` e a falta dos metadados marca a publicação incompleta. Alternativa descartada: metadados primeiro, que declararia uma versão ainda não instalada.
- Um rollback interrompido exige nova confirmação, porque o diário não comprova autorização humana. Alternativa descartada: registrar a autorização no diário e retomar sozinho, o que transformaria um arquivo editável em permissão de downgrade.
- O `--check` não começa uma publicação depois de 8 s, porque o timeout do `SessionStart` é de 15 s e a próxima sessão publica. Alternativa descartada: depender só da recuperação, o que tornaria a interrupção pelo timeout o caso comum num disco lento.
- Uma suíte nova `test-setup-githooks.sh`, porque o `test-protect-main.sh` já tem 162 casos de outro assunto (PreToolUse). Alternativa descartada: estender só o CA5 dele.
- Injeção de falha por `mv` e `ps` falsos no PATH, como os falsos de `gh` e `claude` das suítes atuais. Alternativa descartada: uma variável de ambiente de teste no script de produção.

**Fontes da documentação:**
- git 2.53 (`man githooks`): o `core.hooksPath` substitui o `.git/hooks`, e uma entrada ausente faz o hook não rodar. Confirmado na fixture.
- `rename(2)` e `symlink(2)`: atômicos no mesmo sistema de arquivos; o `symlink` falha com `EEXIST`. Conhecimento do modelo.
- `ln` (uutils coreutils 0.10.0, nesta máquina):
  - `ln -s` sobre um symlink para pasta cria o link dentro da pasta e sai com 0;
  - `ln -sn` recusa ("Already exists");
  - `ln -sn` sobre uma pasta real cria dentro dela e sai com 0, daí o `lstat` antes e a conferência depois.

  No BSD/macOS, o `-n` existe, mas não foi verificado.
- `kill -0` com `LC_ALL=C`: "No such process" para um PID inexistente (bash 5.3, conferido).
- `/proc/<pid>/stat`, campo 22 (`starttime`): `man 5 proc`, conhecimento do modelo, não verificado nesta etapa. `ps -o lstart=`: conferido no Linux.
- Sinal enviado pelo timeout do hook `SessionStart` (`TERM` ou `KILL`): não verificado; o desenho cobre os dois.
- gh 2.105.0: o desenho não cita nenhum comando do `gh`.

**ADR:** emenda à [ADR 0002](../docs/adr/0002-protecao-da-main-por-hooks-do-git.md), nas consequências. Não há ADR nova.

## Testes
- `bash scripts/test-setup-githooks.sh`:
  - fixtures geradas a partir de cópias do plugin com `.claude-plugin/plugin.json` em versões diferentes, um `fabrica-hook` marcado por versão e a versão reduzida;
  - o `mv` falso no PATH registra o estado antes de cada `rename`, pode atrasar cada chamada e mata o script na k-ésima (CA3, CA13, CA14);
  - `timeout -s TERM` e `-s KILL` em cada fase (CA13 a CA15);
  - um `sleep` em segundo plano serve de dono vivo, o PID de um processo encerrado de dono morto, uma marca trocada simula PID reutilizado, e `ps` falso e `/proc` indisponível simulam a marca ausente (CA15, CA16);
  - `.lock` e `.break` montados à mão: malformados, pasta, arquivo, symlink para pasta (CA16);
  - laços concorrentes (CA7);
  - uma fixture legada gerada com o script da `origin/main` por `git show` (CA8).
- **Testes de reprodução, que falham hoje e passam com a correção:** CA2 (downgrade), CA4 e CA13 (janela) e CA7.
- `bash scripts/test-protect-main.sh` (CA5 ajustado, CA10) e `bash scripts/test-session-start.sh` (CA11).
- **Regressão:** a suíte determinística completa do CI e o `claude plugin validate .`.
- Nenhum teste toca o HOME real.

## Passos de produção
nenhum

## Migração e rollback
**Migração de uma máquina:**
1. Atualizar todas as distribuições ativas:
   - Claude Code: `claude plugin marketplace update fabrica` e `claude plugin update fabrica@fabrica`;
   - Antigravity: reinstalar com `agy plugin install`;
   - OpenCode: atualizar o adaptador, conforme o `opencode/README.md`;
   - clones usados com `--plugin-dir`: rebase sobre a `main`;
   - Codex: gerar o pacote de novo depois da readequação da SPEC-245.
2. Abrir uma sessão ou rodar o `/fabrica:setup`. O `--check` migra a instalação legada: grava o `CONTENTS.sha256` quando os bytes conferem com a origem da mesma versão, ou publica quando a origem é maior.
3. Conferir que o `setup-githooks.sh --check` responde `ok`.

Enquanto houver uma distribuição legada ativa, ela pode reintroduzir o downgrade e a janela. O script novo detecta e volta para a versão maior quando pode. O manual registra esse limite.

**Rollback do código:** reverter o PR. O `VERSION` de uma linha continua legível pelo script antigo, que apaga o `CONTENTS.sha256` na primeira cópia e ignora os nomes internos que sobrarem.

**Rollback dos hooks de uma máquina:** `setup-githooks.sh --allow-downgrade <versão>` a partir da distribuição desejada, com a confirmação do `/fabrica:setup`. Ele vale até a próxima execução de uma distribuição mais nova.

## Riscos e dúvidas
- **Distribuições legadas:** fora do controle deste script. Mitigação: migração documentada e retorno à versão maior.
- **Processos que ignoram a trava:** a recuperação segue a regra de segurança.
- **NFS e contêineres:** limites documentados; o comportamento é conservador (`ocupado`).
- **`.break` ou trava ambígua:** exige remoção manual. Isso é raro.
- **macOS:** `ps -o lstart`, `shasum -a 256` e `ln -sn` são caminhos alternativos, não testados no CI (Ubuntu).
- **Integração com o B2:** a SPEC-245 reencaixa o `codex/githooks-version` na `source_version`. O B1 e esta issue são pré-requisitos da integração final do B2.

## Histórico
- 2026-11-27: criação.
- 2026-11-27: antes da publicação, detalha o ciclo de vida do diário, as combinações de metadados, o `fabrica-hook` ausente, danificado ou sem execução, a distinção entre instalação protegida e integridade não garantida, as corridas da trava, a recuperação manual do `.break` e os limites do modelo de segurança.
- 2026-11-27: mudança (alterar) — revisão documental P01–P06 pedida pelo usuário.
  - A instalação legada não é íntegra: saídas `mais-novo … incerta` e `divergente … incerta`.
  - I é o máximo das evidências; o `modo` vai no diário; um rollback interrompido exige nova confirmação.
  - Definição completa de `integra`.
  - Trava com `lstat`, `ln -sn`, conferência, estado ambíguo e nenhuma quebra em caso de dúvida.
  - Prazo do `--check` e rotina dos sinais para o timeout do `SessionStart`.
  - O rollback pode reduzir a proteção.
  - CAs alterados: 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16 e 17. Nenhum incluído ou removido.
