import Foundation

final class GameSessionState {
    var enemyPhaseCount: Int = 0
    var isEnemyPhaseRunning: Bool = false
    var hasLoggedTraceTriggerForCurrentRun: Bool = false
    var playersWhoHaveNotActed: Set<UUID> = []

    /// Number of player turns completed in the current player cycle.
    /// Enemy phase begins once this reaches 4 or all living players have acted.
    var playerTurnsCompleted: Int = 0

    /// Per-character movement tracking: if true, character has already moved this turn
    /// and cannot take a major action (attack/defend/cast/item) in the same turn.
    /// Reset at start of each round.
    var characterHasMovedThisTurn: [UUID: Bool] = [:]

    /// True when any living player has HP <= 0 (player death occurred).
    /// Used to block room transitions after player death.
    var playerIsDead: Bool = false

    var currentMissionTiles: [[Int]] = []
    var pendingSpawns: [GameState.PendingSpawn] = []

    var missionLoadIndex: Int = 0
    var defendingCharacterId: UUID?

    var extractionX: Int = 8
    var extractionY: Int = 1

    var lastAppliedCorpEnemyModifier: Int = 0
    var lastAppliedGangAmbushRadius: Int = 999
    var didApplyAttentionRecoveryLastMission: Bool = false
    var didApplyHighTraceEscalationBonusLastMission: Bool = false
    var lastRewardTier: RewardTier = .low
    var lastRewardMultiplier: Double = 1.0
    var missionTypeBonusMultiplier: Double = 0.0

    var combatWon: Bool? = nil
    var currentMapSituation: MapSituation = .corridor
    var missionHeat: Int = 0
    var missionHeatTier: HeatTier = .low
    var missionTargetTurns: Int = 6
    var currentTurnCount: Int = 0
    var isItemMenuVisible: Bool = false

    // Mission narrative text (loaded from JSON or set during mission setup)
    var missionBriefingText: String? = nil
    var missionCompleteSummaryText: String? = nil

    /// Mission-objective: data acquisition (e.g. M2's "hack the core terminal").
    /// Set to true at mission load when any TileType.dataTerminal exists on the map.
    /// While true and `dataAcquired` is false, extraction is blocked.
    var missionRequiresData: Bool = false
    var dataAcquired: Bool = false

    /// M3-specific: set true when a player steps on the grimoire pickup tile
    /// in the Ritual Chamber after the boss mage is dead. Reflected in the
    /// RUN COMPLETE / debrief screens. Reset on mission setup.
    var grimoireAcquired: Bool = false

    /// M3-specific: set true once Sato (the corp mage at the M3R2 altar)
    /// has been killed and his TRUE FORM (the boss mage) has manifested.
    /// One-shot per mission attempt so killing additional mages in the
    /// room can't re-trigger the phase change.
    var mageBossPhase2Triggered: Bool = false

    /// M3-specific: set true when Sato dies BUT other enemies are still alive.
    /// The phase-2 boss spawn is deferred until those other enemies are also
    /// dead so the boss never appears mid-melee. Cleared when the boss is
    /// actually spawned. Read by `checkMageBossPhase2PendingResolve` on every
    /// subsequent enemy death.
    var mageBossPhase2Pending: Bool = false

    /// M3-specific: stores the tile the deferred boss should spawn on (the
    /// corp mage's last position) so we can place him correctly when the
    /// remaining mooks are cleared.
    var mageBossPendingSpawnX: Int = 0
    var mageBossPendingSpawnY: Int = 0

    /// Running total of enemies killed across ALL rooms of the current mission.
    /// `gameState.enemies` is replaced on every room transition, so the post-
    /// mission "Enemies Defeated" stat must read this counter, not the live
    /// enemies array. Reset to 0 in setupMission / setupMultiRoomMission.
    var missionEnemiesDefeated: Int = 0

    /// Whether the first enemy of the CURRENT room has already been killed.
    /// Used to drop dynamic barriers (rooms with `removeOnFirstKill`).
    /// Reset to false when entering a new room.
    var firstKillProcessedInRoom: Bool = false

    /// Set true once the extraction animation has been requested. Prevents the
    /// player tapping the extraction tile a second time and stacking heli
    /// animations / triggering a double-finalize.
    var extractionAnimationInProgress: Bool = false

    /// Original AGI of enemies before Face's INTIMIDATE temporarily nerfs it.
    /// Restored at the start of the next round (intimidation lasts one round).
    /// Map: enemy.id → original AGI value.
    var intimidationOriginalAgi: [UUID: Int] = [:]

    /// Pending coords of the terminal so we know where to "complete" the
    /// pickup once the Matrix mini-game is won. Mini-game show flag itself is
    /// `@Published` directly on GameState so SwiftUI overlays react to it.
    var pendingHackTerminalX: Int = 0
    var pendingHackTerminalY: Int = 0
    var pendingHackCharacterId: UUID? = nil

    /// Stable display id for the currently-loaded mission (e.g. "Mission001").
    /// Set in MissionSetupService.setupMission/setupMultiRoomMission and read
    /// in OutcomePipeline to record the run's score against the right key.
    var currentMissionDisplayId: String? = nil
}
