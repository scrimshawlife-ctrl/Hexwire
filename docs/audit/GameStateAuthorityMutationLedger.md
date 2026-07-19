# GameState Authority Mutation Ledger — WP4

**Date:** 2026-07-18
**Branch:** `stabilize/wp4-authority-seams`
**Audit method:** `grep -rn "GameState.shared" Game Rendering UI Missions` + assignment-pattern
scan (`\.(prop) *(=|+=|-=)`) + method-call census over `BattleScene.swift` (4,530 lines,
167 refs) and `CombatUI.swift` (2,407 lines).

## Classification summary (pre-migration)

| Layer | Sites | Classification | Post-WP4 status |
|---|---|---|---|
| `HexwireApp.swift` action closures (onAttack/onShoot/onEndTurn/… ×13) | 13 | INTENT_REQUEST — closures call `gameState.perform*()`/`endTurn()` authority methods | Unchanged pattern; `onEndTurn`/`onAttack` now route through typed intents (`endTurn()` delegates to `requestEndTurn()`) |
| `CombatUI.swift` reads (HUD, panels, previews) | ~2,300 lines | READ_ONLY_PROJECTION — `@ObservedObject` reads | Unchanged (correct) |
| `CombatUI.swift` calls (`performSpell`, `consumeRosterItem`, `throwGrenade`, `selectCharacter`, `completeAction`, `addLog`, `postTransientWarning`) | 15 | INTENT_REQUEST — authority methods validate internally | Unchanged (compliant) |
| `BattleScene` reads (positions, HP, phases for rendering) | ~120 | READ_ONLY_PROJECTION | Unchanged (correct) |
| `BattleScene` room-transition block (`enemies=`, `pendingSpawns=`, `currentRoomId=`, `extractionX/Y=` ×3 chains, `playerTeam[i].positionX/Y=`, `firstKillProcessedInRoom=`) | 14 assignments | **DIRECT_MUTATION** (the largest leak) | **MIGRATED** → `GameState.applyRoomEntry(to:enemies:pendingSpawns:spawnAnchor:)` — scene constructs authored spawn lists, authority mutates everything, scene renders from `GameState.enemies` |
| `BattleScene.loadRoom` (`currentRoomId=`, `firstKillProcessedInRoom=`) | 2 | **DIRECT_MUTATION** | **MIGRATED** → `syncRoomLoaded(roomId:)` |
| `BattleScene` early transition reset (`firstKillProcessedInRoom=`) | 1 | **DIRECT_MUTATION** | **MIGRATED** → `resetFirstKillTracking()` |
| `BattleScene` extraction-anim completion (`extractionAnimationInProgress=false` + finalize ×3 sites) | 3 | **DIRECT_MUTATION** | **MIGRATED** → `requestExtractionSequenceCompleted()` — exactly-once (duplicate completion signals now rejected instead of re-finalizing) |
| `BattleScene` targeting (`targetCharacterId=`) | 1 | **DIRECT_MUTATION** | **MIGRATED** → `requestTargetSelection(enemyId:)` (validation + log moved into authority) |
| `BattleScene` deselection (`selectedCharacterId=`, `activeCharacterId=`) | 2 | **DIRECT_MUTATION** | **MIGRATED** → `requestSelectionCleared()` |
| `BattleScene` movement (`moveCharacter(id:toTileX:toTileY:)` ×2) | 2 | INTENT_REQUEST (already authority-routed, but unvalidated at the seam) | **UPGRADED** → `requestMove(unitID:toTileX:toTileY:)` with typed rejection reasons (unknown/dead actor, wrong phase, out-of-bounds, wall, door, already-moved, prone) |
| `MirrorlineScene` / `ColdTraceScene` (`dataAcquired=true`) | 2 | **DIRECT_MUTATION** | **MIGRATED** → `requestObjectiveDataAcquired(source:)` — exactly-once |
| `SFXManager` (reads volume/mission for mix decisions) | 5 | READ_ONLY_PROJECTION | Unchanged |
| `VFXManager`, `CharacterInfoSheet`, `RoomManager` | 7 | READ_ONLY_PROJECTION / authority-internal | Unchanged |
| `MissionStatsStore.reduceFactionAttention` (syncs live GameState copy) | 1 | authority-to-authority sync | Unchanged (both are authority stores) |
| `tests/` singleton state setup | n/a | TEST_ONLY | Snapshot/restore pattern |

**Post-migration verification:** the assignment-pattern scan over `Rendering/` and `UI/`
returns **zero** direct GameState property mutations.

## Intent facade (`Game/GameIntents.swift`)

```swift
enum IntentResult { case accepted; case rejected(reason: String) }

@MainActor protocol CombatIntentHandling {
    func requestEndTurn() -> IntentResult
    func requestMove(unitID: UUID, toTileX: Int, toTileY: Int) -> IntentResult
    func requestAttack() -> IntentResult
    func requestTargetSelection(enemyId: UUID) -> IntentResult
    func requestSelectionCleared() -> IntentResult
    func requestObjectiveDataAcquired(source: String) -> IntentResult
    func requestExtractionResolution(characterId: UUID?, tileX: Int, tileY: Int) -> IntentResult
    func requestExtractionSequenceCompleted() -> IntentResult
}
extension GameState: CombatIntentHandling { ... }
```

Semantic rule enforced: **UI/Scene emits intent → authority validates → authority mutates
→ projection renders.** Door interactions keep their existing authority-side validation
(`RoomManager.attemptTransition` returns the validated room or nil); the packet's
`requestDoorInteraction` semantic is satisfied there and the scene only animates what
the authority approved.

## Packet implementation order — status

| # | Path | Status |
|---|---|---|
| 1 | end turn | DONE — `requestEndTurn` (phase latch + mission-over rejection, typed) |
| 2 | room transitions | DONE — `applyRoomEntry` + `syncRoomLoaded` |
| 3 | extraction | DONE — `requestExtractionResolution` wrapper + `requestExtractionSequenceCompleted` exactly-once |
| 4 | mission completion | DONE in WP2 (OutcomePipeline latch, exactly-once tested); objective flag now intent-gated |
| 5 | actor selection | DONE — `requestTargetSelection` / `requestSelectionCleared` (`selectCharacter` was already an authority method) |
| 6 | movement | DONE — `requestMove` |
| 7 | attacks | DONE — `requestAttack` facade; resolution already lived in CombatFlowController |
| 8 | interactable triggers | PARTIAL — doors validated by authority (`attemptTransition`); terminal-hack launch flow unchanged (UI presents, authority records via `requestObjectiveDataAcquired`) |
| 9 | replay/encounter init | Already authority-side (`MissionSetupService` + seeded rerolls, WP2-tested) — no scene mutations found |

## Behavior deltas (all defect-guards, not feature changes)

1. Duplicate extraction-completion signals (animation callback + 14s safety net both firing)
   now **reject** the second signal instead of re-running finalization (which was previously
   swallowed one layer deeper by `guard !combatEnded`). Net behavior identical; the guard is
   now at the seam with a typed result.
2. `endTurn()` after `missionComplete`/`combatEnded` is now rejected at the facade (previously
   it could advance `currentTurnCount` post-mission; harmless but untracked).
3. `requestMove` rejects out-of-bounds/wall/door destinations at the seam (previously the
   scene's tap-plumbing was the only thing preventing these).

## Safeguard tests (`tests/IntentFacadeTests.swift`, 12 tests — all green)

Per migrated path: accepted, rejected, duplicate, invalid phase, invalid actor,
invalid destination/target, exactly-once. Full suite: **79 tests, 0 failures**.

## Exit gate

```yaml
WP4:
  authority_ledger: COMPLETE
  high_frequency_direct_mutations: REMOVED   # zero remaining in Rendering/ + UI/
  intent_facade: PRESENT                     # Game/GameIntents.swift
  exactly_once_guards: TESTED                # objective, extraction completion, move budget, end-turn latch
  gameplay_behavior: PRESERVED               # 3 documented defect-guard deltas; 79/79 tests green
```
