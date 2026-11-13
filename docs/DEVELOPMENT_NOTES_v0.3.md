# DROPVERSE v0.3: Double Jump, Falling-Bug Fix, Difficulty Redesign and Rhythm Timing Guide

> **Build status:** Xcode isn't available in this environment, so **the Swift code has not been compiled or run**. Gameplay and level data were verified with the Python mirror of the simulation (§6). Please run ⌘B and ⌘U and send back any compiler errors or test failures.

---

## 1. Root cause of the "unexpected falling" bug

DROPVERSE uses **no SpriteKit physics bodies**. The simulation is the custom, deterministic `WorldPhysics.step`, and sprites only display its state. So bit masks, restitution, friction and `usesPreciseCollisionDetection` don't apply. The audit therefore focused on the simulation and on whether everything it simulates is also drawn. It found three causes.

| # | Cause | Evidence | Fix |
|---|---|---|---|
| **1 (primary)** | **Pits were simulated but never drawn.** `Course.pits` cut real gaps into the floor's collision, but `ObstacleRenderer` had no pit visual and `WorldBackdrop` drew the floor as one continuous band. The player fell through floor that looked solid, always near other obstacles, because pits only appear inside patterns. | In v0.2, `grep pits` outside `Game/Simulation` found nothing. Four patterns contained pits (`cube.double_spike_lift`, `cube.saw_narrow_landing`, `cube.note_hop`, `cube.orb_chain`), and an idle run through `note_hop` dies with cause `fell` on flat-looking ground. | Pits are now `CourseObject`s of kind `.pit`, drawn as a black void that cuts the floor band, with glowing red rims. `ObstacleRenderer.draws(_:)` is an exhaustive switch, so adding a simulated kind without a visual is a **compile error**. Regression test: `testEveryPitIsDrawn`. |
| 2 | **Simulation teleport after frame hitches.** When a frame needed more than 24 catch-up steps, `GameScene` set `simTau = targetTau`. The player was moved forward without being simulated and could land inside a block or past a pit edge, dying "with no obstacle". | The line `simTau = targetTau // long hitch` in v0.2's `GameScene.update`. | The simulation is never skipped. Up to 60 steps (0.5 s) run per frame, and any remainder is worked off on later frames. Lag is shown in the debug overlay. |
| 3 | **Unforgiving edge landings.** Landing a few points low on a gap's far edge counted as a wall hit. With cause 1, that looked like dying on flat floor. | Reproduced: a tap jump over a 229 pt gap meets the edge 7.7 pt low and dies (`wall`). | **Ledge catch:** if the previous step was within 12 pt of the surface, the cube snaps onto it. Widths 229–231 pt now survive, while 300 pt still falls (`testLedgeCatchInsteadOfInvisibleWallDeath`). |

**Checked and ruled out:**
- **Floor seams:** the floor is one support split only at real pits. Touching or overlapping pits merge exactly (`testAdjacentAndOverlappingPitsLeaveNoSeams`).
- **Cleanup:** it removes only objects fully behind the camera.
- **Stage boundaries:** they don't move the floor (`testStageBoundaryKeepsTheFloorContinuous`).
- **Grounded state:** it comes from the support actually contacted that step (`supportID`, `supportCount`), never from a fixed y value.
- **Scrolling:** the player's x comes from the audio clock through the speed track, and every obstacle is placed from the same track, so the two can't drift apart.

**Not verifiable here:** the bug report came with no failing seed, so there is no seed-based regression test. The **flight recorder** (below) will capture one if anything else turns up.

### Instrumentation (Settings ▸ Developer, debug builds)
- **Physics overlay:**
  - shows x, y, vy, grounded, jumps left, support contacts, support id, mode and gravity
  - shows the last contact, last event, stage seed and simulation lag
  - has a **Copy flight log** button
- **Collision bounds:** draws the simulation's hitboxes, not the sprites:
  - the player's box in green
  - supports in cyan, and the current support in green
  - lethal cores in red
  - pits in yellow
  - triggers in white
- **Flight recorder:** keeps the last 3 s of state (x, y, vy, grounded, jumps, support, events, input) and writes it to the system log on every death.
- **`lostSupport` event:** marks leaving the ground without a jump, pad, orb or portal, and is logged as a possible unexpected fall.

## 2. Double jump

**Input**
- Each touch-down is a new tap, a second finger included. There is no gesture recognizer, so the first jump fires on the next 120 Hz step.
- Holding never triggers the air jump. It still extends jump height and, as before, re-jumps from the ground on landing.
- A tap while falling counts as a **buffered ground jump** if a surface is within reach in the next 0.1 s (computed from the real geometry). Otherwise the **air jump** fires immediately. So jump buffering keeps working and the second jump never needs a waiting period.

**Physics** (`Sim` in `SimConstants.swift`, all configurable):
- Jump velocities: 620 for the ground jump, 650 for the air jump, 520 and 545 for mini mode.
- The air jump **resets** vertical velocity rather than adding to it.
- Gravity 1850; hold 0.18 s; coyote time 0.08 s; buffer 0.10 s.

**Jump rules**
- `jumpsRemaining` resets to 2 on any valid landing, on the floor or, under flipped gravity, the ceiling.
- Walking off a ledge leaves only the air jump once coyote time expires.
- Pads, gravity changes and entering cube mode through a portal also leave only the air jump.
- Ship and Wave modes have no conventional double jump.
- If you tap while touching an orb, the orb takes priority over the air jump.

**Measured jump envelope** (`Reachability`, by simulation):

| | Single tap | Single held | Double |
|---|---|---|---|
| Height | 101 pt | 156 pt | **325 pt** |
| Distance | 211 pt | 269 pt | **541 pt** |

**Feedback**
- **Expressions:** a new `doubleJump` face (widest eyes, excited grin) and a `modeSwitch` face.
- **Spin and glow:** a 270° spin boost and an aura flare.
- **Per-skin effects:**
  - **Neon Reactor:** magenta ring and white sparks.
  - **Glitch Pulse:** pixel shards.
  - **Bass Crusher:** gold shockwave and a light shake.
  - **Prism Drive:** prismatic burst.
- **Per-skin sound:** a synthesized two-note sting (sine, bit-crushed square, saw thump, bell) on its own audio node, so the music timeline is never affected.

## 3. Difficulty and level generation

- **14 new double-jump patterns** (45 total):
  - long gap
  - kick + snare (bar-aligned: jump on the kick, double on the snare)
  - elevated spike wall
  - double-layer platforms
  - note stairs
  - mid-air saws
  - saw gap
  - **falling platforms** (a new obstacle that cracks, shakes for one beat, then drops)
  - high-low alternation
  - double-jump chain
  - orb launch
  - inverted double
  - moving laser sweep
  - precision notes
- **Proven necessity:** `requiredJumps` is computed, not just declared. A pattern is marked **2** only if the solver *fails* with the air jump disabled at every tempo. Nine patterns qualify: long gap, kick + snare, mid-air saws, saw gap, high-low alternation, chain, orb launch, laser sweep and precision notes.
- **Pattern metadata:**
  - id, difficulty, mode, beats
  - entry and exit state
  - `requiredJumps`, `settleBeats` (beats to land again after a transition) and `barAligned`
  - validated `cues` and `strategies`
- **Generator rules:**
  - New tier weights: 1–3 Challenging, 4–8 Hard, 9–15 Very Hard, 16+ Expert.
  - A double-jump bias, and a **mandatory proven double-jump section** in every stage of 64+ beats. It's placed right after the Surfer section, and Surfer/Wave sections are steered back to Runner until it has happened.
  - Surfer still required. **Wave Mode joins at stage 9**, the Very Hard band, as the difficulty plan specifies.
  - **Never** a mandatory double jump right after a section where the player can't have landed: the settle gap covers this.
  - Kick/snare patterns start on downbeats.
  - Retry reproduces the identical layout.

## 4. Rhythm Timing Guide (Settings ▸ Rhythm Assistance)

| Setting | Default |
|---|---|
| Show Beat Grid | Off |
| Show Tap Timing Guides | Off |
| Show Beat Subdivisions | Off (choices: 1/2, 1/4) |
| Guide Opacity | 65% (range 20–100%) |
| Timing feedback | On |
| Audio/Visual Timing Offset | 0 ms |
| Touch latency compensation | 0 ms |

Settings are saved and apply **immediately**, including mid-run.

**Beat grid**
- **Styles:** bars are strong cyan, beats are thin violet, half-beats dashed, quarter-beats dotted.
- **Alignment:** lines fall on the *song's* beats (half-time songs folded to the gameplay grid still show their real beats). Each stage's grid starts at its own drop downbeat, never at audio time 0.
- **Theme blending:** the grid colour blends into the new theme at song changes.

**Tap markers**
- **Colours:** cyan for jump, magenta for double, yellow for orb, violet for gravity. Each marker shows its tolerance window as a band.
- **Validated strategies only:** markers come only from **validated strategies**:
  - `Tools/annotate_patterns.py` takes a solver solution and re-times each press to the centre of its success interval, snapping to the ¼-beat grid where possible.
  - It keeps the largest window that still completes the pattern at the slowest *and* fastest tempo.
  - Patterns with less than ±0.06 beat of tolerance get **no markers**.
  - Single-jump patterns never show a double-jump cue.
- **Positioning:** positions follow `referenceX + (actionTime − audioTime) × scrollSpeed`, through the audio clock and the speed track.
- **Pause:** stays aligned across pause and resume.

**Judgments** (PERFECT ≤35 ms, GREAT ≤70, GOOD ≤110, otherwise EARLY or LATE)
- Calculated from touch timestamps with latency compensation.
- Presses more than 200 ms from any marker are ordinary jumps and aren't judged.
- The guide never changes physics (`testGuidesDoNotAffectPhysics`).

**Layers (back to front):** decorative notes → guide grid → markers → obstacles → trail → player → effects and judgments → debug.

## 5. Modified files

**New**
- `Game/FlightRecorder.swift`
- `Levels/Reachability.swift`
- `Music/SoundEffects.swift`
- `Visuals/RhythmGuide.swift`
- `Visuals/DebugBoundsRenderer.swift`
- `Tests/RhythmGuideTests.swift`
- `Tools/annotate_patterns.py`

**Changed**
- `Game/Simulation/{SimConstants, Course, WorldSimulation}.swift`: double jump, ledge catch, falling platforms, drawable pits, moving lasers, diagnostics
- `Game/GameScene.swift`: hitch fix, effects, guides, judgments, recorder, debug
- `Game/GameCoordinator.swift`: live settings, sound effects, debug, song BPM
- `Levels/{PatternLibrary, LevelGenerator, LevelValidator, DifficultyManager}.swift`
- `Visuals/{ObstacleRenderer, TextureFactory}.swift`
- `Characters/{CharacterRenderer, PlayerRig}.swift`
- `Music/MusicManager.swift`: sound effect node
- `Persistence/GameSettings.swift`: new settings, tolerant decoding
- `UI/{SettingsView, GameContainerView}.swift`
- `Core/GameConstants.swift`
- `Resources/Patterns/patterns.json` (45 patterns)
- `Tests/{SimulationTests, LevelTests}.swift`
- `Tools/{dropverse_sim, dropverse_gen, validate_patterns, validate_stages}.py`

**Project:** no build-setting changes. If you use XcodeGen, run `xcodegen generate` again so the new files are picked up. If you set the project up manually, add the new `.swift` files to their targets.

## 6. Verification status

**Verified here with the Python mirror of the simulation**

*Pattern checks*
- **Solver method:**
  - inputs decided only every 50 ms, so no frame-perfect presses
  - a hitbox 1 pt larger than the game's
  - run at the slowest (k 0.70), reference (1.0) and fastest (1.41) tempos
- **Patterns:** all 45 are completable at all three tempos.
- **Pairs:** every compatible pattern pair was checked back to back with the minimum gap: 2,356 checks, 0 failures.
- **Lethality:** every non-transition pattern kills a player who doesn't press anything.
- **Double jump proven necessary:** the patterns marked `requiredJumps: 2` can't be completed without the air jump at any tempo.
- **Cue strategies:** every cue strategy completes at both tempo extremes, at its centre timing and at each window edge.

*Stage checks*
- **Full stages:** 128 generated stages (stages 1–25, several seeds and lengths) were proven completable at both tempo extremes. Every stage of 64+ beats contains a proven double-jump section.
- **Tutorial:** the tutorial sequence is completable.

*Bug evidence*
- The ledge-catch improvement (229–231 pt widths) and the jump envelope were measured, not estimated.

**Not verified:**
- Swift compilation and tests. The Swift port mirrors the Python line by line, and the golden generator sequences and Reachability values in the tests catch drift between them.
- Feel on a device. Double-jump strength (650 vs 620), the ledge catch, and judgment windows need playtesting.
- Visual alignment of guides with what you hear on a real iPhone, especially over Bluetooth. Use the A/V offset setting to calibrate.
- The original falling reports. The three causes above explain the behaviour and are fixed, but nobody has re-tested on your device.

```bash
python3 Tools/annotate_patterns.py            # recompute requiredJumps + cues after editing patterns.json
python3 Tools/validate_patterns.py --pairs    # ~4–5 min
python3 Tools/validate_stages.py              # ~1.5 min
```
