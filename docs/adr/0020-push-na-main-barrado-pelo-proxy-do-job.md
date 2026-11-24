# ADR 0020: Push na main barrado pelo proxy do job

**Status:** proposto · **Data:** 2026-11-24 · **Origem:** issue #204

## Contexto
A [ADR 0002](0002-protecao-da-main-por-hooks-do-git.md) protege a `main` com hooks globais do git e deixa ao `protect-main` só checagens de texto no Bash, com um modelo de ameaça de erros e comandos inocentes. No job do dispatcher ([ADR 0016](0016-isolamento-do-job-do-dispatcher.md)), o agente roda sozinho sobre texto de issue, e um agente enganado passa a fazer parte da ameaça. Ali, o agente pode desligar os hooks gravando o `.git/config` da worktree com Write, ou rodando um script gravado por ele, e nenhuma checagem de texto nem permissão de arquivo impede isso: o git precisa escrever na pasta `.git`, e o config é trocado por renomeação. A proteção do GitHub (rulesets) exige GitHub Pro nos repositórios privados.

## Decisão
No job, o addon do proxy (`scripts/egress-addon.py`), que roda como `fabrica-proxy`, lê a lista de comandos de todo push HTTP para o `github.com` e responde 403 quando algum comando cria, atualiza ou apaga `refs/heads/main` ou `refs/heads/master`, ou quando o corpo não pode ser lido. Os hooks do git e o `protect-main` continuam como estão, como primeira camada.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| `.git/config` não gravável pelo agente | Quem escreve na pasta `.git` troca o arquivo por renomeação; com o bit sticky, o `git push -u` das etapas quebra; e um script do agente passa a configuração por ambiente. |
| Só ampliar o `protect-main` (Edit e Write) | Continua dependendo de o agente não montar o comando de outro jeito; vale fora do job, não como fronteira. |
| Rulesets do GitHub | Exigem GitHub Pro nos repositórios privados (ADR 0002). |
| Sobrescrever `core.hooksPath` por ambiente no job | Um script do agente desfaz a variável; e desligaria hooks locais de projetos só no job. |

## Consequências
- No job, a `main` e a `master` não recebem push do agente, qualquer que seja a configuração do git dele.
- O job não cria repositório: o proxy não tem a exceção do commit inicial dos `githooks/`.
- Um corpo de push que o addon não entende é recusado; uma mudança no protocolo de push do git aparece como falha de push no job.
- Escritas na `main` pela API do GitHub (conteúdo, refs, merge de PR) não passam por esta regra e seguem limitadas pelo escopo do token.
- Fora do job, a proteção continua a da ADR 0002, com o `protect-main` também recusando Edit e Write nos arquivos de configuração do git (SPEC-204).
