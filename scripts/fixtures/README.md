# Arquivos de teste

Cópias fiéis de versões antigas, usadas só pelos testes. Não são chamadas pelas skills nem pelos hooks, e não devem ser editadas.

| Arquivo | Origem | sha256 | Uso |
|---|---|---|---|
| `setup-githooks-de4c39a.sh` | `scripts/setup-githooks.sh` do commit `de4c39a` (blob `b411b7d28d92a7a36eae6c126c707c7f771ad682`), byte a byte | `611640e299b1fc2f57cba408dc81cb0430b2e5f020aaf85722066c70b433841a` | `scripts/test-setup-githooks.sh` gera com ele as instalações legadas do CA8 da SPEC-246. Fica versionado porque o checkout raso do CI não tem o commit `de4c39a`. |

O teste confere o sha256 antes de usar a cópia e falha com uma mensagem clara se ela faltar ou tiver mudado.
