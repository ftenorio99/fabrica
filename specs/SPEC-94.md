# SPEC-94: Etapas de agente só usam credenciais de dev ou homologação, nunca de produção

**Issue:** #94 · **PRD:** F2 (item 2 do fatiamento, M1) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** aprovada · **Atualizada em:** 2026-11-10

## Contexto
A F2 do PRD pede que as etapas de agente nunca alcancem o banco nem os serviços de produção, e que o que é de produção vire passo de um runbook executado pelo usuário. Junto com a F1 (#93, ADR 0005), isso precisa valer antes do dispatcher (restrição "F1 e F2 vêm antes do F4"). Hoje nada impede um comando Bash de citar a URL do banco de produção. Além disso, o sandbox da #93 nega a leitura de todos os `.env*`, o que quebra os projetos que carregam o ambiente de dev pelo `.env` (no kairo, o `Makefile` faz `-include .env` e o `drizzle.config.ts` lê `DATABASE_URL`). Na triagem, o usuário escolheu a saída: o agente lê os `.env` de dev e de teste, e só os de produção ficam negados.

## Objetivo
Num projeto com `.fabrica/producao.txt`, o agente não roda comando Bash que cite um padrão de produção nem alcança pela rede um host de produção. O sandbox deixa o agente ler os `.env` de dev e de teste e nega só os de produção. As skills de spec e de implementação mandam o que tem efeito em produção para o runbook do usuário.

## Comportamento esperado

### O arquivo de padrões
`.fabrica/producao.txt`, versionado na raiz do repositório, com uma regra por linha:

```
# Banco e API de produção do kairo
host db.kairo.app
host *.prod.kairo.app
texto sk_live_
texto PROD_DATABASE_URL
```

| Linha | Efeito |
|---|---|
| `host <domínio>` | O hook barra o comando que cita o domínio, e o setup copia o domínio para `sandbox.network.deniedDomains`. Aceita o curinga `*.` no início, como o `allowedDomains`. |
| `texto <literal>` | Só o hook: barra o comando que cita o literal (prefixo de chave, nome de variável, trecho de URL). |
| vazia, ou começando com `#` depois dos espaços | Ignorada. |
| `texto` com menos de 4 caracteres | Ignorada pelo hook, com aviso no `--check` do setup (`padrão curto: <literal>`), para um padrão como `db` não barrar quase tudo. |
| Outro formato (sem `host` ou `texto`, ou sem valor) | Ignorada pelo hook, com aviso no `--check` do setup (`linha inválida: <nº>`). |

Espaços nas pontas do valor são removidos. A comparação ignora maiúsculas e minúsculas e é por substring literal, sem expressão regular.

### O hook `protect-production.sh`
Roda em todo `PreToolUse` do Bash, depois do `protect-main.sh`.

| Situação | Resultado |
|---|---|
| Fora de um repositório git, ou sem `.fabrica/producao.txt` na cópia de trabalho nem no branch padrão do `origin` | Deixa passar, sem saída. |
| O comando cita um padrão da união das duas versões do arquivo (cópia de trabalho e `origin/<branch padrão>`) | Nega, com `permissionDecision: "deny"` e o motivo "Este comando cita um padrão de produção (`<padrão>`, de .fabrica/producao.txt). As etapas de agente só usam dev ou homologação: o que é de produção vai para o runbook e é rodado por você." |
| O comando não cita nenhum padrão | Deixa passar, sem saída. |
| O padrão está só no `origin` e foi apagado da cópia de trabalho | Nega do mesmo jeito: apagar a linha na branch não libera o agente. |
| O padrão foi acrescentado só na cópia de trabalho | Nega: o padrão novo vale antes do merge. |
| Sem `origin`, ou sem o branch padrão buscado | Usa só a cópia de trabalho. |
| O `jq` ou o `git` faltam | Deixa passar e imprime o aviso em stderr: o `protect-main.sh` já depende dos dois, e o setup confere. |

O diretório do repositório sai do campo `cwd` da entrada do hook, e, sem ele, de `CLAUDE_PROJECT_DIR`. O branch padrão é o de `refs/remotes/origin/HEAD`, e, sem ele, `main`. O hook não roda `git fetch`: vale a última versão buscada.

### O setup do sandbox
1. **Template novo** (`templates/sandbox-project.json`): o `deny` dos `.env` cobre só `.env.production` e `.env.production.local`. Os outros `deny` (`~/.ssh`, `GH_TOKEN`, `GITHUB_TOKEN`) ficam.
2. **Entradas aposentadas:** o script remove do settings do projeto as entradas `{"path": ".env", "mode": "deny"}`, `.env.local`, `.env.development` e `.env.test` só quando são idênticas às que a fábrica gravava. Uma entrada com o mesmo `path` e outro `mode`, ou com campos a mais, fica, porque não é da fábrica.
3. **Hosts de produção:** o script lê as linhas `host` do `.fabrica/producao.txt` do projeto (só a cópia de trabalho: quem roda o setup é o usuário) e soma cada domínio em `sandbox.network.deniedDomains`, sem repetir e sem remover domínios que já estejam lá.
4. **`--check`:**
   - `ok`: nada a mudar;
   - `ausente`: como hoje;
   - `incompleto <itens>`: os itens de hoje, mais `network.deniedDomains:<domínio>` para cada host que falta, `remover:credentials:<path>` para cada entrada aposentada presente e os avisos `padrão curto: <literal>` e `linha inválida: <nº>`. Os avisos sozinhos não deixam o estado incompleto: com tudo instalado e só avisos, a saída é `ok`, seguida dos avisos em stderr.
5. **Projeto sem `.fabrica/producao.txt`:** o script não grava `deniedDomains`, e o `--check` não reclama.

O passo **Sandbox** do `/fabrica:setup` explica as duas mudanças novas (remover os `deny` aposentados e bloquear os hosts de produção) quando o `--check` as reporta. Se o projeto não tem `.fabrica/producao.txt`, o setup diz que, sem ele, o hook e a barreira de rede não fazem nada, e remete ao guia. O setup não cria o arquivo: os padrões são do usuário.

### As skills
- **`/fabrica:spec`:** no desenho técnico, uma migração, um seed ou um script com efeito em dados é descrito e verificado só contra dev ou homologação. Se a issue precisa de um passo em produção, a spec o lista na seção nova "Passos de produção" do template, como item para o runbook do usuário (F8, #96), e nenhum CA depende de rodá-lo.
- **`/fabrica:implementar`:** nunca rode nada contra produção, mesmo que o comando pareça só de leitura. Um passo de produção que a spec não previu é desvio relevante: escalone. Se o hook barrar um comando, não tente contorná-lo (outra grafia, variável, `bash -c`): pare e escalone.
- **`templates/CLAUDE.md`:** na seção Segredos, a convenção: `.env`, `.env.local`, `.env.development` e `.env.test` só têm valores de dev ou de homologação, e os segredos de produção ficam no provedor (os secrets do deploy), nunca na máquina.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com `host db.prod.exemplo` e `texto sk_live_` no `.fabrica/producao.txt`, o hook nega `psql postgres://u@DB.PROD.exemplo/x` e `echo sk_live_abc`, com o motivo citando o padrão, e deixa passar `make test` sem saída. | unitário (`scripts/test-protect-production.sh`) |
| CA2 | Com o padrão no arquivo do `origin/main` e apagado da cópia de trabalho, o hook ainda nega. Com um padrão novo só na cópia de trabalho, também nega. | unitário, com um repositório git e um remoto locais em pasta temporária |
| CA3 | Sem o arquivo, fora de um repositório git ou sem `origin`, o hook deixa passar ou usa só a cópia de trabalho, como na tabela, sem erro e com código de saída 0. | unitário |
| CA4 | Comentários, linhas vazias, `texto` com menos de 4 caracteres e linhas inválidas não barram nada. Um curinga `host *.prod.exemplo` barra `curl https://api.prod.exemplo`. | unitário |
| CA5 | O `hooks/hooks.json` registra o `protect-production.sh` no `PreToolUse` do Bash, depois do `protect-main.sh`, e o hook barra um comando com padrão de produção numa sessão com o plugin carregado. | manual — `claude --plugin-dir <clone>` na branch, num repositório de teste com `.fabrica/producao.txt` |
| CA6 | O setup instala o template novo: num projeto sem sandbox, grava o `deny` só de `~/.ssh`, `.env.production`, `.env.production.local`, `GH_TOKEN` e `GITHUB_TOKEN`. | unitário (`scripts/test-setup-sandbox.sh`) |
| CA7 | Num projeto com os `deny` antigos da fábrica, o `--check` sai `incompleto remover:credentials:.env …`, e a instalação remove as quatro entradas aposentadas idênticas e mantém uma entrada do usuário com o mesmo `path` e outro `mode`. | unitário |
| CA8 | Com linhas `host` no `.fabrica/producao.txt`, o `--check` sai `incompleto network.deniedDomains:<domínio>`, a instalação soma os domínios sem repetir e sem tirar os que já estavam, e um segundo `--check` sai `ok`. Sem o arquivo, nada muda em `deniedDomains`. Avisos de padrão curto e de linha inválida saem em stderr sem mudar o estado. | unitário |
| CA9 | No sandbox instalado pelo setup, num clone de teste com `host` de um domínio que estaria liberado (ex.: `uploads.github.com`), um `curl` a esse host falha pela rede, e o agente lê o `.env` e o `.env.test` do clone, mas não o `.env.production`. | manual — sessão aninhada com `claude -p --settings` no clone de teste, como no aceite da #93 |
| CA10 | `skills/spec/SKILL.md`, `skills/spec/template.md`, `skills/implementar/SKILL.md` e `templates/CLAUDE.md` trazem as regras da seção "As skills". | revisão do diff |
| CA11 | O manual e as decisões ficam em dia: `skills/setup/SKILL.md` (passo Sandbox), `docs/guias/isolamento-do-agente.md` (seção nova "Produção fora do alcance", com o formato do arquivo), `docs/principios.md`, `docs/comandos.md` se citar o sandbox, a ADR 0005 com a nota de que a ADR 0006 mudou a lista de `.env`, a ADR 0006 passada a `aceito` no fim, `CLAUDE.md` com o comando do teste novo, e `.claude-plugin/plugin.json` em `0.28.0`. | revisão do diff |

## Fora de escopo
- O runbook de lançamento e o formato dele: é a F8, item 12 (#96). Esta issue só cria a seção "Passos de produção" na spec, que o runbook vai consumir.
- Bloquear padrões de produção nas ferramentas que não são Bash (Read, Write, WebFetch, MCP). O sandbox e o hook cobrem os comandos; os outros caminhos ficam para o runner isolado (#106).
- Detectar credencial de produção pelo formato, sem o arquivo de padrões.
- Criar o `.fabrica/producao.txt` do kairo e ligar o sandbox lá: é passo do usuário, depois do merge, com o `/fabrica:setup`.
- Tirar do settings do usuário os `deniedDomains` de projetos antigos: o script só escreve no projeto.

## Desenho técnico
**Arquivos e módulos:**
- `hooks/protect-production.sh` (novo): lê a entrada com `jq`, junta os padrões de `<repo>/.fabrica/producao.txt` e de `git -C <repo> show origin/<padrão>:.fabrica/producao.txt`, e compara com o comando em minúsculas. Mesmo formato de saída do `protect-main.sh`.
- `hooks/hooks.json`: segunda entrada no `PreToolUse` com `matcher: "Bash"`, `timeout: 15`. Atualizar o `description`.
- `templates/sandbox-project.json`: `credentials.files` com `~/.ssh`, `.env.production` e `.env.production.local`.
- `scripts/setup-sandbox.sh`: no Python embutido, uma lista `RETIRED` com as quatro entradas aposentadas, removidas antes do `merge` e anotadas em `missing` como `remover:credentials:<path>`. Uma função que lê `<projeto>/.fabrica/producao.txt` e acrescenta os hosts a `sandbox.network.deniedDomains` do template do projeto antes do `merge`, que já soma listas sem repetir. Os avisos vão para stderr.
- `scripts/test-protect-production.sh` (novo) e `scripts/test-setup-sandbox.sh` (casos novos).
- `skills/spec/SKILL.md` e `skills/spec/template.md` (seção "Passos de produção"), `skills/implementar/SKILL.md`, `skills/setup/SKILL.md`, `templates/CLAUDE.md`.
- `docs/guias/isolamento-do-agente.md`, `docs/principios.md`, `docs/adr/0005-isolamento-do-agente-em-sandbox.md`, `docs/adr/0006-producao-fora-do-alcance-do-agente.md`, `CLAUDE.md`, `.claude-plugin/plugin.json`.

**Dados:** nenhum banco. O arquivo novo `.fabrica/producao.txt` fica nos projetos, não no fabrica.

**Interfaces:**
- Hook: entrada JSON do `PreToolUse` (`tool_input.command`, `cwd`); saída vazia ou o JSON `hookSpecificOutput` com `permissionDecision: "deny"`. Sempre sai com 0.
- `setup-sandbox.sh --check`: acrescenta os itens `network.deniedDomains:<domínio>` e `remover:credentials:<path>` ao `incompleto`; os códigos de saída não mudam (0, 1 e 2).

**Decisões:**
- **O agente lê os `.env` de dev e de teste; o sandbox nega só `.env.production` e `.env.production.local`** (recomendação da triagem) — o usuário escolheu a opção (a) na triagem, e os projetos da fábrica carregam o ambiente de dev pelo `.env`. Alternativas descartadas: manter o `deny` de todos os `.env*` e injetar os valores pelo `env` do settings, que versiona chaves de dev; rodar testes e migrações com `!`, que para o fluxo a cada `make test`.
- **Barreira de rede pelo `deniedDomains` do projeto, além do hook** (recomendação da triagem) — o `deniedDomains` vale em qualquer escopo, soma entre escopos e tem precedência sobre o `allowedDomains`, então pega o comando que escapa do texto do hook. Alternativa descartada: só o hook, que a ADR 0002 mostra ser contornável.
- **Padrões em `.fabrica/producao.txt`, versionado por repositório** (recomendação da triagem) — fica junto do código que usa os serviços e passa por PR. Alternativa descartada: uma chave no `.claude/settings.json`, que mistura a configuração da fábrica com a do Claude Code.
- **Regra nas skills: efeito em dados só contra dev ou homologação, e o passo de produção vai para o runbook** (recomendação da triagem) — é o escopo da issue, e o runbook é a F8 (#96). Alternativa descartada: deixar a regra só no hook, que não sabe o que é migração.
- **O hook usa a união da cópia de trabalho com o branch padrão do `origin`** — o sandbox deixa o agente escrever no projeto, então só a cópia de trabalho seria apagável por ele. A versão do `origin` só muda por merge do usuário. Alternativa descartada: só a cópia de trabalho.
- **Duas formas de linha, `host` e `texto`** — o setup precisa saber o que é domínio para o `deniedDomains`, e um literal solto não é um domínio válido. Alternativa descartada: um padrão por linha sem tipo, adivinhando o domínio pelo formato.
- **Substring literal, sem expressão regular, e mínimo de 4 caracteres** — o usuário escreve o padrão sem saber regex, e a regra curta evita um padrão que barre quase tudo. Alternativa descartada: regex, mais poderosa e mais fácil de errar.
- **O setup só remove as entradas aposentadas idênticas às da fábrica** — o script soma listas e nunca apagou nada do usuário; a remoção fica restrita ao que ele mesmo gravou. Alternativa descartada: pedir ao usuário para apagar à mão, que deixaria os projetos da #93 com o `.env` ilegível.

**Fontes da documentação:**
- Claude Code (sandbox) — documentação de settings consultada nesta etapa: `sandbox.network.deniedDomains` vale em qualquer escopo, as listas se somam entre escopos e o `deniedDomains` tem precedência sobre o `allowedDomains`. Versão não confirmada.
- Claude Code (hooks) — documentação de hooks: `PreToolUse` com `matcher`, entrada com `tool_input` e `cwd`, saída `hookSpecificOutput.permissionDecision`. Confirmado também pelo `hooks/protect-main.sh` em uso.
- jq 1.8.1 — `jq --version`. git — `git show <ref>:<caminho>` e `git symbolic-ref`, sem flag nova.
- gh — não usado no desenho.

**ADR:** [docs/adr/0006-producao-fora-do-alcance-do-agente.md](../docs/adr/0006-producao-fora-do-alcance-do-agente.md) (proposto). Ela altera a lista de `deny` dos `.env` da [ADR 0005](../docs/adr/0005-isolamento-do-agente-em-sandbox.md).

## Testes
- `bash scripts/test-protect-production.sh`: monta em pasta temporária um repositório com um remoto local (`git init --bare`) e o `.fabrica/producao.txt` no `main` do remoto. Alimenta o hook com JSON de `PreToolUse` e confere a saída e o código de saída para CA1 a CA4.
- `bash scripts/test-setup-sandbox.sh`: casos novos para CA6 a CA8 (template novo, entradas aposentadas, entrada do usuário mantida, `deniedDomains` somado, idempotência, avisos em stderr). Os 49 casos atuais continuam passando, com os ajustes do template novo.
- `bash scripts/test-protect-main.sh`: continua passando, porque o `hooks.json` muda.
- CA5 e CA9: verificação manual, com o resultado registrado no PR.

## Riscos e dúvidas
- **Hook por texto:** um comando que monta o host por partes passa pelo hook. Para `host`, a barreira de rede pega; para `texto` (um prefixo de chave), não há segunda barreira. A convenção de não ter segredo de produção na máquina é o que cobre esse caso.
- **Ferramentas fora do Bash:** a ferramenta Read não passa pelo sandbox nem pelo hook. Se alguém deixar um `.env.production` na máquina, o agente consegue lê-lo por ela. O guia avisa, e a convenção diz para não ter o arquivo.
- **Falso positivo:** um padrão `texto` comum demais barra comandos inocentes (ex.: um `grep` no código que cita o nome da variável). O contorno é o usuário rodar com `!` ou ajustar o padrão.
- **Branch padrão desatualizado:** sem `git fetch`, um padrão recém-mergeado só vale na cópia de trabalho até a próxima busca. Como a cópia de trabalho também conta, isso só importa se o agente apagar a linha antes da busca.
- **Arquivo sensível:** a issue mexe em hooks e na proteção de credenciais. A revisão humana é obrigatória.

## Histórico
- 2026-11-10: criação.
- 2026-11-10: aprovada.
