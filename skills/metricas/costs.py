#!/usr/bin/env python3
"""Soma as linhas de custo (SPEC-58) dos comentários de uma issue e do seu PR.

Uso: python3 costs.py <comentarios-issue.json> <comentarios-pr.json | ->

Cada arquivo é a saída de
`gh api repos/<repo>/issues/<nº>/comments --paginate --slurp` (uma lista de
páginas) ou uma lista simples de comentários. `-` indica que não há PR.

Imprime um JSON com `medida`, `tokens` e `trabalho_min`. A issue é medida
quando cada comentário de triagem e de spec da issue e cada resposta do
revisar no PR tem a linha de custo da própria etapa, e nenhuma linha diz
`tokens=nao-medido` nem `parcial=sim` (SPEC-62). Sem isso, `tokens` e `trabalho_min` saem como null.
"""
import json
import re
import sys
from datetime import datetime

COST_LINE = re.compile(r"^<!-- fabrica:custo (?P<fields>[^>]*?) -->\s*$", re.MULTILINE)
COUNTERS = ("entrada", "saida", "cache_escrita", "cache_leitura")
# Marcador do comentário → etapa cuja linha ele precisa ter.
REQUIRED_ISSUE = {"<!-- fabrica:triagem -->": "triagem", "<!-- fabrica:spec -->": "spec"}
REQUIRED_PR = {"<!-- fabrica:revisar -->": "revisar"}


def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def load(path):
    if path == "-":
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if data and isinstance(data[0], list):
        data = [comment for page in data for comment in page]
    return data


def cost_lines(body):
    lines = []
    for match in COST_LINE.finditer(body or ""):
        fields = dict(item.split("=", 1) for item in match.group("fields").split() if "=" in item)
        lines.append(fields)
    return lines


def main():
    issue_comments, pr_comments = load(sys.argv[1]), load(sys.argv[2])
    measured = False
    lines = []
    complete = True
    for comments, required in ((issue_comments, REQUIRED_ISSUE), (pr_comments, REQUIRED_PR)):
        for comment in comments:
            body = (comment.get("body") or "").lstrip()
            found = cost_lines(body)
            lines.extend(found)
            for marker, stage in required.items():
                if body.startswith(marker):
                    measured = True
                    if not any(line.get("etapa") == stage for line in found):
                        complete = False

    tokens = 0
    work_seconds = 0.0
    for line in lines:
        if line.get("tokens") == "nao-medido" or not all(line.get(c, "").isdigit() for c in COUNTERS):
            complete = False
            continue
        if line.get("parcial") == "sim":
            # A soma pode estar abaixo do real: a issue deixa de ser medida.
            complete = False
        tokens += sum(int(line[c]) for c in COUNTERS)
        try:
            work_seconds += max((parse(line["fim"]) - parse(line["inicio"])).total_seconds(), 0)
        except (KeyError, ValueError):
            complete = False

    medida = measured and complete
    print(json.dumps({
        "medida": medida,
        "tokens": tokens if medida else None,
        "trabalho_min": round(work_seconds / 60) if medida else None,
    }))


if __name__ == "__main__":
    main()
