---
name: triagem
description: Faz a triagem de uma issue do GitHub antes da spec - classifica tipo, classe e tamanho, liga ao PRD e pede na própria issue o que faltar (label precisa-info). Use quando uma issue receber a label agente ou depois que as perguntas da triagem forem respondidas.
argument-hint: "<número da issue>"
disable-model-invocation: true
---

# Triagem da issue

Issue: #$ARGUMENTS

A triagem decide se a issue está pronta para virar spec. Ela não escreve spec nem código. Toda comunicação com o usuário acontece **na issue** (comentários e labels), para que esta skill funcione igual rodando no terminal ou no GitHub Actions.

## 1. Ler
- `gh issue view <nº> --json number,title,body,labels,comments,state`
- Se a issue estiver fechada ou não tiver a label `agente`, pare e avise o usuário no chat.
- `CLAUDE.md` e `docs/prd.md`: identifique as funcionalidades do PRD (F1, F2…) ligadas à issue.
- Specs e ADRs existentes (`specs/`, `docs/adr/`) e o código que a issue provavelmente vai tocar. Leia o suficiente para estimar, não para implementar.
- Se já houver um comentário de triagem anterior, esta é uma nova rodada: leia as respostas que vieram depois dele.

## 2. Classificar
- **Tipo:** `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci` ou `perf`.
- **Classe da tarefa:**
  - `implementacao-simples`: ajuste de UI, CRUD, textos, testes unitários;
  - `implementacao-complexa`: arquitetura, autenticação, migrações, integrações, recorrência, agendamento;
  - `documentacao`: README, changelog, comentários.

  Se a issue tocar arquivos sensíveis (autenticação, pagamentos, migrações de banco, `.github/`), a classe é sempre `implementacao-complexa` e a revisão humana é obrigatória.
- **Tamanho**, em trabalho humano: `P` (até meio dia), `M` (até 1 dia), `G` (1 a 2 dias). Acima de 2 dias, proponha a divisão (passo 3).
- **Dependências:** outras issues que precisam estar concluídas antes (`gh issue list --state open`).

## 3. Procurar lacunas
A issue está pronta para spec quando dá para responder, sem chutar:
- qual comportamento muda e para quem;
- como saber que terminou (pelo menos uma ideia de critério de aceite);
- quais limites ela tem (o que não faz parte dela).

Decisões técnicas que o próprio agente pode recomendar (biblioteca, nome de rota, estrutura de pastas) **não** são lacunas: elas vão para a spec, onde o usuário aprova. Lacuna é o que só o usuário sabe: comportamento, prioridade, regra de negócio.

Se a issue for maior que 2 dias, a lacuna é a divisão: proponha as partes (títulos e escopo de cada uma) no comentário e pergunte se o usuário quer dividir. Não crie as issues.

## 4. Registrar
Publique um comentário na issue (`gh issue comment <nº> --body-file <arquivo>`) neste formato:

```markdown
<!-- fabrica:triagem -->
## Triagem

| Campo | Valor |
|---|---|
| Tipo | feat |
| Classe | implementacao-complexa |
| Tamanho | G |
| PRD | F7 |
| Depende de | #12 |
| Arquivos prováveis | `src/...` |

**Resumo:** <uma ou duas frases do que a issue pede, nas palavras da triagem>

**Riscos:** <o que pode complicar, ou "nenhum relevante">

**Perguntas** (só se houver lacunas):
1. <pergunta objetiva, com opções e uma recomendação quando couber>
```

Depois, ajuste as labels:
- **Com lacunas:** `gh issue edit <nº> --add-label precisa-info` e registre uma lição com o gatilho `precisa-info`, resumindo as lacunas e por que a issue não as respondia, como diz [../licao/formato.md](../licao/formato.md). Pare aqui e diga ao usuário que as perguntas estão na issue. Depois de respondidas, a triagem deve ser rodada de novo.
- **Sem lacunas:** `gh issue edit <nº> --remove-label precisa-info` (se estiver lá). Diga que a issue está pronta para `/fabrica:spec <nº>`.

## Regras
- Não escreva spec, código nem branch.
- Não pergunte no chat o que pode ser perguntado na issue.
- Todo comentário seu, na issue ou no PR, começa com o marcador `<!-- fabrica:triagem -->` numa linha própria, exceto o comentário de lição, que segue [../licao/formato.md](../licao/formato.md). Os comentários do agente e do usuário saem da mesma conta do GitHub, e o marcador é o que os distingue (veja [estados.md](../status/estados.md)).
- Não invente requisitos: se o PRD e a issue não dizem, é uma pergunta.
- Publique todo corpo de issue, comentário ou PR a partir de um arquivo: escreva-o com a ferramenta Write na pasta temporária da sessão e passe `--body-file <arquivo>` ao `gh`. Não monte o corpo com heredoc, `echo`, `--body` ou stdin: o hook `protect-main` lê o texto do comando Bash e barra corpos que citam as opções que desligam os hooks do git.
- Em rodadas seguintes, publique um novo comentário de triagem completo (com o mesmo marcador); não edite os anteriores, para manter o histórico.
- Se `gh issue edit` falhar porque uma label não existe, pare, comente na issue e diga no chat: "A label `<label>` não existe neste repositório. Rode `/fabrica:setup` e repita a etapa." Não crie a label sozinho. A exceção é a `licao`: sem ela, a etapa avisa e segue, como diz [../licao/formato.md](../licao/formato.md).
