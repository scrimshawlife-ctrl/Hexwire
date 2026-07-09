import Foundation

// MARK: - ReinforcementService
//
// When a player team clears every enemy from a room, a single wave of
// reinforcements is queued to arrive **2 enemy phases** later. Existing
// `pendingSpawns` plumbing handles the actual spawn; this service just builds
// the wave, picks placement tiles, and feeds it into `gameState.pendingSpawns`.
//
// Constraints:
// • Multi-room missions only — single-room missions end via the assault
//   victory path in `CombatFlowController.checkCombatEnd` before this fires.
// • One wave per room (tracked via RoomManager).
// • Skipped after `areAllRoomsCleared` (don't spawn into the extraction lap).
//
// Caller contract: invoke from `CombatFlowController.enemyPhase` right after
// `processDelayedSpawns`. If this returns true, the room should NOT be
// marked cleared yet — the door stays locked until the new wave is also
// killed and a subsequent enemy phase finds nothing pending.
//
@MainActor
enum ReinforcementService {

    /// 2 enemy phases of warning before reinforcements arrive.
    private static let reinforcementDelayPhases = 2

    /// Seeded RNG (SplitMix64) for wave composition + placement. Seeding off
    /// `missionAttemptId` means every ATTEMPT rolls different waves while a
    /// single attempt stays deterministic (reproducible when debugging a
    /// report). The old raw-LCG-off-phase-count formula had no per-attempt
    /// input at all, so every replay of a room produced the IDENTICAL wave —
    /// one of the few places the game could cheaply gain run-to-run variance.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func waveRNG(gameState: GameState, roomIdx: Int) -> SplitMix64 {
        SplitMix64(seed: UInt64(bitPattern: Int64(gameState.missionAttemptId)) &* 0x9E37_79B9_7F4A_7C15
                       &+ UInt64(max(0, gameState.enemyPhaseCount)) &* 0xBF58_476D_1CE4_E5B9
                       &+ UInt64(max(0, roomIdx)))
    }

    /// Pool of archetype types eligible for reinforcement waves. Mix of
    /// classic + new specialists from TurnManager.swift.
    private static let archetypePool: [String] = [
        "guard", "drone", "sniper", "bruiser", "spider", "riot"
    ]

    /// Queue a reinforcement wave for the current room, if eligible.
    /// Returns true when a wave is queued — caller defers `onRoomCleared`.
    @discardableResult
    static func tryDeployReinforcements(gameState: GameState) -> Bool {
        guard let mission = RoomManager.shared.currentMission else { return false }
        guard let currentRoom = RoomManager.shared.currentRoom else { return false }
        // Don't punish the player at the end of the mission.
        guard !RoomManager.shared.areAllRoomsCleared else { return false }
        // One wave per room.
        guard !RoomManager.shared.haveReinforcementsBeenDeployed(in: currentRoom.id) else {
            return false
        }
        // Never ambush a room the player already CLEARED — the empty-room
        // enemy phase runs every round, and queueing a wave post-clear
        // re-locked the door on a player who just lingered one extra turn
        // (2026-06-12 playtest: trapped in M1 room_0). Waves are pressure
        // for rooms still contested, not punishment for waiting.
        guard !RoomManager.shared.isRoomCleared(currentRoom.id) else { return false }
        // Don't spawn during a TPK / ongoing combat-end.
        guard !gameState.combatEnded else { return false }
        guard !gameState.livingPlayers.isEmpty else { return false }

        // Pick a wave size scaled by room index — early rooms get 1, later
        // rooms get 2.
        let roomIdx = mission.rooms.firstIndex(where: { $0.id == currentRoom.id }) ?? 0
        let waveSize = (roomIdx >= 1) ? 2 : 1

        var wave: [Enemy] = []
        var occupied = Set(gameState.playerTeam.filter(\.isAlive)
            .map { "\($0.positionX),\($0.positionY)" })
        var rng = waveRNG(gameState: gameState, roomIdx: roomIdx)

        var lastArchetype: String? = nil
        for _ in 0..<waveSize {
            // Seeded-random pick, re-rolled once on an immediate repeat so a
            // 2-unit wave leans toward varied roles instead of twins.
            var archetypeKey = archetypePool.randomElement(using: &rng) ?? "guard"
            if archetypeKey == lastArchetype {
                archetypeKey = archetypePool.randomElement(using: &rng) ?? archetypeKey
            }
            lastArchetype = archetypeKey

            let enemy: Enemy
            switch archetypeKey {
            case "guard":   enemy = Enemy.corpGuard()
            case "drone":   enemy = Enemy.securityDrone()
            case "sniper":  enemy = Enemy.sniper()
            case "bruiser": enemy = Enemy.bruiser()
            case "spider":  enemy = Enemy.spiderDrone()
            case "riot":    enemy = Enemy.riotTrooper()
            default:        enemy = Enemy.corpGuard()
            }
            // Reinforcements bypass makeEnemy(), so apply NG+ durability/stat
            // scaling here too — otherwise mid-room waves stay tier-0 weak
            // while every initial spawn in the room is scaled.
            NGPlusStore.shared.scaleForTier(enemy)

            if let (x, y) = pickReinforcementTile(gameState: gameState, occupied: occupied, using: &rng) {
                enemy.positionX = x
                enemy.positionY = y
                occupied.insert("\(x),\(y)")
            } else {
                // Fall back to a corner; processDelayedSpawns will still add the
                // enemy. Avoids returning false which would unlock the door.
                enemy.positionX = 1
                enemy.positionY = 1
            }
            wave.append(enemy)
        }

        let dueAt = gameState.enemyPhaseCount + reinforcementDelayPhases
        for e in wave {
            gameState.pendingSpawns.append(GameState.PendingSpawn(enemy: e, delayRounds: dueAt))
        }
        RoomManager.shared.markReinforcementsDeployed(in: currentRoom.id)

        // The kill path may have already marked the room cleared (door open)
        // before this wave was queued — re-lock so leaving during the ETA
        // can't strand the wave forever (the deployed flag stays set, so it
        // would never re-queue).
        if RoomManager.shared.unmarkCurrentRoomCleared() {
            gameState.addLog("🔒 Door re-locked — incoming hostiles.")
        }

        let preview = wave.map(\.name).joined(separator: ", ")
        gameState.addLog("⚠️ Hostile reinforcements detected — ETA 2 rounds (\(preview))")
        return true
    }

    /// Find a walkable tile far from every living player. Falls back to any
    /// walkable tile on the map if no "far" tile exists. Picks RANDOMLY
    /// (seeded) among all qualifying far tiles — the old best-distance scan
    /// always chose the same corner, so reinforcements entered from an
    /// identical spot on every replay.
    private static func pickReinforcementTile(
        gameState: GameState,
        occupied: Set<String>,
        using rng: inout SplitMix64
    ) -> (Int, Int)? {
        let tiles = gameState.currentMissionTiles
        guard !tiles.isEmpty else { return nil }
        let height = tiles.count
        let width = tiles.first?.count ?? 0
        let wallRaw = TileType.wall.rawValue

        var farCandidates: [(Int, Int)] = []
        var walkable: [(Int, Int)] = []

        for y in 0..<height {
            for x in 0..<width {
                guard x < tiles[y].count else { continue }
                let raw = tiles[y][x]
                guard raw != wallRaw else { continue }
                let key = "\(x),\(y)"
                if occupied.contains(key) { continue }
                if gameState.enemies.contains(where: { $0.positionX == x && $0.positionY == y }) {
                    continue
                }
                walkable.append((x, y))
                if gameState.distanceToNearestPlayer(x: x, y: y) >= 5 {
                    farCandidates.append((x, y))
                }
            }
        }
        return farCandidates.randomElement(using: &rng) ?? walkable.randomElement(using: &rng)
    }
}
