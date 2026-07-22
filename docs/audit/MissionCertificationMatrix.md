# Mission Certification Matrix — WP6

**Date:** 2026-07-19
**Branch:** `stabilize/wp6-mission-certification`
**Method:** two evidence layers, no phantom validation:

1. **Logic-level certification** (`tests/MissionCertificationTests.swift`, 6 tests):
   drives the REAL authority pipeline per mission — `prepareMissionForCombat` →
   `applyRoomEntry` walk through every room → clear → extraction intent →
   finalize → payout → disk-decode persistence check → defeat path → seeded
   replay rerolls. Runs in the full suite (85 tests, 0 failures) locally and in CI.
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
```
