"""Compara cada execução com a fachada congelada de de4c39a."""

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


HERE = pathlib.Path(__file__).resolve().parent
PROBES = ("harness.sh", "sbx-context.sh", "setup-isolation.sh")

STARTUP = r"""
printf '%s\n' "${0##*/}" >> "$TEST_STARTUPS"
if [[ ${0##*/} == stage-model.sh ]]; then
  case "$TEST_CASE" in
    local) unset BASH_ENV; BASH_ENV="$TEST_SECONDARY" ;;
    desexportada) export -n BASH_ENV ;;
    removida) unset BASH_ENV ;;
    alterada) BASH_ENV="$TEST_SECONDARY" ;;
    allexport) set -a ;;
    readonly) readonly BASH_ENV ;;
    array) unset BASH_ENV; declare -ax BASH_ENV=("$TEST_SECONDARY") ;;
    nameref) unset BASH_ENV; declare -nx BASH_ENV=secondary ;;
  esac
fi
"""

RECORDER = r"""
import json
import os
from pathlib import Path
import sys

if len(sys.argv) > 1 and sys.argv[1] == "--probe":
    role, pid, *args = sys.argv[2:]
    # Leia o ambiente do exec original da sonda, antes do BASH_ENV.
    raw = Path(f"/proc/{pid}/environ").read_bytes()
    received = sorted(os.fsdecode(item) for item in raw.split(b"\0") if item)
    response = {
        "harness.sh": "claude",
        "sbx-context.sh": "onde vm",
        "setup-isolation.sh": "sbx",
    }[role]
else:
    role, args = "delegado", sys.argv[1:]
    received = None
    response = "saída delegada"

record = {
    "role": role, "received": received, "environment": dict(os.environ),
    "args": args, "cwd": os.getcwd(),
}
if role == "delegado":
    record["pid"] = os.getpid()
    record["stdin"] = sys.stdin.buffer.read().hex()
    print("diagnóstico delegado", file=sys.stderr)
with open(os.environ["TEST_LOG"], "a", encoding="utf-8") as log:
    print(json.dumps(record, ensure_ascii=True), file=log)
print(response)
sys.exit(17 if role == "delegado" else 0)
"""


def observe(lab, facade, module, scenario, env, bash):
    scripts = lab / "plugin/scripts"
    shutil.copyfile(facade, scripts / "stage-model.sh")
    shutil.copyfile(module, scripts / "claude-exec.sh")
    log = pathlib.Path(env["TEST_LOG"])
    startups = pathlib.Path(env["TEST_STARTUPS"])
    log.write_text("")
    startups.write_text("")
    input_bytes = b"stdin preservado\n"
    with subprocess.Popen(
        [bash, str(scripts / "stage-model.sh"), "run", "implementar", "247", "modelo:opus"],
        cwd=lab, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ) as process:
        try:
            out, err = process.communicate(input_bytes, timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
    records = [json.loads(line) for line in log.read_text().splitlines()]
    roles = [record["role"] for record in records]
    if roles != [*PROBES, "delegado"]:
        raise ValueError(f"{scenario}: sequência de processos inesperada: {roles}")
    if records[-1].pop("pid") != process.pid or records[-1]["stdin"] != input_bytes.hex():
        raise ValueError(f"{scenario}: o delegado perdeu a identidade ou a entrada da fachada")
    return {"records": records, "startup": startups.read_text(), "result": (process.returncode, out, err)}


def compare(lab, scripts, bash):
    target = lab / "plugin/scripts"
    target.mkdir(parents=True)
    for name in ("home", "tmp"):
        (lab / name).mkdir()
    startup, secondary, delegate = (lab / name for name in ("startup.sh", "secondary", "delegate"))
    startup.write_text(STARTUP)
    secondary.write_text('printf "alternativo %s\\n" "${0##*/}" >> "$TEST_STARTUPS"\n')
    delegate.write_text(f"#!{sys.executable}\n" + RECORDER)
    delegate.chmod(0o700)
    for name in PROBES:
        (target / name).write_text(
            f'#!/usr/bin/env bash\n"{sys.executable}" "$FABRICA_CLAUDE_BIN" '
            '--probe "${0##*/}" "$BASHPID" "$@"\n'
        )

    env = {
        "PATH": "/usr/bin:/bin", "HOME": str(lab / "home"), "TMPDIR": str(lab / "tmp"),
        "FABRICA_CLAUDE_BIN": str(delegate),
        "FABRICA_MODELS_FILE": str(HERE.parent / "skills/avancar/modelos.md"),
        "TEST_SECONDARY": str(secondary), "TEST_STARTUPS": str(lab / "startups"),
        "TEST_LOG": str(lab / "log"),
    }
    scenarios = {
        "ausente": {}, "vazia": {"BASH_ENV": ""}, "exportada": {"BASH_ENV": str(startup)},
        "model herdada": {"model": "modelo preexistente"},
        "plugin herdado": {"plugin_root": "raiz anterior", "plugins_dir": "cache anterior"},
    }
    for name in ("local", "desexportada", "removida", "alterada", "allexport", "readonly", "array"):
        scenarios[name] = {"BASH_ENV": str(startup)}
    if subprocess.run([bash, "-c", "declare -n teste=alvo"], env=env, capture_output=True).returncode == 0:
        scenarios["nameref"] = {"BASH_ENV": str(startup)}
    else:
        print("PULADO nameref: recurso ausente neste Bash")

    failures = 0
    for scenario, variables in scenarios.items():
        inputs = env | variables | {"TEST_CASE": scenario}
        module = scripts / "claude-exec.sh"
        base = observe(lab, HERE / "fixtures/stage-model-de4c39a.sh", module, scenario, inputs, bash)
        got = observe(lab, scripts / "stage-model.sh", module, scenario, inputs, bash)
        if base == got:
            print(f"OK {scenario}")
            continue
        failures += 1
        print(f"DIFERENÇA {scenario}")
        for expected, actual in zip(base["records"], got["records"]):
            fields = [key for key in expected if expected[key] != actual[key]]
            if fields:
                print(f"  {expected['role']}: {', '.join(fields)}")
                keys = expected["environment"].keys() | actual["environment"].keys()
                changed = sorted(k for k in keys if expected["environment"].get(k) != actual["environment"].get(k))
                if changed:
                    print("    ambiente: " + ", ".join(changed))
        for field in ("startup", "result"):
            if base[field] != got[field]:
                print(f"  difere: {field}")
    return bool(failures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scripts", type=pathlib.Path, default=HERE)
    args = parser.parse_args()
    bash = shutil.which("bash")
    if not bash:
        parser.error("bash indisponível")
    with tempfile.TemporaryDirectory(prefix="fabrica-stage-env-") as temp:
        return compare(pathlib.Path(temp), args.scripts, bash)


if __name__ == "__main__":
    raise SystemExit(main())
