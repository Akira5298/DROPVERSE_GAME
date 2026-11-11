"""
Reference implementation of Levels/LevelGenerator.swift (keep in sync).
Composes validated patterns into a stage with seeded randomness.
"""
MASK = (1 << 64) - 1


class SplitMix:
    def __init__(self, seed):
        self.s = seed & MASK

    def next(self):
        self.s = (self.s + 0x9E3779B97F4A7C15) & MASK
        z = self.s
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def next_double(self):
        return (self.next() >> 11) * (2.0 ** -53)


def stage_seed(run_seed, stage):
    g = SplitMix(run_seed ^ ((stage * 0xD1B54A32D192ED03) & MASK))
    return g.next()


TIERS = ["challenging", "hard", "veryHard", "expert"]
WEIGHTS = {
    "challenging": {1: 1.0, 2: 0.7},
    "hard": {1: 0.2, 2: 1.0, 3: 0.8},
    "veryHard": {2: 0.5, 3: 1.0, 4: 0.6},
    "expert": {2: 0.2, 3: 0.8, 4: 1.2},
}
DOUBLE_BONUS = 1.4
GAPS = {"challenging": 2, "hard": 1, "veryHard": 1, "expert": 1}
LEAD_IN = 4
TAIL = 2
PHRASE = 32
TRANSITION_WEIGHT = 0.6


def tier_for(stage):
    if stage <= 3:
        return "challenging"
    if stage <= 8:
        return "hard"
    if stage <= 15:
        return "veryHard"
    return "expert"


def generate(patterns, stage, seed, total_beats, k=1.0, energy=None):
    """Returns [(pattern, start_beat)]. energy: optional list of per-bar energies (0..1)."""
    rng = SplitMix(seed)
    tier = tier_for(stage)
    if k >= 1.25 and tier != "challenging":
        tier = TIERS[TIERS.index(tier) - 1]
    weights = WEIGHTS[tier]
    gap = GAPS[tier]
    by_id = {p["id"]: p for p in patterns}
    returns = {"ship": by_id["trans.ship_to_cube"], "wave": by_id["trans.wave_to_cube"]}
    median = sorted(energy)[len(energy) // 2] if energy else 0.0

    # Wave Mode joins the rotation in the Very Hard band (stage 9+), per the difficulty plan.
    alt_modes = ("ship",) if stage < 9 else ("ship", "wave")
    doubled = False
    settle = 0
    placed = []
    recent = []
    mode = "cube"
    in_mode_count = 0
    flew = False
    beat = LEAD_IN
    while True:
        if placed:
            beat = max(beat, placed[-1][1] + placed[-1][0]["beats"] + settle)
        remaining = total_beats - TAIL - beat
        cands = []
        for p in patterns:
            if p["entry"]["mode"] != mode:
                continue
            if p.get("barAligned") and beat % 4 != 0:
                continue
            if p["exit"]["mode"] == "wave" and p["entry"]["mode"] != "wave" and "wave" not in alt_modes:
                continue
            if p["difficulty"] not in weights and "transition" not in p.get("tags", []):
                continue
            exit_mode = p["exit"]["mode"]
            need = p["beats"] + (0 if exit_mode == "cube" else gap + returns[exit_mode]["beats"])
            if need > remaining:
                continue
            cands.append(p)
        if not cands:
            if mode != "cube":
                p = returns[mode]
                if p["beats"] <= total_beats - beat:
                    placed.append((p, beat))
                    beat += p["beats"]
                    mode = "cube"
            break
        # Surfer section is mandatory early in every stage.
        if not flew and mode == "cube" and beat >= total_beats * 0.25:
            forced = [p for p in cands if p["exit"]["mode"] in alt_modes]
            if forced:
                cands = forced
        if not doubled and mode == "cube" and (flew or beat >= total_beats * 0.45):
            forced = [p for p in cands if p.get("requiredJumps", 0) == 2]
            if forced:
                cands = forced
        if not doubled and mode != "cube" and beat >= total_beats * 0.4:
            forced = [p for p in cands if p["exit"]["mode"] == "cube"]
            if forced:
                cands = forced
        if len(cands) > 1:
            fresh = [p for p in cands if p["id"] not in recent[-2:]]
            if fresh:
                cands = fresh
        bar = beat // 4
        e = energy[bar] if energy and bar < len(energy) else median
        phrase_pos = beat % PHRASE
        total = 0.0
        ws = []
        for p in cands:
            tags = p.get("tags", [])
            w = weights.get(p["difficulty"], TRANSITION_WEIGHT)
            if p["id"] in recent[-6:]:
                w *= 0.25
            if energy and e > median * 1.1 and any(t in tags for t in ("music", "bass", "laser", "eq")):
                w *= 1.5
            if phrase_pos < 4 and "transition" in tags:
                w *= 2.0
            if phrase_pos >= 24 and p["difficulty"] >= 3:
                w *= 1.3
            if mode != "cube" and p["exit"]["mode"] == "cube":
                w *= 0.4 + 0.8 * in_mode_count
            if "double" in tags:
                w *= DOUBLE_BONUS
            ws.append(w)
            total += w
        r = rng.next_double() * total
        choice = cands[-1]
        acc = 0.0
        for p, w in zip(cands, ws):
            acc += w
            if r < acc:
                choice = p
                break
        placed.append((choice, beat))
        recent.append(choice["id"])
        new_mode = choice["exit"]["mode"]
        if new_mode in alt_modes:
            flew = True
        if choice.get("requiredJumps", 0) == 2:
            doubled = True
        settle = choice.get("settleBeats", 0)
        in_mode_count = in_mode_count + 1 if new_mode == mode else 0
        mode = new_mode
        beat += choice["beats"] + gap
    return placed
