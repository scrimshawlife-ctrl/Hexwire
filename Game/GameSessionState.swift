import Foundation

final class GameSessionState {
    var enemyPhaseCount: Int = 0
    var isEnemyPhaseRunning: Bool = false
    var hasLoggedTraceTriggerForCurrentRun: Bool = false
    var playersWhoHaveNotActed: Set<UUID> = []

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

    /// Mission-objective: data acquisition (e.g. M2's "hack the core terminal").
    /// Set to true at mission load when any TileType.dataTerminal exists on the map.
    /// While true and `dataAcquired` is false, extraction is blocked.
    var missionRequiresData: Bool = false
    var dataAcquired: Bool = false
}
