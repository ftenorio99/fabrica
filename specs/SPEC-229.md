# SPEC-229: ci: adiciona workflow de CI rodando os testes unitários do fabrica

**Issue:** #229 · **PRD:** — · **Fonte do escopo:** — · **Classe:** implementacao-complexa · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-26

## Contexto
O repositório `fabrica` exige CI verde em `pull_request` nos projetos que usam a fábrica ([ADR 0011](../docs/adr/0011-verificacao-de-integracao-na-etapa.md) e [ADR 0019](../docs/adr/0019-ci-do-pr-pelo-modelo-da-fabrica.md)), mas não possui `.github/workflows/` próprio. Hoje o repositório conta com 24 arquivos `scripts/test-*.sh` (22 suítes unitárias e 2 suítes de aceite), e alterações em scripts, hooks ou agentes só são validadas quando alguém executa os testes localmente.

## Objetivo
Todo `pull_request` e todo `push` na `main` do repositório `fabrica` executam automaticamente as suítes unitárias `scripts/test-*.sh` no GitHub Actions, garantindo que nenhuma regressão passe despercebida.

## Comportamento esperado
1. Ao abrir ou atualizar um PR (`pull_request`) ou fazer push na branch `main` (`push` com `branches: [main]`), o GitHub Actions dispara o workflow `CI` definido em `.github/workflows/ci.yml`.
2. Execuções antigas do mesmo PR ou da mesma ref são canceladas automaticamente (`concurrency` com `cancel-in-progress: true`).
3. O job roda em `ubuntu-latest` com permissões restritas (`permissions: contents: read`), sem uso de `secrets.` e com ações fixadas por SHA de commit.
4. Após o checkout, o job garante a presença das dependências exigidas pelas suítes unitárias (`python3-yaml` para `import yaml` no Python do sistema e `jq` para hooks/scripts).
5. Em seguida, o job itera sobre todos os arquivos `scripts/test-*.sh`, pulando explicitamente `scripts/test-job-acceptance.sh` e `scripts/test-sandbox-acceptance.sh` (que dependem de runner dedicado ou VM do `sbx`).
6. Cada suíte unitária é executada com `bash "$f"` imprimindo um cabeçalho identificador; o passo executa todas as suítes até o fim acumulando eventuais falhas e sai com código `1` se ao menos uma suíte falhar (ou `0` se todas passarem).
7. O arquivo `AGENTS.md` da raiz passa a documentar `.github/workflows/ci.yml` na seção `## Estrutura`.

## Telas
nenhuma (Interface: não)

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `.github/workflows/ci.yml` é YAML válido, dispara em `pull_request` e em `push` na `main`, define `permissions: contents: read` no topo sem ampliação nos jobs, usa `concurrency` por número de PR ou ref com `cancel-in-progress: true`, não cita `secrets.` e fixa toda ação (`uses:`) por SHA de 40 caracteres hexadecimais com comentário de versão | unitário — validação de estrutura YAML via `python3` + `PyYAML` e `grep` |
| CA2 | O passo de execução de testes do workflow itera sobre `scripts/test-*.sh`, exclui exatamente `scripts/test-job-acceptance.sh` e `scripts/test-sandbox-acceptance.sh`, executa todas as demais suítes sem interromper na primeira falha e sai com código diferente de zero se qualquer suíte falhar | unitário — simulação do loop do passo de shell em diretório temporário com suítes que passam e falham, além da verificação das suítes excluídas |
| CA3 | O passo de preparação instala `python3-yaml` e `jq` antes da execução dos testes, garantindo que `test-dispatch.sh`, `test-setup-ci.sh`, `test-protect-main.sh`, `test-protect-production.sh` e `test-statusline.sh` rodem no runner `ubuntu-latest` | e2e (CI do PR) — execução real do workflow no PR desta própria issue no GitHub Actions, terminando verde com todas as suítes unitárias executadas |
| CA4 | `AGENTS.md` documenta `.github/workflows/ci.yml` na seção `## Estrutura`, explicando que ele roda as suítes unitárias `scripts/test-*.sh` (exceto os testes de aceite) em `pull_request` e `push` na `main` | manual — leitura do diff de `AGENTS.md` |

## Fora de escopo
- Rodar testes de aceite de runner ou VM (`scripts/test-job-acceptance.sh`, `scripts/test-sandbox-acceptance.sh`, `opencode/test-adapter.sh`).
- Alterar o modelo `templates/workflows/ci.yml` ou o `scripts/setup-ci.sh`.
- Alterar regras de skills, hooks ou incrementar a `version` em `.claude-plugin/plugin.json` (não há mudança de comportamento do plugin).
- Configurar branch protection rules no GitHub (configuração manual fora do código).

## Desenho técnico
**Arquivos e módulos:**
- `.github/workflows/ci.yml` (novo): workflow de CI do próprio repositório `fabrica`.
- `AGENTS.md` (alterado): inclusão da descrição de `.github/workflows/ci.yml` na seção `## Estrutura`.

**Dados:** nenhum.

**Interfaces:**
- Gatilhos do GitHub Actions em `.github/workflows/ci.yml`: `on: pull_request` e `on: push: branches: [main]`.
- Ação utilizada: `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1` (mesmo SHA fixado em `templates/workflows/ci.yml`).
- Passo de dependências: `sudo apt-get update && sudo apt-get install -y python3-yaml jq`.
- Passo de testes: loop em `scripts/test-*.sh` pulando `scripts/test-job-acceptance.sh` e `scripts/test-sandbox-acceptance.sh`, rodando `bash "$f"` para cada suíte, contabilizando falhas e retornando `1` ao final caso alguma falhe.

**Decisões:**
- Instalar `python3-yaml` e `jq` via `apt-get` em vez de `pip install pyyaml` — `apt-get` instala `PyYAML` no Python do sistema (`/usr/bin/python3`) sem conflitar com o `PEP 668` (`externally-managed-environment`) do Ubuntu 24.04 (`ubuntu-latest`) e garante `jq` no mesmo passo. Alternativa descartada: `pip install pyyaml`, que exige virtualenv ou `--break-system-packages` em runners modernos.
- Iterar dinamicamente sobre `scripts/test-*.sh` excluindo apenas os 2 testes de aceite — qualquer nova suíte unitária adicionada futuramente entra no CI automaticamente sem edição do workflow. Alternativa descartada: listar manualmente as 22 suítes no YAML, o que exigiria manutenção manual a cada novo script de teste.
- Acumular falhas no loop e falhar apenas ao final em vez de usar `set -e` parando na primeira falha — permite diagnosticar todas as suítes quebradas em uma única execução do CI. Alternativa descartada: parar na primeira suíte que falhar, ocultando eventuais falhas subsequentes.
- Documentar o workflow na seção `## Estrutura` do `AGENTS.md` sem alterar `docs/` — `AGENTS.md` descreve a estrutura interna e os testes do repositório `fabrica`, enquanto `docs/` é o manual de uso do plugin nos projetos. Alternativa descartada: criar página em `docs/guias/`, que poderia ser confundida com `docs/guias/ci-do-pr.md` (sobre o modelo para projetos).
- Manter a `version` atual de `.claude-plugin/plugin.json` — segundo `AGENTS.md`, a versão sobe apenas quando há mudança de comportamento do plugin. Alternativa descartada: subir a versão sem alteração funcional.

**Fontes da documentação:**
- Nenhuma biblioteca externa nem comando `gh` no desenho técnico; o padrão de segurança e o SHA de `actions/checkout` seguem `templates/workflows/ci.yml` do próprio repositório.

**ADR:** nenhum.

## Testes
- **Conferência local das suítes unitárias:** rodar todas as 22 suítes `scripts/test-*.sh` (exceto `test-job-acceptance.sh` e `test-sandbox-acceptance.sh`) na worktree para confirmar que a base está verde.
- **Validação estática do workflow (CA1 e CA2):** comando com `python3` + `PyYAML` e `grep` conferindo gatilhos, `permissions: contents: read`, `concurrency`, ausência de `secrets.`, SHA de 40 caracteres hexadecimais com comentário de versão, e teste do loop de exclusão/acumulação de falhas.
- **Execução no GitHub Actions (CA3):** ao abrir o PR da issue #229, o workflow `CI` roda automaticamente no runner `ubuntu-latest` e deve ficar verde, com o log exibindo a execução das 22 suítes unitárias.
- **Revisão do diff (CA4):** leitura do diff de `AGENTS.md`.

## Passos de produção
nenhum.

## Riscos e dúvidas
- `scripts/test-revisor-agent.sh` pula os checks de `agy` e `claude` quando esses CLIs não estão instalados no `PATH` (comportamento já previsto no script, saindo com `0`); no runner `ubuntu-latest` isso é esperado e não impede o job de ficar verde.
- A suíte `scripts/test-job-isolation.sh` usa sockets locais (`127.0.0.1`) e `scripts/test-issue-worktree.sh` usa repositórios `--bare` locais; ambos não exigem privilégios especiais nem rede externa, mas devem ser confirmados na primeira execução real no runner `ubuntu-latest` pelo PR da issue.

## Histórico
- 2026-11-26: criação.
