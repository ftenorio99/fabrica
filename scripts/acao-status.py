#!/usr/bin/env python3
"""Estado da ação externa de uma issue (SPEC-95, ADR 0012).

Uso: python3 scripts/acao-status.py [--lancamento] <comentários.json>

A entrada é a saída de
`gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` (lista de
páginas) ou uma lista simples de comentários, com `body`, `created_at` e
`html_url`. A saída é uma linha:

    estado=<pendente|concluida|sem-comentario|sem-itens|etapa-invalida> etapa=<etapa ou -> marcados=<k> total=<n> url=<html_url ou ->

Vale o comentário de ação mais recente pela data de criação. Arquivo ausente
ou JSON inválido sai com código 2.

Sem opção, as etapas válidas no marcador são `implementar` e `revisar`. Com
`--lancamento` (SPEC-96), a única válida é `lancamento`, a da issue de runbook
do `/fabrica:lancamento`; assim uma issue de agente com `etapa=lancamento`
continua sendo `etapa-invalida`.
"""
import json
import re
import sys

MARKER = re.compile(r"^<!-- fabrica:acao(?:\s+etapa=(\S*))?\s*-->")
ITEM = re.compile(r"^\s*[-*] \[( |x|X)\] ")
FENCE = re.compile(r"^\s*```")
STAGES = {"implementar", "revisar"}
LAUNCH_STAGES = {"lancamento"}


def flatten(data):
    """Aceita a lista de páginas do --slurp ou uma lista simples."""
    if not isinstance(data, list):
        raise ValueError("a entrada não é uma lista")
    comments = []
    for entry in data:
        if isinstance(entry, list):
            comments.extend(entry)
        else:
            comments.append(entry)
    return comments


def count_items(body):
    """Conta os itens da checklist, ignorando os blocos de código."""
    checked = total = 0
    in_fence = False
    for line in body.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = ITEM.match(line)
        if match:
            total += 1
            if match.group(1) in "xX":
                checked += 1
    return checked, total


def status(comments, stages=STAGES):
    actions = []
    for comment in comments:
        if not isinstance(comment, dict):
            continue
        body = comment.get("body") or ""
        first_line = body.lstrip("﻿").splitlines()[0] if body else ""
        match = MARKER.match(first_line)
        if match:
            actions.append((comment.get("created_at") or "", comment, match.group(1)))
    if not actions:
        return "estado=sem-comentario etapa=- marcados=0 total=0 url=-"
    actions.sort(key=lambda item: item[0])
    _, comment, stage = actions[-1]
    url = comment.get("html_url") or "-"
    checked, total = count_items(comment.get("body") or "")
    if stage not in stages:
        state = "etapa-invalida"
        stage = stage or "-"
    elif total == 0:
        state = "sem-itens"
    elif checked == total:
        state = "concluida"
    else:
        state = "pendente"
    return f"estado={state} etapa={stage} marcados={checked} total={total} url={url}"


def main(argv):
    args = argv[1:]
    stages = STAGES
    if args and args[0] == "--lancamento":
        stages = LAUNCH_STAGES
        args = args[1:]
    if len(args) != 1:
        print("uso: acao-status.py [--lancamento] <comentários.json>", file=sys.stderr)
        return 2
    path = args[0]
    try:
        with open(path, encoding="utf-8") as handle:
            comments = flatten(json.load(handle))
    except (OSError, ValueError) as error:
        print(f"acao-status: não consegui ler {path}: {error}", file=sys.stderr)
        return 2
    print(status(comments, stages))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
