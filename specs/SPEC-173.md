# SPEC-173: OpenCode: registrar comandos e hooks por projeto na instalação global

**Issue:** #173 · **PRD:** nenhuma (o OpenCode está fora do escopo do PRD, que fica "só no Claude Code"; mesma situação das #161 e #162, ver Riscos) · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-17

## Contexto
O adaptador `opencode/server.ts` (#167 a #172) leva ao OpenCode as 12 skills, os comandos `/fabrica:*`, o subagente `fabrica/revisor` e os hooks de proteção. O README da #161 manda instalá-lo por projeto, porque a descoberta da #161 (OpenCode 2.3.0) mostrou que, com o plugin só na entrada global (`~/.config/opencode/opencode.jsonc`):
- `GET /api/command` com `location[directory]=<projeto>` devolve 0 comandos `fabrica:*`, que ficam só na localização global;
- o `protect-production.sh` roda com o `cwd` global e não acha o `.fabrica/producao.txt` do projeto, então o hook de produção não protege.

No `server.ts`, os dois pontos vêm do mesmo lugar: o `setup(ctx)` guarda `ctx.location?.directory` em `cwd` (linha `const cwd`) e a passa a `evaluateShell` e ao guarda-corpo do `edit` em todo evento de permissão, e registra os comandos com `ctx.command.transform` numa localização só. Na instalação global, `cwd` é o diretório global.

## Objetivo
Com o plugin só na entrada global, os 12 comandos aparecem em cada projeto e o hook de produção lê o `.fabrica/producao.txt` do projeto da sessão.

## Comportamento esperado
**Comandos.** Com a pasta `opencode/` só em `"plugins"` de `~/.config/opencode/opencode.jsonc`, `GET /api/command` com `location[directory]=<projeto>` lista exatamente os 12 `fabrica:avancar`, `fabrica:backlog`, `fabrica:implementar`, `fabrica:licao`, `fabrica:metricas`, `fabrica:prd`, `fabrica:retro`, `fabrica:revisar`, `fabrica:setup`, `fabrica:spec`, `fabrica:status` e `fabrica:triagem`, sem duplicata.

**Hooks.** Com a mesma instalação, a avaliação de permissão de uma sessão num projeto usa o diretório da sessão, não o da instalação:
- `curl https://prod.exemplo.com` numa sessão do projeto A, cujo `.fabrica/producao.txt` tem `host prod.exemplo.com`, é negado;
- o mesmo comando numa sessão do projeto B, que não tem `.fabrica/producao.txt`, passa (`allow`), e nada do projeto A vaza para o B;
- o guarda-corpo do `edit` resolve caminhos relativos a partir do diretório da sessão.

**Instalação por projeto.** Continua funcionando como hoje, com as mesmas verificações. Com a entrada global e a do projeto ao mesmo tempo, os comandos não duplicam: continuam 12, e a avaliação de permissão não roda duas vezes por evento (um `deny` ou um `allow` por chamada).

**Sem sessão ou sem diretório no evento.** Se o evento de permissão não traz o diretório da sessão e ele não pode ser lido de outro modo, o hook cai no `ctx.location?.directory` de hoje e registra uma linha `[fabrica]` no log dizendo que usou o diretório da instalação. O comportamento da instalação por projeto, em que os dois diretórios são o mesmo, não muda.

**O teste de aceite.** O `opencode/test-adapter.sh` ganha a opção `--install projeto|global|ambos`, com `ambos` como padrão, e roda o conjunto de verificações uma vez por modo pedido, cada um com um servidor e um projeto temporário próprios. As verificações atuais valem em cada modo, com `projeto` como são hoje. No modo `global`, o `opencode.jsonc` do projeto temporário não tem a entrada do plugin, que vem do `opencode.jsonc` global. Acrescentam-se:

| Nome | O que confere | Esperado |
|---|---|---|
| `global: 12 comandos` | `GET /api/command` do projeto A, instalação só global | exatamente os 12 |
| `global: produção do projeto` | permissão `curl https://prod.exemplo.com` na sessão do projeto A | `deny` |
| `global: produção isolada` | o mesmo comando na sessão do projeto B, sem `.fabrica/producao.txt` | `allow` |
| `ambos: sem duplicata` | instalação global e por projeto juntas, `GET /api/command` do projeto A | exatamente os 12, e uma só negação no log por comando negado |
| `config global intacta` | o `opencode.jsonc` global antes e depois do teste | idêntico (ou ausente nos dois) |

A configuração global do teste é isolada de duas formas, na ordem: com `XDG_CONFIG_HOME` e `XDG_DATA_HOME` apontando para uma pasta temporária, se a versão do OpenCode instalada as respeitar; senão, com cópia do `opencode.jsonc` global existente e restauração dela pelo `trap`, no sucesso e na falha. Em nenhum caso o teste deixa a entrada do plugin na configuração global da VM.

**Prova de falha.** Com `--root` apontando para uma cópia da raiz em que o `server.ts` volta ao comportamento de hoje (diretório fixo no `setup`), `--install global` sai com 1 e marca `falha` em `global: 12 comandos` e em `global: produção do projeto`.

**O README.** A seção "Instalação" passa a oferecer as duas entradas (global e por projeto), com o que cada uma faz, e o primeiro item de "Limites conhecidos" sai ou muda para o que ainda for limite depois do conserto. A seção "Teste" explica o `--install` e a regra de a VM não ter o adaptador na configuração global quando se testa só `projeto`.

**Se o OpenCode 2.3.0 não permite.** Se a investigação do passo 1 do desenho técnico mostrar que a API de plugins não deixa um plugin global registrar comandos por projeto, a etapa não inventa um contorno que mexa fora de `opencode/`: ela para com `escalonado`, com a evidência (a chamada tentada e a resposta da API) e as opções (documentar o limite e manter a instalação por projeto, ou instalar um carregador por projeto), e a spec volta ao usuário. O CA2 e o CA3 (hook de produção) valem mesmo assim, porque dependem só do diretório da sessão.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com o plugin só na entrada global, `GET /api/command` com `location[directory]=<projeto>` lista os 12 comandos `fabrica:*`, sem duplicata. | manual — `bash opencode/test-adapter.sh --install global` na VM do `sbx` com o agente `opencode`: `ok global: 12 comandos` |
| CA2 | Com a entrada global, a avaliação de `curl https://prod.exemplo.com` numa sessão do projeto com `.fabrica/producao.txt` (`host prod.exemplo.com`) devolve `deny`. | manual — o mesmo teste: `ok global: produção do projeto` |
| CA3 | Com a entrada global, o mesmo comando numa sessão de outro projeto sem `.fabrica/producao.txt` devolve `allow`: o arquivo lido é o do projeto da sessão, não o do `cwd` global. | manual — o mesmo teste: `ok global: produção isolada` |
| CA4 | Com a entrada global e a do projeto ao mesmo tempo, os comandos são 12 e cada comando negado aparece uma vez no log. | manual — `--install ambos` na VM: `ok ambos: sem duplicata` |
| CA5 | A instalação só por projeto passa em todas as verificações que já existiam. | manual — `--install projeto` na VM: todas `ok`, saída 0 |
| CA6 | `--install` sem argumento válido ou com valor desconhecido sai com 1 e mostra o uso; sem a opção, roda `ambos`. | manual — duas execuções na VM |
| CA7 | O teste não deixa o plugin na configuração global da VM: depois de qualquer execução, no sucesso ou na falha, o `opencode.jsonc` global é idêntico ao de antes. | manual — `sha256sum` antes e depois; `ok config global intacta` |
| CA8 | Com `--root` apontando para uma cópia com o `server.ts` fixando o diretório no `setup` (comportamento de hoje), `--install global` sai com 1 e marca `falha` em `global: 12 comandos` e em `global: produção do projeto`. | manual — na VM, com a cópia numa pasta temporária |
| CA9 | Quando o evento de permissão não traz o diretório da sessão, o hook usa o diretório da instalação e escreve a linha `[fabrica]` correspondente no log, e a instalação por projeto não muda de comportamento. | unitário — função que escolhe o diretório, exercitada com `bun`/`node` na VM, ou, se não houver como chamar o hook sem a API, manual — leitura do trecho |
| CA10 | O `opencode/README.md` documenta as duas instalações e o `--install`, e o limite da entrada global não afirma mais o que o teste desmente. | manual — leitura |
| CA11 | `git diff --name-only origin/main...HEAD` mostra só `opencode/server.ts`, `opencode/test-adapter.sh`, `opencode/README.md`, `opencode/PLANO-OPENCODE.md` (se mudar) e `specs/SPEC-173.md`; o plugin do Claude Code (`.claude-plugin/`, `skills/`, `agents/`, `hooks/`, `scripts/`) não muda. | manual — o comando, na branch |
| CA12 | Os testes bash atuais passam: todo `scripts/test-*.sh` da `main`, menos o `test-sandbox-acceptance.sh`. | manual — rodar cada script |

## Fora de escopo
- A verificação com modelo (sessão real que dispara a ferramenta `shell`), que a #161 já deixou fora.
- O hook `session.context` (nota de sessão dos hooks do git), que não depende do diretório.
- Mudanças em `skills/`, `agents/`, `hooks/`, `githooks/`, `scripts/`, `templates/`, `docs/`, `.claude-plugin/` e na versão do plugin.
- Publicar o adaptador como pacote npm, ou instalar um `.opencode/plugins/` por projeto.
- Statusline e medição real de tokens no OpenCode.

## Desenho técnico
**Arquivos e módulos:**
- `opencode/server.ts`: o `setup(ctx)` e os hooks de permissão e de `tool.execute.before`.
- `opencode/test-adapter.sh`: a opção `--install` e as verificações novas.
- `opencode/README.md`: instalação, teste e limites.
- `opencode/PLANO-OPENCODE.md`: só a decisão 4 da §11 e a §6, se a instalação global passar a valer (o arquivo é do repositório).
- `specs/SPEC-173.md`: esta spec.

**Dados:** nenhum.

**Interfaces:** o `opencode api` e a API HTTP do OpenCode 2.3.0 que o teste já usa (`GET /api/plugin`, `GET /api/command`, `GET /api/skill`, `GET /api/agent`, `POST /api/session`, `POST /api/session/<id>/permission`), com `location[directory]`. Nenhuma interface nova no plugin.

**Decisões:**
1. **Investigar antes de mudar o código** — a API de plugins v2 não está documentada neste repositório para esse caso, e o `server.ts` só conhece `ctx.location.directory`. O primeiro passo da implementação, numa VM com o `opencode`, descobre: (a) como um plugin carregado na localização global registra comandos que valem nos projetos (por exemplo, se o `setup` roda uma vez por localização, ou se `ctx.command.transform` aceita um alvo de localização); (b) de onde o evento `permission.evaluate` tira o diretório da sessão (campo do evento, `ctx.session.get`, ou a sessão pelo `source.id`). Registra a chamada e a resposta no PR. Alternativa descartada: escolher o mecanismo por suposição e testá-lo só no fim.
2. **O diretório vem do evento ou da sessão, nunca de uma variável do `setup`** — o `cwd` passa a ser resolvido a cada avaliação, pelo mecanismo achado em (b), com o `ctx.location?.directory` como último recurso e log, como no comportamento esperado. Alternativa descartada: manter o `cwd` do `setup`, que é a causa do defeito.
3. **O teste roda os dois modos por padrão** — a regressão mais provável é a instalação por projeto quebrar enquanto se conserta a global, então `ambos` é o padrão. Alternativa descartada: um teste só da instalação global, que deixaria a por projeto sem rede.
4. **Isolar a configuração global do teste** — o teste não pode mexer na configuração global do usuário (SPEC-161), então usa `XDG_CONFIG_HOME`/`XDG_DATA_HOME` quando o OpenCode os respeita e, senão, cópia e restauração no `trap`. Alternativa descartada: escrever direto em `~/.config/opencode/opencode.jsonc`, que deixaria o plugin instalado na VM e quebraria o teste por projeto (ele falha com mais de um plugin `fabrica`).

**Fontes da documentação:**
- OpenCode 2.3.0, API de plugins v2 — não verificada para o registro por localização: o comportamento atual vem da descoberta da #161 (issue #173) e da #149. A investigação do passo 1 é a verificação. A documentação da v2 está em `opencode.ai/docs/build/plugins/server/` (citada na #149).
- Bash e `jq` — sem versão a registrar; os mesmos do `test-adapter.sh` atual.

**ADR:** nenhum.

## Testes
- Os CAs 1 a 8 são o próprio `opencode/test-adapter.sh`, rodado dentro da VM do `sbx` com o agente `opencode` (`sbx exec opencode-<projeto> bash opencode/test-adapter.sh --install <modo>`). O servidor grava em `~/.config/opencode` e `~/.local/share/opencode`, e o teste recusa rodar fora da VM, então não roda no host.
- O CA9 é um teste da função que escolhe o diretório, separada do `setup` para poder ser chamada sozinha, ou a leitura do trecho se não for possível.
- O CA12 roda os testes bash do plugin no host.

## Passos de produção
nenhum

## Riscos e dúvidas
- **A API pode não permitir o registro por projeto (CA1).** É o risco principal: a spec trata o caso, com `escalonado` e opções, em vez de inventar um contorno.
- **O evento de permissão pode não trazer o diretório.** Há a leitura pela sessão e, no pior caso, o diretório da instalação com log. O CA2 e o CA3 só passam se o diretório da sessão for achado.
- **O teste exige a VM com o agente `opencode`.** O agente não cria a VM: sem ela, a verificação dos CAs 1 a 8 vira pedido ao usuário (verificação pendente), como na #161.
- **Janela de inicialização.** O teste já espera a sonda de negação (#159); o modo `global` herda a espera.
- **Fora do PRD.** Como nas #161 e #162, o OpenCode está fora do "só no Claude Code" do PRD. A issue existe por decisão do usuário (#149), e a spec não muda o PRD.

## Histórico
- 2026-11-17: criação.
