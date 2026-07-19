import Foundation

/// HexWire TN dice system engine
/// Rolls Xd6, counts hits (5 or 6), handles exploding 6s, detects glitches
struct DiceEngine {

    // MARK: - Roll Result

    struct RollResult {
        let hits: Int
        let glitch: Bool
        let criticalGlitch: Bool
        let rolls: [Int]           // individual die results (including rerolls)
        let originalPool: Int      // original dice pool size
        let netHits: Int           // hits after subtracting TNs for opposed rolls

        var description: String {
            var parts: [String] = []
            parts.append("Rolled \(rolls)")
            parts.append("\(hits) hit\(hits == 1 ? "" : "s")")
            if criticalGlitch {
                parts.append("💥 CRITICAL GLITCH")
            } else if glitch {
                parts.append("⚠️ GLITCH")
            }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - Core Roll

    /// Roll a dice pool against a Target Number
    /// - Parameters:
    ///   - pool: Number of d6 to roll
    ///   - tn: Target Number to beat (each 5 or 6 = 1 hit)
    /// - Returns: RollResult with hits, glitch flags, and full roll breakdown
    static func roll(pool: Int, tn: Int = 4) -> RollResult {
        var rng = SystemRandomNumberGenerator()
        return roll(pool: pool, tn: tn, using: &rng)
    }

    /// Seed-injectable variant of `roll` — same rules, but every die comes
    /// from the caller's RandomNumberGenerator, so a fixed generator produces
    /// a fully reproducible RollResult (deterministic tests, future replays).
    static func roll<G: RandomNumberGenerator>(pool: Int, tn: Int = 4, using rng: inout G) -> RollResult {
        guard pool > 0 else {
            return RollResult(hits: 0, glitch: false, criticalGlitch: false, rolls: [], originalPool: 0, netHits: 0)
        }

        var allRolls: [Int] = []
        var hits = 0
        var ones = 0

        // First roll
        let firstRolls = rollDice(count: pool, using: &rng)
        allRolls.append(contentsOf: firstRolls)

        // Count hits and ones, collect 6s for exploding
        var sixesToReroll: [Int] = []
        for roll in firstRolls {
            if roll >= 5 {
                hits += 1
            }
            if roll == 6 {
                sixesToReroll.append(6)
            }
            if roll == 1 {
                ones += 1
            }
        }

        // Exploding 6s: reroll and add hits
        while !sixesToReroll.isEmpty {
            let rerollCount = sixesToReroll.count
            sixesToReroll.removeAll()
            let rerolls = rollDice(count: rerollCount, using: &rng)
            allRolls.append(contentsOf: rerolls)
            for roll in rerolls {
                if roll >= 5 {
                    hits += 1
                }
                if roll == 6 {
                    sixesToReroll.append(6)
                }
                if roll == 1 {
                    ones += 1
                }
            }
        }

        // Net hits = hits - TNs (for TN-based comparisons)
        // For simple hit-counting, netHits = hits when tn is the threshold
        let netHits = hits // Will be adjusted if we implement opposed rolls

        // Glitch detection: MORE than half the dice show 1s (HexWire 5e
        // rule). Was `>= pool/2` which fired on EXACTLY half — that made
        // small pools (4–6 dice) glitch 15–20% of the time, which felt
        // broken for chars like Sable using a sidearm with a 5-die pool.
        let glitch = ones * 2 > pool

        // Critical glitch: ALL dice show 1s AND no hits — even one hit
        // converts a critical glitch into a regular glitch per the rules.
        let criticalGlitch = ones == pool && pool > 0 && hits == 0

        return RollResult(
            hits: hits,
            glitch: glitch,
            criticalGlitch: criticalGlitch,
            rolls: allRolls,
            originalPool: pool,
            netHits: netHits
        )
    }

    // MARK: - Opposed Roll

    /// Opposed roll: attacker pool vs defender pool
    /// Net hits = attacker's hits - defender's hits
    static func opposedRoll(attackerPool: Int, defenderPool: Int, tn: Int = 4) -> RollResult {
        var rng = SystemRandomNumberGenerator()
        return opposedRoll(attackerPool: attackerPool, defenderPool: defenderPool, tn: tn, using: &rng)
    }

    /// Seed-injectable variant of `opposedRoll` (see `roll(pool:tn:using:)`).
    static func opposedRoll<G: RandomNumberGenerator>(attackerPool: Int, defenderPool: Int, tn: Int = 4, using rng: inout G) -> RollResult {
        let attackRoll = roll(pool: attackerPool, tn: tn, using: &rng)
        let defenseRoll = roll(pool: defenderPool, tn: tn, using: &rng)

        let netHits = max(0, attackRoll.hits - defenseRoll.hits)
        let criticalGlitch = attackRoll.criticalGlitch

        // Glitch on attack side
        let glitch = attackRoll.glitch

        // Combine rolls for audit trail
        var combinedRolls = attackRoll.rolls
        combinedRolls.append(contentsOf: defenseRoll.rolls)

        return RollResult(
            hits: netHits,
            glitch: glitch,
            criticalGlitch: criticalGlitch,
            rolls: combinedRolls,
            originalPool: attackerPool,
            netHits: netHits
        )
    }

    // MARK: - Private Helpers

    /// Roll `count` d6 dice, returning array of results
    private static func rollDice<G: RandomNumberGenerator>(count: Int, using rng: inout G) -> [Int] {
        var results: [Int] = []
        results.reserveCapacity(count)
        for _ in 0..<count {
            results.append(Int.random(in: 1...6, using: &rng))
        }
        return results
    }

    // MARK: - Initiative Roll

    /// Roll initiative: REA + INT + 1d6
    static func rollInitiative(rea: Int, int: Int) -> Int {
        let base = rea + int
        let die = Int.random(in: 1...6)
        return base + die
    }

    // MARK: - Soak Roll

    /// Roll soak: BOD + armor vs TN (default TN 4)
    /// Returns number of damage actually soaked
    static func soakRoll(pool: Int, tn: Int = 4) -> (soaked: Int, rolls: [Int]) {
        let result = roll(pool: pool, tn: tn)
        return (soaked: result.hits, rolls: result.rolls)
    }

    /// Seed-injectable variant of `soakRoll` (see `roll(pool:tn:using:)`).
    static func soakRoll<G: RandomNumberGenerator>(pool: Int, tn: Int = 4, using rng: inout G) -> (soaked: Int, rolls: [Int]) {
        let result = roll(pool: pool, tn: tn, using: &rng)
        return (soaked: result.hits, rolls: result.rolls)
    }
}

// MARK: - Combat Mechanics

/// Stateless helpers for cover detection, hit-preview, and future tactical calculations.
/// Lives in DiceEngine.swift to avoid requiring a separate build-target entry.
struct CombatMechanics {

    // MARK: - Hex Distance (pure, no GameState needed)

    /// Pure odd-q cube distance — the SAME math as PathingAndAIHelpers.hexDistance
    /// (and the inline copy in computeHitPreview below), duplicated here so
    /// stateless helpers like `isFlanked` don't need a GameState instance.
    static func hexDistance(x1: Int, y1: Int, x2: Int, y2: Int) -> Int {
        let z1 = y1 - (x1 - (x1 & 1)) / 2
        let z2 = y2 - (x2 - (x2 & 1)) / 2
        let cy1 = -x1 - z1
        let cy2 = -x2 - z2
        return max(abs(x1 - x2), abs(cy1 - cy2), abs(z1 - z2))
    }

    // MARK: - Flanking

    /// TRUE when the target is caught between the attacker and one of the
    /// attacker's allies — the target defends with 2 fewer dice (applied at
    /// the attack call sites, same min-1 clamp as the stun/prone penalties).
    ///
    /// Rule: an ally of the attacker (living, not the attacker itself) is
    /// ADJACENT to the target (hex-distance 1) AND on the FAR SIDE of it.
    /// "Far side" is deliberately approximated as
    ///     hexDistance(ally, attacker) >= hexDistance(target, attacker)
    /// i.e. the ally is at least as far from the attacker as the target is,
    /// so the target sits roughly BETWEEN them. This is coarser than a true
    /// opposite-hex check (an ally at 90° to the shot at equal range still
    /// counts) but it's cheap, symmetric for both rosters, and reads
    /// correctly in play: hugging the target from the attacker's own side
    /// (ally closer to the attacker than the target is) never flanks.
    ///
    /// `allies` are board positions of the attacker's LIVING teammates,
    /// excluding the attacker — callers filter before passing so this helper
    /// stays type-agnostic (works for Character-vs-Enemy in both directions).
    static func isFlanked(
        targetX: Int, targetY: Int,
        attackerX: Int, attackerY: Int,
        allies: [(x: Int, y: Int)]
    ) -> Bool {
        let attackerToTarget = hexDistance(x1: attackerX, y1: attackerY, x2: targetX, y2: targetY)
        for ally in allies {
            // Ally adjacent to the target…
            guard hexDistance(x1: ally.x, y1: ally.y, x2: targetX, y2: targetY) == 1 else { continue }
            // …and no closer to the attacker than the target is (far side).
            if hexDistance(x1: ally.x, y1: ally.y, x2: attackerX, y2: attackerY) >= attackerToTarget {
                return true
            }
        }
        return false
    }

    // MARK: - Cover System

    /// Walk the Bresenham line between two tile coordinates and count how many
    /// intermediate tiles (exclusive of both endpoints) have tileType == 2 (cover).
    static func coverBetween(
        tiles: [[Int]],
        fromX sx: Int, fromY sy: Int,
        toX dx: Int, toY dy: Int
    ) -> Int {
        guard !tiles.isEmpty else { return 0 }
        var x0 = sx, y0 = sy
        let x1 = dx, y1 = dy
        let absDx = abs(x1 - x0)
        let absDy = abs(y1 - y0)
        let stepX = x0 < x1 ? 1 : -1
        let stepY = y0 < y1 ? 1 : -1
        var err = absDx - absDy
        var count = 0
        while true {
            if !(x0 == sx && y0 == sy) && !(x0 == x1 && y0 == y1) {
                let h = tiles.count
                if y0 >= 0, y0 < h, x0 >= 0, x0 < tiles[y0].count {
                    if tiles[y0][x0] == 2 { count += 1 }
                }
            }
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 > -absDy { err -= absDy; x0 += stepX }
            if e2 < absDx  { err += absDx; y0 += stepY }
        }
        return count
    }

    /// The COORDINATES of every intermediate cover tile on the shooter→target
    /// line — same Bresenham walk as `coverBetween` (which only counts), used
    /// by the destructible-cover roll to pick WHICH tile splinters. Kept as a
    /// separate function rather than changing coverBetween's signature so the
    /// dozen existing count-only call sites stay untouched.
    static func coverTilesBetween(
        tiles: [[Int]],
        fromX sx: Int, fromY sy: Int,
        toX dx: Int, toY dy: Int
    ) -> [(x: Int, y: Int)] {
        guard !tiles.isEmpty else { return [] }
        var x0 = sx, y0 = sy
        let x1 = dx, y1 = dy
        let absDx = abs(x1 - x0)
        let absDy = abs(y1 - y0)
        let stepX = x0 < x1 ? 1 : -1
        let stepY = y0 < y1 ? 1 : -1
        var err = absDx - absDy
        var found: [(x: Int, y: Int)] = []
        while true {
            if !(x0 == sx && y0 == sy) && !(x0 == x1 && y0 == y1) {
                let h = tiles.count
                if y0 >= 0, y0 < h, x0 >= 0, x0 < tiles[y0].count {
                    if tiles[y0][x0] == 2 { found.append((x: x0, y: y0)) }
                }
            }
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 > -absDy { err -= absDy; x0 += stepX }
            if e2 < absDx  { err += absDx; y0 += stepY }
        }
        return found
    }

    /// Cover defense bonus.
    /// Tuned 2026-05 (was 0/+2/+4): the +4 from 2 cover tiles single-handedly
    /// flipped a competent attacker's expected net hits negative — even Lyra's
    /// 10-dice SMG pool was missing through cover. Halved to 0/+1/+2 so cover
    /// matters but isn't an instant attack-shutdown.
    static func coverDefenseBonus(count: Int) -> Int {
        switch count {
        case 0:  return 0
        case 1:  return 1
        default: return 2
        }
    }

    // MARK: - Hit Preview

    struct HitPreview {
        let actionLabel: String
        let weaponName: String
        let targetName: String
        let attackPool: Int
        let defensePool: Int
        let coverBonus: Int
        let estimatedHitChance: Double
        let weaponDamage: Int
        let estimatedDamage: Double
        let blocked: Bool
        let reason: String?
    }

    /// Compute a live hit-preview for display before the player commits to an attack.
    static func computeHitPreview(
        attacker: Character,
        target: Enemy,
        tiles: [[Int]],
        weapon overrideWeapon: Weapon? = nil,
        actionLabel: String = "ATK",
        signalDiceBonus: Int = 0,
        attackerAllies: [(x: Int, y: Int)] = [],
        isBlocked: (Int, Int, Int, Int) -> Bool
    ) -> HitPreview {
        let weapon = overrideWeapon ?? attacker.equippedWeapon ?? Weapon(name: "Fists", type: .unarmed, damage: 3, accuracy: 3, armorPiercing: 0)
        if isBlocked(attacker.positionX, attacker.positionY,
                     target.positionX, target.positionY) {
            return HitPreview(actionLabel: actionLabel, weaponName: weapon.name,
                              targetName: target.name, attackPool: 0, defensePool: 0, coverBonus: 0,
                              estimatedHitChance: 0, weaponDamage: 0, estimatedDamage: 0,
                              blocked: true, reason: "Wall blocks LOS")
        }
        let skill: SkillKey = (weapon.type == .blade || weapon.type == .unarmed) ? .blades : .firearms
        // Match performAttack: include weapon-accuracy smartlink bonus.
        let weaponBonus = max(0, weapon.accuracy / 3)
        // Match performAttack: ranged falloff on the ATTACK POOL (1d per
        // tile past effective range, cap 4) and the SIGNAL heat bonus. The
        // preview used to omit both, overstating exactly the marginal long
        // shots the player consults it for.
        let isMeleeWeapon = weapon.type == .blade || weapon.type == .unarmed
        let effectiveRange: Int
        switch weapon.type {
        case .pistol:          effectiveRange = 3
        case .smg:             effectiveRange = 5
        case .rifle:           effectiveRange = 8
        case .blade, .unarmed: effectiveRange = 99
        }
        // Pure odd-q cube distance (same math as PathingAndAIHelpers.hexDistance).
        let cz1 = attacker.positionY - (attacker.positionX - (attacker.positionX & 1)) / 2
        let cz2 = target.positionY - (target.positionX - (target.positionX & 1)) / 2
        let cy1 = -attacker.positionX - cz1
        let cy2 = -target.positionX - cz2
        let shotDistance = max(abs(attacker.positionX - target.positionX),
                               abs(cy1 - cy2), abs(cz1 - cz2))
        let rangePenalty = isMeleeWeapon ? 0 : min(4, max(0, shotDistance - effectiveRange))
        let attackPool = max(1, attacker.attackPool(skill: skill) + weaponBonus + signalDiceBonus - rangePenalty)
        let coverCount = coverBetween(tiles: tiles,
                                      fromX: attacker.positionX, fromY: attacker.positionY,
                                      toX: target.positionX, toY: target.positionY)
        let coverBonus  = coverDefenseBonus(count: coverCount)
        // Match performAttack: stunned enemies take a flat -2 defense penalty,
        // and PRONE enemies (riot knockdown / BLITZ sweep) another stacking -2.
        // FLANKED enemies (an ally of the attacker adjacent to the target on
        // the far side — see isFlanked) take a further stacking -2, so the
        // pre-attack preview shows the same defense pool the real roll uses.
        // `attackerAllies` = the attacker's LIVING teammates' positions
        // (attacker excluded), passed from GameState.attackPreview/shootPreview.
        let previewFlanked = isFlanked(
            targetX: target.positionX, targetY: target.positionY,
            attackerX: attacker.positionX, attackerY: attacker.positionY,
            allies: attackerAllies
        )
        let baseDefense = target.attributes.rea + target.attributes.agi + coverBonus
        let statusPenalty = ((target.status == .stunned) ? 2 : 0)
            + (target.statusEffects.contains(.prone) ? 2 : 0)
            + (previewFlanked ? 2 : 0)
        let defensePool = statusPenalty > 0
            ? max(1, baseDefense - statusPenalty)
            : baseDefense
        let hitsPerDie  = 1.0 / 3.0
        let atkExp      = Double(attackPool)  * hitsPerDie
        let defExp      = Double(defensePool) * hitsPerDie
        let netExp      = max(0.0, atkExp - defExp)
        let hitChance   = attackPool > 0
            ? min(1.0, max(0.0, 0.5 + (atkExp - defExp) / Double(max(1, attackPool))))
            : 0.0
        let weaponDamage    = weapon.damage
        let estimatedDamage = Double(weaponDamage) + netExp
        return HitPreview(actionLabel: actionLabel, weaponName: weapon.name,
                          targetName: target.name, attackPool: attackPool, defensePool: defensePool, coverBonus: coverBonus,
                          estimatedHitChance: hitChance, weaponDamage: weaponDamage,
                          estimatedDamage: estimatedDamage, blocked: false, reason: nil)
    }
}
