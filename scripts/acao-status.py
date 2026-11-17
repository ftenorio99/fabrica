#!/usr/bin/env python3
"""Estado da ação externa de uma issue (SPEC-95, ADR 0012).

Uso: python3 scripts/acao-status.py <comentários.json>

A entrada é a saída de
`gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` (lista de
páginas) ou uma lista simples de comentários, com `body`, `created_at` e
`html_url`. A saída é uma linha:

    estado=<pendente|concluida|sem-comentario|sem-itens|etapa-invalida> etapa=<etapa ou -> marcados=<k> total=<n> url=<html_url ou ->

Vale o comentário de ação mais recente pela data de criação. Arquivo ausente
ou JSON inválido sai com código 2.
"""
import json
import re
import sys

MARKER = re.compile(r"^<!-- fabrica:acao(?:\s+etapa=(\S*))?\s*-->")
ITEM = re.compile(r"^\s*[-*] \[( |x|X)\] ")
FENCE = re.compile(r"^\s*```")
STAGES = {"implementar", "revisar"}


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


def status(comments):
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
    if stage not in STAGES:
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
    if len(argv) != 2:
        print("uso: acao-status.py <comentários.json>", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            comments = flatten(json.load(handle))
    except (OSError, ValueError) as error:
        print(f"acao-status: não consegui ler {argv[1]}: {error}", file=sys.stderr)
        return 2
    print(status(comments))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
