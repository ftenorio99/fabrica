# Dispatcher no GitHub Actions (piloto)

O dispatcher é um workflow do GitHub Actions que roda a etapa de agente sem sessão na sua máquina: você aplica a label `agente` numa issue, e o runner instala o Claude Code e o plugin e roda o `/fabrica:triagem` ([ADR 0015](../adr/0015-dispatcher-no-github-actions.md)). No piloto, ele vale só para o repositório de teste `ftenorio99/fabrica-teste`; a instalação nos projetos pelo `/fabrica:setup` vem depois (#108).

## O que ele faz
- Dispara só quando a label aplicada é `agente` e a issue está aberta. As labels que as etapas aplicam (`modelo:*`, `precisa-info`, `spec-pronta`, `em-andamento`) não disparam nada, então não há cascata.
- Roda só a **triagem**, e só numa issue em "Aguardando triagem" (sem comentário de triagem). Numa issue já triada, ele termina verde sem chamar o Claude e sem comentar. As etapas seguintes continuam pela sua máquina (`/fabrica:avancar`) até a retomada por evento (#107).
- Respeita a `em-andamento` como o `/fabrica:avancar`: se outra execução aplicou a label há menos de 2 h, ele não pega a issue. Quando é ele quem aplica a label, ele a remove no fim, com sucesso ou com falha.
- Uma execução por issue de cada vez (grupo de concorrência `fabrica-<nº>`), com 30 min para a etapa e 40 min para o job.

A lógica fica no `scripts/dispatch.sh` do plugin; o workflow só prepara o runner e chama o script. A etapa roda pelo mesmo `scripts/stage-model.sh run` do `/fabrica:avancar`, com o modelo de [modelos.md](../../skills/avancar/modelos.md) e o modo de permissão `auto`.

## Como ligar num repositório
1. **Copie o workflow:** `templates/workflows/agente.yml` do plugin vai para `.github/workflows/agente.yml` do repositório, na branch padrão (o GitHub só roda workflows de `issues` a partir dela). Como a `main` é protegida, a cópia entra por PR.
2. **Labels:** rode `bash scripts/setup-labels.sh <dono>/<repo>` do plugin, se o repositório ainda não as tem.
3. **Secret `CLAUDE_CODE_OAUTH_TOKEN`:** gere com `claude setup-token` na sua máquina (usa a sua assinatura) e cadastre com `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <dono>/<repo>`, colando o valor quando o `gh` pedir.
4. **Secret `FABRICA_PLUGIN_TOKEN`:** o repositório `ftenorio99/fabrica` é privado, e o token do job só alcança o próprio repositório. Crie um token *fine-grained* em GitHub → Settings → Developer settings → Fine-grained tokens, com acesso só ao repositório `ftenorio99/fabrica` e só a permissão **Contents: read**, e cadastre com `gh secret set FABRICA_PLUGIN_TOKEN --repo <dono>/<repo>`.

Cada secret aparece só no passo que o usa: o `FABRICA_PLUGIN_TOKEN` no passo que instala o plugin, e o `CLAUDE_CODE_OAUTH_TOKEN` no passo que roda a etapa.

## Quando falha
O job fica vermelho e a issue recebe um comentário que começa com `<!-- fabrica:dispatcher -->`, com a etapa, o motivo e o link do run:

| Motivo | O que aconteceu |
|---|---|
| `permissao` | O modo `auto` negou ferramentas à etapa; o comentário lista os nomes delas. |
| `erro` | O Claude saiu com erro, terminou com `is_error` ou não devolveu um JSON legível. |
| `labels` | A issue tem duas ou mais labels `modelo:*`; deixe uma só. |
| `sem-resultado` | A etapa não chegou a devolver resultado: tempo esgotado ou erro antes do Claude, ao ler a issue. |

O comentário não traz o texto da resposta do Claude nem valores de secrets; os detalhes ficam no log do run. Ele não muda o estado da issue ([estados.md](../../skills/status/estados.md)), que continua em "Aguardando triagem": corrija a causa e reaplique `agente` (remova e aplique de novo), ou rode `/fabrica:triagem <nº>` na sua máquina.

Uma falha na instalação do Claude Code ou do plugin (secret errado ou ausente, por exemplo) deixa o job vermelho sem comentário na issue, porque o script que comenta vem do próprio plugin. Veja o log do run.

## Limites do piloto
- **Sem isolamento:** o job roda com a rede aberta e com o `GITHUB_TOKEN` (escrita em issues) ao alcance do agente. A restrição de rede e o token fine-grained vêm na #106. Até lá, use só no repositório de teste, com issues escritas por você.
- **CI do PR do agente:** quando as etapas que abrem PR rodarem no Actions (#107), o push feito com o `GITHUB_TOKEN` não dispara o CI sozinho. No piloto, a decisão é aprovar o run à mão; a troca de token da #106 pode resolver o disparo.
- **Linha de custo:** depende do log da sessão no runner; sem ele, sai `tokens=nao-medido`.
