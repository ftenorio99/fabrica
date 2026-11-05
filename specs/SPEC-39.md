# SPEC-39: Verificar a versão mínima do gh no setup e nas etapas da fábrica

**Issue:** #39 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-05

## Contexto
Todas as etapas da fábrica leem e escrevem no GitHub pelo `gh`. Numa implementação, o `gh pr edit` falhou com o erro de descontinuação dos Projects clássicos (`repository.pullRequest.projectCards`), e o agente precisou atualizar o PR pela API REST. A causa era o `gh` 2.46.0 do repositório do Ubuntu. O bug é o [cli/cli#11983](https://github.com/cli/cli/issues/11983), e o `gh` 2.103.3 do repositório oficial não o tem. Hoje a fábrica só descobre um `gh` antigo quando um comando falha no meio de uma etapa.

## Objetivo
A fábrica confere o `gh` antes de usá-lo e, se ele estiver ausente, sem login ou abaixo da versão mínima, diz o que fazer em vez de falhar no meio de uma etapa.

## Comportamento esperado

### Script de checagem
`bash scripts/check-gh.sh` imprime uma única linha, conferindo nesta ordem:

| Situação | Linha | Código de saída |
|---|---|---|
| `gh` não está no `PATH` | `ausente` | 1 |
| Versão abaixo da mínima | `desatualizado <versão> <mínima>` | 1 |
| Versão que o script não consegue ler | `desatualizado desconhecida <mínima>` | 1 |
| Na mínima ou acima, mas `gh auth status` falha | `sem-login <versão>` | 1 |
| Na mínima ou acima e autenticado | `ok <versão>` | 0 |

Regras do script:
- A versão sai da primeira linha de `gh --version` (`gh version 2.103.3 (2026-10-26)`).
- A comparação é numérica, campo a campo: 2.103.3 fica acima de 2.82.1, e 2.9.0 fica abaixo.
- **Versão desatualizada:** o script não roda `gh auth status`, porque o primeiro passo é atualizar.
- **Fonte única:** a versão mínima é a variável `MIN_GH_VERSION` no início do script, com um comentário que cita o cli/cli#11983 e o PR #11987.

### `/fabrica:setup`
Ganha um passo de `gh`, antes das labels, que roda o `check-gh.sh` do plugin:
- **`ok`:** segue para as labels.
- **`desatualizado`:** mostra a versão atual e a mínima, e explica o erro dos Projects clássicos. Mostra também o comando de instalação pelo repositório oficial para Debian/Ubuntu, copiado de `docs/install_linux.md` do cli/cli, e o link para as outras plataformas (`https://github.com/cli/cli#installation`). Não roda `sudo` nem instala nada. Depois, segue para as labels e os hooks, porque o `gh label create` funciona na versão antiga.
- **`ausente`:** para o setup e indica o link de instalação.
- **`sem-login`:** para o setup e indica `gh auth login`.
- **Resposta:** a do setup passa a começar com a linha do `gh` (`ok 2.103.3`, `desatualizado 2.46.0 2.82.1` etc.).

### Etapas que escrevem no GitHub
As etapas `triagem`, `spec`, `implementar`, `revisar`, `backlog` e `prd` rodam o `check-gh.sh` no início, logo depois de guardar o instante de início, quando a etapa guarda um.
- **`ok`:** a etapa segue.
- **Qualquer outra linha:** a etapa para antes de ler ou escrever no GitHub. Ela diz no chat a linha do script e o que fazer: `/fabrica:setup` para `desatualizado`, e a instalação ou o `gh auth login` nos outros casos. Não comenta na issue, não muda labels e não publica linha de custo.
- No `/fabrica:avancar`, uma etapa que para assim aparece como "sem avanço", com o motivo. O `avancar` não muda.
- **Exceção do `/fabrica:prd`:** ele só usa o `gh` no passo das labels, no fim. Por isso, roda a checagem nesse passo, e não no início. Se a linha não for `ok`, ele não cria as labels, mostra a linha e indica `/fabrica:setup`, mas o PRD já escrito fica, como hoje acontece sem remote.

### Plano B por REST
O plano B vale só para falha do próprio `gh` num `gh pr edit` ou num `gh issue edit`. A falha conta como do próprio `gh` quando a mensagem é um erro `GraphQL:` que cita algo que o comando não pediu, como `projectCards` ou "Projects (classic)".
- Nesse caso, a etapa refaz o mesmo efeito pela API REST:
  - corpo ou título do PR: `gh api -X PATCH repos/<dono>/<repo>/pulls/<nº> -F body=@<arquivo>` (ou `-f title=...`);
  - incluir uma label: `gh api -X POST repos/<dono>/<repo>/issues/<nº>/labels -f "labels[]=<label>"`;
  - remover uma label: `gh api -X DELETE repos/<dono>/<repo>/issues/<nº>/labels/<label>`.
- A etapa diz no chat que usou o plano B, com o comando que falhou e a mensagem resumida.
- **Fora do plano B:** uma label que não existe e qualquer outro erro continuam com a regra atual. Para a label que não existe, a etapa para e indica o `/fabrica:setup`.
- As regras do plano B ficam num único arquivo de apoio, `skills/setup/gh.md`, citado pelas seis etapas.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | Com um `gh` falso na 2.46.0, `check-gh.sh` imprime `desatualizado 2.46.0 <mínima>` e sai com código 1, sem chamar `gh auth status`. O passo do `gh` no `skills/setup/SKILL.md` manda mostrar a versão atual, a mínima e o comando de instalação, e proíbe rodar `sudo`. | unitário (`scripts/test-check-gh.sh`) e manual: leitura |
| CA2 | Com um `gh` falso na mínima e em 2.103.3, os dois autenticados, o script imprime `ok <versão>` e sai com 0. Com 2.9.0, imprime `desatualizado`, o que prova que a comparação é numérica. O setup segue para as labels com `ok`. | unitário e manual: leitura |
| CA3 | Sem `gh` no `PATH`, o script imprime `ausente`. Com um `gh` falso cujo `auth status` falha, imprime `sem-login <versão>`. Uma versão ilegível sai como `desatualizado desconhecida <mínima>`. Nos três casos, o código é 1, e o setup manda parar com a instrução de cada caso. | unitário e manual: leitura |
| CA4 | Os `SKILL.md` de `triagem`, `spec`, `implementar`, `revisar` e `backlog` rodam o `check-gh.sh` no início e param, sem escrever no GitHub, quando a linha não é `ok`. O do `prd` roda a checagem no passo das labels e, sem `ok`, pula as labels e indica o `/fabrica:setup`. | unitário: o teste confere, com `grep`, que cada um dos seis cita `check-gh.sh` |
| CA5 | `skills/setup/gh.md` descreve o plano B: quando vale, quais são os comandos REST, o aviso no chat e o que fica fora dele. As seis etapas citam esse arquivo. | manual: leitura; unitário: `grep` da citação |
| CA6 | A versão mínima `2.82.1` aparece num único arquivo do plugin, `scripts/check-gh.sh`, fora de `specs/` e do próprio teste. `bash scripts/test-check-gh.sh` cobre os casos de CA1 a CA3. | unitário |
| CA7 | `docs/primeiros-passos.md`, `docs/solucao-de-problemas.md`, `docs/comandos.md` (setup) e o `README.md` citam a checagem, remetendo ao script para a versão, e o `plugin.json` sobe um minor. | manual: leitura |

## Fora de escopo
- Instalar ou atualizar o `gh` automaticamente.
- Trocar os `gh issue edit` e `gh pr edit` por REST como padrão.
- Checar a versão de outras ferramentas (Docker, Node, pnpm).
- Mudar o `/fabrica:avancar`, o `/fabrica:status` e o `/fabrica:metricas`. O `status` e o `metricas` só leem.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/check-gh.sh` (novo): a checagem e `MIN_GH_VERSION`.
- `scripts/test-check-gh.sh` (novo): os casos com um `gh` falso num diretório temporário no começo do `PATH`. O caso `ausente` usa um `PATH` só com as ferramentas de que o script precisa. O teste também faz os `grep` de CA4 a CA6.
- `skills/setup/SKILL.md`: o passo novo do `gh`, a resposta e o `description`.
- `skills/setup/gh.md` (novo): o que cada linha do script significa para uma etapa e o plano B.
- `skills/{triagem,spec,implementar,revisar,backlog,prd}/SKILL.md`: a checagem no início e a citação do `gh.md` nas regras.
- `docs/primeiros-passos.md`, `docs/solucao-de-problemas.md`, `docs/comandos.md`, `README.md`.
- `.claude-plugin/plugin.json`: 0.15.0.

**Interfaces:** `bash scripts/check-gh.sh`, sem argumentos. Ele imprime uma linha, conforme a tabela do script, e sai com 0 só no `ok`. As etapas o chamam pelo caminho do plugin: `bash <diretório base da etapa>/../../scripts/check-gh.sh`.

**Decisões:**
- **Versão mínima 2.82.1:** é a primeira release com o PR #11987, que corrige a detecção da descontinuação dos Projects clássicos no `gh pr edit`. A falha sem nenhuma opção de projeto, a do cli/cli#11983, já não acontecia na 2.82.0, segundo a própria issue, então a 2.82.1 cobre os dois casos. Alternativa descartada: a 2.82.0, que ainda falha com `--add-project` e `--remove-project`.
- **O `/fabrica:prd` também roda a checagem, mas só no passo das labels:** ele escreve no GitHub só ali, e um `gh` sem login não deve impedir a entrevista nem a escrita do PRD local. Alternativas descartadas: deixá-lo de fora, o que manteria um caminho que falha no meio, e checar no início, o que bloquearia um PRD que nem usa o GitHub.
- **No setup, `desatualizado` avisa e segue:** as labels e os hooks funcionam com o `gh` antigo, e o usuário sai do setup sabendo o que atualizar. Já `ausente` e `sem-login` param, porque nada do resto funciona. Alternativa descartada: parar também no `desatualizado`, o que obrigaria rodar o setup duas vezes.
- **Nas etapas, qualquer linha que não seja `ok` para:** a etapa ia falhar de qualquer jeito, e parar antes evita um estado pela metade na issue. Alternativa descartada: só avisar e seguir, que é o problema da issue.
- **Plano B só para erro `GraphQL:` que cita algo que o comando não pediu:** esse é o sinal do bug do `gh`. Um erro de label, de permissão ou de rede continua parando a etapa. Alternativa descartada: plano B para qualquer falha, que esconderia erros do usuário.
- **Regras do plano B num arquivo só, `skills/setup/gh.md`:** as seis etapas citam o arquivo, como já fazem com o `licao/formato.md`. Alternativa descartada: copiar o texto nas seis skills.

**Fontes da documentação:**
- GitHub CLI 2.82.1: notas da release `v2.82.1` (`gh api repos/cli/cli/releases/tags/v2.82.1`), que trazem o PR #11987. Também os comentários do cli/cli#11983, consultados em 2026-11-05.
- Instalação no Debian/Ubuntu: `docs/install_linux.md` do repositório `cli/cli`, consultado em 2026-11-05.
- Formato de `gh --version` e `gh auth status`: conferido no `gh` 2.103.3 desta máquina.

**ADR:** nenhum.

## Testes
- `bash scripts/test-check-gh.sh`: as versões 2.46.0, 2.9.0, 2.82.1 e 2.103.3, a versão ilegível, `ausente` e `sem-login`, e os `grep` de CA4, CA5 e CA6.
- `bash scripts/test-protect-main.sh`, `bash scripts/test-stage-usage.sh` e `bash scripts/test-costs.sh` continuam passando.
- **Manual:** rodar `bash scripts/check-gh.sh` nesta máquina e conferir `ok 2.103.3`.
- O repositório não tem `make lint`, `make test` nem CI.

## Riscos e dúvidas
- **Formato da saída do `gh`:** se `gh --version` mudar de formato, a checagem sai `desatualizado desconhecida`, e as etapas param. O teste cobre esse caso, e a mensagem diz o que aconteceu.
- **Plano B incompleto:** os três comandos REST cobrem o que as etapas fazem hoje com `gh pr edit` e `gh issue edit`, que é o corpo e o título do PR e as labels. Outro uso futuro precisaria entrar no `gh.md`.
- **Custo da checagem:** ela roda `gh --version` e `gh auth status`, que é uma chamada de rede, em cada etapa. Ela custa menos de 1 s.

## Histórico
- 2026-11-05: criação.
- 2026-11-05: aprovada.
