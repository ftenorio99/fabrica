# SPEC-230: test: eval enxuto do revisor com bugs plantados e controle limpo

**Issue:** #230 · **PRD:** — (fora do MVP do PRD; apoio às melhorias do revisor #133–#139) · **Fonte do escopo:** — · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** rascunho · **Atualizada em:** 2026-11-26

## Contexto
As issues #133 a #139 alteram as instruções do subagente `revisor` (`agents/revisor.md` e `agy-agents/revisor.md`), mas hoje só existe `scripts/test-revisor-agent.sh`, que valida frontmatter, igualdade de corpo e carregamento do plugin. Não há uma linha de base reproduzível para medir se uma mudança em prosa melhora ou piora a detecção de defeitos reais ou introduz falsos positivos.

## Objetivo
Criar um eval sob demanda (`scripts/test-revisor-quality.sh`) que executa o subagente `revisor` contra uma branch com 3 defeitos plantados e uma branch de controle limpa, conferindo a detecção dos achados esperados e a ausência de falsos positivos.

## Comportamento esperado
1. Ao rodar `bash scripts/test-revisor-quality.sh`, o script cria um repositório git temporário (`mktemp -d`) com um remoto local (`origin`) e uma branch `main` contendo um projeto mínimo em Python com `Makefile` (`lint` e `test`), `AGENTS.md` e uma spec local (`specs/SPEC-1.md`), removendo o diretório temporário ao sair (`trap ... EXIT`).
2. A partir de `main`, o script cria duas branches para avaliação:
   - **Branch com defeitos (`feat/1-bugs-plantados`):** contém exatamente 3 defeitos plantados contra `specs/SPEC-1.md`:
     1. um bug de lógica (cálculo ou regra de limite em desacordo com um CA da spec);
     2. uma falha de segurança (ex.: execução de comando shell com interpolação de entrada do usuário via `shell=True` ou segredo hardcoded);
     3. um teste enfraquecido ou removido (asserção de um CA trocada por verificação trivial ou removida).
   - **Branch de controle limpo (`feat/1-controle-limpo`):** implementa corretamente os CAs de `specs/SPEC-1.md`, com testes reais passando em `make lint` e `make test`, sem defeitos nem mudanças fora do escopo.
3. Para cada branch, o script prepara uma worktree ou checkout limpo da branch e invoca o subagente `fabrica:revisor` via `claude -p --plugin-dir <raiz-do-clone> --agent fabrica:revisor --permission-mode bypassPermissions --output-format text`, passando no prompt o caminho da worktree, a branch, o caminho de `specs/SPEC-1.md` e a instrução de revisar localmente (sem depender de `gh issue view`).
4. O script analisa a saída de texto do `revisor` para cada branch com correspondência flexível (case-insensitive e regex para acomodar variação de prosa do LLM):
   - Na branch `feat/1-bugs-plantados`: verifica que o veredito não aprova (`corrigir antes do PR`) e que os 3 defeitos aparecem na seção de achados com referência a arquivo e linha (`<arquivo>:<linha>` ou número de linha junto ao nome do arquivo), severidade compatível (`bloqueante` para o bug de lógica e a falha de segurança; `bloqueante` ou `importante` para o teste enfraquecido/removido) e menção ao problema correspondente.
   - Na branch `feat/1-controle-limpo`: verifica que o veredito aprova (`aprovar`) e que não há achados de severidade `bloqueante` nem `importante`.
5. O script imprime o resultado de cada verificação (`ok` / `FALHOU`) e o resumo final, saindo com `0` quando todas passam e `1` se alguma falhar (ou se o binário `claude` não estiver disponível no `PATH`).
6. No workflow `.github/workflows/ci.yml`, `scripts/test-revisor-quality.sh` é pulado explicitamente junto com os testes de aceite para não consumir tokens em cada commit/PR.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `scripts/test-revisor-quality.sh` gera um repositório git temporário (`mktemp -d`) com `origin/main`, `specs/SPEC-1.md`, `Makefile` (`lint` e `test`), a branch `feat/1-bugs-plantados` (com bug de lógica, falha de segurança e teste enfraquecido/removido) e a branch `feat/1-controle-limpo`, removendo o diretório ao sair | unitário (inspeção e execução com `FABRICA_CLAUDE_BIN` mockado ou execução real do script) |
| CA2 | Na execução contra `feat/1-bugs-plantados` usando `claude -p --plugin-dir <clone> --agent fabrica:revisor`, o script confere que os 3 defeitos aparecem com arquivo/linha e severidade compatível (`bloqueante` para lógica e segurança; `bloqueante` ou `importante` para teste enfraquecido/removido) e que o veredito não aprova | manual (`bash scripts/test-revisor-quality.sh` na branch com `claude --plugin-dir <clone>`) |
| CA3 | Na execução contra `feat/1-controle-limpo` usando `claude -p --plugin-dir <clone> --agent fabrica:revisor`, o script confere que o veredito aprova e que não há achados `bloqueante` nem `importante` | manual (`bash scripts/test-revisor-quality.sh` na branch com `claude --plugin-dir <clone>`) |
| CA4 | `.github/workflows/ci.yml` pula `scripts/test-revisor-quality.sh` na execução automática do CI | unitário (verificação do `case` em `.github/workflows/ci.yml` e execução simulada do loop do CI) |
| CA5 | `AGENTS.md` documenta o propósito e o comando de execução sob demanda de `scripts/test-revisor-quality.sh` e sua exclusão do CI | unitário (leitura de `AGENTS.md`) |

## Fora de escopo
- Eval automático de `spec` ou `triagem`.
- Juiz multi-modelo em loop contínuo no CI.
- Alterações nas instruções de `agents/revisor.md` ou `agy-agents/revisor.md`.

## Desenho técnico
**Arquivos e módulos:**
- `scripts/test-revisor-quality.sh` (novo): script bash executável que monta a fixture temporária, invoca `fabrica:revisor` nas duas branches e valida os achados e vereditos.
- `.github/workflows/ci.yml` (alteração): inclui `scripts/test-revisor-quality.sh` no `case` de exclusão do loop `for f in scripts/test-*.sh`.
- `AGENTS.md` (alteração): documenta `scripts/test-revisor-quality.sh` na seção `## Estrutura` e atualiza a lista de exceções do `.github/workflows/ci.yml`.

**Dados:** nenhum.

**Interfaces:**
- Entrada de `scripts/test-revisor-quality.sh`: sem argumentos obrigatórios; aceita variável de ambiente opcional `FABRICA_CLAUDE_BIN` (padrão `claude`) para permitir testes determinísticos da lógica de parsing/fixture sem gastar tokens, e `FABRICA_REVISOR_MODEL` (opcional, para passar `--model` ao `claude -p` quando o usuário quiser fixar o modelo da linha de base).
- Saída: código `0` se todas as verificações passarem, `1` caso contrário.

**Decisões:**
- Gerar o repositório git de fixture em diretório temporário (`mktemp -d`) dentro de `scripts/test-revisor-quality.sh` (recomendação da triagem) — segue a convenção dos demais `scripts/test-*.sh` do repositório (como `scripts/test-revisor-agent.sh`) e evita manter código defeituoso de exemplo versionado na árvore do projeto. Alternativa descartada: versionar os arquivos da fixture no repositório.
- Invocar o subagente via `claude -p --plugin-dir <clone> --agent fabrica:revisor --permission-mode bypassPermissions --output-format text` — testa exatamente o agente `agents/revisor.md` da worktree/clone atual de forma não interativa e sem depender de instalação prévia do plugin. Alternativa descartada: invocar `claude -p` sem `--agent` colando o prompt manualmente, pois não exercitaria o carregamento do agente do plugin.
- Usar projeto fixture em Python 3 com `Makefile` (`lint` com `python3 -m py_compile`, `test` com `python3 -m unittest`) — não requer instalação de dependências externas nem rede para o `revisor` rodar `make lint` e `make test`. Alternativa descartada: fixture em Node/TypeScript, que exigiria `npm install` ou `node_modules`.

**Fontes da documentação:**
- `claude` CLI (versão local instalada) — `claude --help` consultado para `--agent`, `--plugin-dir`, `--permission-mode`, `--output-format` e `--model`.

**ADR:** nenhum.

## Testes
- `bash -n scripts/test-revisor-quality.sh` para validar sintaxe.
- Execução com `FABRICA_CLAUDE_BIN` mockado (simulando saída positiva e negativa do revisor) para garantir que a criação da fixture e as asserções do parser funcionam antes de gastar tokens.
- Execução real sob demanda `bash scripts/test-revisor-quality.sh` contra o plugin local (`--plugin-dir`) para validar CA2 e CA3 com o modelo real.
- Execução das suítes unitárias do CI (`for f in scripts/test-*.sh; ...`) garantindo que `scripts/test-revisor-quality.sh` é pulado no loop do `.github/workflows/ci.yml` e os demais testes continuam passando.

## Passos de produção
nenhum.

## Riscos e dúvidas
- Variação não determinística na saída do LLM pode fazer o `revisor` formatar a referência de arquivo/linha ou descrever um achado com palavras diferentes; regexes muito restritivas causam falsos negativos no eval.
- Se a execução ocorrer dentro de uma sessão ativa do Claude Code (`CLAUDECODE` definida), o sub-processo `claude -p` pode precisar de `env -u CLAUDECODE` para não recusar execução aninhada.

## Histórico
- 2026-11-26: criação.
