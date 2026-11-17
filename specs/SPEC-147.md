# SPEC-147: Checklist do sbx usa o nome real da VM e não manda recriar a VM em que o setup roda

**Issue:** #147 · **PRD:** F1 · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-16

## Contexto
A F1 do PRD isola o agente numa VM do Docker Sandboxes ([ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)). No fim do `/fabrica:setup`, um checklist mostra o que o usuário faz no host para preparar essa VM. Hoje o checklist e o guia usam `<projeto>` como nome da VM, mas as VMs reais se chamam `claude-<projeto>`, que é o nome padrão do `sbx`. Em 2026-11-16, o setup rodou dentro das VMs do kairo e do ankyra, mandou criar de novo a VM em que estava e sugeriu comandos de rede e de log para nomes que nenhuma VM usa.

## Objetivo
O checklist do modo `sbx` e o guia usam o nome `claude-<projeto>` em todo comando, e o setup rodado dentro da VM mostra como feito o que a VM já prova, deixando pendente só o que ainda pode faltar.

## Comportamento esperado
No modo `sbx`, o setup roda o `scripts/sbx-context.sh` e monta o checklist com a saída dele. `<vm>` é o valor da linha `nome`, ou seja, `claude-` mais o nome da pasta do repositório.

| Item | Setup no host (`onde host`) | Setup na VM (`onde vm`) |
|---|---|---|
| 1. Fechar a rede padrão | pendente, como hoje | feito: o setup roda dentro da VM, e o item 6 confere |
| 2. Criar a VM | pendente: `sbx create --name <vm> claude .` | feito: o setup roda dentro da VM |
| 3. Rede base da VM | pendente: `sbx policy allow network --sandbox <vm> <hosts base>` | feito: o setup roda dentro da VM, e o item 6 confere |
| 3. Hosts do Playwright | com `e2e sim`: pendente, com `sbx policy allow network --sandbox <vm> cdn.playwright.dev,playwright.download.prss.microsoft.com`. Com `e2e não`: a linha não aparece | igual ao host |
| 4. Secret do GitHub | pendente: `sbx secret set github --command 'gh auth token'` | `token marcador`: feito. `token ausente`: pendente, com o comando. `token real`: pendente, com o comando e o aviso de que o `GH_TOKEN` da VM tem formato de token real |
| 5. Plugin e hooks do git | `sbx run --name <vm>`, marcado como feito pela regra de hoje (hooks `ok`, `atualizado` ou instalados agora) | igual ao host |
| 6. Conferir a rede | pendente: `sbx policy log <vm>` | pendente: `sbx policy log <vm>`, lembrando que ele também confere os itens 1 e 3 |

Nos dois contextos, o checklist fecha com uma linha: "`<vm>` é o nome padrão do `sbx` para esta pasta. Se a VM do projeto tem outro nome, confira na coluna SANDBOX do `sbx ls`, no host, e use esse nome nos comandos."

Item "feito" aparece no checklist marcado como feito, com o motivo. Ele não some.

Fora do modo `sbx`, o setup não roda o `sbx-context.sh`, e nada muda.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O `scripts/sbx-context.sh`, com o arquivo de sinal presente (variável `FABRICA_SBX_PERSISTENT_FILE` apontando para um arquivo que existe), imprime `onde vm` | unitário — `scripts/test-sbx-context.sh` |
| CA2 | Com o arquivo de sinal ausente e o `PROXY_CA_CERT_B64` não vazio, imprime `onde vm`. Com o arquivo ausente e o `PROXY_CA_CERT_B64` vazio ou indefinido, imprime `onde host` | unitário — `scripts/test-sbx-context.sh` |
| CA3 | A linha `nome` é `claude-` mais o nome da pasta do topo do repositório, sem transformação, também quando o script roda numa subpasta (ex.: projeto em `/tmp/x/kairo`, rodando em `kairo/src`, dá `nome claude-kairo`) | unitário — `scripts/test-sbx-context.sh` |
| CA4 | A linha `token`: `token ausente` com o `GH_TOKEN` vazio ou indefinido; `token real` quando ele casa com `gh[opsu]_[A-Za-z0-9]{30,}\|github_pat_`, a mesma expressão do `scripts/test-sandbox-acceptance.sh`; `token marcador` nos outros casos | unitário — `scripts/test-sbx-context.sh` |
| CA5 | A linha `e2e`: `e2e sim` quando o `Makefile` do topo do repositório tem uma linha que começa com `e2e:`; `e2e não` sem `Makefile`, ou com ele sem essa linha (um `test-e2e:` ou um `e2e` citado no meio de uma linha não contam) | unitário — `scripts/test-sbx-context.sh` |
| CA6 | O script imprime sempre as quatro linhas, nesta ordem: `onde`, `nome`, `token`, `e2e`. Sai com 0. Fora de um repositório git e sem `--project`, sai com 1 e uma mensagem em stderr. Com `--project <dir>` inexistente, sai com 1. Uma opção desconhecida sai com 1 | unitário — `scripts/test-sbx-context.sh` |
| CA7 | O script não roda nenhum comando `sbx` e não grava nenhum arquivo | unitário — `scripts/test-sbx-context.sh`, com um `sbx` falso no `PATH` que grava um marcador quando é chamado, e com a lista de arquivos do projeto igual antes e depois |
| CA8 | O checklist do `skills/setup/SKILL.md` usa `<vm>`, vindo da linha `nome`, em todo comando `sbx` (`create`, `policy allow`, `run`, `policy log`), e nenhum comando cita `<projeto>` como nome da VM | manual — leitura do `skills/setup/SKILL.md` na branch |
| CA9 | O setup no host, num projeto `sbx` com `make e2e`, mostra os itens 1 a 4 e o 6 pendentes, com `--name claude-<pasta>` no item 2, a linha do Playwright no item 3 e a linha do `sbx ls` no fim. Num projeto sem `make e2e`, a linha do Playwright não aparece | manual — `claude --plugin-dir <clone>` na branch, no host, num repositório de teste com `.fabrica/isolamento.txt` em `sbx`, com e sem um `Makefile` com `e2e:` |
| CA10 | O setup rodado dentro de uma VM do `sbx` mostra os itens 1, 2 e 3 (base) como feitos e não manda criar a VM. O item 4 aparece feito com o secret entregue ao proxy. O item 6 fica pendente, com `sbx policy log claude-<pasta>` | depois do merge — depende de o usuário abrir a sessão numa VM real do `sbx` no host e instalar nela o plugin publicado |
| CA11 | Na mesma VM do CA10, num projeto com `make e2e` (o kairo), o item 3 mostra a linha do Playwright como pendente | depois do merge — mesmo motivo do CA10 |
| CA12 | Em `docs/guias/isolamento-do-agente.md`, todo comando `sbx` com nome de VM usa `claude-<projeto>`. O guia diz que esse é o nome padrão do `sbx` (`<agente>-<pasta>`), descreve o checklist no host e na VM e manda conferir com `sbx ls` uma VM de outro nome | manual — leitura do guia na branch; `grep -n -- '--name <projeto>\|--sandbox <projeto>\|policy log <projeto>\|policy ls <projeto>' docs/guias/isolamento-do-agente.md` não acha nada |
| CA13 | O `scripts/test-sandbox-acceptance.sh`, com tudo `ok`, termina com `confira no host: sbx policy log claude-<pasta do repositório>` | unitário — `grep` da linha final no script; a execução completa só roda na VM |
| CA14 | `CLAUDE.md` cita `bash scripts/test-sbx-context.sh` entre os testes, e `.claude-plugin/plugin.json` sobe para `0.36.0` | manual — leitura na branch |

## Fora de escopo
- Rodar comandos `sbx` pelo setup ou pelo script, para conferir a política, o secret ou o nome da VM. A regra do setup continua: o checklist é do usuário ([ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md)).
- Renomear ou recriar VMs que já existem com outro nome. O guia só manda conferir com `sbx ls`.
- Tratar nomes de pasta com caracteres que o `--name` do `sbx` recusa (fora de letras, números, hífens e pontos). O script imprime o nome sem transformação, e a linha do `sbx ls` cobre o caso.
- Mudar o `test-sandbox-acceptance.sh` além da última linha, ou fazer o teste de aceite usar o `sbx-context.sh`.
- O dispatcher e o isolamento do job (#106).

## Desenho técnico
**Arquivos e módulos:**
- `scripts/sbx-context.sh` (novo): diz onde o setup roda e os dados do checklist.
- `scripts/test-sbx-context.sh` (novo): testes do script, no padrão do `scripts/test-setup-isolation.sh` (projeto temporário, função `check`, resumo no fim e saída 1 se algo falhar).
- `skills/setup/SKILL.md`: a seção "Checklist do modo `sbx`" passa a rodar o `sbx-context.sh` e segue a tabela de "Comportamento esperado". A seção "Responder" e as regras não mudam, fora a referência ao checklist.
- `docs/guias/isolamento-do-agente.md`: troca `<projeto>` por `claude-<projeto>` nos comandos `sbx` (seção "Modo `sbx`", "Ampliar os domínios", "Teste de aceite", "Verificação de integração" e "Hosts da verificação de integração"), explica a convenção e descreve o checklist dentro da VM.
- `scripts/test-sandbox-acceptance.sh`: a última linha passa a `sbx policy log claude-$(basename "$root")`.
- `CLAUDE.md`: cita o `test-sbx-context.sh` em `scripts/`.
- `.claude-plugin/plugin.json`: `version` de `0.35.1` para `0.36.0`.

**Dados:** nenhum.

**Interfaces:**
- `scripts/sbx-context.sh [--project <dir>]`
  - Sem `--project`, o projeto é o `git rev-parse --show-toplevel` do diretório atual.
  - Saída, sempre quatro linhas: `onde vm|host`, `nome claude-<pasta>`, `token marcador|ausente|real`, `e2e sim|não`.
  - Sinal de VM: o arquivo `${FABRICA_SBX_PERSISTENT_FILE:-/etc/sandbox-persistent.sh}` existe, ou o `PROXY_CA_CERT_B64` não está vazio. A variável `FABRICA_SBX_PERSISTENT_FILE` serve aos testes.
  - Código de saída: 0 em sucesso; 1 em uso inválido, projeto inexistente ou fora de um repositório git sem `--project`.

**Decisões:**
- Nome da VM `claude-<projeto>`, com `--name claude-<projeto>` explícito no `sbx create` (recomendação da triagem). As VMs existentes seguem esse padrão, e ele é o nome padrão do `sbx` 0.51.0 (`--name ... default: <agent>-<workdir>`, no `sbx create --help`), o que confirma o "a confirmar" da issue. O `--name` explícito deixa o comando igual mesmo se o padrão mudar. Alternativa descartada: `<projeto>`, que obrigaria a recriar as VMs existentes.
- Dentro da VM, os itens já cumpridos aparecem como feitos, e não somem (recomendação da triagem), seguindo a convenção do setup, que já marca o item 5 como feito. Ficam pendentes o Playwright, com `make e2e`, e o `sbx policy log`. Alternativa descartada: tirar os itens do checklist, o que esconde do usuário o que foi pressuposto.
- Item 4 marcado como feito só com `token marcador` (recomendação da triagem), pela mesma expressão do `token-marcador` do teste de aceite. Alternativa descartada: marcar o item sempre, o que esconde um secret faltando.
- Detecção da VM num script com teste, chamado pelo setup (recomendação da triagem). Os sinais são o `/etc/sandbox-persistent.sh`, que a documentação do `sbx` descreve como lido pelo Bash dentro da sandbox, e o `PROXY_CA_CERT_B64`, que a documentação manda decodificar de dentro da sandbox. Vale um ou outro, para a detecção não depender de um sinal só. Alternativa descartada: o `home-isolado` do teste de aceite, que também passa numa máquina sem chaves SSH.
- Nome nos comandos pela convenção, com a linha do `sbx ls` (recomendação da triagem). Nem a documentação nem a ajuda do `sbx` 0.51.0 citam uma variável com o nome da sandbox dentro dela, então o script não tenta descobrir o nome. Alternativa descartada: ler o hostname, um comportamento não documentado.
- Linha do Playwright pela detecção do alvo `e2e:` no `Makefile`, nos dois contextos. Ela substitui a frase condicional de hoje, que passou despercebida no kairo e no ankyra (corpo da issue). Alternativa descartada: manter a frase condicional sempre, que é o que falhou.
- `make e2e` detectado por uma linha que começa com `e2e:` no `Makefile` do topo. É a convenção da fábrica para o comando de ponta a ponta (`skills/implementar/SKILL.md`). Alternativa descartada: rodar `make -n e2e`, que executa o `make` só para responder a uma pergunta de texto.

**Fontes da documentação:**
- Docker Sandboxes (`sbx`) 0.51.0: ajuda local `sbx create --help` e `sbx run --help` (nome padrão `<agent>-<workdir>`), `sbx --help` e `sbx exec --help` (nenhuma variável com o nome da sandbox).
- Docker Sandboxes, Context7 `/websites/docker_ai_sandboxes`: `/etc/sandbox-persistent.sh` (usage, "Set environment variables") e `PROXY_CA_CERT_B64` (troubleshooting). Versão não confirmada: a documentação é a atual do site, sem número de versão.
- gh: nenhum comando do `gh` no desenho.

**ADR:** nenhum. A decisão cabe na [ADR 0010](../docs/adr/0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md), que já deixa a VM e o checklist com o usuário.

## Testes
- `bash scripts/test-sbx-context.sh` cobre os CAs 1 a 7, com projetos temporários (`git init`), `FABRICA_SBX_PERSISTENT_FILE` apontando para um arquivo do diretório temporário, presente ou ausente, `PROXY_CA_CERT_B64` e `GH_TOKEN` controlados por `env`, e um `sbx` falso no `PATH` para o CA7. Os valores de `GH_TOKEN` do teste são inventados, no formato das expressões, sem nenhum token real.
- O CA13 sai de um `grep` no `scripts/test-sandbox-acceptance.sh`.
- Os CAs 8, 12 e 14 são de leitura. O CA9 roda o setup com `claude --plugin-dir <clone>` no host. Os CAs 10 e 11 dependem de uma VM real e ficam para depois do merge.
- Os outros testes de `scripts/` (`test-setup-isolation.sh`, `test-protect-main.sh` e os demais citados no `CLAUDE.md`) continuam passando.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Sinal da VM não testado numa VM real:** os dois sinais vêm da documentação, não de um teste. Se nenhum existir na VM, o setup mostra o checklist do host, que é o comportamento de hoje, só que com o nome certo. Os CAs 10 e 11 conferem depois do merge.
- **Falso positivo no host:** um host com o `PROXY_CA_CERT_B64` definido por outro motivo, ou com um `/etc/sandbox-persistent.sh`, leva ao checklist da VM. O item 6 continua pendente, e o `sbx policy log` mostra o que falta.
- **Itens 1 e 3 presumidos na VM:** a VM existir não prova a política global `deny-all` nem a regra base de rede. O checklist da VM diz que o item 6 confere os dois.

## Histórico
- 2026-11-16: criação.
- 2026-11-16: aprovada.
