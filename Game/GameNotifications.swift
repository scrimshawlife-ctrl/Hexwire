import Foundation

// MARK: - Shared Notification Names

extension Notification.Name {
    static let characterSelected = Notification.Name("characterSelected")
    static let tileTapped     = Notification.Name("tileTapped")
    static let combatAction   = Notification.Name("combatAction")
    static let turnChanged    = Notification.Name("turnChanged")
    static let enemyHit       = Notification.Name("enemyHit")
    static let enemyDied      = Notification.Name("enemyDied")
    static let playerHit      = Notification.Name("playerHit")
    static let characterHit   = Notification.Name("characterHit")
    static let characterLevelUp = Notification.Name("characterLevelUp")
    static let enemyMoved     = Notification.Name("enemyMoved")
    static let enemySpawned    = Notification.Name("enemySpawned")
    static let characterDefend  = Notification.Name("characterDefend")
    static let roundStarted    = Notification.Name("roundStarted")
    static let roomCleared     = Notification.Name("roomCleared")
    static let enemyPhaseBegan  = Notification.Name("enemyPhaseBegan")
    static let playerTurnResumed = Notification.Name("playerTurnResumed")
    static let roomTransitionStarted = Notification.Name("roomTransitionStarted")
    static let roomTransitionCompleted = Notification.Name("roomTransitionCompleted")
    static let roomNavigationRequested = Notification.Name("roomNavigationRequested")
    static let enemyPhaseCompleted = Notification.Name("enemyPhaseCompleted")
    static let dataTerminalHacked  = Notification.Name("dataTerminalHacked")
    static let grimoireAcquired    = Notification.Name("grimoireAcquired")
    static let playerDied          = Notification.Name("playerDied")
    static let barriersDropped     = Notification.Name("barriersDropped")
    static let extractionAnimationRequested = Notification.Name("extractionAnimationRequested")
    static let extractionAnimationCompleted = Notification.Name("extractionAnimationCompleted")

    // MARK: - Spell / skill visual effects
    /// userInfo: ["targetId": String (character id), "amount": Int]
    static let healEffect      = Notification.Name("healEffect")
    /// userInfo: ["x": Int, "y": Int]   (tile coords of the explosion centre)
    static let fireballEffect  = Notification.Name("fireballEffect")
    /// userInfo: ["fromX": Int, "fromY": Int, "toX": Int, "toY": Int, "color": String hex]
    static let boltEffect      = Notification.Name("boltEffect")
    /// userInfo: ["fromX": Int, "fromY": Int, "toX": Int, "toY": Int]   (yellow lightning)
    static let shockEffect     = Notification.Name("shockEffect")
    /// userInfo: ["x": Int, "y": Int]   (samurai's tile — slash radiates out)
    static let blitzEffect     = Notification.Name("blitzEffect")
    /// userInfo: ["x": Int, "y": Int]   (Face's tile — red shockwave)
    static let intimidateEffect = Notification.Name("intimidateEffect")
    /// userInfo: ["fromX": Int, "fromY": Int, "toX": Int, "toY": Int]
    /// Muzzle flash at shooter + bullet tracer line from shooter → target.
    static let gunfireEffect   = Notification.Name("gunfireEffect")
    /// userInfo: ["x": Int, "y": Int]   (target tile — slash arc lands)
    /// Fires on every melee attempt (hit OR miss). SFXManager plays the
    /// swing-whoosh sound here.
    static let meleeStrikeEffect = Notification.Name("meleeStrikeEffect")
    /// userInfo: ["x": Int, "y": Int]
    /// Fires only when a melee attack actually lands damage. SFXManager
    /// plays the wet-thunk impact clip on this event.
    static let meleeImpactEffect = Notification.Name("meleeImpactEffect")
    /// userInfo: ["fromX": Int, "fromY": Int, "toX": Int, "toY": Int]
    /// Decker → target enemy binary-stream + circuit-pattern impact flash.
    static let hackEffect      = Notification.Name("hackEffect")
    /// userInfo: ["tileX": Int, "tileY": Int, "kind": Int]
    /// Posted when a runner steps onto a data terminal or extraction tile.
    /// `kind` matches `TileType.rawValue` (5 = dataTerminal, 4 = extraction).
    /// BattleScene draws an expanding floor ring as a triggered VFX.
    static let objectivePulseRequested = Notification.Name("objectivePulseRequested")
    /// Posted when the player long-presses a character or enemy sprite to
    /// surface their info dossier. CombatView observes and presents the
    /// CharacterInfoSheet modal.
    /// userInfo: ["kind": "player" | "enemy",
    ///            "characterId" or "enemyId": <UUID string>]
    static let entityInfoRequested = Notification.Name("entityInfoRequested")
}

// MARK: - Character Events
