# Arquivos de teste

Cópias fiéis de versões antigas, usadas só pelos testes. Não são chamadas pelas skills nem pelos hooks, e não devem ser editadas.

| Arquivo | Origem | sha256 | Uso |
|---|---|---|---|
| `stage-model-de4c39a.sh` | `scripts/stage-model.sh` do commit `de4c39a` (blob `94423eef97c9b44eb92c31a2c8d79104cedbacaf`), byte a byte; trazida pela SPEC-247 (B1, #247) | `54b47c231998a6d98844029dc57bfa145fcb37950b06292049c52d24a97cf90c` | `scripts/test-stage-model-environment.py`, chamado por `scripts/test-stage-model.sh`, compara com ela o comportamento da fachada Claude atual (teste diferencial da B1). |
| `setup-githooks-de4c39a.sh` | `scripts/setup-githooks.sh` do commit `de4c39a` (blob `b411b7d28d92a7a36eae6c126c707c7f771ad682`), byte a byte | `611640e299b1fc2f57cba408dc81cb0430b2e5f020aaf85722066c70b433841a` | `scripts/test-setup-githooks.sh` gera com ele as instalações legadas do CA8 da SPEC-246. Fica versionado porque o checkout raso do CI não tem o commit `de4c39a`. |

O `test-setup-githooks.sh` confere o sha256 antes de usar a cópia dele e falha com uma mensagem clara se ela faltar ou tiver mudado.
