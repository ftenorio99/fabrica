#!/usr/bin/env python3
"""Calcula os tempos de uma issue da fábrica a partir da timeline do GitHub.

Uso: python3 durations.py <created_at> <closed_at> <timeline.json>

O timeline.json é a saída de
`gh api repos/<repo>/issues/<nº>/timeline --paginate --slurp`
(uma lista de páginas) ou uma lista simples de eventos.

Imprime um JSON com os minutos de cada métrica (arredondados) e o número
de escalonamentos. Campos sem dado, como uma issue que nunca recebeu
`agente`, saem como null.
"""
import json
import sys
from datetime import datetime

# Labels que, enquanto estão na issue, indicam espera pelo usuário.
USER_GATES = {"precisa-info", "escalonado", "pronto-revisao"}


def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def minutes(delta):
    return round(delta.total_seconds() / 60)


def waiting_for_user(labels):
    if labels & USER_GATES:
        return True
    # Spec pronta sem aprovação: estado "Spec para aprovar" do estados.md.
    return "spec-pronta" in labels and "spec-aprovada" not in labels


def main():
    created, closed = parse(sys.argv[1]), parse(sys.argv[2])
    with open(sys.argv[3]) as f:
        data = json.load(f)
    if data and isinstance(data[0], list):
        data = [event for page in data for event in page]

    events = sorted(
        (e for e in data if e.get("event") in ("labeled", "unlabeled") and e.get("label")),
        key=lambda e: e["created_at"],
    )
    agent_marks = [
        parse(e["created_at"])
        for e in events
        if e["event"] == "labeled" and e["label"]["name"] == "agente"
    ]
    result = {
        "abertura_ao_merge": minutes(closed - created),
        "antes_do_fluxo": None,
        "esperando_voce": None,
        "com_o_agente": None,
        "escalonamentos": sum(
            1 for e in events if e["event"] == "labeled" and e["label"]["name"] == "escalonado"
        ),
    }
    if not agent_marks:
        print(json.dumps(result))
        return

    start = agent_marks[0]
    labels = set()
    waiting_seconds = 0.0
    cursor = start
    # Varre os eventos em ordem: entre dois eventos, o conjunto de labels é fixo.
    for event in events + [None]:
        moment = closed if event is None else min(parse(event["created_at"]), closed)
        if moment > cursor:
            if waiting_for_user(labels):
                waiting_seconds += (moment - cursor).total_seconds()
            cursor = moment
        if event is None or moment >= closed:
            break
        name = event["label"]["name"]
        if event["event"] == "labeled":
            labels.add(name)
        else:
            labels.discard(name)

    in_flow = (closed - start).total_seconds()
    result["antes_do_fluxo"] = minutes(start - created)
    result["esperando_voce"] = round(waiting_seconds / 60)
    result["com_o_agente"] = round((in_flow - waiting_seconds) / 60)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
