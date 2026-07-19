# Test Coverage Map — WP2

**Date:** 2026-07-18
**Branch:** `stabilize/wp2-test-baseline`
**Suite:** 65 tests / 0 failures / 0 flaky (3 consecutive green runs on a pre-booted
iPhone 17 simulator, iOS 26.5, fresh DerivedData).

## Runner note (infrastructure, not flakiness)

Back-to-back `xcodebuild test` invocations against a cold or tearing-down simulator
intermittently fail **before any test runs** with
`FBSOpenApplicationServiceErrorDomain … SBMainWorkspace: Busy (Application failed
preflight checks)`. With the simulator pre-booted and settled
(`simctl boot` + `simctl bootstatus <udid> -b`), the suite is 100% stable.
WP3's CI workflow must pre-boot the destination simulator.

## Inventory

| System | Existing tests | Missing critical cases | Priority |
|---|---|---|---|
| Turn flow | `TurnAuthorityTests`: initiative order build, round wrap exactly-once, end-turn phase latch (rejected in enemyResolving/combatResolved), accepted end-turn increments exactly once | Full multi-actor phase walk with living team (needs mission bootstrap seam); "no player input during enemy phase" beyond end-turn (move/attack intents — WP4 intent facade is the right seam) | WP4 |
| Combat math | `CombatMathTests` (pre-existing): dice invariants, cover tiers, cover line-trace; `DiceDeterminismTests`: seeded roll/opposedRoll/soakRoll full determinism, rules recount (hits/glitch/critical), unseeded invariants | Damage application end-to-end (attack→soak→HP) via intent API; invalid-target rejection (WP4 facade) | WP4 |
| Mission lifecycle | `TurnAuthorityTests.testMissionOutcomeFinalizesExactlyOnce`: OutcomePipeline latch — second finalize records nothing, pays nothing | Defeat path; per-mission-type completion flows (runtime, WP6 matrix) | WP6 |
| Replay seeds | `ReplaySpawnTests`: same attempt+room ⇒ identical squad; 30 attempts ⇒ variation; first clear ⇒ authored squad verbatim | Reinforcement-service seed determinism (same SplitMix64 family, separate service) | Medium |
| Spawn placement | `ReplaySpawnTests`: determinism, distinctness, walkable-only, door/extraction exclusion, occupied avoidance, cramped-room anchor-overflow contract | Enemy spawn templates (per-mission JSON validation — WP3 hygiene job candidate) | Medium |
| Economy | `EconomyPersistenceTests`: first-clear payout formula (base×rank×risk×run), replay 25% residual, data/grimoire bonuses gated on acquisition, rank boundaries, rank multipliers, kill bounty floor, spend guards (negative/overdraft), credit guards, score components+caps, wallet moves exactly once per victory | Shop purchase flows (UI-side, WP4/WP6) | Low |
| Progression (XP/levels) | indirectly via exactly-once test (participation XP path executes) | Level-up threshold math; cyberware effect application | Medium |
| Persistence | `EconomyPersistenceTests`: legacy `ShadowrunGame.*`→`HexWire.*` migration (copies, preserves old, never overwrites new, flag-guarded no-replay), MissionStats lastGood backup semantics, roster round-trip, corrupt roster→defaults, corrupt roster→lastGood recovery, legacy bare-array roster decode, freshenForMission transient-vs-progression split | MissionStatsStore corrupt-blob **live reload** path (load() is private and runs once per process — needs a small internal seam; WP7), faction-attention persistence round-trip | WP7 |
| Status effects | `CombatMathTests.testBurningDisplayName` (pre-existing) | Application/expiration over turns (needs combat bootstrap; WP4 seam makes this testable) | WP4 |
| Overwatch | none | fireOverwatchShot result handling (27-site unused-result warning WP1-B2) — test alongside WP4 authority work | WP4 |
| Cover destruction | `TurnAuthorityTests`: destroy converts cover→floor + per-room record, invalid/OOB no-ops, destruction survives room reload | `maybeDegradeCoverAlongShot` 25% chance path is unseeded (`Double.random`) — needs the same RNG seam DiceEngine got; deferred WP4/WP5 | Medium |
| Explosive props | `TurnAuthorityTests`: impact-adjacent barrels detonate to floor, adjacent-but-out-of-radius barrel does NOT chain, distant barrel untouched, empty impact no-op; `DiceDeterminismTests`: barrel coordinate hash determinism + rate band | Blast damage/soak application to units (unit-in-blast fixture; needs care with live UI host) | Medium |
| Room transitions | none (RoomManager loaded/unloaded as fixture only) | attemptTransition/beginTransition/completeTransition state machine; door backtrack rules | WP6 |
| Extraction | none | requestExtraction validation (via WP4 intent tests) | WP4 |
| Save migration | covered under Persistence (key rename + chase backfill exists in code; backfill untested) | `migrateBackfillChaseCompletion` footprint test (M1–M3 done, M3.5 missing ⇒ backfilled once) | WP7 |
| Consequence loop | `ConsequenceEngineGoldenTests` (pre-existing, 14 golden tests) | — | Low |

## Production change made for testability

`Game/DiceEngine.swift`: added seed-injectable overloads
`roll(pool:tn:using:)`, `opposedRoll(attackerPool:defenderPool:tn:using:)`,
`soakRoll(pool:tn:using:)` over a generic `RandomNumberGenerator`; the existing
unseeded entry points now delegate through `SystemRandomNumberGenerator` and are
behavior-identical. This satisfies packet §5.2 (randomness must accept a
reproducible seed) with zero call-site changes.

## Known intentional behaviors pinned by tests

- Cramped-room spawn overflow **stacks runners on the anchor** (documented in
  `findGroupSpawnSlots`); the test pins walkable-tiles-first + anchor-overflow.
- Replay squad rerolls preserve authored positions/delays, stay within ±1 threat
  cost, never touch boss/unknown slots, and are seeded by (attemptId, roomId).
- A duplicate mission-finalize signal is swallowed whole (no double payout).

## Exit gate

```yaml
WP2:
  existing_tests: INVENTORIED          # 22 pre-existing across 2 files
  required_critical_tests: IMPLEMENTED # 43 added across 4 files (65 total); gaps above are
                                       # explicitly deferred to the WP that owns the seam
  deterministic_tests: PASS
  flaky_tests: ZERO                    # 3 consecutive green runs, pre-booted simulator
  test_failures: ZERO
```
