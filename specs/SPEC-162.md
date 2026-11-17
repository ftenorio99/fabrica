# SPEC-162: Antigravity: testar o revisor, as perguntas ao usuário e o aviso de início de sessão

**Issue:** #162 · **PRD:** nenhuma (o Antigravity está fora do escopo do PRD, que fica "só no Claude Code"; mesma situação da #161, ver Riscos) · **Classe:** documentacao · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-17

## Contexto
A fase 0 da #149 mostrou que, com o plugin instalado pelo `agy plugin install`, os hooks de proteção negam de verdade, `/fabrica:status` roda e recebe argumento, e só `metricas` e `status` ficam visíveis ao modelo. Três pontos ficaram sem teste: o subagente `revisor`, o equivalente do `AskUserQuestion` e o aviso do `SessionStart`, que sai como texto puro quando o `agy` espera `{"injectSteps":[...]}`. Esta issue testa os três com modelo real e registra o que acontece, sem consertar nada.

O que mudou desde a fase 0: o plugin está na 0.38.0 e o `agy` na 1.5.10. Os testes valem para essas versões.

## Objetivo
Os três pontos têm um resultado registrado (comando usado e saída relevante), cada falha virou uma issue de `fix` separada, e o registro fica na issue e num guia em `docs/`.

## Comportamento esperado
**Onde roda.** Num ambiente com o `agy` autenticado e com o `sbx`, a VM da fase 0 (`claude-kairo`, com os CLIs logados pelo usuário) e um projeto de estudo fora do repositório do kairo, numa branch que não seja a `main`. O plugin é instalado do clone da branch desta issue (`agy plugin install <clone>`); a spec e o guia não mudam o plugin, então ele é o da `main`. Se o `agy` não estiver autenticado no ambiente da etapa, a etapa para com a checklist de ação externa ([ADR 0012](../docs/adr/0012-acao-externa-com-checklist.md)): "autenticar o `agy` na VM" e "confirmar o projeto de estudo".

**Os três testes.** Cada um grava no comentário da issue o comando exato, a saída relevante (cortada, sem credencial) e a conclusão `funciona`, `funciona com ressalva` ou `falha`.

| # | Ponto | O que fazer | O que registrar |
|---|---|---|---|
| 1 | `revisor` | No projeto de estudo, com uma branch de estudo que tenha uma spec (`specs/SPEC-<nº>.md`) e um diff pequeno, pedir ao `agy -p` que revise a branch com o agente `revisor` (a mesma chamada que o `revisar` faz). Depois pedir ao mesmo agente que altere um arquivo. | Se o agente convertido existe e roda; se devolve a tabela de CAs e os achados; se o `tools: Read, Grep, Glob, Bash` do frontmatter vira restrição no `agy`; se o pedido de alterar um arquivo é recusado ou obedecido; o `git status` e a contagem de commits antes e depois. |
| 2 | Perguntas ao usuário | Listar as ferramentas do `agy` (pedindo ao modelo ou pelo `--output-format stream-json`) e rodar `/fabrica:prd` e `/fabrica:setup` no projeto de estudo com `-p`, dizendo ao modelo que pare na primeira pergunta ao usuário. | O nome da ferramenta equivalente ao `AskUserQuestion`, se existir; se a pergunta chega como chamada da ferramenta ou como texto; se o modelo responde por conta própria em vez de esperar. |
| 3 | `SessionStart` | Com os hooks do git da fábrica ausentes (`core.hooksPath` global sem a pasta da fábrica), abrir uma sessão do `agy` no projeto de estudo e perguntar ao modelo o que o aviso de início de sessão disse. Rodar também o comando do hook de `hooks/hooks.json` à mão, para ver a saída crua. | Se o texto "Os hooks do git da fábrica não estão instalados…" chega ao modelo; o que o `agy` faz com a saída em texto puro; se há registro do hook no log do `agy` (`--log-file`). |

**Observações sobre o teste 2.** O `spec` não usa o `AskUserQuestion`: ele pergunta pela própria issue, com `precisa-info`, e não é afetado. As etapas que usam a ferramenta são o `prd`, o `setup`, o `licao`, o `backlog` e o `retro`, e o teste cobre o `prd` e o `setup`. O `setup` só pergunta antes de mudar a máquina, e o teste confere, depois, que o `core.hooksPath` global da VM ficou como estava.

**Falhas.** Cada `falha` vira uma issue de `fix`, com título e corpo em português, que cita a #162, o comando que falhou e a saída. O corpo descreve o comportamento esperado em termos dos dois contratos (Claude Code e `agy`), como a #150, sem mudar o comportamento no Claude Code. As issues nascem sem a label `agente`: o usuário decide quando puxar. Uma `ressalva` não vira issue; entra no guia. Sem falha, o comentário diz que nenhuma issue foi aberta.

**O registro.**
- Um comentário na #162 com o resultado dos três testes, que é o que a issue pede.
- O guia `docs/guias/antigravity.md`, no PR da issue, com o resultado de cada ponto em linguagem de manual (o que funciona, o que não funciona e o que fazer), as versões testadas (plugin, `agy`) e o link das issues de falha. O guia entra na tabela "Guias" de `docs/README.md`. Ele explica e remete: não copia regras nem tabelas das skills.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O comentário da #162 tem o resultado do teste do `revisor`, com o comando, a saída relevante e a conclusão, e diz se o frontmatter `tools` restringe o agente e se o pedido de alterar um arquivo foi recusado. | manual — `agy -p` na VM; o revisor lê o comentário |
| CA2 | O comentário traz o resultado das perguntas ao usuário: o nome da ferramenta equivalente (ou "não há"), como a pergunta chega e o que o modelo faz no `prd` e no `setup`, e registra que o `spec` não usa a ferramenta. | manual — `agy -p` na VM |
| CA3 | Depois do teste do `setup`, o `git config --global --get core.hooksPath` da VM é igual ao de antes, e o comentário mostra os dois valores. | manual — `git config` antes e depois, na VM |
| CA4 | O comentário traz o resultado do `SessionStart`: se o texto do aviso chega ao modelo, a saída crua do comando do hook e o que o `agy` registra. | manual — `agy` na VM com os hooks do git ausentes |
| CA5 | Cada ponto com conclusão `falha` tem uma issue de `fix` aberta, em português, sem a label `agente`, que cita a #162, o comando e a saída; o comentário da #162 lista os números. Sem falha, o comentário diz "nenhuma issue aberta". | manual — `gh issue list --search "#162" --state open`, depois do registro |
| CA6 | Nenhuma saída colada no comentário, no guia ou nas issues traz token, chave ou credencial do `agy`. | manual — o revisor lê o comentário, o guia e as issues |
| CA7 | `docs/guias/antigravity.md` existe, traz os três resultados, as versões testadas (plugin e `agy`) e o link das issues de falha, e `docs/README.md` o lista na tabela "Guias". | manual — `git diff origin/main...HEAD --stat` e leitura do guia |
| CA8 | O PR não altera nada fora de `specs/` e `docs/`: o plugin, os hooks, as skills e o `agents/revisor.md` ficam como estão. | manual — `git diff origin/main...HEAD --stat` |

## Fora de escopo
- Consertar qualquer falha encontrada: cada uma vira uma issue de `fix` separada.
- Alterar `hooks/`, `agents/`, `skills/` ou a versão do plugin.
- Testar o OpenCode (o adaptador dele tem as issues próprias) ou retestar o que a fase 0 da #149 já provou: os hooks de negativa, o `/fabrica:status` e o argumento.
- Rodar uma etapa inteira do fluxo (`implementar`, `revisar`) no `agy`.
- Testar as etapas `licao`, `backlog` e `retro`, que usam a mesma ferramenta de perguntas do `prd` e do `setup`.

## Desenho técnico
**Arquivos e módulos:**
- `docs/guias/antigravity.md` (novo): o guia com o resultado.
- `docs/README.md`: uma linha na tabela "Guias".
- `specs/SPEC-162.md`: esta spec.
- Nada em `.claude-plugin/plugin.json`: não há mudança de comportamento do plugin, então a versão não sobe.

**Dados:** nenhum.

**Interfaces:** nenhuma. Os comandos do teste são os do `agy` 1.5.10: `agy -p "<prompt>"` (`--print`), `--output-format stream-json`, `--log-file <caminho>`, `--agent <nome>` e `agy plugin install <caminho>`, vistos em `agy --help` e `agy plugin --help`. A forma de chamar o subagente `revisor` no `agy` não está na ajuda: o teste 1 descobre qual funciona (por exemplo, pedir ao modelo, ou `--agent revisor`) e registra a que serviu.

**Decisões:**
- O registro vai no comentário da issue e no guia `docs/guias/antigravity.md`, no PR (recomendação da triagem) — sem PR da branch a issue não sai do estado 8 e o `Fixes #162` não fecha sozinho; a #149 também aceita "aqui ou num documento em `docs/`". Alternativa descartada: só o comentário, com o usuário fechando a issue na mão.
- A etapa `implementar` roda os testes na VM; sem o `agy` autenticado, para com a checklist de ação externa (recomendação da triagem) — como a SPEC-156 faz com ferramenta sem login e como o ADR 0012 prevê. Alternativa descartada: o usuário roda os testes e cola o resultado.
- Uma issue de `fix` por falha, com o mesmo cuidado da #150 (recomendação da triagem) — o conserto aceita os dois contratos sem mudar o Claude Code. Alternativa descartada: uma issue só com todas as falhas, que mistura o `fix` do revisor com o do hook e não fecha por partes.
- O guia fica em `docs/guias/` e não numa página nova do manual: o manual diz "Guias: situação", e o Antigravity é uma situação (usar a fábrica por outro CLI) que não muda o fluxo. Alternativa descartada: `docs/` solto, sem entrada no índice, que ninguém acharia.
- Os testes usam o modo `-p` do `agy`: o agente não roda etapa interativa com o usuário, e o `-p` mostra o que o modelo faz quando uma pergunta precisa de resposta. Alternativa descartada: sessão interativa, que depende de alguém digitando.

**Fontes da documentação:**
- `agy` 1.5.10 — `agy --help` e `agy plugin --help`, rodados nesta etapa.
- gh 2.104.0 — `gh issue create --help` (`-t`, `-F`, `-l`) e `gh issue view --help`.

**ADR:** nenhum.

## Testes
Não há teste automático: a mudança é um guia e um registro de teste manual. Cada CA acima diz como é conferido, e o que o revisor consegue conferir sem a VM é o CA7 e o CA8, com o `git diff`, e a leitura do comentário, do guia e das issues para o CA1, CA2, CA4, CA5 e CA6. Os CAs que dependem do `agy` autenticado (CA1 a CA4) são conferidos pela evidência que o `implementar` cola no comentário: se não houver como rodar na etapa, o `revisar` pede ao usuário a verificação.

## Passos de produção
nenhum

## Riscos e dúvidas
- **Sem `agy` autenticado ou sem a VM:** nada roda. A etapa para na checklist de ação externa.
- **O guia descreve versões que mudam:** `agy` e plugin saem em versões novas. O guia registra as versões testadas e a data, para quem lê saber até onde vale.
- **O projeto de estudo e a branch de estudo da fase 0 podem ter sido apagados:** a etapa os recria fora do repositório da fábrica e de qualquer projeto real.
- **O modelo pode responder a pergunta por conta própria no `-p`:** é um resultado, não um erro do teste, e vai para o registro como `funciona com ressalva` ou `falha`.
- **Fora do PRD:** como na #161, o Antigravity está fora do "só no Claude Code" do PRD. A issue existe por decisão do usuário (#149), e a spec não muda o PRD.

## Histórico
- 2026-11-17: criação.
