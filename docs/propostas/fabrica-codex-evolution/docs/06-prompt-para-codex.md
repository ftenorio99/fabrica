# Instruções para retomar o trabalho

Leia integralmente `AGENTS.md`, `README.md`, `templates/AGENTS.md` e o [pacote de planejamento](../README.md), em `docs/propostas/fabrica-codex-evolution/`. Consulte os ADRs, as specs e o código citados em cada issue.

1. Confira o SHA, o estado local e a main remota. A referência aprovada é `de4c39adae11`. Apresente qualquer delta antes de adotar outra base. Preserve as alterações locais.
2. Confira a fase autorizada. Durante A1 e A2, atualize documentação e caracterize a base. A aprovação de A1 e A2 só cobre documentação e testes determinísticos restritos a ambiente local temporário.
3. Registre comandos, versões, falhas, casos pulados e grupos pendentes. Peça autorização específica para configuração global, serviços externos, ambientes adicionais, efeitos remotos e modelos reais.
4. Use o fluxo da Fabrica para levar o backlog local a issues e specs quando houver autorização. Aguarde aprovação da spec antes da implementação. A revisão humana precede o merge.
5. Preserve os contratos dos runtimes. Trate SPEC-241 e SPEC-135 como parte da base. GitHub confirma o estado do processo e a implementação deve preservar os portões.
