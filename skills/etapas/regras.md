# Regras comuns das etapas

Regras que valem para mais de uma etapa. Cada `SKILL.md` de etapa manda ler este arquivo e diz quais seções se aplicam a ela; aplique só essas. Onde aparece `<etapa>`, use o nome que a remissão da skill informa. O `<diretório base desta skill>` é o da skill da etapa, não esta pasta. As exceções e os casos próprios de cada etapa estão no `SKILL.md` dela.

## Corpo por arquivo
- Publique todo corpo de issue, comentário ou PR a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.

## Plano B
- Se um `gh pr edit` ou um `gh issue edit` falhar por um erro do próprio `gh`, use o plano B de [../setup/gh.md](../setup/gh.md#plano-b-por-rest) e avise no chat.

## Label inexistente
- Uma label que não existe não é erro do `gh`: o plano B não se aplica. Se `gh issue edit` falhar porque uma label não existe, pare, comente na issue e diga no chat: "A label `<label>` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label sozinho.

## Marcador
- Todo comentário seu, na issue ou no PR, começa com o marcador `<!-- fabrica:<etapa> -->` numa linha própria. Os comentários do agente e do usuário saem da mesma conta do GitHub, e o marcador é o que os distingue (veja [estados.md](../status/estados.md)).

## Linha de custo
- Logo antes de publicar, acrescente ao fim do arquivo do corpo a linha que registra o início, o fim e os tokens desta execução: `python3 <diretório base desta skill>/../../scripts/stage-usage.py --stage <etapa> --since <início> >> <arquivo>`. O `<início>` é o instante em UTC que a etapa guardou ao começar. O script nunca falha: sem log da sessão, a linha sai com `tokens=nao-medido`. Em quais comentários a linha entra está no `SKILL.md` da etapa.
