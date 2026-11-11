"""
DROPVERSE reference simulation + solver bot.

This file mirrors the Swift gameplay simulation (Game/Simulation/*.swift) line for line
so level patterns can be validated outside Xcode. Keep the two in sync: any physics
change in Swift must be reflected here (and vice versa).

Units: points and *reference seconds* (tau). One beat = 60/128 tau at every tempo;
the game scales real time by k = foldedBPM / 128, so patterns validated here are
tempo-independent in beat space.
"""
import json
import math
import sys

# ---------------------------------------------------------------- constants
BEAT_TAU = 60.0 / 128.0
SPEED = 320.0                      # x per tau at speed multiplier 1
BEAT_X = SPEED * BEAT_TAU          # 150 points per beat
FLOOR = 150.0
CEIL = 600.0
PLAY_H = CEIL - FLOOR              # 450

HALF_BIG = 22.0
HALF_MINI = 13.0

G = 1850.0
JUMP = 620.0
JUMP_MINI = 520.0
JUMP2 = 650.0                      # second (air) jump; velocity is reset, not added
JUMP2_MINI = 545.0
MAX_JUMPS = 2
EDGE_SNAP = 12.0                   # lenient ledge catch: snap up if <= this far below a surface
FALL_G = 1400.0                    # falling-platform acceleration
HOLD_MAX = 0.18
HOLD_SCALE = 0.45
COYOTE = 0.08
BUFFER = 0.10
TERMINAL = 1000.0

SHIP_G = 1200.0
SHIP_THRUST = 2200.0
SHIP_MAX = 430.0

WAVE_SLOPE = 1.0
WAVE_SLOPE_MINI = 2.0

PAD_YELLOW = 860.0
PAD_PINK = 700.0
ORB_YELLOW = 680.0
ORB_PINK = 560.0
ORB_GRAVITY_PUSH = 250.0

SPIKE_W = 44.0
SPIKE_CORE_HALF = SPIKE_W * 0.18
SPIKE_CORE_H = SPIKE_W * 0.6

LAND_TOLERANCE = 6.0
TRIGGER_PAD = 6.0
KILL_MARGIN = 120.0
INF = float("inf")


# ---------------------------------------------------------------- course model
class SpeedTrack:
    """Piecewise-linear tau -> x mapping built from speed segments."""

    def __init__(self):
        self.segs = [(-1e6, -1e6 * SPEED, 1.0)]  # (tau_start, x_start, mult)

    def add(self, tau, mult):
        t0, x0, m0 = self.segs[-1]
        assert tau >= t0
        x = x0 + (tau - t0) * SPEED * m0
        if abs(tau - t0) < 1e-12:
            self.segs[-1] = (t0, x0, mult)
        else:
            self.segs.append((tau, x, mult))

    def seg(self, tau):
        lo = 0
        for i in range(len(self.segs) - 1, -1, -1):
            if self.segs[i][0] <= tau:
                lo = i
                break
        return self.segs[lo]

    def x(self, tau):
        t0, x0, m = self.seg(tau)
        return x0 + (tau - t0) * SPEED * m

    def mult(self, tau):
        return self.seg(tau)[2]


def wave(local_beats, period, phase):
    return math.sin(2 * math.pi * (local_beats - phase) / period)


class Obj:
    __slots__ = ("kind", "id", "x0", "x1", "y0", "y1", "tau0", "p", "cx", "cy")

    def __init__(self, kind, oid, tau0, **p):
        self.kind = kind
        self.id = oid
        self.tau0 = tau0
        self.p = p

    def local(self, tau):
        return (tau - self.tau0) / BEAT_TAU

    def offset(self, tau):
        mv = self.p.get("move")
        if not mv:
            return 0.0, 0.0
        d = mv["amp"] * wave(self.local(tau), mv["period"], mv.get("phase", 0.0))
        return (d, 0.0) if mv["axis"] == "x" else (0.0, d)

    def rect(self, tau):
        dx, dy = self.offset(tau)
        p = self.p
        fa = p.get("fall_at")
        if fa is not None:
            lb = self.local(tau) - fa
            if lb > 0:
                dt = lb * BEAT_TAU
                dy -= 0.5 * FALL_G * dt * dt
        return (p["x0"] + dx, p["x1"] + dx, p["y0"] + dy, p["y1"] + dy)

    def timed_active(self, tau):
        p = self.p
        local = (self.local(tau) - p.get("phase", 0.0)) % p["period"]
        return p["on"] <= local < p["on"] + p["dur"]

    def basswall_h(self, tau):
        p = self.p
        s = 0.5 - 0.5 * math.cos(2 * math.pi * (self.local(tau) - p.get("phase", 0.0)) / p["period"])
        return p["hmin"] + (p["hmax"] - p["hmin"]) * s


class Course:
    def __init__(self):
        self.solids = []
        self.hazards = []
        self.triggers = []
        self.pits = []
        self.speed = SpeedTrack()
        self.next_id = 0
        self.floor = []  # list of solid floor Obj (rebuilt by finalize)

    def nid(self):
        self.next_id += 1
        return self.next_id

    def finalize(self, x_min=-1e7, x_max=1e7):
        pits = sorted(self.pits)
        segs = []
        cur = x_min
        for a, b in pits:
            if a > cur:
                segs.append((cur, a))
            cur = max(cur, b)
        segs.append((cur, x_max))
        self.floor = [Obj("solid", self.nid(), 0.0, x0=a, x1=b, y0=-1000.0, y1=FLOOR) for a, b in segs]
        self.ceiling = Obj("solid", self.nid(), 0.0, x0=x_min, x1=x_max, y0=CEIL, y1=CEIL + 1000.0)
        # Same ordering as the Swift Course (objects sorted by their minimum x).
        self.solids.sort(key=lambda o: o.p["x0"] - (abs(o.p["move"]["amp"]) if o.p.get("move") and o.p["move"]["axis"] == "x" else 0.0))
        self.all_solids = self.floor + [self.ceiling] + self.solids
        return self


def compile_pattern(course, pattern, tau0, base_mult=1.0):
    """Adds a pattern to the course with its first beat at tau0. Returns tau at pattern end."""
    beats = pattern["beats"]
    segs = pattern.get("speed") or [{"at": 0, "mult": base_mult}]
    segs = sorted(segs, key=lambda s: s["at"])
    if segs[0]["at"] > 0:
        segs = [{"at": 0, "mult": base_mult}] + segs
    for s in segs:
        course.speed.add(tau0 + s["at"] * BEAT_TAU, s["mult"])
        if s["at"] > 0:
            course.triggers.append(Obj("speedportal", course.nid(), tau0, x=course.speed.x(tau0 + s["at"] * BEAT_TAU), mult=s["mult"]))
    tau_end = tau0 + beats * BEAT_TAU

    def X(b):
        return course.speed.x(tau0 + b * BEAT_TAU)

    for o in pattern["objects"]:
        t = o["type"]
        oid = course.nid()
        if t == "spike":
            n = o.get("count", 1)
            base = FLOOR + o.get("y", 0.0)
            down = o.get("dir", "up") == "down"
            x = X(o["x"])
            for i in range(n):
                cx = x + SPIKE_W / 2 + i * SPIKE_W
                y0, y1 = (base - SPIKE_CORE_H, base) if down else (base, base + SPIKE_CORE_H)
                course.hazards.append(Obj("rect", course.nid(), tau0, x0=cx - SPIKE_CORE_HALF, x1=cx + SPIKE_CORE_HALF, y0=y0, y1=y1, move=o.get("move")))
        elif t in ("block", "mblock", "fallblock"):
            y = FLOOR + o.get("y", 0.0)
            course.solids.append(Obj("solid", oid, tau0, x0=X(o["x"]), x1=X(o["x"] + o["w"]), y0=y, y1=y + o["h"], move=o.get("move"),
                                     fall_at=o.get("fallAt") if t == "fallblock" else None))
        elif t == "pit":
            course.pits.append((X(o["x"]), X(o["x"] + o["w"])))
        elif t in ("hazard", "mhazard", "notehazard"):
            y = FLOOR + o.get("y", 0.0)
            course.hazards.append(Obj("rect", oid, tau0, x0=X(o["x"]), x1=X(o["x"] + o["w"]), y0=y, y1=y + o["h"], move=o.get("move")))
        elif t == "saw":
            course.hazards.append(Obj("circle", oid, tau0, cx=X(o["x"]), cy=FLOOR + o["y"], r=o["r"] * 0.8, move=o.get("move")))
        elif t == "pendulum":
            course.hazards.append(Obj("pendulum", oid, tau0, px=X(o["x"]), py=FLOOR + o["y"], len=o["len"], r=o["r"] * 0.85,
                                      amp=math.radians(o["amp"]), period=o["period"], phase=o.get("phase", 0.0)))
        elif t in ("laser", "gate"):
            y = FLOOR + o.get("y", 0.0)
            w = o.get("w", 0.12)
            course.hazards.append(Obj("timed", oid, tau0, x0=X(o["x"]), x1=X(o["x"] + w), y0=y, y1=y + o["h"],
                                      period=o["period"], on=o["on"], dur=o["dur"], phase=o.get("phase", 0.0), move=o.get("move")))
        elif t == "basswall":
            course.hazards.append(Obj("basswall", oid, tau0, x0=X(o["x"]), x1=X(o["x"] + o["w"]), y0=FLOOR + o.get("y", 0.0),
                                      hmin=o["hmin"], hmax=o["hmax"], period=o["period"], phase=o.get("phase", 0.0)))
        elif t == "eq":
            bw = o.get("barW", 0.2)
            gap = o.get("gap", 0.1)
            for i in range(o["bars"]):
                bx = o["x"] + i * (bw + gap)
                course.hazards.append(Obj("basswall", course.nid(), tau0, x0=X(bx), x1=X(bx + bw), y0=FLOOR,
                                          hmin=o["hmin"], hmax=o["hmax"], period=o["period"], phase=o.get("phase", 0.0) + i * o.get("step", 0.25)))
        elif t == "pad":
            down = o.get("dir", "up") == "down"
            base = FLOOR + o.get("y", 0.0)
            x = X(o["x"])
            y0, y1 = (base - 14, base) if down else (base, base + 14)
            course.triggers.append(Obj("pad", oid, tau0, x0=x, x1=x + 40, y0=y0, y1=y1, strength=o.get("kind", "yellow")))
        elif t == "orb":
            course.triggers.append(Obj("orb", oid, tau0, cx=X(o["x"]), cy=FLOOR + o["y"], r=30.0, orb=o.get("kind", "yellow")))
        elif t == "portal":
            course.triggers.append(Obj("portal", oid, tau0, x=X(o["x"]), portal=o["kind"]))
        else:
            raise ValueError("unknown object type " + t)
    # restore base speed after pattern if pattern changed it
    if course.speed.mult(tau_end - 1e-9) != base_mult:
        course.speed.add(tau_end, base_mult)
        course.triggers.append(Obj("speedportal", course.nid(), tau0, x=course.speed.x(tau_end), mult=base_mult))
    return tau_end


# ---------------------------------------------------------------- player + step
class Player:
    __slots__ = ("y", "vy", "mode", "gs", "mini", "grounded", "tsg", "tsp", "hold_t", "hold_active", "dead", "used", "cause",
                 "jumps", "max_jumps")

    def __init__(self, mode="cube", gs=1, mini=False, max_jumps=MAX_JUMPS):
        self.mode = mode
        self.gs = gs
        self.mini = mini
        self.y = (FLOOR + self.half()) if gs == 1 else (CEIL - self.half())
        self.vy = 0.0
        self.grounded = mode == "cube"
        self.tsg = 0.0
        self.tsp = INF
        self.hold_t = 0.0
        self.hold_active = False
        self.dead = False
        self.used = frozenset()
        self.cause = ""
        self.max_jumps = max_jumps
        self.jumps = max_jumps if mode == "cube" else max_jumps - 1

    def half(self):
        return HALF_MINI if self.mini else HALF_BIG

    def copy(self):
        q = Player.__new__(Player)
        for s in Player.__slots__:
            setattr(q, s, getattr(self, s))
        return q


def overlap(px, py, h, r):
    return px + h > r[0] and px - h < r[1] and py + h > r[2] and py - h < r[3]


def circle_hit(px, py, h, cx, cy, r):
    nx = min(max(cx, px - h), px + h)
    ny = min(max(cy, py - h), py + h)
    return (nx - cx) ** 2 + (ny - cy) ** 2 < r * r


def hazard_hit(o, tau, px, py, h):
    k = o.kind
    if k == "rect":
        return overlap(px, py, h, o.rect(tau))
    if k == "circle":
        dx, dy = o.offset(tau)
        return circle_hit(px, py, h, o.p["cx"] + dx, o.p["cy"] + dy, o.p["r"])
    if k == "pendulum":
        p = o.p
        a = p["amp"] * wave(o.local(tau), p["period"], p["phase"])
        bx = p["px"] + p["len"] * math.sin(a)
        by = p["py"] - p["len"] * math.cos(a)
        return circle_hit(px, py, h, bx, by, p["r"])
    if k == "timed":
        return o.timed_active(tau) and overlap(px, py, h, o.rect(tau))
    if k == "basswall":
        y0 = o.p["y0"]
        return overlap(px, py, h, (o.p["x0"], o.p["x1"], y0, y0 + o.basswall_h(tau)))
    raise ValueError(k)


def hazard_x_extent(o):
    p = o.p
    if o.kind in ("rect", "timed", "basswall"):
        mv = p.get("move")
        a = mv["amp"] if mv and mv["axis"] == "x" else 0.0
        return p["x0"] - abs(a), p["x1"] + abs(a)
    if o.kind == "circle":
        mv = p.get("move")
        a = mv["amp"] if mv and mv["axis"] == "x" else 0.0
        return p["cx"] - p["r"] - abs(a), p["cx"] + p["r"] + abs(a)
    if o.kind == "pendulum":
        return p["px"] - p["len"] - p["r"], p["px"] + p["len"] + p["r"]
    return -INF, INF


def step(course, p, tau_prev, dtau, held, pressed, hazard_margin=0.0, events=None):
    """Advances the player by one fixed step. Mirrors WorldSimulation.step in Swift."""
    tau = tau_prev + dtau
    x_prev = course.speed.x(tau_prev)
    x = course.speed.x(tau)
    mult = course.speed.mult(tau)
    gs = p.gs
    if pressed:
        p.tsp = 0.0

    # 1. mode physics
    if p.mode == "cube":
        can_jump = p.grounded or p.tsg <= COYOTE
        if not can_jump and p.jumps >= p.max_jumps:
            p.jumps = p.max_jumps - 1          # walked off a ledge: the ground jump is gone
        fresh = p.tsp <= BUFFER
        if can_jump and (fresh or held):
            p.vy = (JUMP_MINI if p.mini else JUMP) * gs
            p.grounded = False
            p.tsg = INF
            p.tsp = INF
            p.jumps = p.max_jumps - 1
            p.hold_active = True
            p.hold_t = 0.0
            if events is not None:
                events.append("jump")
        elif (fresh and not can_jump and p.jumps > 0 and not touching_orb(course, p, x_prev)
              and not landing_soon(course, p, x_prev, tau_prev, mult)):
            # Air jump: only on a new tap (fresh press), velocity reset for consistent height.
            p.vy = (JUMP2_MINI if p.mini else JUMP2) * gs
            p.jumps -= 1
            p.tsp = INF
            p.hold_active = True
            p.hold_t = 0.0
            if events is not None:
                events.append("double")
        if p.hold_active:
            if held and p.hold_t < HOLD_MAX and p.vy * gs > 0:
                p.hold_t += dtau
            else:
                p.hold_active = False
        g = G * (HOLD_SCALE if p.hold_active else 1.0)
        p.vy -= g * gs * dtau
        if gs > 0:
            p.vy = max(p.vy, -TERMINAL)
        else:
            p.vy = min(p.vy, TERMINAL)
    elif p.mode == "ship":
        acc = (SHIP_THRUST - SHIP_G) if held else -SHIP_G
        p.vy += acc * gs * dtau
        p.vy = max(-SHIP_MAX, min(SHIP_MAX, p.vy))
    else:  # wave
        slope = WAVE_SLOPE_MINI if p.mini else WAVE_SLOPE
        p.vy = (1.0 if held else -1.0) * gs * SPEED * mult * slope

    y_prev = p.y
    p.y += p.vy * dtau
    h = p.half()
    was_grounded = p.grounded
    p.grounded = False

    # 2. solids
    for s in course.all_solids:
        r = s.rect(tau)
        if r[1] < x - 80 or r[0] > x + 80:
            continue
        if not overlap(x, p.y, h, r):
            continue
        rp = s.rect(tau_prev)
        prev_bottom = y_prev - h
        prev_top = y_prev + h
        if prev_bottom >= rp[3] - LAND_TOLERANCE:
            side = "top"
        elif prev_top <= rp[2] + LAND_TOLERANCE:
            side = "bottom"
        elif prev_bottom >= rp[3] - EDGE_SNAP and (p.mode != "cube" or (gs > 0 and p.vy <= 0)):
            side = "top"                      # ledge catch: was at most EDGE_SNAP below the edge last step
        elif prev_top <= rp[2] + EDGE_SNAP and (p.mode != "cube" or (gs < 0 and p.vy >= 0)):
            side = "bottom"
        else:
            side = "side"
        if side == "side":
            p.dead = True
            p.cause = "wall"
            return
        if p.mode == "cube":
            if (side == "top" and gs > 0) or (side == "bottom" and gs < 0):
                p.y = r[3] + h if side == "top" else r[2] - h
                p.vy = 0.0
                p.grounded = True
                p.jumps = p.max_jumps
            else:
                p.dead = True
                p.cause = "head"
                return
        else:
            if side == "top":
                p.y = r[3] + h
                p.vy = max(p.vy, 0.0)
            else:
                p.y = r[2] - h
                p.vy = min(p.vy, 0.0)
            if p.mode == "ship" and ((side == "top" and gs > 0) or (side == "bottom" and gs < 0)):
                p.grounded = True
    for s in course.all_solids:
        r = s.rect(tau)
        if r[1] < x - 80 or r[0] > x + 80:
            continue
        if overlap(x, p.y, h - 0.5, r):
            p.dead = True
            p.cause = "crushed"
            return

    if p.grounded and not was_grounded and events is not None:
        events.append("land")
    if p.grounded:
        p.tsg = 0.0
    elif p.tsg != INF:
        p.tsg += dtau

    # 3. triggers
    for t in course.triggers:
        k = t.kind
        if k == "portal":
            px = t.p["x"]
            if x_prev < px <= x:
                apply_portal(p, t.p["portal"])
                if events is not None:
                    events.append("portal:" + t.p["portal"])
                h = p.half()
        elif k == "pad":
            if p.mode != "cube" or t.id in p.used:
                continue
            if overlap(x, p.y, h + TRIGGER_PAD, (t.p["x0"], t.p["x1"], t.p["y0"], t.p["y1"])):
                p.vy = (PAD_YELLOW if t.p["strength"] == "yellow" else PAD_PINK) * p.gs
                p.grounded = False
                p.tsg = INF
                p.jumps = min(p.jumps, p.max_jumps - 1)
                p.hold_active = False
                p.used = p.used | {t.id}
                if events is not None:
                    events.append("pad")
        elif k == "orb":
            if p.mode != "cube" or t.id in p.used or p.tsp > BUFFER:
                continue
            if circle_hit(x, p.y, h + TRIGGER_PAD, t.p["cx"], t.p["cy"], t.p["r"]):
                kind = t.p["orb"]
                if kind == "gravity":
                    p.gs = -p.gs
                    p.vy = -p.gs * ORB_GRAVITY_PUSH
                    p.jumps = min(p.jumps, p.max_jumps - 1)
                    if events is not None:
                        events.append("gravity")
                else:
                    p.vy = (ORB_YELLOW if kind == "yellow" else ORB_PINK) * p.gs
                p.grounded = False
                p.tsg = INF
                p.tsp = INF
                p.hold_active = False
                p.used = p.used | {t.id}
                if events is not None:
                    events.append("orb")
    p.tsp += dtau

    # 4. hazards
    hh = h + hazard_margin
    for o in course.hazards:
        a, b = hazard_x_extent(o)
        if b < x - hh or a > x + hh:
            continue
        if hazard_hit(o, tau, x, p.y, hh):
            p.dead = True
            p.cause = "hazard"
            return

    # 5. bounds
    if p.y < FLOOR - KILL_MARGIN or p.y > CEIL + KILL_MARGIN:
        p.dead = True
        p.cause = "fell"


def landing_soon(course, p, x, tau, mult):
    """True when the falling player will reach a support within the jump buffer, so a tap
    now is a buffered ground jump rather than the air jump."""
    gs = p.gs
    if p.vy * gs >= 0:
        return False
    h = p.half()
    reach = abs(p.vy) * BUFFER + 0.5 * G * BUFFER * BUFFER
    x_hi = x + h + SPEED * mult * BUFFER
    foot = p.y - h if gs > 0 else p.y + h
    for s in course.all_solids:
        r = s.rect(tau)
        if r[1] < x - h or r[0] > x_hi:
            continue
        if gs > 0 and r[3] <= foot + 0.5 and foot - r[3] <= reach:
            return True
        if gs < 0 and r[2] >= foot - 0.5 and r[2] - foot <= reach:
            return True
    return False


def touching_orb(course, p, x):
    """True when an unused orb is under the player: a tap then belongs to the orb, not the air jump."""
    h = p.half() + TRIGGER_PAD
    for t in course.triggers:
        if t.kind == "orb" and t.id not in p.used and circle_hit(x, p.y, h, t.p["cx"], t.p["cy"], t.p["r"]):
            return True
    return False


def apply_portal(p, kind):
    if kind in ("cube", "ship", "wave"):
        if p.mode != kind:
            p.mode = kind
            p.grounded = False
            p.hold_active = False
            p.tsg = INF
            if kind == "ship":
                p.vy *= 0.5
            elif kind == "cube":
                p.vy = max(-400.0, min(400.0, p.vy))
                p.jumps = p.max_jumps - 1
    elif kind == "gravityFlip":
        if p.gs > 0:
            p.gs = -1
            p.vy *= 0.5
            p.grounded = False
            p.tsg = INF
            p.jumps = min(p.jumps, p.max_jumps - 1)
    elif kind == "gravityNormal":
        if p.gs < 0:
            p.gs = 1
            p.vy *= 0.5
            p.grounded = False
            p.tsg = INF
            p.jumps = min(p.jumps, p.max_jumps - 1)
    elif kind == "mini":
        p.mini = True
    elif kind == "big":
        p.mini = False


# ---------------------------------------------------------------- solver bot
def solve(course, player, tau_start, tau_end, dtau, decision=0.05, hazard_margin=1.0, exit_state=None, max_nodes=400000):
    """Depth-first search over hold/release decisions taken every `decision` tau.
    Returns the list of held flags per decision, or None. A returned path is a real,
    fully simulated completion; None means no completion was found at this granularity."""
    sys.setrecursionlimit(100000)
    n_steps = max(1, int(round(decision / dtau)))
    visited = set()
    path = []
    budget = [max_nodes]

    def key(p, depth, held):
        return (depth, int(round(p.y / 2)), int(round(p.vy / 25)), p.mode, p.gs, p.mini, held, p.grounded,
                p.hold_active, p.used, min(p.tsg, 1.0) > COYOTE, p.jumps)

    def dfs(p, tau, held_prev, depth):
        if tau >= tau_end:
            if exit_state and (p.mode, p.gs, p.mini) != exit_state:
                return False
            return True
        k = key(p, depth, held_prev)
        if k in visited:
            return False
        visited.add(k)
        budget[0] -= 1
        if budget[0] < 0:
            return False
        for held in ((held_prev, not held_prev)):
            q = p.copy()
            t = tau
            for i in range(n_steps):
                step(course, q, t, dtau, held, held and not held_prev and i == 0, hazard_margin)
                t += dtau
                if q.dead:
                    break
            if q.dead:
                continue
            path.append(held)
            if dfs(q, t, held, depth + 1):
                return True
            path.pop()
        return False

    ok = dfs(player, tau_start, False, 0)
    return (list(path) if ok else None), len(visited)


def replay(course, player, tau_start, path, dtau, decision=0.05, hazard_margin=0.0):
    """Re-simulates a solver path (used to measure timing windows)."""
    n_steps = max(1, int(round(decision / dtau)))
    p = player.copy()
    t = tau_start
    held_prev = False
    for held in path:
        for i in range(n_steps):
            step(course, p, t, dtau, held, held and not held_prev and i == 0, hazard_margin)
            t += dtau
            if p.dead:
                return p, t
        held_prev = held
    return p, t


def state_tuple(s):
    return (s["mode"], 1 if s.get("gravity", "normal") == "normal" else -1, bool(s.get("mini", False)))


# ---------------------------------------------------------------- reachability model
def reachability(mini=False, dt=1.0 / 120.0):
    """Measures the jump envelope by simulation on flat ground (mirrors Swift Reachability).
    Returns a dict of heights (pt above the take-off surface) and distances (pt of travel)."""
    def flight(second_at=None, hold1=True, hold2=True):
        c = Course().finalize()
        p = Player(mini=mini)
        t = 0.0
        apex = 0.0
        held_until = HOLD_MAX + 0.02 if hold1 else 0.0
        pressed_second = False
        took_off = None
        while t < 4:
            press = t == 0.0
            held = t < held_until
            if second_at is not None and not pressed_second and took_off is not None and t - took_off >= second_at:
                press = True
                pressed_second = True
                held_until = t + (HOLD_MAX + 0.02 if hold2 else 0.0)
                held = hold2
            ev = []
            step(c, p, t, dt, held, press, events=ev)
            t += dt
            if "jump" in ev:
                took_off = t
            apex = max(apex, p.y - p.half() - FLOOR)
            if took_off is not None and "land" in ev:
                return apex, (t - took_off) * SPEED
        return apex, (t - (took_off or 0)) * SPEED
    single_tap = flight(hold1=False)
    single_hold = flight()
    best_h = max((flight(second_at=s)[0], s) for s in [i * 0.01 for i in range(1, 80)])
    best_d = max((flight(second_at=s)[1], s) for s in [i * 0.01 for i in range(1, 80)])
    return {
        "singleTapHeight": single_tap[0], "singleTapDistance": single_tap[1],
        "singleMaxHeight": single_hold[0], "singleMaxDistance": single_hold[1],
        "doubleMaxHeight": best_h[0], "doubleMaxHeightAt": best_h[1],
        "doubleMaxDistance": best_d[0], "doubleMaxDistanceAt": best_d[1],
    }
