#!/usr/bin/env python3
"""Calcula indicadores pós-merge (SPEC-231) para um repositório no período.

Uso: python3 quality.py <prs-merged.json> <bugs.json> [--prs-entregues <n1> <n2> ...]

Cada arquivo JSON é a saída de `gh search prs` / `gh search issues` (lista simples
ou lista de páginas). `-` indica entrada vazia.

Imprime um JSON com `revertidos` e `bugs_pos_merge` (inteiros, nunca null).
"""
import argparse
import json
import re
import sys

REVERT_TITLE = re.compile(r"^revert\b", re.IGNORECASE)
REVERT_BODY_PR = re.compile(
    r"\breverts\s+(?:[a-z0-9._-]+/[a-z0-9._-]+)?#\d+",
    re.IGNORECASE,
)
REVERT_BODY_COMMIT = re.compile(r"\bthis reverts commit\b", re.IGNORECASE)


def load(path):
    """Carrega JSON de lista simples ou paginada (lista de listas)."""
    if path == "-":
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if data and isinstance(data[0], list):
        return [item for page in data for item in page]
    return data


def is_revert_pr(pr):
    """Retorna True se o PR indica reversão pelo título ou corpo."""
    title = pr.get("title") or ""
    body = pr.get("body") or ""
    return bool(
        REVERT_TITLE.search(title)
        or REVERT_BODY_PR.search(body)
        or REVERT_BODY_COMMIT.search(body)
    )


def cites_any_pr(issue, pr_patterns):
    """Retorna True se título ou corpo da issue cita algum PR entregue."""
    if not pr_patterns:
        return False
    text = f"{issue.get('title') or ''}\n{issue.get('body') or ''}"
    return any(pattern.search(text) for pattern in pr_patterns)


def build_pr_patterns(prs):
    """Compila regexes para casar #<nº> ou /pull/<nº> dos PRs entregues."""
    patterns = []
    for pr in dict.fromkeys(prs):
        num = re.escape(str(pr).lstrip("#"))
        patterns.append(re.compile(rf"(?:(?<![0-9/])#|/pull/){num}\b"))
    return patterns


def main():
    parser = argparse.ArgumentParser(description="Calcula indicadores pós-merge.")
    parser.add_argument("prs_merged", help="JSON de PRs merged no período (ou -)")
    parser.add_argument("bugs", help="JSON de issues bug abertas no período (ou -)")
    parser.add_argument(
        "--prs-entregues",
        nargs="*",
        default=[],
        help="Números dos PRs das issues entregues no período",
    )
    args = parser.parse_args()

    prs_merged = load(args.prs_merged)
    bugs = load(args.bugs)
    pr_patterns = build_pr_patterns(args.prs_entregues)

    revertidos = sum(1 for pr in prs_merged if is_revert_pr(pr))
    bugs_pos_merge = sum(1 for issue in bugs if cites_any_pr(issue, pr_patterns))

    print(json.dumps({"revertidos": revertidos, "bugs_pos_merge": bugs_pos_merge}))


if __name__ == "__main__":
    main()
