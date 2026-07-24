# Mission Certification Matrix — WP6

**Date:** 2026-07-19
**Branch:** `stabilize/wp6-mission-certification`
**Method:** two evidence layers, no phantom validation:

1. **Logic-level certification** (`tests/MissionCertificationTests.swift`, 6 tests):
   drives the REAL authority pipeline per mission — `prepareMissionForCombat` →
   `applyRoomEntry` walk through every room → clear → extraction intent →
   finalize → payout → disk-decode persistence check → defeat path → seeded
   replay rerolls. Runs in the full suite (126 tests, 0 failures as of 2026-07-24)
   locally and in CI.
2. **Runtime launch smoke** (simulator): Debug build launched with
   `SR_AUTOSTART_MISSION_ID` for each mission on **iPhone 17** and
   **iPad Pro 13-inch (M5)** (iOS 26.5 runtime). Process verified alive after
   14 s; screenshot captured per launch (12/12 alive). Spot-checked screenshots
   show fully rendered combat: room art, enemy sprites, initiative rolled,
   action tray, and correct per-device layout.

## Matrix — multi-room story missions

Column legend: result (evidence layer). L = logic-level test, S = simulator
launch smoke, D = recommended owner device pass.

| Mission | Launch | Room transitions | Combat completion | Extraction | Victory | Failure | Replay | Save/resume | iPhone | iPad |
|---|---|---|---|---|---|---|---|---|---|---|
| Mission001 | PASS (L+S) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (S) | PASS (S) |
| Mission002 | PASS (L+S) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (S) | PASS (S) |
| Mission003 | PASS (L+S) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (S) | PASS (S) |
| Mission004 | PASS (L+S) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (S) | PASS (S) |
| Mission005 | PASS (L+S) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (S) | PASS (S) |
| Mission006 | PASS (L+S) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (S) | PASS (S) |

What each logic column certifies (per mission, all six):

- **Launch/setup** — squad placed in-bounds on non-wall tiles; opposition count
  equals authored count at NG+0 / zero faction attention; live tile map installed.
- **Room transitions** — every room reachable from the entry room; `applyRoomEntry`
  syncs GameState + RoomManager + tiles for each; squad never lands in a wall.
- **Combat completion + Victory** — full clear of every room, extraction intent
  accepted, extraction sequence completes, `missionComplete` latches, victory
  recorded exactly once, wallet credited > 0, first-clear payment latched
  (Mission006 intentionally clears `paidThisRun` — finale starts the next
  campaign run; NG+ advance verified by tier snapshot/restore).
- **Failure** — full squad wipe ends combat with no victory record and no payout.
- **Replay** — rerolled squads deterministic within an attempt, ±1 threat budget,
  authored-pool-only, boss/unique slots untouched, positions/delays verbatim,
  for every room of every mission.
- **Save/resume** — completion decoded back from the raw UserDefaults blob
  (what a relaunch loads), plus WP2's corruption/migration coverage.
- **Room-graph integrity** — unique room ids, valid connection targets/triggers,
  known enemy/boss types only (22 spawn + 3 boss types, all mapped to factories),
  spawns in-bounds and never in walls, an extraction room exists.

## Runtime launch smoke receipts

| Device | Runtime | Missions | Result |
|---|---|---|---|
| iPhone 17 sim | iOS 26.5 | M1–M6 via `SR_AUTOSTART_MISSION_ID` | 6/6 alive @ 14 s, screenshots captured |
| iPad Pro 13-inch (M5) sim | iOS 26.5 | M1–M6 | 6/6 alive @ 14 s, screenshots captured |

Screenshots (12) are evidence, not source — kept outside the repo per the WP8
asset policy (session scratchpad `wp6_evidence/`; ask the stabilization agent to
copy them somewhere permanent if wanted). Spot-checked: iPhone M1 (combat HUD +
tutorial overlay, initiative log), iPad M5 (room art, enemy sprite, fitted map,
capped HUD — the recent iPad layout pass rendering as designed).

## Interstitial / mini-game missions (scene-driven, no JSON pipeline)

| Mission | Status | Evidence / gap |
|---|---|---|
| Mission002_5 (Mirrorline) | PARTIAL (L) | Payout + objective flag routed through tested authority (`recordVictory`, `requestObjectiveDataAcquired`); the scene's own play loop is NOT_COMPUTABLE headlessly |
| Mission003_5 (The Drop / chase) | PARTIAL (L) | Same; plus chase-completion backfill migration covered in WP2 persistence gaps list (WP7) |
| Mission004_5 (Basement brawl) | PARTIAL (L) | Same |
| Mission005_5 (Cold Trace) | PARTIAL (L) | Same |

## Replay modes — gauntlet, side contracts, arenas

**Added 2026-07-24 (PR #44).** WP6 shipped before these modes existed and this
document did not mention them; they were live with unit coverage only. A device
pass on 2026-07-23 found side contracts **uncompletable** while the whole suite
was green — see "Method correction" below.

Evidence: `tests/ReplayModeCertificationTests.swift` (6 tests) plus the existing
`ContractBoardTests` / `ArenaPoolTests`.

| Surface | Structure | Builds | Full clear | Extraction (walk-on) | Progression |
|---|---|---|---|---|---|
| Arenas (all 20) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | n/a |
| Side contracts (tiers 1–3) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) |
| Gauntlet floors (1–8 sampled) | PASS (L) | PASS (L) | PASS (L) | PASS (L) | PASS (L) |

What these certify:

- **Arenas** — every one of the 20 is driven through a REAL side contract, reached
  by sweeping seeds through `ArenaPool.arenaId(forSeed:)` rather than constructing
  rooms by hand. A player only ever rolls a handful, so an individually broken
  arena could otherwise sit undiscovered indefinitely. Structural gate additionally
  asserts: party spawn in-bounds and not in a wall, exit door on-map, sealing the
  arena yields a real extraction point whose tile is actually an extraction tile,
  enemies on non-wall in-bounds tiles, and known spawn types only.
- **Contracts** — all three tiers complete, not just the tier-1 offer the board
  test happens to use.
- **Gauntlet** — floors build and complete across the scaling band (composition
  changes at floor 4); exactly ONE arena per floor holds the exit and it is the
  last one (zero = unfinishable, several = skippable arenas); floor victory
  advances the pit and returns the floor just completed, a wipe resets to floor 1
  without erasing `bestFloor`.

Every run above is finished the player's way — walking a runner onto the pad via
`moveCharacter` — not by calling the extraction intent.

## Method correction — the player-input path (2026-07-24)

The logic layer described at the top of this document enters through AUTHORITY:
`applyRoomEntry` to walk rooms, `requestExtractionResolution` to extract. A player
calls neither. They move a runner onto a tile and the move commit decides what
that tile means.

That translation layer had **no coverage at all**, and it is where side contracts
broke: extraction resolved correctly at the authority level, but walking onto the
pad never reached it — extraction only adjudicated on an explicit tap or at the
end of an enemy phase, and with the last enemy dead there is no enemy phase. The
symptom was silence, because every messaged rejection lives inside
`requestExtraction`, which was never called. `ContractBoardTests`' own
"end to end" test additionally hand-called `markCurrentRoomCleared()`, so it
passed throughout.

`tests/StepOnSemanticsTests.swift` (7 tests) now enters one layer up, through
`moveCharacter` — the call the tap handler makes — and certifies that stepping on
a tile does what the tile promises: armed pad resolves the run; unarmed pad and
plain floor do not; a data-gated mission stays locked until the objective is met
and opens once it is; re-stepping does not double-resolve; the move budget still
refuses a second move. Doors are deliberately excluded — they are tap-only by
design (BattleScene bypasses `moveCharacter` there so a transition cannot trigger
`endTurn` mid-fade).

Both new suites are **mutation-checked**: reverting the extraction fix fails 4
tests in `StepOnSemanticsTests` and 3 in `ReplayModeCertificationTests`. A test
that cannot fail is not evidence.

## Honest gaps (NOT_COMPUTABLE via automation — recommended device pass)

Per the project's own history, simulated tap-automation of the combat HUD is
unreliable, so these remain human checks on real hardware:

1. Touch-driven combat feel: tap-to-move/target hit-testing, long-press stat
   sheets, camera pan/zoom during play.
2. Mission-intro VN cutscenes and mini-game scenes end-to-end.
3. On-screen ranged-attack damage numbers (pre-existing open playtest item).
4. Audio mix on device speakers.

Everything in the matrix above is machine-verified; these four are the
remaining certification surface for the owner's iPad pass.

**Caveat added 2026-07-24:** item 1 is doing more work than it looks. "Touch
feel" was treated as a taste question, but the tap/move → intent wiring UNDER it
is functional code that automation can reach, and leaving it uncovered is what
let a total blocker ship. `StepOnSemanticsTests` now covers the step-on half.
The genuinely non-computable remainder is hit-testing, gesture handling and
camera — the parts that need a finger.

## Exit gate

```yaml
WP6:
  all_missions_launch: PASS          # logic setup + 12/12 sim launches
  all_missions_complete: PASS        # logic-level full clear → extract → finalize, all 6
  all_transitions: PASS              # every room of every mission
  replay_paths: PASS                 # seeded reroll certified per room per mission
  save_resume: PASS                  # disk-decode + WP2 corruption/migration suite
  iphone_matrix: PASS                # launch smoke + rendered-combat screenshot evidence
  ipad_matrix: PASS                  # launch smoke + rendered-combat screenshot evidence
  touch_layer: DEVICE_PASS_RECOMMENDED  # documented gap, not silently claimed

# Added 2026-07-24 (PR #44) — replay modes were live but uncertified.
REPLAY_MODES:
  arenas_all_20: PASS                # each driven through a real contract via seed sweep
  arena_structure: PASS              # spawn/exit/enemy placement + extraction sealing
  contracts_all_tiers: PASS          # tiers 1-3 complete
  gauntlet_floors: PASS              # floors 1-8, one exit per floor, on the last arena
  gauntlet_progression: PASS         # victory advances, wipe resets, bestFloor survives
  player_input_path: PASS            # step-on semantics via moveCharacter, mutation-checked
  device_pass: PENDING               # nothing in this section has been run on hardware
```
