# SPEC-108: Dispatcher instalado num projeto pelo `/fabrica:setup`, com o workflow e o guia dos secrets, e ligado no kairo

**Issue:** #108 · **PRD:** F4 (item 8 do fatiamento, M2) · **Classe:** implementacao-complexa · **Tamanho:** G
**Status:** rascunho · **Atualizada em:** 2026-11-22

## Contexto
O dispatcher (#105, #106, #107; [ADR 0015](../docs/adr/0015-dispatcher-no-github-actions.md) a [0017](../docs/adr/0017-leitor-de-estado-em-codigo-para-o-dispatcher.md)) roda as etapas de agente no GitHub Actions, mas hoje só funciona no repositório de teste `ftenorio99/fabrica-teste`, ligado à mão pelos passos de [docs/guias/dispatcher.md](../docs/guias/dispatcher.md). O guia deixa para esta issue duas pendências: a instalação nos projetos pelo `/fabrica:setup` e a lista de domínios por projeto, que o `implementar` precisa para baixar dependências. O kairo é o primeiro projeto real a receber o dispatcher.

## Objetivo
O `/fabrica:setup` instala e atualiza o workflow do dispatcher num projeto, com confirmação, e termina com o checklist dos três secrets; o job aceita hosts extras do projeto por `.fabrica/dominios.txt`; e o dispatcher fica ligado e validado no kairo.

## Comportamento esperado

### No `/fabrica:setup` (novo passo 6, "Dispatcher")
Roda depois da statusline, só dentro de um repositório git. Fora dele, o passo é pulado e o resumo diz "dispatcher: por projeto, não instalado fora de um repositório git".

1. O setup roda `bash <diretório base>/../../scripts/setup-dispatcher.sh --check` e segue a linha impressa:

   | Saída do `--check` | O que o setup faz |
   |---|---|
   | `ausente` (não existe `.github/workflows/agente.yml`) | Explica o dispatcher: a cada gesto na issue ou no PR, um workflow do GitHub Actions roda as etapas de agente até o próximo portão, gastando a assinatura do Claude do usuário e minutos de Actions; precisa de três secrets, cadastrados pelo usuário. Pergunta com o AskUserQuestion se instala, com "Não instalar" como primeira opção. Com um sim, roda `setup-dispatcher.sh --apply`. Com um não, não grava nada. |
   | `ok` (o arquivo é igual, byte a byte, ao `templates/workflows/agente.yml` do plugin) | Não pergunta nada. |
   | `desatualizado` (o arquivo existe e difere do modelo) | Mostra o resumo da diferença que o script imprime em stderr (linhas a mais e a menos) e avisa que uma edição local também aparece como diferença e se perde na troca. Pergunta com o AskUserQuestion se substitui, com "Manter o atual" como primeira opção. Com um sim, roda `setup-dispatcher.sh --apply`. |
   | Saída 1 do script | Leva a mensagem de erro para o resumo e segue. |

2. O `--apply` grava `.github/workflows/agente.yml` na cópia de trabalho, criando `.github/workflows/` se faltar. O setup **não** faz o commit nem abre PR: no resumo, diz ao usuário para levar o arquivo por uma branch e um PR, porque o GitHub só roda o workflow a partir da branch padrão.
3. **Checklist dos secrets.** Se o workflow ficou instalado (gravado agora, `ok` ou `desatualizado` mantido), o setup roda `gh secret list --repo <dono>/<repo> --json name` (só os nomes; nunca lê nem pede um valor) e termina o resumo com o checklist abaixo. Cada item aparece como feito quando o nome do secret está na lista e como pendente quando não está. Se o `gh secret list` falhar (sem permissão, sem remoto), todos os itens aparecem pendentes, com a mensagem de erro.
   1. `CLAUDE_CODE_OAUTH_TOKEN`: gerar com `claude setup-token` e cadastrar com `gh secret set` a partir de uma variável do terminal, sem colar o valor no chat.
   2. `FABRICA_PLUGIN_TOKEN`: token fine-grained só para `ftenorio99/fabrica`, só `Contents: read`.
   3. `FABRICA_GH_TOKEN`: token fine-grained só para o repositório do projeto, com as permissões e a expiração do guia, sem `Workflows`.
   4. Levar `.github/workflows/agente.yml` à branch padrão por um PR (feito quando o `--check` deu `ok` e o arquivo já está em `origin/<branch padrão>`; senão, pendente).

   O detalhe de cada item fica no guia; o checklist remete a ele e não copia as permissões.
4. Com o dispatcher não instalado a pedido do usuário, o resumo diz "dispatcher: não instalado, a pedido do usuário", sem checklist.

### Lista de domínios do projeto no job ([ADR 0018](../docs/adr/0018-lista-de-dominios-por-projeto.md))
- O projeto pode versionar `.fabrica/dominios.txt`, com um host exato por linha, linhas em branco e comentários com `#`. Ele **acrescenta** hosts à lista do plugin (`templates/workflows/dominios-liberados.txt`); nunca tira.
- O `job-isolation.sh prepare` lê o arquivo do checkout (que é a branch padrão, feito antes de o agente rodar), valida e grava a lista final, a do plugin seguida da do projeto sem repetições, em `<dir do isolamento>/dominios.txt`, de root, modo 0644, **antes** de passar o checkout ao `fabrica-agent`. O `lock` passa a ler essa lista final.
- Regras de validação de cada linha do projeto (depois de tirar espaços das pontas e passar para minúsculas):

  | Linha | Resultado |
  |---|---|
  | Vazia ou começando com `#` | Ignorada |
  | Host com pelo menos um ponto, rótulos de `[a-z0-9-]` sem hífen nas pontas e o último rótulo com uma letra (ex.: `registry.npmjs.org`) | Aceita |
  | Com `*` (qualquer curinga, inclusive `*.npmjs.org`), `/`, `:`, espaço no meio, sem ponto, ou um IP (último rótulo só com dígitos) | Inválida |

- **Falha fechada:** uma única linha inválida faz o `prepare` sair com 1, com a linha e o motivo em stderr, sem gravar a lista final; o `lock` não sobe e o agente não roda. O job fica vermelho, e o passo "Publica a falha" comenta na issue com o motivo `sem-resultado`.
- Arquivo ausente, ou só com comentários e linhas vazias: a lista final é a do plugin, igual a hoje.
- Os hosts do projeto **nunca** recebem segredo: o mapa dos marcadores (`markers.json`) continua com os hosts fixos da Anthropic e do GitHub.
- O `lock` sem a lista final (o `prepare` não rodou) falha com "rode job-isolation.sh prepare antes", como já acontece com os hooks do git.

### No kairo
1. O usuário roda o `/fabrica:setup` no clone do kairo e aceita instalar o dispatcher.
2. O kairo ganha, no mesmo PR do workflow, `.fabrica/dominios.txt` com `registry.npmjs.org` (pnpm e o `corepack`), com uma linha de comentário de motivo. Outros hosts só entram depois, pelo log do proxy ("Ampliar a lista" do guia).
3. O usuário cadastra os três secrets e faz o merge do PR do kairo.
4. Uma issue de teste do kairo com `agente` percorre a triagem e a spec e para em "Spec para aprovar".
5. Depois da #203, `spec-aprovada` na mesma issue roda o `implementar` com o `revisar` até "PR para revisar". Sem Docker no job, a parte de integração do `make test` (que precisa do `db-up`) fica pendente para o CI do PR, pelo caminho que o `implementar` já tem para a assinatura do Docker ([ADR 0011](../docs/adr/0011-verificacao-de-integracao-na-etapa.md)).
6. No fim, a issue de teste e o PR dela são fechados com um comentário dizendo que eram teste.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `setup-dispatcher.sh --check` imprime `ausente` num repositório sem `.github/workflows/agente.yml`, `ok` quando o arquivo é byte a byte igual a `templates/workflows/agente.yml` e `desatualizado` quando difere (inclusive por uma única linha ou por quebra de linha final), e não grava nada em nenhum dos três casos. | unitário (`scripts/test-setup-dispatcher.sh`) |
| CA2 | No `desatualizado`, o `--check` imprime em stderr uma linha `diferença: +<n> -<m> linhas` com as contagens do `diff` entre o arquivo e o modelo. | unitário |
| CA3 | `setup-dispatcher.sh --apply` cria `.github/workflows/` se faltar e grava o arquivo igual ao modelo; depois dele, o `--check` imprime `ok`. Num arquivo `desatualizado`, o `--apply` o substitui. | unitário |
| CA4 | O script sai com 1 e uma mensagem em stderr, sem gravar nada, fora de um repositório git, com uma opção desconhecida, sem opção, ou quando o modelo do plugin não existe. | unitário |
| CA5 | O script não faz commit, não roda `git add` nem `gh`: depois do `--apply`, o `git status --porcelain` mostra o arquivo como não rastreado (ou modificado) e o `git log` não muda. | unitário |
| CA6 | O passo 6 do `skills/setup/SKILL.md` segue a tabela do `--check` (pergunta só em `ausente` e `desatualizado`, com a opção de não mexer em primeiro lugar), não faz commit, e o resumo traz o estado final do dispatcher (`instalado agora`, `já estava instalado`, `desatualizado, mantido a pedido do usuário`, `não instalado, a pedido do usuário`, `não instalado fora de um repositório git` ou o erro do script). | manual: `claude --plugin-dir <worktree>` num repositório de teste, nos casos `ausente` (sim e não), `ok` e `desatualizado` |
| CA7 | O checklist dos secrets marca cada um dos três como feito ou pendente pelos nomes do `gh secret list --json name`; com o `gh secret list` falhando, todos aparecem pendentes com a mensagem de erro. O setup não roda `gh secret set` e não pede nenhum valor de token. | manual: `claude --plugin-dir <worktree>` no `ftenorio99/fabrica-teste` (que tem os três secrets) e num repositório de teste sem nenhum |
| CA8 | O `prepare` com `.fabrica/dominios.txt` válido no checkout grava `<dir>/dominios.txt` com os hosts do plugin seguidos dos do projeto, sem repetir um host que já está na lista do plugin, de root e modo 0644, antes de passar o checkout ao agente. | unitário (`scripts/test-job-isolation.sh`) |
| CA9 | Sem `.fabrica/dominios.txt`, ou com ele só com comentários e linhas vazias, a lista final é igual à do plugin. | unitário |
| CA10 | Cada forma inválida da tabela de validação (`*`, `*.npmjs.org`, `https://x.org`, `x.org:443`, `a b.org`, `localhost`, `10.0.0.1`, `-x.org`) faz o `prepare` sair com 1, com a linha em stderr, sem gravar `<dir>/dominios.txt`. | unitário |
| CA11 | O `lock` lê `<dir>/dominios.txt`; sem ele, sai com 1 e a mensagem "rode job-isolation.sh prepare antes", sem subir o proxy. O `FABRICA_DOMAINS_FILE` continua trocando o arquivo nos testes. | unitário |
| CA12 | Com um host do projeto na lista, o `markers.json` gravado pelo `lock` continua com os hosts fixos de cada segredo: nenhum host do projeto aparece nele. | unitário |
| CA13 | O guia `docs/guias/dispatcher.md` descreve a instalação pelo `/fabrica:setup`, o `.fabrica/dominios.txt` (formato, regras, falha fechada, que vale pela branch padrão e que pede revisão humana) e tira as menções de "fica para a #108"; o `docs/comandos.md` e o `description` do setup citam o dispatcher; o `AGENTS.md` cita o `setup-dispatcher.sh` e o teste dele; a `version` do `plugin.json` sobe. | manual (revisão do diff) |
| CA14 | O comentário de cabeçalho do `templates/workflows/agente.yml` diz que o `/fabrica:setup` copia o arquivo e que os hosts extras vêm de `.fabrica/dominios.txt`; os testes do workflow (`bash scripts/test-dispatch.sh`) seguem verdes. | unitário |
| CA15 | No kairo, `.github/workflows/agente.yml` igual ao modelo e `.fabrica/dominios.txt` com `registry.npmjs.org` estão na `main`, e os três secrets estão cadastrados (`gh secret list --repo ftenorio99/kairo` mostra os três nomes). | depois do merge — o setup roda interativo no clone do kairo, o job instala o plugin da `main` da fábrica pelo marketplace, e cadastrar os secrets é ação do usuário |
| CA16 | No kairo, uma issue de teste com `agente` roda a triagem e a spec num só run e para em "Spec para aprovar", com o run verde e o log do proxy sem `bloqueado` de host necessário. | depois do merge — o job do kairo instala o plugin da `main` da fábrica, então a lista do projeto só vale com este PR na `main` |
| CA17 | No kairo, depois da #203, `spec-aprovada` na issue de teste roda o `implementar` com o `revisar` e para em "PR para revisar"; o `pnpm install` passa pelo proxy, e a integração que precisa de Docker fica anotada como pendente para o CI. A issue e o PR de teste são fechados com um comentário dizendo que eram teste. | depois do merge — depende da #203 e do mesmo plugin da `main` do CA16 |

## Fora de escopo
- Docker dentro do job: o `fabrica-agent` não ganha acesso ao `docker.sock`, que equivale a root e desfaria o isolamento ([ADR 0016](../docs/adr/0016-isolamento-do-job-do-dispatcher.md)). A integração fica para o CI do PR.
- Copiar o `isolamento-aceite.yml` para os projetos: ele segue só no repositório de teste.
- Cadastrar secrets ou gerar tokens pelo setup.
- A identidade de commit do agente no job (#203), o `.git/config` da worktree (#204) e as sugestões da #205.
- Hosts com curinga na lista do projeto e listas por etapa.
- O revisor apontar mudanças em `.fabrica/dominios.txt` como sensíveis: a revisão humana do PR cobre isso por ora.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/setup-dispatcher.sh` (novo): `--check` e `--apply`, como descrito; acha a raiz com `git rev-parse --show-toplevel` e o modelo em `<script_dir>/../templates/workflows/agente.yml`. Saídas: 0 ok, 1 erro.
- `scripts/test-setup-dispatcher.sh` (novo): CA1 a CA5, em repositórios git temporários.
- `scripts/job-isolation.sh`: no `cmd_prepare`, antes do `chown` do checkout, uma função `build_domains` que lê `$workspace/.fabrica/dominios.txt`, valida e grava `$dir/dominios.txt`; no `cmd_lock`, o padrão do `domains` passa a ser `$dir/dominios.txt`, com a falha "rode job-isolation.sh prepare antes" quando falta. A validação do projeto fica no shell, mais estrita que o `load_domains` do `egress-addon.py`, que continua validando a lista final no `check`.
- `scripts/test-job-isolation.sh`: CA8 a CA12.
- `skills/setup/SKILL.md`: passo 6, item do dispatcher no "Responder", regras ("não grave o workflow sem a confirmação", "não rode `gh secret set` nem peça valor de token", "não faça commit do workflow") e o `description`.
- `templates/workflows/agente.yml`: só o comentário de cabeçalho (CA14).
- `docs/guias/dispatcher.md`, `docs/comandos.md`, `AGENTS.md`, `.claude-plugin/plugin.json` (CA13).
- `docs/adr/0018-lista-de-dominios-por-projeto.md` (novo, proposto).
- No kairo (fora deste PR, pelo setup e por um PR do usuário): `.github/workflows/agente.yml` e `.fabrica/dominios.txt`.

**Dados:** nenhum.

**Interfaces:**
- `setup-dispatcher.sh --check` → stdout `ausente` | `ok` | `desatualizado`; stderr `diferença: +<n> -<m> linhas` no `desatualizado`.
- `setup-dispatcher.sh --apply` → grava o arquivo; stdout `instalado .github/workflows/agente.yml`.
- `.fabrica/dominios.txt` do projeto → um host exato por linha.
- `<dir do isolamento>/dominios.txt` → lista final, gravada pelo `prepare`, lida pelo `lock`.

**Decisões:**
- Instalação opt-in, com o AskUserQuestion antes de gravar o workflow (recomendação da triagem) — os hooks e a statusline já funcionam assim, e o dispatcher passa a gastar a assinatura. Alternativa descartada: instalar sempre.
- O setup grava o workflow na cópia de trabalho e não faz o commit; o usuário leva por branch e PR (recomendação da triagem) — o `.fabrica/isolamento.txt` já segue esse caminho e a `main` é protegida. Alternativa descartada: o setup abrir o PR sozinho.
- Os secrets ficam fora do setup, que termina com um checklist do usuário (recomendação da triagem) — o setup já não grava o secret do `sbx`, e o checklist do `sbx` é o modelo. Alternativa descartada: o setup rodar `gh secret set`.
- O checklist lê só os nomes com `gh secret list --json name` — marca o que já está feito, como o checklist do `sbx`, sem tocar em valores. Alternativa descartada: checklist sempre pendente, que obrigaria o usuário a conferir à mão.
- Atualização por `--check` com `ausente`, `ok` ou `desatualizado`, comparando byte a byte com o modelo, e troca só com confirmação (recomendação da triagem) — igual ao `setup-githooks.sh` e ao `setup-statusline.sh`. Alternativa descartada: sobrescrever sempre.
- Domínios por projeto em `.fabrica/dominios.txt`, versionado, só acrescentando hosts exatos e valendo pela branch padrão (recomendação da triagem) — o checkout do job já é a branch padrão, então só vale o que entrou por PR de um humano. Alternativa descartada: a lista única do plugin ganhar os hosts do kairo, que abriria esses hosts para todos os projetos.
- Na lista do projeto, nenhum curinga, nem `*.dominio` — o projeto declara o host que o log do proxy mostrou; o curinga fica só na lista do plugin, revisada na fábrica. Alternativa descartada: aceitar `*.dominio` com a mesma regra do plugin.
- A lista final é montada no `prepare`, de root, antes de o checkout passar ao agente — depois do `chown`, o agente poderia editar o arquivo do projeto antes do `lock`. Alternativa descartada: o `lock` ler o arquivo direto do checkout.
- Validação no kairo em dois passos, triagem e spec antes e `implementar` com `revisar` só depois da #203 (recomendação da triagem). Alternativa descartada: validar só a triagem.

**Fontes da documentação:**
- gh 2.105.0 — `gh secret list --help` (flag `--repo`, `--json` com o campo `name`).
- GitHub Actions (eventos `issues` só a partir da branch padrão, `actions/checkout` com `ref`) — não verificada nesta etapa; o comportamento já foi validado no `fabrica-teste` pela #105 a #107.
- pnpm 12.16.1 (`packageManager` do kairo) — não verificada: o host do registro (`registry.npmjs.org`) é o padrão do pnpm e já está no checklist do `sbx`.

**ADR:** [docs/adr/0018-lista-de-dominios-por-projeto.md](../docs/adr/0018-lista-de-dominios-por-projeto.md)

## Testes
- `bash scripts/test-setup-dispatcher.sh`: CA1 a CA5, com repositórios git temporários e o modelo do plugin (e um modelo falso para o caso do modelo ausente).
- `bash scripts/test-job-isolation.sh`: CA8 a CA12, com os binários falsos que o teste já usa e um checkout temporário com e sem `.fabrica/dominios.txt`.
- `bash scripts/test-dispatch.sh`: CA14.
- Manual, antes do merge, com `claude --plugin-dir <worktree>`: CA6 e CA7, num repositório de teste e no `fabrica-teste`. A revisão do diff cobre o CA13.
- Depois do merge: CA15 a CA17 no kairo.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Hosts que faltam no kairo:** além de `registry.npmjs.org`, o `implementar` pode pedir outros (fontes do Next.js no build, binários de pacotes nativos). O caminho é o log do proxy e um PR no `.fabrica/dominios.txt` do kairo; o CA17 só fecha com o `pnpm install` passando.
- **#203 aberta:** sem a identidade de commit, o `implementar` do kairo pode não fazer o commit; por isso o CA17 depende dela.
- **Agente propondo hosts:** um PR do agente pode acrescentar um host ao `.fabrica/dominios.txt`; ele só vale depois do merge humano, mas o revisor automático não o destaca. O guia pede atenção a essa mudança na revisão do PR.
- **Arquivo sensível no kairo:** o workflow vai para o `.github/` do kairo, ao lado do `homolog-deploy.yml`. O job do dispatcher só referencia os três secrets dele; a revisão humana do PR do kairo confere isso.
- **Edição local do workflow:** quem ajustar o `agente.yml` no projeto vê `desatualizado` a cada setup; trocar desfaz o ajuste. O aviso do passo 6 cobre isso.

## Histórico
- 2026-11-22: criação.
