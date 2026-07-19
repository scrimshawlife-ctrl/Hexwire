# Stabilization Extraction Map — WP5

**Date:** 2026-07-19
**Branch:** `stabilize/wp5-complexity-extraction`
**Rule applied:** pure moves only — every extraction is a verbatim relocation of a
contiguous responsibility block into its own file (`extension GameState` /
free SwiftUI structs). No behavior rewrite, no new abstractions, no dependency
framework, names and interfaces preserved exactly. Verified by clean build +
the full 85-test suite (which includes WP6's per-mission certification —
the strongest available drift net).

## Completed extractions

```yaml
- source_file: Game/GameState.swift (2,673 → 2,176 lines, −497)
  extractions:
    - target_component: Game/GameState+CombatTactics.swift (358 lines)
      current_responsibilities: enemy overwatch reaction fire, flanking
        adjudication (incl. room-cleared signalling), per-type enemy AI
        dispatch, hex-grid neighbor/distance helpers
      authority_level: unchanged — GameState extension, same @MainActor isolation
      dependencies: DiceEngine, CombatFlowController, PathingAndAIHelpers,
        NotificationCenter (all pre-existing)
      tests_added: covered by existing suite (overwatch/flanking exercised via
        certification + combat tests); characterization deferred where behavior
        is dice-driven
      migration_status: DONE — pure move; the only private symbol in range
        (enemyOverwatchRange) moved together with its sole caller
    - target_component: Game/GameState+Environment.swift (157 lines)
      current_responsibilities: destructible cover conversion + per-room
        destruction records, explosive-barrel detonation (no-chain rule),
        ranged-fire cover degradation
      authority_level: unchanged
      dependencies: TileMap, DiceEngine, HapticsManager, CombatFlowController
      tests_added: WP2 TurnAuthorityTests already pin this domain (destroy /
        no-chain / reload survival) — they ran green post-move
      migration_status: DONE

- source_file: UI/CombatUI.swift (2,407 → 632 lines, −1,775)
  extractions:
    - target_component: UI/CombatWidgets.swift (989 lines)
      current_responsibilities: HP/XP/stun/mana bars, portrait badge, team
        roster bar, status display, action buttons + action tray, combat log
        views, loot/intel badges, utility buttons, mission intel card, corner
        bracket chrome
      authority_level: READ_ONLY_PROJECTION + intent closures (unchanged)
      migration_status: DONE — whole-struct moves; struct-scoped privates intact
    - target_component: UI/CombatPickerSheets.swift (501 lines)
      current_responsibilities: spell picker sheet, item picker sheet
      migration_status: DONE
    - target_component: UI/HitPreviewViews.swift (295 lines)
      current_responsibilities: hit preview card/strip/compact pill
      migration_status: DONE
  remaining_in_file: CombatTheme, Color(hex:), TurnIndicatorBanner, the main
    CombatUI composition view, previews — a single-screen composition file

- source_file: Rendering/BattleScene.swift (4,530 → 4,436 lines)
  extractions:
    - WP4 already relocated the room-entry authority block (the scene's largest
      non-rendering responsibility) into GameState.applyRoomEntry
    - this WP: deleted dead private firstExtractionTile(in:) (orphaned by WP4;
      LEGACY_OR_DORMANT per the WP4 ledger)
  migration_status: PARTIAL BY DESIGN — see deferred section
```

## Deferred (documented, not silently skipped)

```yaml
- candidate: BattleScene file-split (camera / board rendering / unit rendering /
    interaction translation / animation orchestration)
  reason: the scene's sections share ~40 private stored properties; a file-split
    requires widening them to internal, which INCREASES mutation reach — the
    opposite of this WP's goal — or a stateful-controller refactor, which is a
    rewrite, not a seam move. Needs characterization tests around touch
    translation + camera fit first (the two most entangled domains).
  entry_condition: post-RC, or when a rendering bug forces work in those areas
- candidate: BattleScene's duplicate enemy factory switch (room-transition
    spawns) vs MissionSetupService.makeEnemy
  reason: consolidating changes archetype assignment on transition spawns —
    a real behavior change requiring a characterization test of both paths
    before unifying. Flagged in the scene's own comments as a parity risk.
- candidate: GameState "Computed" block (1,133–1,443) + inventory/loot section
  reason: heavily @Published-interleaved; moving @Published storage out of the
    class body is not a pure move. Revisit only with a stronger seam design.
```

## Exit gate

```yaml
WP5:
  central_file_responsibility: REDUCED   # GameState −497, CombatUI −1,775 lines;
                                          # 5 new single-responsibility files
  behavior_drift: NONE_OBSERVED          # full suite 85/85 post-move, incl.
                                          # per-mission certification
  compile: PASS
  tests: PASS
```
