#!/usr/bin/env python3
"""
End-to-end check: generates whole stages with the reference generator and proves each
one completable with the solver bot at the slowest and fastest tempo factors.
Also prints a golden pattern sequence used by the Swift unit tests to detect port drift.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import dropverse_sim as sim  # noqa: E402
import dropverse_gen as gen  # noqa: E402

PATTERNS = os.path.join(os.path.dirname(__file__), "..", "DROPVERSE", "Resources", "Patterns", "patterns.json")


def stage_course(placed, total_beats):
    course = sim.Course()
    for p, b in placed:
        sim.compile_pattern(course, p, b * sim.BEAT_TAU)
    course.finalize()
    return course, total_beats * sim.BEAT_TAU


def main():
    pats = json.load(open(PATTERNS))["patterns"]
    print("golden stage=1 seed=42 beats=64:", [p["id"] for p, _ in gen.generate(pats, 1, 42, 64)])
    print("golden stage=12 seed=7 beats=80:", [p["id"] for p, _ in gen.generate(pats, 12, 7, 80)])
    t0 = time.time()
    fails = 0
    runs = 0
    for stage in (1, 2, 4, 7, 10, 14, 18, 25):
        for seed in range(4):
            s = gen.stage_seed(1234 + seed, stage)
            for total in (48, 88):
                placed = gen.generate(pats, stage, s, total)
                ids = [p["id"] for p, _ in placed]
                assert any(i in ("trans.cube_to_ship",) or (stage >= 9 and i == "trans.cube_to_wave") for i in ids), ("no surfer section", stage, seed, total, ids)
                if total >= 64:
                    assert any(p.get("requiredJumps", 0) == 2 for p, _ in placed), ("no double-jump section", stage, seed, total, ids)
                course, tau_end = stage_course(placed, total)
                for k in (0.70, 1.41):
                    runs += 1
                    path, nodes = sim.solve(course, sim.Player(), 0.0, tau_end, k / 120.0, 0.05, 1.0, ("cube", 1, False), max_nodes=2_000_000)
                    if path is None:
                        fails += 1
                        print("FAIL", stage, seed, total, k, ids)
    print(f"stages validated: {runs}, failures: {fails}, {time.time() - t0:.1f}s")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
