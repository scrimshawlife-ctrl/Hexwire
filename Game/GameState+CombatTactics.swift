import Foundation

// Extracted from GameState.swift (WP5 decomposition) — pure move,
// same methods and names. GameState remains the single authority;
// this file only reduces the main file's responsibility span.

extension GameState {

    // MARK: - Enemy Overwatch (sniper / turret reaction fire)

    /// Bank an ENEMY overwatch shot — the inverse of performOverwatch. Called
    /// from the sniper/turret AI branches when they end their turn with no
    /// target in range/LOS. The log line is the player's warning: moving in
    /// the open next round eats a reaction shot.
    func bankEnemyOverwatch(for enemy: Enemy, pool: Int) {
        enemyOverwatchers[enemy.id] = pool
        addLog("🎯 \(enemy.name) settles into OVERWATCH — holding fire on any movement!")
    }

    /// Reaction-fire range for a banked enemy — mirrors each archetype's
    /// normal engagement range (sniper lane 8 / turret arc 6) so overwatch
    /// never reaches farther than a deliberate shot could.
    private func enemyOverwatchRange(for enemy: Enemy) -> Int {
        enemy.archetype.lowercased() == "sniper" ? 8 : 6
    }

    /// Fire banked ENEMY overwatch at a player who just committed a MOVE.
    /// Called from CombatFlowController.moveCharacter (the movement commit
    /// path — DEFEND/attack/other actions never trigger this, movement only).
    /// Each banked enemy with range + clear LOS fires ONE reaction shot, then
    /// its bank is spent for the round. Same conventions as the player-side
    /// fireOverwatchShot: net hits HALVED (reaction-fire penalty), soak minus
    /// AP, and the moving runner keeps their cover dice — ducking tile-to-tile
    /// behind crates is still safer than sprinting the open lane.
    func fireEnemyOverwatchShots(atMovingPlayer char: Character) {
        guard !enemyOverwatchers.isEmpty else { return }
        for (enemyId, pool) in enemyOverwatchers {
            // The mover can die to the first reaction shot — later banks stay
            // armed for the next runner rather than firing at a corpse.
            guard char.isAlive else { return }
            // Stale ids (banker died to the player phase, or leftovers from a
            // previous mission's roster) simply never match — inert entries.
            guard let shooter = enemies.first(where: { $0.id == enemyId && $0.isAlive }) else {
                enemyOverwatchers.removeValue(forKey: enemyId)
                continue
            }
            let dist = hexDistance(x1: shooter.positionX, y1: shooter.positionY,
                                   x2: char.positionX, y2: char.positionY)
            guard dist <= enemyOverwatchRange(for: shooter) else { continue }
            guard !isLineBlockedByWall(fromX: shooter.positionX, fromY: shooter.positionY,
                                       toX: char.positionX, toY: char.positionY) else { continue }

            // The shot is happening — the bank is spent for the round.
            enemyOverwatchers.removeValue(forKey: enemyId)
            addLog("⚡ OVERWATCH! \(shooter.name) reacts to \(char.name)'s movement!")

            // Tracer + muzzle flash — same payload shape as a deliberate enemy shot.
            NotificationCenter.default.post(name: .gunfireEffect, object: nil, userInfo: [
                "fromX": shooter.positionX, "fromY": shooter.positionY,
                "toX": char.positionX, "toY": char.positionY,
                "weaponType": (shooter.equippedWeapon?.type ?? .rifle).rawValue,
                "enemyArchetype": shooter.archetype
            ])

            // Moving runner still defends with their full pool + cover dice
            // read from the LIVE map (a detonated barrel no longer shields).
            let cover = CombatMechanics.coverBetween(
                tiles: currentMissionTiles,
                fromX: shooter.positionX, fromY: shooter.positionY,
                toX: char.positionX, toY: char.positionY)
            let defPool = char.defensePool() + CombatMechanics.coverDefenseBonus(count: cover)
            let atk = DiceEngine.roll(pool: pool)
            let def = DiceEngine.roll(pool: defPool)
            // Reaction fire: halved net hits — same rule as player overwatch.
            let net = max(0, atk.hits - def.hits) / 2
            if net == 0 {
                addLog("→ \(char.name) dives clear of the reaction shot!")
                continue
            }
            let wd = shooter.equippedWeapon?.damage ?? 7
            let ap = shooter.equippedWeapon?.armorPiercing ?? 2
            let soak = DiceEngine.roll(pool: max(0, char.computeDerived().soak - ap)).hits
            let dmg = escalatedIncomingDamage(max(0, wd + net - soak))
            if dmg > 0 {
                char.takeDamage(amount: dmg, isStun: shooter.equippedWeapon?.isStunDamage ?? false)
                HapticsManager.shared.playerDamaged()
                addLog("💥 OVERWATCH hit! \(shooter.name) → \(char.name): \(net) net hits → \(dmg) dmg. (HP \(char.currentHP)/\(char.maxHP))")
                NotificationCenter.default.post(name: .playerHit, object: nil, userInfo: [
                    "playerId": char.id.uuidString, "damage": dmg, "enemyId": shooter.id.uuidString])
                if !char.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: char) }
            } else {
                addLog("→ \(char.name)'s armour holds against the reaction shot!")
            }
        }
    }

    // MARK: - Flanking (enemy → player side)

    /// Flanking penalty for an ENEMY attack against a PLAYER — the symmetric
    /// mirror of the check in CombatFlowController.performAttack. Returns 2
    /// (dice to subtract, callers apply the same min-1 clamp as stun/prone)
    /// when another living enemy is adjacent to the runner on the far side of
    /// the attacker, else 0. Logs the FLANKED! warning so the player learns
    /// the mechanic works against them too and spreads enemies apart.
    /// Lives here (not in Character.defensePool) because the pool computation
    /// has no board context — see the note in defensePool.
    func flankedDefensePenalty(target: Character, attacker: Enemy) -> Int {
        let allies = livingEnemies
            .filter { $0.id != attacker.id }
            .map { (x: $0.positionX, y: $0.positionY) }
        guard CombatMechanics.isFlanked(
            targetX: target.positionX, targetY: target.positionY,
            attackerX: attacker.positionX, attackerY: attacker.positionY,
            allies: allies
        ) else { return 0 }
        addLog("⚔️ FLANKED! \(target.name) is caught in a crossfire (−2 DEF)")
        return 2
    }

    func endTurn() {
        _ = requestEndTurn()
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
        // Authored delayed spawns still queued = the room is NOT clear. The
        // enemy-phase path already checks this; the kill paths didn't, so
        // killing the last visible enemy unlocked the door early and the
        // door transition then silently wiped the queued spawns forever.
        // Pull the stragglers in NOW (they heard the gunfire) — leaving the
        // player locked in an empty room waiting out spawn timers read as
        // a stuck door (2026-06-12 playtest).
        guard pendingSpawns.isEmpty else {
            addLog("…it's not over. More hostiles inbound!")
            pendingSpawns = pendingSpawns.map { PendingSpawn(enemy: $0.enemy, delayRounds: enemyPhaseCount) }
            processDelayedSpawns(enemyPhaseIndex: enemyPhaseCount)
            return
        }

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
                let attempt = missionAttemptId
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self = self else { return }
                    RoomManager.shared.bossPendingRoomIds.remove(room.id)
                    // Stale-mission / wrong-room guard: an abort (or a room
                    // exit) during the 2.5s suspense beat must not drop
                    // AGI-PRIME into whatever is active now. Skipping the
                    // deploy leaves the room uncleared, so the intercept
                    // re-fires when the player returns and re-clears it.
                    guard self.missionAttemptId == attempt,
                          !self.combatEnded,
                          RoomManager.shared.currentRoom?.id == room.id else { return }
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

}
