import Foundation

// MARK: - Spell Type
// (Consolidated here from Entities/Spell.swift on 2026-04-19 to work around
//  the same Xcode cross-file type resolution issue that affected MultiRoomMission.)

enum SpellType: String, CaseIterable, Codable {

    case fireball   // AoE Physical — scorches all living enemies
    case manaBolt   // Single-target Physical — raw mana lance
    case shock      // Single-target Stun — lightning jolt
    case heal       // Self-heal — mend flesh and stun

    // MARK: Display

    var displayName: String {
        switch self {
        case .fireball: return "Fireball"
        case .manaBolt: return "Mana Bolt"
        case .shock:    return "Shock"
        case .heal:     return "Heal"
        }
    }

    var icon: String {
        switch self {
        case .fireball: return "flame.fill"
        case .manaBolt: return "bolt.fill"
        case .shock:    return "bolt.circle.fill"
        case .heal:     return "cross.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .fireball: return "FF4422"
        case .manaBolt: return "6699FF"
        case .shock:    return "FFEE00"
        case .heal:     return "44CC88"
        }
    }

    var manaCost: Int {
        switch self {
        case .fireball: return 4
        case .manaBolt: return 3
        case .shock:    return 2
        case .heal:     return 2
        }
    }

    var baseDamage: Int {
        switch self {
        case .fireball: return 5   // AoE, so lower per-target
        case .manaBolt: return 8   // Strong single-target
        case .shock:    return 6   // Stun track
        case .heal:     return 0
        }
    }

    var description: String {
        switch self {
        case .fireball: return "Blast ALL enemies. \(baseDamage)+hits Physical each."
        case .manaBolt: return "Focus single target. \(baseDamage)+hits Physical."
        case .shock:    return "Stun single target. \(baseDamage)+hits Stun."
        case .heal:     return "Restore HP & stun to a chosen ally."
        }
    }

    var isAreaOfEffect: Bool { self == .fireball }
    var isStunDamage: Bool   { self == .shock }
    var isHeal: Bool         { self == .heal }
    var needsEnemyTarget: Bool { self == .manaBolt || self == .shock }
}

enum ActionMode: String, CaseIterable {
    case street
    case signal
}

enum MissionPreset: String, CaseIterable {
    case lowPressure
    case standard
    case highPressure
}

enum PlayerRole: String, CaseIterable {
    case normal
    case hacker
    case street
}

enum MissionType {
    case stealth
    case assault
    case extraction
}

/// Additive Stage-1 state machine axis.
/// Legacy booleans remain for compatibility during migration.
enum CombatPhase {
    case idle
    case playerInput
    case playerResolving
    case enemyResolving
    case extractRequested
    case combatResolved
    case rewarding
    case complete
}

/// Additive Stage-1 outcome axis.
/// Legacy booleans remain for compatibility during migration.
enum CombatOutcome {
    case none
    case victory
    case defeat
    case extracted
}

enum EnemyArchetype {
    case watcher
    case enforcer
    case interceptor
}

enum MapSituation {
    case corridor
    case openZone
    case chokepoint
}

enum HeatTier {
    case low
    case medium
    case high
}

enum Faction: String, Hashable {
    case corp
    case gang
    case unknown
}

// MARK: - Singleton combat/game runtime state

/// Singleton combat/game runtime state — accessible across all layers.
@MainActor
final class GameState: ObservableObject {

    static let shared = GameState()
    var sessionState = GameSessionState()

    private init() {}

    private enum TraceCadence {
        static let gainPerSignal = 1
        static let recoveryPerLayLow = 1
        static func threshold(for preset: MissionPreset) -> Int {
            switch preset {
            case .lowPressure: return 5
            case .standard: return 4
            case .highPressure: return 3
            }
        }
        static func escalationDamageBonus(for preset: MissionPreset) -> Int {
            switch preset {
            case .lowPressure: return 1
            case .standard: return 1
            case .highPressure: return 1
            }
        }
    }

    // MARK: - Team

    @Published var playerTeam: [Character] = []
    @Published var enemies: [Enemy] = []

    /// Transient warning banner text (set by BattleScene when player tries to
    /// leave a room without hacking a required terminal, etc.). Auto-clears
    /// after ~3s — SwiftUI overlay observes and renders. nil = no banner.
    @Published var transientWarning: String? = nil

    /// Posts a transient warning and schedules an auto-clear after `duration`s.
    /// Re-firing while a previous warning is active replaces its text and
    /// resets the timer (no stacking).
    func postTransientWarning(_ text: String, duration: TimeInterval = 3.0) {
        transientWarning = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            // Only clear if it's still the same warning — a newer warning may
            // have overwritten it in the meantime, and we'd be cutting its
            // own timer short otherwise.
            if self.transientWarning == text { self.transientWarning = nil }
        }
    }

    // MARK: - Inventory / Loot

    /// Unequipped items available to the team
    @Published var loot: [Item] = []

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let type: ItemType
        let bonus: Int  // HP heal, armor value, or tactical item base damage

        enum ItemType: String {
            case consumable  // medkit
            case weapon
            case armor
            case grenade     // tactical throwable
        }
    }

    private let lootTable: [(type: Item.ItemType, chance: Double, name: String, bonus: Int)] = [
        (.consumable, 0.6, "Medkit", 10),
        (.consumable, 0.3, "Stimpatch", 5),
        (.consumable, 0.25, "Mana Focus", 6),  // restores mana for the mage
        (.consumable, 0.22, "Frag Grenade", 7),
        (.weapon, 0.2, "Combat Knife +1", 1),
        (.weapon, 0.1, "Heavy Pistol", 2),
        (.armor, 0.15, "Armored Vest", 2),
        (.armor, 0.1, "Shield", 3),
    ]

    func generateLoot() {
        let drop = lootTable.randomElement()!
        loot.append(Item(name: drop.name, type: drop.type, bonus: drop.bonus))
        addLog("Loot: \(drop.name)!")
    }

    // MARK: - Turn

    @Published var currentTurnIndex: Int = 0
    @Published var roundNumber: Int = 1
    var enemyPhaseCount: Int {  // how many enemy phases have completed (for delayed spawns)
        get { sessionState.enemyPhaseCount }
        set { sessionState.enemyPhaseCount = newValue }
    }
    @Published var isPlayerTurn: Bool = true
    /// When true, blocks player input in BattleScene while enemy phase is running.
    @Published var isPlayerInputBlocked: Bool = false
    /// Stage-1 additive migration layer. Owned by CombatFlowController writes only.
    @Published var combatPhase: CombatPhase = .idle
    /// Stage-1 additive migration layer. Owned by CombatFlowController writes only.
    @Published var combatOutcome: CombatOutcome = .none
    /// Guards against double-triggering enemyPhase() within the same frame/turn.
    var isEnemyPhaseRunning: Bool {
        get { sessionState.isEnemyPhaseRunning }
        set { sessionState.isEnemyPhaseRunning = newValue }
    }
    @Published var actionMode: ActionMode = .street
    @Published var playerRole: PlayerRole = .normal
    @Published var selectedMissionPreset: MissionPreset = .standard
    @Published var traceLevel: Int = 0
    var traceThreshold: Int { TraceCadence.threshold(for: selectedMissionPreset) }
    var traceGainPerSignal: Int { TraceCadence.gainPerSignal }
    var traceRecoveryPerLayLow: Int { TraceCadence.recoveryPerLayLow }
    var escalationDamageBonus: Int { TraceCadence.escalationDamageBonus(for: selectedMissionPreset) }
    @Published var traceEscalationLevel: Int = 0
    var hasLoggedTraceTriggerForCurrentRun: Bool {
        get { sessionState.hasLoggedTraceTriggerForCurrentRun }
        set { sessionState.hasLoggedTraceTriggerForCurrentRun = newValue }
    }

    // MARK: - Turn Structure (Issue 1 fix)
    // Track which players have NOT yet acted this round. Empty = all acted = enemy phase.
    var playersWhoHaveNotActed: Set<UUID> {
        get { sessionState.playersWhoHaveNotActed }
        set { sessionState.playersWhoHaveNotActed = newValue }
    }

    /// Per-character movement tracking: if true, character has already moved this turn
    /// and cannot take a major action (attack/defend/cast/item) in the same turn.
    /// Reset at start of each round alongside hasActedThisRound.
    var characterHasMovedThisTurn: [UUID: Bool] {
        get { sessionState.characterHasMovedThisTurn }
        set { sessionState.characterHasMovedThisTurn = newValue }
    }

    /// Number of player turns completed in the current player cycle.
    /// Enemy phase begins after 4 player turns or once all living players have acted.
    var playerTurnsCompleted: Int {
        get { sessionState.playerTurnsCompleted }
        set { sessionState.playerTurnsCompleted = newValue }
    }

    /// True when any living player has HP <= 0 (player death occurred).
    /// Used to block room transitions after player death.
    var playerIsDead: Bool {
        get { sessionState.playerIsDead }
        set { sessionState.playerIsDead = newValue }
    }

    /// Reset turn-tracking state at the start of each round.
    func resetTurnTracking() {
        CombatFlowController.resetTurnTracking(gameState: self)
    }

    var isTraceTriggered: Bool {
        traceLevel >= traceThreshold
    }

    /// Tier 0: below threshold (low), Tier 1: triggered (medium), Tier 2: high pressure.
    /// Deterministic and fully derived from existing trace values.
    var traceTier: Int {
        ConsequenceEngine.traceTier(traceLevel: traceLevel, traceThreshold: traceThreshold)
    }

    var traceTierLabel: String {
        switch traceTier {
        case 2: return "HIGH"
        case 1: return "MED"
        default: return "LOW"
        }
    }

    /// Enemy incoming damage modifier derived from trace tier.
    /// Tier 0 = +0, Tier 1 = +base, Tier 2 = +(base + 1)
    var escalationDamageBonusForCurrentTrace: Int {
        switch traceTier {
        case 2:
            return escalationDamageBonus + 1
        case 1:
            return escalationDamageBonus
        default:
            return 0
        }
    }

    func applyStreetAction() {
        // Explicitly no trace mutation.
    }

    func applySignalAction() {
        let previousTier = traceTier
        addLog("TRACE +\(traceGainPerSignal) (Signal)")
        traceLevel += traceGainPerSignal
        if !isTraceTriggered && traceLevel == traceThreshold - 1 {
            addLog("TRACE WARNING — near escalation")
        }
        if isTraceTriggered && !hasLoggedTraceTriggerForCurrentRun {
            hasLoggedTraceTriggerForCurrentRun = true
            addLog("⚠️ TRACE TRIGGERED — hostile network awareness increased.")
        }
        let newTier = traceTier
        traceEscalationLevel = newTier
        if newTier != previousTier {
            addLog("⚠️ TRACE \(traceTierLabel) — enemy damage +\(escalationDamageBonusForCurrentTrace)")
        }
    }

    private func escalatedIncomingDamage(_ baseDamage: Int) -> Int {
        guard baseDamage > 0 else { return baseDamage }
        let dynamicBonus = escalationDamageBonusForCurrentTrace
        guard dynamicBonus > 0 else { return baseDamage }
        let escalatedDamage = baseDamage + dynamicBonus
        if playerRole == .street {
            addLog("STREET — bracing against escalation")
            let reducedDamage = max(0, escalatedDamage - 1)
            addLog("STREET — reduced incoming damage")
            return reducedDamage
        }
        return escalatedDamage
    }

    func applyTraceRecovery() {
        let previousTier = traceTier
        let recoveryAmount: Int
        if playerRole == .hacker {
            recoveryAmount = traceRecoveryPerLayLow + 1
            addLog("HACKER — enhanced trace recovery")
        } else {
            recoveryAmount = traceRecoveryPerLayLow
        }
        let previous = traceLevel
        traceLevel = max(0, traceLevel - recoveryAmount)
        if traceLevel < previous {
            addLog("TRACE -\(previous - traceLevel) (Lay Low)")
        } else {
            addLog("TRACE -0 (Lay Low)")
        }
        let newTier = traceTier
        traceEscalationLevel = newTier
        if newTier != previousTier {
            addLog("TRACE \(traceTierLabel) — enemy damage +\(escalationDamageBonusForCurrentTrace)")
        }
    }

    func traceTelemetrySummary() -> String {
        "trace=\(traceLevel)/\(traceThreshold) escalated=\(traceEscalationLevel >= 1) mode=\(actionMode.rawValue) role=\(playerRole.rawValue)"
    }

    var playerRoleLabel: String {
        switch playerRole {
        case .normal: return "NORMAL"
        case .hacker: return "HACKER"
        case .street: return "STREET"
        }
    }

    var missionPresetLabel: String {
        switch selectedMissionPreset {
        case .lowPressure: return "LOW"
        case .standard: return "STANDARD"
        case .highPressure: return "HIGH"
        }
    }

    var missionTypeLabel: String {
        switch currentMissionType {
        case .stealth: return "STEALTH"
        case .assault: return "ASSAULT"
        case .extraction: return "EXTRACTION"
        }
    }

    var missionTypeHint: String {
        switch currentMissionType {
        case .stealth: return "Stay low profile for bonus"
        case .assault: return "High intensity yields bonus"
        case .extraction: return "Balanced approach rewarded"
        }
    }

    var mapSituationLabel: String {
        switch currentMapSituation {
        case .corridor: return "CORRIDOR"
        case .openZone: return "OPEN ZONE"
        case .chokepoint: return "CHOKEPOINT"
        }
    }

    func cyclePlayerRole() {
        switch playerRole {
        case .normal:
            playerRole = .hacker
        case .hacker:
            playerRole = .street
        case .street:
            playerRole = .normal
        }

        addLog("ROLE SET — \(playerRoleLabel)")
    }

    func cycleMissionPreset() {
        switch selectedMissionPreset {
        case .lowPressure:
            selectedMissionPreset = .standard
        case .standard:
            selectedMissionPreset = .highPressure
        case .highPressure:
            selectedMissionPreset = .lowPressure
        }

        addLog("PRESET SET — \(missionPresetLabel)")
    }

    func cycleMissionType() {
        switch currentMissionType {
        case .stealth:
            currentMissionType = .assault
        case .assault:
            currentMissionType = .extraction
        case .extraction:
            currentMissionType = .stealth
        }

        addLog("MISSION TYPE — \(missionTypeLabel)")
    }

    /// Call at the START of each round (before first player acts).
    func beginRound() {
        CombatFlowController.beginRound(gameState: self)
    }

    /// SR5 stun recovery: at the start of each round, each living character rolls BOD+WIL.
    /// Each hit reduces stun by 1 (simplified from real SR5 rest-based recovery).
    func recoverStunAtRoundStart() {
        CombatFlowController.recoverStunAtRoundStart(gameState: self)
    }

    // MARK: - Current Mission Tiles (for enemy pathfinding)

    var currentMissionTiles: [[Int]] {
        get { sessionState.currentMissionTiles }
        set { sessionState.currentMissionTiles = newValue }
    }

    /// True when the active mission/room has a data-terminal objective that must
    /// be hacked before extraction is allowed.
    var missionRequiresData: Bool {
        get { sessionState.missionRequiresData }
        set { sessionState.missionRequiresData = newValue }
    }

    var dataAcquired: Bool {
        get { sessionState.dataAcquired }
        set { sessionState.dataAcquired = newValue }
    }

    /// M3 grimoire pickup status — mirrors sessionState (see GameSessionState).
    var grimoireAcquired: Bool {
        get { sessionState.grimoireAcquired }
        set { sessionState.grimoireAcquired = newValue }
    }

    /// M3 boss-phase-2 trigger flag — mirrors sessionState.
    var mageBossPhase2Triggered: Bool {
        get { sessionState.mageBossPhase2Triggered }
        set { sessionState.mageBossPhase2Triggered = newValue }
    }
    /// M3 boss-phase-2 deferred-spawn flag — see GameSessionState.
    var mageBossPhase2Pending: Bool {
        get { sessionState.mageBossPhase2Pending }
        set { sessionState.mageBossPhase2Pending = newValue }
    }
    var mageBossPendingSpawnX: Int {
        get { sessionState.mageBossPendingSpawnX }
        set { sessionState.mageBossPendingSpawnX = newValue }
    }
    var mageBossPendingSpawnY: Int {
        get { sessionState.mageBossPendingSpawnY }
        set { sessionState.mageBossPendingSpawnY = newValue }
    }

    /// Total kills across all rooms in the current mission.
    var missionEnemiesDefeated: Int {
        get { sessionState.missionEnemiesDefeated }
        set { sessionState.missionEnemiesDefeated = newValue }
    }

    /// Has the first kill in the current room been processed (for barrier drops)?
    /// Reset on room transition.
    var firstKillProcessedInRoom: Bool {
        get { sessionState.firstKillProcessedInRoom }
        set { sessionState.firstKillProcessedInRoom = newValue }
    }

    var extractionAnimationInProgress: Bool {
        get { sessionState.extractionAnimationInProgress }
        set { sessionState.extractionAnimationInProgress = newValue }
    }

    var intimidationOriginalAgi: [UUID: Int] {
        get { sessionState.intimidationOriginalAgi }
        set { sessionState.intimidationOriginalAgi = newValue }
    }

    /// Drives the Matrix hacking mini-game overlay. SwiftUI binds to this so
    /// it must be @Published directly on GameState (forwarded to sessionState
    /// won't trigger view updates).
    @Published var showMatrixMiniGame: Bool = false
    var pendingHackTerminalX: Int {
        get { sessionState.pendingHackTerminalX }
        set { sessionState.pendingHackTerminalX = newValue }
    }
    var pendingHackTerminalY: Int {
        get { sessionState.pendingHackTerminalY }
        set { sessionState.pendingHackTerminalY = newValue }
    }
    var pendingHackCharacterId: UUID? {
        get { sessionState.pendingHackCharacterId }
        set { sessionState.pendingHackCharacterId = newValue }
    }

    /// Stable display id for the currently-loaded mission (e.g. "Mission001").
    /// Used by OutcomePipeline to record the run's score under the right key.
    var currentMissionDisplayId: String? {
        get { sessionState.currentMissionDisplayId }
        set { sessionState.currentMissionDisplayId = newValue }
    }

    // MARK: - Pending Enemy Spawns

    /// Enemies not yet on the map (waiting for their delay timer)
    var pendingSpawns: [PendingSpawn] {
        get { sessionState.pendingSpawns }
        set { sessionState.pendingSpawns = newValue }
    }

    struct PendingSpawn: Identifiable {
        let id = UUID()
        let enemy: Enemy
        let delayRounds: Int  // spawn after N enemy phases have passed
    }

    /// Called after each enemy phase to check if any delayed enemies should spawn.
    /// enemyPhaseIndex = how many enemy phases have completed (0 = first enemy phase just ran).
    func processDelayedSpawns(enemyPhaseIndex: Int) {
        MissionSetupService.processDelayedSpawns(gameState: self, enemyPhaseIndex: enemyPhaseIndex)
    }

    // MARK: - Combat Log

    @Published var combatLog: [String] = []

    // MARK: - Room

    /// Current room ID — synced with BattleScene.currentRoomId during multi-room transitions.
    @Published var currentRoomId: String = "room_0"

    // MARK: - Selected

    /// The character that is actively taking actions (set by selection or turn order)
    @Published var activeCharacterId: UUID?

    @Published var selectedCharacterId: UUID?
    @Published var targetCharacterId: UUID?
    var combatWon: Bool? {
        get { sessionState.combatWon }
        set {
            objectWillChange.send()
            sessionState.combatWon = newValue
        }
    }
    @Published var combatEnded: Bool = false
    @Published var currentMissionType: MissionType = .stealth
    var currentMapSituation: MapSituation {
        get { sessionState.currentMapSituation }
        set {
            objectWillChange.send()
            sessionState.currentMapSituation = newValue
        }
    }
    @Published var missionComplete: Bool = false
    var missionHeat: Int {
        get { sessionState.missionHeat }
        set {
            objectWillChange.send()
            sessionState.missionHeat = newValue
        }
    }
    var missionHeatTier: HeatTier {
        get { sessionState.missionHeatTier }
        set {
            objectWillChange.send()
            sessionState.missionHeatTier = newValue
        }
    }
    @Published var factionAttention: [Faction: Int] = [
        .corp: 0,
        .gang: 0,
        .unknown: 0
    ]
    var lastAppliedCorpEnemyModifier: Int {
        get { sessionState.lastAppliedCorpEnemyModifier }
        set {
            objectWillChange.send()
            sessionState.lastAppliedCorpEnemyModifier = newValue
        }
    }
    var lastAppliedGangAmbushRadius: Int {
        get { sessionState.lastAppliedGangAmbushRadius }
        set {
            objectWillChange.send()
            sessionState.lastAppliedGangAmbushRadius = newValue
        }
    }
    var didApplyAttentionRecoveryLastMission: Bool {
        get { sessionState.didApplyAttentionRecoveryLastMission }
        set {
            objectWillChange.send()
            sessionState.didApplyAttentionRecoveryLastMission = newValue
        }
    }
    var didApplyHighTraceEscalationBonusLastMission: Bool {
        get { sessionState.didApplyHighTraceEscalationBonusLastMission }
        set {
            objectWillChange.send()
            sessionState.didApplyHighTraceEscalationBonusLastMission = newValue
        }
    }
    var lastRewardTier: RewardTier {
        get { sessionState.lastRewardTier }
        set {
            objectWillChange.send()
            sessionState.lastRewardTier = newValue
        }
    }
    var lastRewardMultiplier: Double {
        get { sessionState.lastRewardMultiplier }
        set {
            objectWillChange.send()
            sessionState.lastRewardMultiplier = newValue
        }
    }
    var missionTypeBonusMultiplier: Double {
        get { sessionState.missionTypeBonusMultiplier }
        set {
            objectWillChange.send()
            sessionState.missionTypeBonusMultiplier = newValue
        }
    }
    @Published var baseMissionPayout: Int = 100
    var missionTargetTurns: Int {
        get { sessionState.missionTargetTurns }
        set {
            objectWillChange.send()
            sessionState.missionTargetTurns = newValue
        }
    }
    var currentTurnCount: Int {
        get { sessionState.currentTurnCount }
        set {
            objectWillChange.send()
            sessionState.currentTurnCount = newValue
        }
    }
    var missionLoadIndex: Int {
        get { sessionState.missionLoadIndex }
        set { sessionState.missionLoadIndex = newValue }
    }
    var activeCharacter: Character? {
        guard let id = activeCharacterId else { return currentCharacter }
        return playerTeam.first(where: { $0.id == id && $0.isAlive })
    }

    // MARK: - Actions

    @Published var isDefending: Bool = false
    var isItemMenuVisible: Bool {
        get { sessionState.isItemMenuVisible }
        set {
            objectWillChange.send()
            sessionState.isItemMenuVisible = newValue
        }
    }

    /// Which character is currently defending (for turn-scoped defense bonus)
    var defendingCharacterId: UUID? {
        get { sessionState.defendingCharacterId }
        set { sessionState.defendingCharacterId = newValue }
    }

    /// Active overwatch entries: characterId → attack pool snapshot.
    /// Cleared at the start of each round (resetTurnTracking).
    @Published var overwatchers: [UUID: Int] = [:]

    // MARK: - Computed

    var currentCharacter: Character? {
        guard isPlayerInputPhase, !playerTeam.isEmpty else { return nil }
        // Find first living player at or after currentTurnIndex
        for i in currentTurnIndex..<playerTeam.count {
            if playerTeam[i].isAlive { return playerTeam[i] }
        }
        // Wrap around
        for i in 0..<currentTurnIndex {
            if playerTeam[i].isAlive { return playerTeam[i] }
        }
        return nil
    }

    var livingPlayers: [Character] { playerTeam.filter { $0.isAlive } }
    var livingEnemies: [Enemy] { enemies.filter { $0.isAlive } }

    var isCombatOver: Bool {
        livingPlayers.isEmpty || livingEnemies.isEmpty
    }

    var playerTeamWon: Bool {
        isCombatOver && !livingPlayers.isEmpty && livingEnemies.isEmpty
    }

    /// Compatibility accessor — prefer phase/outcome, legacy fallback retained temporarily.
    var isPlayerInputPhase: Bool {
        (combatPhase == .playerInput) || isPlayerTurn
    }

    /// Compatibility accessor — prefer phase/outcome, legacy fallback retained temporarily.
    var isInputBlockedByPhase: Bool {
        (combatPhase != .playerInput) || isPlayerInputBlocked
    }

    /// Compatibility accessor — prefer phase/outcome, legacy fallback retained temporarily.
    var isCombatResolvedOrBeyond: Bool {
        (combatPhase == .combatResolved || combatPhase == .rewarding || combatPhase == .complete) || combatEnded
    }

    /// Compatibility accessor — prefer phase/outcome, legacy fallback retained temporarily.
    var isCombatVictoryLike: Bool {
        if combatOutcome == .victory || combatOutcome == .extracted {
            return true
        }
        if combatOutcome == .defeat {
            return false
        }
        return combatWon ?? false
    }

    /// Compatibility accessor — prefer phase/outcome, legacy fallback retained temporarily.
    var isMissionCompleteCompat: Bool {
        (combatPhase == .complete) || missionComplete
    }

    /// Read-only diagnostics summary for turn authority mapping.
    /// Non-authoritative: intended for UI/debug overlays and documentation only.
    var turnAuthoritySummary: String {
        let activeId = (activeCharacter ?? currentCharacter)?.id.uuidString.prefix(8) ?? "n/a"
        return "owner=GameState idx=\(currentTurnIndex) round=\(roundNumber) playerTurn=\(isPlayerTurn) inputBlocked=\(isPlayerInputBlocked) active=\(activeId)"
    }

    var heatTierLabel: String {
        ConsequenceEngine.heatTierLabel(for: missionHeatTier)
    }

    func generateWorldReactionMessage() -> String {
        OutcomePipeline.generateWorldReactionMessage(gameState: self)
    }

    func generateMissionModifierPreview() -> String {
        OutcomePipeline.generateMissionModifierPreview(gameState: self)
    }

    func generateGangReactionMessage() -> String {
        OutcomePipeline.generateGangReactionMessage(gameState: self)
    }

    func generateGangMissionPreview() -> String {
        OutcomePipeline.generateGangMissionPreview(gameState: self)
    }

    func generateCombinedPressurePreview() -> String {
        OutcomePipeline.generateCombinedPressurePreview(gameState: self)
    }

    func rewardTierLabel(_ tier: RewardTier) -> String {
        OutcomePipeline.rewardTierLabel(tier)
    }

    func generateRewardPreview() -> String {
        OutcomePipeline.generateRewardPreview(gameState: self)
    }

    var finalMissionPayout: Int {
        Int(Double(baseMissionPayout) * finalRewardMultiplier)
    }

    var finalRewardMultiplier: Double {
        lastRewardMultiplier + missionTypeBonusMultiplier
    }

    var riskBonus: Int {
        finalMissionPayout - baseMissionPayout
    }

    func generateRewardPayoutSummary() -> String {
        OutcomePipeline.generateRewardPayoutSummary(gameState: self)
    }

    func assignMissionTypeForCurrentLoad() {
        MissionSetupService.assignMissionTypeForCurrentLoad(gameState: self)
    }

    func tileKey(x: Int, y: Int) -> String {
        MissionSetupService.tileKey(gameState: self, x: x, y: y)
    }

    func applyMapSituation(
        to originalMap: [[Int]],
        extractionPoint: (x: Int, y: Int),
        protectedTiles: Set<String>
    ) -> ([[Int]], (x: Int, y: Int)) {
        MissionSetupService.applyMapSituation(
            gameState: self,
            to: originalMap,
            extractionPoint: extractionPoint,
            protectedTiles: protectedTiles
        )
    }

    var currentMissionTilesSnapshot: [[Int]] {
        currentMissionTiles
    }

    func generateMissionEndSummary() -> String {
        OutcomePipeline.generateMissionEndSummary(gameState: self)
    }

    func generateMissionBriefing() -> String {
        let corpAttention = factionAttention[.corp, default: 0]
        let gangAttention = factionAttention[.gang, default: 0]

        let objectiveText: String
        switch currentMissionType {
        case .stealth:
            objectiveText = "Avoid detection and complete the run cleanly."
        case .assault:
            objectiveText = "Push through resistance and secure the objective."
        case .extraction:
            objectiveText = "Maintain momentum and reach extraction safely."
        }

        let expectedThreats: String
        switch currentMissionType {
        case .stealth:
            expectedThreats = "Watchers present. Detection risk high."
        case .assault:
            expectedThreats = "Enforcers present. Direct combat expected."
        case .extraction:
            expectedThreats = "Interceptors present. Movement pressure expected."
        }

        let attentionTotal = corpAttention + gangAttention
        let pressureProfile: String
        switch attentionTotal {
        case 0...2:
            pressureProfile = "Low pressure expected."
        case 3...5:
            pressureProfile = "Moderate escalation likely."
        default:
            pressureProfile = "High escalation risk."
        }

        let rewardProfile: String
        switch currentMissionType {
        case .stealth:
            rewardProfile = "Low trace yields bonus."
        case .assault:
            rewardProfile = "High intensity yields bonus."
        case .extraction:
            rewardProfile = "Balanced approach yields bonus."
        }

        // Prepend story briefing text from mission JSON if available
        let storyBriefing = briefingText.map { "\($0)\n\n" } ?? ""

        return """
        \(storyBriefing)
        ------------------------

        MISSION BRIEFING

        TYPE:
        \(missionTypeLabel)

        OBJECTIVE:
        \(objectiveText)
        \(missionTypeHint)

        EXPECTED THREATS:
        \(expectedThreats)

        PRESSURE PROFILE:
        \(pressureProfile)

        REWARD PROFILE:
        \(rewardProfile)
        \(generateRewardPreview())

        WORLD STATE:
        Corp Attention: \(corpAttention)
        Gang Attention: \(gangAttention)
        \(generateCombinedPressurePreview())

        ------------------------
        """
    }

    func corpAttentionEnemyModifier() -> Int {
        let corpAttention = factionAttention[.corp, default: 0]
        return ConsequenceEngine.corpEnemyModifier(corpAttention: corpAttention)
    }

    /// Live hit-preview for the currently selected attacker → target pair.
    /// Returns nil if no valid attacker or target is selected.
    var hitPreview: CombatMechanics.HitPreview? {
        attackPreview
    }

    var attackPreview: CombatMechanics.HitPreview? {
        guard let attacker = activeCharacter ?? currentCharacter,
              let target = previewTarget(for: attacker) else { return nil }
        let weapon = attacker.equippedWeapon ?? Weapon(name: "Fists", type: .unarmed, damage: 3, accuracy: 3, armorPiercing: 0)
        if (attacker.archetype == .streetSam || attacker.archetype == .decker),
           (weapon.type == .blade || weapon.type == .unarmed),
           hexDistance(x1: attacker.positionX, y1: attacker.positionY,
                       x2: target.positionX, y2: target.positionY) > 1 {
            return CombatMechanics.HitPreview(
                actionLabel: "ATK",
                weaponName: weapon.name,
                targetName: target.name,
                attackPool: 0,
                defensePool: 0,
                coverBonus: 0,
                estimatedHitChance: 0,
                weaponDamage: weapon.damage,
                estimatedDamage: 0,
                blocked: true,
                reason: "Move adjacent first"
            )
        }
        return CombatMechanics.computeHitPreview(
            attacker:  attacker,
            target:    target,
            tiles:     currentMissionTiles,
            weapon:    weapon,
            actionLabel: "ATK",
            isBlocked: { sx, sy, tx, ty in
                self.isLineBlockedByWall(fromX: sx, fromY: sy, toX: tx, toY: ty)
            }
        )
    }

    var shootPreview: CombatMechanics.HitPreview? {
        guard let attacker = activeCharacter ?? currentCharacter,
              attacker.archetype != .streetSam,
              let target = previewTarget(for: attacker) else { return nil }
        let sidearm: Weapon
        switch attacker.archetype {
        case .decker:
            sidearm = Weapon(name: "Smartgun Pistol", type: .pistol, damage: 5, accuracy: 5, armorPiercing: 1)
        default:
            sidearm = Weapon(name: "Sidearm", type: .pistol, damage: 4, accuracy: 4, armorPiercing: 1)
        }
        return CombatMechanics.computeHitPreview(
            attacker: attacker,
            target: target,
            tiles: currentMissionTiles,
            weapon: sidearm,
            actionLabel: "SHT",
            isBlocked: { sx, sy, tx, ty in
                self.isLineBlockedByWall(fromX: sx, fromY: sy, toX: tx, toY: ty)
            }
        )
    }

    private func previewTarget(for attacker: Character) -> Enemy? {
        if let targetId = targetCharacterId,
           let selected = enemies.first(where: { $0.id == targetId && $0.isAlive }) {
            return selected
        }
        return livingEnemies
            .map { ($0, hexDistance(x1: attacker.positionX, y1: attacker.positionY, x2: $0.positionX, y2: $0.positionY)) }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    // MARK: - Setup

    private func archetypeLabel(_ archetype: EnemyArchetype) -> String {
        switch archetype {
        case .watcher: return "Watcher"
        case .enforcer: return "Enforcer"
        case .interceptor: return "Interceptor"
        }
    }

    func archetypeForSpawnIndex(_ spawnIndex: Int) -> EnemyArchetype {
        MissionSetupService.archetypeForSpawnIndex(gameState: self, spawnIndex: spawnIndex)
    }

    func applyEnemyArchetype(_ archetype: EnemyArchetype, to enemy: Enemy) {
        MissionSetupService.applyEnemyArchetype(gameState: self, archetype: archetype, to: enemy)
    }

    func makeEnemy(for type: String, archetype: EnemyArchetype) -> Enemy {
        MissionSetupService.makeEnemy(gameState: self, for: type, archetype: archetype)
    }

    func logEnemyComposition(totalSpawnCount: Int) {
        MissionSetupService.logEnemyComposition(gameState: self, totalSpawnCount: totalSpawnCount)
    }

    func applyCorpAttentionEnemyInfluence(spawnTemplates: [(type: String, x: Int, y: Int)], map: [[Int]]) {
        MissionSetupService.applyCorpAttentionEnemyInfluence(gameState: self, spawnTemplates: spawnTemplates, map: map)
    }

    func distanceToNearestPlayer(x: Int, y: Int) -> Int {
        PathingAndAIHelpers.distanceToNearestPlayer(gameState: self, x: x, y: y)
    }

    func applyGangAmbushBias(map: [[Int]]) {
        MissionSetupService.applyGangAmbushBias(gameState: self, map: map)
    }

    func setupMission(_ mission: Mission) {
        MissionSetupService.setupMission(gameState: self, mission: mission)
    }

    @discardableResult
    func prepareMissionForCombat(named missionId: String?) -> String {
        MissionSetupService.prepareMissionForCombat(gameState: self, missionId: missionId)
    }

    /// Setup a multi-room mission.
    /// Update tiles for enemy pathfinding (called when a room transition completes).
    func updateTilesForCurrentRoom(_ tiles: [[Int]]) {
        MissionSetupService.updateTilesForCurrentRoom(gameState: self, tiles: tiles)
    }

    func setupMultiRoomMission(_ mission: MultiRoomMission) {
        MissionSetupService.setupMultiRoomMission(gameState: self, mission: mission)
    }

    // MARK: - Actions

    func performAttack() {
        CombatFlowController.performAttack(gameState: self)
    }

    func performShoot() {
        CombatFlowController.performShoot(gameState: self)
    }

    func performLayLow() {
        CombatFlowController.performLayLow(gameState: self)
    }

    // MARK: - Spell Casting

    /// Entry point called from SpellPickerSheet. Validates mage & mana, then dispatches.
    func performSpell(type: SpellType, targetId: UUID? = nil) {
        CombatFlowController.performSpell(gameState: self, type: type, targetId: targetId)
    }

    // MARK: Fireball — AoE Physical

    func castFireball(by mage: Character) {
        let targets = livingEnemies
        guard !targets.isEmpty else { addLog("No targets."); return }

        let spellPool = mage.attributes.log + mage.skills.spellcasting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= SpellType.fireball.manaCost
        HapticsManager.shared.attackHit()

        // Glitch handling
        if spellRoll.criticalGlitch {
            let drain = mage.attributes.wil * 2
            mage.takeDamage(amount: drain)
            addLog("💥 CRIT GLITCH! FIREBALL backfires! \(mage.name) takes \(drain) drain!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": mage.id.uuidString, "damage": drain])
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
            completeAction(for: mage)
            return
        }
        if spellRoll.glitch || spellRoll.hits == 0 {
            let drain = mage.attributes.wil
            mage.takeDamage(amount: drain)
            addLog("⚠️ GLITCH! FIREBALL fizzles. \(mage.name) takes \(drain) drain!")
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
            completeAction(for: mage)
            return
        }

        addLog("🔥 \(mage.name) FIREBALL! [\(spellPool)d6→\(spellRoll.hits) hits] hits ALL \(targets.count) enemies!")
        for target in targets {
            let baseDamage = SpellType.fireball.baseDamage + spellRoll.hits
            let soakPool = target.attributes.wil + (target.equippedArmor?.armorValue ?? 0) / 2
            let soakRoll = DiceEngine.roll(pool: max(0, soakPool))
            let finalDamage = max(1, baseDamage - soakRoll.hits)
            target.takeDamage(amount: finalDamage, isStun: false)
            // Burning: 2 rounds, 3 dmg/round
            target.statusEffects.append(.burning(roundsLeft: 2))
            addLog("  → \(target.name): \(baseDamage)P - \(soakRoll.hits)soak = \(finalDamage) dmg (\(target.currentHP)/\(target.maxHP) HP)")
            addLog("    🔥 BURNING for 2 rounds!")
            NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": finalDamage])
            // Visual: orange explosion on each enemy tile.
            NotificationCenter.default.post(
                name: .fireballEffect, object: nil,
                userInfo: ["x": target.positionX, "y": target.positionY]
            )
            if !target.isAlive { handleEnemyKilled(target, by: mage) }
        }
        addLog("  Mana: \(mage.currentMana)/\(mage.maxMana)")
        if livingEnemies.isEmpty { onRoomCleared() }
        completeAction(for: mage)
    }

    // MARK: Mana Bolt & Shock — Single-target

    func castSingleTarget(type: SpellType, targetId: UUID?, by mage: Character) {
        // Resolve target: use provided id or nearest enemy
        let target: Enemy
        if let tid = targetId, let e = enemies.first(where: { $0.id == tid && $0.isAlive }) {
            target = e
        } else if let nearest = livingEnemies.first {
            target = nearest
            targetCharacterId = nearest.id
        } else {
            addLog("No targets in range."); return
        }

        let spellPool = mage.attributes.log + mage.skills.spellcasting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= type.manaCost
        HapticsManager.shared.attackHit()

        // Glitch handling
        if spellRoll.criticalGlitch {
            let drain = mage.attributes.wil * 2
            mage.takeDamage(amount: drain)
            addLog("💥 CRIT GLITCH! \(type.displayName) backfires! \(mage.name) takes \(drain) drain!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": mage.id.uuidString, "damage": drain])
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
            completeAction(for: mage)
            return
        }
        if spellRoll.glitch || spellRoll.hits == 0 {
            let drain = mage.attributes.wil
            mage.takeDamage(amount: drain)
            addLog("⚠️ GLITCH! \(type.displayName) fizzles. \(mage.name) takes \(drain) drain!")
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
            completeAction(for: mage)
            return
        }

        let baseDamage = type.baseDamage + spellRoll.hits
        let isStun = type.isStunDamage
        let soakPool = isStun
            ? max(0, target.attributes.wil)
            : max(0, target.attributes.wil + (target.equippedArmor?.armorValue ?? 0) / 2)
        let soakRoll = DiceEngine.roll(pool: soakPool)
        let finalDamage = max(1, baseDamage - soakRoll.hits)
        let dmgType = isStun ? "S" : "P"

        target.takeDamage(amount: finalDamage, isStun: isStun)
        let icon = type == .shock ? "⚡" : "✨"
        addLog("\(icon) \(mage.name) \(type.displayName.uppercased())! [\(spellPool)d6→\(spellRoll.hits) hits] \(baseDamage)\(dmgType) - \(soakRoll.hits)soak = \(finalDamage) dmg. (\(target.currentHP)/\(target.maxHP) HP | Stun \(target.currentStun)/\(target.maxStun))")
        addLog("  Mana: \(mage.currentMana)/\(mage.maxMana)")

        NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": finalDamage])
        // Visual: bolt from caster to target. Yellow zigzag for SHOCK,
        // purple straight bolt for MANABOLT.
        if type == .shock {
            NotificationCenter.default.post(
                name: .shockEffect, object: nil,
                userInfo: ["fromX": mage.positionX, "fromY": mage.positionY,
                           "toX": target.positionX, "toY": target.positionY]
            )
        } else {
            NotificationCenter.default.post(
                name: .boltEffect, object: nil,
                userInfo: ["fromX": mage.positionX, "fromY": mage.positionY,
                           "toX": target.positionX, "toY": target.positionY,
                           "color": "#AA66FF"]
            )
        }
        if !target.isAlive {
            handleEnemyKilled(target, by: mage)
            if livingEnemies.isEmpty { onRoomCleared() }
        }
        completeAction(for: mage)
    }

    // MARK: Heal

    /// Cast HEAL on a chosen ally (defaults to the mage if no target given).
    /// Heal can target ANY living party member, including the mage themselves.
    func castHeal(by mage: Character, targetId: UUID? = nil) {
        // Resolve the heal target. Prefer an explicit targetId (passed from
        // the UI's heal-target picker), else the currently-selected character
        // if it's a living ally, else the mage.
        //
        // 2026-05 — also handles the "I picked an ally but they died before
        // the spell resolved" case explicitly: if the requested target is
        // now dead, log it clearly so the player isn't confused about why
        // the heal landed on the wrong character. Refunds the mana so the
        // mage isn't penalised for the timing race.
        if let id = targetId,
           let intended = playerTeam.first(where: { $0.id == id }),
           !intended.isAlive {
            addLog("⚠️ \(intended.name) is down — heal cancelled (mana refunded). Use a Stim or revive ability if available.")
            return
        }
        let target: Character = {
            if let id = targetId,
               let c = playerTeam.first(where: { $0.id == id && $0.isAlive }) {
                return c
            }
            if let id = selectedCharacterId,
               let c = playerTeam.first(where: { $0.id == id && $0.isAlive }) {
                return c
            }
            return mage
        }()

        let spellPool = mage.attributes.log + mage.skills.spellcasting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= SpellType.heal.manaCost
        HapticsManager.shared.attackHit()

        if spellRoll.criticalGlitch {
            let drain = mage.attributes.wil * 2
            mage.takeDamage(amount: drain)
            addLog("💥 CRIT GLITCH! HEAL backfires! \(mage.name) takes \(drain) drain!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": mage.id.uuidString, "damage": drain])
            completeAction(for: mage)
            return
        }

        let healHP   = max(1, 2 + spellRoll.hits)
        let healStun = max(1, 1 + spellRoll.hits / 2)
        let prevHP = target.currentHP
        target.currentHP = min(target.maxHP, target.currentHP + healHP)
        target.recoverStun(amount: healStun)
        let actualHP = target.currentHP - prevHP
        let onSelf = (target.id == mage.id)
        let header = onSelf
            ? "💚 \(mage.name) HEAL (self)!"
            : "💚 \(mage.name) HEALs \(target.name)!"
        addLog("\(header) [\(spellPool)d6→\(spellRoll.hits) hits] +\(actualHP) HP, -\(healStun) Stun. (\(target.currentHP)/\(target.maxHP) HP | Stun \(target.currentStun)/\(target.maxStun))")
        addLog("  Mana: \(mage.currentMana)/\(mage.maxMana)")
        // Force SwiftUI re-render of the team panel — HPBar takes Int values
        // by-value, so a mutation on the Character object alone doesn't reach
        // GameState's observers without an explicit nudge.
        objectWillChange.send()
        NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": target.id.uuidString, "damage": -actualHP])
        // Visual: green particle bloom + "+N HP" floating text on the target.
        NotificationCenter.default.post(
            name: .healEffect, object: nil,
            userInfo: ["targetId": target.id.uuidString, "amount": actualHP]
        )
        completeAction(for: mage)
    }

    // MARK: Shared helper — award XP / loot when enemy killed by spell

    func handleEnemyKilled(_ enemy: Enemy, by mage: Character) {
        HapticsManager.shared.enemyKilled()
        missionEnemiesDefeated += 1
        CombatFlowController.handleEnemyKillForRoomEffects(gameState: self)
        addLog("☠️ \(enemy.name) DOWN! +\(enemy.maxHP / 2) XP")
        generateLoot()
        let leveledUp = mage.gainXP(enemy.maxHP / 2)
        if leveledUp {
            HapticsManager.shared.levelUp()
            addLog("🎖️ LEVEL UP! \(mage.name) → Level \(mage.level)!")
            NotificationCenter.default.post(name: .characterLevelUp, object: nil, userInfo: ["characterId": mage.id.uuidString])
        }
        NotificationCenter.default.post(name: .enemyDied, object: nil, userInfo: ["enemyId": enemy.id.uuidString])
        if livingEnemies.isEmpty { onRoomCleared() }
    }

    /// Spawn the room's designated boss enemy AFTER regular enemies are
    /// cleared. Plays the full reveal sequence (arrival horn + thud + radio
    /// + boss music swap) and suppresses any pending reinforcement waves so
    /// the boss is the focal threat. Marks `bossDeployedRoomIds[room]` so
    /// the next `onRoomCleared` call resolves normally.
    func deployBoss(_ boss: BossSpawn, in room: Room) {
        let enemy: Enemy
        switch boss.type {
        case "mech":    enemy = Enemy.bossMech()
        case "boss":    enemy = Enemy.bossMech()
        case "agi", "bossagi", "ai":  enemy = Enemy.bossAGI()
        default:        enemy = Enemy.bossMech()
        }
        enemy.positionX = boss.x
        enemy.positionY = boss.y
        // Name + archetype already set by the factory (MEKTON-7 / AGI-PRIME)
        // so SFX + sprite dispatch route correctly.

        // Mark deployed BEFORE adding to enemies, so the .enemySpawned
        // observer in BattleScene doesn't recurse into onRoomCleared early.
        RoomManager.shared.bossDeployedRoomIds.insert(room.id)

        // Suppress reinforcements for this room — boss fight is the focus.
        pendingSpawns.removeAll()

        // M5 Mech Bay: the wall cluster in the middle of the room is the
        // PARKED MEKTON-7 silhouette. When the real boss "wakes up" and spawns
        // at (3,9), the central decoration disappears — that mech IS the boss.
        // Convert those wall tiles to floor in the live grid and post
        // .barriersDropped so BattleScene re-renders the floor tiles.
        if enemy.archetype == "bossmech" && room.id == "room_2" {
            var tiles = currentMissionTiles
            // Cluster from Mission005_multi.json room_2 map:
            //   (2,6),(3,6),(4,6),(2,7),(3,7),(4,7),(3,8)
            let mechSilhouette: [(Int, Int)] = [
                (2, 6), (3, 6), (4, 6),
                (2, 7), (3, 7), (4, 7),
                (3, 8)
            ]
            var droppedCoords: [[String: Int]] = []
            for (x, y) in mechSilhouette {
                guard y >= 0, y < tiles.count, x >= 0, x < tiles[y].count else { continue }
                tiles[y][x] = TileType.floor.rawValue
                droppedCoords.append(["x": x, "y": y])
            }
            currentMissionTiles = tiles
            NotificationCenter.default.post(
                name: .barriersDropped, object: nil,
                userInfo: ["tiles": droppedCoords]
            )
        }

        enemies.append(enemy)
        addLog("⚠️  HEAVY UNIT DEPLOYED — \(enemy.name)")

        // Visual + audio reveal — fire each notification with userInfo so
        // the BattleScene observer can place sprite + run intro sequence.
        NotificationCenter.default.post(
            name: .enemySpawned, object: nil,
            userInfo: [
                "enemyId": enemy.id.uuidString,
                "isBoss": true
            ]
        )
        // Reveal SFX cluster — per-archetype. Mech gets the heavy
        // industrial horn + thud + radio sequence; AGI gets the glitchy
        // hack-intrusion stinger + a paced trace-warning pulse (until
        // dedicated AGI SFX files ship). All calls no-op if files missing.
        if enemy.archetype == "bossagi" {
            // AGI reveal sequence — three-stage cinematic:
            //   1. arrival_glitch: reality-tear
            //   2. manifestation: ringing emergence + heartbeat thud (~1.5s in)
            //   3. voice_mocking: corp-AGI taunt line (~3.0s in)
            SFXManager.shared.play("agi_arrival_glitch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                SFXManager.shared.play("agi_manifestation")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                SFXManager.shared.play("agi_voice_mocking")
            }
            // Chained boss music — "Intruder Protocol" → "Intruder Protocol 2"
            // alternating with a 3-second early handoff so the fade-out tail
            // of the first track is replaced by the crossfade into the second.
            MusicManager.shared.playBossChain(
                ["m6_boss_a", "m6_boss_b"],
                startOffset: 0,
                endTrimSeconds: 3.0
            )
        } else {
            SFXManager.shared.play("mech_arrival_horn")
            SFXManager.shared.play("mech_thud_landing")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                SFXManager.shared.play("mech_engagement_radio")
            }
            MusicManager.shared.playBossTrack(filename: "m5_boss", startOffset: 28)
        }

        HapticsManager.shared.playerKilled()  // strong shake for the entrance
        objectWillChange.send()
    }

    /// Death from a non-attributed source (burn DoT, environmental hazards).
    /// No XP awarded — no character "lands the kill" — but the death pipeline
    /// still runs so sprites despawn and the room-clear state advances.
    func handleEnemyKilledByEnvironment(_ enemy: Enemy) {
        HapticsManager.shared.enemyKilled()
        missionEnemiesDefeated += 1
        CombatFlowController.handleEnemyKillForRoomEffects(gameState: self)
        addLog("☠️ \(enemy.name) DOWN! (burned out)")
        generateLoot()
        NotificationCenter.default.post(name: .enemyDied, object: nil, userInfo: ["enemyId": enemy.id.uuidString])
        if livingEnemies.isEmpty { onRoomCleared() }
    }

    func performDefend() {
        CombatFlowController.performDefend(gameState: self)
    }

    @discardableResult
    func throwGrenade(item: Item, by runner: Character) -> Bool {
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: self, runner) else { return false }
        guard let targetId = targetCharacterId,
              let primary = enemies.first(where: { $0.id == targetId && $0.isAlive }) else {
            addLog("Select an enemy before throwing \(item.name).")
            HapticsManager.shared.buttonTap()
            return false
        }
        if isLineBlockedByWall(
            fromX: runner.positionX, fromY: runner.positionY,
            toX: primary.positionX, toY: primary.positionY
        ) {
            addLog("⛔ \(item.name) throw blocked by wall!")
            HapticsManager.shared.buttonTap()
            return false
        }

        switch actionMode {
        case .street: applyStreetAction()
        case .signal: applySignalAction()
        }

        let throwPool = max(1, runner.attributes.agi + max(1, runner.skills.firearms / 2) + runner.level)
        let throwRoll = DiceEngine.roll(pool: throwPool)
        HapticsManager.shared.attackHit()
        NotificationCenter.default.post(
            name: .fireballEffect,
            object: nil,
            userInfo: ["x": primary.positionX, "y": primary.positionY]
        )

        if throwRoll.criticalGlitch {
            let selfDamage = 4
            runner.takeDamage(amount: selfDamage)
            addLog("💥 CRIT GLITCH! \(runner.name)'s \(item.name) detonates early — \(selfDamage) dmg!")
            NotificationCenter.default.post(
                name: .characterHit,
                object: nil,
                userInfo: ["characterId": runner.id.uuidString, "damage": selfDamage]
            )
            completeAction(for: runner)
            return true
        }
        if throwRoll.glitch || throwRoll.hits == 0 {
            addLog("⚠️ \(runner.name) throws \(item.name) wide. [\(throwPool)d6→\(throwRoll.hits)]")
            completeAction(for: runner)
            return true
        }

        let blastTargets = enemies.filter { enemy in
            enemy.isAlive && hexDistance(
                x1: primary.positionX, y1: primary.positionY,
                x2: enemy.positionX, y2: enemy.positionY
            ) <= 1
        }

        addLog("💣 \(runner.name) throws \(item.name)! [\(throwPool)d6→\(throwRoll.hits)] \(blastTargets.count) target\(blastTargets.count == 1 ? "" : "s") in blast.")

        for enemy in blastTargets {
            let distance = hexDistance(
                x1: primary.positionX, y1: primary.positionY,
                x2: enemy.positionX, y2: enemy.positionY
            )
            let falloff = distance == 0 ? 0 : 2
            let baseDamage = max(1, item.bonus + throwRoll.hits - falloff)
            let soakPool = max(0, enemy.computeDerived().soak - 2)
            let soakRoll = DiceEngine.roll(pool: soakPool)
            let finalDamage = max(0, baseDamage - soakRoll.hits)
            enemy.takeDamage(amount: finalDamage, isStun: false)
            addLog("  → \(enemy.name): \(baseDamage)P AP-2 - \(soakRoll.hits) soak = \(finalDamage) dmg. (\(enemy.currentHP)/\(enemy.maxHP) HP)")
            NotificationCenter.default.post(
                name: .enemyHit,
                object: nil,
                userInfo: ["enemyId": enemy.id.uuidString, "damage": finalDamage]
            )
            if !enemy.isAlive {
                handleEnemyKilled(enemy, by: runner)
            }
        }

        if livingEnemies.isEmpty {
            onRoomCleared()
        }
        completeAction(for: runner)
        return true
    }

    /// Decker HACK: Disables target enemy for 1 round (0 attack dice, can't move).
    /// Uses LOG + spellcasting (hacking is logic-based in Shadowrun).
    func performHack() {
        CombatFlowController.performHack(gameState: self)
    }

    func performHackOnTarget(_ target: Enemy, by decker: Character) {
        // Hack pool: LOG + INT (matrix intrusion)
        let hackPool = decker.attributes.log + decker.attributes.int
        let hackRoll = DiceEngine.roll(pool: hackPool)

        decker.currentMana -= 2
        HapticsManager.shared.attackHit()

        if hackRoll.criticalGlitch {
            let drain = 4
            decker.takeDamage(amount: drain)
            addLog("💥 CRITICAL GLITCH! ICE counterattacks! \(decker.name) takes \(drain) dmg!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": decker.id.uuidString, "damage": drain])
            completeAction(for: decker)
            return
        }
        if hackRoll.glitch || hackRoll.hits == 0 {
            addLog("⚠️ GLITCH! \(decker.name)'s intrusion fails — ICE detected!")
            completeAction(for: decker)
            return
        }

        // Disable enemy: mark as stunned (use status effect)
        target.status = .stunned
        addLog("💻 \(decker.name) HACKS \(target.name)! [\(hackPool)d6→\(hackRoll.hits)] — SYSTEM DISABLED for 1 round!")
        NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": 0])
        // Visual: stream of binary glyphs from decker to target + circuit
        // breach flash on impact.
        NotificationCenter.default.post(
            name: .hackEffect, object: nil,
            userInfo: ["fromX": decker.positionX, "fromY": decker.positionY,
                       "toX": target.positionX, "toY": target.positionY,
                       "targetId": target.id.uuidString]
        )
        completeAction(for: decker)
    }

    /// Face INTIMIDATE: Reduce all living enemies' effective attack this round.
    /// Uses CHA + skills. All enemies get -2 dice to their next attack.
    func performIntimidate() {
        CombatFlowController.performIntimidate(gameState: self)
    }

    /// Street Sam BLITZ: High-damage melee charge attack. Uses BOD+STR.
    /// More powerful than normal attack but costs extra (BOD damage risk).
    func performBlitz() {
        CombatFlowController.performBlitz(gameState: self)
    }

    /// Apply Blitz damage to a single target. Does NOT advance the turn — the
    /// caller (`performBlitz`) does that ONCE after all adjacent targets are
    /// hit, so a multi-target sweep doesn't fire `completeAction` N times.
    func performBlitzOnTarget(_ target: Enemy, by sam: Character) {
        // Blitz pool: BOD + STR + blades skill (raw power charge)
        let blitzPool = sam.attributes.bod + sam.attributes.str + sam.skills.blades
        let attackRoll = DiceEngine.roll(pool: blitzPool)
        HapticsManager.shared.attackHit()

        if attackRoll.criticalGlitch {
            let selfDmg = 3
            sam.takeDamage(amount: selfDmg)
            addLog("💥 CRITICAL GLITCH! \(sam.name) stumbles — \(selfDmg) self-damage!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": sam.id.uuidString, "damage": selfDmg])
            return
        }

        // Hacked / stunned enemies can't dodge a Blitz — pool collapses to 0.
        let defensePool = (target.status == .stunned) ? 0 : max(1, target.attributes.rea)
        let defenseRoll = DiceEngine.roll(pool: defensePool)
        let netHits = max(0, attackRoll.hits - defenseRoll.hits)

        // Blitz deals high physical damage: base 8 + net hits
        let baseDmg = 8 + netHits
        let soakPool = max(0, target.computeDerived().soak - 2)  // -2 AP for charge force
        let soakRoll = DiceEngine.roll(pool: soakPool)
        let finalDmg = max(1, baseDmg - soakRoll.hits)

        target.takeDamage(amount: finalDmg, isStun: false)
        addLog("⚡ \(sam.name) BLITZ → \(target.name)! [\(blitzPool)d6→\(attackRoll.hits)] \(baseDmg)P - \(soakRoll.hits)soak = \(finalDmg) dmg! (\(target.currentHP)/\(target.maxHP))")
        NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": finalDmg])

        if !target.isAlive {
            HapticsManager.shared.enemyKilled()
            missionEnemiesDefeated += 1
            CombatFlowController.handleEnemyKillForRoomEffects(gameState: self)
            addLog("☠️ \(target.name) DOWN! +\(target.maxHP / 2) XP")
            generateLoot()
            let leveledUp = sam.gainXP(target.maxHP / 2)
            if leveledUp {
                HapticsManager.shared.levelUp()
                addLog("🎖️ LEVEL UP! \(sam.name) → Level \(sam.level)!")
                NotificationCenter.default.post(name: .characterLevelUp, object: nil, userInfo: ["characterId": sam.id.uuidString])
            }
            NotificationCenter.default.post(name: .enemyDied, object: nil, userInfo: ["enemyId": target.id.uuidString])
        }
    }

    /// Move a character to a new tile position (called from BattleScene on player tap).
    /// Movement is a FREE action — does NOT consume the turn.
    /// The player can still act (attack, defend, spell, item) after moving.
    func moveCharacter(id: UUID, toTileX tileX: Int, toTileY tileY: Int) {
        CombatFlowController.moveCharacter(gameState: self, id: id, toTileX: tileX, toTileY: tileY)
    }

    func showItemMenu() {
        CombatFlowController.showItemMenu(gameState: self)
    }

    func completeAction(for character: Character) {
        CombatFlowController.completeAction(gameState: self, for: character)
    }

    /// Enter overwatch: lock in the character's attack pool as a reaction trigger.
    /// Any enemy that moves into LOS of this character before their next turn
    /// will be automatically attacked (halved net hits — reaction fire penalty).
    func performOverwatch() {
        guard let a = activeCharacter ?? currentCharacter else { return }
        let ovwPool = a.attackPool(skill: .firearms)
        overwatchers[a.id] = ovwPool
        addLog("🎯 \(a.name) ENTERS OVERWATCH — holding fire on any movement.")
        NotificationCenter.default.post(name: .characterDefend, object: nil, userInfo: ["characterId": a.id.uuidString])
        completeAction(for: a)
    }

    /// Fire an overwatch shot at a moving enemy. Called from runEnemyAI just before
    /// each enemy movement step. Returns the number of shots fired (0 or 1 per overwatcher).
    func fireOverwatchShot(atEnemy enemy: Enemy, attackerId: UUID) -> Int {
        guard let ovwPool = overwatchers[attackerId] else { return 0 }
        // Only fire if enemy is in LOS with no wall blocking
        guard let attacker = playerTeam.first(where: { $0.id == attackerId }) else { return 0 }
        if isLineBlockedByWall(fromX: attacker.positionX, fromY: attacker.positionY,
                               toX: enemy.positionX, toY: enemy.positionY) { return 0 }
        // Fire the overwatch shot at the enemy's current position
        let weapon = attacker.equippedWeapon ?? Weapon(name: "Sidearm", type: .pistol, damage: 4, accuracy: 4, armorPiercing: 1)
        let attackRoll = DiceEngine.roll(pool: ovwPool)
        if attackRoll.criticalGlitch {
            addLog("💥 \(attacker.name) OVERWATCH fumble!")
            attacker.takeDamage(amount: 2)
            return 1
        }
        if attackRoll.glitch || attackRoll.hits == 0 {
            addLog("⚠️ \(attacker.name) OVERWATCH misses!")
            return 1
        }
        // Reaction fire: halved net hits (surprise penalty but not a full ambush)
        let defensePool = enemy.attributes.rea + enemy.attributes.agi
        let defenseRoll = DiceEngine.roll(pool: defensePool)
        let netHits = max(0, attackRoll.hits - defenseRoll.hits) / 2
        if netHits == 0 {
            addLog("→ \(attacker.name) OVERWATCH fires at \(enemy.name) — DODGED!")
            return 1
        }
        let baseDmg = weapon.damage + netHits
        let soakPool = max(0, enemy.computeDerived().soak - weapon.armorPiercing)
        let soakRoll = DiceEngine.roll(pool: soakPool)
        let finalDmg = max(0, baseDmg - soakRoll.hits)
        enemy.takeDamage(amount: finalDmg, isStun: weapon.isStunDamage)
        addLog("⚡ \(attacker.name) OVERWATCH → \(enemy.name)! \(netHits) net hits → \(finalDmg) dmg. (\(enemy.currentHP)/\(enemy.maxHP) HP)")
        NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": enemy.id.uuidString, "damage": finalDmg])
        if !enemy.isAlive {
            HapticsManager.shared.enemyKilled()
            missionEnemiesDefeated += 1
            CombatFlowController.handleEnemyKillForRoomEffects(gameState: self)
            addLog("☠️ \(enemy.name) DOWN from OVERWATCH!")
            NotificationCenter.default.post(name: .enemyDied, object: nil, userInfo: ["enemyId": enemy.id.uuidString])
        }
        return 1
    }

    func endTurn() {
        TurnManager.requestTurnAdvance(gameState: self)
    }

    /// Check if combat is over
    func checkCombatEnd() {
        CombatFlowController.checkCombatEnd(gameState: self)
    }

    /// Check if any living player is standing on the extraction tile with no enemies alive.
    /// If so, trigger extraction win immediately.
    func checkExtraction() {
        ExtractionController.checkExtraction(gameState: self)
    }

    /// Request extraction resolution through GameState authority.
    /// Callers should pass the selected living character id (if available) and tapped tile.
    /// CombatFlowController validates and adjudicates extraction outcome.
    func requestExtraction(characterId: UUID?, tileX: Int, tileY: Int) -> Bool {
        ExtractionController.requestExtraction(
            gameState: self,
            characterId: characterId,
            tileX: tileX,
            tileY: tileY
        )
    }

    /// Centralized mission outcome finalization.
    /// Ensures all victory/defeat paths mutate through GameState and emit one shared completion signal.
    private func finalizeCombat(won: Bool, missionLog: String, terminalLog: String? = nil) {
        OutcomePipeline.execute(
            gameState: self,
            won: won,
            missionLog: missionLog,
            terminalLog: terminalLog
        )
    }

    func finalizeCombatFromCombatFlow(won: Bool, missionLog: String, terminalLog: String? = nil) {
        finalizeCombat(won: won, missionLog: missionLog, terminalLog: terminalLog)
    }

    /// Mission's extraction point — set by setupMission from the mission JSON.
    var extractionX: Int {
        get { sessionState.extractionX }
        set { sessionState.extractionX = newValue }
    }
    var extractionY: Int {
        get { sessionState.extractionY }
        set { sessionState.extractionY = newValue }
    }

    /// Briefing text loaded from mission JSON (story/plot shown at mission start).
    var briefingText: String? {
        get { sessionState.missionBriefingText }
        set { sessionState.missionBriefingText = newValue }
    }

    /// Mission complete summary text loaded from mission JSON (shown on victory).
    var missionCompleteSummaryText: String? {
        get { sessionState.missionCompleteSummaryText }
        set { sessionState.missionCompleteSummaryText = newValue }
    }


    /// MULTI-ROOM PROGRESSION: called when livingEnemies becomes empty.
    func onRoomCleared() {
        guard livingEnemies.isEmpty else { return }

        // ── BOSS PHASE INTERCEPT ──────────────────────────────────────
        // If the current room defines a `bossSpawn` and we haven't deployed
        // the boss yet, spawn the boss instead of marking the room clear.
        // The boss becomes the "last enemy" — when they die, this method
        // re-fires (because livingEnemies will be empty again) and falls
        // through to normal clear since `bossDeployedRoomIds` is now set.
        if let room = RoomManager.shared.currentRoom,
           let boss = room.bossSpawn,
           !RoomManager.shared.bossDeployedRoomIds.contains(room.id),
           !RoomManager.shared.bossPendingRoomIds.contains(room.id) {
            // Suspense beat: let the player think the mission is over.
            // For the AGI boss, delay the actual manifestation by 2.5s
            // and show a "room cleared" message first. Mark `pending` so
            // a second onRoomCleared call during the delay window doesn't
            // re-enter and schedule a duplicate spawn. The mech boss still
            // drops immediately — his thing is the impact, not the wait.
            if boss.type == "agi" || boss.type == "bossagi" || boss.type == "ai" {
                RoomManager.shared.bossPendingRoomIds.insert(room.id)
                addLog("★ ROOM CLEARED ★")
                addLog("...the lights dim. Something is wrong.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self = self else { return }
                    RoomManager.shared.bossPendingRoomIds.remove(room.id)
                    self.deployBoss(boss, in: room)
                }
            } else {
                deployBoss(boss, in: room)
            }
            return
        }

        if RoomManager.shared.currentMission != nil {
            guard RoomManager.shared.markCurrentRoomCleared() else { return }
        }
        addLog("★ ROOM CLEARED ★")
        if RoomManager.shared.currentMission != nil {
            if RoomManager.shared.areAllRoomsCleared {
                addLog("All rooms cleared. Extraction point is active.")
            } else {
                addLog("Door unlocked — move to the next room.")
            }
        }
        NotificationCenter.default.post(name: .roomCleared, object: nil)
    }

    // MARK: - Per-Type Enemy AI
    /// Run all enemy AI actions asynchronously with staggered per-enemy dispatch.
    /// Posts .enemyPhaseCompleted notification ONLY after all animations have finished,
    /// so BattleScene can unblock player input at the right moment.
    func enemyPhase() {
        CombatFlowController.enemyPhase(gameState: self)
    }

    /// Execute a single enemy's full AI turn synchronously (move + attack).
    /// All notifications are posted synchronously here — animations are scheduled
    /// by BattleScene's observers and played by the SpriteKit run loop.
    func runEnemyAI(enemy: Enemy, livingEnemies: [Enemy]) {
        let livingPlayers = playerTeam.filter { $0.isAlive }
        guard !livingPlayers.isEmpty else { return }
        let enemyTurnStartX = enemy.positionX
        let enemyTurnStartY = enemy.positionY
        func enemyMovedThisTurn() -> Bool {
            enemy.positionX != enemyTurnStartX || enemy.positionY != enemyTurnStartY
        }

        // Stunned enemies skip their turn (Decker hack effect)
        if enemy.status == .stunned {
            addLog("⚡ \(enemy.name) is stunned — cannot act!")
            enemy.status = .wounded  // recover to wounded after 1 round
            return
        }

        switch enemy.archetype {

        case "drone":
            let closestPlayer = livingPlayers.min { a, b in
                let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                return distA < distB
            }!
            let dist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
            if dist >= 2 && dist <= 5 {
                // Reposition before firing so drones don't sit motionless on
                // identical tiles round after round. Pick a neighbor that
                // keeps the player in the optimal 2-5 band, preferring tiles
                // that move toward range 3 (centre of band) and have cover.
                if Double.random(in: 0...1) < 0.55 {
                    let candidates = PathingAndAIHelpers.hexNeighbors(gameState: self, x: enemy.positionX, y: enemy.positionY)
                        .filter { (nx, ny) in
                            PathingAndAIHelpers.tileWalkable(gameState: self, x: nx, y: ny, excluding: enemy.id)
                        }
                        .map { (nx, ny) -> (Int, Int, Int) in
                            let nd = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: nx, y2: ny)
                            // Score: prefer distance closer to 3, penalise leaving the band
                            let bandPenalty = (nd >= 2 && nd <= 5) ? 0 : 100
                            let centerDist = abs(nd - 3)
                            return (nx, ny, bandPenalty + centerDist)
                        }
                        .sorted { $0.2 < $1.2 }
                    if let pick = candidates.first, pick.2 < 100 {
                        // Overwatch check: before the enemy moves, fire at their START position
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = pick.0
                        enemy.positionY = pick.1
                        addLog("→ \(enemy.name) repositions")
                        NotificationCenter.default.post(name: .enemyMoved, object: nil, userInfo: ["enemyId": enemy.id.uuidString, "x": pick.0, "y": pick.1])
                    }
                }
                if enemyMovedThisTurn() { return }
                // Drones attack at optimal range 2–5 (extended from 2–3 to prevent stall states)
                let weaponAccuracy = enemy.equippedWeapon?.accuracy ?? 3
                let enemyAttackPool = enemy.attributes.agi + (weaponAccuracy / 2 + 1)

                // Player defense pool: REA + AGI + defend bonus + cover
                let defenseBonus = isCharacterDefending(closestPlayer.id) ? 3 : 0
                let enemyCoverCount = CombatMechanics.coverBetween(
                    tiles: currentMissionTiles,
                    fromX: enemy.positionX, fromY: enemy.positionY,
                    toX: closestPlayer.positionX, toY: closestPlayer.positionY
                )
                let playerCoverBonus = CombatMechanics.coverDefenseBonus(count: enemyCoverCount)
                let playerDefensePool = closestPlayer.attributes.rea + closestPlayer.attributes.agi + defenseBonus + playerCoverBonus

                let attackRoll = DiceEngine.roll(pool: enemyAttackPool)
                let defenseRoll = DiceEngine.roll(pool: playerDefensePool)
                let netHits = max(0, attackRoll.hits - defenseRoll.hits)

                if netHits == 0 {
                    addLog("→ \(enemy.name) attacks \(closestPlayer.name) — DODGED!")
                } else {
                    let weaponDmg = enemy.equippedWeapon?.damage ?? 4
                    let baseDmg = weaponDmg + netHits
                    let ap = enemy.equippedWeapon?.armorPiercing ?? 0
                    let soakPool = max(0, closestPlayer.computeDerived().soak - ap)
                    let soakRoll = DiceEngine.roll(pool: soakPool)
                    let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))

                    if dmg > 0 {
                        let isStun = enemy.equippedWeapon?.isStunDamage ?? false
                        closestPlayer.takeDamage(amount: dmg, isStun: isStun)
                        let dmgType = isStun ? "S" : "P"
                        HapticsManager.shared.playerDamaged()
                        addLog("⚠️ \(enemy.name) hits \(closestPlayer.name)! \(netHits) net hits → \(dmg)\(dmgType) dmg. (HP \(closestPlayer.currentHP)/\(closestPlayer.maxHP) | Stun \(closestPlayer.currentStun)/\(closestPlayer.maxStun))")
                        NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: ["playerId": closestPlayer.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString])
                        if !closestPlayer.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: closestPlayer) }
                    } else {
                        addLog("→ \(enemy.name) attacks — \(closestPlayer.name) soaks all damage!")
                    }
                }
            } else if dist < 2 {
                let (bx, by) = bestRetreatTile(for: enemy, awayFrom: closestPlayer)
                if let (rx, ry) = bfsPathfindDrone(from: enemy, towardX: bx, y: by) {
                    enemy.positionX = rx; enemy.positionY = ry
                    addLog("→ \(enemy.name) retreats")
                    NotificationCenter.default.post(name: .enemyMoved, object: nil, userInfo: ["enemyId": enemy.id.uuidString, "x": rx, "y": ry])
                }
            } else {
                // Multi-step move — collect path silently, post .enemyMoved
                // ONCE at the end so the visual animation doesn't restart
                // mid-flight on every step (caused the corpmage's
                // "walks-right-disappears-half-body" glitch).
                let drStartX = enemy.positionX, drStartY = enemy.positionY
                for _ in 0..<2 {
                    if let (nx, ny) = bfsPathfindDrone(from: enemy, towardX: closestPlayer.positionX, y: closestPlayer.positionY) {
                        // Overwatch: check before each step of multi-step movement
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = nx; enemy.positionY = ny
                        let newDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
                        if newDist >= 2 { break }
                    } else { break }
                }
                if enemy.positionX != drStartX || enemy.positionY != drStartY {
                    addLog("→ \(enemy.name) advances")
                    NotificationCenter.default.post(name: .enemyMoved, object: nil,
                        userInfo: ["enemyId": enemy.id.uuidString,
                                   "x": enemy.positionX, "y": enemy.positionY])
                }
                if enemyMovedThisTurn() { return }
                let afterDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
                if afterDist >= 2 && afterDist <= 5 {
                    // Drones attack at range 2–5 after advancing
                    let weaponAccuracy = enemy.equippedWeapon?.accuracy ?? 3
                    let enemyAttackPool = enemy.attributes.agi + (weaponAccuracy / 2 + 1)

                    // Player defense pool: REA + AGI + defend bonus + cover
                    let defenseBonus = isCharacterDefending(closestPlayer.id) ? 3 : 0
                    let enemyCoverCount2 = CombatMechanics.coverBetween(
                        tiles: currentMissionTiles,
                        fromX: enemy.positionX, fromY: enemy.positionY,
                        toX: closestPlayer.positionX, toY: closestPlayer.positionY
                    )
                    let playerCoverBonus2 = CombatMechanics.coverDefenseBonus(count: enemyCoverCount2)
                    let playerDefensePool = closestPlayer.attributes.rea + closestPlayer.attributes.agi + defenseBonus + playerCoverBonus2

                    let attackRoll = DiceEngine.roll(pool: enemyAttackPool)
                    let defenseRoll = DiceEngine.roll(pool: playerDefensePool)
                    let netHits = max(0, attackRoll.hits - defenseRoll.hits)

                    if netHits == 0 {
                        addLog("→ \(enemy.name) attacks \(closestPlayer.name) — DODGED!")
                    } else {
                        let weaponDmg = enemy.equippedWeapon?.damage ?? 4
                        let baseDmg = weaponDmg + netHits
                        let ap = enemy.equippedWeapon?.armorPiercing ?? 0
                        let soakPool = max(0, closestPlayer.computeDerived().soak - ap)
                        let soakRoll = DiceEngine.roll(pool: soakPool)
                        let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))

                        if dmg > 0 {
                            let isStun = enemy.equippedWeapon?.isStunDamage ?? false
                            closestPlayer.takeDamage(amount: dmg, isStun: isStun)
                            let dmgType = isStun ? "S" : "P"
                            HapticsManager.shared.playerDamaged()
                            addLog("⚠️ \(enemy.name) hits \(closestPlayer.name)! \(netHits) net hits → \(dmg)\(dmgType) dmg. (HP \(closestPlayer.currentHP)/\(closestPlayer.maxHP) | Stun \(closestPlayer.currentStun)/\(closestPlayer.maxStun))")
                            NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: ["playerId": closestPlayer.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString])
                            if !closestPlayer.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: closestPlayer) }
                        } else {
                            addLog("→ \(enemy.name) attacks — \(closestPlayer.name) soaks all damage!")
                        }
                    }
                }
            }

        case "healer":
            if let woundedAlly = findWoundedAlly(for: enemy) {
                let distToAlly = hexDistance(x1: woundedAlly.positionX, y1: woundedAlly.positionY, x2: enemy.positionX, y2: enemy.positionY)
                if distToAlly > 1 {
                    // Single .enemyMoved post at end (see corpmage fix above).
                    let healStartX = enemy.positionX, healStartY = enemy.positionY
                    for _ in 0..<2 {
                        if let (newX, newY) = bfsPathfindToWounded(from: enemy, toward: woundedAlly) {
                            // Overwatch: check before each step
                            for (attackerId, _) in overwatchers {
                                fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                            }
                            enemy.positionX = newX; enemy.positionY = newY
                            let newDist = hexDistance(x1: woundedAlly.positionX, y1: woundedAlly.positionY, x2: enemy.positionX, y2: enemy.positionY)
                            if newDist <= 1 { break }
                        } else { break }
                    }
                    if enemy.positionX != healStartX || enemy.positionY != healStartY {
                        addLog("→ \(enemy.name) moves to assist ally")
                        NotificationCenter.default.post(name: .enemyMoved, object: nil,
                            userInfo: ["enemyId": enemy.id.uuidString,
                                       "x": enemy.positionX, "y": enemy.positionY])
                    }
                    let afterDist = hexDistance(x1: woundedAlly.positionX, y1: woundedAlly.positionY, x2: enemy.positionX, y2: enemy.positionY)
                    if afterDist > 1 { return }
                    if enemyMovedThisTurn() { return }
                }
                // Don't heal a corpse — between findWoundedAlly and the move-to-ally
                // loop the ally could have been killed (async damage events).
                guard woundedAlly.isAlive else { return }
                let healAmount = 8 + Int.random(in: 0...4)
                let actualHeal = max(0, min(healAmount, woundedAlly.maxHP - woundedAlly.currentHP))
                woundedAlly.currentHP += actualHeal
                HapticsManager.shared.attackHit()
                addLog("💉 \(enemy.name) heals \(woundedAlly.name)! +\(actualHeal) HP. (\(woundedAlly.currentHP)/\(woundedAlly.maxHP))")
                NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": woundedAlly.id.uuidString, "damage": -actualHeal])
                return
            }
            // No wounded ally — reposition near the nearest living ally OR attack nearest player.
            let nearestAlly = enemies.filter({ $0.isAlive && $0.id != enemy.id }).min { a, b in
                let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                return distA < distB
            }
            if let ally = nearestAlly {
                // Allies still alive — stay close to support them
                let distToAlly = hexDistance(x1: ally.positionX, y1: ally.positionY, x2: enemy.positionX, y2: enemy.positionY)
                if distToAlly > 2 {
                    if let (nx, ny) = bfsPathfindToWounded(from: enemy, toward: ally) {
                        // Overwatch: check before movement
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = nx; enemy.positionY = ny
                        addLog("→ \(enemy.name) repositions near ally")
                        NotificationCenter.default.post(name: .enemyMoved, object: nil, userInfo: ["enemyId": enemy.id.uuidString, "x": nx, "y": ny])
                    }
                }
            } else {
                // No allies alive at all — healer attacks nearest player with its sidearm.
                guard let target = livingPlayers.min(by: {
                    hexDistance(x1: $0.positionX, y1: $0.positionY, x2: enemy.positionX, y2: enemy.positionY) <
                    hexDistance(x1: $1.positionX, y1: $1.positionY, x2: enemy.positionX, y2: enemy.positionY)
                }) else { break }

                // Advance 1 step if out of range (healer weapon range ≤ 3)
                let distToTarget = hexDistance(x1: target.positionX, y1: target.positionY, x2: enemy.positionX, y2: enemy.positionY)
                if distToTarget > 3 {
                    if let (nx, ny) = bfsPathfind(from: enemy, toward: target) {
                        enemy.positionX = nx; enemy.positionY = ny
                        addLog("→ \(enemy.name) advances (no allies)")
                        NotificationCenter.default.post(name: .enemyMoved, object: nil, userInfo: ["enemyId": enemy.id.uuidString, "x": nx, "y": ny])
                    }
                }
                if enemyMovedThisTurn() { return }
                // Ranged attack
                let weaponAccuracy = enemy.equippedWeapon?.accuracy ?? 3
                let attackPool = max(1, enemy.attributes.agi + (weaponAccuracy / 2))
                let defensePool = target.attributes.rea + target.attributes.agi
                let attackRoll = DiceEngine.roll(pool: attackPool)
                let defenseRoll = DiceEngine.roll(pool: defensePool)
                let netHits = max(0, attackRoll.hits - defenseRoll.hits)
                if netHits > 0 {
                    let weaponDmg = enemy.equippedWeapon?.damage ?? 3
                    let dmg = escalatedIncomingDamage(max(0, weaponDmg + netHits - DiceEngine.roll(pool: target.computeDerived().soak).hits))
                    if dmg > 0 {
                        target.takeDamage(amount: dmg)
                        addLog("⚠️ \(enemy.name) attacks \(target.name) → \(dmg)P dmg")
                        NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: ["playerId": target.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString])
                    } else {
                        addLog("→ \(enemy.name) attacks \(target.name) — soaked!")
                    }
                } else {
                    addLog("→ \(enemy.name) attacks \(target.name) — DODGED!")
                }
            }

        case "elite":
            let closestPlayer = livingPlayers.min { a, b in
                let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                return distA < distB
            }!
            let dist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
            if dist > 1 {
                // Single .enemyMoved post at end (see corpmage fix above).
                let eliteStartX = enemy.positionX, eliteStartY = enemy.positionY
                for _ in 0..<3 {
                    if let (newX, newY) = bfsPathfind(from: enemy, toward: closestPlayer) {
                        // Overwatch: check before each step
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = newX; enemy.positionY = newY
                        let newDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
                        if newDist <= 1 { break }
                    } else { break }
                }
                if enemy.positionX != eliteStartX || enemy.positionY != eliteStartY {
                    addLog("→ \(enemy.name) charges!")
                    NotificationCenter.default.post(name: .enemyMoved, object: nil,
                        userInfo: ["enemyId": enemy.id.uuidString,
                                   "x": enemy.positionX, "y": enemy.positionY])
                }
                let afterMoveDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
                if afterMoveDist > 1 { return }
                if enemyMovedThisTurn() { return }
            }
            // Enemy attack pool: AGI + weapon accuracy/2 (approx skill)
            let weaponAccuracy = enemy.equippedWeapon?.accuracy ?? 3
            let enemyAttackPool = enemy.attributes.agi + (weaponAccuracy / 2 + 1)

            // Player defense pool: REA + AGI + defend bonus + cover
            let defenseBonus = isCharacterDefending(closestPlayer.id) ? 3 : 0
            let eliteCoverCount = CombatMechanics.coverBetween(
                tiles: currentMissionTiles,
                fromX: enemy.positionX, fromY: enemy.positionY,
                toX: closestPlayer.positionX, toY: closestPlayer.positionY
            )
            let elitePlayerCoverBonus = CombatMechanics.coverDefenseBonus(count: eliteCoverCount)
            let playerDefensePool = closestPlayer.attributes.rea + closestPlayer.attributes.agi + defenseBonus + elitePlayerCoverBonus

            let attackRoll = DiceEngine.roll(pool: enemyAttackPool)
            let defenseRoll = DiceEngine.roll(pool: playerDefensePool)
            let netHits = max(0, attackRoll.hits - defenseRoll.hits)

            if netHits == 0 {
                addLog("→ \(enemy.name) attacks \(closestPlayer.name) — DODGED!")
            } else {
                let weaponDmg = enemy.equippedWeapon?.damage ?? 4
                let baseDmg = weaponDmg + netHits
                let ap = enemy.equippedWeapon?.armorPiercing ?? 0
                let soakPool = max(0, closestPlayer.computeDerived().soak - ap)
                let soakRoll = DiceEngine.roll(pool: soakPool)
                let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))

                if dmg > 0 {
                    let isStun = enemy.equippedWeapon?.isStunDamage ?? false
                    closestPlayer.takeDamage(amount: dmg, isStun: isStun)
                    let dmgType = isStun ? "S" : "P"
                    HapticsManager.shared.playerDamaged()
                    addLog("⚠️ \(enemy.name) hits \(closestPlayer.name)! \(netHits) net hits → \(dmg)\(dmgType) dmg. (HP \(closestPlayer.currentHP)/\(closestPlayer.maxHP) | Stun \(closestPlayer.currentStun)/\(closestPlayer.maxStun))")
                    NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: ["playerId": closestPlayer.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString])
                    if !closestPlayer.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: closestPlayer) }
                } else {
                    addLog("→ \(enemy.name) attacks — \(closestPlayer.name) soaks all damage!")
                }
            }

        case "bossmage":
            // M3 boss — Sato Unbound. Aggressive blood-magic caster. Per
            // playtest 2026-05-23: boss was "stuck in one place for several
            // turns" — root cause was preferredRange=3 letting him stop the
            // moment a player got near. New behavior: re-evaluate closest
            // target every step AND keep closing aggressively (range 2)
            // so he always advances on the party. Boss still steps one tile
            // per move-budget iteration to avoid the bfsPathfind teleport
            // pattern. Only stops moving if already at range 2 OR cornered.
            do {
                let startX = enemy.positionX
                let startY = enemy.positionY
                let preferredRange = 2
                for _ in 0..<enemy.moveRange {
                    // Re-target every step — players may move past the boss
                    // mid-pursuit; without this he'd commit to a stale target
                    // and miss closer threats.
                    guard let closestPlayer = livingPlayers.min(by: { a, b in
                        let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                        let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                        return distA < distB
                    }) else { break }
                    let curDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY,
                                              x2: enemy.positionX, y2: enemy.positionY)
                    if curDist <= preferredRange { break }
                    if let (newX, newY) = bfsNextStep(from: enemy, toward: closestPlayer) {
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = newX; enemy.positionY = newY
                    } else {
                        break
                    }
                }
                // Re-pick spell target from final position so the cast
                // resolves against whoever is actually closest now.
                guard let closestPlayer = livingPlayers.min(by: { a, b in
                    let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                    let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                    return distA < distB
                }) else { return }
                if enemy.positionX != startX || enemy.positionY != startY {
                    addLog("→ \(enemy.name) glides forward, robes trailing red")
                    NotificationCenter.default.post(name: .enemyMoved, object: nil,
                        userInfo: ["enemyId": enemy.id.uuidString,
                                   "x": enemy.positionX, "y": enemy.positionY])
                }
                // Cast spell from new position if in range.
                let afterDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY,
                                            x2: enemy.positionX, y2: enemy.positionY)
                if afterDist <= 6 {
                    let attackPool = enemy.attributes.agi + 4
                    let defensePool = closestPlayer.attributes.rea + closestPlayer.attributes.agi
                    let attackRoll = DiceEngine.roll(pool: attackPool)
                    let defenseRoll = DiceEngine.roll(pool: defensePool)
                    let netHits = max(0, attackRoll.hits - defenseRoll.hits)
                    if netHits == 0 {
                        addLog("→ \(enemy.name) hurls a blood-bolt — \(closestPlayer.name) dives clear!")
                    } else {
                        let baseDmg = 8 + netHits
                        let soakPool = max(0, closestPlayer.computeDerived().soak - 3)
                        let soakRoll = DiceEngine.roll(pool: soakPool)
                        let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))
                        if dmg > 0 {
                            closestPlayer.takeDamage(amount: dmg, isStun: false)
                            HapticsManager.shared.playerDamaged()
                            addLog("🩸 \(enemy.name)'s blood-bolt hits \(closestPlayer.name)! \(dmg)P. (HP \(closestPlayer.currentHP)/\(closestPlayer.maxHP))")
                            NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: [
                                "playerId": closestPlayer.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString
                            ])
                            if !closestPlayer.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: closestPlayer) }
                        } else {
                            addLog("→ \(enemy.name)'s spell — \(closestPlayer.name) soaks all damage!")
                        }
                    }
                }
            }

        case "bossmech":
            // M5 boss — heavy autocannon, range 6, aggressively pursues. The
            // mech holds at preferred range ~4 (close enough to threaten,
            // not so close it walks into melee), advancing ONE tile per
            // move-budget iteration via `bfsNextStep`. Earlier this used
            // `bfsPathfind` which returns a tile ADJACENT TO THE PLAYER —
            // that teleported the mech across the whole room in one tick
            // and looked like a glitch (sometimes the player saw the boss
            // "not moving" because it pinned itself in melee on turn 1 and
            // never moved again). Step-by-step pursuit reads as proper AI.
            do {
                let closestPlayer = livingPlayers.min { a, b in
                    let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                    let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                    return distA < distB
                }!
                let startX = enemy.positionX
                let startY = enemy.positionY
                let preferredRange = 4   // autocannon optimal: ~4 tiles
                for _ in 0..<enemy.moveRange {
                    let curDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY,
                                              x2: enemy.positionX, y2: enemy.positionY)
                    // Already at preferred range — hold position and shoot.
                    if curDist <= preferredRange { break }
                    if let (newX, newY) = bfsNextStep(from: enemy, toward: closestPlayer) {
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = newX; enemy.positionY = newY
                    } else {
                        break
                    }
                }
                if enemy.positionX != startX || enemy.positionY != startY {
                    addLog("→ \(enemy.name) advances on \(closestPlayer.name)")
                    NotificationCenter.default.post(name: .enemyMoved, object: nil,
                        userInfo: ["enemyId": enemy.id.uuidString,
                                   "x": enemy.positionX, "y": enemy.positionY])
                }
                // Fire from new position.
                let afterDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY,
                                            x2: enemy.positionX, y2: enemy.positionY)
                if afterDist <= 6 {
                    let attackPool = enemy.attributes.agi + (enemy.equippedWeapon?.accuracy ?? 4) / 2 + 1
                    let defensePool = closestPlayer.attributes.rea + closestPlayer.attributes.agi
                    let attackRoll = DiceEngine.roll(pool: attackPool)
                    let defenseRoll = DiceEngine.roll(pool: defensePool)
                    let netHits = max(0, attackRoll.hits - defenseRoll.hits)
                    if netHits == 0 {
                        addLog("→ \(enemy.name) autocannon — \(closestPlayer.name) dodges!")
                    } else {
                        let baseDmg = (enemy.equippedWeapon?.damage ?? 10) + netHits
                        let ap = enemy.equippedWeapon?.armorPiercing ?? 4
                        let soakPool = max(0, closestPlayer.computeDerived().soak - ap)
                        let soakRoll = DiceEngine.roll(pool: soakPool)
                        let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))
                        if dmg > 0 {
                            closestPlayer.takeDamage(amount: dmg, isStun: false)
                            HapticsManager.shared.playerDamaged()
                            addLog("💥 \(enemy.name) autocannon hits \(closestPlayer.name) — \(dmg)P. (HP \(closestPlayer.currentHP)/\(closestPlayer.maxHP))")
                            NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: [
                                "playerId": closestPlayer.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString
                            ])
                            NotificationCenter.default.post(name: .gunfireEffect, object: nil,
                                userInfo: [
                                    "fromX": enemy.positionX, "fromY": enemy.positionY,
                                    "toX": closestPlayer.positionX, "toY": closestPlayer.positionY,
                                    "weaponType": (enemy.equippedWeapon?.type.rawValue ?? "rifle"),
                                    "enemyArchetype": enemy.archetype
                                ])
                            if !closestPlayer.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: closestPlayer) }
                        } else {
                            addLog("→ \(enemy.name) — \(closestPlayer.name) soaks all damage!")
                        }
                    }
                }
            }

        case "bossagi":
            // M6 boss — AGGRESSIVE pursue. The AGI prefers to chase right up
            // to the player (Reality Glitch is best in close range). Steps
            // ONE tile per move-budget iteration via `bfsNextStep` so it
            // visibly stalks across the room rather than teleporting (the
            // earlier `bfsPathfind` returned a tile adjacent to the player
            // directly, which moved the boss its full distance in one tick
            // and made it appear to skip all intermediate squares).
            let closestPlayer = livingPlayers.min { a, b in
                let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                return distA < distB
            }!
            let startX = enemy.positionX
            let startY = enemy.positionY
            let preferredRange = 2   // AGI hunts in close — preferred ~2 tiles
            for _ in 0..<enemy.moveRange {
                let curDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY,
                                          x2: enemy.positionX, y2: enemy.positionY)
                if curDist <= preferredRange { break }
                if let (newX, newY) = bfsNextStep(from: enemy, toward: closestPlayer) {
                    for (attackerId, _) in overwatchers {
                        fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                    }
                    enemy.positionX = newX; enemy.positionY = newY
                } else {
                    break
                }
            }
            if enemy.positionX != startX || enemy.positionY != startY {
                addLog("→ \(enemy.name) phase-shifts toward \(closestPlayer.name)")
                NotificationCenter.default.post(name: .enemyMoved, object: nil,
                    userInfo: ["enemyId": enemy.id.uuidString,
                               "x": enemy.positionX, "y": enemy.positionY])
            }

            // Attack from the new position if in range.
            let afterDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY,
                                        x2: enemy.positionX, y2: enemy.positionY)
            if afterDist <= 6 {
                let attackPool = enemy.attributes.agi + (enemy.equippedWeapon?.accuracy ?? 5) / 2 + 1
                let defensePool = closestPlayer.attributes.rea + closestPlayer.attributes.agi
                let attackRoll = DiceEngine.roll(pool: attackPool)
                let defenseRoll = DiceEngine.roll(pool: defensePool)
                let netHits = max(0, attackRoll.hits - defenseRoll.hits)
                if netHits == 0 {
                    addLog("→ AGI-PRIME's Reality Glitch — \(closestPlayer.name) phases through!")
                } else {
                    let baseDmg = (enemy.equippedWeapon?.damage ?? 9) + netHits
                    let ap = enemy.equippedWeapon?.armorPiercing ?? 5
                    let soakPool = max(0, closestPlayer.computeDerived().soak - ap)
                    let soakRoll = DiceEngine.roll(pool: soakPool)
                    let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))
                    if dmg > 0 {
                        closestPlayer.takeDamage(amount: dmg, isStun: false)
                        HapticsManager.shared.playerDamaged()
                        addLog("✨ AGI-PRIME's Reality Glitch hits \(closestPlayer.name)! \(dmg)P dmg. (HP \(closestPlayer.currentHP)/\(closestPlayer.maxHP))")
                        NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: [
                            "playerId": closestPlayer.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString
                        ])
                        NotificationCenter.default.post(name: .gunfireEffect, object: nil,
                            userInfo: [
                                "fromX": enemy.positionX, "fromY": enemy.positionY,
                                "toX": closestPlayer.positionX, "toY": closestPlayer.positionY,
                                "weaponType": (enemy.equippedWeapon?.type.rawValue ?? "rifle"),
                                "enemyArchetype": enemy.archetype
                            ])
                        if !closestPlayer.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: closestPlayer) }
                    } else {
                        addLog("→ AGI-PRIME's glitch — \(closestPlayer.name) soaks all damage!")
                    }
                }
            }

        default:
            let closestPlayer = livingPlayers.min { a, b in
                let distA = hexDistance(x1: a.positionX, y1: a.positionY, x2: enemy.positionX, y2: enemy.positionY)
                let distB = hexDistance(x1: b.positionX, y1: b.positionY, x2: enemy.positionX, y2: enemy.positionY)
                return distA < distB
            }!
            let dist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
            let target = closestPlayer

            // FIX 2: reposition non-drone enemies before attacking if out of weapon range
            // Melee: range 1. Ranged guards/pistols: range 4. Rifles: range 6. Mages: range 5.
            let maxWeaponRange: Int
            if enemy.archetype == "mage" {
                maxWeaponRange = 5
            } else {
                // Guard / default: pistol/rifle
                switch enemy.equippedWeapon?.type {
                case .rifle: maxWeaponRange = 6
                case .pistol, .smg: maxWeaponRange = 4
                case .blade, .unarmed: maxWeaponRange = 1
                default: maxWeaponRange = 3
                }
            }

            if dist > maxWeaponRange {
                // Move up to moveRange tiles toward player. Post .enemyMoved
                // ONCE at the end with the final destination so the visual
                // animation slides smoothly from start → final without
                // cancelling itself mid-flight on every intermediate step.
                // (The previous version posted inside the loop, which
                // combined with animateMove's "move" action key cancelling
                // produced the corpmage's "walks right, half body, reappears
                // left" glitch — each intermediate post killed the in-flight
                // animation and replaced it with a new one starting from the
                // node's mid-tile position.)
                let startX = enemy.positionX
                let startY = enemy.positionY
                for _ in 0..<enemy.moveRange {
                    if let (newX, newY) = bfsPathfind(from: enemy, toward: closestPlayer) {
                        // Overwatch: check before each step
                        for (attackerId, _) in overwatchers {
                            fireOverwatchShot(atEnemy: enemy, attackerId: attackerId)
                        }
                        enemy.positionX = newX; enemy.positionY = newY
                        let newDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
                        if newDist <= maxWeaponRange { break }
                    } else { break }
                }
                if enemy.positionX != startX || enemy.positionY != startY {
                    addLog("→ \(enemy.name) advances")
                    NotificationCenter.default.post(name: .enemyMoved, object: nil,
                        userInfo: ["enemyId": enemy.id.uuidString,
                                   "x": enemy.positionX, "y": enemy.positionY])
                }
            }

            if enemyMovedThisTurn() { return }
            let afterMoveDist = hexDistance(x1: closestPlayer.positionX, y1: closestPlayer.positionY, x2: enemy.positionX, y2: enemy.positionY)
            // Only attack if in range after repositioning; mage spells are range 5
            let effectiveRange = enemy.archetype == "mage" ? 5 : (enemy.equippedWeapon?.type == .rifle ? 6 : (enemy.equippedWeapon?.type == .pistol || enemy.equippedWeapon?.type == .smg) ? 4 : 1)
            if afterMoveDist > effectiveRange { return }

            // Handle mage enemy with spellcasting
            if enemy.archetype == "mage" {
                let spellPool = enemy.attributes.log + 3
                let spellRoll = DiceEngine.roll(pool: spellPool)

                if spellRoll.hits == 0 {
                    addLog("✨ \(enemy.name) casts a spell but it fizzles...")
                } else {
                    let baseDamage = 6 + spellRoll.hits
                    let soakPool = target.attributes.wil + (target.equippedArmor?.armorValue ?? 0) / 2
                    let soakRoll = DiceEngine.roll(pool: max(0, soakPool))
                    let dmg = escalatedIncomingDamage(max(1, baseDamage - soakRoll.hits))

                    if dmg > 0 {
                        target.takeDamage(amount: dmg, isStun: false)  // enemy mage spells deal physical
                        HapticsManager.shared.playerDamaged()
                        addLog("✨ \(enemy.name) casts! [\(spellPool)d6→\(spellRoll.hits) hits] \(baseDamage)P - \(soakRoll.hits)soak = \(dmg) dmg. (HP \(target.currentHP)/\(target.maxHP))")
                        NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: ["playerId": target.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString])
                        if !target.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: target) }
                    } else {
                        addLog("✨ \(enemy.name) casts but \(target.name) resists!")
                    }
                }
            } else {
                // Guard/regular enemy uses melee combat
                let weaponAccuracy = enemy.equippedWeapon?.accuracy ?? 3
                let enemyAttackPool = enemy.attributes.agi + (weaponAccuracy / 2 + 1)

                let defenseBonus = isCharacterDefending(target.id) ? 3 : 0
                let guardCoverCount = CombatMechanics.coverBetween(
                    tiles: currentMissionTiles,
                    fromX: enemy.positionX, fromY: enemy.positionY,
                    toX: target.positionX, toY: target.positionY
                )
                let guardPlayerCoverBonus = CombatMechanics.coverDefenseBonus(count: guardCoverCount)
                let playerDefensePool = target.attributes.rea + target.attributes.agi + defenseBonus + guardPlayerCoverBonus

                // Post gunfire effect so SFXManager can play the right
                // weapon clip (sniper enemies share the rifle WeaponType but
                // should sound distinct, so we also pass archetype).
                let weaponType = enemy.equippedWeapon?.type
                if let wt = weaponType, wt != .blade && wt != .unarmed {
                    NotificationCenter.default.post(
                        name: .gunfireEffect, object: nil,
                        userInfo: [
                            "fromX": enemy.positionX, "fromY": enemy.positionY,
                            "toX":   target.positionX,  "toY":   target.positionY,
                            "weaponType":     wt.rawValue,
                            "enemyArchetype": enemy.archetype
                        ]
                    )
                }

                let attackRoll = DiceEngine.roll(pool: enemyAttackPool)
                let defenseRoll = DiceEngine.roll(pool: playerDefensePool)
                let netHits = max(0, attackRoll.hits - defenseRoll.hits)

                if netHits == 0 {
                    addLog("→ \(enemy.name) attacks \(target.name) — DODGED!")
                } else {
                    let weaponDmg = enemy.equippedWeapon?.damage ?? 4
                    let baseDmg = weaponDmg + netHits
                    let ap = enemy.equippedWeapon?.armorPiercing ?? 0
                    let soakPool = max(0, target.computeDerived().soak - ap)
                    let soakRoll = DiceEngine.roll(pool: soakPool)
                    let dmg = escalatedIncomingDamage(max(0, baseDmg - soakRoll.hits))

                    if dmg > 0 {
                        let isStun = enemy.equippedWeapon?.isStunDamage ?? false
                        target.takeDamage(amount: dmg, isStun: isStun)
                        let dmgType = isStun ? "S" : "P"
                        HapticsManager.shared.playerDamaged()
                        addLog("⚠️ \(enemy.name) hits \(target.name)! \(netHits) net hits → \(dmg)\(dmgType) dmg. (HP \(target.currentHP)/\(target.maxHP) | Stun \(target.currentStun)/\(target.maxStun))")
                        NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: ["playerId": target.id.uuidString, "damage": dmg, "enemyId": enemy.id.uuidString])
                        if !target.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: target) }
                    } else {
                        addLog("→ \(enemy.name) attacks — \(target.name) soaks all damage!")
                    }
                }
            }
        }
    }

    /// Find the best retreat tile for a drone — step AWAY from the target (hex-aware).
    func bestRetreatTile(for enemy: Enemy, awayFrom target: Character) -> (Int, Int) {
        PathingAndAIHelpers.bestRetreatTile(gameState: self, for: enemy, awayFrom: target)
    }

    /// BFS pathfinding for drone (hex-aware).
    func bfsPathfindDrone(from enemy: Enemy, towardX gx: Int, y gy: Int) -> (Int, Int)? {
        PathingAndAIHelpers.bfsPathfindDrone(gameState: self, from: enemy, towardX: gx, y: gy)
    }
    /// BFS pathfinding — returns best hex-adjacent tile to move toward target.
    func bfsPathfind(from enemy: Enemy, toward target: Character) -> (Int, Int)? {
        PathingAndAIHelpers.bfsPathfind(gameState: self, from: enemy, toward: target)
    }

    /// Single-step BFS — returns the FIRST hex toward target along the
    /// shortest path. Used by boss pursuit AI so each move-budget iteration
    /// advances ONE tile (visible per-tile pursuit) instead of teleporting
    /// straight to a tile adjacent to the player.
    func bfsNextStep(from enemy: Enemy, toward target: Character) -> (Int, Int)? {
        PathingAndAIHelpers.bfsNextStep(gameState: self, from: enemy, toward: target)
    }

    /// Find a wounded ally (enemy) within 5 hex tiles to heal.
    func findWoundedAlly(for enemy: Enemy) -> Enemy? {
        PathingAndAIHelpers.findWoundedAlly(gameState: self, for: enemy)
    }

    /// BFS pathfinding to a wounded ally (hex-aware, healer can pass through other enemies).
    func bfsPathfindToWounded(from enemy: Enemy, toward target: Enemy) -> (Int, Int)? {
        PathingAndAIHelpers.bfsPathfindToWounded(gameState: self, from: enemy, toward: target)
    }

    /// Check if a tile is walkable for the healer (medic can walk through other enemies).
    func tileWalkableForHealer(x: Int, y: Int, excluding enemyId: UUID) -> Bool {
        PathingAndAIHelpers.tileWalkableForHealer(gameState: self, x: x, y: y, excluding: enemyId)
    }

    /// Expose isDefending for enemyPhase damage check.
    func isCharacterDefending(_ charId: UUID) -> Bool {
        CombatFlowController.isCharacterDefending(gameState: self, charId)
    }

    /// FIX 2: Check if any wall tile intersects the straight line between two tiles.
    /// Uses Bresenham's line algorithm to check each tile along the path.
    /// Returns true if a wall blocks the attack.
    func isLineBlockedByWall(fromX sx: Int, fromY sy: Int, toX dx: Int, toY dy: Int) -> Bool {
        PathingAndAIHelpers.isLineBlockedByWall(gameState: self, fromX: sx, fromY: sy, toX: dx, toY: dy)
    }

    func findNextLivingCharacter(after index: Int) -> Character? {
        PathingAndAIHelpers.findNextLivingCharacter(gameState: self, after: index)
    }

    // MARK: - Hex Grid Helpers

    /// Returns the 6 valid hex neighbors for a flat-top odd-q offset coordinate.
    func hexNeighbors(x: Int, y: Int) -> [(Int, Int)] {
        PathingAndAIHelpers.hexNeighbors(gameState: self, x: x, y: y)
    }

    /// True if (x2,y2) is one of the 6 hex neighbors of (x1,y1).
    func hexAdjacent(x1: Int, y1: Int, x2: Int, y2: Int) -> Bool {
        PathingAndAIHelpers.hexAdjacent(gameState: self, x1: x1, y1: y1, x2: x2, y2: y2)
    }

    /// Hex distance between two tiles using cube coordinate conversion (flat-top odd-q offset).
    func hexDistance(x1: Int, y1: Int, x2: Int, y2: Int) -> Int {
        PathingAndAIHelpers.hexDistance(gameState: self, x1: x1, y1: y1, x2: x2, y2: y2)
    }

    /// Check if a tile is walkable for enemies (not wall/door, not occupied by player or other enemy)
    func tileWalkable(x: Int, y: Int, excluding enemyId: UUID) -> Bool {
        PathingAndAIHelpers.tileWalkable(gameState: self, x: x, y: y, excluding: enemyId)
    }

    func showMoveMenu() {
        CombatFlowController.showMoveMenu(gameState: self)
    }

    /// Use first available consumable on the active character.
    func performUseItem() {
        CombatFlowController.performUseItem(gameState: self)
    }

    /// Select a character by UUID and update active character.
    func selectCharacter(id: UUID) {
        CombatFlowController.selectCharacter(gameState: self, id: id)
    }

    /// Handle a tap on a tile from BattleScene.
    func handleTileTap(tileX: Int, tileY: Int) {
        CombatFlowController.handleTileTap(gameState: self, tileX: tileX, tileY: tileY)
    }

    // MARK: - Log

    func addLog(_ entry: String) {
        combatLog.append(entry)
        if combatLog.count > 50 { combatLog.removeFirst() }
        // Force SwiftUI refresh for array mutations
        objectWillChange.send()

        // Play UI error chirp on user-facing failure messages. We detect by
        // prefix/keyword so call sites stay terse — anything starting with
        // these tokens is treated as a "you can't do that" feedback event.
        // Glitches (⚠️/💥) are gameplay events with their own SFX, so excluded.
        if SFXClassifier.isLockedDoor(entry) {
            // Door-specific buzzy refusal — checked BEFORE generic error so
            // it doesn't get masked by the broader "Move closer" matcher.
            SFXManager.shared.play("door_locked")
        } else if SFXClassifier.isUserError(entry) {
            HapticsManager.shared.error()
        } else if SFXClassifier.isUnlock(entry) {
            HapticsManager.shared.unlock()
        }
    }
}

/// Helper for classifying combat-log entries so SFX can fire from a single
/// place (addLog) rather than at every error site.
@MainActor
enum SFXClassifier {
    static func isUserError(_ entry: String) -> Bool {
        // Prefixes / keywords that indicate "you can't do that" feedback.
        let triggers = [
            "No target", "No targets",
            "No character",
            "Not enough",
            "Only the ",     // "Only the Face can intimidate", etc.
            "already moved", "already attacked",
            "Move adjacent", "Move closer",
            "Out of ",
            "Invalid target",
            "Cannot move",
            "⛔",            // line-of-sight-blocked emoji prefix
        ]
        return triggers.contains { entry.contains($0) }
    }

    static func isUnlock(_ entry: String) -> Bool {
        // Door / terminal / objective unlocks.
        return entry.contains("Door unlocked") ||
               entry.contains("data acquired") ||
               entry.contains("Terminal hacked")
    }

    static func isLockedDoor(_ entry: String) -> Bool {
        // Player tried to use a still-locked door.
        return entry.contains("Use the marked door tile") ||
               entry.contains("Cannot move onto a door tile") ||
               entry.contains("Move closer to the door first")
    }
}

// MARK: - Game Phase

/// Game state machine managing all major game states and transitions
enum GamePhase: Equatable {
    case title
    case prologue            // Pre-M1 "Neon Lotus" VN-style recruit cinematic
    case missionSelect
    case missionIntro        // Per-mission pre-briefing VN cutscene (M1-M6)
    case briefing
    case combat
    case missionOutro        // Per-mission post-combat VN cutscene (M1-M6) — plays before debrief on victory
    case dropIntro           // M3.5 pre-chase VN cinematic (runners exiting M3, boarding bike)
    case hoverbikeChase      // M3.5 "The Drop" — side-scrolling chase mission
    case basementBrawl       // M4.5 "Basement Brawl" — Raze solo side-on melee duel
    case mirrorline          // M2.5 "Mirrorline" — Sable solo astral sigil-tracing
    case coldTrace           // M5.5 "Cold Trace" — Cipher solo matrix-dive process-triage
    case debrief
    case gameEnding          // Post-M6-victory ending cutscene (epilogue + AI-seed coda)

    var displayName: String {
        switch self {
        case .title:           return "Title"
        case .prologue:        return "Prologue"
        case .missionSelect:   return "Mission Select"
        case .missionIntro:    return "Mission Intro"
        case .briefing:        return "Briefing"
        case .combat:          return "Combat"
        case .missionOutro:    return "Mission Outro"
        case .dropIntro:       return "The Drop — Intro"
        case .hoverbikeChase:  return "The Drop"
        case .basementBrawl:   return "Basement Brawl"
        case .mirrorline:      return "Mirrorline"
        case .coldTrace:       return "Cold Trace"
        case .debrief:         return "Debrief"
        case .gameEnding:      return "Endless Rain"
        }
    }
}

// MARK: - State Transition Event

enum StateTransition {
    case startGame
    case viewPrologue          // Title → Prologue (Neon Lotus recruit scene)
    case finishPrologue        // Prologue → Title (loops back, doesn't auto-start M1)
    case viewMissionIntro      // MissionSelect → MissionIntro (per-mission cutscene)
    case finishMissionIntro    // MissionIntro → Briefing (mission-specific cutscene done)
    case viewDropIntro         // MissionSelect → DropIntro (M3.5 cutscene)
    case finishDropIntro       // DropIntro → HoverbikeChase (auto-into the chase)
    case viewHoverbikeChase    // MissionSelect → HoverbikeChase (skip intro)
    case finishHoverbikeChase  // HoverbikeChase → MissionSelect (legacy/abort path)
    case endChase(won: Bool)   // HoverbikeChase → MissionOutro on win, Debrief on loss
    case viewBasementBrawl     // MissionIntro → BasementBrawl (M4.5 gameplay)
    case endBrawl(won: Bool)   // BasementBrawl → MissionOutro on win, Debrief on loss
    case viewMirrorline        // MissionIntro → Mirrorline (M2.5 gameplay)
    case endMirrorline(won: Bool)  // Mirrorline → MissionOutro on win, Debrief on loss
    case viewColdTrace         // MissionIntro → ColdTrace (M5.5 gameplay)
    case endColdTrace(won: Bool)  // ColdTrace → MissionOutro on win, Debrief on loss
    case selectMission(String)
    case beginMission
    case startCombat
    case endCombat(won: Bool)
    case viewMissionOutro      // Combat → MissionOutro (post-combat cutscene on victory)
    case finishMissionOutro    // MissionOutro → Debrief (outro done, go score the mission)
    case viewGameEnding        // Debrief → GameEnding (only after M6 victory)
    case finishGameEnding      // GameEnding → Title (epilogue done, return to title)
    case viewDebrief
    case returnToTitle
    case exitGame
}

// `GameStateManager` (legacy phase manager) was removed 2026-05 — was
// declared "for compatibility" but had zero call sites. `PhaseManager` in
// ShadowrunGameApp.swift is the canonical phase-flow authority.
