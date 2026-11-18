# Antigravity

Este guia é para quando você quer usar a fábrica pelo Antigravity CLI (`agy`) em vez do Claude Code. A fábrica é um plugin do Claude Code, e o `agy plugin install <clone-da-fábrica>` converte skills, agentes e hooks para o formato dele. O resultado da conversão depende das versões dos dois lados: este guia registra o que foi testado com o **plugin 0.38.0** e o **`agy` 1.5.10**, em 2026-11-18, numa VM do `sbx` com modelo real (fase 0 em [#149](https://github.com/ftenorio99/fabrica/issues/149), pontos restantes em [#162](https://github.com/ftenorio99/fabrica/issues/162)). O registro do subagente `revisor` foi testado com o **plugin 0.40.0** e o mesmo `agy` 1.5.10 ([#177](https://github.com/ftenorio99/fabrica/issues/177)).

## O que funciona
- **Instalação:** `agy plugin install` converte as 12 skills (comandos `/fabrica:*`), o agente `revisor` e os hooks `PreToolUse` e `SessionStart`.
- **Proteções:** os hooks de proteção (`protect-main.sh`, `protect-production.sh`) negam de verdade, também com `--dangerously-skip-permissions`.
- **Etapas:** os comandos `/fabrica:*` rodam em modo `-p` e recebem argumento (fase 0 da #149).
- **Perguntas ao usuário:** o equivalente ao `AskUserQuestion` é a ferramenta `ask_question`. Nas etapas que perguntam (`prd`, `setup`), a pergunta sai como chamada da ferramenta, não como texto solto.
- **Subagente `revisor`:** o `agy` registra o agente instalado pelo plugin como subagente, e o `revisar` o chama pelo `invoke_subagent`, com o nome que o `agy` lista. O `agents/revisor.md` declara `tools` como lista YAML, com os nomes do Claude Code e os do `agy` (`read_file`, `run_command`, `manage_task`), e `subagent: true` e `mainAgent: false`. Por ser subagente, `agy --agent revisor` segue recusado: ele não é agente principal de sessão.
- **Revisão automática:** se o revisor não estiver disponível, o `revisar` cai no fallback — um subagente genérico registrado com o conteúdo de `agents/revisor.md` (via `define_subagent`). No teste da #162, ele devolveu a tabela de critérios de aceite com evidência e recusou um pedido de alterar arquivo, mantendo o repositório intacto.
- **Aviso do `SessionStart`:** o hook `hooks/session-start.sh` responde no contrato de quem o chamou. Sob o `agy`, o aviso de hooks do git ausentes sai como `{"injectSteps":[{"systemMessage":{...}}]}`, o formato que a documentação de hooks do `agy` 1.5.10 define para o `SessionStart`; sob o Claude Code, continua texto puro. O teste unitário (`bash scripts/test-session-start.sh`) cobre os dois contratos. A confirmação com o `agy` em uma VM do `sbx` (o modelo relatar o aviso e o log sem erro de parsing) ainda não foi feita: segue na [#178](https://github.com/ftenorio99/fabrica/issues/178).

## O que funciona com ressalva
- **Modo `-p` não espera resposta:** o `ask_question` retorna imediatamente com resposta vazia (`A1:`), sem bloquear. Cabe ao modelo parar ou seguir; no teste, com instrução explícita de parar na primeira pergunta, ele parou sem responder por conta própria. Em sessão interativa, a pergunta chega ao usuário normalmente.
- **Restrição de ferramentas do revisor:** no `agy`, o revisor registrado não tem as ferramentas de editar e criar arquivos (`edit_file`, `write_file`), mas o shell (`run_command`) fica liberado, como o `Bash` no Claude Code — o `agy` não oferece shell somente leitura. A regra de não alterar arquivos pelo shell vem das instruções do agente. No fallback do `define_subagent`, nem essa restrição existe: o shell vem atrelado a `EnableWriteTools`, junto com as ferramentas de editar.

## O que não funciona

## Fontes
Os comandos exatos e as saídas completas dos testes estão no comentário de registro da [#162](https://github.com/ftenorio99/fabrica/issues/162) e, para a fase 0, na [#149](https://github.com/ftenorio99/fabrica/issues/149). As regras do fluxo valem iguais às do Claude Code: veja [Comandos](../comandos.md) e [Fluxo](../fluxo.md).
