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

        for i in 0..<waveSize {
            // Rotate through pool deterministically per spawn so each wave
            // contains varied roles instead of N identical units.
            let seed = (gameState.enemyPhaseCount &+ roomIdx &+ i)
            let archetypeKey = archetypePool[(seed &* 1_103_515_245 &+ 12345) % archetypePool.count]

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

            if let (x, y) = pickReinforcementTile(gameState: gameState, occupied: occupied) {
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

        let preview = wave.map(\.name).joined(separator: ", ")
        gameState.addLog("⚠️ Hostile reinforcements detected — ETA 2 rounds (\(preview))")
        return true
    }

    /// Find a walkable tile far from every living player. Falls back to any
    /// walkable tile on the map if no "far" tile exists.
    private static func pickReinforcementTile(
        gameState: GameState,
        occupied: Set<String>
    ) -> (Int, Int)? {
        let tiles = gameState.currentMissionTiles
        guard !tiles.isEmpty else { return nil }
        let height = tiles.count
        let width = tiles.first?.count ?? 0
        let wallRaw = TileType.wall.rawValue

        var bestFar: (Int, Int)? = nil
        var bestFarDist = -1
        var anyWalkable: (Int, Int)? = nil

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
                anyWalkable = (x, y)
                let d = gameState.distanceToNearestPlayer(x: x, y: y)
                if d >= 5, d > bestFarDist {
                    bestFarDist = d
                    bestFar = (x, y)
                }
            }
        }
        return bestFar ?? anyWalkable
    }
}
