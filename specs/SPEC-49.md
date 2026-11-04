# SPEC-49: Estabilizar o caso de desempenho do test-protect-main.sh

**Issue:** #49 · **PRD:** — (a fábrica não tem `docs/prd.md`) · **Classe:** implementacao-simples · **Tamanho:** P
**Status:** rascunho · **Atualizada em:** 2026-11-04

## Contexto
O `scripts/test-protect-main.sh` tem um caso de desempenho que garante o critério da SPEC-27: o hook PreToolUse (`hooks/protect-main.sh`) leva menos de 50 ms num comando de 40 KB. A SPEC-29 manteve esse critério no CA5. Hoje o caso mede uma execução só, sem aquecimento. Ele falhou em 2 de 5 execuções na branch da #41 (63 ms), sem nenhuma mudança no hook. Nesta máquina, execuções normais ficam entre 14 e 18 ms.

## Objetivo
O caso de desempenho deixa de falhar pela oscilação da máquina, mas continua falhando quando o hook fica de fato mais lento que o limite de 50 ms.

## Comportamento esperado
- O caso roda o hook uma vez para aquecer e descarta esse tempo. Depois, mede 5 execuções com o mesmo comando de 40 KB.
- O resultado é a **mediana** das 5. Ele passa se ela ficar abaixo de 50 ms.
- A linha do resultado mostra a mediana e as 5 medidas, por exemplo: `ok      CA6  comando de 40 KB: mediana 15 ms em 5 execuções (14 15 15 16 18), limite 50 ms`.
- Uma execução lenta isolada, como o pico de 63 ms visto na #41, não reprova o caso. Um hook que fica lento em todas as execuções reprova.

## Critérios de aceite
| ID | Critério | Verificação |
|---|---|---|
| CA1 | O caso de 40 KB aquece com 1 execução descartada, mede 5 execuções e compara a mediana com o limite de 50 ms. A linha de resultado mostra a mediana e as 5 medidas. | manual: leitura do script e da saída |
| CA2 | `bash scripts/test-protect-main.sh` passa 10 vezes seguidas nesta máquina, com os 95 casos ok em todas. | manual: laço de 10 execuções |
| CA3 | Com uma cópia do hook que tem `sleep 0.06` no início, passada como argumento (`bash scripts/test-protect-main.sh <cópia>`), o caso de 40 KB falha. | manual: introduzir a lentidão e conferir |
| CA4 | O limite continua 50 ms, e o número de casos continua 95. | manual: leitura e saída |

## Fora de escopo
- Mudar o limite de 50 ms da SPEC-27.
- Otimizar o hook `protect-main.sh`.
- Os outros casos do `test-protect-main.sh`.

## Desenho técnico
**Arquivos e módulos:** `scripts/test-protect-main.sh`, só o bloco "Tempo: comando de 40 KB".

**Interfaces:** nenhuma nova. O script continua aceitando o caminho do hook como primeiro argumento, e é isso que o CA3 usa.

**Decisões:**
- **Mediana de 5 execuções depois de 1 aquecimento, com o limite mantido:** um pico isolado não muda a mediana, e uma lentidão real muda. Alternativa descartada: subir o limite, que afrouxaria o critério aceito na SPEC-27 e na SPEC-29.
- **Mediana calculada em bash**, ordenando as 5 medidas com `sort -n` e pegando a terceira, sem depender de `python3` no teste. Alternativa descartada: a média, que um pico grande ainda desloca.

**Fontes da documentação:** nenhuma biblioteca envolvida.

**ADR:** nenhum.

## Testes
- CA1 e CA4: leitura do bloco e uma execução do script.
- CA2: `for i in $(seq 10); do bash scripts/test-protect-main.sh | tail -1; done`, com todas as linhas mostrando "Todos os 95 casos passaram."
- CA3: copiar o hook para a pasta temporária, inserir `sleep 0.06` logo depois do shebang, rodar o script com a cópia como argumento e conferir `FALHOU  CA6  comando de 40 KB`.
- O repositório não tem `make lint`, `make test` nem CI.

## Riscos e dúvidas
- O caso fica cerca de 80 ms mais lento, por causa das 5 execuções extras mais o aquecimento.
- Numa máquina muito carregada, em que a maioria das execuções passa de 50 ms, o caso ainda falha. Isso é o esperado, porque nessa situação o hook está de fato lento.

## Histórico
- 2026-11-04: criação.
