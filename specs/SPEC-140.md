# SPEC-140: Regras comuns às etapas ficam num arquivo só, e as skills remetem a ele

**Issue:** #140 · **PRD:** — (mudança interna da fábrica) · **Fonte do escopo:** — · **Classe:** implementacao-simples · **Tamanho:** M
**Status:** aprovada · **Atualizada em:** 2026-11-26

## Contexto
As skills de etapa repetem, quase palavra por palavra, cinco regras: publicar o corpo a partir de arquivo com `--body-file`, o plano B por REST quando o `gh` falha, o que fazer quando uma label não existe, o marcador que todo comentário do agente leva e a linha de custo. Mudar uma delas exige editar até sete arquivos, e as cópias podem divergir. Esta spec tira as cópias das skills e as põe num arquivo comum, que cada skill lê no início. O texto das regras não muda de sentido. A origem é a triagem da issue #140.

## Objetivo
Cada uma das cinco regras comuns está escrita num só arquivo, e as sete skills de etapa remetem a ele sem repetir o texto.

## Comportamento esperado
1. Antes do primeiro passo, cada skill de etapa lê `skills/etapas/regras.md` e aplica as regras listadas na sua remissão, trocando `<etapa>` pelo nome da própria etapa.
2. As regras que se aplicam, por skill:

   | Skill | Regras do arquivo comum que se aplicam |
   |---|---|
   | `backlog` | corpo por arquivo; plano B |
   | `retro` | corpo por arquivo (a skill mantém `gh api -F body=@<arquivo>` no lugar de `--body-file`, como hoje) |
   | `lancamento` | corpo por arquivo; plano B; marcador; linha de custo |
   | `triagem`, `spec`, `implementar`, `revisar` | as cinco |

3. Os casos específicos ficam no `SKILL.md` de cada etapa: o comentário de lição, o comentário de ação, as condições em que a linha de custo sai, a variante `-F body=@` do `retro` e as labels próprias de cada etapa.
4. Nenhum comportamento muda: quem roda uma etapa publica o mesmo tipo de comentário, com o mesmo marcador, pelo mesmo caminho de arquivo, e para nas mesmas situações.

Não há regra com limite, nem regra que leva dados de um item para outro, então não há casos de borda novos nesta spec.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | `skills/etapas/regras.md` existe, a pasta não tem `SKILL.md`, e o arquivo tem as cinco regras, uma vez cada, com `<etapa>` onde o nome da etapa entra | unitário (`bash scripts/test-regras-etapas.sh`) |
| CA2 | Nenhuma das sete skills (`backlog`, `triagem`, `spec`, `implementar`, `revisar`, `retro`, `lancamento`) repete o texto de uma das cinco regras | unitário (mesmo teste) |
| CA3 | Cada uma das sete skills tem, antes do primeiro passo, a remissão `../etapas/regras.md` com o `<etapa>` dela e a lista das regras que se aplicam (tabela do Comportamento esperado), e o caminho resolve para o arquivo | unitário (mesmo teste) |
| CA4 | As exceções continuam no `SKILL.md` de cada etapa: lição (`triagem`, `implementar`, `revisar`), ação (`implementar`, `revisar`, e o marcador `acao` do `lancamento`), condição da linha de custo (`implementar`, `triagem`, `lancamento`), `gh api -F body=@` (`retro`) e a frase sobre a label da `licao` | manual (revisão do diff no PR, contra a tabela do Comportamento esperado) |
| CA5 | O sentido de cada regra não muda; as diferenças de texto são só as listadas em "Diferenças de texto" no Desenho técnico | manual (revisão do diff no PR) |
| CA6 | Com `claude --plugin-dir <clone>` na branch, `/fabrica:` lista as mesmas 13 skills de antes, e `etapas` não aparece como comando | plugin instalado: `claude --plugin-dir <clone>` na branch |
| CA7 | Rodar `/fabrica:triagem` numa issue de teste publica o comentário com o marcador `<!-- fabrica:triagem -->`, o corpo sai de arquivo com `--body-file`, e a linha de custo fica no fim, como na versão atual | publicar no GitHub: issue de teste no próprio repositório, fechada no fim com um comentário dizendo que era teste |
| CA8 | `AGENTS.md` cita `skills/etapas/regras.md` na estrutura e `scripts/test-regras-etapas.sh` na lista de testes, e a seção "Escrevendo skills" diz que regra comum a mais de uma etapa vai para o arquivo comum | unitário (mesmo teste) |
| CA9 | `.claude-plugin/plugin.json` sobe a `version` de `0.56.0` para `0.56.1` | manual (revisão do diff no PR) |

Nenhum CA é de ponta a ponta, então a regra de casos adversariais não se aplica.

## Fora de escopo
- Encurtar ou reescrever o texto das regras comuns (é a issue, não esta spec).
- Frontmatter das skills, que é a #98.
- Bloco de etapa nos comentários de agente, que é a #139.
- A regra de início da etapa (`date -u`) e a checagem do `gh` (`check-gh.sh`). Continuam em cada skill: não estão na lista de regras da issue.
- `skills/status/estados.md` e `docs/`: as labels e os marcadores não mudam, e o manual descreve as regras sem copiá-las.

## Desenho técnico
**Arquivos e módulos:**
- `skills/etapas/regras.md` (novo): intro curta e as cinco regras, com o texto de hoje e `<etapa>` no lugar do nome. Os links são refeitos a partir de `skills/etapas/`: `../status/estados.md`, `../setup/gh.md#plano-b-por-rest`.
- `skills/backlog/SKILL.md`, `skills/triagem/SKILL.md`, `skills/spec/SKILL.md`, `skills/implementar/SKILL.md`, `skills/revisar/SKILL.md`, `skills/lancamento/SKILL.md` e `skills/retro/SKILL.md`: a remissão antes do primeiro passo, a remoção das cópias e a manutenção das exceções (CA4).
- `AGENTS.md`: a estrutura passa a listar `skills/etapas/regras.md`; a lista de testes em `scripts/` ganha `scripts/test-regras-etapas.sh`; a seção "Escrevendo skills" ganha a regra de que a regra comum a mais de uma etapa vai para o arquivo comum.
- `scripts/test-regras-etapas.sh` (novo): o teste da CA1 a CA3 e da CA8.
- `.claude-plugin/plugin.json`: `version` de `0.56.0` para `0.56.1`.

O `skills/etapas/` não é um comando. O plugin do Claude Code e o adaptador do OpenCode leem `skills/*/SKILL.md`, então a pasta sem `SKILL.md` fica de fora. A CA6 confere isso no plugin instalado.

**Remissão:** cada skill ganha, antes do primeiro passo (ou logo depois da introdução, se não houver passo de pré-requisitos), um parágrafo no modelo:
`**Regras comuns:** leia [../etapas/regras.md](../etapas/regras.md) e aplique as regras dele com \`<etapa>\` = \`spec\`: <lista das regras da tabela>.`

**Diferenças de texto** (as únicas permitidas, CA5):
- *Plano B e label:* a frase "Uma label que não existe não é erro do `gh`: vale a regra abaixo" sai do bullet do plano B e vira a primeira frase do bullet da label. Assim, `backlog` e `lancamento`, que não têm a regra de label, não recebem remissão a uma regra que não têm. O sentido é o mesmo.
- *Plano B:* o bullet diz "`gh pr edit` ou `gh issue edit`", e hoje o `lancamento` só diz `gh issue edit`. O `lancamento` não usa `gh pr edit`, então a frase larga não muda o comportamento dele.
- *Marcador:* o `lancamento` dizia "na issue de runbook"; o texto comum diz "na issue ou no PR". O `lancamento` não tem PR, então o sentido é o mesmo.
- *Retro:* o `retro` mantém a própria frase com `gh api -F body=@<arquivo>`, fora do arquivo comum.

**Dados:** nenhum. **Interfaces:** nenhuma rota nem função. O caminho relativo `../etapas/regras.md` é a única interface nova, e vale a partir de `skills/<etapa>/`.

**Decisões:**
- Local do arquivo comum: `skills/etapas/regras.md`, em pasta própria, sem `SKILL.md`, para não virar comando. Alternativa descartada: pôr o arquivo em `skills/status/`, junto de `estados.md`, porque misturaria regra de publicação com a máquina de estados.
- Escopo inclui `lancamento` (recomendação da triagem, item 1). Alternativa descartada: deixá-la fora com motivo, porque ela repete as mesmas regras de corpo e de plano B, e a issue pede que cada regra comum fique num só arquivo. (recomendação da triagem)
- A variante `gh api -F body=@<arquivo>` do `retro` fica no `retro`. Alternativa descartada: incluí-la no arquivo comum, porque só o `retro` a usa.
- Teste por texto (`scripts/test-regras-etapas.sh`) em vez de revisão manual só. Alternativa descartada: revisar à mão, porque uma cópia voltaria a uma skill sem ninguém perceber.
- Bump de patch no `plugin.json`. Alternativa descartada: não subir a versão, já que o comportamento não muda. Subo porque os arquivos instalados mudam, e a versão mostra qual instalação tem o arquivo novo.

**Fontes da documentação:**
- gh 2.105.0 — `gh issue edit --help` (`--body-file`, `--add-label`), `gh pr comment --help` (`--body-file`) e `gh api --help` (`-F` com `@<caminho>`), consultados nesta etapa. Nenhuma biblioteca nova.

**ADR:** nenhum. A decisão de onde fica o arquivo comum não afeta mais que esta issue.

## Testes
- `bash scripts/test-regras-etapas.sh` (novo), que confere:
  - a CA1: o arquivo existe, não há `SKILL.md` na pasta, e cada frase-âncora das cinco regras aparece uma vez ("Publique todo corpo de issue", "use o plano B de", "Não crie a label sozinho", "Os comentários do agente e do usuário saem da mesma conta", "--stage <etapa>");
  - a CA2: nenhuma das sete skills contém essas frases-âncora;
  - a CA3: cada uma das sete skills contém o link `../etapas/regras.md`, e o caminho resolve para o arquivo;
  - a CA8: `AGENTS.md` cita o arquivo novo e o teste novo.
- Revisão do diff no PR para CA4, CA5 e CA9.
- Plugin instalado para CA6: `claude --plugin-dir <clone>` na branch, e conferir a lista de `/fabrica:`.
- Issue de teste para CA7, fechada no fim com comentário dizendo que era teste.

## Passos de produção
nenhum

## Riscos e dúvidas
- Uma regra num arquivo à parte pode ser seguida com menos rigor. A CA7 compara o comentário publicado com o de hoje, e a remissão vem antes do primeiro passo.
- Conflito com a #98 e a #139, que mexem nos mesmos `SKILL.md`. Antes de abrir o PR, a branch é atualizada sobre a `main`.
- Se o plugin tratar a pasta `skills/etapas/` como comando, a CA6 pega isso antes do merge.

## Histórico
- 2026-11-26: criação.
- 2026-11-26: aprovada.
