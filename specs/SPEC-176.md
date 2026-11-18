# SPEC-176: OpenCode: os primeiros comandos de shell de uma localização passam sem o hook de produção

**Issue:** #176 · **PRD:** nenhuma (o OpenCode está fora do escopo do PRD, que fica "só no Claude Code"; mesma situação das #161, #162 e #173, ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-18

## Contexto
A #173 mediu a **janela de inicialização** do adaptador `opencode/server.ts` no OpenCode 2.3.0: o plugin carrega por localização, de forma preguiçosa, no primeiro acesso que precisa dele, e leva cerca de 0,7 a 1,0 s. Nesse intervalo, a 1ª avaliação de permissão sai `deny` do próprio OpenCode e 1 a 3 seguintes saem `allow`, antes do 1º `deny` do `protect-production.sh`. Vale nas duas instalações, e o plugin não a fecha, porque os `allow` acontecem antes de o `setup` rodar. Hoje a janela só está documentada em `opencode/README.md`, que aponta para esta issue. A issue pede fechar a janela, ou provar que não dá e registrar o limite, por três caminhos (regra `deny` fixa na config, pré-carregamento, sessão com modelo), e corrigir um defeito de isolamento no `opencode/test-adapter.sh`, apontado na revisão do PR #175.

**O que esta spec mediu** (OpenCode 2.3.0, VM `opencode-fabrica`, sonda `curl https://prod.exemplo.com` em sequência, a 1ª chamada logo depois do primeiro acesso à localização):

| Caminho | Medido | Fecha a janela? |
|---|---|---|
| Regra estática no `permissions` do topo do `opencode.jsonc` do projeto (formato da doc, `{ "action": "shell", "resource": "*prod.exemplo.com*", "effect": "deny" }`; variantes com `"action": "*"` e com `"curl *prod.exemplo.com*"`) | `opencode debug config` lista a regra, mas ela **nunca negou**: `allow` em todas as 8 avaliações, também depois de carregar. A regra padrão `* * allow` vem depois dela na lista | não |
| Regra estática em `agents.build.permissions` do `opencode.jsonc` do projeto | nega, mas só a partir de 0,73 s: as 3 primeiras avaliações (0 a 0,6 s) saíram `allow`. A config também é por localização | não |
| A mesma regra em `agents.build.permissions` da config **global** | nega a partir de 0,76 s; 1ª `deny` do OpenCode e 3 `allow` antes | não |
| Pré-carregar a localização pelo cliente: `GET /api/command` (ou `GET /api/agent`) antes da sessão, esperando os 12 `fabrica:*` (ou 2 s) | **as 8 avaliações seguintes saíram `deny`, desde a 1ª (1 a 2 ms)**, nas duas formas | **sim, se o cliente faz isso antes da 1ª ferramenta** |
| Sessão com modelo | **não medido**: a VM não tem provedor, e um `opencode run` sem provedor não terminou em 120 s | desconhecido |

Duas conclusões: nenhuma regra estática fecha a janela, porque a config é carregada com a localização, e só o pré-carregamento fecha. O pré-carregamento é do **cliente** (TUI, `opencode run`, API), e o plugin não o faz. A pergunta que sobra, e que só uma sessão com modelo responde, é se o cliente real já pré-carrega antes da primeira ferramenta do modelo.

## Objetivo
A janela de inicialização fica registrada com o que foi medido nos três caminhos, a forma de fechá-la (pré-carregar a localização) fica documentada e coberta pelo teste de aceite, e o teste de aceite deixa de passar a verificação `permissão: commit` pelo motivo errado.

## Comportamento esperado
**Janela fechada pelo pré-carregamento, com prova.** O `opencode/test-adapter.sh` ganha a verificação `aquecido: sem janela`, em cada modo (`projeto`, `global`, `ambos`): num servidor e numa localização novos, ele pré-carrega com `GET /api/command` até listar os 12 `fabrica:*` e, sem esperar mais, avalia `curl https://prod.exemplo.com` 8 vezes seguidas na sessão do projeto A. As 8 saem `deny`. Se alguma sair `allow`, a verificação falha e diz em qual avaliação. A sonda de negação de 30 s que já existe continua valendo para as outras verificações.

**Isolamento do `permissão: commit`.** O `protect-main.sh` (linhas 33 a 36) nega qualquer comando com `commit` ou `push` quando o `core.hooksPath` global não é `${XDG_CONFIG_HOME:-$HOME/.config}/fabrica/githooks`, e essa checagem vem **antes** da recusa de `--no-verify` (linha 43). Com o `XDG_CONFIG_HOME` temporário do teste, e também numa VM sem os hooks do git instalados, o primeiro ramo nega o commit, e o `ok permissão: commit` passa sem exercitar a regra de `--no-verify`. Isso vem da leitura do código: o motivo da negação não aparece na saída do teste, e esta spec não o mediu (o hook `protect-main` do Claude recusa as linhas de comando que o medem). O teste passa a:
- deixar o `git config --global` do ambiente isolado (servidor e API) apontando o `core.hooksPath` para o destino que o `protect-main.sh` espera nesse ambiente, para o primeiro ramo não negar;
- só marcar `ok permissão: commit` se, além do `deny` da API, a linha `[fabrica] shell negado (...)` do log do servidor para esse comando trouxer o motivo de `--no-verify` (e não "hooks do git ... não estão instalados"); senão, `falha permissão: commit` com o motivo lido.

**Prova de falha do isolamento.** Com `--root` apontando para uma cópia da raiz em que a linha da recusa de `--no-veri` foi tirada do `hooks/protect-main.sh`, `--install projeto` sai com 1 e marca `falha` em `permissão: commit`, com o motivo "negado por outro motivo" ou equivalente. Antes desta spec, essa cópia passava.

**O README.** O item "Janela de inicialização" de "Limites conhecidos" passa a trazer as três medições da tabela acima, em vez de remeter a esta issue, e uma seção "Fechar a janela" ensina o pré-carregamento: antes da primeira etapa de agente numa localização, chame `GET /api/command` com `location[directory]=<projeto>` e espere os 12 comandos `fabrica:*` (ou `GET /api/plugin` com o `fabrica` `active`); depois disso, nenhuma avaliação passa sem o hook, como o teste prova. O README diz que o TUI e o `opencode run` não foram observados nesse ponto, e traz o procedimento para quem tem um provedor medir (próximo parágrafo). A regra estática fica explicada como alternativa que **não** fecha a janela, com o formato que funciona (`agents.<agente>.permissions`) e o que não funciona (`permissions` no topo).

**Medir com modelo (pedido ao usuário, depois do merge).** O README descreve, em passos curtos, como medir numa VM com provedor: subir `opencode serve` no projeto com o plugin e o `.fabrica/producao.txt`, abrir uma sessão e mandar o prompt "rode `curl https://prod.exemplo.com` e mostre a saída" **sem** pré-carregar, e conferir no log do servidor se há uma linha `[fabrica] shell negado` para esse comando ou se o comando executou. O usuário roda o procedimento e anota o resultado na #176.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Em cada modo, depois do pré-carregamento (`GET /api/command` até os 12 comandos), 8 avaliações seguidas de `curl https://prod.exemplo.com` no projeto A saem `deny`. | manual — `bash opencode/test-adapter.sh` na VM do `sbx` com o agente `opencode`: `ok aquecido: sem janela` nos três modos |
| CA2 | O `ok permissão: commit` só sai quando o log do plugin traz o motivo de `--no-verify` para o comando negado, com o `core.hooksPath` global do ambiente isolado apontando para o destino esperado pelo `protect-main.sh`. | manual — o mesmo teste, olhando o `ok` e, no código, a leitura do log |
| CA3 | Com `--root` apontando para uma cópia sem a recusa de `--no-veri` no `hooks/protect-main.sh`, `--install projeto` sai com 1 e marca `falha permissão: commit`. | manual — na VM, com a cópia numa pasta temporária |
| CA4 | O teste não falha por causa da janela nem do novo isolamento: três execuções seguidas do teste sem `--install` (`todos`) saem 0, e `config global intacta` segue `ok`. | manual — três execuções na VM |
| CA5 | O `opencode/README.md` traz as três medições da tabela (regra estática, pré-carregamento, sessão com modelo não medida), a seção "Fechar a janela" com o pré-carregamento e o sinal de "pronto", o formato de regra estática que funciona e o que não, e o procedimento "Medir com modelo". | manual — leitura |
| CA6 | Uma sessão com modelo, sem pré-carregar, mostra se a primeira ferramenta `shell` de uma localização nova passa sem o hook; o resultado fica registrado na #176. | depois do merge — a VM `opencode-fabrica` não tem provedor de modelo, e os agentes não rodam sessão interativa com provedor; o usuário roda o procedimento do README |
| CA7 | `git diff --name-only origin/main...HEAD` mostra só arquivos de `opencode/` (`test-adapter.sh`, `README.md`, e `PLANO-OPENCODE.md` se mudar) e `specs/SPEC-176.md`; `opencode/server.ts` e o plugin do Claude Code (`.claude-plugin/`, `skills/`, `agents/`, `hooks/`, `scripts/`) não mudam. | manual — o comando, na branch |
| CA8 | Os testes bash atuais passam: todo `scripts/test-*.sh` da `main`, menos o `test-sandbox-acceptance.sh`. | manual — rodar cada script |

## Fora de escopo
- Gerar a regra `deny` a partir do `.fabrica/producao.txt` (um script ou o `/fabrica:setup`). A medição mostra que ela não fecha a janela e que o formato do topo é ignorado; manteria uma segunda lista e mexeria no plugin do Claude Code.
- Código que pré-carregue a localização (um wrapper ou lançador do OpenCode). O pré-carregamento é do cliente, fica documentado e provado pelo teste.
- Mudar o `opencode/server.ts`: nenhum caminho medido depende dele.
- O hook `session.context` e a statusline.

## Desenho técnico
**Arquivos e módulos:**
- `opencode/test-adapter.sh`: a verificação `aquecido: sem janela`, o `core.hooksPath` do ambiente isolado, a leitura do motivo no log para `permissão: commit` e a mensagem de falha por motivo trocado.
- `opencode/README.md`: limites, "Fechar a janela" e "Medir com modelo", e a seção "Teste".
- `opencode/PLANO-OPENCODE.md`: só se a §6 ou a §11 precisarem registrar a janela (edição pequena).
- `specs/SPEC-176.md`: esta spec.

**Dados:** nenhum.

**Interfaces:** o `opencode api` e a API HTTP do OpenCode 2.3.0 que o teste já usa (`GET /api/command`, `GET /api/plugin`, `POST /api/session`, `POST /api/session/<id>/permission`), com `location[directory]`. A API de permissão devolve só `{id, effect}`; o motivo vem da linha `[fabrica] shell negado (...) | motivo: ...` que o plugin escreve na saída do servidor. Nenhuma interface nova.

**Decisões:**
1. **A janela fecha pelo pré-carregamento do cliente, não por regra nem por código do plugin** — foi o único caminho medido que fechou a janela (8 de 8 `deny` desde a 1ª avaliação), e a regra estática tem a mesma janela. Alternativa descartada: regra `deny` gerada do `producao.txt`, que não fecha a janela, ignora o formato do topo e muda o plugin do Claude Code.
2. **O pré-carregamento é documentado e provado pelo teste, sem lançador novo** — o cliente real (TUI, `opencode run`) não é nosso. Alternativa descartada: um `opencode/warmup.sh`, que ninguém chamaria no caminho do TUI.
3. **A sessão com modelo vira CA `depois do merge`, com o procedimento no README** — a VM não tem provedor. Alternativa descartada: declarar a janela inofensiva por hipótese.
4. **O `permissão: commit` passa a conferir o motivo no log** — a API de permissão não devolve a mensagem, só o `effect`, e o log do plugin é a única fonte do motivo. Alternativa descartada: só apontar o `core.hooksPath` e registrar o limite no README, o que deixaria a regra de `--no-verify` sem cobertura (recomendação da triagem, mantida com a conferência do motivo).

**Fontes da documentação:**
- OpenCode 2.3.0, permissões — Context7 `/websites/opencode_ai` (v2), `opencode.ai/docs/permissions.md` e `.../agents.md`: regras em ordem, a última que casa vence, regras globais antes das do agente; `agents.<nome>.permissions`. A forma do topo (`permissions`) está na doc e **não** negou na 2.3.0: a medição desta spec prevalece. O comportamento da janela vem da medição.
- Bash e `jq` — sem versão a registrar; os do `test-adapter.sh` atual.
- gh 2.104.0 — nenhum comando novo no desenho; os usados são os da etapa.

**ADR:** nenhum.

## Testes
- Os CAs 1 a 4 são o próprio `opencode/test-adapter.sh`, rodado dentro da VM do `sbx` com o agente `opencode` (`sbx exec opencode-fabrica bash opencode/test-adapter.sh [--install <modo>]`). O teste recusa rodar no host. A VM `opencode-fabrica` existe, parada, e o `sbx exec` a inicia.
- O CA3 roda com uma cópia da raiz em pasta temporária, com a linha da recusa de `--no-veri` tirada do `hooks/protect-main.sh` por `sed`, e `--root <cópia> --install projeto`.
- O CA8 roda os testes bash do plugin no host.
- **Cuidado:** o hook `protect-main` do Claude recusa uma linha de comando que cita `XDG_CONFIG_HOME`, `HOME=`, `GIT_CONFIG*` ou `core.hooksPath`. O isolamento fica dentro do `test-adapter.sh`, que os define; nenhuma linha de comando da implementação precisa citá-los.

## Passos de produção
nenhum

## Riscos e dúvidas
- **A janela segue aberta para quem não pré-carrega.** Esta issue a registra e a prova fechada no caso do pré-carregamento, mas não muda o comportamento do OpenCode. Se a sessão com modelo (CA6) mostrar que o cliente real passa pela janela, a correção é de outro lugar (o próprio OpenCode ou o fluxo de uso) e vira outra issue.
- **O `hooksPath` do ambiente isolado.** A VM pode ter um `~/.gitconfig` com o próprio `core.hooksPath`, que vence a config do `XDG`. O teste precisa isolar o `git config --global` por inteiro (por exemplo, apontando a config global do git do servidor e da API para um arquivo próprio), e o CA2 só vale com o motivo certo no log.
- **O motivo no log.** A conferência depende do texto da negação do `protect-main.sh`. Uma mudança futura nele quebra o teste, o que é desejado, e a mensagem de falha mostra o motivo lido.
- **Fora do PRD.** Como nas #161, #162 e #173, o OpenCode está fora do "só no Claude Code" do PRD. A issue existe por decisão do usuário (#149), e a spec não muda o PRD.

## Histórico
- 2026-11-18: criação.
- 2026-11-18: aprovada.
