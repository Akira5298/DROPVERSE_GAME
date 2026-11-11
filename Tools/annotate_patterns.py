#!/usr/bin/env python3
"""
Computes derived pattern metadata and writes it back into patterns.json:

- requiredJumps: 2 when the solver cannot complete the pattern with air jumps disabled at
  any tempo (so the double jump is proven necessary), 1 when a jump is needed, 0 otherwise.
- settleBeats: beats a following pattern must wait so the player is grounded with both jumps.
- cues: tap-timing markers for cube patterns. Derived from a solver solution: each press is
  re-timed to the centre of its success interval (snapped to the 1/4-beat grid when that point
  is inside the interval, so markers sit on the music), with the largest symmetric window that
  still completes the pattern at the slowest AND fastest tempo. Patterns whose presses have
  less than MIN_WINDOW of tolerance get no cues (the guide stays silent rather than lying).
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import dropverse_sim as sim
import validate_patterns as vp

PATH = os.path.join(os.path.dirname(__file__), "..", "DROPVERSE", "Resources", "Patterns", "patterns.json")
KS = (0.70, 1.41)
MIN_WINDOW = 0.06      # beats
MAX_WINDOW = 0.25
LEAD = vp.LEAD_BEATS


FORBID_DOUBLE = [False]


def script_run(pattern, presses, k, max_jumps=sim.MAX_JUMPS, events_out=None):
    """presses: list of (beat, holdBeats) relative to pattern start. Returns (alive_at_end, player)."""
    course, tau_end = vp.build([pattern])
    e = sim.state_tuple(pattern["entry"])
    p = sim.Player(e[0], e[1], e[2], max_jumps)
    dt = k / 120.0
    t = 0.0
    starts = [(LEAD + b) * sim.BEAT_TAU for b, _ in presses]
    ends = [(LEAD + b + h) * sim.BEAT_TAU for b, h in presses]
    done = [False] * len(presses)
    while t < tau_end:
        press = False
        held = False
        for i in range(len(presses)):
            if not done[i] and t >= starts[i]:
                done[i] = True
                press = True
                if events_out is not None:
                    events_out.append(("press", i, t))
            if starts[i] <= t < ends[i]:
                held = True
        ev = []
        sim.step(course, p, t, dt, held or press, press, events=ev)
        if FORBID_DOUBLE[0] and "double" in ev:
            return False, p
        if events_out is not None:
            for x in ev:
                events_out.append((x, None, t))
        t += dt
        if p.dead:
            return False, p
    return (sim.state_tuple(pattern["exit"]) == (p.mode, p.gs, p.mini)), p


def presses_from_path(path, k):
    """Converts a solver decision path into (beat, holdBeats) presses."""
    n = max(1, int(round(0.05 / (k / 120.0))))
    dec_beats = n * (k / 120.0) / sim.BEAT_TAU
    out = []
    prev = False
    start = None
    for i, held in enumerate(path + [False]):
        if held and not prev:
            start = i
        if not held and prev:
            out.append((start * dec_beats - LEAD, (i - start) * dec_beats))
        prev = held
    return out


def ok_all(pattern, presses):
    return all(script_run(pattern, presses, k)[0] for k in KS)


def derive_cues(pattern):
    FORBID_DOUBLE[0] = False
    if "authoredCues" in pattern:
        presses = [(c["beat"], c.get("hold", 0.1)) for c in pattern["authoredCues"]]
        if not ok_all(pattern, presses):
            raise SystemExit(f'{pattern["id"]}: authored cues do not complete the pattern')
        return finish_cues(pattern, presses)
    course, tau_end = vp.build([pattern])
    e = sim.state_tuple(pattern["entry"])
    path = None
    # Prefer a strategy without air jumps so the guide never encourages an unneeded double jump.
    for mj in (1, sim.MAX_JUMPS):
        path, _ = sim.solve(course, sim.Player(*e, max_jumps=mj), 0.0, tau_end, 1.0 / 120.0, 0.05, 1.0,
                            sim.state_tuple(pattern["exit"]))
        if path is not None:
            # A single-jump strategy exists: its cues must never trigger an air jump in the real game.
            FORBID_DOUBLE[0] = mj == 1
            break
    if path is None:
        return None
    presses = presses_from_path(path, 1.0)
    if not presses or len(presses) > 8 or not ok_all(pattern, presses):
        return None
    # Iteratively centre each press inside its success interval.
    for _ in range(2):
        for i in range(len(presses)):
            b, h = presses[i]
            lo = hi = 0.0
            step = 0.02
            while lo > -0.4 and ok_all(pattern, presses[:i] + [(b + lo - step, h)] + presses[i + 1:]):
                lo -= step
            while hi < 0.4 and ok_all(pattern, presses[:i] + [(b + hi + step, h)] + presses[i + 1:]):
                hi += step
            a, z = b + lo, b + hi
            centre = (a + z) / 2
            grid = round(centre * 4) / 4
            if a + MIN_WINDOW <= grid <= z - MIN_WINDOW:
                centre = grid
            presses[i] = (round(centre, 3), h)
    return finish_cues(pattern, presses)


def finish_cues(pattern, presses):
    cues = []
    for i, (b, h) in enumerate(presses):
        w = MAX_WINDOW
        while w >= MIN_WINDOW:
            if ok_all(pattern, presses[:i] + [(b - w, h)] + presses[i + 1:]) and \
               ok_all(pattern, presses[:i] + [(b + w, h)] + presses[i + 1:]):
                break
            w = round(w - 0.01, 3)
        if w < MIN_WINDOW:
            return None
        cues.append({"beat": b, "hold": round(h, 3), "window": round(w, 3)})
    if not ok_all(pattern, presses):
        return None
    FORBID_DOUBLE[0] = False
    # Label each press by what it caused.
    log = []
    script_run(pattern, presses, 1.0, events_out=log)
    labels = []
    for i in range(len(presses)):
        t_press = next(t for kind, idx, t in log if kind == "press" and idx == i)
        after = [kind for kind, idx, t in log if idx is None and t_press <= t < t_press + 0.12 and kind in ("jump", "double", "orb", "gravity")]
        label = "gravity" if "gravity" in after else (after[0] if after else "jump")
        labels.append(label)
    for c, l in zip(cues, labels):
        c["action"] = l
    return cues


def main():
    data = json.load(open(PATH))
    for p in data["patterns"]:
        cube = p["entry"]["mode"] == "cube" and p["exit"]["mode"] == "cube"
        # required jumps
        if "transition" in p.get("tags", []) or not cube:
            req = 0
        else:
            single_ok = any(vp.check([p], k, max_jumps=1)[0] for k in vp.K_VALUES)
            req = 1 if single_ok else 2
        p["requiredJumps"] = req
        p["settleBeats"] = 3 if p["exit"]["mode"] == "cube" and p["entry"]["mode"] != "cube" else 0
        p.pop("cues", None)
        if cube and "transition" not in p.get("tags", []):
            cues = derive_cues(p)
            if cues:
                p["cues"] = cues
        print(f'{p["id"]:28s} req={req} cues={[(c["action"], c["beat"], c["window"]) for c in p.get("cues", [])]}')
    json.dump(data, open(PATH, "w"), indent=1)


if __name__ == "__main__":
    main()
