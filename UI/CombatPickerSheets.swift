import SwiftUI

// Extracted from CombatUI.swift (WP5 decomposition) — pure move.

// MARK: - Spell Picker Sheet

struct SpellPickerSheet: View {
    @ObservedObject var gameState: GameState
    @Binding var showingPicker: Bool

    /// True while the player is choosing which ally to heal — replaces the
    /// spell list with a roster of party members.
    @State private var showingHealTargetPicker: Bool = false

    private var mage: Character? {
        (gameState.activeCharacter ?? gameState.currentCharacter).flatMap {
            $0.archetype == .mage ? $0 : nil
        }
    }

    /// Living party members eligible for HEAL targeting.
    private var healableTargets: [Character] {
        gameState.playerTeam.filter { $0.isAlive }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            ZStack {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            CornerBracket(color: Color(hex: "6699FF"))
                            Spacer()
                        }
                        Spacer()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer()
                            CornerBracket(color: Color(hex: "AA44FF"))
                                .scaleEffect(x: -1)
                        }
                        Spacer()
                    }
                }
                .frame(height: 20)

                HStack {
                    Text("SPELLBOOK")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(hex: "6699FF"))
                        .tracking(2)
                    Spacer()
                    if let m = mage {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "6699FF"))
                            Text("\(m.currentMana)/\(m.maxMana)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "6699FF"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "6699FF").opacity(0.15))
                        .cornerRadius(6)
                    }
                    Button(action: { showingPicker = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(CombatTheme.textMuted)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }

            // Heal target picker overrides the spell list when active.
            if showingHealTargetPicker {
                healTargetPickerBody
            } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(mage?.knownSpells ?? SpellType.allCases.filter { $0.isBaseSpell }, id: \.self) { spell in
                        let canCast = (mage?.currentMana ?? 0) >= spell.manaCost
                        Button(action: {
                            guard canCast else { return }
                            HapticsManager.shared.buttonTap()
                            // HEAL needs a target — show the party-member
                            // picker instead of casting immediately.
                            if spell == .heal {
                                showingHealTargetPicker = true
                                return
                            }
                            showingPicker = false
                            gameState.performSpell(type: spell)
                        }) {
                            HStack(spacing: 12) {
                                // Spell icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(hex: spell.colorHex).opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: spell.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(Color(hex: spell.colorHex))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(spell.displayName.uppercased())
                                            .font(.system(size: 13, weight: .black))
                                            .foregroundColor(canCast ? .white : CombatTheme.textMuted)
                                            .tracking(1)
                                        if spell.isAreaOfEffect {
                                            Text("AoE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(Color(hex: "FF4422"))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(hex: "FF4422").opacity(0.18))
                                                .cornerRadius(3)
                                        }
                                    }
                                    Text(spell.description)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(CombatTheme.textMuted)
                                        .lineLimit(2)
                                }

                                Spacer()

                                // Mana cost badge
                                VStack(spacing: 2) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 9))
                                        .foregroundColor(canCast ? Color(hex: "6699FF") : CombatTheme.textMuted)
                                    Text("\(spell.manaCost)")
                                        .font(.system(size: 14, weight: .black, design: .monospaced))
                                        .foregroundColor(canCast ? Color(hex: "6699FF") : CombatTheme.textMuted)
                                }
                                .frame(width: 28)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(canCast ? CombatTheme.panelBG : CombatTheme.panelBG.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                canCast ? Color(hex: spell.colorHex).opacity(0.4) : CombatTheme.panelEdge,
                                                lineWidth: canCast ? 1.5 : 1
                                            )
                                    )
                            )
                            .opacity(canCast ? 1.0 : 0.5)
                        }
                        .disabled(!canCast)
                    }
                }
            }
            }   // end of else branch (spell list)
        }
        .padding(16)
        .background(CombatTheme.panelBG)
        .cornerRadius(16)
        .padding(20)
    }

    // MARK: - Heal target picker

    /// Roster of living allies — tap one to cast HEAL on them. Replaces the
    /// spell-list region while `showingHealTargetPicker == true`.
    @ViewBuilder
    private var healTargetPickerBody: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: {
                    HapticsManager.shared.buttonTap()
                    showingHealTargetPicker = false
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(hex: "6699FF"))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Text("HEAL — PICK A TARGET")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "6699FF"))
                Spacer()
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(healableTargets, id: \.id) { ally in
                        Button(action: {
                            HapticsManager.shared.buttonTap()
                            showingHealTargetPicker = false
                            showingPicker = false
                            gameState.performSpell(type: .heal, targetId: ally.id)
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(archetypeColor(ally.archetype).opacity(0.18))
                                        .frame(width: 44, height: 44)
                                    Text(String(ally.name.prefix(1)).uppercased())
                                        .font(.system(size: 18, weight: .black, design: .monospaced))
                                        .foregroundColor(archetypeColor(ally.archetype))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(ally.name)
                                            .font(.system(size: 13, weight: .black))
                                            .foregroundColor(.white)
                                        if ally.id == mage?.id {
                                            Text("(self)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(CombatTheme.textMuted)
                                        }
                                    }
                                    Text("HP \(ally.currentHP)/\(ally.maxHP)  •  Stun \(ally.currentStun)/\(ally.maxStun)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(CombatTheme.textMuted)
                                }
                                Spacer()
                                Image(systemName: "cross.fill")
                                    .foregroundColor(Color(hex: "44CC88"))
                                    .font(.system(size: 18))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(CombatTheme.panelBG)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(archetypeColor(ally.archetype).opacity(0.4), lineWidth: 1.2)
                                    )
                            )
                        }
                    }
                }
            }
        }
    }

    private func archetypeColor(_ archetype: CharacterArchetype) -> Color {
        switch archetype {
        case .streetSam: return Color(hex: "FF6633")
        case .mage:    return Color(hex: "6699FF")
        case .decker:  return Color(hex: "00DDFF")
        case .face:    return Color(hex: "FFCC00")
        }
    }
}

// MARK: - Item Picker Sheet

struct ItemPickerSheet: View {
    @ObservedObject var gameState: GameState
    @Binding var showingPicker: Bool
    let onUseItem: () -> Void

    private var usableItems: [GameState.Item] {
        gameState.loot.filter { $0.type == .consumable || $0.type == .grenade }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header with corner brackets
            ZStack {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            CornerBracket(color: CombatTheme.neonPink)
                            Spacer()
                        }
                        Spacer()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer()
                            CornerBracket(color: CombatTheme.neonBlue)
                                .scaleEffect(x: -1)
                        }
                        Spacer()
                    }
                }
                .frame(height: 20)

                HStack {
                    Text("ITEMS")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(CombatTheme.accent)
                        .tracking(2)
                    Spacer()
                    Button(action: { showingPicker = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(CombatTheme.textMuted)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }

            if usableItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cross.case")
                        .font(.largeTitle)
                        .foregroundColor(CombatTheme.textMuted)
                    Text("No medkits available")
                        .font(.subheadline)
                        .foregroundColor(CombatTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(usableItems) { item in
                            Button(action: {
                                HapticsManager.shared.buttonTap()
                                guard let idx = gameState.loot.firstIndex(where: { $0.id == item.id }) else {
                                    showingPicker = false
                                    return
                                }
                                let chosen = gameState.loot[idx]
                                // Pick the SELECTED character first (the one the
                                // player has chosen on screen) — earlier this
                                // fell through to activeCharacter, which often
                                // pointed to a different runner so the heal
                                // appeared to do nothing on the unit the
                                // player was looking at.
                                let target: Character? = {
                                    if let id = gameState.selectedCharacterId,
                                       let c = gameState.playerTeam.first(where: { $0.id == id && $0.isAlive }) {
                                        return c
                                    }
                                    return gameState.activeCharacter ?? gameState.currentCharacter
                                }()
                                guard let char = target else {
                                    showingPicker = false
                                    return
                                }

                                let isManaItem = chosen.name.lowercased().contains("mana")
                                               || chosen.name.lowercased().contains("focus")
                                let isGrenade = chosen.name.lowercased().contains("grenade")

                                if isGrenade {
                                    guard let targetId = gameState.targetCharacterId,
                                          gameState.enemies.contains(where: { $0.id == targetId && $0.isAlive }) else {
                                        gameState.addLog("Select an enemy before using \(chosen.name).")
                                        showingPicker = false
                                        return
                                    }
                                    let removed = gameState.loot.remove(at: idx)
                                    if gameState.throwGrenade(item: removed, by: char) {
                                        gameState.consumeRosterItem(removed)
                                    } else {
                                        gameState.loot.insert(removed, at: min(idx, gameState.loot.count))
                                    }
                                    showingPicker = false
                                    return
                                }

                                // Don't consume the item if it can't actually do anything
                                // for the chosen target — show a message and bail out so
                                // the player can pick a different runner.
                                if isManaItem {
                                    if char.maxMana <= 0 {
                                        gameState.addLog("\(char.name) can't channel — \(chosen.name) cancelled.")
                                        showingPicker = false
                                        return
                                    }
                                    if char.currentMana >= char.maxMana {
                                        gameState.addLog("\(char.name) is at full Mana — \(chosen.name) cancelled.")
                                        showingPicker = false
                                        return
                                    }
                                } else {
                                    if char.currentHP >= char.maxHP && char.currentStun <= 0 {
                                        gameState.addLog("\(char.name) is already at full HP — \(chosen.name) cancelled.")
                                        showingPicker = false
                                        return
                                    }
                                }

                                // Commit: remove the item AFTER we've confirmed it'll do something.
                                let removed = gameState.loot.remove(at: idx)
                                gameState.consumeRosterItem(removed)

                                if isManaItem {
                                    let before = char.currentMana
                                    let restored = min(char.maxMana, before + removed.bonus)
                                    char.currentMana = restored
                                    let delta = restored - before
                                    gameState.addLog("\(char.name) uses \(removed.name)! +\(delta) Mana. (\(char.currentMana)/\(char.maxMana))")
                                } else {
                                    // Apply heal via the character's own heal() method so
                                    // any stat-watching observers in Character fire correctly,
                                    // then echo it through the @Published assignment too
                                    // (defense-in-depth — the original direct assignment
                                    // worked but a recent SwiftUI change can occasionally
                                    // drop the publish if the value is set on a copy).
                                    let before = char.currentHP
                                    char.heal(amount: removed.bonus)
                                    if char.currentHP == before {
                                        // Fallback: ensure the @Published mutation publishes.
                                        char.currentHP = min(char.maxHP, before + removed.bonus)
                                    }
                                    let actualHeal = char.currentHP - before
                                    char.recoverStun(amount: removed.bonus / 2)
                                    // Using a heal item was silent — give it the heal cue.
                                    SFXManager.shared.play("spell_heal", volume: 0.7)
                                    gameState.addLog("\(char.name) uses \(removed.name)! +\(actualHeal) HP. (\(char.currentHP)/\(char.maxHP))")
                                    // Visual: green particle bloom + "+N HP"
                                    // floating text on the target. Same effect
                                    // the mage's HEAL spell uses, so item +
                                    // spell heals look consistent.
                                    NotificationCenter.default.post(
                                        name: .healEffect, object: nil,
                                        userInfo: ["targetId": char.id.uuidString,
                                                   "amount": actualHeal]
                                    )
                                }
                                HapticsManager.shared.attackHit()
                                gameState.completeAction(for: char)
                                showingPicker = false
                            }) {
                                HStack {
                                    Image(systemName: itemIcon(for: item))
                                        .foregroundColor(itemColor(for: item))
                                        .font(.system(size: 22))
                                        .frame(width: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(itemEffectText(for: item))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(itemColor(for: item))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(CombatTheme.textMuted)
                                        .font(.caption)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(CombatTheme.panelBG)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(CombatTheme.panelEdge, lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(CombatTheme.panelBG)
        .cornerRadius(16)
        .padding(20)
    }

    private func itemIcon(for item: GameState.Item) -> String {
        if item.name.lowercased().contains("grenade") { return "circle.hexagongrid.fill" }
        if item.name.lowercased().contains("mana") || item.name.lowercased().contains("focus") { return "sparkles" }
        switch item.type {
        case .consumable: return "cross.case.fill"
        case .weapon:    return "flame.fill"
        case .armor:     return "shield.fill"
        case .grenade:   return "circle.hexagongrid.fill"
        }
    }

    private func itemColor(for item: GameState.Item) -> Color {
        if item.name.lowercased().contains("grenade") { return CombatTheme.damage }
        if item.name.lowercased().contains("mana") || item.name.lowercased().contains("focus") { return Color(hex: "6699FF") }
        switch item.type {
        case .consumable: return CombatTheme.accent
        case .weapon:    return CombatTheme.damage
        case .armor:     return Color(hex: "8866FF")
        case .grenade:   return CombatTheme.damage
        }
    }

    private func itemEffectText(for item: GameState.Item) -> String {
        if item.name.lowercased().contains("grenade") { return "\(item.bonus)P AP-2 BLAST" }
        if item.name.lowercased().contains("mana") || item.name.lowercased().contains("focus") { return "+\(item.bonus) MANA" }
        return "+\(item.bonus) HP"
    }
}
