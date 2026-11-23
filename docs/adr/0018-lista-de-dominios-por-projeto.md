# ADR 0018: Lista de domínios por projeto no job do dispatcher

**Status:** proposto · **Data:** 2026-11-22 · **Origem:** issue #108

## Contexto
O job do dispatcher deixa o agente alcançar só os hosts de `templates/workflows/dominios-liberados.txt`, do plugin ([ADR 0016](0016-isolamento-do-job-do-dispatcher.md)). A lista cobre a API da Anthropic e o GitHub, o suficiente para a triagem, a spec e a revisão. O `implementar` de um projeto real baixa dependências (no kairo, o pnpm do `registry.npmjs.org`), e cada projeto tem as suas. Pôr esses hosts na lista do plugin os abriria para todos os projetos; deixá-los fora faz o `implementar` falhar no proxy.

## Decisão
O projeto pode versionar `.fabrica/dominios.txt`, com um host exato por linha, sem curinga. O `job-isolation.sh prepare` lê o arquivo do checkout da branch padrão, antes de passar o checkout ao agente, valida cada linha e grava, como root, a lista final: a do plugin seguida da do projeto. O `lock` sobe o proxy com essa lista. Uma linha inválida falha fechado: o agente não roda. Os hosts do projeto nunca recebem segredo; o mapa dos marcadores segue com os hosts fixos da Anthropic e do GitHub.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Hosts de todos os projetos na lista do plugin | Abre para cada projeto os registros dos outros e obriga um PR na fábrica a cada host novo de um projeto. |
| Aceitar `*.dominio` no arquivo do projeto | Um curinga num arquivo que o agente pode propor por PR amplia demais a saída; o host exato do log do proxy basta. |
| O `lock` ler o arquivo direto do checkout | Depois do `prepare`, o checkout é do agente, que poderia editar o arquivo antes do `lock`. |
| Lista no secret ou na variável do repositório | Fica fora da revisão do PR e do histórico do git. |

## Consequências
- Ampliar a rede de um projeto é um PR no próprio projeto, revisado por um humano; a lista vale só depois de entrar na branch padrão.
- A mudança em `.fabrica/dominios.txt` passa a ser sensível na revisão do PR, como o `.github/`.
- O `prepare` passa a ter de rodar antes do `lock` também para a lista de domínios, além dos hooks do git.
- O curinga continua possível só na lista do plugin, revisada na fábrica.
