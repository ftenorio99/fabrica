# Checagem do `gh` e plano B

As etapas que escrevem no GitHub conferem o `gh` antes de usá-lo e, numa falha do próprio `gh`, podem refazer a edição pela API REST. Este arquivo vale para todas elas.

## Checagem
Rode `bash <diretório base da etapa>/../../scripts/check-gh.sh`. Ele imprime uma linha:

| Linha | O que a etapa faz |
|---|---|
| `ok <versão>` | Segue. |
| `desatualizado <versão> <mínima>` | Para e diz no chat: "O `gh` <versão> está abaixo da mínima da fábrica (<mínima>). Rode `/fabrica:setup` para ver como atualizar e repita a etapa." |
| `sem-login <versão>` | Para e diz no chat: "O `gh` não está autenticado. Rode `gh auth login` e repita a etapa." |
| `ausente` | Para e diz no chat: "O `gh` não está instalado. Instale-o pelas instruções de https://github.com/cli/cli#installation e repita a etapa." |

Ao parar por causa da checagem, a etapa não lê nem escreve no GitHub: não comenta, não muda labels e não publica linha de custo. A versão mínima fica só no `check-gh.sh`; não a repita em outro lugar.

## Plano B por REST
Vale só quando um `gh pr edit` ou um `gh issue edit` falha por um erro do próprio `gh`. Isso acontece quando a mensagem é um erro `GraphQL:` que cita algo que o comando não pediu, como `projectCards` ou "Projects (classic)". Nesse caso, refaça o mesmo efeito pela API REST:

| Efeito | Comando |
|---|---|
| Corpo do PR | `gh api -X PATCH repos/<dono>/<repo>/pulls/<nº> -F body=@<arquivo>` |
| Título do PR | `gh api -X PATCH repos/<dono>/<repo>/pulls/<nº> -f title=<título>` |
| Incluir uma label | `gh api -X POST repos/<dono>/<repo>/issues/<nº>/labels -f "labels[]=<label>"` |
| Remover uma label | `gh api -X DELETE repos/<dono>/<repo>/issues/<nº>/labels/<label>` |

Os PRs também são issues na API, então as labels de um PR usam o caminho `issues/<nº do PR>`.

Ao usar o plano B, diga no chat que usou e por quê, com o comando que falhou e a mensagem resumida.

**Fora do plano B:**
- **Label que não existe:** continua valendo a regra da etapa. Ela para e indica o `/fabrica:setup`.
- **Outros erros**, como de permissão, de rede ou de um argumento errado: a etapa trata como trata hoje, sem trocar de caminho.
