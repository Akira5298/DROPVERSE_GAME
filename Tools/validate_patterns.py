#!/usr/bin/env python3
"""
Validates every pattern in Resources/Patterns/patterns.json by actually simulating it.

For each pattern and each tempo factor k (slowest, reference, fastest), a depth-first
solver searches hold/release inputs (one decision every DECISION reference-seconds,
i.e. no frame-perfect inputs) with a hitbox 1 pt larger than the game's. A pattern passes
only if a complete run is found that ends in the declared exit state.

Usage:  python3 Tools/validate_patterns.py [--pairs] [--json path]
"""
import argparse
import itertools
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import dropverse_sim as sim  # noqa: E402

K_VALUES = (0.70, 1.0, 1.41)        # folded-BPM range 90..180 -> k = bpm/128
DECISION = 0.05                     # reference seconds between input decisions
LEAD_BEATS = 2
TAIL_BEATS = 2
GAP_BEATS = 1                       # generator's minimum gap between patterns


def build(patterns):
    course = sim.Course()
    tau = LEAD_BEATS * sim.BEAT_TAU
    for i, p in enumerate(patterns):
        tau = sim.compile_pattern(course, p, tau)
        if i < len(patterns) - 1:
            tau += GAP_BEATS * sim.BEAT_TAU
    course.finalize()
    return course, tau + TAIL_BEATS * sim.BEAT_TAU


def check(patterns, k, max_jumps=sim.MAX_JUMPS):
    course, tau_end = build(patterns)
    entry = sim.state_tuple(patterns[0]["entry"])
    exit_ = sim.state_tuple(patterns[-1]["exit"])
    player = sim.Player(mode=entry[0], gs=entry[1], mini=entry[2], max_jumps=max_jumps)
    path, nodes = sim.solve(course, player, 0.0, tau_end, k / 120.0, DECISION, 1.0, exit_)
    return path is not None, nodes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=os.path.join(os.path.dirname(__file__), "..", "DROPVERSE", "Resources", "Patterns", "patterns.json"))
    ap.add_argument("--pairs", action="store_true", help="also validate every compatible pattern pair")
    ap.add_argument("--only", default=None)
    args = ap.parse_args()
    data = json.load(open(args.json))
    pats = data["patterns"]
    ids = [p["id"] for p in pats]
    assert len(ids) == len(set(ids)), "duplicate pattern ids"
    failures = 0
    t0 = time.time()
    for p in pats:
        if args.only and args.only not in p["id"]:
            continue
        results = []
        for k in K_VALUES:
            ok, nodes = check([p], k)
            results.append((k, ok, nodes))
        good = all(r[1] for r in results)
        failures += 0 if good else 1
        print(("PASS " if good else "FAIL ") + p["id"].ljust(26) + "  " + "  ".join(f"k={k}:{'ok' if ok else 'NO'}({n})" for k, ok, n in results))
    if args.pairs:
        pair_fail = 0
        count = 0
        for a, b in itertools.product(pats, pats):
            if sim.state_tuple(a["exit"]) != sim.state_tuple(b["entry"]) or a["id"] == b["id"]:
                continue
            for k in (K_VALUES[0], K_VALUES[-1]):
                count += 1
                ok, _ = check([a, b], k)
                if not ok:
                    pair_fail += 1
                    print(f"PAIR FAIL {a['id']} -> {b['id']} at k={k}")
        print(f"pairs checked: {count}, failures: {pair_fail}")
        failures += pair_fail
    print(f"done in {time.time() - t0:.1f}s, failing: {failures}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
