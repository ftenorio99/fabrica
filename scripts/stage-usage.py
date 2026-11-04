#!/usr/bin/env python3
"""Soma os tokens de uma etapa da fábrica a partir do log da sessão do Claude Code.

Uso: python3 stage-usage.py --stage <etapa> --since <ISO UTC>

Lê ~/.claude/projects/*/$CLAUDE_CODE_SESSION_ID.jsonl e os logs dos
subagentes em <sessão>/subagents/*.jsonl, soma o `usage` das respostas com
`timestamp` entre --since e agora (cada `message.id` uma vez) e imprime a
linha de custo da SPEC-58. Sem log aproveitável, imprime a linha com
`tokens=nao-medido`. Sai sempre com código 0, para nunca derrubar a etapa.
"""
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

STAGES = ("triagem", "spec", "implementar", "revisar")
FIELDS = (
    ("entrada", "input_tokens"),
    ("saida", "output_tokens"),
    ("cache_escrita", "cache_creation_input_tokens"),
    ("cache_leitura", "cache_read_input_tokens"),
)


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


def sum_usage(logs, since, until):
    """Soma o usage por message.id no intervalo. Devolve None sem nenhuma resposta."""
    seen = {}
    for log in logs:
        try:
            lines = log.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with lines:
            for line in lines:
                try:
                    entry = json.loads(line)
                    message = entry.get("message")
                    if not isinstance(message, dict) or not isinstance(message.get("usage"), dict):
                        continue
                    moment = parse(entry["timestamp"])
                except (ValueError, KeyError, TypeError, AttributeError):
                    continue
                if not since <= moment <= until:
                    continue
                key = message.get("id") or entry.get("requestId") or entry.get("uuid") or line
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", required=True, choices=STAGES)
    parser.add_argument("--since", required=True)
    args = parser.parse_args()

    until = datetime.now(timezone.utc)
    try:
        since = parse(args.since)
    except ValueError:
        since = None

    totals = None
    session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "").strip()
    if since is not None and session_id and "/" not in session_id:
        try:
            totals = sum_usage(session_logs(session_id), since, until)
        except Exception:  # nunca derrubar a etapa por causa do log
            totals = None

    start = iso(since) if since is not None else args.since
    if totals is None:
        counters = "tokens=nao-medido"
    else:
        counters = " ".join(f"{name}={totals[name]}" for name, _ in FIELDS)
    print(f"<!-- fabrica:custo etapa={args.stage} inicio={start} fim={iso(until)} {counters} -->")


if __name__ == "__main__":
    main()
