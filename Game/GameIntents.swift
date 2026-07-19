import Foundation

// MARK: - Intent Facade (stabilization WP4)
//
// The seam rule for presentation layers (BattleScene, SwiftUI views,
// mini-game scenes):
//
//     UI/Scene emits intent.  Authority validates intent.
//     Authority mutates state.  Projection renders resulting state.
//
// Presentation code must not assign GameState properties directly. It calls
// these request* methods (or the existing perform*/authority methods, which
// already live on GameState) and renders from the resulting state. Every
// request returns an IntentResult so call sites can react without guessing
// at authority rules.

/// Outcome of a presentation-layer intent request.
enum IntentResult: Equatable {
    case accepted
    case rejected(reason: String)

    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}

/// Intent-level API the presentation layers are allowed to drive combat with.
@MainActor
protocol CombatIntentHandling: AnyObject {
    func requestEndTurn() -> IntentResult
    func requestMove(unitID: UUID, toTileX: Int, toTileY: Int) -> IntentResult
    func requestAttack() -> IntentResult
    func requestTargetSelection(enemyId: UUID) -> IntentResult
    func requestSelectionCleared() -> IntentResult
    func requestObjectiveDataAcquired(source: String) -> IntentResult
    func requestExtractionResolution(characterId: UUID?, tileX: Int, tileY: Int) -> IntentResult
    func requestExtractionSequenceCompleted() -> IntentResult
}

extension GameState: CombatIntentHandling {

    // MARK: End turn

    /// Validated end-turn. Rejects duplicates that arrive during the enemy
    /// phase or after resolution (the CombatFlowController latch also guards
    /// this; rejecting here reports it to the caller instead of silently
    /// dropping) and any end-turn after the mission is over.
    func requestEndTurn() -> IntentResult {
        if missionComplete || combatEnded {
            return .rejected(reason: "mission already resolved")
        }
        switch combatPhase {
        case .enemyResolving:
            return .rejected(reason: "enemy phase is resolving")
        case .combatResolved, .rewarding, .complete:
            return .rejected(reason: "combat already resolved")
        default:
            TurnManager.requestTurnAdvance(gameState: self)
            return .accepted
        }
    }

    // MARK: Movement

    /// Validated free-move. Mirrors CombatFlowController.moveCharacter's
    /// guards so the caller learns WHY a move was refused, then delegates the
    /// mutation to the same authority path the scene used to call directly.
    func requestMove(unitID: UUID, toTileX tileX: Int, toTileY tileY: Int) -> IntentResult {
        guard let char = playerTeam.first(where: { $0.id == unitID }) else {
            return .rejected(reason: "unknown actor")
        }
        guard char.isAlive else { return .rejected(reason: "actor is down") }
        guard CombatFlowController.canAcceptPlayerAction(gameState: self) else {
            return .rejected(reason: "not the player phase")
        }
        guard tileY >= 0, tileY < currentMissionTiles.count,
              tileX >= 0, tileX < currentMissionTiles[tileY].count else {
            return .rejected(reason: "destination out of bounds")
        }
        let tile = currentMissionTiles[tileY][tileX]
        if tile == TileType.wall.rawValue { return .rejected(reason: "destination is a wall") }
        if tile == TileType.door.rawValue { return .rejected(reason: "doors route through transitions") }
        guard !char.hasActedThisRound else { return .rejected(reason: "actor already acted this round") }
        guard characterHasMovedThisTurn[unitID] != true else {
            return .rejected(reason: "actor already moved this turn")
        }
        guard !char.statusEffects.contains(.prone) else { return .rejected(reason: "actor is prone") }
        moveCharacter(id: unitID, toTileX: tileX, toTileY: tileY)
        return .accepted
    }

    // MARK: Attack

    /// Validated attack intent — the resolution itself stays in
    /// CombatFlowController.performAttack (dice, soak, death, VFX routing).
    func requestAttack() -> IntentResult {
        guard CombatFlowController.canAcceptPlayerAction(gameState: self) else {
            return .rejected(reason: "not the player phase")
        }
        performAttack()
        return .accepted
    }

    // MARK: Actor / target selection

    /// Target an enemy for the next attack action. Requires a selected or
    /// active runner and a living target. (Moved from BattleScene, which used
    /// to assign targetCharacterId directly.)
    func requestTargetSelection(enemyId: UUID) -> IntentResult {
        guard activeCharacterId != nil || selectedCharacterId != nil else {
            return .rejected(reason: "no character selected")
        }
        guard let enemy = enemies.first(where: { $0.id == enemyId && $0.isAlive }) else {
            return .rejected(reason: "invalid or dead target")
        }
        targetCharacterId = enemyId
        addLog("🎯 Targeting: \(enemy.name) — tap ATK / SHT / HACK to fire.")
        return .accepted
    }

    /// Clear the current selection (e.g. the selected runner died). Idempotent.
    func requestSelectionCleared() -> IntentResult {
        selectedCharacterId = nil
        activeCharacterId = nil
        return .accepted
    }

    // MARK: Mission objective

    /// Record the data objective as acquired (mini-game victories). Exactly
    /// once: a duplicate report is rejected and changes nothing.
    func requestObjectiveDataAcquired(source: String) -> IntentResult {
        guard !dataAcquired else { return .rejected(reason: "objective already recorded") }
        dataAcquired = true
        dlog("[Intent] data objective recorded by \(source)")
        return .accepted
    }

    // MARK: Extraction

    /// Validated extraction request (wraps the existing Bool-returning
    /// authority path so intent callers get a typed result).
    func requestExtractionResolution(characterId: UUID?, tileX: Int, tileY: Int) -> IntentResult {
        requestExtraction(characterId: characterId, tileX: tileX, tileY: tileY)
            ? .accepted
            : .rejected(reason: "extraction conditions not met")
    }

    /// The extraction fly-out animation finished (or its safety net fired):
    /// clear the in-flight flag, notify observers, and finalize the mission.
    /// Exactly once — a second completion signal is rejected and does not
    /// re-run finalization.
    func requestExtractionSequenceCompleted() -> IntentResult {
        guard extractionAnimationInProgress else {
            return .rejected(reason: "no extraction sequence in flight")
        }
        extractionAnimationInProgress = false
        NotificationCenter.default.post(name: .extractionAnimationCompleted, object: nil)
        CombatFlowController.finalizeExtractionAfterAnimation(gameState: self)
        return .accepted
    }
}

// MARK: - Room-entry authority (moved out of BattleScene)

extension GameState {

    /// Reset the per-room first-kill barrier tracking. Authority-side setter
    /// for what BattleScene used to assign directly.
    func resetFirstKillTracking() {
        firstKillProcessedInRoom = false
    }

    /// Sync authority state when the scene finishes (re)loading a room's
    /// visuals after a transition fade.
    func syncRoomLoaded(roomId: String) {
        currentRoomId = roomId
        resetFirstKillTracking()
    }

    /// Apply a room transition to authority state. BattleScene builds the
    /// room's authored spawn lists (a construction job) and hands them here;
    /// every gameplay mutation — squad placement, NG+ extras, roster swap,
    /// room bookkeeping, extraction objective, live tile map — happens inside
    /// authority. The scene then renders from the resulting state
    /// (GameState.enemies), not from its own locals.
    ///
    /// Behavior moved verbatim from BattleScene.performRoomTransition.
    func applyRoomEntry(to targetRoom: Room,
                        enemies newEnemies: [Enemy],
                        pendingSpawns newPendingSpawns: [PendingSpawn],
                        spawnAnchor: SpawnPoint?) {
        var roomEnemies = newEnemies

        // Place the squad NOW that the on-board (delay-0) enemies exist: lay
        // them HORIZONTALLY along the entry row (door target-spawn row),
        // walking right then left, avoiding enemy hexes.
        if let anchor = spawnAnchor {
            let enemyTiles = Set(roomEnemies.map { "\($0.positionX),\($0.positionY)" })
            let livingIdx = playerTeam.indices.filter { playerTeam[$0].isAlive }
            let slots = MissionSetupService.findGroupSpawnSlots(
                map: targetRoom.map,
                anchor: anchor,
                count: livingIdx.count,
                occupied: enemyTiles)
            for (n, i) in livingIdx.enumerated() {
                let p = slots[n]
                playerTeam[i].positionX = p.x
                playerTeam[i].positionY = p.y
                dlog("Room transition: char=\(playerTeam[i].name) x=\(p.x) y=\(p.y)")
            }
        }

        // New Game+ extra enemies for this room (placed on free floor tiles).
        // Only for uncleared rooms — a cleared room stays empty on re-entry.
        if !RoomManager.shared.isRoomCleared(targetRoom.id) {
            let ngOccupied = Set(
                roomEnemies.map { "\($0.positionX),\($0.positionY)" }
                + newPendingSpawns.map { "\($0.enemy.positionX),\($0.enemy.positionY)" }
                + playerTeam.filter { $0.isAlive }.map { "\($0.positionX),\($0.positionY)" }
            )
            roomEnemies.append(contentsOf: MissionSetupService.ngPlusExtraEnemies(
                gameState: self, map: targetRoom.map, occupied: ngOccupied))
        }
        enemies = roomEnemies
        pendingSpawns = newPendingSpawns

        RoomManager.shared.completeTransition(to: targetRoom)
        currentRoomId = targetRoom.id
        resetFirstKillTracking()

        // Recompute extraction objective for the room we just entered.
        // Priority:
        // 1) explicit room extractionPoint
        // 2) extraction tile embedded in map
        // 3) first room connection trigger tile (fallback objective)
        if let extraction = targetRoom.extractionPoint {
            extractionX = extraction.x
            extractionY = extraction.y
            if RoomManager.shared.isExtractionActive(in: targetRoom) {
                addLog("Extraction active at (\(extraction.x), \(extraction.y))")
            } else {
                addLog("Clear this room to activate extraction.")
            }
        } else if let mapExtraction = GameState.firstExtractionTile(in: targetRoom.map) {
            extractionX = mapExtraction.x
            extractionY = mapExtraction.y
            if RoomManager.shared.isExtractionActive(in: targetRoom) {
                addLog("Extraction active at (\(mapExtraction.x), \(mapExtraction.y))")
            } else {
                addLog("Clear this room to activate extraction.")
            }
        } else if let firstConn = targetRoom.connections.first {
            extractionX = firstConn.triggerTileX
            extractionY = firstConn.triggerTileY
            addLog("Find a way through to: \(firstConn.targetRoomId)")
        }

        // Update tiles for enemy pathfinding, then re-flatten any cover the
        // player already destroyed in this room (barrels/crates), so cover
        // math and walkability keep reading the destroyed state on re-entry.
        updateTilesForCurrentRoom(targetRoom.map)
        applyDestroyedCoverToCurrentTiles(roomId: targetRoom.id)
    }

    /// First extraction tile embedded in a room's map, if any.
    /// (Moved from BattleScene so room-entry authority owns the lookup.)
    static func firstExtractionTile(in map: [[Int]]) -> SpawnPoint? {
        for (y, row) in map.enumerated() {
            for (x, raw) in row.enumerated() where raw == TileType.extraction.rawValue {
                return SpawnPoint(x: x, y: y)
            }
        }
        return nil
    }
}
