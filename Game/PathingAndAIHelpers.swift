import Foundation

@MainActor
struct PathingAndAIHelpers {

    static func hexNeighbors(gameState: GameState, x: Int, y: Int) -> [(Int, Int)] {
        if x % 2 == 0 {
            return [(x,y-1),(x,y+1),(x-1,y-1),(x-1,y),(x+1,y-1),(x+1,y)]
        } else {
            return [(x,y-1),(x,y+1),(x-1,y),(x-1,y+1),(x+1,y),(x+1,y+1)]
        }
    }

    static func hexAdjacent(gameState: GameState, x1: Int, y1: Int, x2: Int, y2: Int) -> Bool {
        hexNeighbors(gameState: gameState, x: x1, y: y1).contains { $0.0 == x2 && $0.1 == y2 }
    }

    static func hexDistance(gameState: GameState, x1: Int, y1: Int, x2: Int, y2: Int) -> Int {
        let cx1 = x1
        let cz1 = y1 - (x1 - (x1 & 1)) / 2
        let cy1 = -cx1 - cz1
        let cx2 = x2
        let cz2 = y2 - (x2 - (x2 & 1)) / 2
        let cy2 = -cx2 - cz2
        return max(abs(cx1 - cx2), abs(cy1 - cy2), abs(cz1 - cz2))
    }

    static func tileWalkable(gameState: GameState, x: Int, y: Int, excluding enemyId: UUID) -> Bool {
        let h = gameState.currentMissionTiles.isEmpty ? 14 : gameState.currentMissionTiles.count
        guard x >= 0, x < TileMap.mapWidth, y >= 0, y < h else { return false }
        let playerBlocking = gameState.playerTeam.contains { $0.isAlive && $0.positionX == x && $0.positionY == y }
        if playerBlocking { return false }
        let enemyBlocking = gameState.enemies.contains { $0.isAlive && $0.id != enemyId && $0.positionX == x && $0.positionY == y }
        if enemyBlocking { return false }
        guard !gameState.currentMissionTiles.isEmpty, y < gameState.currentMissionTiles.count, x < gameState.currentMissionTiles[y].count else { return true }
        let tileType = gameState.currentMissionTiles[y][x]
        return tileType != 1
    }

    static func tileWalkableForHealer(gameState: GameState, x: Int, y: Int, excluding enemyId: UUID) -> Bool {
        let h = gameState.currentMissionTiles.isEmpty ? 14 : gameState.currentMissionTiles.count
        guard x >= 0, x < TileMap.mapWidth, y >= 0, y < h else { return false }
        let playerBlocking = gameState.playerTeam.contains { $0.isAlive && $0.positionX == x && $0.positionY == y }
        if playerBlocking { return false }
        guard !gameState.currentMissionTiles.isEmpty, y < gameState.currentMissionTiles.count, x < gameState.currentMissionTiles[y].count else { return true }
        let tileType = gameState.currentMissionTiles[y][x]
        return tileType != 1
    }

    /// Cube coordinates for an odd-q offset hex (matches TileMap layout).
    private struct CubeCoord {
        let x: Double, y: Double, z: Double
    }

    private static func offsetToCube(_ col: Int, _ row: Int) -> CubeCoord {
        let x = Double(col)
        let z = Double(row) - Double(col - (col & 1)) / 2.0
        let y = -x - z
        return CubeCoord(x: x, y: y, z: z)
    }

    private static func cubeRoundToOffset(_ c: CubeCoord) -> (Int, Int) {
        var rx = (c.x).rounded()
        var ry = (c.y).rounded()
        var rz = (c.z).rounded()
        let xDiff = abs(rx - c.x)
        let yDiff = abs(ry - c.y)
        let zDiff = abs(rz - c.z)
        if xDiff > yDiff && xDiff > zDiff {
            rx = -ry - rz
        } else if yDiff > zDiff {
            ry = -rx - rz
        } else {
            rz = -rx - ry
        }
        let col = Int(rx)
        let row = Int(rz) + (col - (col & 1)) / 2
        return (col, row)
    }

    /// Hex-aware line of sight check. Walks the actual hex line (cube-coord lerp,
    /// round-to-nearest-hex) between source and target instead of using 2D
    /// Bresenham — that earlier algorithm clipped corners of wall hexes and
    /// reported false-positive blocks for shots that visually had a clear lane.
    /// Only blocks if a wall hex (TileType.wall = 1) sits directly on the
    /// straight hex line between source and target.
    static func isLineBlockedByWall(gameState: GameState, fromX sx: Int, fromY sy: Int, toX dx: Int, toY dy: Int) -> Bool {
        if sx == dx && sy == dy { return false }
        let a = offsetToCube(sx, sy)
        let b = offsetToCube(dx, dy)
        // Hex distance in cube coords = max of axial diffs
        let hexDist = max(
            abs(a.x - b.x),
            abs(a.y - b.y),
            abs(a.z - b.z)
        )
        let steps = max(1, Int(hexDist))
        // Sample every 1/steps along the line, skipping endpoints
        for i in 1..<steps {
            let t = Double(i) / Double(steps)
            // Slight nudge along the line so samples that fall exactly on a
            // hex edge don't ambiguously snap to the wall side. This makes
            // marginal "corner-clip" shots succeed instead of being blocked.
            let nudgedT = t + 1e-6
            let lerped = CubeCoord(
                x: a.x * (1.0 - nudgedT) + b.x * nudgedT,
                y: a.y * (1.0 - nudgedT) + b.y * nudgedT,
                z: a.z * (1.0 - nudgedT) + b.z * nudgedT
            )
            let (cx, cy) = cubeRoundToOffset(lerped)
            // Bounds check
            guard cx >= 0, cx < TileMap.mapWidth, cy >= 0 else { continue }
            let tiles = gameState.currentMissionTiles
            guard cy < tiles.count, cx < tiles[cy].count else { continue }
            // Skip endpoints — caller is checking if intermediate hexes block.
            if cx == sx && cy == sy { continue }
            if cx == dx && cy == dy { continue }
            if tiles[cy][cx] == TileType.wall.rawValue {
                return true
            }
        }
        return false
    }

    /// True "next-tile" BFS — returns the FIRST step from `enemy` toward
    /// `target`, not the destination adjacent tile. Reconstructs the path via
    /// parent tracking and returns path[1]. Used by boss pursuit AI so each
    /// move-budget iteration steps the boss ONE tile (visible per-tile
    /// pursuit) instead of teleporting straight to the player's elbow.
    ///
    /// Returns nil if the enemy is already adjacent or no path exists.
    static func bfsNextStep(gameState: GameState, from enemy: Enemy, toward target: Character) -> (Int, Int)? {
        let sx = enemy.positionX, sy = enemy.positionY
        let gx = target.positionX, gy = target.positionY
        if hexAdjacent(gameState: gameState, x1: sx, y1: sy, x2: gx, y2: gy) { return nil }

        // BFS with parent map for path reconstruction.
        var parent: [String: (Int, Int)] = [:]
        var queue: [(Int, Int)] = [(sx, sy)]
        var visited: Set<String> = ["\(sx),\(sy)"]
        var i = 0
        var goalAdjacent: (Int, Int)? = nil

        while i < queue.count, goalAdjacent == nil {
            let cur = queue[i]; i += 1
            for (nx, ny) in hexNeighbors(gameState: gameState, x: cur.0, y: cur.1) {
                let k = "\(nx),\(ny)"
                guard !visited.contains(k) else { continue }
                guard tileWalkable(gameState: gameState, x: nx, y: ny, excluding: enemy.id) else { continue }
                visited.insert(k)
                parent[k] = cur
                if hexAdjacent(gameState: gameState, x1: nx, y1: ny, x2: gx, y2: gy) || (nx == gx && ny == gy) {
                    goalAdjacent = (nx, ny)
                    break
                }
                queue.append((nx, ny))
            }
        }

        guard let goal = goalAdjacent else {
            // No reachable tile adjacent to target — fall back to the best
            // immediate neighbor by raw hex distance.
            let neighbors = hexNeighbors(gameState: gameState, x: sx, y: sy)
                .filter { tileWalkable(gameState: gameState, x: $0.0, y: $0.1, excluding: enemy.id) }
                .sorted { hexDistance(gameState: gameState, x1: $0.0, y1: $0.1, x2: gx, y2: gy) <
                          hexDistance(gameState: gameState, x1: $1.0, y1: $1.1, x2: gx, y2: gy) }
            return neighbors.first
        }

        // Walk back from `goal` via parent map until we're one step from start.
        var cur = goal
        while let par = parent["\(cur.0),\(cur.1)"], par != (sx, sy) {
            cur = par
        }
        return cur
    }

    static func bfsPathfind(gameState: GameState, from enemy: Enemy, toward target: Character) -> (Int, Int)? {
        let sx = enemy.positionX, sy = enemy.positionY
        let gx = target.positionX, gy = target.positionY
        if hexAdjacent(gameState: gameState, x1: sx, y1: sy, x2: gx, y2: gy) { return nil }

        struct Node { let x: Int; let y: Int }
        var queue: [Node] = [Node(x: sx, y: sy)]
        var visited: Set<String> = ["\(sx),\(sy)"]
        var i = 0

        while i < queue.count {
            let cur = queue[i]; i += 1
            for (nx, ny) in hexNeighbors(gameState: gameState, x: cur.x, y: cur.y) {
                let k = "\(nx),\(ny)"
                guard !visited.contains(k), tileWalkable(gameState: gameState, x: nx, y: ny, excluding: enemy.id) else { continue }
                visited.insert(k)
                if hexAdjacent(gameState: gameState, x1: nx, y1: ny, x2: gx, y2: gy) || (nx == gx && ny == gy) { return (nx, ny) }
                queue.append(Node(x: nx, y: ny))
            }
        }
        let neighbors = hexNeighbors(gameState: gameState, x: sx, y: sy)
        let sorted = neighbors.filter { tileWalkable(gameState: gameState, x: $0.0, y: $0.1, excluding: enemy.id) }
            .sorted { hexDistance(gameState: gameState, x1: $0.0, y1: $0.1, x2: gx, y2: gy) < hexDistance(gameState: gameState, x1: $1.0, y1: $1.1, x2: gx, y2: gy) }
        return sorted.first
    }

    static func bfsPathfindDrone(gameState: GameState, from enemy: Enemy, towardX gx: Int, y gy: Int) -> (Int, Int)? {
        let sx = enemy.positionX, sy = enemy.positionY
        if hexAdjacent(gameState: gameState, x1: sx, y1: sy, x2: gx, y2: gy) { return nil }

        struct Node { let x: Int; let y: Int }
        var queue: [Node] = [Node(x: sx, y: sy)]
        var visited: Set<String> = ["\(sx),\(sy)"]
        var i = 0

        while i < queue.count {
            let cur = queue[i]; i += 1
            for (nx, ny) in hexNeighbors(gameState: gameState, x: cur.x, y: cur.y) {
                let k = "\(nx),\(ny)"
                guard !visited.contains(k), tileWalkable(gameState: gameState, x: nx, y: ny, excluding: enemy.id) else { continue }
                visited.insert(k)
                if hexAdjacent(gameState: gameState, x1: nx, y1: ny, x2: gx, y2: gy) || (nx == gx && ny == gy) { return (nx, ny) }
                queue.append(Node(x: nx, y: ny))
            }
        }
        let neighbors = hexNeighbors(gameState: gameState, x: sx, y: sy)
        let sorted = neighbors.filter { tileWalkable(gameState: gameState, x: $0.0, y: $0.1, excluding: enemy.id) }
            .sorted { hexDistance(gameState: gameState, x1: $0.0, y1: $0.1, x2: gx, y2: gy) < hexDistance(gameState: gameState, x1: $1.0, y1: $1.1, x2: gx, y2: gy) }
        return sorted.first
    }

    static func bfsPathfindToWounded(gameState: GameState, from enemy: Enemy, toward target: Enemy) -> (Int, Int)? {
        let sx = enemy.positionX, sy = enemy.positionY
        let gx = target.positionX, gy = target.positionY
        if hexAdjacent(gameState: gameState, x1: sx, y1: sy, x2: gx, y2: gy) { return nil }

        struct Node { let x: Int; let y: Int }
        var queue: [Node] = [Node(x: sx, y: sy)]
        var visited: Set<String> = ["\(sx),\(sy)"]
        var i = 0

        while i < queue.count {
            let cur = queue[i]; i += 1
            for (nx, ny) in hexNeighbors(gameState: gameState, x: cur.x, y: cur.y) {
                let k = "\(nx),\(ny)"
                guard !visited.contains(k), tileWalkableForHealer(gameState: gameState, x: nx, y: ny, excluding: enemy.id) else { continue }
                visited.insert(k)
                if hexAdjacent(gameState: gameState, x1: nx, y1: ny, x2: gx, y2: gy) || (nx == gx && ny == gy) { return (nx, ny) }
                queue.append(Node(x: nx, y: ny))
            }
        }
        let neighbors = hexNeighbors(gameState: gameState, x: sx, y: sy)
        let sorted = neighbors.filter { tileWalkableForHealer(gameState: gameState, x: $0.0, y: $0.1, excluding: enemy.id) }
            .sorted { hexDistance(gameState: gameState, x1: $0.0, y1: $0.1, x2: gx, y2: gy) < hexDistance(gameState: gameState, x1: $1.0, y1: $1.1, x2: gx, y2: gy) }
        return sorted.first
    }

    static func bestRetreatTile(gameState: GameState, for enemy: Enemy, awayFrom target: Character) -> (Int, Int) {
        var candidates: [(Int, Int, Int)] = []

        for (nx, ny) in hexNeighbors(gameState: gameState, x: enemy.positionX, y: enemy.positionY) {
            if tileWalkable(gameState: gameState, x: nx, y: ny, excluding: enemy.id) {
                let newDist = hexDistance(gameState: gameState, x1: nx, y1: ny, x2: target.positionX, y2: target.positionY)
                candidates.append((nx, ny, newDist))
            }
        }

        if let best = candidates.max(by: { $0.2 < $1.2 }) {
            return (best.0, best.1)
        }
        return (enemy.positionX, enemy.positionY)
    }

    static func findWoundedAlly(gameState: GameState, for enemy: Enemy) -> Enemy? {
        let wounded = gameState.enemies.filter { ally in
            guard ally.id != enemy.id, ally.isAlive else { return false }
            let dist = hexDistance(gameState: gameState, x1: ally.positionX, y1: ally.positionY, x2: enemy.positionX, y2: enemy.positionY)
            let isWounded = Double(ally.currentHP) / Double(ally.maxHP) < 0.75
            return dist <= 5 && isWounded
        }
        return wounded.min { a, b in
            Double(a.currentHP) / Double(a.maxHP) < Double(b.currentHP) / Double(b.maxHP)
        }
    }

    static func distanceToNearestPlayer(gameState: GameState, x: Int, y: Int) -> Int {
        let living = gameState.playerTeam.filter { $0.isAlive }
        guard !living.isEmpty else { return Int.max }
        var best = Int.max
        for player in living {
            let distance = abs(player.positionX - x) + abs(player.positionY - y)
            if distance < best {
                best = distance
            }
        }
        return best
    }

    static func findNextLivingCharacter(gameState: GameState, after index: Int) -> Character? {
        for i in index..<gameState.playerTeam.count {
            if gameState.playerTeam[i].isAlive { return gameState.playerTeam[i] }
        }
        for i in 0..<index {
            if gameState.playerTeam[i].isAlive { return gameState.playerTeam[i] }
        }
        return nil
    }
}
