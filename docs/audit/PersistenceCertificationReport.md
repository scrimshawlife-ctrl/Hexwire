# Persistence Certification Report — WP7

**Date:** 2026-07-19
**Branch:** `stabilize/wp7-persistence`
**Suite:** 94 tests / 0 failures (9 added this WP on top of WP2's persistence coverage).

## Persistence inventory (complete)

| Surface | Store / file | Keys | Format |
|---|---|---|---|
| Mission records (completion, best score, attempts, mini-game best) | `MissionStatsStore` | `HexWire.MissionStats.v1` (+ `.lastGood` backup) | JSON `[String: MissionRecord]` |
| Wallet (nuyen) | `MissionStatsStore` | `HexWire.PlayerNuyen.v1` | Int |
| Per-run payout latch | `MissionStatsStore` | `HexWire.PaidThisRun.v1` | JSON `Set<String>` |
| Faction attention | `MissionStatsStore` | `HexWire.FactionAttention.v1` | `[String: Int]` dict |
| Roster progression (levels/XP/gear/cyberware) | `RosterStore` | `HexWire.Roster.v1` (+ `.lastGood`) | versioned JSON envelope; legacy bare-array still decodable |
| New Game+ tier | `NGPlusStore` | `HexWire.NGPlusTier.v1` | Int (clamped ≥ 0) |
| Gauntlet floors | `GauntletStore` | `HexWire.Gauntlet.CurrentFloor.v1`, `.BestFloor.v1`, `.FloorMission.v1` | Ints/String |
| Tutorial tip suppression | `TutorialCoach` (+ CombatUI hint cards) | per-tip `udKey` bools | Bool |
| One-shot migration flags | `StorageMigration`, backfill | `HexWire.Migration.KeyRename.v1`, `HexWire.Migration.ChaseBackfill.v1` | Bool |
| Legacy (pre-rebrand) keys | read-only migration source | `ShadowrunGame.*` mirrors of the above | as above |

No files, Core Data, or keychain surfaces exist; everything persists via
`UserDefaults`. Mid-combat state is intentionally NOT persisted (missions
restart on relaunch; progression/economy persist) — by design, documented here.

## Defect found and fixed (direct evidence)

**`MissionRecord` used synthesized Codable while `bestMiniGameScore` was added
after early saves shipped.** A records blob written before that field existed
fails synthesized decoding (`keyNotFound` is a hard error), the `.lastGood`
backup is same-format so it fails too, and `load()` then falls back to empty —
**silently wiping every mission completion on upgrade** for veteran installs.

- Proven by two probe tests written BEFORE the fix (both failed exactly as
  predicted): pre-field blob decode, and the end-to-end legacy-install upgrade
  simulation (`ShadowrunGame.*` keys + old-format blob → rename migration →
  decode).
- Fixed with a tolerant `init(from:)` (`decodeIfPresent` + defaults for every
  field). Encoding unchanged; current-format blobs decode identically.
- Both probes now pass; full suite green.

## Required test coverage → status

| # | Packet case | Status | Where |
|---|---|---|---|
| 1 | fresh install defaults | PASS | `testFreshInstallDefaultsAreSafe` |
| 2 | normal save/load | PASS | WP2 round-trips + WP6 disk-decode per mission |
| 3 | legacy save migration (key rename) | PASS | WP2 + `testUpgradeFromLegacyInstallPreservesProgressEndToEnd` |
| 4 | missing-field migration | PASS (after fix) | `testLegacyRecordBlobWithoutMiniGameFieldStillDecodes`, unknown-extra-field test |
| 5 | malformed value handling | PASS | WP2 corrupt-roster tests + `testDecodeRecordsRecoveryChain` |
| 6 | corrupt payload handling | PASS | recovery chain: live→backup→defaults, never a crash; backup only consulted when live exists-but-corrupt |
| 7 | duplicate reward prevention | PASS | WP2 (25% residual latch) + WP2/WP6 exactly-once finalize |
| 8 | mission completion idempotency | PASS | WP2 `testMissionOutcomeFinalizesExactlyOnce` + WP6 per-mission |
| 9 | interrupted lifecycle | PASS | `testPartialKeyStateLoadsIndependently` (keys load independently; save order can't hold the wallet hostage) |
| 10 | app upgrade simulation | PASS | end-to-end: legacy keys + old-format blob → rename → tolerant decode → progress intact |

Also certified: chase-completion backfill migration (eligible footprint
backfills exactly once, `paidThisRun` deliberately untouched for the make-good
payout, flag never replays, ineligible installs untouched) and faction-attention
round-trip with unknown-future-faction tolerance.

## Testability seams added (behavior-preserving)

- `MissionStatsStore.decodeRecords(live:backup:)` — the recovery chain
  extracted from `load()` verbatim (load() runs once per process; the chain
  was untestable). `load()` now calls it.
- `migrateBackfillChaseCompletion()` widened private → internal (init-time
  one-shot; unobservable otherwise).

## Exit gate

```yaml
WP7:
  persistence_inventory: COMPLETE
  migration_tests: PASS
  corrupted_state_behavior: DEFINED_AND_TESTED   # live→lastGood→defaults, no crash, no overwrite of inspectable data
  duplicate_rewards: PREVENTED                   # paidThisRun latch + exactly-once finalize, tested
  data_loss_risk: ACCEPTABLE                     # the one real loss vector (missing-field decode) found and FIXED with regression tests
```
