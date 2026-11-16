# ADR 0011: Verificação de integração na própria etapa, com o CI como reserva

**Status:** aceito · **Data:** 2026-11-15 · **Origem:** issue #143

## Contexto
A [ADR 0007](0007-verificacao-de-integracao-pelo-ci.md) mandou para o CI do PR a verificação que depende de Docker, de banco e do `localhost` (`make test` com banco, `make e2e`), porque o sandbox nativo do Claude Code bloqueava os três. A [ADR 0010](0010-isolamento-pelo-sbx-com-opcao-sem-sandbox.md) retirou o sandbox nativo. Nos dois modos que ficaram, o limite não existe:
- **`sbx`:** Docker e Compose funcionam dentro da VM (teste de 2026-11-12 no `ancora` e no `kairo`);
- **`sem-sandbox`:** o agente roda na máquina, com o Docker dela.

Esperar o CI para cada CA de integração deixa a revisão automática mais longa, e uma falha real só aparece depois do push.

## Decisão
- **Na etapa:** o `/fabrica:implementar`, o `/fabrica:revisar` e o revisor rodam a verificação completa (`make lint`, `make test` e, quando a spec tem CA de ponta a ponta, `make e2e`) no ambiente em que a etapa roda, em qualquer modo de `.fabrica/isolamento.txt`. A evidência dos CAs de integração é o teste que o revisor rodou.
- **Reserva do CI:** quando o comando falha com uma assinatura de ambiente (socket do Docker inacessível, `localhost` recusado, socket negado, navegador do Playwright que não baixa ou não abre), o ambiente não roda a verificação. Vale o caminho da ADR 0007: PR em rascunho, espera do CI do head e o resultado do CI como evidência. Sem CI em `pull_request`, a etapa pede a verificação ao usuário.
- **Modo:** as etapas leem o modo com `scripts/setup-isolation.sh --check`. O modo não muda o caminho: ele entra na anotação da reserva e na orientação ao usuário. Sem o arquivo, ou com ele inválido, a etapa segue e avisa para rodar o `/fabrica:setup`.
- **CI:** continua rodando a verificação completa em todo PR, como conferência num ambiente descartável.

## Alternativas consideradas
| Alternativa | Por que não |
|---|---|
| Manter a verificação sempre no CI | O limite que motivou a ADR 0007 saiu com o sandbox nativo. |
| Rodar na etapa só no modo `sbx` e manter o CI no `sem-sandbox` | No modo `sem-sandbox`, o agente já roda na máquina, com o Docker dela. |
| Tirar a reserva do CI e tratar a assinatura como falha comum | Uma máquina com o Docker desligado contaria rodadas de correção e escalaria issues que hoje passam pelo CI. |
| Parar a etapa sem `.fabrica/isolamento.txt` | O `kairo` e o `ancora` ainda não têm o arquivo, e o modo não muda o caminho. |
| Só uma nota na ADR 0007 | A decisão muda: a verificação passa a rodar na etapa, e o CI vira reserva e conferência. |

## Consequências
- A ADR 0007 fica substituída por esta.
- O PR só nasce em rascunho por verificação de integração quando o ambiente não a roda.
- A VM do `sbx` precisa alcançar o que a verificação baixa: as imagens do Compose e os navegadores do Playwright. O guia de isolamento lista os hosts.
- Uma falha de ambiente fora das assinaturas conta como falha da implementação e pode escalar. As assinaturas ficam numa lista única, no `/fabrica:implementar`.
- O CI em `pull_request` continua obrigatório nos projetos: ele é a reserva e a conferência.
