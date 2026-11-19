# ADR 0016: Isolamento do job do dispatcher por proxy com marcadores e usuário sem rede direta

**Status:** aceito · **Data:** 2026-11-19 · **Origem:** issue #106

## Contexto
A F1 do [PRD](../prd.md) pede que o agente rode com rede restrita a uma lista de domínios e sem ler segredos em claro, também no job do dispatcher. A [ADR 0015](0015-dispatcher-no-github-actions.md) escolheu o CLI no `ubuntu-latest` e deixou o isolamento do job para a #106. A [ADR 0010](0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) isolou o agente local pela VM do `sbx`, com uma política de rede e um proxy que troca um marcador pelo token do GitHub. O job do Actions não tem VM do `sbx`: rodar o `sbx` no `ubuntu-latest` depende de virtualização aninhada, que não foi verificada.

No job, o usuário `runner` tem `sudo` sem senha e os secrets entram no ambiente dos passos. O agente (`claude -p` e os comandos que ele executa) precisa do `CLAUDE_CODE_OAUTH_TOKEN` para falar com a API e do token do GitHub para comentar e aplicar labels.

## Decisão
O job roda o agente como um usuário sem rede direta, e todo o tráfego dele passa por um proxy local, que roda como outro usuário:
- o proxy (`mitmproxy`, modo regular, com o addon `scripts/egress-addon.py`) só libera os hosts de `templates/workflows/dominios-liberados.txt` e troca, no cabeçalho `Authorization`, um marcador aleatório do job pelo valor real do secret, só nos hosts daquele secret;
- o agente recebe os marcadores no lugar dos tokens, e o `iptables` (por uid) só deixa o `fabrica-agent` falar com a porta do proxy;
- as escritas do job no GitHub passam a sair com um token fine-grained (`FABRICA_GH_TOKEN`), no lugar do `GITHUB_TOKEN`, e as `permissions` do workflow caem para `contents: read`;
- como o token novo dispara workflows, o filtro por label do workflow é a única trava contra cascata, e o grupo de concorrência passa a incluir o nome da label.

O isolamento falha fechado: sem lista de domínios válida ou sem um dos segredos, o agente não roda.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| `sbx` dentro do `ubuntu-latest` | Depende de virtualização aninhada, não verificada, e mudaria o modo de permissão para `bypassPermissions` (ADR 0013). |
| `ANTHROPIC_BASE_URL` com um proxy em HTTP puro | É o caminho que a documentação do Claude Code descreve para a Anthropic, mas não cobre o token do GitHub (git e API), que ficaria à vista do agente. Fica como plano B só para a Anthropic, se o marcador não funcionar com o TLS terminado. |
| Um único usuário, com `iptables` por processo | O agente roda no mesmo uid do passo e lê o ambiente dele. |
| Liberar DNS e filtrar por IP | Os IPs de CDN rotacionam; o proxy resolve o nome e decide pelo host. |
| GitHub App em vez do token fine-grained | Exige instalar e manter o App no piloto. |
| Lista de domínios dentro do YAML | O teste não a alcança, e a #108 teria de duplicá-la. |

## Consequências
- O job passa a ter três usuários (`runner`, `fabrica-proxy` e `fabrica-agent`) e uma fase de isolamento entre a instalação e o despacho. O plugin é instalado pelo `runner`, porque o `job-isolation.sh` vem dele; o `prepare` o copia, sem o `.git`, para `/opt/fabrica-plugin`, e o `run-as-agent.sh` o passa ao `claude` por `--plugin-dir`. O home do agente nunca guarda o token do plugin. O proxy é o `mitmproxy==12.3.1`, numa venv em `/opt/fabrica-mitm`; mudar a versão pede rodar o aceite de novo.
- O agente enganado ainda pode usar o token do GitHub através do proxy, dentro do escopo do token fine-grained: só o repositório do projeto, sem Workflows e com expiração de até 90 dias. Renovar o token é uma ação externa do usuário ([ADR 0012](0012-acao-externa-com-checklist.md)).
- Eventos criados com o `FABRICA_GH_TOKEN` disparam workflows, inclusive o CI do PR do agente, que passa a rodar sozinho. A decisão pendente da #105 sobre a aprovação manual do CI deixa de valer.
- Cada host novo que uma etapa precise (dependências do `implementar`, por exemplo) entra na lista versionada; essa lista por projeto é da #108.
- Um aceite no runner (`isolamento-aceite.yml` e `scripts/test-job-acceptance.sh`) prova o isolamento depois de cada mudança na lista, no proxy ou na versão do `mitmproxy`.
- O aceite no runner confirmou que o `claude -p` aceita um marcador no lugar do `CLAUDE_CODE_OAUTH_TOKEN` com o proxy terminando o TLS (a triagem da fabrica-teste#3 terminou verde, só com `api.anthropic.com` e `api.github.com` no log do proxy). O plano B do `ANTHROPIC_BASE_URL` não foi preciso.
- O `gh` manda `Authorization: token <valor>`, e o `git` manda `Basic`; o addon troca os três esquemas (`Bearer`, `token` e `Basic`).
