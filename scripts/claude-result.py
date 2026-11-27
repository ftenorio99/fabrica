#!/usr/bin/env python3
"""Normaliza o resultado técnico de uma execução Claude já encerrada."""

import argparse
import json
from pathlib import Path


class ResultArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        # argparse pode reproduzir valores fornecidos na linha de comando.
        self.exit(2, "claude-result: argumentos inválidos; consulte --help.\n")


def read_result(path):
    try:
        with path.open(encoding="utf-8") as stream:
            result = json.load(stream)
    except (OSError, ValueError, RecursionError):
        return {}
    return result if isinstance(result, dict) else {}


def has_permission_denial(result):
    denials = result.get("permission_denials")
    return isinstance(denials, list) and any(
        isinstance(denial, dict)
        and isinstance(name := denial.get("tool_name"), str)
        and name.strip()
        for denial in denials
    )


def classify(result, exit_code, evidence):
    if evidence == "configuration":
        return "failed", "configuration", "pre_exec"
    if evidence == "timeout":
        return "timed_out", "timeout", "observer"
    if evidence == "cancellation":
        return "cancelled", "cancellation", "observer"

    origin = "executor" if evidence == "executor_exit" else None
    is_error = result.get("is_error")
    if exit_code == 0 and is_error is False:
        return "succeeded", None, origin
    if exit_code not in (None, 0) or is_error is True:
        reason = "permission_denied" if has_permission_denial(result) else "execution"
        return ("blocked" if reason == "permission_denied" else "failed"), reason, origin
    if is_error is not False:
        return "failed", "invalid_result", origin
    # Mesmo com is_error=false, falta observar um código zero.
    return "failed", None, origin


def main():
    parser = ResultArgumentParser(description=__doc__)
    parser.add_argument("raw_result", type=Path, help="arquivo com stdout bruto do Claude")
    parser.add_argument("--exit-code", type=int, help="código de saída observado")
    parser.add_argument(
        "--evidence",
        choices=("configuration", "executor_exit", "timeout", "cancellation"),
        help="fato observado pelo chamador, independente do stdout e do código",
    )
    args = parser.parse_args()
    if args.evidence == "executor_exit" and args.exit_code is None:
        parser.error("executor_exit requer --exit-code")

    result = read_result(args.raw_result)
    status, reason, origin = classify(result, args.exit_code, args.evidence)
    normalized = {
        "version": 1,
        "runtime": "claude-code",
        "status": status,
        "reason": reason,
        "exit_code": args.exit_code,
        "origin": origin,
    }
    duration = result.get("duration_ms")
    if type(duration) is int and duration >= 0:
        normalized["metadata"] = {"duration_ms": duration}
    print(json.dumps(normalized))


if __name__ == "__main__":
    main()
