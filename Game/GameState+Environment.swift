import Foundation

// Extracted from GameState.swift (WP5 decomposition) — pure move,
// same methods and names. GameState remains the single authority;
// this file only reduces the main file's responsibility span.

extension GameState {

    // MARK: - Destructible Cover & Explosive Barrels

    /// Convert a COVER tile to floor mid-combat and keep every consumer in
    /// sync: the LIVE pathfinding/cover map mutates immediately (so walkability
    /// and coverBetween see floor on the very next roll), the destruction is
    /// recorded per-room (so re-entering the room doesn't resurrect the crate
    /// from JSON — see destroyedCoverByRoom), and `.coverTileDestroyed` tells
    /// BattleScene to swap the tile visuals — the same fade-out + sampled
    /// floor-patch pass the removeOnFirstKill barrier drop uses.
    func destroyCoverTile(x: Int, y: Int) {
        guard y >= 0, y < currentMissionTiles.count,
              x >= 0, x < currentMissionTiles[y].count,
              currentMissionTiles[y][x] == TileType.cover.rawValue else { return }
        currentMissionTiles[y][x] = TileType.floor.rawValue
        destroyedCoverByRoom[currentRoomId, default: []].append([x, y])
        NotificationCenter.default.post(
            name: .coverTileDestroyed, object: nil,
            userInfo: ["tiles": [["x": x, "y": y]]]
        )
    }

    /// Re-apply this room's recorded cover destruction to the freshly loaded
    /// tile grid. Room maps rebuild from JSON on every (re)entry, which would
    /// otherwise resurrect blown barrels/splintered crates in the LOGIC map
    /// while the player remembers destroying them. Called by BattleScene right
    /// after updateTilesForCurrentRoom on room transitions.
    func applyDestroyedCoverToCurrentTiles(roomId: String) {
        guard let destroyed = destroyedCoverByRoom[roomId], !destroyed.isEmpty else { return }
        var tiles = currentMissionTiles
        for pair in destroyed where pair.count == 2 {
            let x = pair[0], y = pair[1]
            guard y >= 0, y < tiles.count, x >= 0, x < tiles[y].count else { continue }
            tiles[y][x] = TileType.floor.rawValue
        }
        currentMissionTiles = tiles
    }

    /// EXPLOSIVE BARREL detonation. Any barrel cover tile (live cover == 2 AND
    /// TileMap.isBarrelTile — the same deterministic rule the renderer draws
    /// barrels with) within hex-distance 1 of an AoE impact tile goes up:
    /// 6 physical to EVERY unit (both rosters — friendly fire very much
    /// included) within hex-distance 1 of the barrel, each with its own soak
    /// roll, then the tile converts to floor/rubble.
    ///
    /// ONE PASS ONLY — deliberately: all triggered barrels are collected
    /// BEFORE any of them detonate, and a detonation does NOT re-scan for
    /// barrels caught in ITS blast. No chain reactions; a Fireball into a
    /// barrel farm is one simultaneous boom, not a room-clearing cascade.
    ///
    /// Call sites: Fireball (SpellResolver), the player grenade
    /// (throwGrenade), and the grenadier's lob (EnemyAI).
    func detonateBarrelsNear(impactTiles: [(x: Int, y: Int)]) {
        guard !impactTiles.isEmpty else { return }
        // Collect every live barrel within 1 of any impact tile (deduped).
        var barrels: [(x: Int, y: Int)] = []
        for (y, row) in currentMissionTiles.enumerated() {
            for (x, raw) in row.enumerated() {
                guard raw == TileType.cover.rawValue, TileMap.isBarrelTile(x: x, y: y) else { continue }
                guard impactTiles.contains(where: {
                    hexDistance(x1: $0.x, y1: $0.y, x2: x, y2: y) <= 1
                }) else { continue }
                barrels.append((x: x, y: y))
            }
        }
        guard !barrels.isEmpty else { return }

        for barrel in barrels {
            addLog("🛢💥 The chemical barrels at (\(barrel.x),\(barrel.y)) DETONATE!")
            // Reuse the fireball explosion VFX (blast bloom + keyed screen
            // shake) — BattleScene already listens for this and it reads
            // exactly like an explosion at a tile, which is what this is.
            NotificationCenter.default.post(
                name: .fireballEffect, object: nil,
                userInfo: ["x": barrel.x, "y": barrel.y]
            )
            // Tile becomes rubble (floor). Mutating BEFORE the damage pass
            // also means a runner's cover dice never count the barrel that
            // is currently exploding in their face.
            destroyCoverTile(x: barrel.x, y: barrel.y)

            let blastDamage = 6
            // Players in the blast — per-unit soak, same dice conventions as
            // the grenade (BOD+armor pool vs the flat blast damage).
            for runner in playerTeam where runner.isAlive {
                guard hexDistance(x1: runner.positionX, y1: runner.positionY,
                                  x2: barrel.x, y2: barrel.y) <= 1 else { continue }
                let soak = DiceEngine.roll(pool: max(0, runner.computeDerived().soak)).hits
                let dmg = max(0, blastDamage - soak)
                if dmg > 0 {
                    runner.takeDamage(amount: dmg, isStun: false)
                    HapticsManager.shared.playerDamaged()
                    addLog("  → \(runner.name) caught in the blast: \(blastDamage)P - \(soak) soak = \(dmg) dmg. (HP \(runner.currentHP)/\(runner.maxHP))")
                    NotificationCenter.default.post(name: .characterHit, object: nil,
                        userInfo: ["characterId": runner.id.uuidString, "damage": dmg])
                    if !runner.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: runner) }
                } else {
                    addLog("  → \(runner.name) shrugs off the barrel blast.")
                }
            }
            // Enemies in the blast — kills route through the environment
            // pipeline (bounty pays, no runner XP: the barrel landed it).
            for foe in enemies where foe.isAlive {
                guard hexDistance(x1: foe.positionX, y1: foe.positionY,
                                  x2: barrel.x, y2: barrel.y) <= 1 else { continue }
                let soak = DiceEngine.roll(pool: max(0, foe.computeDerived().soak)).hits
                let dmg = max(0, blastDamage - soak)
                if dmg > 0 {
                    foe.takeDamage(amount: dmg, isStun: false)
                    addLog("  → \(foe.name) caught in the blast: \(blastDamage)P - \(soak) soak = \(dmg) dmg. (\(foe.currentHP)/\(foe.maxHP) HP)")
                    NotificationCenter.default.post(name: .enemyHit, object: nil,
                        userInfo: ["enemyId": foe.id.uuidString, "damage": dmg, "outcome": "hit"])
                    if !foe.isAlive { handleEnemyKilledByEnvironment(foe, cause: "barrel detonation") }
                } else {
                    addLog("  → \(foe.name) soaks the barrel blast.")
                    NotificationCenter.default.post(name: .enemyHit, object: nil,
                        userInfo: ["enemyId": foe.id.uuidString, "damage": 0, "outcome": "soak"])
                }
            }
        }
    }

    /// DESTRUCTIBLE COVER on ranged fire: after a ranged attack that traced
    /// through ≥1 cover tile resolves, 25% chance the cover tile NEAREST THE
    /// TARGET degrades to floor. Called AFTER the attack's dice are rolled —
    /// this shot still enjoyed the cover bonus; the NEXT one won't.
    /// Barrel tiles that degrade this way just become floor with NO
    /// detonation — stray bullets nick and topple them, they don't ignite
    /// them (only real AoE blasts set them off, see detonateBarrelsNear).
    func maybeDegradeCoverAlongShot(fromX: Int, fromY: Int, toX: Int, toY: Int) {
        let coverTiles = CombatMechanics.coverTilesBetween(
            tiles: currentMissionTiles,
            fromX: fromX, fromY: fromY, toX: toX, toY: toY)
        guard !coverTiles.isEmpty else { return }
        guard Double.random(in: 0..<1) < 0.25 else { return }
        // ONE tile degrades — the one nearest the target end of the line
        // (that's where the bulk of the incoming fire chews).
        guard let hit = coverTiles.min(by: {
            hexDistance(x1: $0.x, y1: $0.y, x2: toX, y2: toY) <
            hexDistance(x1: $1.x, y1: $1.y, x2: toX, y2: toY)
        }) else { return }
        if TileMap.isBarrelTile(x: hit.x, y: hit.y) {
            addLog("🛢 Stray rounds topple the barrels at (\(hit.x),\(hit.y)) — that cover is gone!")
        } else {
            addLog("📦 The crate at (\(hit.x),\(hit.y)) splinters apart — that cover is gone!")
        }
        destroyCoverTile(x: hit.x, y: hit.y)
    }

}
