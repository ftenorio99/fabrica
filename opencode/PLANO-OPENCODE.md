# Plano: adaptar o fabrica ao OpenCode sem tocar no Claude Code

Status: proposta, nada implementado. As APIs de plugin em que o plano se apoia
foram verificadas em 2026-11-16 com o OpenCode 2.3.0 (estudo da issue #149), e
a fase 0, com modelo real, rodou em 2026-11-17; o que foi confirmado e o que
falta está na §0.
Escopo: levar as 12 etapas, o subagente revisor e as proteções da fábrica ao
OpenCode, com **zero mudança** no que existe para o Claude Code.

---

## 0. O que já foi verificado

O estudo carregou um plugin mínimo numa VM do `sbx`, com um servidor local
(`opencode serve`) e sem modelo, e exercitou o plugin pela API do servidor.
Depois, a fase 0 repetiu os pontos que dependiam de modelo com
`opencode run` e o modelo gratuito `opencode/deepseek-v4.1-flash-free` (os
pagos do gateway recusaram por falta de crédito). O registro completo está na
issue #149.

| Ponto | Situação | Como foi visto |
|---|---|---|
| `export default Plugin.define({ id, setup(ctx) })`, de `@opencode/plugin` | confirmado | plugin carregado; o import resolve sem `package.json` |
| Arquivo `.ts` solto em `.opencode/plugins/` do projeto carrega sozinho | confirmado | `GET /api/plugin`: `source.type: "local"`, `status: "active"` |
| Pasta local listada em `"plugins"` do `opencode.jsonc`, com `server.ts` na raiz | só na documentação | página de configuração de plugins |
| `ctx.command.transform` e nome de comando com `:` | confirmado na API | `GET /api/command` lista o comando; `POST /api/session/<id>/command` executa |
| Argumentos do comando em `prompt.text` | confirmado | o `execute` recebe `{sessionID, prompt, delivery}` |
| `ctx.session.prompt` a partir do comando | confirmado | disparou o hook `context` da sessão |
| `ctx.skill.transform`, com `autoinvoke: false` | confirmado | `GET /api/skill` |
| `ctx.permission.hook("evaluate")` nega com `event.effect = "deny"` | confirmado na API | `POST /api/session/<id>/permission` devolveu `deny` |
| `ctx.session.hook("context")`, com `event.system` e `event.tools` | confirmado | hook disparou |
| O evento `context` traz `sessionID` e `system` como lista de `{type, text}` | confirmado | plugin de sonda numa sessão real do `opencode run` (#160) |
| Ferramentas `shell`, `question` e `subagent` no agente padrão | confirmado | lista de `event.tools` |
| A ferramenta `shell` pede permissão com `action: "shell"` | confirmado | sessão com modelo |
| O `deny` do hook barra a ferramenta `shell` numa sessão real | confirmado | a ferramenta termina em erro com `event.message`, e o modelo a repete; nenhum commit foi criado |
| O `--auto` não passa por cima do `deny` do hook | confirmado | mesmo resultado com `opencode run --auto` |
| Ordem numa chamada de `shell`: `tool.execute.before` → `shell.create.before` → `permission.evaluate` | confirmado | log do plugin; o comando só roda depois da permissão |
| `resources` traz cada comando separado, não a linha inteira | confirmado | ver §4.5 |
| A skill com `autoinvoke: false` chega ao modelo pela ferramenta `skill` | confirmado | o modelo carregou a skill pelo nome e seguiu a instrução |
| `opencode run "/fabrica:<etapa>"` executa o comando | **não** | o `run` trata o texto como mensagem comum; comando só pelo TUI ou pela API |
| O OpenCode 2.3.0 não carrega o `CLAUDE.md` sozinho | confirmado | projeto só com `CLAUDE.md`: o modelo não soube a regra (#160) |
| O OpenCode 2.3.0 carrega o `AGENTS.md` sem configuração | confirmado | projeto só com `AGENTS.md`: o modelo respondeu a regra (#160) |
| `"instructions": ["CLAUDE.md"]` resolve a partir do projeto | confirmado só no `opencode.jsonc` do projeto | no config apontado por `OPENCODE_CONFIG`, o `CLAUDE.md` do projeto não chegou; a config global real (`~/.config/opencode`) não foi testada (#160) |

Ainda sem verificação:

1. se `/fabrica:<etapa>` digitado no TUI é aceito, já que a API aceita (pede
   sessão interativa);
2. se o preâmbulo de harness (§4.3), enviado pelo comando, muda o
   comportamento do modelo como esperado; depende do item 1 ou da API;
3. se a nota de sessão dos hooks do git (#160) chega ao modelo: a forma do
   evento foi conferida, mas a nota em si não foi vista numa sessão, porque a
   máquina de teste tem os hooks instalados.

A documentação da v2 fica em `https://opencode.ai/docs/build/plugins/server/`.
A página `https://opencode.ai/docs/plugins` indexada por buscadores e pelo
Context7 descreve a v1 (`"tool.execute.before"`), que a v2 não traduz.

---

## 1. Contrato de compatibilidade

O Claude Code hoje carrega a fábrica por `.claude-plugin/plugin.json` e pelas
convenções `skills/`, `agents/`, `hooks/hooks.json`, `githooks/` e `scripts/`.
Todo o plano é **aditivo**: nada existente é editado, movido, renomeado ou
removido.

Invariantes:

1. Nenhum arquivo em `skills/`, `agents/`, `hooks/`, `githooks/`, `scripts/`,
   `templates/`, `docs/` ou `.claude-plugin/` é modificado.
2. `.claude-plugin/plugin.json` continua com a mesma `version`; o adaptador não
   a altera nem depende dela para funcionar.
3. Nenhum arquivo em `~/.claude/` e nenhuma entrada de `~/.gitconfig` é criada
   ou alterada pela instalação do adaptador.
4. O plugin do Claude Code continua instalável pelo marketplace e pelo
   `claude --plugin-dir`, com as mesmas skills, o mesmo agente, os mesmos hooks
   e a mesma statusline.
5. A única mudança dentro do repositório é a pasta `opencode/`.
6. Todo o estado do adaptador fora do repositório fica em
   `~/.config/opencode/`, que o Claude Code não lê.

O adaptador lê os arquivos existentes em tempo de execução; ele não os copia
para dentro de si.

---

## 2. Superfície da mudança

| Artefato | Tipo | Onde fica | O Claude Code vê? |
|---|---|---|---|
| `opencode/server.ts` | novo | repositório | não |
| `opencode/test-adapter.sh` | novo | repositório | não |
| `opencode/README.md` | novo | repositório | não |
| `opencode/PLANO-OPENCODE.md` | este | repositório | não |
| entrada da pasta `opencode/` em `"plugins"` | nova entrada | `~/.config/opencode/opencode.jsonc` | não |
| agente `fabrica/revisor` | registrado pelo plugin ou gerado (ver §4.4) | memória do servidor ou `~/.config/opencode/` | não |
| `instructions: ["CLAUDE.md"]` (opcional) | nova entrada | `~/.config/opencode/opencode.jsonc` | não |

Nenhuma linha existente é alterada. Nenhum arquivo é apagado.

A pasta `opencode/` acompanha o plugin quando o Claude Code o instala e quando
o `agy plugin install` o converte para o Antigravity. Nos dois casos ela é só
copiada, sem efeito.

---

## 3. Por que o Claude Code não é afetado

- O Claude Code só descobre `skills/`, `agents/`, `hooks/hooks.json`,
  `commands/` e `.claude-plugin/`. Uma pasta `opencode/` na raiz do plugin é
  inerte.
- Não haverá `package.json` na raiz do repositório nem dentro de `opencode/`:
  o import de `@opencode/plugin` resolve sem ele.
- A instalação grava apenas em `~/.config/opencode/`. Ela não executa
  `setup-statusline.sh`, não edita `~/.claude/settings.json` e não altera o
  `core.hooksPath`.
- Os hooks do OpenCode chamam os scripts atuais em modo leitura. Os scripts, os
  testes e o comportamento no Claude Code permanecem idênticos.

Provas no fim da implementação:

```bash
git status --porcelain           # só arquivos novos em opencode/
git diff --name-only main        # só caminhos em opencode/
```

---

## 4. Arquitetura do adaptador

O OpenCode não lê `plugin.json` nem `hooks.json`. O adaptador é um plugin de
servidor em TypeScript, no formato confirmado na §0:

```ts
import { Plugin, Skill } from "@opencode/plugin"

export default Plugin.define({
  id: "fabrica",
  async setup(ctx) { /* ... */ },
})
```

No `setup`, ele:

1. localiza a raiz da fábrica (`ctx.options.root` ou `../` a partir de
   `opencode/server.ts`);
2. lê `skills/*/SKILL.md` e registra as 12 skills em `ctx.skill.transform`;
3. registra os 12 comandos em `ctx.command.transform`;
4. registra os hooks de permissão em `ctx.permission.hook("evaluate")`;
5. registra a nota de sessão em `ctx.session.hook("context")`.

O adaptador não mantém regras próprias: corpo de skill, mensagens de bloqueio e
listas de padrões continuam vindo dos arquivos existentes.

### 4.1 Skills

- ID: `fabrica-<pasta>` (ex.: `fabrica-triagem`), criado com
  `Skill.ID.make(...)`, para não colidir com skills genéricas do usuário.
- `name`: o `name` do frontmatter, com `Skill.Name.make(...)`.
- `description`: o `description` do frontmatter.
- `autoinvoke`: `false` quando `disable-model-invocation: true`.
- `path`: o `SKILL.md` real, para o OpenCode resolver os arquivos de apoio.
- `content`: o corpo sem frontmatter.

Alternativa mais simples, a avaliar na fase 1: a configuração do OpenCode tem a
chave `skills` ("caminhos adicionais para descobrir skills"), e o leitor nativo
de skills já entende `disable-model-invocation`. Apontar essa chave para
`<raiz>/skills` dispensaria o registro por plugin, mas o ID das skills deixaria
de ter o prefixo `fabrica-`. Vale só se o prefixo não fizer falta.

### 4.2 Comandos e argumentos

Skills do OpenCode não recebem argumentos; comandos recebem. Para cada skill, o
adaptador registra um comando:

| Comando | Equivalente no Claude Code |
|---|---|
| `/fabrica:setup` | `/fabrica:setup` |
| `/fabrica:avancar` | `/fabrica:avancar` |
| … | … |

A execução do comando:

1. recebe `{sessionID, prompt, delivery}`, com os argumentos digitados em
   `prompt.text`;
2. monta `texto = preâmbulo + corpo` com `$ARGUMENTS` substituído;
3. envia com `ctx.session.prompt({ ...prompt, sessionID, text, delivery })`, na
   mesma sessão.

O corpo vem do `SKILL.md` a cada reload. Mudou a skill, mudou o comando; não há
cópia para sincronizar.

A API do servidor aceita `:` no nome do comando, no registro e na execução.
Falta conferir o TUI: se ele rejeitar o nome digitado, o plano B é registrar
`/fabrica/setup` etc. A decisão é tomada no primeiro teste com o TUI (ver §8).

O `opencode run "/fabrica:status"` **não** executa o comando: o texto vai ao
modelo como mensagem comum (fase 0). Uso não interativo de uma etapa, como no
dispatcher da Fase 1, precisa ir pela API do servidor
(`POST /api/session/<id>/command`).

### 4.3 Preâmbulo de harness

Para não editar as skills, o adaptador injeta um preâmbulo curto, igual para
todas as etapas:

```text
<!-- fabrica:opencode -->
Esta etapa da fábrica roda no OpenCode. O diretório base desta skill é
<raiz>/skills/<etapa>: resolva "<diretório base desta skill>" e os caminhos
relativos a partir dele. Adaptações desta harness, sem mudar as regras:
- "AskUserQuestion" é a ferramenta `question`.
- "fabrica:revisor" é o subagente `fabrica/revisor`, chamado pela ferramenta
  `subagent`; se ele não estiver disponível, use o fallback que a própria
  skill descreve.
- Statusline, `~/.claude/settings.json` e `setup-statusline.sh` são do Claude
  Code: não execute esses passos, avise que não se aplicam ao OpenCode e siga.
O restante vale sem alteração.
```

As ferramentas `question` e `subagent` existem no agente padrão (§0). Esse é o
único ponto que traduz nomes de ferramentas. Nenhuma regra de negócio da
fábrica é duplicada.

### 4.4 Agente revisor

O corpo do agente continua num só lugar: o `agents/revisor.md` atual. O que o
OpenCode recebe é só a definição (modo, permissões) e um ponteiro para esse
arquivo. O ID fica `fabrica/revisor`, próximo de `fabrica:revisor`.

Há dois caminhos, e a fase 2 começa testando o primeiro:

1. **Pelo plugin.** O `ctx.agent.transform` existe e o editor tem `update`,
   `remove`, `get`, `list` e `default`. No código do OpenCode, o `update` de um
   ID que ainda não existe é o que cria os agentes declarados na configuração.
   Se o mesmo valer para um plugin externo, o adaptador registra o agente em
   memória e nenhum arquivo é gerado.
2. **Por arquivo.** Se o plugin não puder criar o agente, a instalação gera a
   definição a partir de um template, com a raiz absoluta. O local e o formato
   do arquivo de agente da v2 precisam ser conferidos na documentação antes.

Permissões pretendidas, nos dois caminhos:

```yaml
mode: subagent
permissions:
  - { action: edit, resource: "*", effect: deny }
  - { action: shell, resource: "make *", effect: allow }
  - { action: shell, resource: "git *", effect: allow }
  - { action: shell, resource: "gh *", effect: allow }
  - { action: shell, resource: "*", effect: deny }
```

O formato `{action, resource, effect}` é o que os agentes internos do OpenCode
usam. A ordem de avaliação (a última regra que casa vence, pelo que o código
indica) precisa ser confirmada antes de fixar a lista.

### 4.5 Hooks de proteção

`ctx.permission.hook("evaluate")` recebe `{sessionID, agent, action, resources,
source, effect, message}`. O adaptador intercepta `action: "shell"` e `"edit"`.

**Shell — proteção da main e de produção:** o adaptador chama os scripts
existentes com o mesmo JSON que o Claude Code envia:

```ts
spawnSync("bash", [script], {
  input: JSON.stringify({ tool_input: { command }, cwd }),
  encoding: "utf8",
});
```

- `hooks/protect-main.sh`
- `hooks/protect-production.sh`

Se a saída tiver `permissionDecision: "deny"`, o hook define
`event.effect = "deny"` e copia `permissionDecisionReason` para
`event.message`. As mensagens ao usuário ficam iguais.

Assim, a lógica e os testes (`test-protect-main.sh`,
`test-protect-production.sh`) continuam valendo para os dois harnesses, e não
há duas implementações da mesma regra. Desde a 0.35.1 (#150), os dois scripts
também aceitam o contrato do Antigravity; o adaptador do OpenCode usa o do
Claude Code e não cria um terceiro.

**De onde vem a linha de comando.** As checagens do `protect-main.sh` são de
texto sobre a linha inteira (prefixo de variável como `HOME=...`, a flag
`--no-verify`, `core.hooksPath`). A fase 0 mostrou que `resources` não traz
essa linha. Para `HOME=/tmp git status --short && echo fim | cat`:

| Hook | O que chega |
|---|---|
| `tool.execute.before` | `event.input.command` com a linha inteira; `event.id` é o id da chamada |
| `permission.evaluate` | `resources: ["HOME=/tmp git status --short", "echo fim", "cat"]`; `source.id` é o mesmo id |

O prefixo fica no comando a que pertence, mas o encadeamento se perde. Por
isso o adaptador faz uma ponte pelo id da chamada:

1. em `ctx.tool.hook("execute.before")`, com `event.tool === "shell"`, guarda
   `event.input.command` num `Map` indexado por `event.id`;
2. em `permission.evaluate`, com `action: "shell"`, busca a linha por
   `source.id`, passa-a aos scripts e apaga a entrada do `Map`;
3. se a linha não estiver no `Map`, usa `resources.join(" && ")`, para nunca
   avaliar menos do que chegou.

A negativa continua no hook de permissão, que é o que barra de verdade (a
documentação não diz como barrar pelo `execute.before`). O `test-adapter.sh`
cobre a ponte com uma linha encadeada.

**Limites conhecidos**

- O comando de shell digitado pelo próprio usuário não passa pelo hook de
  permissão (só pelo `shell.hook("create.before")`). É o mesmo modelo do
  Claude Code, em que o hook protege contra o agente, não contra o usuário.
- Uma regra `deny` configurada pelo usuário é final e não chama o hook. O hook
  roda nas decisões `allow` e `ask`.

**Guarda-corpo do Claude Code (recomendado):** o adaptador também nega, no
OpenCode, comandos que escrevem em `~/.claude/` ou rodam
`setup-statusline.sh`. Isso garante o contrato da §1 mesmo quando o modelo
decide "seguir" um passo que o preâmbulo mandou pular. Desligável por opção
(`protectClaudeConfig: false`, lida de `ctx.options`).

**Nota de sessão:** no primeiro `context` hook de cada sessão, o adaptador lê
`git config --global --get core.hooksPath` e, se não apontar para
`~/.config/fabrica/githooks`, acrescenta uma nota de sistema com
`event.system.push({ type: "text", text })`:
"Os hooks do git da fábrica não estão instalados nesta máquina. Rode
/fabrica:setup." É o equivalente ao `SessionStart` do Claude, sem statusline.

### 4.6 `CLAUDE.md` dos projetos

O OpenCode 2.3.0 carrega o `AGENTS.md` e não carrega o `CLAUDE.md` sozinho; o
Claude Code faz o contrário. As skills da fábrica mandam ler e seguir o
`CLAUDE.md` do projeto.

Duas saídas, que não se excluem:

- **`instructions` na configuração do OpenCode** (opt-in): acrescentar
  `"instructions": ["CLAUDE.md"]` na config global. A chave existe na v2
  ("caminhos ou URLs adicionais de instruções"). Falta confirmar que o caminho
  relativo é resolvido a partir de cada projeto. Nada muda nos templates nem
  no Claude.
- **`AGENTS.md` como fonte das regras**, com o `CLAUDE.md` apontando para ele.
  Vale para o OpenCode e para o Antigravity, mas muda os templates da fábrica
  e os projetos existentes. É uma decisão separada deste plano (ver §11).

**Conferido na #160 (OpenCode 2.3.0):**

- **Projeto com `AGENTS.md`:** as regras chegam ao modelo sem configuração
  extra. É o caso dos projetos migrados pela #156.
- **Opt-in para projeto só com `CLAUDE.md`:** um `opencode.jsonc` **na raiz do
  projeto** com `{ "instructions": ["CLAUDE.md"] }` faz o modelo receber as
  regras; o caminho relativo resolve a partir do projeto. O mesmo `instructions`
  num config apontado por `OPENCODE_CONFIG` **não** entregou o `CLAUDE.md` do
  projeto, então não dá para contar com o caminho relativo num config fora do
  projeto. A config global em `~/.config/opencode` não foi testada. Enquanto
  isso, o opt-in vale por projeto, e a saída duradoura é migrar o projeto para
  o `AGENTS.md`.

Sem nenhuma das duas, o agente ainda lê o `CLAUDE.md` pela ferramenta de
leitura quando a skill manda, mas perde o carregamento automático. Atenção ao
kairo, que já tem um `AGENTS.md` só com regras do Next.

### 4.7 Linha de custo, statusline e isolamento

- `scripts/stage-usage.py` continua sendo chamado igual. No OpenCode não há
  `~/.claude/projects/...jsonl`, então a linha sai com `tokens=nao-medido`.
  O script nunca falha. Portar a medição para a API de uso do OpenCode fica
  para uma fase posterior, sem tocar no script atual.
- A statusline não tem equivalente no servidor do OpenCode. Não será portada
  nesta fase; fica documentado em `opencode/README.md`.
- O `sbx create` aceita `opencode` como agente, então o modo `sbx` da fábrica
  pode valer também aqui. O checklist do `/fabrica:setup` hoje é escrito para
  o `claude`; adaptá-lo fica fora desta fase, e o preâmbulo não manda mais
  pular o isolamento.

---

## 5. Arquivos novos

### `opencode/server.ts`

Plugin de servidor. Responsabilidades:

- carregar e validar a raiz;
- ler frontmatter (subconjunto YAML: `name`, `description`,
  `disable-model-invocation`, `argument-hint`);
- registrar skills e comandos;
- registrar o agente revisor, se o caminho 1 da §4.4 funcionar;
- ponte para os dois hooks;
- guarda-corpo da config do Claude;
- nota de sessão.

Regras de robustez: qualquer erro em uma skill é logado e ignorado; o plugin
nunca impede o OpenCode de iniciar. Sem rede, sem escrita em disco.

O nome `server.ts` é o que o OpenCode procura na raiz de uma pasta de plugin
local sem `package.json`.

### `opencode/test-adapter.sh`

Teste de aceite sem modelo, para rodar dentro da VM do `sbx` (o servidor grava
em `~/.config/opencode` e `~/.local/share/opencode`). Sobe `opencode serve`
numa porta local, lê a senha do log e confere pela API os itens automáticos da
§8. É o mesmo método do estudo da #149.

### `opencode/README.md`

O que funciona, o que é adaptado, o que não existe (statusline, custo real) e
como instalar, atualizar e desinstalar.

---

## 6. Instalação e rollback

Não há instalador próprio. A instalação é uma entrada na configuração global
do OpenCode, apontando para a pasta do adaptador:

```jsonc
// ~/.config/opencode/opencode.jsonc
{
  "plugins": ["/home/<usuário>/projetos/fabrica/opencode"]
}
```

Caminhos locais em `"plugins"` precisam ser pastas; um arquivo solto é
ignorado. Esse formato veio da documentação e é o primeiro item a confirmar na
fase 1. Se o agente revisor precisar de arquivo (caminho 2 da §4.4), um script
pequeno gera esse arquivo; fora isso, nada é gerado.

O servidor observa os arquivos de plugin, o que indica recarga automática, mas
isso não foi testado. Na dúvida, `opencode reload` ou
`opencode service restart`.

Rollback:

1. remover a entrada da pasta de `"plugins"` em
   `~/.config/opencode/opencode.jsonc`;
2. remover o arquivo do agente, se ele tiver sido gerado;
3. opcionalmente apagar `opencode/` do repositório.

Nada em `~/.claude/` é tocado em nenhum dos dois sentidos.

---

## 7. Fases

| Fase | Entrega | Impacto no Claude |
|---|---|---|
| 0 | Teste com modelo dos pontos em aberto da §0 (**feita em 2026-11-17**, falta o TUI) | nenhum |
| 1 | `server.ts`: skills + comandos `/fabrica:*`, carregado pela entrada em `"plugins"` | nenhum |
| 2 | Agente `fabrica/revisor` | nenhum |
| 3 | Hooks de permissão (main, produção, guarda-corpo) | nenhum |
| 4 | Nota de sessão e leitura do `CLAUDE.md` (opt-in) | nenhum |
| 5 | `test-adapter.sh` e README do adaptador | nenhum |

A fase 0 vinha antes porque o conteúdo de `resources` decidia o desenho da
fase 3; o resultado é a ponte da §4.5. O nome `/fabrica:<etapa>` no TUI fica
para o primeiro teste manual da fase 1.

Cada fase termina com o checkpoint: `git diff --name-only main` só com
caminhos em `opencode/`, e os testes bash atuais passando.

---

## 8. Testes e critérios de aceite

**Regressão do Claude Code**

- `git diff --name-only main` só mostra caminhos em `opencode/`.
- `bash scripts/test-protect-main.sh` e
  `bash scripts/test-protect-production.sh` passam.
- `claude --plugin-dir ~/projetos/fabrica` carrega as 12 skills, o agente e os
  hooks como hoje.

**OpenCode, sem modelo (`opencode/test-adapter.sh`)**

- `GET /api/plugin` lista `fabrica` com `status: "active"`.
- `GET /api/command` lista os 12 comandos; `GET /api/skill`, as 12 skills, com
  `autoinvoke: false` nas que têm `disable-model-invocation`.
- `GET /api/agent` lista `fabrica/revisor`.
- `POST /api/session/<id>/permission` com `action: "shell"`:
  - um commit com `--no-verify` volta `deny`;
  - um comando que cita um padrão de `.fabrica/producao.txt` volta `deny`;
  - uma escrita em `~/.claude/` volta `deny` (guarda-corpo);
  - `git status` volta `allow`;
  - com a linha encadeada guardada pelo `execute.before`, a negativa vale
    mesmo quando o comando proibido não é o primeiro da linha.
- Nenhum erro do plugin em `~/.local/share/opencode/log/opencode.log`.

**OpenCode, com modelo (manual, pelo TUI; o `opencode run` não executa comandos)**

- `/fabrica:status` digitado no TUI roda sem erro.
- O agente tenta um commit com `--no-verify` e recebe a mensagem atual de
  bloqueio.
- A etapa de revisão chama o subagente `fabrica/revisor`.

---

## 9. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Nome com `:` não funcionar no TUI | A API aceita; teste no TUI no primeiro uso manual da fase 1; fallback `/fabrica/...` |
| `resources` não trazer a linha inteira | Confirmado na fase 0; ponte pelo id da chamada a partir do `tool.hook("execute.before")` (§4.5) |
| API de plugins V2 mudar | Adaptador pequeno e isolado; `test-adapter.sh` acusa a quebra |
| Plugin externo não poder criar agente | Caminho 2 da §4.4, por arquivo |
| Skill nova quebrar o parser de frontmatter | Parser tolerante; erro logado e skill ignorada |
| Duplicação de regra | Nenhuma: corpo e mensagens vêm dos arquivos atuais |
| `instructions: ["CLAUDE.md"]` afetar projetos | Opt-in, só na config do OpenCode |
| Modelo ignorar o preâmbulo e mexer no Claude | Guarda-corpo nega shell/edit em `~/.claude` |
| `opencode --auto` aprovar o que o hook deveria negar | Descartado na fase 0: o `deny` do hook vale também com `--auto` |
| `jq` ausente | Ponte falha aberta (não nega), como os scripts atuais |

---

## 10. Fora de escopo nesta fase

- Statusline da fábrica no OpenCode (exigiria plugin de TUI).
- Medição real de tokens (`stage-usage.py` no OpenCode).
- Checklist do modo `sbx` para o agente `opencode`.
- Publicação do adaptador como pacote npm (`opencode plugin add`).
- Qualquer alteração em skills, agente, hooks, scripts ou docs existentes.

---

## 11. Decisões que dependem de você

1. **Nome do comando:** manter `/fabrica:<etapa>`, que a API aceita, sujeito
   ao teste no TUI, ou já usar `/fabrica/<etapa>`?
2. **Regras do projeto:** ativar `instructions: ["CLAUDE.md"]` na config
   global do OpenCode, adotar o `AGENTS.md` como fonte das regras (decisão D3
   do mnemo, que também serve ao Antigravity), ou os dois?
3. **Guarda-corpo:** negar no OpenCode qualquer escrita em `~/.claude` e os
   passos de statusline? (recomendado, garante o contrato da §1)
4. **Config global ou por projeto:** o adaptador entra em
   `~/.config/opencode` (vale para todos) ou só nos projetos da fábrica, pela
   pasta `.opencode/plugins/` de cada um? **Resolvido na #173:** as duas
   entradas valem, e o `opencode/test-adapter.sh --install
   projeto|global|ambos|todos` cobre as três combinações; a global já lê o
   `.fabrica/producao.txt` de cada projeto depois da janela de inicialização,
   que vale nas duas. A pasta `.opencode/plugins/` não foi adotada.
5. **README do repositório:** deixar a menção ao OpenCode só em
   `opencode/README.md` (zero edições) ou acrescentar uma seção no `README.md`
   em um PR separado?
