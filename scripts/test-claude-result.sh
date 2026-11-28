#!/usr/bin/env bash
# Exercita o normalizador apenas com fixtures e arquivos temporários.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -I -B - "$script_dir/claude-result.py" <<'PY'
import json
import subprocess
import sys
import tempfile
from pathlib import Path

script = sys.argv[1]
command = [sys.executable, "-I", "-B", script]
success = b'{"is_error":false}'
failure = b'{"is_error":true}'
denied = b'{"is_error":true,"permission_denials":[{"tool_name":"Bash"}]}'
cases = [
    ("JSON mínimo", success, 0, None, "succeeded", None, None),
    ("booleano falso", b'{"type":"result","is_error":false}', 0, "executor_exit", "succeeded", None, "executor"),
    ("booleano verdadeiro", failure, 0, None, "failed", "execution", None),
    ("texto em vez de JSON", b"fixture-invalida", 0, None, "failed", "invalid_result", None),
    ("JSON truncado", b'{"is_error":false', 0, None, "failed", "invalid_result", None),
    ("stdout vazio", b"", 0, None, "failed", "invalid_result", None),
    ("codificação inválida", b"\xff", 0, None, "failed", "invalid_result", None),
    ("UTF-16 fora do formato legado", success.decode().encode("utf-16"), 0, None, "failed", "invalid_result", None),
    ("BOM fora do formato legado", b"\xef\xbb\xbf" + success, 0, None, "failed", "invalid_result", None),
    ("array em vez de objeto", b"[]", 0, None, "failed", "invalid_result", None),
    ("is_error string", b'{"is_error":"false"}', 0, None, "failed", "invalid_result", None),
    ("is_error numérico", b'{"is_error":0}', 0, None, "failed", "invalid_result", None),
    ("is_error ausente", b'{"result":"fixture"}', 0, None, "failed", "invalid_result", None),
    ("campo futuro ignorado", b'{"is_error":false,"future":{"unknown":[1]}}', 0, None, "succeeded", None, None),
    ("exit nativo prevalece sobre is_error falso", success, 7, "executor_exit", "failed", "execution", "executor"),
    ("exit não zero sem stdout", b"", 1, None, "failed", "execution", None),
    ("exit 2 da validação comprovada", b"", 2, "configuration", "failed", "configuration", "pre_exec"),
    ("exit 2 do executor", b"", 2, "executor_exit", "failed", "execution", "executor"),
    ("exit 2 de origem desconhecida", b"", 2, None, "failed", "execution", None),
    ("exit 124 sem evidência", b"", 124, None, "failed", "execution", None),
    ("exit 130 sem evidência", b"", 130, None, "failed", "execution", None),
    ("exit 143 sem evidência", b"", 143, None, "failed", "execution", None),
    ("timeout observado sem exit", b"", None, "timeout", "timed_out", "timeout", "observer"),
    ("cancelamento observado", success, 143, "cancellation", "cancelled", "cancellation", "observer"),
    ("permissão negada com is_error", denied, 0, None, "blocked", "permission_denied", None),
    ("permissão negada com exit nativo", denied, 1, "executor_exit", "blocked", "permission_denied", "executor"),
    ("denial não torna execução bem-sucedida em falha",
     b'{"is_error":false,"permission_denials":[{"tool_name":"Bash"}]}', 0, None, "succeeded", None, None),
    ("denial malformado", b'{"is_error":true,"permission_denials":"fixture"}', 0, None, "failed", "execution", None),
    ("texto de resultado não prova bloqueio nem timeout",
     b'{"is_error":true,"result":"permission denied, timeout, cancelled"}', 1, None, "failed", "execution", None),
    ("exit ausente com JSON de sucesso", success, None, None, "failed", None, None),
    ("arquivo ausente", None, 0, None, "failed", "invalid_result", None),
]


def invoke(path, code, evidence):
    args = [str(path)]
    if code is not None:
        args += ["--exit-code", str(code)]
    if evidence is not None:
        args += ["--evidence", evidence]
    return subprocess.run(command + args, capture_output=True, check=False)


with tempfile.TemporaryDirectory() as folder:
    raw = Path(folder) / "stdout bruto.json"
    for label, fixture, code, evidence, status, reason, origin in cases:
        if fixture is None:
            raw.unlink(missing_ok=True)
        else:
            raw.write_bytes(fixture)
        process = invoke(raw, code, evidence)
        assert (process.returncode, process.stderr) == (0, b""), label
        assert json.loads(process.stdout) == {
            "version": 1, "runtime": "claude-code", "status": status,
            "reason": reason, "exit_code": code, "origin": origin,
        }, label
        observed = raw.read_bytes() if raw.exists() else None
        assert observed == fixture, label

    secret = "FIXTURE_PRIVADA"
    private = {
        "is_error": True, "result": secret, "subtype": secret, "session_id": secret,
        "modelUsage": {secret: {}},
        "permission_denials": [{"tool_name": secret, "tool_input": {"command": secret}}],
        "duration_ms": 17,
    }
    raw.write_bytes(json.dumps(private, indent=2).encode() + b"\n\n")
    original = raw.read_bytes()
    process = invoke(raw, 1, "executor_exit")
    assert process.returncode == 0 and process.stderr == b""
    assert json.loads(process.stdout) == {
        "version": 1, "runtime": "claude-code", "status": "blocked",
        "reason": "permission_denied", "exit_code": 1, "origin": "executor",
        "metadata": {"duration_ms": 17},
    }
    assert secret.encode() not in process.stdout and raw.read_bytes() == original

    for duration in (secret, True, -1):
        raw.write_text(json.dumps({"is_error": False, "duration_ms": duration}))
        process = invoke(raw, 0, None)
        assert process.returncode == 0 and process.stderr == b""
        assert "metadata" not in json.loads(process.stdout)

    for args in (["--evidence", secret], ["--exit-code", secret], ["--evidence", "executor_exit"]):
        process = subprocess.run(command + [str(raw)] + args, capture_output=True, check=False)
        assert process.returncode == 2 and process.stdout == b""
        assert process.stderr == b"claude-result: argumentos inv\xc3\xa1lidos; consulte --help.\n"

print(f"{len(cases) + 7} verificações passaram")
PY
