# SPEC-173: OpenCode: registrar comandos e hooks por projeto na instalação global

**Issue:** #173 · **PRD:** nenhuma (o OpenCode está fora do escopo do PRD, que fica "só no Claude Code"; mesma situação das #161 e #162, ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-18

## Contexto
O adaptador `opencode/server.ts` (#167 a #172) leva ao OpenCode as 12 skills, os comandos `/fabrica:*`, o subagente `fabrica/revisor` e os hooks de proteção. O README da #161 manda instalá-lo por projeto, porque, com o plugin só na entrada global (`~/.config/opencode/opencode.jsonc`), a #161 viu `GET /api/command` do projeto sem os comandos e o hook de produção sem efeito. A #173 nasceu dessa observação e pedia mudar o `server.ts`.

**A investigação da implementação e a desta spec (OpenCode 2.3.0, VM `opencode-fabrica`) mostraram que o defeito não é de diretório.** O `setup(ctx)` de um plugin global roda uma vez por localização, com o `ctx.location.directory` dela, e a avaliação de permissão de uma sessão cai na instância da própria localização. Depois de a localização carregar, a entrada global dá os 12 comandos e o hook lê o `.fabrica/producao.txt` do projeto da sessão, sem mudar o `server.ts`. O que a #161 viu é a **janela de inicialização**, descrita abaixo, que existe também na instalação por projeto. Esta spec, portanto, passa a provar a instalação global no teste, a dizer a verdade no README e a registrar o que se sabe da janela.

## Objetivo
A instalação global do adaptador passa a ser coberta pelo teste de aceite e documentada, e a janela de inicialização fica registrada no README com o que foi medido, valendo para as duas instalações.

## Comportamento esperado
**Instalação global (já funciona; passa a ser provada).** Com a pasta `opencode/` só em `"plugins"` de `~/.config/opencode/opencode.jsonc`, depois de a localização carregar: `GET /api/command` com `location[directory]=<projeto>` lista exatamente os 12 `fabrica:*`, sem duplicata; `curl https://prod.exemplo.com` numa sessão do projeto A (`.fabrica/producao.txt` com `host prod.exemplo.com`) é negado; o mesmo comando numa sessão do projeto B, sem o arquivo, passa (`allow`).

**Instalação por projeto** continua como hoje, com as mesmas verificações. Com a entrada global e a do projeto ao mesmo tempo, há 1 plugin `fabrica`, 12 comandos, e cada comando negado deixa uma linha de negação no log.

**Janela de inicialização (medida; o plugin não a fecha).** O carregamento do plugin é por localização e preguiçoso: começa no primeiro acesso que precisa dos plugins da localização (não no boot do servidor nem na criação da sessão) e leva cerca de 0,7 a 1,0 s. Medido com a sonda `curl https://prod.exemplo.com`, repetida em sequência logo depois do primeiro acesso:

| Instalação | Execuções | 1ª avaliação | Avaliações seguintes | 1º `deny` do plugin |
|---|---|---|---|---|
| só por projeto | 10 | `deny` do OpenCode, sem mensagem, em até 0,17 s | 1 a 3 `allow` | 0,68 a 1,03 s |
| só global | 3 | igual | 1 a 2 `allow` | 0,73 a 1,00 s |
| global e projeto | 2 | igual | 2 `allow` | 0,78 a 0,79 s |

Com 5 s de espera depois de criar a sessão, a sequência é a mesma: a janela começa no primeiro acesso, não no boot. Numa localização nova de um servidor que já estava de pé há 6 s, também. Os `allow` acontecem **antes de o `setup` do plugin rodar**: com um plugin sonda que registra o hook de permissão na primeira linha do `setup`, o `[probe] setup` apareceu a 0,90 e 1,02 s do primeiro acesso, depois dos `allow` de 0,28 a 0,90 s. Nenhum código do plugin roda antes do `setup`, então nenhuma mudança no `server.ts` (ordem dos hooks, negar até estar pronto) fecha a janela. Fechar exige algo fora do plugin; está proposto em "Fora de escopo".

**O que não foi medido:** se uma sessão com modelo chega a avaliar uma ferramenta dentro da janela. A VM não tem provedor, e o carregamento do plugin é anterior à primeira resposta do modelo no caso comum, mas isso é hipótese. O README diz "não medido".

**O teste de aceite.** O `opencode/test-adapter.sh` ganha `--install projeto|global|ambos|todos`, com `todos` como padrão, e roda o conjunto de verificações uma vez por modo pedido, cada um com um servidor e um projeto temporário próprios. `projeto` e `global` são as entradas sozinhas, `ambos` é a entrada global e a do projeto juntas, e `todos` roda os três. As verificações atuais valem em cada modo. No modo `global`, o `opencode.jsonc` do projeto temporário não tem a entrada do plugin, que vem do `opencode.jsonc` global. A sonda de negação que já existe (até 30 s) cobre a janela em todos os modos. Acrescentam-se:

| Nome | O que confere | Esperado |
|---|---|---|
| `global: 12 comandos` | `GET /api/command` do projeto A, instalação só global, depois da sonda | exatamente os 12 |
| `global: produção do projeto` | permissão `curl https://prod.exemplo.com` na sessão do projeto A | `deny` |
| `global: produção isolada` | o mesmo comando na sessão do projeto B, sem `.fabrica/producao.txt` | `allow` |
| `ambos: sem duplicata` | instalação global e por projeto juntas | 1 plugin `fabrica`, os 12 comandos, e uma linha de negação por comando negado |
| `config global intacta` | o `opencode.jsonc` global antes e depois do teste | idêntico (ou ausente nos dois) |

A configuração global do teste é isolada, na ordem, com `XDG_CONFIG_HOME` e `XDG_DATA_HOME` numa pasta temporária, definidas só no ambiente dos processos `opencode serve` e `opencode api` (nunca exportadas para o resto do script, para o `git` do teste não mudar de configuração global), se a versão instalada as respeitar; senão, com cópia do `opencode.jsonc` global existente e restauração pelo `trap`, no sucesso e na falha. Em nenhum caso o teste deixa a entrada do plugin na configuração global da VM.

**Prova de falha.** O teste precisa falhar quando a instalação global deixa de valer. Com `--root` apontando para uma cópia da raiz alterada em pasta temporária, `--install global` sai com 1:
- cópia sem o registro de comandos (`ctx.command.transform` removido do `server.ts`): marca `falha` em `global: 12 comandos`;
- cópia em que o `cwd` do `setup` é o diretório pessoal em vez de `ctx.location?.directory`: marca `falha` em `global: produção do projeto`.

**O README.** A seção "Instalação" passa a oferecer as duas entradas (por projeto e global), com o que cada uma faz; o primeiro item de "Limites conhecidos" (a entrada global não registra comandos nem hook) sai; o item "Janela de inicialização" passa a trazer os números medidos, o que não foi medido, que vale nas duas instalações e que o plugin não consegue fechá-la. A seção "Teste" explica o `--install` e que, com `projeto`, a VM não deve ter o adaptador na configuração global.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com o plugin só na entrada global, `GET /api/command` com `location[directory]=<projeto>` lista os 12 comandos `fabrica:*`, sem duplicata. | manual — `bash opencode/test-adapter.sh --install global` na VM do `sbx` com o agente `opencode`: `ok global: 12 comandos` |
| CA2 | Com a entrada global, a avaliação de `curl https://prod.exemplo.com` numa sessão do projeto com `.fabrica/producao.txt` (`host prod.exemplo.com`) devolve `deny`. | manual — o mesmo teste: `ok global: produção do projeto` |
| CA3 | Com a entrada global, o mesmo comando numa sessão de outro projeto sem `.fabrica/producao.txt` devolve `allow`: o arquivo lido é o do projeto da sessão. | manual — o mesmo teste: `ok global: produção isolada` |
| CA4 | Com a entrada global e a do projeto ao mesmo tempo, há 1 plugin `fabrica`, 12 comandos e uma linha de negação por comando negado. | manual — `--install ambos` na VM: `ok ambos: sem duplicata` |
| CA5 | A instalação só por projeto passa em todas as verificações que já existiam. | manual — `--install projeto` na VM: todas `ok`, saída 0 |
| CA6 | `--install` com valor desconhecido, ou sem valor, sai com 1 e mostra o uso; sem a opção, roda `todos`. | manual — três execuções na VM |
| CA7 | O teste não deixa o plugin na configuração global da VM: depois de qualquer execução, no sucesso ou na falha, o `opencode.jsonc` global é idêntico ao de antes. | manual — `sha256sum` antes e depois (ou ausente nos dois); `ok config global intacta` |
| CA8 | As duas cópias da prova de falha fazem `--install global` sair com 1: a sem registro de comandos marca `falha` em `global: 12 comandos`, e a com o `cwd` do `setup` no diretório pessoal marca `falha` em `global: produção do projeto`. | manual — na VM, com as cópias numa pasta temporária |
| CA9 | A janela de inicialização não derruba o teste: três execuções seguidas do teste sem `--install` (`todos`) saem 0. | manual — três execuções na VM |
| CA10 | O `opencode/README.md` documenta as duas instalações e o `--install`, não afirma mais que a entrada global não registra comandos nem hook, e descreve a janela com os números medidos, o "não medido" e o fato de valer nas duas instalações. | manual — leitura |
| CA11 | `git diff --name-only origin/main...HEAD` mostra só `opencode/test-adapter.sh`, `opencode/README.md`, `opencode/PLANO-OPENCODE.md` (se mudar) e `specs/SPEC-173.md`; nem o `opencode/server.ts` nem o plugin do Claude Code (`.claude-plugin/`, `skills/`, `agents/`, `hooks/`, `scripts/`) mudam. | manual — o comando, na branch |
| CA12 | Os testes bash atuais passam: todo `scripts/test-*.sh` da `main`, menos o `test-sandbox-acceptance.sh`. | manual — rodar cada script |

## Fora de escopo
- **Fechar a janela de inicialização.** Não cabe ao plugin (ver "Comportamento esperado"). Proposta de issue separada, a abrir pelo usuário: **"OpenCode: os primeiros comandos de shell de uma localização passam sem o hook de produção"**, para investigar: (a) se uma sessão com modelo chega a avaliar uma ferramenta na janela (precisa de uma VM com provedor); (b) uma regra estática de permissão que negue os padrões de produção fora do plugin: a tentativa desta spec, com o formato `"permissions": [{ "action": "shell", "resource": "*prod.exemplo.com*", "effect": "deny" }]` do `opencode.jsonc` do projeto, não negou nada na 2.3.0, nem depois de carregar, e o formato (ou a chave) precisa ser confirmado; (c) um aquecimento da localização antes da primeira etapa de agente (um `GET /api/command`), que encurta a janela para antes do modelo, se a hipótese de (a) se confirmar.
- A verificação com modelo (sessão real que dispara a ferramenta `shell`), que a #161 já deixou fora.
- O hook `session.context` (nota de sessão dos hooks do git).
- Mudanças em `opencode/server.ts`, `skills/`, `agents/`, `hooks/`, `githooks/`, `scripts/`, `templates/`, `docs/`, `.claude-plugin/` e na versão do plugin.
- Publicar o adaptador como pacote npm, ou instalar um `.opencode/plugins/` por projeto.
- Statusline e medição real de tokens no OpenCode.

## Desenho técnico
**Arquivos e módulos:**
- `opencode/test-adapter.sh`: a opção `--install`, o laço por modo, o isolamento da configuração global, as verificações novas e a limpeza.
- `opencode/README.md`: instalação, teste e limites.
- `opencode/PLANO-OPENCODE.md`: só a decisão 4 da §11 (as duas instalações valem), se a edição for pequena.
- `specs/SPEC-173.md`: esta spec.

**Dados:** nenhum.

**Interfaces:** o `opencode api` e a API HTTP do OpenCode 2.3.0 que o teste já usa (`GET /api/plugin`, `GET /api/command`, `GET /api/skill`, `GET /api/agent`, `POST /api/session`, `POST /api/session/<id>/permission`), com `location[directory]`. Nenhuma interface nova.

**Decisões:**
1. **O `server.ts` não muda** — o `setup` roda por localização e o diretório já é o da sessão; resolver o diretório a cada avaliação (a decisão da spec anterior) acrescentaria código num hook de segurança sem caso que o exija. Alternativa descartada: resolver o diretório pelo evento ou pela sessão a cada avaliação, com `ctx.location?.directory` como último recurso e log.
2. **A janela vira limite documentado, com a evidência, e não código** — o plugin não roda antes do próprio `setup`, então não há o que negar. Alternativa descartada: reordenar os hooks no `setup` ou "negar até estar pronto", que o teste da sonda mostrou não mudar nada.
3. **O teste roda os três modos por padrão (`todos`)** — a regressão mais provável é a instalação por projeto quebrar sem ninguém ver. Alternativa descartada: testar só a global.
4. **Isolar a configuração global do teste** — o teste não pode mexer na configuração global do usuário (SPEC-161); usa `XDG_CONFIG_HOME` e `XDG_DATA_HOME` só no ambiente do servidor e da API quando o OpenCode os respeita e, senão, cópia e restauração no `trap`. Se o OpenCode respeita as variáveis não foi medido aqui: o hook `protect-main` recusa uma linha de comando do Claude que cita `XDG_CONFIG_HOME`, e a investigação fica para dentro do `test-adapter.sh`, que as define. Alternativa descartada: escrever direto em `~/.config/opencode/opencode.jsonc`, que deixaria o plugin instalado na VM e quebraria o teste por projeto (ele falha com mais de um plugin `fabrica`).
5. **A prova de falha usa cópias alteradas da raiz** — como o `server.ts` correto já está certo na instalação global, a prova precisa de uma mutação para o teste ter o que acusar: uma sem os comandos e uma com o diretório errado. Alternativa descartada: provar a falha com o `server.ts` "de antes", que é o de hoje e não falha.

**Fontes da documentação:**
- OpenCode 2.3.0, API de plugins v2 — `https://opencode.ai/docs/build/plugins/server` pelo Context7 (`/websites/opencode_ai`, v2): o hook `evaluate` roda para `allow` e `ask`, e uma regra `deny` configurada é final. A janela e o carregamento por localização vêm da medição desta spec, não da doc. A forma das regras estáticas (`"permissions"` no `opencode.jsonc`) vem da doc e não se confirmou na 2.3.0.
- Bash e `jq` — sem versão a registrar; os mesmos do `test-adapter.sh` atual.
- gh 2.104.0 — nenhum comando novo no desenho; os usados são os da etapa.

**ADR:** nenhum.

## Testes
- Os CAs 1 a 9 são o próprio `opencode/test-adapter.sh`, rodado dentro da VM do `sbx` com o agente `opencode` (`sbx exec opencode-<projeto> bash opencode/test-adapter.sh --install <modo>`). O servidor grava em `~/.config/opencode` e `~/.local/share/opencode`, e o teste recusa rodar fora da VM, então não roda no host. A VM `opencode-fabrica` já existe, parada, e o `sbx exec` a inicia.
- O CA8 roda com cópias da raiz em pasta temporária, alteradas por `sed`, e `--root <cópia> --install global`.
- O CA12 roda os testes bash do plugin no host.

## Passos de produção
nenhum

## Riscos e dúvidas
- **A janela segue aberta.** Ela continua sendo um limite de segurança do adaptador, nas duas instalações, e esta issue não a fecha: ela a mede e a documenta. A issue separada proposta em "Fora de escopo" é quem pode fechá-la ou reduzi-la.
- **O OpenCode pode não respeitar o `XDG_*`.** O teste cai na cópia e restauração; o `trap` precisa cobrir `INT` e `TERM`, além do `EXIT`, para o `opencode.jsonc` global não ficar com a entrada se o teste for interrompido.
- **O teste exige a VM com o agente `opencode`.** O agente não cria a VM, mas ela já existe (`sbx ls`); sem ela, a verificação dos CAs 1 a 9 vira pedido ao usuário.
- **Modelo.** Sem provedor na VM, a janela numa sessão real não foi medida.
- **Fora do PRD.** Como nas #161 e #162, o OpenCode está fora do "só no Claude Code" do PRD. A issue existe por decisão do usuário (#149), e a spec não muda o PRD.

## Histórico
- 2026-11-17: criação.
- 2026-11-17: aprovada.
- 2026-11-18: mudança (alterar) — a implementação mediu que, com a entrada global, os comandos e o hook de produção já funcionam por projeto depois da janela de inicialização, que existe também na instalação por projeto e que o plugin não fecha; o usuário pediu a opção 1, com a checagem da janela nas duas instalações e um CA para fechá-la ou o registro do porquê. CAs: incluídos CA9 (estabilidade do teste); removidos o CA9 anterior (diretório da sessão no evento); alterados CA4 (1 plugin, 12 comandos, uma negação por comando), CA8 (prova de falha por duas cópias alteradas), CA10 (README com a janela medida) e CA11 (o `server.ts` não muda). A decisão 1 anterior (investigar na VM) foi feita; a decisão 2 (diretório a cada avaliação) caiu. O CA de fechar a janela não existe: não é possível pelo plugin, e a proposta de issue separada está em "Fora de escopo".
