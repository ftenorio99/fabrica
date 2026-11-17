# SPEC-161: OpenCode: teste de aceite test-adapter.sh e README do adaptador

**Issue:** #161 · **PRD:** nenhuma (o OpenCode está no "Fora de escopo" do PRD; ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-17

## Contexto
Esta é a fase 5 do `opencode/PLANO-OPENCODE.md` (§5 e §8), sobre a #149. As fases 1 a 4 já estão na `main`: o adaptador `opencode/server.ts` registra as 12 skills, os 12 comandos `/fabrica:*`, o subagente `fabrica/revisor`, os hooks de proteção da main, de produção e do `~/.claude` e a nota de sessão dos hooks do git (#157 a #160). Falta a prova automática e a documentação: hoje o adaptador só se confere com chamadas manuais à API, e não há README para instalar, testar nem desfazer.

O Claude Code não é afetado: o adaptador é aditivo e lê os arquivos existentes em tempo de execução (§1 e §3 do plano).

## Objetivo
Um teste de aceite em `opencode/test-adapter.sh` confere, numa VM do `sbx` e sem modelo, o adaptador completo pela API do OpenCode, e o `opencode/README.md` ensina a instalar, testar e desfazer o adaptador do zero.

## Comportamento esperado
**Onde roda.** O teste roda dentro de uma VM do `sbx` criada com o agente `opencode` (`sbx create --name opencode-<projeto> opencode .`), com o clone da fábrica montado. Ele não roda no host: o servidor grava em `~/.config/opencode` e `~/.local/share/opencode`, e o teste não pode mexer na configuração do OpenCode do usuário. Fora da VM, ele para com código 1 e uma mensagem. O sinal de VM é o mesmo do `scripts/sbx-context.sh`: o arquivo `/etc/sandbox-persistent.sh` ou a variável `PROXY_CA_CERT_B64`.

**Pré-requisitos.** `opencode` no `PATH` (versão 2.3.0, API de plugins v2), `git` e `jq`. O `protect-main.sh` usa os dois; sem o `jq`, ele sai sem decidir, e o teste falharia nos casos que exigem `deny`. Faltando algum, o teste para com código 1 e diz qual.

**Fluxo.**
1. Lê a raiz da fábrica: `--root <pasta>` ou a pasta pai da pasta do script (`opencode/`).
2. Cria um projeto temporário, com `git init`, um `opencode.jsonc` com `"plugins": ["<raiz>/opencode"]` e um `.fabrica/producao.txt` com `host prod.exemplo.com`.
3. Gera uma senha aleatória, exporta `OPENCODE_PASSWORD` e, dentro do projeto, sobe `opencode serve --hostname 127.0.0.1 --port 0`, com a saída num arquivo temporário.
4. Espera por até 30 s a linha `server listening on <url>` e extrai a URL. Aos 30 s sem a linha, falha e mostra a saída do servidor.
5. Cria uma sessão com `POST /api/session` e confere que o plugin `fabrica` está `active`. O plugin pode não ter registrado os hooks na janela de inicialização (visto na #159), então espera até 30 s a sonda de permissão do `permissão: commit` devolver `deny` antes de seguir.
6. Confere, pela API (`opencode api --server <url>`, rodando com o projeto como diretório de trabalho), a tabela abaixo.
7. Lê só as linhas que o log do OpenCode ganhou desde o passo 3 e confere que não há erro do plugin.
8. Encerra o servidor e apaga o projeto temporário, com um `trap`, no sucesso e na falha.

**As verificações.**

| Nome | O que confere | Esperado |
|---|---|---|
| `vm` | o sinal de VM do `sbx` | presente; fora da VM, para com 1 |
| `binários` | `opencode`, `git` e `jq` no `PATH` | os três; faltando, para com 1 |
| `servidor` | a linha `server listening on <url>` | em até 30 s |
| `plugin` | `GET /api/plugin` e o `path` de uma skill no `GET /api/skill` | um único `fabrica`, com `status: "active"`, e o `path` da skill começando em `<raiz>/skills/`; outro `fabrica` de outro caminho é falha, com a mensagem de tirar a instalação global da VM |
| `plugin pronto` | a mesma avaliação do `permissão: commit`, repetida | `deny` em até 30 s |
| `12 comandos` | `GET /api/command` | exatamente os 12 nomes `fabrica:avancar`, `fabrica:backlog`, `fabrica:implementar`, `fabrica:licao`, `fabrica:metricas`, `fabrica:prd`, `fabrica:retro`, `fabrica:revisar`, `fabrica:setup`, `fabrica:spec`, `fabrica:status` e `fabrica:triagem`, sem nenhum `fabrica:` além deles |
| `12 skills` | `GET /api/skill` | exatamente as 12 com ID `fabrica-<pasta>`; `autoinvoke: false` nas 10 com `disable-model-invocation: true`, e `true` em `status` e `metricas` |
| `revisor` | `GET /api/agent` | `fabrica/revisor`, com `mode: "subagent"` |
| `permissão: commit` | `POST /api/session/<id>/permission` com `action: "shell"` e o recurso `git commit --allow-empty -m teste --no-verify` | `effect: "deny"` |
| `permissão: produção` | o mesmo, com `curl https://prod.exemplo.com` | `deny` |
| `permissão: ~/.claude` | o mesmo, com `echo x > ~/.claude/teste` | `deny` |
| `permissão: git status` | o mesmo, com `git status` | `effect: "allow"` |
| `permissão: linha encadeada` | o mesmo, com os recursos separados `["git status --short", "git commit --allow-empty -m teste --no-verify"]` | `deny`; é a reserva `resources.join(" && ")` da §4.5, porque sem modelo não há `tool.execute.before` |
| `log` | as linhas novas de `<log>/opencode.log`, com `<log>` lido de `opencode debug paths` | nenhuma linha `[fabrica]` fora das `shell negado (...)` dos casos acima; um erro do plugin, um script ausente ou um hook não registrado falham |
| `limpeza` | no fim, antes de sair; o `trap` repete na saída por erro | o servidor não está rodando e o projeto temporário sumiu |

**Saída e código de retorno.** Uma linha por verificação, `ok <nome>` ou `falha <nome>: <motivo>`, como no `scripts/test-sandbox-acceptance.sh`. Sai 0 quando todas passam e 1 quando alguma falha. Uma falha que impede continuar (sem VM, sem binário, servidor que não sobe, sessão que não é criada) para o teste ali. A falha de prontidão do plugin não impede as chamadas: o teste segue e marca as permissões. A senha nunca é impressa.

**Prova de falha.** Com uma cópia da raiz em que o bloco `ctx.permission.hook("evaluate")` foi removido, e `--root` apontando para ela, o teste sai 1 e marca `falha` na prontidão e nas permissões que exigem `deny`.

**`--root`.** Opcional. Sem ele, a raiz é a pasta pai de `opencode/`. Aceita caminho relativo, resolvido a partir do diretório de onde o teste roda. Uma opção desconhecida sai com 1 e a mensagem de uso.

**O `opencode/README.md`.** Nesta ordem, o suficiente para instalar do zero:
1. o que o adaptador faz (12 skills, 12 comandos, `fabrica/revisor`, hooks), o que é adaptado e o que não existe (statusline, custo real);
2. requisitos: OpenCode 2.3.0 (API v2), `git`, `jq`;
3. instalação: a entrada `"plugins": ["<clone>/opencode"]` em `~/.config/opencode/opencode.jsonc`, que precisa ser uma pasta, e `opencode reload` ou `opencode service restart`; como conferir no TUI;
4. atualização: `git pull` no clone e o reload, sem passo de cópia;
5. teste: `bash opencode/test-adapter.sh` dentro da VM com o agente `opencode`, o que ele confere e o `--root`;
6. rollback: tirar a entrada da `"plugins"`, recarregar e, opcionalmente, apagar a pasta; nada em `~/.claude` é tocado;
7. limites conhecidos: o shell digitado pelo usuário não passa pelo hook de permissão; uma regra `deny` do usuário é final; o `opencode run "/fabrica:..."` não executa comandos; a statusline não existe no OpenCode; os tokens saem como `nao-medido`; a janela de inicialização do plugin; o guarda-corpo é por texto; o formato do `edit` não foi conferido com uma ferramenta real.

**O `AGENTS.md`.** A lista de `Estrutura` ganha um item para a pasta, no estilo dos outros:

> `- opencode/: adaptador da fábrica para o OpenCode, com as skills, os comandos `/fabrica:*`, o subagente `fabrica/revisor` e os hooks de proteção; a instalação e os limites estão em `opencode/README.md`. O teste de aceite roda com `bash opencode/test-adapter.sh`, dentro da VM do `sbx` com o agente `opencode`.`


## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Numa VM do `sbx` com o agente `opencode`, na branch, `bash opencode/test-adapter.sh` sai com 0 e imprime `ok` para `vm`, `binários`, `servidor`, `plugin`, `plugin pronto`, `12 comandos`, `12 skills`, `revisor`, as cinco `permissão`, `log` e `limpeza` | manual — o usuário roda na VM (o servidor grava em `~/.config/opencode` e `~/.local/share/opencode`), e o agente não cria a VM |
| CA2 | Com `--root` apontando para uma cópia da raiz sem o bloco `ctx.permission.hook("evaluate")`, a mesma execução sai com 1 e marca `falha` na prontidão e nas permissões que exigem `deny` | manual — na VM, com a cópia numa pasta temporária |
| CA3 | Fora da VM, o script sai com 1, diz que precisa da VM do `sbx` e não sobe servidor nem cria projeto temporário | manual — no host, na branch |
| CA4 | Sem `opencode`, `git` ou `jq` no `PATH`, ou com um `opencode` falso que responde ao `debug paths` e não imprime `server listening on`, o script sai com 1, diz a causa e não deixa processo do teste | manual — na VM, com o `PATH` restrito ou um `opencode` falso |
| CA5 | A checagem do log usa só as linhas acrescentadas depois do início do servidor: com um erro `[fabrica]` antigo no log, a execução passa; com um erro novo, como um `hooks/protect-main.sh` ausente na cópia do `--root`, a verificação `log` falha | manual — duas execuções na VM |
| CA6 | Ao terminar, no sucesso e na falha, o projeto temporário foi apagado e o `opencode serve` do teste não está rodando: `pgrep -af "opencode serve --hostname 127.0.0.1 --port 0"` não mostra o processo | manual — na VM, conferir com `ls` e `pgrep` |
| CA7 | A saída do script não contém a senha do servidor | manual — leitura do script e da saída da execução |
| CA8 | Seguindo só o `opencode/README.md` numa VM nova com o `opencode` instalado, o adaptador fica instalado e o TUI lista os 12 comandos `/fabrica:*` | manual — VM nova, sem outra fonte |
| CA9 | O `opencode/README.md` tem as seções de instalação, atualização, teste, rollback e limites, e os limites incluem os três da issue (shell do usuário, `deny` do usuário, `opencode run`) e os dois do plano (statusline, custo real) | manual — leitura |
| CA10 | O `AGENTS.md` tem o item `opencode/` da lista de `Estrutura`, com `bash opencode/test-adapter.sh` e a VM do `sbx` | manual — leitura |
| CA11 | `git diff --name-only origin/main...HEAD` mostra só `opencode/test-adapter.sh`, `opencode/README.md`, `AGENTS.md` e `specs/SPEC-161.md` | manual — o comando, na branch |
| CA12 | Os testes bash atuais passam: todo `scripts/test-*.sh` da `main`, menos o `test-sandbox-acceptance.sh` | manual — rodar cada script |

## Fora de escopo
- A verificação com modelo do §8 do plano: o `/fabrica:status` no TUI, o commit recusado na sessão real, o subagente `fabrica/revisor` e a ponte `execute.before` de uma linha encadeada real.
- O formato do `edit` no guarda-corpo, que só a SPEC-159 verificou pela API, e as variações de texto do shell que ela deixou passar.
- Corrigir a janela de inicialização no adaptador: o teste espera, e o README documenta.
- Statusline, medição real de tokens e checklist do `sbx` para o agente `opencode`.
- Mudanças em `skills/`, `agents/`, `hooks/`, `githooks/`, `scripts/`, `templates/`, `docs/`, `.claude-plugin/` e na configuração do OpenCode da máquina do usuário.
- Publicar o adaptador como pacote npm e instalá-lo por projeto em `.opencode/plugins/`.
- Fazer o `opencode run "/fabrica:..."` executar comandos, que a fase 0 mostrou não acontecer.

## Desenho técnico
**Arquivos e módulos:** `opencode/test-adapter.sh` (novo), `opencode/README.md` (novo) e um item em `AGENTS.md`. Nenhuma mudança em `opencode/server.ts` nem nos arquivos do Claude Code.

**Dados:** nenhum.

**Interfaces:**
- `opencode/test-adapter.sh [--root <pasta>]`: sem opção, a raiz é a pasta pai da pasta do script. `--help` imprime o uso e sai 0; opção desconhecida vai para o stderr e sai 1.
- Saída: `ok <nome>` ou `falha <nome>: <motivo>`, uma por linha; código 0 se nenhuma falhou, 1 caso contrário.
- Estado fora do projeto temporário: só o log e os dados do OpenCode da VM, que o servidor grava. A senha fica em `OPENCODE_PASSWORD` e não é impressa.
- O projeto temporário: `opencode.jsonc`, `.fabrica/producao.txt` e o repositório git. O servidor sobe com ele como diretório de trabalho, e as chamadas da API também.
- Funções: `ok`, `bad` (contador e saída), `cleanup` (trap), `resolve_root`, `start_server`, `wait_url`, `api`, `new_session`, `permission`, `log_since`, além de uma por verificação.

**Decisões:**
- **A linha do teste fica no `AGENTS.md`, num item próprio de `opencode/`** (recomendação da triagem): a issue pede "junto dos demais", e desde a #165 as regras do repositório estão no `AGENTS.md`, com o `CLAUDE.md` só importando-o; a pasta também ainda não aparece na lista de `Estrutura`, e o item diz onde o teste roda. Alternativa: o `CLAUDE.md`, como a issue nomeia, que hoje só importa o `AGENTS.md` e não lista testes.
- **A linha encadeada é conferida sem modelo, pela reserva `resources.join(" && ")`** (recomendação da triagem): a §8 do plano pede o teste "sem modelo", e sem modelo não há chamada de ferramenta que passe pelo `execute.before`; o CA6 da SPEC-159 fez assim. Alternativa: um passo com `opencode run --auto`, que exige modelo, rede e gateway.
- **A VM é criada com o agente `opencode`** (recomendação da triagem): a §4.7 do plano diz que o `sbx` aceita esse agente, e a VM do checklist do setup nasce com o `claude`, sem o binário. Alternativa: instalar o `opencode` na VM do projeto e documentar isso.
- **O teste recusa rodar fora da VM:** o servidor grava no `~/.config/opencode` e no `~/.local/share/opencode`, e rodar no host mexeria na configuração do usuário, que o plano evita (§5). Os sinais são os mesmos de `scripts/sbx-context.sh`. Alternativa: aceitar qualquer máquina e documentar o risco.
- **A senha e a porta:** o teste define `OPENCODE_PASSWORD` com um valor aleatório, sobe o servidor com `--port 0` e lê a URL de `server listening on`. O servidor usa o valor da variável e, nesse caso, não imprime a senha; a porta 0 evita conflito. Alternativa: subir sem a variável, ler `server password ...` da saída e fixar uma porta.
- **O log é lido pela diferença desde o começo do servidor, e as linhas de negativa esperadas são excluídas:** o arquivo é cumulativo e o plugin registra cada negativa com `console.error`; sem as duas regras, a segunda execução falharia pelas linhas antigas e as negativas esperadas contariam como erro. Alternativa: ler o log inteiro e proibir todo `[fabrica]`, que quebra as duas coisas.
- **A prontidão é o plugin ativo mais a sonda de negativa:** a #159 viu avaliações passarem antes de o plugin carregar; a sonda no mesmo endpoint dos casos elimina a janela. Alternativa: esperar só o `status: "active"`.
- **`--root` é opcional:** permite provar a falha com uma cópia sem o hook de permissão, sem editar o clone. Alternativa: sem a opção, a prova exigiria editar o clone e desfazer.
- **A saída é `ok`/`falha`, com código 1:** é a convenção do `scripts/test-sandbox-acceptance.sh`, que roda no mesmo tipo de VM. Alternativa: só o código de retorno, sem o detalhe por verificação.
- **O teste usa `opencode api`:** é o que a issue pede e dispensa montar o cabeçalho Basic auth à mão. Alternativa: `curl` com `-u opencode:<senha>`, como nas SPEC-157 a SPEC-159.
- **O caminho do log vem de `opencode debug paths`:** a saída tem a linha `log <pasta>`. Alternativa: fixar `~/.local/share/opencode/log/opencode.log`, o caminho da issue.
- **Sem subida de `version` no `plugin.json`:** a mudança é no adaptador e nas regras do repositório, e não altera o comportamento do plugin do Claude Code, que já copia o `opencode/` sem efeito. Alternativa: subir a versão mesmo assim.

**Fontes da documentação:**
- opencode 2.3.0 (`opencode --version`) — `opencode serve --help` (`--hostname`, `--port`), `opencode api --help` (`--server`, `--data`), `opencode debug paths` (a linha `log <pasta>`). As rotas `POST /api/session` (`session.create`) e `POST /api/session/:sessionID/permission` (`session.permission.create`, com `action` e `resources`) foram conferidas nas definições OpenAPI do binário 2.3.0.
- **Não verificados na documentação:** a variável `OPENCODE_PASSWORD` e a linha `server listening on <url>` (conferidas no binário), o campo `effect` da resposta da permissão (visto na #149 e nas SPEC-158 e SPEC-159) e o corpo do `POST /api/session` sem diretório explícito (o servidor sobe com o projeto como diretório de trabalho).
- Context7: não consultado — a documentação indexada descreve a v1 do OpenCode (§0 do plano), que a v2 não traduz.
- `git`, `jq` e `bash`: os mesmos já usados por `hooks/` e `scripts/`, sem versão nova fixada.
- gh 2.104.0 — a spec não cita flag nem campo do `gh`.

**ADR:** nenhum. O adaptador e as decisões dele estão no plano mergeado; esta spec só acrescenta o teste e a documentação.

## Testes
O entregável é o teste. O implementador roda o que não depende da VM: `bash -n opencode/test-adapter.sh`, a recusa fora da VM (CA3), o `grep` da senha (CA7), o `git diff` (CA11) e os testes bash atuais (CA12). O CA1, o CA2, o CA4 ao CA6 e o CA8 ao CA10 dependem da VM e da leitura, e ficam para o usuário rodar na branch. O que anotar no PR: a saída do teste na VM (CA1), a da cópia sem o hook (CA2), o `git diff`, e os resultados dos testes atuais.

## Passos de produção
nenhum

## Riscos e dúvidas
- **A primeira execução completa é na VM, e o agente não a cria.** Um erro de fluxo do teste só aparece nela. O usuário pode rodar antes do merge, na branch, e o PR traz a saída.
- **A API não é documentada** (o corpo da permissão, o `effect` e a criação da sessão). Uma mudança do OpenCode quebra o teste, que é o que ele deve acusar; o README fixa a versão conferida.
- **O log é cumulativo e registra as negativas como erro.** Sem a diferença desde o início e a exclusão das `shell negado`, o teste falharia por linhas antigas ou pelas próprias negativas (decisão acima).
- **A janela de inicialização.** A prontidão pela sonda cobre o caso visto na #159; se o plugin demorar mais de 30 s, o teste falha, e o README documenta a janela.
- **A linha encadeada testa a reserva, não a ponte.** A ponte `execute.before` continua coberta pelo teste manual com modelo (SPEC-159, CA6).
- **A VM do teste não é a do checklist do setup.** Ela nasce com o agente `opencode`, e o usuário a cria; a do projeto nasce com o `claude` e não traz o binário. O README mostra o comando.
- **`AGENTS.md` é mais um arquivo fora de `opencode/`,** contra o invariante 5 da §1 e o checkpoint da §7 do plano. A issue pede a linha, e a triagem a levou para o `AGENTS.md`; o CA11 admite o arquivo.
- **O PRD deixa o OpenCode fora de escopo.** A issue e o plano mergeado tratam de portabilidade, como nas SPEC-157 a SPEC-160, que foram aceitas.
- **O README "basta para instalar do zero" é um julgamento,** conferido numa VM limpa e não na máquina do usuário (CA8).

## Histórico
- 2026-11-17: criação.
- 2026-11-17: aprovada.
