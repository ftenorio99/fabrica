#!/usr/bin/env python3
"""Soma os tokens de uma etapa da fábrica a partir do log da sessão do Claude Code.

Uso: python3 stage-usage.py --stage <etapa> --since <ISO UTC> [--exact]

Lê ~/.claude/projects/*/$CLAUDE_CODE_SESSION_ID.jsonl e os logs dos
subagentes em <sessão>/subagents/*.jsonl, soma o `usage` das respostas com
`timestamp` entre o início efetivo e agora (cada `message.id` uma vez) e
imprime a linha de custo da SPEC-58.

SPEC-62:
- O Claude Code grava o log com atraso. Antes de somar, o script espera o log
  principal ter a entrada da resposta que chamou o script, de no máximo 10 s
  antes de agora, por até 30 s (FABRICA_STAGE_USAGE_TIMEOUT). Se o prazo
  acabar, soma o que houver e acrescenta `parcial=sim`.
- O início efetivo recua do --since até a última mensagem do usuário ou até
  a última chamada anterior deste script, o que for mais recente, em no
  máximo 30 min. --exact desliga o recuo.

SPEC-66: a chamada anterior do script vale como marco até 1 s depois do
--since, que vem cortado em segundos do fim da etapa anterior.

Sem log aproveitável, imprime a linha com `tokens=nao-medido`. Sai sempre com
código 0, para nunca derrubar a etapa.
"""
import argparse
import json
import math
import os
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

STAGES = ("triagem", "spec", "implementar", "revisar")
FIELDS = (
    ("entrada", "input_tokens"),
    ("saida", "output_tokens"),
    ("cache_escrita", "cache_creation_input_tokens"),
    ("cache_leitura", "cache_read_input_tokens"),
)
FRESH_WINDOW = timedelta(seconds=10)
MAX_LOOKBACK = timedelta(minutes=30)
# O fim da etapa anterior sai cortado em segundos, então a chamada que a fechou
# fica até 1 s depois do --since da etapa seguinte (SPEC-66).
CALL_MARGIN = timedelta(seconds=1)
POLL_SECONDS = 0.5
TAIL_BYTES = 512 * 1024
SCRIPT_NAME = "stage-usage.py"


def parse(ts):
    moment = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment


def iso(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def session_logs(session_id):
    """Devolve o log da sessão e os dos subagentes, ou [] se não achar."""
    projects = Path.home() / ".claude" / "projects"
    for main_log in sorted(projects.glob(f"*/{session_id}.jsonl")):
        subagents = sorted((main_log.parent / session_id / "subagents").glob("*.jsonl"))
        return [main_log] + subagents
    return []


def entries(path, tail=False):
    """Lê as entradas JSON de um log, ignorando linhas inválidas."""
    try:
        with path.open("rb") as f:
            if tail:
                size = f.seek(0, os.SEEK_END)
                f.seek(max(size - TAIL_BYTES, 0))
            data = f.read()
    except OSError:
        return
    lines = data.decode("utf-8", errors="replace").splitlines()
    if tail and len(data) >= TAIL_BYTES:
        lines = lines[1:]  # a primeira linha pode ter sido cortada no meio
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            yield entry


def timestamp(entry):
    try:
        return parse(entry["timestamp"])
    except (KeyError, TypeError, ValueError, AttributeError):
        return None


def wait_for_log(main_log, until, timeout):
    """Espera a entrada da resposta que chamou este script (até 10 s antes de
    until). Ela é gravada depois das anteriores. Devolve False no prazo."""
    deadline = time.monotonic() + timeout
    while True:
        for entry in entries(main_log, tail=True):
            moment = timestamp(entry)
            if moment is not None and until - FRESH_WINDOW <= moment <= until and calls_this_script(entry):
                return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(POLL_SECONDS)


def is_user_prompt(entry):
    """Mensagem do usuário que não é resultado de ferramenta."""
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    origin = entry.get("origin")
    if isinstance(origin, dict) and origin.get("kind") not in (None, "human"):
        return False
    message = entry.get("message")
    if not isinstance(message, dict):
        return False
    content = message.get("content")
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        return not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return False


def calls_this_script(entry):
    """Resposta do agente com uma chamada de ferramenta que roda este script."""
    if entry.get("type") != "assistant":
        return False
    message = entry.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, list):
        return False
    for block in content:
        if isinstance(block, dict) and block.get("type") == "tool_use":
            command = (block.get("input") or {}).get("command")
            if isinstance(command, str) and SCRIPT_NAME in command:
                return True
    return False


def effective_start(main_log, since):
    """Recua o início até a última mensagem do usuário ou chamada anterior do script.

    A chamada do script vale como marco até CALL_MARGIN depois do --since,
    porque o --since vindo do fim da etapa anterior perdeu os milissegundos.
    A mensagem do usuário vale só até o --since.
    """
    floor = since - MAX_LOOKBACK
    start = None
    for entry in entries(main_log):
        moment = timestamp(entry)
        if moment is None or not floor <= moment <= since + CALL_MARGIN:
            continue
        if is_user_prompt(entry):
            if moment > since:
                continue
            candidate = moment
        elif calls_this_script(entry):
            # A resposta que chamou o script pertence à etapa anterior.
            candidate = moment + timedelta(milliseconds=1)
        else:
            continue
        if start is None or candidate > start:
            start = candidate
    return start if start is not None else since


def sum_usage(logs, since, until):
    """Soma o usage por message.id no intervalo. Devolve None sem nenhuma resposta."""
    seen = {}
    for log in logs:
        for entry in entries(log):
            message = entry.get("message")
            if not isinstance(message, dict) or not isinstance(message.get("usage"), dict):
                continue
            moment = timestamp(entry)
            if moment is None or not since <= moment <= until:
                continue
            key = message.get("id") or entry.get("requestId") or entry.get("uuid") or id(entry)
            # A mesma resposta se repete em várias linhas com o mesmo usage.
            seen.setdefault(key, message["usage"])
    if not seen:
        return None
    totals = {}
    for name, field in FIELDS:
        total = 0
        for usage in seen.values():
            value = usage.get(field)
            if isinstance(value, int):
                total += value
        totals[name] = total
    return totals


def timeout_seconds():
    try:
        value = float(os.environ.get("FABRICA_STAGE_USAGE_TIMEOUT", "30"))
    except ValueError:
        return 30.0
    # nan ou inf travariam a espera: a etapa nunca pode ficar presa aqui.
    return max(value, 0) if math.isfinite(value) else 30.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True, choices=STAGES)
    parser.add_argument("--since", required=True)
    parser.add_argument("--exact", action="store_true")
    args = parser.parse_args()

    until = datetime.now(timezone.utc)
    try:
        since = parse(args.since)
    except ValueError:
        since = None

    totals = None
    partial = False
    start = since
    session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "").strip()
    if since is not None and session_id and "/" not in session_id:
        try:
            logs = session_logs(session_id)
            if logs:
                partial = not wait_for_log(logs[0], until, timeout_seconds())
                if not args.exact:
                    start = effective_start(logs[0], since)
                totals = sum_usage(logs, start, until)
        except Exception:  # nunca derrubar a etapa por causa do log
            totals = None

    shown_start = iso(start) if start is not None else args.since
    if totals is None:
        counters = "tokens=nao-medido"
    else:
        counters = " ".join(f"{name}={totals[name]}" for name, _ in FIELDS)
        if partial:
            counters += " parcial=sim"
    print(f"<!-- fabrica:custo etapa={args.stage} inicio={shown_start} fim={iso(until)} {counters} -->")


if __name__ == "__main__":
    main()
