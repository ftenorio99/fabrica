# ADR 0022: distribuição nativa e seleção explícita para Codex

**Status:** proposto · **Data:** 2026-11-27 · **Origem:** issue #245

## Contexto

B1 separou a execução Claude da coordenação. O piloto B2.1 confirmou que o Codex CLI 0.172.0 descobre na worktree uma skill instalada via marketplace local. Os recursos precisam manter caminhos relativos e a instalação precisa funcionar em uma máquina exclusivamente Codex.

## Decisão

Gere o plugin portátil `fabrica` a partir de um inventário explícito de fontes compartilhadas, com metadados Codex gerados e marketplace `fabrica-local`. Selecione o executor explicitamente e resolva modelo e esforço por etapa em `.fabrica/codex-models.json`, preservando a detecção de sessão e a política de modelos Claude. Comece com `version: 1` para validar a estrutura e recusar formatos incompatíveis.

## Alternativas consideradas

| Alternativa | Limitação |
|---|---|
| Distribuir skills apenas pelo clone | Uma worktree pode descobrir um conjunto diferente do clone principal. |
| Manter cópias editoriais independentes | Regras e caminhos podem divergir a cada mudança. |
| Projetar labels Claude no Codex | IDs e níveis de esforço dependem do runtime e do modelo. |

## Consequências

- Valide origem, destino e recursos. Rejeite symlinks, referências externas e arquivos que estejam fora do inventário. Gere caminhos, bytes e modos determinísticos em temporário, preservando as fontes e qualquer pacote anterior se a geração falhar.
- A resolução é determinística, lê somente a configuração local e dispensa consultas a provedores, execução de modelos e escritas no workflow. Erros do empacotador e do resolvedor omitem dados sensíveis. O dispatcher e o fluxo assistido mantêm seus contratos atuais.
- Hooks, agentes instaláveis e execução real exigem aceites próprios. Marketplace remoto e publicação seguem etapas autorizadas separadamente.
