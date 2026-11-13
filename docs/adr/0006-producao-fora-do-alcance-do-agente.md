# ADR 0006: Produção fora do alcance do agente

**Status:** aceito · **Data:** 2026-11-10 · **Origem:** issue #94

> A [ADR 0010](0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) retirou o sandbox nativo: o bloqueio de rede por `sandbox.network.deniedDomains` deixou de existir, e o que vale em cada modo de isolamento está nela.

## Contexto
A F2 do PRD pede que as etapas de agente nunca alcancem o banco nem os serviços de produção, e que o que é de produção vire passo de um runbook executado pelo usuário (F8). O sandbox da [ADR 0005](0005-isolamento-do-agente-em-sandbox.md) restringe a rede a uma lista de domínios, mas não sabe quais hosts de cada projeto são de produção. Ele também nega a leitura de todos os `.env*`, o que impede os testes e as migrações locais dos projetos que carregam o ambiente de dev pelo `.env`, como o kairo.

A ADR 0002 mostra que um hook que lê o texto do comando é contornável. Por isso, o hook sozinho não basta como barreira.

## Decisão
- **Convenção do `.env`:** `.env`, `.env.local`, `.env.development` e `.env.test` só têm valores de dev ou de homologação, e o agente pode lê-los. Os segredos de produção ficam no provedor (os secrets do deploy), nunca na máquina. O sandbox nega só `.env.production` e `.env.production.local`, o que substitui a lista de `.env*` da ADR 0005.
- **Padrões por repositório:** cada projeto lista em `.fabrica/producao.txt` os hosts (`host <domínio>`) e os literais (`texto <literal>`) de produção.
- **Duas barreiras:**
  - o hook `PreToolUse` `protect-production.sh` nega o comando Bash que cita um padrão, lendo a união da cópia de trabalho com a versão do branch padrão do `origin`, que só muda por merge do usuário;
  - o setup copia os hosts para `sandbox.network.deniedDomains` do projeto, que tem precedência sobre o `allowedDomains`.
- **Skills:** a spec e a implementação só rodam migrações e scripts com efeito em dados contra dev ou homologação. O passo de produção vai para a seção "Passos de produção" da spec e, de lá, para o runbook do usuário.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Manter o `deny` de todos os `.env*` e injetar os valores de dev pelo `env` do `.claude/settings.json` | Versiona chaves de dev no settings, contra a regra de não commitar `.env`. |
| Manter o `deny` e rodar testes e migrações com `!`, pelo usuário | Para o fluxo automático a cada `make test`. |
| Só o hook, sem barreira de rede | Contornável por um comando que monta o host por partes (ADR 0002). |
| Padrões numa chave do `.claude/settings.json` | Mistura a configuração da fábrica com a do Claude Code. |
| Hook lendo só a cópia de trabalho | O agente escreve no projeto e poderia apagar a linha antes de rodar o comando. |

## Consequências
- Todo projeto que fala com produção precisa de um `.fabrica/producao.txt`. Sem ele, o hook e a barreira de rede não fazem nada.
- Um segredo de produção na máquina passa a ser uma violação da convenção: os literais do arquivo pegam o erro inocente no Bash, mas não a ferramenta Read.
- Os projetos que instalaram o sandbox da ADR 0005 rodam o `/fabrica:setup` de novo para remover os `deny` aposentados.
- Toda spec com efeito em produção lista os passos de produção, e o runbook (#96) parte deles.
