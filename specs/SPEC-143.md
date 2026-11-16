# SPEC-143: Rodar a verificação de integração dentro da VM do sbx

**Issue:** #143 · **PRD:** F1, F6 · **Classe:** implementacao-complexa · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-15

## Contexto
A [ADR 0007](../docs/adr/0007-verificacao-de-integracao-pelo-ci.md) mandou o `make test` com banco e o `make e2e` para o CI do PR, porque o sandbox nativo bloqueava o Docker e o `localhost`. A [ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) (#141) retirou o sandbox nativo e gravou o modo de isolamento do projeto em `.fabrica/isolamento.txt`. Na VM do `sbx`, Docker e Compose funcionam, e no modo `sem-sandbox` o agente usa os da máquina. Esta issue é a parte C da divisão da #141: as etapas passam a rodar a verificação de integração elas mesmas. A F6 do PRD (testes de ponta a ponta no CI do PR) não muda: o CI continua rodando tudo.

## Objetivo
O `/fabrica:implementar`, o `/fabrica:revisar` e o revisor rodam a verificação de integração na própria etapa, nos dois modos de isolamento, e o CI do PR fica como reserva, para quando o ambiente não a roda, e como conferência.

## Comportamento esperado

### Termos
- **Verificação de integração:** a parte do `make test` e do `make e2e` que precisa de Docker, de banco ou do `localhost`.
- **Assinatura de ambiente:** trecho da saída que mostra que o ambiente não roda a verificação. Substitui a "assinatura de limite do sandbox". A lista fica só no passo "Verificar" do `/fabrica:implementar`:
  1. `docker.sock` junto com `permission denied`, `EACCES` ou `connect: operation not permitted`;
  2. `ECONNREFUSED` (ou `Connection refused`) para `127.0.0.1`, `::1` ou `localhost`;
  3. `Operation not permitted` ao criar um socket (`socket(AF_UNIX`);
  4. `Cannot connect to the Docker daemon` (Docker desligado ou não instalado);
  5. do Playwright: `Failed to download` na instalação do navegador, `Executable doesn't exist at` ou `Host system is missing dependencies`.
- **Reserva do CI:** o caminho que hoje se chama "verificação pendente para o CI". O nome e o mecanismo ficam: PR em rascunho, espera do CI do head, resultado do CI passado ao revisor.

### Modo de isolamento
Antes de rodar a verificação, a etapa lê o modo com `bash <diretório base da skill>/../../scripts/setup-isolation.sh --check`. O modo não muda o caminho. Ele muda só a anotação e a orientação:

| Saída do `--check` | O que a etapa faz | Orientação quando há assinatura de ambiente |
|---|---|---|
| `sbx` | Roda a verificação completa na etapa | "Na VM, confira o Docker; no host, veja o `sbx policy log <projeto>`", com o link da seção de hosts do guia |
| `sem-sandbox` | Roda a verificação completa na etapa | "Confira se o Docker está ligado na máquina" |
| `ausente` ou `inválido` | Roda a verificação completa na etapa, sem parar, e avisa no chat: "O projeto não tem modo de isolamento gravado. Rode `/fabrica:setup`." | As duas orientações acima |
| O script sai com código diferente de 0 | Trata como `ausente` | Idem |

O aviso de `ausente` ou `inválido` sai uma vez por execução, no chat, e não vai para a issue nem para o PR.

### `/fabrica:implementar`, passo "Verificar"
1. Lê o modo.
2. Roda `make lint`, `make test` e, se a spec tem CA de ponta a ponta, `make e2e`. Tudo conta como uma rodada de verificação, como hoje.
3. Sem assinatura de ambiente, vale a regra de hoje: verde segue; falha conta rodada de correção e escala depois de duas.
4. Com assinatura de ambiente num comando:
   - roda as partes que não dependem do ambiente, quando o projeto as separa, como hoje;
   - anota `<comando>: o ambiente não roda a verificação (modo <saída do --check>: <assinatura>)`. Essa é a verificação pendente para o CI, que vai para o `revisar`;
   - não conta rodada nem escala por ela.
5. **Bordas:**
   - o mesmo comando falha com assinatura e com outro erro: vale o outro erro, como hoje;
   - `make test` passa e só o `make e2e` tem assinatura: só o `make e2e` fica pendente para o CI, e os CAs cobertos pelo `make test` têm a evidência da etapa;
   - a assinatura some depois de uma correção de ambiente feita pelo usuário e a etapa é retomada: roda de novo e não há pendência.
6. O passo não fala mais em "limite do sandbox" nem em "bloqueado pelo sandbox".

### `/fabrica:revisar`
- **Pré-requisitos:** `make lint` e `make test` passam, ou falham só com assinatura de ambiente, com a verificação pendente para o CI anotada. Rodada sozinha (sem vir do `implementar`), a etapa lê o modo no passo 1.
- **Sem pendência:** o PR não nasce em rascunho por causa da verificação de integração. O revisor roda a verificação, e a evidência dos CAs de integração é a dele. O CI do passo 6 continua sendo esperado, como em todo PR.
- **Reserva do CI:** com verificação pendente, o caminho é o de hoje (sem CI → pedido ao usuário; PR em rascunho; espera do CI; resultado ao revisor). Muda o texto: "comandos que o ambiente não roda" no lugar de "comandos bloqueados pelo sandbox", e a referência passa a ser a ADR 0011. A linha do resumo do PR vira "Verificação de integração pelo CI (ADR 0011)". O corpo do PR ganha, em "Para a sua revisão", a anotação de cada comando e a orientação do modo.
- **Ao revisor:** a etapa passa também a saída do `--check`.
- **CA manual fora do alcance:** só vale quando o revisor devolve o CA como não feito com um destes motivos: depende do usuário (outra sessão, conta externa, passo interativo), ou a tentativa falhou com assinatura de ambiente. O pedido ao usuário e o ⏳ "aguardando a sua verificação" continuam como hoje. O texto deixa de dizer "não roda no sandbox".

### Revisor (`agents/revisor.md`)
- Roda `make lint`, `make test` e, se a spec tem CA de ponta a ponta, `make e2e`.
- Falha com assinatura de ambiente não é achado: anota "o ambiente não roda a verificação (<assinatura>)" e usa o resultado do CI recebido, como hoje. Sem CI e sem resposta do usuário, o CA fica `parcial`, com a evidência "o ambiente não roda a verificação, sem resultado do CI".
- **Verificação manual com app e banco:** o revisor tenta rodar antes de devolver como não feita. Ele sobe o que o projeto oferece pelo `Makefile` (ex.: `make db-up`) e roda o comando do CA. Subir e parar serviços do projeto não é alterar arquivos nem o estado do repositório. Se a verificação cria arquivos na cópia de trabalho, ele não a roda e devolve `não`, com esse motivo.
- Devolve `não`, com a evidência "verificação manual fora do alcance do agente, sem resultado (<motivo>)", só nos dois motivos do "CA manual fora do alcance".
- O formato da resposta troca `bloqueado pelo sandbox (<assinatura>)` por `o ambiente não roda a verificação (<assinatura>)` e ganha a linha `- make e2e: <ok | falhou: resumo | o ambiente não roda a verificação (<assinatura>) | não se aplica>`.

### Rede da VM
- A verificação baixa as imagens do Compose e os navegadores do Playwright. O Docker Hub já está na política do checklist.
- O Playwright baixa os navegadores de `cdn.playwright.dev`, com `playwright.download.prss.microsoft.com` como espelho. Esses dois hosts entram no guia e no checklist do setup como uma linha condicional, "projeto com `make e2e` (Playwright)", com o comando `sbx policy allow network --sandbox <projeto> cdn.playwright.dev,playwright.download.prss.microsoft.com`. Eles não entram no comando base do item 3.
- Imagem de outro registry: o guia manda ver o host bloqueado no `sbx policy log <projeto>` e liberar só ele, como a seção "Ampliar os domínios" já diz.
- Bibliotecas de sistema do navegador: o guia diz que, se o `make e2e` falhar com `Host system is missing dependencies`, o usuário roda na VM, uma vez, o comando de instalação das dependências do Playwright do projeto (ex.: `pnpm exec playwright install --with-deps chromium`). A etapa não instala pacotes de sistema.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md` e `agents/revisor.md` não têm mais `limite do sandbox`, `bloqueado pelo sandbox`, `fora do sandbox`, `no sandbox` nem link para a ADR 0007. | manual — `grep -nE 'limite do sandbox\|bloqueado pelo sandbox\|fora do sandbox\|no sandbox\|0007' skills/implementar/SKILL.md skills/revisar/SKILL.md agents/revisor.md` sem resultado |
| CA2 | O passo "Verificar" do `implementar` manda ler o modo com `setup-isolation.sh --check` antes dos comandos e traz a tabela das quatro saídas desta spec, com a etapa seguindo sem parar em `ausente`, em `inválido` e na falha do script, e o aviso no chat para rodar o `/fabrica:setup`. | manual — leitura do arquivo |
| CA3 | O mesmo passo lista as cinco assinaturas de ambiente desta spec e o formato da anotação `<comando>: o ambiente não roda a verificação (modo <saída do --check>: <assinatura>)`, e diz que a assinatura não conta rodada nem escala. | manual — leitura do arquivo |
| CA4 | O mesmo passo traz as três bordas: assinatura junto com outro erro (vale o outro erro); só o `make e2e` com assinatura (só ele fica pendente); assinatura que some na retomada (sem pendência). | manual — leitura do arquivo |
| CA5 | No `revisar`, sem verificação pendente, o PR não é aberto em rascunho por causa da verificação de integração; com pendente, o caminho da reserva do CI tem os mesmos quatro itens de hoje (sem CI, PR em rascunho, CI, revisor), com a referência à ADR 0011. | manual — leitura do passo 3 |
| CA6 | O `revisar` passa a saída do `--check` ao revisor e, rodado sozinho, lê o modo no passo 1. A linha do resumo do PR é "Verificação de integração pelo CI (ADR 0011)". | manual — leitura dos passos 1, 3 e 6 |
| CA7 | O "CA manual fora do alcance" do `revisar` só se aplica aos dois motivos desta spec (depende do usuário; tentativa com assinatura de ambiente). | manual — leitura do passo 4 |
| CA8 | O `agents/revisor.md` manda rodar o `make e2e` quando a spec tem CA de ponta a ponta, tentar a verificação manual com app e banco antes de devolvê-la como não feita, e não rodá-la se ela cria arquivos na cópia de trabalho. O formato da resposta tem a linha do `make e2e` e o texto novo da anotação. | manual — leitura do arquivo |
| CA9 | As três evidências do revisor têm o texto desta spec: "o ambiente não roda a verificação (<assinatura>)", "o ambiente não roda a verificação, sem resultado do CI" e "verificação manual fora do alcance do agente, sem resultado (<motivo>)". | manual — `grep -n 'o ambiente não roda a verificação\|fora do alcance do agente' agents/revisor.md` |
| CA10 | A ADR 0011 está com status `aceito`. A ADR 0007 está com `substituído por ADR 0011`, com o texto das seções preservado e a nota abaixo do status remetendo à 0011, sem citar a #143 como pendência. | manual — leitura dos dois arquivos e `git diff origin/main -- docs/adr/0007-verificacao-de-integracao-pelo-ci.md` só com mudança no status e na nota |
| CA11 | A seção "Verificação de integração" do guia `docs/guias/isolamento-do-agente.md` descreve a verificação na etapa nos dois modos, a reserva do CI e as assinaturas pelo nome, remete à ADR 0011 e não cita a #143 como pendência. A frase "por enquanto, ele só orienta o setup" da seção "Os dois modos" sai. | manual — leitura do guia |
| CA12 | O guia tem a subseção de hosts da verificação de integração, com o comando dos dois hosts do Playwright, o caminho para imagem de outro registry e o caso `Host system is missing dependencies`. O checklist do modo `sbx`, no guia e no `skills/setup/SKILL.md`, tem a linha condicional do Playwright no item 3, com o mesmo comando, e o comando base do item 3 não muda. | manual — leitura dos dois arquivos e `git diff origin/main -- skills/setup/SKILL.md` |
| CA13 | `docs/guias/issue-escalonada.md` (as duas linhas da tabela que falam do sandbox), `docs/comandos.md` (`implementar` e `revisar`) e a linha 9 da tabela de `skills/status/estados.md` descrevem a regra nova e remetem à ADR 0011. Fora de `specs/` e de `docs/adr/`, nenhum arquivo `.md` de `skills/`, `agents/` e `docs/` cita a ADR 0007. | manual — leitura e `grep -rn '0007' skills agents docs --include=*.md \| grep -v '^docs/adr/'` sem resultado |
| CA14 | Os testes de script continuam passando: `test-setup-isolation.sh`, `test-protect-main.sh`, `test-protect-production.sh`, `test-statusline.sh`, `test-check-gh.sh`, `test-stage-usage.sh`, `test-costs.sh` e `test-durations.sh`. | unitário — `bash scripts/<teste>` para cada um |
| CA15 | A `version` do `.claude-plugin/plugin.json` sobe para a próxima versão menor a partir da que estiver na `main` no momento da implementação (hoje `0.33.0`, então `0.34.0`). | manual — `git diff origin/main -- .claude-plugin/plugin.json` |
| CA16 | Na máquina, no clone do `kairo`, o `setup-isolation.sh --check --project <clone do kairo>` desta branch imprime uma das quatro saídas, e `make test` roda os testes com banco até o fim, sem assinatura de ambiente. | manual — rodar os dois comandos e registrar a saída; com assinatura de ambiente na máquina da etapa, registrar a assinatura e conferir que ela é uma das cinco |
| CA17 | Na VM do `sbx` do `kairo`, com a política do checklist mais a linha do Playwright, `make test` e `make e2e` passam, e o `sbx policy log kairo` não mostra host bloqueado durante a verificação. | depois do merge — depende de o usuário liberar os hosts no host (`sbx policy allow`) e abrir a sessão na VM |
| CA18 | Na primeira issue do `kairo` ou do `ancora` implementada depois do merge, com Docker disponível, o PR não nasce em rascunho por verificação de integração, e os CAs de integração têm como evidência o teste rodado na etapa. | depois do merge — depende de uma issue real com `spec-aprovada` num projeto com banco |

## Fora de escopo
- Remover os scripts e templates do sandbox nativo e migrar os projetos: #142.
- Mudar o CI dos projetos. Ele continua rodando a verificação completa em `pull_request`.
- Mudar `scripts/setup-isolation.sh`: as etapas usam o `--check` que já existe.
- Detectar se a sessão roda mesmo dentro da VM quando o modo gravado é `sbx`.
- Instalar o Docker, os navegadores ou pacotes de sistema pela etapa.
- Gravar `.fabrica/isolamento.txt` no `kairo` e no `ancora`: é do `/fabrica:setup`, rodado pelo usuário.
- Editar o texto das ADRs 0005 e 0010, que citam a 0007 como registro histórico.

## Desenho técnico
**Arquivos e módulos:**
- `skills/implementar/SKILL.md`: passo 4 (modo, assinaturas, anotação, bordas) e passo 5 (a frase "verde com só a verificação pendente para o CI" fica).
- `skills/revisar/SKILL.md`: passo 1 (pré-requisito e leitura do modo), passo 3 (verificação pedida ao usuário, reserva do CI, o que passa ao revisor), passo 4 ("CA manual fora do alcance") e passo 6 (linha do resumo; a menção ao token fine-grained da ADR 0005 em "Ler o CI" passa a remeter ao guia de isolamento).
- `agents/revisor.md`: item 3, tabela e detalhes do item 4, regra do Bash (inclui `make e2e` e subir serviços do projeto) e formato da resposta.
- `docs/adr/0011-verificacao-de-integracao-na-etapa.md` (status) e `docs/adr/0007-verificacao-de-integracao-pelo-ci.md` (status e nota).
- `docs/guias/isolamento-do-agente.md`: seções "Os dois modos", "Modo `sbx`" (item 3) e "Verificação de integração", com a subseção de hosts.
- `docs/guias/issue-escalonada.md`, `docs/comandos.md`, `skills/status/estados.md` (só o link e o texto da linha 9; nenhum estado muda) e `skills/setup/SKILL.md` (linha condicional no item 3 do checklist).
- `.claude-plugin/plugin.json`.

**Dados:** nenhum.

**Interfaces:**
- `scripts/setup-isolation.sh --check`: imprime `ausente`, `inválido`, `sbx` ou `sem-sandbox`, com código 0; código 1 fora de um repositório git. Não muda.
- Anotação do `implementar` para o `revisar`: linhas `<comando>: o ambiente não roda a verificação (modo <saída do --check>: <assinatura>)`.
- Do `revisar` para o revisor: a saída do `--check`, além do que já passa.

**Decisões:**
- No modo `sem-sandbox`, a etapa roda a verificação de integração na máquina (recomendação da triagem) — o agente já roda lá, com o Docker dela, e o motivo da ADR 0007 era só o sandbox nativo. Alternativa descartada: manter no CI.
- A falha com assinatura de ambiente usa a reserva do CI nos dois modos (recomendação da triagem) — cobre a máquina com o Docker desligado sem contar rodada nem escalar. Alternativa descartada: tratar a assinatura como falha comum.
- Sem `.fabrica/isolamento.txt`, ou com ele inválido, a etapa não para e avisa para rodar o `/fabrica:setup` (recomendação da triagem) — o `kairo` e o `ancora` ainda não têm o arquivo. Alternativa descartada: parar até o modo ser gravado.
- O revisor tenta a verificação manual com app e banco antes de pedi-la ao usuário (recomendação da triagem) — o limite que impedia isso saiu. Alternativa descartada: tratar só o `make test` e o `make e2e`.
- ADR nova, a 0011, que substitui a 0007 (recomendação da triagem) — a decisão muda de fato, e a #141 fez o mesmo com a 0005. Alternativa descartada: só uma nota na 0007.
- As etapas leem o modo pelo `setup-isolation.sh --check` (recomendação da triagem) — um leitor só do arquivo. Alternativa descartada: cada etapa ler o arquivo.
- Os hosts do Playwright entram como linha condicional do checklist, e os demais são liberados um a um pelo `sbx policy log` (recomendação da triagem) — "libere só o host exato". Alternativa descartada: pôr todos os registries conhecidos no comando base.
- O modo não muda o caminho da verificação, só a anotação e a orientação — com as três primeiras decisões, os quatro casos rodam a verificação e caem na mesma reserva. Alternativa descartada: um caminho por modo, que repetiria o mesmo texto quatro vezes nas skills.
- As assinaturas de ambiente ganham dois itens além dos três da ADR 0007: `Cannot connect to the Docker daemon` e as três mensagens do Playwright — sem eles, o Docker desligado e o navegador que não baixa na VM contariam como falha da implementação e escalariam. Alternativa descartada: manter só as três assinaturas e deixar esses casos escalarem.
- O revisor passa a rodar o `make e2e` quando a spec tem CA de ponta a ponta — o escopo da issue inclui o revisor, e ele só aceita como evidência o que ele mesmo roda. Alternativa descartada: o revisor aceitar o `make e2e` do `implementar` ou o do CI.
- O revisor recebe o modo do `revisar` — o subagente não tem o diretório base do plugin para achar o script. Alternativa descartada: o revisor rodar o script.

**Fontes da documentação:**
- `@playwright/test` 1.64.1 (`kairo`) e 1.65.0 (`ancora`) — doc local: `node_modules/playwright-core/lib/coreBundle.js`, de onde saem os espelhos de download (`cdn.playwright.dev`, `playwright.download.prss.microsoft.com`), as variáveis `PLAYWRIGHT_DOWNLOAD_HOST` e as mensagens `Failed to download`, `Executable doesn't exist at` e `Host system is missing dependencies`.
- `sbx` 0.51.0 — `sbx policy allow network --help` e `sbx policy log --help`.
- Docker — a mensagem `Cannot connect to the Docker daemon`: não verificada.
- gh 2.104.0 — `gh pr create --help` (`--draft`, `--body-file`) e `gh pr ready --help` (`--undo`). A spec não acrescenta comando do `gh` às etapas.

**ADR:** [docs/adr/0011-verificacao-de-integracao-na-etapa.md](../docs/adr/0011-verificacao-de-integracao-na-etapa.md) (proposto).

## Testes
- CA1 a CA13 e CA15: leitura dos arquivos e os `grep` e `git diff` indicados. Não há teste automático para texto de skill.
- CA14: rodar cada `scripts/test-*.sh` da lista com `bash`. O repositório não tem `Makefile` nem CI. Os testes do sandbox nativo (`test-setup-sandbox.sh`, `test-sandbox-acceptance.sh`) ficam fora, porque saem na #142.
- CA16: no clone do `kairo` da máquina da etapa, `bash scripts/setup-isolation.sh --check --project <clone>` e `make test`. O `make test` sobe o Postgres de dev do Compose e não toca em produção.
- CA17 e CA18: depois do merge, pelo usuário.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Texto de skill sem teste automático:** um texto mal amarrado deixa um PR sair do rascunho sem a verificação de integração. O CI do passo 6 do `revisar` continua obrigatório antes do `pronto-revisao`, e o CA18 confere o comportamento numa issue real.
- **Hosts do Playwright não testados na VM:** a lista sai do código do Playwright instalado, e não de um teste com a política fechada. O CA17 confere. Se faltar host, o guia já manda liberar o que aparecer no `sbx policy log`.
- **Bibliotecas de sistema na VM:** o `make e2e` do `kairo` instala o Chromium sem `--with-deps`. Se a imagem da VM não tiver as bibliotecas, a etapa cai na reserva do CI pela assinatura do Playwright até o usuário instalar as dependências na VM.
- **Modo `sbx` gravado e sessão fora da VM:** a etapa não distingue. Ela roda a verificação na máquina, como no `sem-sandbox`.
- **Conflito com a #142:** ela mexe em `docs/guias/isolamento-do-agente.md`, `docs/comandos.md`, `skills/setup/SKILL.md` e na `version`. A que entrar depois faz o rebase.
- **`make e2e` duas vezes:** o `implementar` e o revisor rodam o `make e2e`, o que alonga a etapa nos projetos com build de produção no e2e.

## Histórico
- 2026-11-15: criação.
