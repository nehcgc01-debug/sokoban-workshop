#!/usr/bin/env python3
"""Summarise exported playtest logs (kuro_playtest_*.jsonl) per level.

    python tools/playtest_summary.py tester_a.jsonl tester_b.jsonl ...

Each input file is one tester. Prints one row per level in play order and a short list of
moments worth watching on the recordings (long stalls, dead ends, full hints, give-ups).
Numbers describe what happened, not why: pair them with your observation notes.
"""
import json
import pathlib
import re
import statistics
import sys
from collections import defaultdict


def _play_order():
    """V7.12: read the play order from level_catalog.gd so the two can never disagree."""
    catalog = pathlib.Path(__file__).resolve().parents[1] / "level_catalog.gd"
    found = re.search(r"(?m)^const ORDER = \[([0-9,\s]+)\]", catalog.read_text(encoding="utf-8"))
    if not found:
        raise SystemExit("Could not read ORDER from level_catalog.gd")
    order = [int(x) for x in found.group(1).split(",") if x.strip()]
    # Lab: the lab maps (12-15) follow the night's 11, as positions 12-15.
    lab = re.search(r"(?m)^const LAB_ORDER = \[([0-9,\s]+)\]", catalog.read_text(encoding="utf-8"))
    if lab:
        order += [int(x) for x in lab.group(1).split(",") if x.strip()]
    extra = re.search(r"(?m)^const LAB_EXTRA = \[([0-9,\s]+)\]", catalog.read_text(encoding="utf-8"))
    if extra:
        order += [int(x) for x in extra.group(1).split(",") if x.strip()]
    return order


ORDER = _play_order()


def load(paths):
    rows = []
    for tester, path in enumerate(paths, 1):
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    print(f"skip {path}:{n} (not JSON)", file=sys.stderr)
                    continue
                row["tester"] = tester
                rows.append(row)
    return rows


def med(values):
    return f"{statistics.median(values):.0f}" if values else "-"


def main(paths):
    rows = [r for r in load(paths) if int(r.get("level", 0)) > 0]
    if not rows:
        print("no built-in level attempts found")
        return 1
    testers = len(paths)
    by_level = defaultdict(list)
    for r in rows:
        by_level[int(r["level"])].append(r)
    print(f"{testers} tester(s), {len(rows)} attempt(s)\n")
    head = ["关", "尝试", "通过人数", "首通用时中位(秒)", "撤销中位", "重开合计", "看到第3级提示", "进入死局合计", "B回退合计", "未解离开"]
    print(" | ".join(head))
    print(" | ".join(["---"] * len(head)))
    for pos, lid in enumerate(ORDER, 1):
        attempts = by_level.get(lid, [])
        if not attempts:
            print(f"{pos:02d} | 0 | - | - | - | - | - | - | - | -")
            continue
        solvers = {r["tester"] for r in attempts if r.get("solved")}
        first_solve = []
        for t in solvers:
            mine = [r for r in attempts if r["tester"] == t]
            spent = 0.0
            for r in mine:  # time on this level until the first solve, across visits
                if r.get("solved"):
                    first_solve.append(spent + float(r.get("solve_at", r.get("seconds", 0))))
                    break
                spent += float(r.get("seconds", 0))
        print(" | ".join(str(x) for x in [
            f"{pos:02d}", len(attempts), f"{len(solvers)}/{testers}", med(first_solve),
            med([r.get("undos", 0) for r in attempts]), sum(r.get("restarts", 0) for r in attempts),
            len({r["tester"] for r in attempts if r.get("max_hint", 0) >= 3}),
            sum(r.get("dead_entries", 0) for r in attempts), sum(r.get("rewinds", 0) for r in attempts),
            sum(1 for r in attempts if r.get("end") in ("left_unsolved", "closed_unsolved")),
        ]))
    print("\nMoments to review on the recordings:")
    flagged = 0
    for r in sorted(rows, key=lambda r: (r["tester"], ORDER.index(int(r["level"])) if int(r["level"]) in ORDER else 99)):
        pos = ORDER.index(int(r["level"])) + 1 if int(r["level"]) in ORDER else r["level"]
        notes = []
        if r.get("end") in ("left_unsolved", "closed_unsolved") and float(r.get("seconds", 0)) >= 60:
            notes.append(f"gave up after {float(r['seconds']):.0f}s")
        if r.get("dead_entries", 0) >= 3:
            notes.append(f"hit a dead end {r['dead_entries']}x (first at {float(r.get('first_dead_at', 0)):.0f}s)")
        if r.get("max_hint", 0) >= 3:
            notes.append("needed the final hint")
        if r.get("tool_wasted"):
            notes.append("opened the tool crate at full pulls (rope wasted)")
        if r.get("solved") and float(r.get("solve_at", 0)) >= 300:
            notes.append(f"solved but took {float(r['solve_at']):.0f}s")
        if notes:
            flagged += 1
            print(f"  tester {r['tester']} · level {pos:02d} · " + "; ".join(notes))
    if not flagged:
        print("  none")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
