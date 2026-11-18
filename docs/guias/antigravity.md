# Antigravity

Este guia é para quando você quer usar a fábrica pelo Antigravity CLI (`agy`) em vez do Claude Code. A fábrica é um plugin do Claude Code, e o `agy plugin install <clone-da-fábrica>` converte skills, agentes e hooks para o formato dele. O resultado da conversão depende das versões dos dois lados: este guia registra o que foi testado com o **plugin 0.38.0** e o **`agy` 1.5.10**, em 2026-11-18, numa VM do `sbx` com modelo real (fase 0 em [#149](https://github.com/ftenorio99/fabrica/issues/149), pontos restantes em [#162](https://github.com/ftenorio99/fabrica/issues/162)).

## O que funciona
- **Instalação:** `agy plugin install` converte as 12 skills (comandos `/fabrica:*`), o agente `revisor` e os hooks `PreToolUse` e `SessionStart`.
- **Proteções:** os hooks de proteção (`protect-main.sh`, `protect-production.sh`) negam de verdade, também com `--dangerously-skip-permissions`.
- **Etapas:** os comandos `/fabrica:*` rodam em modo `-p` e recebem argumento (fase 0 da #149).
- **Perguntas ao usuário:** o equivalente ao `AskUserQuestion` é a ferramenta `ask_question`. Nas etapas que perguntam (`prd`, `setup`), a pergunta sai como chamada da ferramenta, não como texto solto.
- **Revisão automática:** a chamada do revisor funciona pelo fallback — um subagente genérico registrado com o conteúdo de `agents/revisor.md` (via `define_subagent`). No teste, ele devolveu a tabela de critérios de aceite com evidência e recusou um pedido de alterar arquivo, mantendo o repositório intacto.

## O que funciona com ressalva
- **Modo `-p` não espera resposta:** o `ask_question` retorna imediatamente com resposta vazia (`A1:`), sem bloquear. Cabe ao modelo parar ou seguir; no teste, com instrução explícita de parar na primeira pergunta, ele parou sem responder por conta própria. Em sessão interativa, a pergunta chega ao usuário normalmente.
- **Restrição de ferramentas do revisor:** o `tools: Read, Grep, Glob, Bash` do frontmatter não vira restrição no `agy` — o `define_subagent` atrela o shell a `EnableWriteTools`, sem opção somente leitura. O comportamento só-leitura do revisor fica garantido apenas pelas instruções do agente.

## O que não funciona
- **Subagente `revisor` convertido:** a instalação reporta "1 installed", mas nenhuma chamada o alcança: `agy agents` lista vazio, `--agent revisor` dá `unknown agent` e `invoke_subagent` dá `not found or not allowed`. O `revisar` precisa usar o fallback acima. Conserto acompanhado na [#177](https://github.com/ftenorio99/fabrica/issues/177).
- **Aviso do `SessionStart`:** o hook imprime texto puro ("Os hooks do git da fábrica não estão instalados…"), mas o `agy` espera JSON (`{"injectSteps":[...]}`) e falha no parsing (`proto: syntax error`, no log). O aviso não chega ao modelo — confira os hooks do git você mesmo (`bash scripts/setup-githooks.sh --check` no clone, ou `/fabrica:setup`). Conserto acompanhado na [#178](https://github.com/ftenorio99/fabrica/issues/178).

## Fontes
Os comandos exatos e as saídas completas dos testes estão no comentário de registro da [#162](https://github.com/ftenorio99/fabrica/issues/162) e, para a fase 0, na [#149](https://github.com/ftenorio99/fabrica/issues/149). As regras do fluxo valem iguais às do Claude Code: veja [Comandos](../comandos.md) e [Fluxo](../fluxo.md).
