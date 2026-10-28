---
name: setup
description: Cria ou corrige as seis labels da fábrica (agente, precisa-info, spec-pronta, spec-aprovada, escalonado, pronto-revisao) num repositório do GitHub, conforme a tabela de estados.md. Use num repositório que ainda não tem as labels ou quando uma etapa avisar que uma label não existe.
argument-hint: "[<dono>/<repo>]"
disable-model-invocation: true
---

# Setup das labels

Repositório: $ARGUMENTS (vazio = o repositório do diretório atual)

## Executar
- Rode o script do plugin a partir do diretório base desta skill: `bash <diretório base>/../../scripts/setup-labels.sh $ARGUMENTS`.
- O script é idempotente: cria as labels que faltam, corrige cor e descrição das que divergem da tabela em [estados.md](../status/estados.md) e não toca em outras labels.

## Responder
- Com sucesso, mostre o repositório alvo e a linha `ok <label>` de cada uma.
- Com erro, mostre a mensagem do script e o que fazer (autenticar o `gh`, criar o repositório com `gh repo create`, passar `<dono>/<repo>`). Não tente criar as labels por outro caminho.

## Regras
- Não aplique nem remova labels em issues; o setup só garante que as labels existam no repositório.
