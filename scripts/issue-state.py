#!/usr/bin/env python3
"""Leitor do estado de uma issue da fábrica (SPEC-107, ADR 0017).

Reproduz a tabela de estados de skills/status/estados.md, de cima para baixo.
A tabela e este programa mudam no mesmo PR. Código puro, sem rede: a coleta é
do scripts/dispatch.sh, com o gh.

Uso:
    issue-state.py branch <issue.json>
        A entrada é a saída de `gh issue view <nº> --json state,labels,comments`.
        Imprime a branch da issue (regra da "spec da issue" de estados.md) ou
        nada.
    issue-state.py state <pacote.json>
        O pacote é {"issue": <gh issue view>, "acao": <linha do acao-status.py
        ou null>, "prs": <gh pr list --json ... ou []>}. Imprime uma linha:

        linha=<1|1a|1b|2…13|-> etapa=<triagem|spec|implementar|revisar|-> quem=<agente|usuario> inconsistencia=<código|->

        `linha=-` é uma issue que não cai em nenhuma linha da tabela (por
        exemplo, o PR da branch já mergeado com a issue aberta); ela é tratada
        como estado do usuário. Com inconsistência, `quem=usuario` e `etapa=-`.

Arquivo ausente ou JSON inválido sai com código 2, como o acao-status.py.
"""
import json
import re
import sys
from datetime import datetime, timezone

AGENT_STAGES = ("triagem", "spec", "implementar", "revisar", "backlog", "lancamento")
AGENT = re.compile(r"^<!-- fabrica:(?:(" + "|".join(AGENT_STAGES) + r")(?:\s|-->)|(acao))")
IGNORED = re.compile(r"^<!-- fabrica:(?:licao|dispatcher|backlog par-recusado)")
BRANCH = re.compile(r"^\*\*Branch:\*\*\s*`?([A-Za-z0-9._/-]+)`?\s*$", re.M)
SHORTCUT = re.compile(r"^\*\*Atalho:\*\*\s*sim\b", re.M)
READ_UNTIL = re.compile(r"^\*\*Pedidos lidos até:\*\*\s*`?([0-9T:+.Z-]+)`?", re.M)
ACAO = re.compile(r"^estado=(\S+) etapa=(\S+)")
OLDEST = datetime.min.replace(tzinfo=timezone.utc)

CI_CONCLUSIONS = {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"}
CI_STATES = {"FAILURE", "ERROR"}
ACAO_INCONSISTENT = {
    "sem-comentario": "acao-sem-comentario",
    "sem-itens": "acao-sem-itens",
    "etapa-invalida": "acao-etapa-invalida",
}
USER_LINES = {"1", "1a", "3", "7", "9", "13", "-"}


def when(value):
    """Instante ISO 8601 em datetime com fuso; None se faltar ou for inválido."""
    if not value or not isinstance(value, str):
        return None
    try:
        moment = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def kind(body):
    """Classifica um corpo: ('agente', etapa), ('ignorado', None) ou ('usuario', None)."""
    text = (body or "").lstrip("﻿ \t\r\n")
    first = text.splitlines()[0] if text else ""
    if IGNORED.match(first):
        return "ignorado", None
    match = AGENT.match(first)
    if match:
        return "agente", match.group(1) or match.group(2)
    return "usuario", None


def classify(comments):
    """Comentários com tipo, etapa e instante, em ordem de criação."""
    items = []
    for c in comments or []:
        if not isinstance(c, dict):
            continue
        k, stage = kind(c.get("body"))
        items.append({"kind": k, "stage": stage, "at": when(c.get("createdAt")), "body": c.get("body") or ""})
    items.sort(key=lambda c: c["at"] or OLDEST)
    return items


def last(items, *stages):
    """Último comentário do agente com uma das etapas."""
    found = [c for c in items if c["kind"] == "agente" and c["stage"] in stages and c["at"]]
    return found[-1] if found else None


def new_reply(items, marker):
    """Há comentário do usuário estritamente posterior ao marcador?"""
    if marker is None:
        return False
    return any(c["kind"] == "usuario" and c["at"] and c["at"] > marker["at"] for c in items)


def spec_source(items):
    """Comentário da spec da issue pela regra de estados.md, ou None."""
    spec = last(items, "spec")
    if spec:
        return spec
    triage = last(items, "triagem")
    if triage and SHORTCUT.search(triage["body"]):
        return triage
    return None


def branch_of(issue):
    source = spec_source(classify(issue.get("comments")))
    if not source:
        return ""
    match = BRANCH.search(source["body"])
    return match.group(1) if match else ""


def pick_pr(prs):
    """O PR aberto da branch; sem aberto, o mais recente por updatedAt."""
    prs = [p for p in prs or [] if isinstance(p, dict)]
    if not prs:
        return None
    opened = [p for p in prs if str(p.get("state", "")).upper() == "OPEN"]
    if opened:
        return opened[0]
    return max(prs, key=lambda p: when(p.get("updatedAt")) or OLDEST)


def ci_failing(pr):
    for item in pr.get("statusCheckRollup") or []:
        if not isinstance(item, dict):
            continue
        if str(item.get("conclusion") or "").upper() in CI_CONCLUSIONS:
            return True
        if str(item.get("state") or "").upper() in CI_STATES:
            return True
    return False


def new_request(pr):
    """Pedido novo no PR (linha 11), pelas regras de estados.md."""
    conv = classify(pr.get("comments"))
    anchor = last(conv, "revisar")
    reference = None
    if anchor:
        match = READ_UNTIL.search(anchor["body"])
        reference = (when(match.group(1)) if match else None) or anchor["at"]

    def counts(at):
        return at is not None and (reference is None or at > reference)

    if any(c["kind"] == "usuario" and counts(c["at"]) for c in conv):
        return True
    for r in pr.get("reviews") or []:
        if not isinstance(r, dict):
            continue
        state = str(r.get("state") or "").upper()
        body = (r.get("body") or "").strip()
        if state == "PENDING" or (state == "APPROVED" and not body):
            continue
        if body and kind(body)[0] != "usuario":
            continue
        if counts(when(r.get("submittedAt"))):
            return True
    return False


def evaluate(package):
    """(linha, etapa, quem, inconsistência) do pacote."""
    issue = package.get("issue") or {}
    labels = {l.get("name", "") for l in issue.get("labels") or [] if isinstance(l, dict)}
    items = classify(issue.get("comments"))
    pr = pick_pr(package.get("prs"))
    pr_open = pr is not None and str(pr.get("state", "")).upper() == "OPEN"

    # Inconsistências que não dependem da linha.
    inconsistency = "-"
    if "spec-aprovada" in labels and spec_source(items) is None:
        inconsistency = "spec-aprovada-sem-spec"
    elif "pronto-revisao" in labels and not pr_open:
        inconsistency = "pronto-revisao-sem-pr"
    elif (pr is not None and not pr_open and not pr.get("mergedAt")
          and str(issue.get("state") or "OPEN").upper() == "OPEN"):
        inconsistency = "pr-fechado-sem-merge"

    def result(lin, stage="-", inc=None):
        inc = inconsistency if inc is None else inc
        if lin in USER_LINES or inc != "-":
            return lin, "-", "usuario", inc
        return lin, stage, "agente", inc

    if "escalonado" in labels:
        return result("1")
    if "acao-externa" in labels:
        match = ACAO.match(package.get("acao") or "")
        state, stage = match.groups() if match else ("sem-comentario", "-")
        if state == "pendente":
            return result("1a")
        if state == "concluida" and stage in ("implementar", "revisar"):
            return result("1b", stage)
        return result("1a", inc=ACAO_INCONSISTENT.get(state, "acao-etapa-invalida"))

    triage = last(items, "triagem")
    spec = last(items, "spec")
    if triage is None:
        return result("2", "triagem")
    if "precisa-info" in labels:
        marker = last(items, "triagem", "spec")
        if not new_reply(items, marker):
            return result("3")
        return result("4", marker["stage"])
    approved = "spec-aprovada" in labels
    ready = "spec-pronta" in labels
    if not ready and not approved and spec is None:
        return result("5", "spec")
    if ready and not approved:
        shortcut = spec is None and SHORTCUT.search(triage["body"]) is not None
        if new_reply(items, spec) or (shortcut and new_reply(items, triage)):
            return result("6", "spec")
        return result("7")
    if approved and pr is None:
        return result("8", "implementar")
    if pr_open:
        if pr.get("isDraft"):
            return result("9")
        if ci_failing(pr):
            return result("10", "revisar")
        if str(pr.get("reviewDecision") or "").upper() == "CHANGES_REQUESTED" or new_request(pr):
            return result("11", "revisar")
        if "pronto-revisao" not in labels:
            return result("12", "revisar")
        return result("13")
    return result("-")


def load(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("a entrada não é um objeto")
    return data


def main(argv):
    if len(argv) != 3 or argv[1] not in ("branch", "state"):
        print("uso: issue-state.py branch <issue.json> | state <pacote.json>", file=sys.stderr)
        return 2
    try:
        data = load(argv[2])
    except (OSError, ValueError) as error:
        print(f"issue-state: não consegui ler {argv[2]}: {error}", file=sys.stderr)
        return 2
    if argv[1] == "branch":
        branch = branch_of(data)
        if branch:
            print(branch)
        return 0
    print("linha=%s etapa=%s quem=%s inconsistencia=%s" % evaluate(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
