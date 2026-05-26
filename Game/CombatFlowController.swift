import Foundation

@MainActor
struct CombatFlowController {
    static func setCombatPhase(gameState: GameState, _ phase: CombatPhase) {
        gameState.combatPhase = phase
        CombatFlowController.syncLegacyState(gameState: gameState)
    }

    static func setCombatOutcome(gameState: GameState, _ outcome: CombatOutcome) {
        gameState.combatOutcome = outcome
        CombatFlowController.syncLegacyState(gameState: gameState)
    }

    /// Legacy fields derived from CombatPhase/CombatOutcome — do not write directly.
    static func syncLegacyState(gameState: GameState) {
        let phase = gameState.combatPhase
        let outcome = gameState.combatOutcome

        gameState.isPlayerTurn = (phase == .playerInput)
        gameState.isPlayerInputBlocked = (phase != .playerInput)

        // Outcome is terminal? Keep combatEnded latched ON regardless of
        // phase. Without this, a stray setCombatPhase(.playerInput) tick
        // (or any non-resolved phase) would reset combatEnded=false,
        // dropping the RUN COMPLETE/RUN FAILED overlay out from under the
        // player and dumping them back on the empty combat scene with
        // enemies still standing — exactly the M6 defeat repro.
        let outcomeIsTerminal: Bool = {
            switch outcome {
            case .victory, .extracted, .defeat: return true
            case .none: return false
            }
        }()

        // Special case: extraction is in flight. The outcome is already
        // .extracted (set when the player stepped on the pad so the
        // ExtractionService and onComplete handlers can read it), but the
        // helicopter animation hasn't finished. If we latch combatEnded /
        // missionComplete here, the debrief overlay pops over the heli
        // sequence. Wait for finalizeExtractionAfterAnimation to do the
        // latch — it runs from the animation's onComplete or the 11s
        // safety net.
        let extractionInFlight = (outcome == .extracted)
            && gameState.extractionAnimationInProgress

        if outcomeIsTerminal && !extractionInFlight {
            gameState.combatEnded = true
            gameState.missionComplete = true
        } else if outcomeIsTerminal && extractionInFlight {
            // Hold off on the terminal flags until the heli leaves.
            gameState.combatEnded = false
            gameState.missionComplete = false
        } else {
            switch phase {
            case .combatResolved, .rewarding, .complete:
                gameState.combatEnded = true
                gameState.missionComplete = true
            default:
                gameState.combatEnded = false
                gameState.missionComplete = false
            }
        }

        switch outcome {
        case .victory, .extracted:
            gameState.combatWon = true
        case .defeat:
            gameState.combatWon = false
        case .none:
            gameState.combatWon = nil
        }
    }

    /// Broad combat closure flags are owned here so setup/outcome flows do not write ad hoc.
    static func resetCombatOutcomeFlagsForNewMission(gameState: GameState) {
        CombatFlowController.setCombatPhase(gameState: gameState, .idle)
        CombatFlowController.setCombatOutcome(gameState: gameState, .none)
    }

    /// Canonical owner path for combat outcome flags once a terminal result is determined.
    static func applyCombatOutcome(gameState: GameState, won: Bool) {
        CombatFlowController.setCombatPhase(gameState: gameState, .combatResolved)
        if won {
            // Preserve extraction-specific terminal outcome if it was set during request path.
            if gameState.combatOutcome != .extracted {
                CombatFlowController.setCombatOutcome(gameState: gameState, .victory)
            }
        } else {
            CombatFlowController.setCombatOutcome(gameState: gameState, .defeat)
        }
    }

    static func beginRound(gameState: GameState) {
        CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
        CombatFlowController.resetTurnTracking(gameState: gameState)
        gameState.isDefending = false
        gameState.defendingCharacterId = nil
        // Restore any AGI nerfs from Face's INTIMIDATE — the debuff lasts ONE
        // round, then enemies recover their wits.
        if !gameState.intimidationOriginalAgi.isEmpty {
            for enemy in gameState.enemies {
                if let original = gameState.intimidationOriginalAgi[enemy.id] {
                    enemy.attributes.agi = original
                }
            }
            gameState.intimidationOriginalAgi.removeAll()
        }
        // Natural stun recovery: each character rolls BOD+WIL to reduce stun (SR5 recovery rules)
        CombatFlowController.recoverStunAtRoundStart(gameState: gameState)
        // Mana regen: mages and deckers recover 1 resource point per round passively
        for char in gameState.playerTeam where char.isAlive {
            if char.archetype == .mage || char.archetype == .decker {
                let prev = char.currentMana
                char.currentMana = min(char.maxMana, char.currentMana + 1)
                if char.currentMana > prev {
                    gameState.addLog("✨ \(char.name) recovers 1 mana. (\(char.currentMana)/\(char.maxMana))")
                }
            }
        }
        // Tick timed status effects: burning deals damage and decrements counters.
        CombatFlowController.tickStatusEffects(gameState: gameState)
    }

    static func resetTurnTracking(gameState: GameState) {
        // Stunned characters auto-skip their turn (they can't act while fully stunned)
        // They still count as "acted" so the round advances without them.
        gameState.playersWhoHaveNotActed = Set(
            gameState.playerTeam.filter { $0.isAlive && $0.status != .stunned }.map { $0.id }
        )
        gameState.playerTurnsCompleted = 0
        gameState.characterHasMovedThisTurn = [:]
        // Reset per-character action flags at start of new round
        for char in gameState.playerTeam {
            char.hasActedThisRound = false
            gameState.characterHasMovedThisTurn[char.id] = false
            // Log stunned characters being skipped
            if char.isAlive && char.status == .stunned {
                gameState.addLog("💤 \(char.name) is STUNNED — skipping turn. (Stun \(char.currentStun)/\(char.maxStun))")
                char.hasActedThisRound = true
            }
        }
        // Clear overwatch — it expires at end of each round
        gameState.overwatchers.removeAll()
    }

    static func characterHasAlreadyMoved(gameState: GameState, _ character: Character) -> Bool {
        if gameState.characterHasMovedThisTurn[character.id] == true {
            gameState.addLog("\(character.name) already moved this turn — choose move OR action.")
            HapticsManager.shared.buttonTap()
            return true
        }
        return false
    }

    static func recoverStunAtRoundStart(gameState: GameState) {
        for char in gameState.playerTeam where char.isAlive && char.currentStun > 0 {
            let recoveryPool = char.attributes.bod + char.attributes.wil
            let roll = DiceEngine.roll(pool: recoveryPool)
            if roll.hits > 0 {
                char.recoverStun(amount: roll.hits)
            }
        }
        for enemy in gameState.enemies where enemy.isAlive && enemy.currentStun > 0 {
            let recoveryPool = enemy.attributes.bod + enemy.attributes.wil
            let roll = DiceEngine.roll(pool: recoveryPool)
            if roll.hits > 0 {
                enemy.currentStun = max(0, enemy.currentStun - roll.hits)
                if enemy.status == .stunned && enemy.currentStun < enemy.maxStun {
                    enemy.status = .wounded
                }
            }
        }
    }

    static func tickStatusEffects(gameState: GameState) {
        // Tick player status effects
        for char in gameState.playerTeam {
            guard char.isAlive else { continue }
            var toRemove: [Int] = []
            for (i, effect) in char.statusEffects.enumerated() {
                switch effect {
                case .burning(let rounds):
                    char.takeDamage(amount: 3, isStun: false)
                    gameState.addLog("🔥 \(char.name) BURNS! 3 damage. (\(char.currentHP)/\(char.maxHP) HP)")
                    NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": char.id.uuidString, "damage": 3])
                    if char.isAlive {
                        let newRounds = rounds - 1
                        if newRounds <= 0 { toRemove.append(i) }
                        else { char.statusEffects[i] = .burning(roundsLeft: newRounds) }
                    } else {
                        toRemove.append(i)
                        // Bug fix 2026-05: burn-out wasn't firing the death
                        // pipeline, so the corpse stayed on screen and turn
                        // tracking still treated them as a participant.
                        CombatFlowController.handlePlayerKilled(gameState: gameState, char: char)
                    }
                case .marked(let rounds):
                    // Marked: attackers get +1 die when targeting this character
                    let newRounds = rounds - 1
                    if newRounds <= 0 { toRemove.append(i) }
                    else { char.statusEffects[i] = .marked(roundsLeft: newRounds) }
                case .confused(let rounds):
                    let newRounds = rounds - 1
                    if newRounds <= 0 { toRemove.append(i) }
                    else { char.statusEffects[i] = .confused(roundsLeft: newRounds) }
                default:
                    break
                }
            }
            for i in toRemove.reversed() { char.statusEffects.remove(at: i) }
        }
        // Tick enemy status effects
        for enemy in gameState.enemies {
            guard enemy.isAlive else { continue }
            var toRemove: [Int] = []
            for (i, effect) in enemy.statusEffects.enumerated() {
                switch effect {
                case .burning(let rounds):
                    enemy.takeDamage(amount: 3, isStun: false)
                    gameState.addLog("🔥 \(enemy.name) BURNS! 3 damage. (\(enemy.currentHP)/\(enemy.maxHP) HP)")
                    // Visual HP-bar refresh + damage pop. Without this the
                    // enemy's bar stayed frozen at its pre-burn HP, hiding
                    // the actual death from the player.
                    NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": enemy.id.uuidString, "damage": 3, "outcome": "hit"])
                    if enemy.isAlive {
                        let newRounds = rounds - 1
                        if newRounds <= 0 { toRemove.append(i) }
                        else { enemy.statusEffects[i] = .burning(roundsLeft: newRounds) }
                    } else {
                        toRemove.append(i)
                        // Bug fix 2026-05: burn-out kills weren't routing
                        // through the death pipeline, so the enemy stayed
                        // on screen "alive-looking" while `livingEnemies`
                        // (and the room-clear / data-acquired logic) saw
                        // them as dead. Symptom: ATK said "no enemies in
                        // range" while the player could clearly see them.
                        gameState.handleEnemyKilledByEnvironment(enemy)
                    }
                case .marked(let rounds):
                    let newRounds = rounds - 1
                    if newRounds <= 0 { toRemove.append(i) }
                    else { enemy.statusEffects[i] = .marked(roundsLeft: newRounds) }
                case .confused(let rounds):
                    let newRounds = rounds - 1
                    if newRounds <= 0 { toRemove.append(i) }
                    else { enemy.statusEffects[i] = .confused(roundsLeft: newRounds) }
                default:
                    break
                }
            }
            for i in toRemove.reversed() { enemy.statusEffects.remove(at: i) }
        }
    }

    static func performAttack(gameState: GameState) {
        let attacker: Character?
        if let selected = gameState.selectedCharacterId, let char = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            attacker = char
        } else {
            attacker = gameState.currentCharacter
        }
        guard let a = attacker else { gameState.addLog("No character available."); return }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, a) else { return }

        // Resolve target: prefer the player's tap-selected target, else fall
        // back to the nearest living enemy. This matches `performHack` /
        // `castSingleTarget` behavior and removes the "tap an enemy first"
        // friction step — ATK/SHT now Just Work as long as any enemy exists.
        let targetEnemy: Enemy
        let targetId: UUID
        if let tid = gameState.targetCharacterId,
           let e = gameState.enemies.first(where: { $0.id == tid && $0.isAlive }) {
            targetEnemy = e
            targetId = tid
        } else {
            // Pick closest living enemy by hex distance from the attacker.
            let candidates = gameState.livingEnemies
                .map { ($0, gameState.hexDistance(x1: a.positionX, y1: a.positionY, x2: $0.positionX, y2: $0.positionY)) }
                .sorted { $0.1 < $1.1 }
            guard let nearest = candidates.first?.0 else {
                // Verbose diagnostic — user reported visible enemies still
                // on screen with HP, but `livingEnemies` returned empty. We
                // need to see exactly what GameState thinks vs. what's on
                // screen. Print every enemy with status, HP, position.
                let total = gameState.enemies.count
                let alive = gameState.enemies.filter { $0.isAlive }.count
                let detail = gameState.enemies
                    .map { "\($0.name)@(\($0.positionX),\($0.positionY))[s=\($0.status),hp=\($0.currentHP)/\($0.maxHP),alive=\($0.isAlive)]" }
                    .joined(separator: " | ")
                gameState.addLog("⚠️ DIAG: enemies=\(total) alive=\(alive) | \(detail)")
                return
            }
            targetEnemy = nearest
            targetId = nearest.id
            gameState.targetCharacterId = nearest.id
        }

        var weapon = a.equippedWeapon ?? Weapon(name: "Fists", type: .unarmed, damage: 3, accuracy: 3, armorPiercing: 0)

        // Melee-only enforcement for the Street Samurai. Raze's loadout is
        // a katana, no sidearm — if the target is out of melee range, the
        // action fails cleanly (no turn consumed). Other melee-class chars
        // (mage stunball) still get the sidearm fallback so they have SOME
        // ranged option if their spells are out / out-of-mana.
        if weapon.type == .blade || weapon.type == .unarmed {
            let distance = gameState.hexDistance(
                x1: a.positionX, y1: a.positionY,
                x2: targetEnemy.positionX, y2: targetEnemy.positionY
            )
            if distance > 1 {
                if a.archetype == .streetSam || a.archetype == .decker {
                    gameState.addLog("⚔️ \(a.name)'s \(weapon.name) is melee only — move adjacent first.")
                    HapticsManager.shared.error()
                    return   // no turn consumed
                }
                // Non-samurai melee classes get the sidearm fallback.
                weapon = Weapon(name: "Sidearm", type: .pistol, damage: 4,
                                accuracy: 4, armorPiercing: 1)
                gameState.addLog("\(a.name) is too far for melee — drawing sidearm.")
            }
        }

        if gameState.isLineBlockedByWall(
            fromX: a.positionX, fromY: a.positionY,
            toX: targetEnemy.positionX, toY: targetEnemy.positionY
        ) {
            gameState.addLog("⛔ Line of sight blocked by wall!")
            HapticsManager.shared.buttonTap()
            return
        }

        // Determine attack skill from weapon type
        let skill: SkillKey = (weapon.type == .blade || weapon.type == .unarmed) ? .blades : .firearms

        // Attack pool: AGI + skill + weapon-accuracy bonus.
        // Tuning history:
        //   • Original: just AGI+skill (~6-7d). Vs. defense 6-9d this missed
        //     ~75% of the time — felt broken.
        //   • Bumped to +acc/2 (~+2 dice). Pushed it to ~95% hit rate. Too
        //     deterministic the other way.
        //   • Now: +acc/3 (rounds down). Pistol acc 4 → +1, SMG acc 5 → +1,
        //     Rifle acc 7 → +2, Sniper acc 6 → +2. Lands a typical attacker
        //     at 8d vs. 6d defense → ~70% hit rate with variance.
        let weaponBonus = max(0, weapon.accuracy / 3)
        let attackPool = a.attackPool(skill: skill) + weaponBonus

        switch gameState.actionMode {
        case .street: gameState.applyStreetAction()
        case .signal: gameState.applySignalAction()
        }

        // Cover bonus: count cover tiles between attacker and target
        let coverCount = CombatMechanics.coverBetween(
            tiles: gameState.currentMissionTiles,
            fromX: a.positionX, fromY: a.positionY,
            toX: targetEnemy.positionX, toY: targetEnemy.positionY
        )
        let coverBonus = CombatMechanics.coverDefenseBonus(count: coverCount)

        // Defense pool: REA + AGI + cover bonus.
        // Hacked / stunned enemies take a -2 dice flat penalty (down from
        // halving — halving made hacked targets near-guaranteed multi-hits,
        // which removed the dice-roll tension). -2 keeps the hack meaningful
        // (~33% smaller defense pool against a typical 6d enemy) without
        // making everything an instant kill.
        let baseDefense = targetEnemy.attributes.rea + targetEnemy.attributes.agi + coverBonus
        let defensePool: Int = (targetEnemy.status == .stunned)
            ? max(1, baseDefense - 2)
            : baseDefense

        // Roll attack
        let attackRoll = DiceEngine.roll(pool: attackPool)

        // Critical glitch: attacker fumbles, takes self-damage
        if attackRoll.criticalGlitch {
            let selfDmg = 2
            a.takeDamage(amount: selfDmg)
            gameState.addLog("💥 CRITICAL GLITCH! \(a.name) fumbles — \(selfDmg) self-damage!")
            HapticsManager.shared.playerDamaged()
            NotificationCenter.default.post(name: .characterHit, object: nil, userInfo: ["characterId": a.id.uuidString, "damage": selfDmg])
            CombatFlowController.completeAction(gameState: gameState, for: a)
            return
        }

        if attackRoll.glitch {
            // "Misfires" only makes sense for firearms — a katana can't misfire.
            // Pick a verb that fits the weapon class.
            let glitchVerb: String
            switch weapon.type {
            case .blade:   glitchVerb = "swings wide and misses"
            case .unarmed: glitchVerb = "loses balance"
            case .pistol, .smg, .rifle: glitchVerb = "misfires"
            }
            gameState.addLog("⚠️ GLITCH! \(a.name)'s \(weapon.name) \(glitchVerb)!")
            CombatFlowController.completeAction(gameState: gameState, for: a)
            return
        }

        // Defense roll
        let defenseRoll = DiceEngine.roll(pool: defensePool)
        let netHits = max(0, attackRoll.hits - defenseRoll.hits)

        gameState.addLog("⚔️ \(a.name) attacks with \(weapon.name)! [\(attackPool)d6→\(attackRoll.hits)] vs [\(defensePool)d6→\(defenseRoll.hits)\(coverBonus > 0 ? " +\(coverBonus)cov" : "")]")

        // Visual: muzzle flash + tracer for ranged, slash arc for melee.
        // Fired regardless of hit/miss so the player always sees something
        // happen when they tap ATK/SHT.
        let isMelee = weapon.type == .blade || weapon.type == .unarmed
        if isMelee {
            NotificationCenter.default.post(
                name: .meleeStrikeEffect, object: nil,
                userInfo: [
                    "x": targetEnemy.positionX,
                    "y": targetEnemy.positionY,
                    "weaponType": weapon.type.rawValue
                ]
            )
        } else {
            NotificationCenter.default.post(
                name: .gunfireEffect, object: nil,
                userInfo: ["fromX": a.positionX, "fromY": a.positionY,
                           "toX": targetEnemy.positionX, "toY": targetEnemy.positionY,
                           "weaponType": weapon.type.rawValue]
            )
        }

        if netHits == 0 {
            gameState.addLog("  → MISS! \(targetEnemy.name) dodges!")
            NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": targetId.uuidString, "damage": 0, "outcome": "miss"])
            CombatFlowController.completeAction(gameState: gameState, for: a)
            return
        }

        // Damage = weapon base + net hits
        let baseDamage = weapon.damage + netHits
        let ap = weapon.armorPiercing

        // Soak: enemy BOD + armor - AP (minimum 0)
        let soakPool = max(0, targetEnemy.computeDerived().soak - ap)
        let soakRoll = DiceEngine.roll(pool: soakPool)
        let finalDamage = max(0, baseDamage - soakRoll.hits)

        HapticsManager.shared.attackHit()
        let isStunDmg = weapon.isStunDamage
        targetEnemy.takeDamage(amount: finalDamage, isStun: isStunDmg)
        let dmgType = isStunDmg ? "S" : "P"

        if finalDamage > 0 {
            gameState.addLog("  → \(netHits) net hits! \(baseDamage)\(dmgType) - \(soakRoll.hits) soak = \(finalDamage) dmg! (\(targetEnemy.currentHP)/\(targetEnemy.maxHP) HP | Stun \(targetEnemy.currentStun)/\(targetEnemy.maxStun))")
        } else {
            gameState.addLog("  → Hit but \(targetEnemy.name) soaks ALL damage!")
        }

        // Fire melee-impact event so SFXManager plays the wet-thunk clip
        // only when blade actually lands damage (not on full-soak / miss).
        // 4+ net hits = critical (top-tier hit), routed to a beefier SFX.
        if isMelee && finalDamage > 0 {
            NotificationCenter.default.post(
                name: .meleeImpactEffect, object: nil,
                userInfo: [
                    "x": targetEnemy.positionX,
                    "y": targetEnemy.positionY,
                    "critical": netHits >= 4,
                    "weaponType": weapon.type.rawValue
                ]
            )
        }

        NotificationCenter.default.post(name: .enemyHit, object: nil, userInfo: ["enemyId": targetId.uuidString, "damage": finalDamage, "outcome": finalDamage > 0 ? "hit" : "soak"])

        if !targetEnemy.isAlive {
            HapticsManager.shared.enemyKilled()
            gameState.missionEnemiesDefeated += 1
            CombatFlowController.handleEnemyKillForRoomEffects(gameState: gameState)
            gameState.addLog("☠️ \(targetEnemy.name) DOWN! +\(targetEnemy.maxHP / 2) XP")
            gameState.generateLoot()
            if let char = gameState.playerTeam.first(where: { $0.id == a.id }) {
                let leveledUp = char.gainXP(targetEnemy.maxHP / 2)
                if leveledUp {
                    HapticsManager.shared.levelUp()
                    gameState.addLog("🎖️ LEVEL UP! \(char.name) → Level \(char.level)!")
                    NotificationCenter.default.post(name: .characterLevelUp, object: nil, userInfo: ["characterId": char.id.uuidString])
                }
            }
            NotificationCenter.default.post(name: .enemyDied, object: nil, userInfo: ["enemyId": targetId.uuidString])
            if gameState.livingEnemies.isEmpty { gameState.onRoomCleared() }
        }

        CombatFlowController.completeAction(gameState: gameState, for: a)
    }

    static func performShoot(gameState: GameState) {
        let attacker: Character?
        if let selected = gameState.selectedCharacterId, let char = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            attacker = char
        } else {
            attacker = gameState.currentCharacter
        }
        guard let a = attacker else { gameState.addLog("No character available."); return }

        // Per-archetype sidearm. Cipher keeps the Smartgun Pistol he used
        // to carry as primary — when he taps SHT he's drawing his trained
        // backup, not a generic holdout. Everyone else uses the standard
        // Sidearm fallback.
        let sidearm: Weapon
        switch a.archetype {
        case .decker:
            sidearm = Weapon(name: "Smartgun Pistol", type: .pistol, damage: 5, accuracy: 5, armorPiercing: 1)
        default:
            sidearm = Weapon(name: "Sidearm", type: .pistol, damage: 4, accuracy: 4, armorPiercing: 1)
        }

        let originalWeapon = a.equippedWeapon
        a.equippedWeapon = sidearm
        defer { a.equippedWeapon = originalWeapon }

        CombatFlowController.performAttack(gameState: gameState)
    }

    static func performLayLow(gameState: GameState) {
        let actor: Character?
        if let selected = gameState.selectedCharacterId, let char = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            actor = char
        } else {
            actor = gameState.currentCharacter
        }
        guard let character = actor else {
            gameState.addLog("No character available.")
            return
        }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, character) else { return }
        gameState.applyTraceRecovery()
        CombatFlowController.completeAction(gameState: gameState, for: character) // Cost: consumes full turn
    }

    static func performSpell(gameState: GameState, type: SpellType, targetId: UUID? = nil) {
        // Resolve caster
        let char: Character?
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else {
            char = gameState.currentCharacter
        }
        guard let mage = char, mage.archetype == CharacterArchetype.mage else {
            gameState.addLog("Only mages can cast spells.")
            return
        }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, mage) else { return }
        guard mage.currentMana >= type.manaCost else {
            gameState.addLog("Not enough mana for \(type.displayName)! Need \(type.manaCost), have \(mage.currentMana).")
            HapticsManager.shared.buttonTap()
            return
        }

        // Dispatch by spell type
        switch type {
        case .fireball:
            gameState.castFireball(by: mage)
        case .manaBolt:
            gameState.castSingleTarget(type: type, targetId: targetId ?? gameState.targetCharacterId, by: mage)
        case .shock:
            gameState.castSingleTarget(type: type, targetId: targetId ?? gameState.targetCharacterId, by: mage)
        case .heal:
            gameState.castHeal(by: mage, targetId: targetId)
        }
    }

    static func performDefend(gameState: GameState) {
        let char: Character
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else if let current = gameState.currentCharacter {
            char = current
        } else { return }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, char) else { return }
        HapticsManager.shared.buttonTap()
        gameState.isDefending = true
        gameState.defendingCharacterId = char.id
        gameState.addLog("\(char.name) takes a defensive stance. (+2 DEF)")
        NotificationCenter.default.post(
            name: .characterDefend,
            object: nil,
            userInfo: ["characterId": char.id.uuidString]
        )
        CombatFlowController.completeAction(gameState: gameState, for: char)
    }

    static func performHack(gameState: GameState) {
        let char: Character?
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else {
            char = gameState.currentCharacter
        }
        guard let decker = char, decker.archetype == CharacterArchetype.decker else {
            gameState.addLog("Only Deckers can hack.")
            return
        }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, decker) else { return }
        guard decker.currentMana >= 2 else {
            gameState.addLog("Not enough matrix energy! Need 2, have \(decker.currentMana).")
            HapticsManager.shared.buttonTap()
            return
        }
        guard let targetId = gameState.targetCharacterId,
              let target = gameState.enemies.first(where: { $0.id == targetId && $0.isAlive }) else {
            guard let nearest = gameState.livingEnemies.first else {
                gameState.addLog("No targets in range."); return
            }
            gameState.targetCharacterId = nearest.id
            gameState.performHackOnTarget(nearest, by: decker)
            return
        }
        gameState.performHackOnTarget(target, by: decker)
    }

    static func performIntimidate(gameState: GameState) {
        let char: Character?
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else {
            char = gameState.currentCharacter
        }
        guard let face = char, face.archetype == CharacterArchetype.face else {
            gameState.addLog("Only the Face can intimidate.")
            return
        }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, face) else { return }
        // Social pool: CHA + (LOG / 2)
        let socialPool = face.attributes.cha + face.attributes.log / 2
        let socialRoll = DiceEngine.roll(pool: socialPool)
        HapticsManager.shared.attackHit()

        if socialRoll.hits == 0 {
            gameState.addLog("🎭 \(face.name) tries to intimidate but the guards laugh it off.")
            CombatFlowController.completeAction(gameState: gameState, for: face)
            return
        }

        // Apply intimidation to all living enemies: snapshot original AGI so we
        // can restore it at the start of the next round (intimidation lasts a
        // single round). Without the snapshot the AGI mutation was permanent
        // for the rest of the battle, even though the log message said "this
        // round".
        for enemy in gameState.livingEnemies {
            // Don't double-snapshot — keep the FIRST original value if INTIMIDATE
            // is somehow stacked.
            if gameState.intimidationOriginalAgi[enemy.id] == nil {
                gameState.intimidationOriginalAgi[enemy.id] = enemy.attributes.agi
            }
            let penalty = min(socialRoll.hits, enemy.attributes.agi - 1)
            enemy.attributes.agi = max(1, enemy.attributes.agi - penalty)
        }
        gameState.addLog("🎭 \(face.name) INTIMIDATES! [\(socialPool)d6→\(socialRoll.hits)] — Enemies rattled! (-\(socialRoll.hits) ATK this round)")
        // Visual: red shockwave radiating from Face's tile.
        NotificationCenter.default.post(
            name: .intimidateEffect, object: nil,
            userInfo: ["x": face.positionX, "y": face.positionY]
        )
        CombatFlowController.completeAction(gameState: gameState, for: face)
    }

    static func performBlitz(gameState: GameState) {
        let char: Character?
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else {
            char = gameState.currentCharacter
        }
        guard let sam = char, sam.archetype == CharacterArchetype.streetSam else {
            gameState.addLog("Only the Street Samurai can Blitz.")
            return
        }
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, sam) else { return }

        // Charge limit (replaces mana cost — 4 + level charges per mission)
        guard sam.blitzChargesRemaining > 0 else {
            gameState.addLog("⚡ \(sam.name) is out of Blitz charges this run.")
            return
        }

        // Find every enemy within hex-distance 1 of the samurai. Blitz is a
        // melee sweep — it hits ALL adjacent enemies at once, not a
        // long-range pick. We use cube-coordinate hexDistance (rather than
        // the neighbor-list hexAdjacent) so any rendering-vs-logic position
        // ambiguity at the edges of the offset grid still resolves to a
        // proper distance check.
        let adjacents = gameState.livingEnemies.filter {
            gameState.hexDistance(x1: sam.positionX, y1: sam.positionY,
                                  x2: $0.positionX,  y2: $0.positionY) <= 1
        }
        guard !adjacents.isEmpty else {
            // Diagnostic: log positions so we can tell whether the samurai's
            // logical position drifted from where the player thinks he is.
            let sx = sam.positionX, sy = sam.positionY
            let enemyPositions = gameState.livingEnemies
                .map { "\($0.name)@(\($0.positionX),\($0.positionY)):d\(gameState.hexDistance(x1: sx, y1: sy, x2: $0.positionX, y2: $0.positionY))" }
                .joined(separator: ", ")
            gameState.addLog("⚡ Move adjacent first. Samurai @(\(sx),\(sy)) | \(enemyPositions)")
            return
        }

        sam.blitzChargesUsed += 1
        let chargesLeft = sam.blitzChargesRemaining
        gameState.addLog("⚡ \(sam.name) BLITZES \(adjacents.count) target\(adjacents.count == 1 ? "" : "s")! (\(chargesLeft) charges left)")
        // Visual: red slash arc from the samurai's tile.
        NotificationCenter.default.post(
            name: .blitzEffect, object: nil,
            userInfo: ["x": sam.positionX, "y": sam.positionY]
        )
        for enemy in adjacents {
            gameState.performBlitzOnTarget(enemy, by: sam)
        }
        // Final room-cleared check + single turn advance after the sweep.
        if gameState.livingEnemies.isEmpty { gameState.onRoomCleared() }
        CombatFlowController.completeAction(gameState: gameState, for: sam)
    }

    static func moveCharacter(gameState: GameState, id: UUID, toTileX tileX: Int, toTileY tileY: Int) {
        guard let char = gameState.playerTeam.first(where: { $0.id == id && $0.isAlive }) else { return }
        guard !char.hasActedThisRound else {
            gameState.addLog("\(char.name) has already acted this round.")
            return
        }
        guard gameState.characterHasMovedThisTurn[id] != true else {
            gameState.addLog("\(char.name) already moved this turn.")
            return
        }
        char.positionX = tileX
        char.positionY = tileY
        gameState.characterHasMovedThisTurn[id] = true
        gameState.addLog("\(char.name) moves to (\(tileX),\(tileY))")
        // Footstep SFX — random variant of the surface material set by
        // mission (street/exterior = concrete, interior corp = metal).
        // 2026-05: bumped 0.45 → 0.52 (+15%) — earlier global trims left
        // them too quiet vs the rest of the SFX layer.
        let surface = (gameState.currentMissionDisplayId == "Mission001") ? "concrete" : "metal"
        let variant = Int.random(in: 1...4)
        SFXManager.shared.play("step_\(surface)_\(variant)", volume: 0.52)
        NotificationCenter.default.post(
            name: .tileTapped,
            object: nil,
            userInfo: ["tileX": tileX, "tileY": tileY, "characterId": id.uuidString]
        )
        // Floor-pulse VFX on objective tile entry (data terminal or
        // extraction). Single expanding ring — fires once per step-on, not
        // per render frame.
        if tileY >= 0, tileY < gameState.currentMissionTiles.count,
           tileX >= 0, tileX < gameState.currentMissionTiles[tileY].count {
            let raw = gameState.currentMissionTiles[tileY][tileX]
            if raw == TileType.dataTerminal.rawValue || raw == TileType.extraction.rawValue {
                NotificationCenter.default.post(
                    name: .objectivePulseRequested,
                    object: nil,
                    userInfo: ["tileX": tileX, "tileY": tileY, "kind": raw]
                )
            }
        }
        checkDataTerminalPickup(gameState: gameState, atX: tileX, y: tileY, by: char)
        checkGrimoirePickup(gameState: gameState, atX: tileX, y: tileY, by: char)
        // Movement consumes the character's action choice, but does not auto-advance.
        // Keep player input open so the player can explicitly end early via END.
    }

    /// M3 boss-phase-2 trigger. When the corp mage at the M3R2 altar dies,
    /// his TRUE FORM (the boss mage) manifests on the same tile. Idempotent —
    /// only fires once per attempt via `mageBossPhase2Triggered`. Called from
    /// the BattleScene `.enemyDied` observer with the dead enemy's ID.
    static func checkMageBossPhase2(gameState: GameState, deadEnemyId: UUID) {
        // One-shot per mission attempt — once Triggered, this never re-fires.
        guard !gameState.mageBossPhase2Triggered else {
            // But if Sato already fell and the spawn is DEFERRED, check whether
            // the field is finally clear so the boss can manifest now.
            checkMageBossPhase2PendingResolve(gameState: gameState)
            return
        }
        // Only fires on M3 Ritual Chamber.
        guard gameState.currentMissionDisplayId == "Mission003" else { return }
        guard gameState.currentRoomId == "room_2" else { return }
        // The dead enemy must be the corp mage (archetype "mage"). Other
        // archetypes (the two guards) don't trigger phase 2.
        guard let dead = gameState.enemies.first(where: { $0.id == deadEnemyId }) else { return }
        guard dead.archetype.lowercased() == "mage" else { return }

        gameState.mageBossPhase2Triggered = true

        // If other enemies are still alive, DEFER the boss spawn. The boss
        // emerges only after the room is otherwise empty so he never appears
        // mid-melee. Stash the tile for the eventual spawn.
        let othersAlive = gameState.enemies.contains { e in
            e.id != deadEnemyId && e.isAlive
        }
        if othersAlive {
            gameState.mageBossPhase2Pending   = true
            gameState.mageBossPendingSpawnX   = dead.positionX
            gameState.mageBossPendingSpawnY   = dead.positionY
            gameState.addLog("☠️  Sato falls — but the room thrums. His blood is gathering.")
            gameState.postTransientWarning("SATO IS REFORMING — CLEAR THE ROOM", duration: 3.0)
            return
        }

        // No one else alive — manifest the boss immediately.
        spawnSatoBoss(gameState: gameState,
                      atX: dead.positionX, atY: dead.positionY)
    }

    /// Called on every subsequent enemy death after Sato has fallen but the
    /// boss spawn is deferred. Fires the boss spawn once the room is empty.
    static func checkMageBossPhase2PendingResolve(gameState: GameState) {
        guard gameState.mageBossPhase2Pending else { return }
        // Only fires on M3 Ritual Chamber (same scope guard as checkMageBossPhase2).
        guard gameState.currentMissionDisplayId == "Mission003" else { return }
        guard gameState.currentRoomId == "room_2" else { return }
        // Boss already on the field? Bail.
        if gameState.enemies.contains(where: { $0.archetype.lowercased() == "bossmage" && $0.isAlive }) {
            gameState.mageBossPhase2Pending = false
            return
        }
        // Any non-boss living enemy remaining blocks the spawn.
        let othersAlive = gameState.enemies.contains { e in
            let arch = e.archetype.lowercased()
            return e.isAlive && arch != "bossmage"
        }
        if othersAlive { return }

        // Field is clear — boss manifests now.
        spawnSatoBoss(gameState: gameState,
                      atX: gameState.mageBossPendingSpawnX,
                      atY: gameState.mageBossPendingSpawnY)
        gameState.mageBossPhase2Pending = false
    }

    /// Actual boss spawn — shared by the immediate and deferred paths. Suppresses
    /// any queued reinforcement waves so the boss is the focal threat (matching
    /// the M5/M6 deployBoss pattern), and posts all the audio/visual beats.
    private static func spawnSatoBoss(gameState: GameState, atX x: Int, atY y: Int) {
        // Pause any timed/pending reinforcement spawns — boss fight is the focus.
        gameState.pendingSpawns.removeAll()

        // Spawn the boss mage on the stashed tile (Sato unleashed).
        let boss = Enemy.bossMage()
        boss.positionX = x
        boss.positionY = y
        gameState.enemies.append(boss)

        // Narrative beats — these are loud on purpose. The player should
        // feel that the fight just got serious.
        gameState.addLog("☠️  SATO RISES — his blood magic was only the start.")
        gameState.addLog("⚠️  BOSS — \(boss.name) (\(boss.maxHP) HP). Burn him down before he summons.")
        gameState.postTransientWarning("BOSS PHASE 2 — SATO UNBOUND", duration: 4.0)
        HapticsManager.shared.combatStart()

        // Bespoke boss-fight music. Falls back to the mission's track if the
        // user hasn't dropped the file yet (MusicManager logs the miss).
        MusicManager.shared.playLoop(filename: "mage_boss_theme", startOffset: 0)

        // Notify the renderer to place the new boss sprite.
        NotificationCenter.default.post(
            name: .enemySpawned,
            object: nil,
            userInfo: ["enemyId": boss.id.uuidString,
                       "x": boss.positionX, "y": boss.positionY]
        )
    }

    /// M3 grimoire pickup. Located at tile (1, 1) in `room_2` (Ritual
    /// Chamber) — top-left corner so it sits well off the natural path
    /// from spawn → boss → extraction. Player has to make a deliberate
    /// detour to grab it. Auto-collected the first time any player walks
    /// onto the tile AFTER the boss mage is dead. Posts `.grimoireAcquired`
    /// so the scene can animate the visual node out.
    static func checkGrimoirePickup(gameState: GameState, atX x: Int, y: Int, by char: Character) {
        // Only matters on M3 in the Ritual Chamber.
        guard gameState.currentMissionDisplayId == "Mission003" else { return }
        guard gameState.currentRoomId == "room_2" else { return }
        // Grimoire tile — top-left walkable corner of M3R2. Moved from
        // (3, 5) (center-south) per playtest: extraction kicks in too fast
        // when the player crosses the spawn-to-extraction axis, so the
        // grimoire needs to sit OFF that path.
        guard x == 1, y == 1 else { return }
        // Don't double-pickup.
        guard !gameState.grimoireAcquired else { return }
        // Phase 2 boss must have been spawned AND killed. The grimoire is
        // bound to Sato while ANY form of him lives — corp mage OR boss form.
        let p2Triggered = gameState.mageBossPhase2Triggered
        let mageAlive = gameState.enemies.contains { e in
            let arch = e.archetype.lowercased()
            return (arch == "mage" || arch == "bossmage") && e.isAlive
        }
        guard p2Triggered, !mageAlive else {
            gameState.addLog("The grimoire pulses red — bound to Sato while he lives.")
            return
        }
        gameState.grimoireAcquired = true
        gameState.addLog("📖 \(char.name) snatches Sato's grimoire — GRIMOIRE ACQUIRED.")
        SFXManager.shared.play("terminal_correct", volume: 0.65)
        SFXManager.shared.play("mainframe_breach", volume: 0.5)
        NotificationCenter.default.post(
            name: .grimoireAcquired,
            object: nil,
            userInfo: ["x": x, "y": y]
        )
    }

    /// If the tile under the moving character is a data terminal, hack it.
    /// Converts the tile to floor in-memory, marks the objective complete, and
    /// posts .dataTerminalHacked so the scene can update its visual.
    static func checkDataTerminalPickup(gameState: GameState, atX x: Int, y: Int, by char: Character) {
        guard y >= 0, y < gameState.currentMissionTiles.count else { return }
        guard x >= 0, x < gameState.currentMissionTiles[y].count else { return }
        guard gameState.currentMissionTiles[y][x] == TileType.dataTerminal.rawValue else { return }
        // Don't auto-acquire — launch the Matrix mini-game first.
        // ShadowrunGameApp overlays MatrixMiniGameView when showMatrixMiniGame
        // becomes true; the mini-game's completion handler calls
        // resolveMatrixMiniGame(success:) below to finalise the pickup or bail.
        gameState.pendingHackTerminalX = x
        gameState.pendingHackTerminalY = y
        gameState.pendingHackCharacterId = char.id
        gameState.addLog("📡 \(char.name) jacks into the matrix...")
        gameState.showMatrixMiniGame = true
    }

    /// Called by MatrixMiniGameView when the player either retrieves the data
    /// core (success=true) or dies/bails (success=false).
    static func resolveMatrixMiniGame(gameState: GameState, success: Bool) {
        let x = gameState.pendingHackTerminalX
        let y = gameState.pendingHackTerminalY
        let charName = gameState.pendingHackCharacterId
            .flatMap { id in gameState.playerTeam.first(where: { $0.id == id })?.name }
            ?? "Netrunner"
        gameState.showMatrixMiniGame = false
        gameState.pendingHackCharacterId = nil
        if !success {
            gameState.addLog("💥 \(charName) crashed out of the matrix — terminal still active.")
            SFXManager.shared.play("terminal_wrong", volume: 0.7)
            return
        }
        // Success — layer the rich win SFX on top of the hack_success chime.
        SFXManager.shared.play("terminal_correct", volume: 0.65)
        SFXManager.shared.play("mainframe_breach", volume: 0.6)
        // Success: replace tile with floor, mark data acquired, post visual.
        guard y >= 0, y < gameState.currentMissionTiles.count,
              x >= 0, x < gameState.currentMissionTiles[y].count else { return }
        gameState.currentMissionTiles[y][x] = TileType.floor.rawValue
        gameState.dataAcquired = true
        gameState.addLog("📡 \(charName) extracted the data — DATA ACQUIRED.")
        gameState.addLog("Now reach extraction at (\(gameState.extractionX), \(gameState.extractionY)).")
        NotificationCenter.default.post(
            name: .dataTerminalHacked,
            object: nil,
            userInfo: ["x": x, "y": y]
        )
    }

    static func showItemMenu(gameState: GameState) {
        gameState.isItemMenuVisible = true
    }

    static func completeAction(gameState: GameState, for character: Character) {
        CombatFlowController.setCombatPhase(gameState: gameState, .playerResolving)
        // Set active to this character so turn-advance marks the right one.
        gameState.activeCharacterId = character.id
        TurnManager.requestTurnAdvance(gameState: gameState)
    }

    /// Turn-advance implementation invoked by TurnManager ownership entrypoint.
    static func endTurn(gameState: GameState) {
        // NOTE: Do NOT set isPlayerTurn=false or block input here unless we're actually
        // transitioning to the enemy phase. Doing so prematurely disables action buttons
        // for the next player character in the round.
        gameState.isItemMenuVisible = false
        gameState.targetCharacterId = nil

        // Mark current active character as having acted this round.
        // ALWAYS remove from playersWhoHaveNotActed regardless of hasActedThisRound flag —
        // guards against the race condition where the flag was already set but the Set
        // removal was missed (e.g. character died mid-action or endTurn fired twice).
        if let activeId = gameState.activeCharacterId {
            if let char = gameState.playerTeam.first(where: { $0.id == activeId }) {
                char.hasActedThisRound = true
            }
            gameState.playersWhoHaveNotActed.remove(activeId)
        }

        gameState.currentTurnCount += 1
        gameState.playerTurnsCompleted += 1
        // Single-room stealth: end when turn window closes
        if RoomManager.shared.currentMission == nil
            && gameState.currentMissionType == .stealth
            && !gameState.missionComplete
            && gameState.currentTurnCount >= gameState.missionTargetTurns {
            gameState.finalizeCombatFromCombatFlow(
                won: true,
                missionLog: "MISSION COMPLETE — STEALTH WINDOW HELD FOR \(gameState.missionTargetTurns) TURNS"
            )
            return
        }
        // Multi-room stealth: only end on turn window if ALL rooms cleared (no partial completion)
        if gameState.currentMissionType == .stealth
            && RoomManager.shared.currentMission != nil
            && !gameState.missionComplete
            && gameState.currentTurnCount >= gameState.missionTargetTurns {
            if RoomManager.shared.areAllRoomsCleared {
                gameState.finalizeCombatFromCombatFlow(
                    won: true,
                    missionLog: "MISSION COMPLETE — STEALTH WINDOW HELD FOR \(gameState.missionTargetTurns) TURNS"
                )
            } else {
                gameState.addLog("Stealth window closed — clear remaining rooms!")
            }
            return
        }

        let living = gameState.playerTeam.filter { $0.isAlive }
        guard !living.isEmpty else {
            CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
            return
        }

        // Find next living character who hasn't acted this round.
        //
        // 2026-05-10 BUG FIX: was `playersWhoHaveNotActed.first` which is a
        // Set — non-deterministic. If A was the active character, user
        // tapped B in the roster, and B acted, the next pick could be C
        // or D instead of A — making A "feel" like they lost their turn.
        // Now iterates playerTeam in declaration order and picks the
        // first who hasn't acted yet, so original turn order is preserved
        // across mid-round selection changes.
        let nextChar = gameState.playerTeam.first { char in
            char.isAlive
                && gameState.playersWhoHaveNotActed.contains(char.id)
        }

        if let char = nextChar, gameState.playerTurnsCompleted < 4 {
            // More players still need to act — advance to next player without blocking input.
            gameState.activeCharacterId = char.id
            gameState.selectedCharacterId = char.id
            gameState.currentTurnIndex = gameState.playerTeam.firstIndex(where: { $0.id == char.id }) ?? 0
            CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)      // Stay in player phase — buttons must remain enabled
            gameState.isDefending = false
            gameState.defendingCharacterId = nil
            NotificationCenter.default.post(
                name: .turnChanged,
                object: nil,
                userInfo: ["characterId": char.id.uuidString]
            )
        } else {
            // Four player turns completed, or all living players have acted —
            // ALWAYS go through the enemy-phase entrypoint. enemyPhase() has its
            // own fast path for "no enemies" that processes delayed spawns,
            // which is critical for missions like M6 where every enemy starts
            // with a non-zero delay (without this, enemyPhaseCount never
            // advances and the spawns never trigger).
            CombatFlowController.setCombatPhase(gameState: gameState, .enemyResolving)
            gameState.currentTurnIndex = 0
            gameState.enemyPhaseCount += 1
            gameState.roundNumber += 1
            gameState.addLog("═══ ROUND \(gameState.roundNumber) ═══")
            HapticsManager.shared.roundStart()
            NotificationCenter.default.post(name: .roundStarted, object: nil, userInfo: ["round": gameState.roundNumber])
            CombatFlowController.enemyPhase(gameState: gameState)
        }
    }

    /// Centralised player-death handling. Call any time a player's HP just hit 0.
    /// Posts .playerDied so BattleScene can remove the sprite, plays the killed
    /// haptic, and runs checkCombatEnd so a TPK ends the run immediately rather
    /// than waiting for the next phase boundary.
    /// Process post-kill effects that fire ONCE per room — most importantly,
    /// dropping any "removeOnFirstKill" barriers defined on the active room.
    /// Caller must have already incremented `missionEnemiesDefeated`.
    static func handleEnemyKillForRoomEffects(gameState: GameState) {
        guard !gameState.firstKillProcessedInRoom else { return }
        gameState.firstKillProcessedInRoom = true
        guard let room = RoomManager.shared.currentRoom,
              let drops = room.removeOnFirstKill,
              !drops.isEmpty else { return }
        // Mutate the live tile grid so pathfinding immediately sees the
        // dropped barriers as floor.
        var tiles = gameState.currentMissionTiles
        var droppedCoords: [[String: Int]] = []
        for p in drops {
            guard p.y >= 0, p.y < tiles.count, p.x >= 0, p.x < tiles[p.y].count else { continue }
            tiles[p.y][p.x] = TileType.floor.rawValue
            droppedCoords.append(["x": p.x, "y": p.y])
        }
        gameState.currentMissionTiles = tiles
        gameState.addLog("⚙️ Security barriers retracted.")
        NotificationCenter.default.post(
            name: .barriersDropped,
            object: nil,
            userInfo: ["tiles": droppedCoords]
        )
    }

    static func handlePlayerKilled(gameState: GameState, char: Character) {
        guard !char.isAlive else { return }
        // Lock in the dead state. `isAlive` is `status != .dead && currentHP > 0`,
        // so HP=0 alone marks them dead — but if a future code path ever
        // restores HP (medkit-on-corpse bug, save/load round trip, etc.),
        // the corpse would silently revive. Setting status=.dead here means
        // even if HP comes back, isAlive stays false. Belt-and-suspenders.
        char.status = .dead
        HapticsManager.shared.playerKilled()
        gameState.addLog("💀 \(char.name) is DOWN!")
        // If the dead character had any active selection/turn, clear it so input
        // can't be routed to a corpse.
        if gameState.selectedCharacterId == char.id { gameState.selectedCharacterId = nil }
        if gameState.activeCharacterId == char.id { gameState.activeCharacterId = nil }
        gameState.playersWhoHaveNotActed.remove(char.id)
        NotificationCenter.default.post(
            name: .playerDied,
            object: nil,
            userInfo: ["playerId": char.id.uuidString]
        )
        CombatFlowController.checkCombatEnd(gameState: gameState)
    }

    static func checkCombatEnd(gameState: GameState) {
        // Idempotency guard: once combat has ended (victory or defeat), every
        // subsequent caller is a no-op. Without this, async enemy-phase
        // callbacks plus per-death calls can re-finalize and overwrite the
        // outcome (e.g. assault-victory then immediate TPK overwrite).
        guard !gameState.combatEnded else { return }
        // ASSAULT ENDING: only finalize if we're in a single-room mission or the LAST room of a multi-room mission.
        // Multi-room missions rely on extraction flow for victory (player reaches extraction tile after all rooms cleared).
        let isLastRoom: Bool
        if let mission = RoomManager.shared.currentMission,
           let currentRoom = RoomManager.shared.currentRoom,
           let idx = mission.rooms.firstIndex(where: { $0.id == currentRoom.id }) {
            isLastRoom = (idx == mission.rooms.count - 1)
        } else {
            isLastRoom = true // single-room mission
        }

        if gameState.currentMissionType == .assault
            && gameState.livingEnemies.isEmpty
            && gameState.pendingSpawns.isEmpty
            && isLastRoom {
            gameState.finalizeCombatFromCombatFlow(won: true, missionLog: "MISSION COMPLETE — ASSAULT TARGET ELIMINATED")
            return
        }

        if gameState.livingPlayers.isEmpty {
            gameState.finalizeCombatFromCombatFlow(
                won: false,
                missionLog: "MISSION FAILED — ALL UNITS DOWN",
                terminalLog: "=== DEFEAT ==="
            )
        }
    }

    static func enemyPhase(gameState: GameState) {
        guard !gameState.isEnemyPhaseRunning else { return }
        gameState.isEnemyPhaseRunning = true

        let livingEnemies = gameState.enemies.filter { $0.isAlive }
        let livingPlayers = gameState.playerTeam.filter { $0.isAlive }
        // Skip enemy phase if no enemies alive — post .enemyPhaseCompleted so player input unlocks.
        guard !livingEnemies.isEmpty else {
            gameState.processDelayedSpawns(enemyPhaseIndex: gameState.enemyPhaseCount)
            if gameState.livingEnemies.isEmpty && gameState.pendingSpawns.isEmpty {
                // Room is empty AND no spawns are pending. Try to deploy a
                // reinforcement wave (one per room) before declaring it cleared.
                // If a wave is queued, pendingSpawns becomes non-empty so the
                // door stays locked until those reinforcements are also killed.
                if !ReinforcementService.tryDeployReinforcements(gameState: gameState) {
                    gameState.onRoomCleared()
                }
            }
            gameState.isEnemyPhaseRunning = false
            CombatFlowController.beginRound(gameState: gameState)
            NotificationCenter.default.post(name: .enemyPhaseCompleted, object: nil)
            return
        }

        // Only show "Enemy Turn" badge AFTER we've confirmed there are enemies to act.
        NotificationCenter.default.post(name: .enemyPhaseBegan, object: nil)

        // If no players left, combat will end via checkCombatEnd() in the notify block.
        guard !livingPlayers.isEmpty else {
            gameState.isEnemyPhaseRunning = false
            CombatFlowController.beginRound(gameState: gameState)
            NotificationCenter.default.post(name: .enemyPhaseCompleted, object: nil)
            return
        }

        let group = DispatchGroup()
        let staggerDelay: TimeInterval = 0.18  // delay between enemy turns

        for (i, enemy) in livingEnemies.enumerated() {
            let delay = Double(i) * staggerDelay

            group.enter()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak gameState] in
                guard let gameState = gameState else { group.leave(); return }
                gameState.runEnemyAI(enemy: enemy, livingEnemies: livingEnemies)
                // Leave group only after the enemy's animations would have finished playing.
                // animateEnemyMove = 0.35s, playerHitEffect = 0.25s. Use 0.5s buffer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    group.leave()
                }
            }
        }

        // When ALL enemies have finished their turns + animation windows, finalize.
        group.notify(queue: .main) { [weak gameState] in
            guard let gameState = gameState else { return }
            gameState.processDelayedSpawns(enemyPhaseIndex: gameState.enemyPhaseCount)
            gameState.checkExtraction()
            CombatFlowController.checkCombatEnd(gameState: gameState)
            if gameState.combatEnded {
                gameState.isEnemyPhaseRunning = false
                NotificationCenter.default.post(name: .enemyPhaseCompleted, object: nil)
                return
            }
            gameState.isEnemyPhaseRunning = false
            // CRITICAL: reset hasActedThisRound for all players so they can act next round
            CombatFlowController.beginRound(gameState: gameState)
            // Signal BattleScene to unblock player input
            NotificationCenter.default.post(name: .enemyPhaseCompleted, object: nil)
            dlog("[GameState] enemyPhase: all enemies done, beginRound() called, .enemyPhaseCompleted posted")

            // Safety timeout: if .enemyPhaseCompleted notification fails to unblock input
            // (rare but possible if BattleScene observer is not registered), force-unblock
            // after 3 seconds so the player is never permanently locked out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak gameState] in
                guard let gameState = gameState else { return }
                if gameState.isPlayerInputBlocked && !gameState.combatEnded {
                    dlog("[GameState] Safety timeout: force-unblocking player input")
                    CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
                    NotificationCenter.default.post(name: .enemyPhaseCompleted, object: nil)
                }
            }
        }
    }

    static func isCharacterDefending(gameState: GameState, _ charId: UUID) -> Bool {
        return gameState.isDefending && gameState.defendingCharacterId == charId
    }

    static func showMoveMenu(gameState: GameState) {
        let char: Character
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else if let current = gameState.currentCharacter {
            char = current
        } else { return }
        gameState.addLog("\(char.name): tap a tile to move.")
    }

    static func performUseItem(gameState: GameState) {
        let char: Character
        if let selected = gameState.selectedCharacterId, let c = gameState.playerTeam.first(where: { $0.id == selected && $0.isAlive }) {
            char = c
        } else if let current = gameState.currentCharacter {
            char = current
        } else { gameState.addLog("No character to heal."); return }

        // Find a consumable item
        guard !CombatFlowController.characterHasAlreadyMoved(gameState: gameState, char) else { return }

        guard let idx = gameState.loot.firstIndex(where: { $0.type == .consumable }) else {
            gameState.addLog("No medkits available.")
            HapticsManager.shared.buttonTap()
            return
        }
        HapticsManager.shared.attackHit()
        let item = gameState.loot.remove(at: idx)
        char.currentHP = min(char.maxHP, char.currentHP + item.bonus)
        // Medkits also clear some stun damage (First Aid = treat stun & physical)
        char.recoverStun(amount: item.bonus / 2)
        gameState.addLog("\(char.name) uses \(item.name)! +\(item.bonus) HP, -\(item.bonus / 2) Stun. (HP \(char.currentHP)/\(char.maxHP) | Stun \(char.currentStun)/\(char.maxStun))")
        // HPBar/values are passed by-value (Int snapshots), so changes on the
        // Character object don't propagate to the GameState's observers
        // unless we explicitly poke objectWillChange. Without this, the UI
        // shows the OLD HP until the next gameState mutation.
        gameState.objectWillChange.send()
        CombatFlowController.completeAction(gameState: gameState, for: char)
    }

    static func selectCharacter(gameState: GameState, id: UUID) {
        if let char = gameState.playerTeam.first(where: { $0.id == id && $0.isAlive }) {
            gameState.selectedCharacterId = char.id
            gameState.activeCharacterId = char.id
            gameState.targetCharacterId = nil
            gameState.addLog("Selected: \(char.name)")
            NotificationCenter.default.post(
                name: .characterSelected,
                object: nil,
                userInfo: ["characterId": char.id.uuidString]
            )
        }
    }

    /// Request path for scene/UI attack intent against a specific enemy.
    static func requestAttackOnEnemy(gameState: GameState, enemyId: UUID) {
        gameState.targetCharacterId = enemyId
        CombatFlowController.performAttack(gameState: gameState)
    }

    /// Request path for scene-driven selection updates; selection intent only.
    static func requestCharacterSelectionFromScene(gameState: GameState, id: UUID) {
        guard gameState.playerTeam.contains(where: { $0.id == id && $0.isAlive }) else { return }
        gameState.selectedCharacterId = id
        gameState.activeCharacterId = id
        gameState.targetCharacterId = nil
    }

    /// Scene callback when enemy phase has fully completed and control returns to player.
    static func restorePlayerControlAfterEnemyPhase(gameState: GameState) {
        CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)

        if let char = gameState.findNextLivingCharacter(after: 0) {
            gameState.activeCharacterId = char.id
            gameState.selectedCharacterId = char.id
            NotificationCenter.default.post(
                name: .turnChanged,
                object: nil,
                userInfo: ["characterId": char.id.uuidString]
            )
        }
    }

    static func handleTileTap(gameState: GameState, tileX: Int, tileY: Int) {
        if let char = gameState.playerTeam.first(where: { $0.positionX == tileX && $0.positionY == tileY && $0.isAlive }) {
            gameState.selectedCharacterId = char.id
            gameState.targetCharacterId = nil
            gameState.addLog("Selected: \(char.name)")
            NotificationCenter.default.post(name: .characterSelected, object: nil, userInfo: ["characterId": char.id.uuidString])
            return
        }

        if let enemy = gameState.enemies.first(where: { $0.positionX == tileX && $0.positionY == tileY && $0.isAlive }) {
            if gameState.selectedCharacterId == nil { gameState.addLog("Select a character first."); return }
            gameState.targetCharacterId = enemy.id
            gameState.addLog("Targeting: \(enemy.name)")
            return
        }

        if let selectedId = gameState.selectedCharacterId,
           let char = gameState.playerTeam.first(where: { $0.id == selectedId && $0.isAlive }) {
            let moveDistance = gameState.hexDistance(x1: tileX, y1: tileY, x2: char.positionX, y2: char.positionY)
            if moveDistance >= 1 && moveDistance <= 2 {
                CombatFlowController.moveCharacter(gameState: gameState, id: char.id, toTileX: tileX, toTileY: tileY)
            }
            // Silent no-op when tap is too far — see BattleScene.handleTileTap
            // for full reasoning. Avoids the misleading "out of range" message
            // firing during ranged attack workflows.
            return
        }

        gameState.addLog("Empty tile: (\(tileX),\(tileY))")
    }

    /// Extraction is a request path; CombatFlowController owns extraction outcome adjudication.
    static func requestExtraction(
        gameState: GameState,
        characterId: UUID?,
        tileX: Int,
        tileY: Int
    ) -> Bool {
        guard !gameState.combatEnded else { return false }
        CombatFlowController.setCombatPhase(gameState: gameState, .extractRequested)

        guard tileX == gameState.extractionX && tileY == gameState.extractionY else {
            CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
            gameState.addLog("That is not the extraction point.")
            return false
        }

        if RoomManager.shared.currentMission != nil {
            guard RoomManager.shared.isExtractionActive() else {
                CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
                gameState.addLog("Extraction is locked until every room is clear.")
                return false
            }
        }

        guard let id = characterId,
              let char = gameState.playerTeam.first(where: { $0.id == id && $0.isAlive }) else {
            CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
            gameState.addLog("Select a character, then step onto extraction.")
            return false
        }

        // Keep model-space position aligned with tile tap before adjudication.
        char.positionX = tileX
        char.positionY = tileY

        let hasActiveThreats = RoomManager.shared.currentMission != nil
            ? !gameState.livingEnemies.isEmpty
            : !(gameState.livingEnemies.isEmpty && gameState.pendingSpawns.isEmpty)

        if hasActiveThreats {
            CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
            gameState.addLog("Clear all enemies before extraction!")
            return false
        }

        if gameState.missionRequiresData && !gameState.dataAcquired {
            CombatFlowController.setCombatPhase(gameState: gameState, .playerInput)
            gameState.addLog("Hack the data terminal first — extraction is locked.")
            return false
        }

        adjudicateExtractionIfEligible(gameState: gameState)
        return true
    }

    /// Owner path for extraction mission completion resolution.
    static func adjudicateExtractionIfEligible(gameState: GameState) {
        let isMultiRoomMission = RoomManager.shared.currentMission != nil
        guard isMultiRoomMission || gameState.currentMissionType == .extraction else { return }
        if isMultiRoomMission {
            guard gameState.livingEnemies.isEmpty else { return }
        } else {
            guard gameState.livingEnemies.isEmpty && gameState.pendingSpawns.isEmpty else { return }
        }
        if RoomManager.shared.currentMission != nil {
            guard RoomManager.shared.isExtractionActive() else { return }
        }
        guard !gameState.missionRequiresData || gameState.dataAcquired else { return }

        let onExtraction = gameState.livingPlayers.contains {
            $0.positionX == gameState.extractionX && $0.positionY == gameState.extractionY
        }

        if onExtraction {
            // Idempotency: bail if extraction is already animating. Prevents
            // double-tap stacking two helicopters / two finalize calls.
            guard !gameState.extractionAnimationInProgress else { return }
            gameState.extractionAnimationInProgress = true
            CombatFlowController.setCombatOutcome(gameState: gameState, .extracted)
            // Defer the actual finalize until the extraction animation finishes.
            gameState.addLog("🚁 EXTRACTION SUCCESS — Runners are out!")
            NotificationCenter.default.post(
                name: .extractionAnimationRequested,
                object: nil,
                userInfo: ["x": gameState.extractionX, "y": gameState.extractionY]
            )
            // Safety net: finalize after 14s if the animation observer
            // doesn't run for any reason. 2026-05-10: bumped 11s → 14s after
            // waitOnPad raised to 2.2s (full animation now ~9.8s); the old
            // 11s margin was too tight and would surface the debrief while
            // the chopper was still ascending.
            DispatchQueue.main.asyncAfter(deadline: .now() + 14.0) { [weak gameState] in
                guard let gs = gameState, !gs.combatEnded else { return }
                CombatFlowController.finalizeExtractionAfterAnimation(gameState: gs)
            }
        }
    }

    /// Called by BattleScene when the helicopter extraction animation finishes
    /// (or by the safety timer in adjudicateExtractionIfEligible).
    /// Idempotent — safe to call multiple times.
    static func finalizeExtractionAfterAnimation(gameState: GameState) {
        guard !gameState.combatEnded else { return }
        // Clear the in-flight flag BEFORE finalize. Otherwise syncLegacyState
        // (which we made aware of extractionInFlight) refuses to latch
        // combatEnded/missionComplete on terminal outcomes — and the
        // debrief overlay never shows.
        gameState.extractionAnimationInProgress = false
        gameState.finalizeCombatFromCombatFlow(
            won: true,
            missionLog: "🚁 EXTRACTION SUCCESS — Runners are out!",
            terminalLog: "=== VICTORY ==="
        )
    }

    /// Combined finalize — resets animation state, posts completion
    /// notification, and ends combat. Safe to call multiple times
    /// (finalizeExtractionAfterAnimation is idempotent via combatEnded guard).
    /// Used by the helicopter animation's onComplete and 10s safety net so
    /// the mission reliably returns to the menu after extraction.
    @MainActor
    static func completeExtractionFinalize() {
        let gameState = GameState.shared
        gameState.extractionAnimationInProgress = false
        NotificationCenter.default.post(name: .extractionAnimationCompleted, object: nil)
        finalizeExtractionAfterAnimation(gameState: gameState)
    }
}
