import Foundation

// Spell resolution (Fireball / ManaBolt / Shock / Heal).
// Extracted from GameState.swift (mechanical move; logic unchanged).
extension GameState {
    // MARK: Fireball — AoE Physical

    /// FIREBALL — the mage's signature map-wide barrage. Design intent
    /// (restored 2026-06-12 per playtest): it targets EVERY living enemy, no
    /// range or LOS gate; each enemy rolls soak independently, so each has a
    /// chance to shrug it off entirely. `targetId` accepted for call-site
    /// symmetry with the single-target spells but unused.
    func castFireball(by mage: Character, targetId: UUID? = nil) {
        let targets = livingEnemies
        guard !targets.isEmpty else { addLog("No targets."); return }

        let spellPool = max(1, mage.attributes.log + mage.skills.spellcasting + signalDiceBonus + (mage.equippedArmor?.spellPenalty ?? 0))   // heavy armor hampers casting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= max(0, SpellType.fireball.manaCost - signalManaDiscount)
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

        addLog("🔥 \(mage.name) FIREBALL! [\(spellPool)d6→\(spellRoll.hits) hits] engulfs \(targets.count) \(targets.count == 1 ? "enemy" : "enemies")!")
        for target in targets {
            // Per-target detonation, but every projectile streaks from the
            // MAGE's tile (the old nil-origin version had them arriving from
            // random off-screen directions). The keyed screen shake means
            // overlapping detonations restart the shake instead of stacking.
            NotificationCenter.default.post(
                name: .fireballEffect, object: nil,
                userInfo: ["x": target.positionX, "y": target.positionY,
                           "fromX": mage.positionX, "fromY": mage.positionY]
            )
            let baseDamage = SpellType.fireball.baseDamage + spellRoll.hits
            let soakPool = target.attributes.wil + (target.equippedArmor?.armorValue ?? 0) / 2
            let soakRoll = DiceEngine.roll(pool: max(0, soakPool))
            let finalDamage = max(0, baseDamage - soakRoll.hits)
            target.takeDamage(amount: finalDamage, isStun: false)
            // Burning: 2 rounds, 3 dmg/round — only if the blast actually bit
            // through soak. REFRESH the timer rather than appending — each
            // .burning ticks independently in tickStatusEffects, so stacking N
            // casts would deal N×3 dmg/round and a mage with mana could keep a
            // group permanently ablaze.
            if finalDamage > 0 {
                if let i = target.statusEffects.firstIndex(where: {
                    if case .burning = $0 { return true } else { return false }
                }) {
                    target.statusEffects[i] = .burning(roundsLeft: 2)
                } else {
                    target.statusEffects.append(.burning(roundsLeft: 2))
                }
                addLog("  → \(target.name): \(baseDamage)P - \(soakRoll.hits)soak = \(finalDamage) dmg (\(target.currentHP)/\(target.maxHP) HP)")
                addLog("    🔥 BURNING for 2 rounds!")
            } else {
                addLog("  → \(target.name) soaks the blast!")
            }
            NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": finalDamage, "outcome": finalDamage > 0 ? "hit" : "soak"])
            if !target.isAlive { handleEnemyKilled(target, by: mage) }
        }
        addLog("  Mana: \(mage.currentMana)/\(mage.maxMana)")
        if livingEnemies.isEmpty { onRoomCleared() }
        completeAction(for: mage)
    }

    // MARK: Mana Bolt & Shock — Single-target

    func castSingleTarget(type: SpellType, targetId: UUID?, by mage: Character) {
        // Single-target spells obey the same range + LOS rules as Fireball —
        // previously they could snipe any enemy through every wall on the map.
        let spellRange = 6
        let candidates = livingEnemies.filter { e in
            hexDistance(x1: mage.positionX, y1: mage.positionY,
                        x2: e.positionX, y2: e.positionY) <= spellRange
                && !isLineBlockedByWall(fromX: mage.positionX, fromY: mage.positionY,
                                        toX: e.positionX, toY: e.positionY)
        }
        let target: Enemy
        if let tid = targetId, let chosen = enemies.first(where: { $0.id == tid && $0.isAlive }) {
            guard candidates.contains(where: { $0.id == tid }) else {
                addLog("\(chosen.name) is out of range/LOS for \(type.displayName) (range \(spellRange)).")
                return
            }
            target = chosen
        } else if let nearest = candidates.min(by: {
            hexDistance(x1: mage.positionX, y1: mage.positionY, x2: $0.positionX, y2: $0.positionY)
                < hexDistance(x1: mage.positionX, y1: mage.positionY, x2: $1.positionX, y2: $1.positionY)
        }) {
            target = nearest
            targetCharacterId = nearest.id
        } else {
            addLog("No enemy in range/LOS for \(type.displayName) (range \(spellRange)).")
            return
        }

        let spellPool = max(1, mage.attributes.log + mage.skills.spellcasting + signalDiceBonus + (mage.equippedArmor?.spellPenalty ?? 0))   // heavy armor hampers casting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= max(0, type.manaCost - signalManaDiscount)
        HapticsManager.shared.attackHit()
        if signalDiceBonus > 0 { addLog("📡 SIGNAL +\(signalDiceBonus)d (running hot)") }

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

        // Crit fishing applies to direct-damage spells too.
        let isCrit = spellRoll.hits >= critThreshold
        if isCrit { addLog("🎯 CRITICAL CAST!") }
        let baseDamage = type.baseDamage + spellRoll.hits + (isCrit ? 2 : 0)
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

    // MARK: Confusion — Single-target control

    /// CONFUSION — Sable's control hex. No damage: an OPPOSED roll of the
    /// mage's spellcasting pool vs the target's WIL-based mental resistance
    /// (mirrors the Decker hack's opposed-resist pattern — bosses get the
    /// same hardened +2). On a win the target is `.confused(roundsLeft: 1)`:
    /// its next AI turn is spent lashing out at a random adjacent unit —
    /// friend or foe — or stumbling to a random tile (see runConfusedTurn).
    /// Range/LOS gating and glitch/drain handling match the single-target
    /// bolts exactly.
    func castConfusion(by mage: Character, targetId: UUID? = nil) {
        // Same range + LOS rules as Mana Bolt — no hexing through walls.
        let spellRange = 6
        let candidates = livingEnemies.filter { e in
            hexDistance(x1: mage.positionX, y1: mage.positionY,
                        x2: e.positionX, y2: e.positionY) <= spellRange
                && !isLineBlockedByWall(fromX: mage.positionX, fromY: mage.positionY,
                                        toX: e.positionX, toY: e.positionY)
        }
        let target: Enemy
        if let tid = targetId, let chosen = enemies.first(where: { $0.id == tid && $0.isAlive }) {
            guard candidates.contains(where: { $0.id == tid }) else {
                addLog("\(chosen.name) is out of range/LOS for \(SpellType.confusion.displayName) (range \(spellRange)).")
                return
            }
            target = chosen
        } else if let nearest = candidates.min(by: {
            hexDistance(x1: mage.positionX, y1: mage.positionY, x2: $0.positionX, y2: $0.positionY)
                < hexDistance(x1: mage.positionX, y1: mage.positionY, x2: $1.positionX, y2: $1.positionY)
        }) {
            target = nearest
            targetCharacterId = nearest.id
        } else {
            addLog("No enemy in range/LOS for \(SpellType.confusion.displayName) (range \(spellRange)).")
            return
        }

        let spellPool = max(1, mage.attributes.log + mage.skills.spellcasting + signalDiceBonus + (mage.equippedArmor?.spellPenalty ?? 0))   // heavy armor hampers casting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= max(0, SpellType.confusion.manaCost - signalManaDiscount)
        HapticsManager.shared.attackHit()
        if signalDiceBonus > 0 { addLog("📡 SIGNAL +\(signalDiceBonus)d (running hot)") }

        // Glitch handling — same drain conventions as the bolts.
        if spellRoll.criticalGlitch {
            let drain = mage.attributes.wil * 2
            mage.takeDamage(amount: drain)
            addLog("💥 CRIT GLITCH! CONFUSION backfires! \(mage.name) takes \(drain) drain!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": mage.id.uuidString, "damage": drain])
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
            completeAction(for: mage)
            return
        }
        if spellRoll.glitch || spellRoll.hits == 0 {
            let drain = mage.attributes.wil
            mage.takeDamage(amount: drain)
            addLog("⚠️ GLITCH! CONFUSION fizzles. \(mage.name) takes \(drain) drain!")
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
            completeAction(for: mage)
            return
        }

        // Opposed resist: the target's willpower pushes the hex back. Bosses
        // get the same hardened +2 as ICE in performHackOnTarget — high-WIL
        // elites shrug it off, keeping this from being a free boss-lock.
        let isBoss = target.archetype.lowercased().hasPrefix("boss")
        let resistPool = max(1, target.attributes.wil + (isBoss ? 2 : 0))
        let resistRoll = DiceEngine.roll(pool: resistPool)
        guard spellRoll.hits > resistRoll.hits else {
            addLog("🌀 \(target.name) RESISTS Confusion! [\(spellPool)d6→\(spellRoll.hits) vs WIL \(resistPool)d6→\(resistRoll.hits)]")
            addLog("  Mana: \(mage.currentMana)/\(mage.maxMana)")
            NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": 0, "outcome": "miss"])
            completeAction(for: mage)
            return
        }

        // Land the hex — REFRESH rather than stack (same rule as .burning):
        // re-casting on a confused target resets the clock instead of
        // queueing multiple scrambled turns.
        if let i = target.statusEffects.firstIndex(where: {
            if case .confused = $0 { return true } else { return false }
        }) {
            target.statusEffects[i] = .confused(roundsLeft: 1)
        } else {
            target.statusEffects.append(.confused(roundsLeft: 1))
        }
        addLog("🌀 \(mage.name) CONFUSION! [\(spellPool)d6→\(spellRoll.hits) vs WIL \(resistRoll.hits)] — \(target.name)'s mind scrambles!")
        addLog("  Mana: \(mage.currentMana)/\(mage.maxMana)")
        NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": target.id.uuidString, "damage": 0])
        // Visual: pink bolt from caster to target — same delivery VFX as
        // MANABOLT, tinted to the spell's UI color.
        NotificationCenter.default.post(
            name: .boltEffect, object: nil,
            userInfo: ["fromX": mage.positionX, "fromY": mage.positionY,
                       "toX": target.positionX, "toY": target.positionY,
                       "color": "#FF66CC"]
        )
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

        let spellPool = max(1, mage.attributes.log + mage.skills.spellcasting + signalDiceBonus + (mage.equippedArmor?.spellPenalty ?? 0))   // heavy armor hampers casting
        let spellRoll = DiceEngine.roll(pool: spellPool)
        mage.currentMana -= max(0, SpellType.heal.manaCost - signalManaDiscount)
        HapticsManager.shared.attackHit()

        if spellRoll.criticalGlitch {
            let drain = mage.attributes.wil * 2
            mage.takeDamage(amount: drain)
            addLog("💥 CRIT GLITCH! HEAL backfires! \(mage.name) takes \(drain) drain!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": mage.id.uuidString, "damage": drain])
            // Same drain-death routing as fireball/single-target: without this
            // a heal-backfire death left a live-looking mage in turn tracking.
            if !mage.isAlive { CombatFlowController.handlePlayerKilled(gameState: self, char: mage) }
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
}
