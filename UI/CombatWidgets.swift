import SwiftUI

// Extracted from CombatUI.swift (WP5 decomposition) — pure move.
// MARK: - HP Bar

struct HPBar: View {
    let current: Int
    let max: Int

    private var pct: Double {
        guard max > 0 else { return 0 }
        return min(1.0, Swift.max(0, Double(current) / Double(max)))
    }

    private var barColor: Color {
        pct > 0.6 ? CombatTheme.accent
        : pct > 0.3 ? Color.yellow
        : CombatTheme.enemyColor
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.6))
                Capsule()
                    .fill(barColor)
                    .frame(width: geo.size.width * pct)
                    .animation(.easeInOut(duration: 0.3), value: pct)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - XP Bar

struct XPBar: View {
    let xp: Int
    let level: Int

    private var pct: Double {
        let threshold = level * 100
        return min(1.0, Swift.max(0, Double(xp) / Double(threshold)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.4))
                Capsule()
                    .fill(CombatTheme.gold)
                    .frame(width: geo.size.width * pct)
                    .animation(.easeInOut(duration: 0.4), value: pct)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Stun Bar (SR5 stun damage track — yellow/orange)

struct StunBar: View {
    let current: Int
    let max: Int

    private var pct: Double {
        guard max > 0 else { return 0 }
        return min(1.0, Swift.max(0, Double(current) / Double(max)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.6))
                Capsule()
                    .fill(pct > 0.7 ? Color(hex: "FF4400") : Color(hex: "FFAA00"))
                    .frame(width: geo.size.width * pct)
                    .animation(.easeInOut(duration: 0.3), value: pct)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Mana Bar

struct ManaBar: View {
    let current: Int
    let max: Int

    private var pct: Double {
        guard max > 0 else { return 0 }
        return min(1.0, Swift.max(0, Double(current) / Double(max)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.6))
                Capsule()
                    .fill(Color(hex: "6699FF"))
                    .frame(width: geo.size.width * pct)
                    .animation(.easeInOut(duration: 0.3), value: pct)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Character Portrait Badge

struct PortraitBadge: View {
    let name: String
    let archetype: CharacterArchetype
    let color: Color
    let isDefending: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isDefending ? 0.1 : 0.2))
                .frame(width: 28, height: 28)
            Circle()
                .stroke(color.opacity(isDefending ? 0.15 : 1.0), lineWidth: isDefending ? 1.0 : 1.5)
                .frame(width: 28, height: 28)
            VStack(spacing: 0) {
                Text(String(name.prefix(1)))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(color)
                if isDefending {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 5))
                        .foregroundColor(Color(hex: "4488FF"))
                        .offset(y: -1)
                }
            }
        }
    }
}

// MARK: - Team Roster Bar

struct TeamRosterBar: View {
    @ObservedObject var gameState: GameState

    private func archetypeColor(_ archetype: CharacterArchetype) -> Color {
        switch archetype {
        case .streetSam: return Color(hex: "FF6633")
        case .mage:    return Color(hex: "6699FF")
        case .decker:  return Color(hex: "00DDFF")
        case .face:    return Color(hex: "FFCC00")
        }
    }

    private func archetypeIcon(_ archetype: CharacterArchetype) -> String {
        switch archetype {
        case .streetSam: return "flame.fill"
        case .mage:    return "sparkles"
        case .decker:  return "cpu"
        case .face:    return "person.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(gameState.playerTeam, id: \.id) { char in
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(archetypeColor(char.archetype).opacity(0.2))
                            .frame(width: 32, height: 32)

                        // Gold border glow if selected
                        if gameState.activeCharacter?.id == char.id {
                            Circle()
                                .stroke(CombatTheme.gold, lineWidth: 2)
                                .frame(width: 32, height: 32)
                                .shadow(color: CombatTheme.gold.opacity(0.6), radius: 4)
                        } else {
                            Circle()
                                .stroke(archetypeColor(char.archetype).opacity(0.7), lineWidth: 1.5)
                                .frame(width: 32, height: 32)
                        }

                        // Character state
                        if char.currentHP <= 0 {
                            VStack(spacing: 0) {
                                Image(systemName: "skull.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(CombatTheme.enemyColor)
                            }
                            .opacity(0.6)
                        } else {
                            VStack(spacing: 0) {
                                Text(String(char.name.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundColor(archetypeColor(char.archetype))
                            }
                        }

                        // "Acted" indicator dot — archetype color if can still act, gray if done
                        Circle()
                            .fill(char.hasActedThisRound
                                  ? Color.gray.opacity(0.35)
                                  : archetypeColor(char.archetype).opacity(0.9))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.5), lineWidth: 0.5)
                            )
                            .offset(x: 12, y: -12)
                    }

                    // Physical HP bar
                    GeometryReader { geo in
                        let hpPct = Swift.max(0, Double(char.currentHP) / Double(char.maxHP))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.5))
                            Capsule()
                                .fill(hpPct > 0.3 ? Color.green : CombatTheme.enemyColor)
                                .frame(width: geo.size.width * hpPct)
                        }
                    }
                    .frame(height: 3)

                    // Stun track (yellow-orange, SR5 stun damage)
                    GeometryReader { geo in
                        let stunPct = Swift.max(0, Double(char.currentStun) / Double(char.maxStun))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.4))
                            Capsule()
                                .fill(Color(hex: "FFAA00").opacity(0.85))
                                .frame(width: geo.size.width * stunPct)
                        }
                    }
                    .frame(height: 2)

                    // Character name
                    Text(char.name.prefix(4).lowercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(CombatTheme.textMuted)
                }
                .frame(width: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticsManager.shared.buttonTap()
                    gameState.selectCharacter(id: char.id)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CombatTheme.darkPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CombatTheme.panelEdge, lineWidth: 1)
                )
        )
    }
}

// MARK: - Status Display

struct StatusDisplay: View {
    @ObservedObject var gameState: GameState

    private var char: Character? {
        gameState.activeCharacter ?? gameState.currentCharacter
    }

    private func archetypeIcon(_ archetype: CharacterArchetype) -> String {
        switch archetype {
        case .streetSam: return "flame.fill"
        case .mage:    return "sparkles"
        case .decker:  return "cpu"
        case .face:    return "person.fill"
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

    var body: some View {
        if let c = char {
            HStack(spacing: 8) {
                // Compact avatar
                PortraitBadge(
                    name: c.name,
                    archetype: c.archetype,
                    color: CombatTheme.accent,
                    isDefending: gameState.isDefending
                )

                // Name + level inline with archetype icon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: archetypeIcon(c.archetype))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(archetypeColor(c.archetype))
                        // .lineLimit(1) prevents the name from wrapping into a
                        // vertical stack of single letters when the parent
                        // HStack is space-starved. (Tried .fixedSize too —
                        // that caused the StatusDisplay to over-allocate
                        // width, exploding the HUD vertically and leaving
                        // dead black space. lineLimit(1) alone is sufficient
                        // — SwiftUI truncates instead of wrapping.)
                        Text(c.name)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(gameState.isDefending ? .gray : .white)
                            .lineLimit(1)
                        Text("LV\(c.level)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(CombatTheme.gold)
                            .cornerRadius(3)
                    }

                    // Weapon name in small muted text — shows the character's
                    // OWN equipped weapon (was incorrectly reading from
                    // gameState.loot.first, which made every character's HUD
                    // say "combat knife" the moment anyone picked one up).
                    // Clamped to one line + truncated so a long weapon name
                    // can't drive the column wider.
                    if let weapon = c.equippedWeapon {
                        Text(weapon.name)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    HPBar(current: c.currentHP, max: c.maxHP)
                        .frame(height: 6)

                    // Stun track (SR5 stun damage — yellow bar)
                    if c.currentStun > 0 || c.maxStun > 0 {
                        HStack(spacing: 3) {
                            Text("S")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "FFAA00"))
                            StunBar(current: c.currentStun, max: c.maxStun)
                            Text("\(c.currentStun)/\(c.maxStun)")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(Color(hex: "FFAA00").opacity(0.7))
                        }
                        .frame(height: 5)
                    }

                    // Mana bar for mages
                    if c.maxMana > 0 {
                        ManaBar(current: c.currentMana, max: c.maxMana)
                    }
                }

                Spacer()

                // (Removed 2026-05-10: redundant right-side mana display
                // for mages/deckers. The ManaBar in the VStack above already
                // shows it, and the extra widget was competing for
                // horizontal width on iPhone when the right-side IntelMetric
                // row included DATA CORE — squeezing the name column and
                // making "Sable"/"Cipher" wrap one letter per line.)

                // Turn indicator
                if gameState.isPlayerInputPhase {
                    if gameState.isDefending {
                        Text("DEF")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: "4488FF"))
                            .cornerRadius(3)
                    } else {
                        Text("TURN")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(CombatTheme.accent)
                            .cornerRadius(3)
                    }
                }
            }
            // Slimmed 2026-05 — vertical padding 6 → 3 — to recover space for
            // the play map. Avatar still anchors the panel; bars get tighter
            // but everything stays legible.
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                CombatTheme.panelBG,
                                CombatTheme.panelBG.opacity(0.7)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(gameState.isDefending ? CombatTheme.secondary.opacity(0.6) : CombatTheme.panelEdge, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Action Buttons

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    var disabled: Bool = false
    var disabledReason: String? = nil
    /// Optional press-and-hold action (e.g. hold SHT to enter overwatch). When
    /// set, a long press fires this instead of the normal tap `action`.
    var longPressAction: (() -> Void)? = nil

    @State private var pressed = false
    @State private var didLongPress = false
    // iPad (regular width) reads bigger icons/labels; iPhone (compact) unchanged.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            // A completed long press already handled this touch — swallow the
            // trailing tap so we don't also fire the normal action.
            if didLongPress { didLongPress = false; return }
            HapticsManager.shared.buttonTap()
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(disabled
                          ? Color.black.opacity(0.3)
                          : color.opacity(pressed ? 0.4 : 0.2))
                RoundedRectangle(cornerRadius: 6)
                    .stroke(disabled
                            ? color.opacity(0.2)
                            : color.opacity(pressed ? 1.0 : 0.7), lineWidth: pressed ? 1.5 : 1)

                // Diagonal stripe pattern overlay when disabled
                if disabled {
                    Canvas { context, size in
                        var path = Path()
                        let spacing: CGFloat = 4
                        for i in stride(from: -size.height, through: size.width, by: spacing) {
                            path.move(to: CGPoint(x: i, y: 0))
                            path.addLine(to: CGPoint(x: i + size.height, y: size.height))
                        }
                        context.stroke(
                            path,
                            with: .color(color.opacity(0.15)),
                            lineWidth: 1
                        )
                    }
                }

                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: isPad ? (disabledReason == nil ? 24 : 19)
                                                   : (disabledReason == nil ? 17 : 14)))
                    Text(title.uppercased())
                        .font(.system(size: isPad ? 13 : 9, weight: .black))
                        .tracking(0.3)
                    if disabled, let disabledReason {
                        Text(disabledReason)
                            .font(.system(size: isPad ? 8 : 6.2, weight: .black, design: .monospaced))
                            .tracking(0)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .foregroundColor(color.opacity(0.90))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.55))
                                    .overlay(
                                        Capsule()
                                            .stroke(color.opacity(0.35), lineWidth: 0.5)
                                    )
                            )
                    }
                }
                .foregroundColor(disabled ? Color.white.opacity(0.3) : (pressed ? .white : Color.white.opacity(0.9)))
            }
            .frame(width: width, height: height)
            .shadow(color: disabled ? .clear : color.opacity(pressed ? 0.4 : 0.15), radius: pressed ? 4 : 2, x: 0, y: 0)
            // Colored bottom border
            .overlay(
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(disabled ? color.opacity(0.3) : color)
                        .frame(height: 2)
                }
            )
        }
        .scaleEffect(pressed && !disabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.08), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !disabled { if !pressed { didLongPress = false }; pressed = true } }
                .onEnded { _ in pressed = false }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    guard !disabled, let longPressAction else { return }
                    didLongPress = true
                    HapticsManager.shared.selectionChanged()
                    longPressAction()
                }
        )
    }
}

struct ActionBar: View {
    let onAttack: () -> Void
    let onShoot: () -> Void
    /// Press-and-hold SHT to enter overwatch (hold fire / reaction shot).
    let onOverwatch: () -> Void
    let onDefend: () -> Void
    let onItems: () -> Void
    let onSpecial: (() -> Void)?
    let specialTitle: String
    let specialIcon: String
    let specialColor: Color
    let onEndTurn: () -> Void
    var actionDisabled: Bool = false
    var endTurnDisabled: Bool = false
    var attackDisabledReason: String? = nil
    var shootDisabledReason: String? = nil
    var specialDisabledReason: String? = nil
    var itemDisabledReason: String? = nil
    /// When true, the SHT button is greyed out (e.g. Street Samurai is melee
    /// only and can't shoot).
    var shootDisabled: Bool = false

    // iPad gets bigger, more tappable buttons + more breathing room; iPhone
    // (compact width) keeps the original 56×54 / spacing-5 layout exactly.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    private var bw: CGFloat { isPad ? 92 : 56 }
    private var bh: CGFloat { isPad ? 76 : 54 }
    private var gap: CGFloat { isPad ? 10 : 5 }

    var body: some View {
        HStack(spacing: gap) {
            ActionButton(title: "ATK", icon: "flame.fill", color: CombatTheme.damage, width: bw, height: bh, action: onAttack, disabled: actionDisabled || attackDisabledReason != nil, disabledReason: attackDisabledReason)
            ActionButton(title: "SHT", icon: "scope", color: Color(hex: "00D4FF"), width: bw, height: bh, action: onShoot, disabled: actionDisabled || shootDisabled || shootDisabledReason != nil, disabledReason: shootDisabledReason, longPressAction: (actionDisabled || shootDisabled || shootDisabledReason != nil) ? nil : onOverwatch)
            ActionButton(title: "DEF", icon: "shield.fill", color: CombatTheme.secondary, width: bw, height: bh, action: onDefend, disabled: actionDisabled)
            if let onSpecial {
                ActionButton(title: specialTitle, icon: specialIcon, color: specialColor, width: bw, height: bh, action: onSpecial, disabled: actionDisabled || specialDisabledReason != nil, disabledReason: specialDisabledReason)
            }
            ActionButton(title: "ITM", icon: "cross.case.fill", color: Color(hex: "8866FF"), width: bw, height: bh, action: onItems, disabled: actionDisabled || itemDisabledReason != nil, disabledReason: itemDisabledReason)
            ActionButton(title: "END", icon: "arrow.right.circle.fill", color: CombatTheme.accent, width: bw, height: bh, action: onEndTurn, disabled: endTurnDisabled)
        }
    }
}

// MARK: - Combat Log

struct CombatLogView: View {
    @ObservedObject var gameState: GameState

    private var recentEntries: [String] {
        Array(gameState.combatLog.suffix(3))
    }

    private func hasMoreEntries() -> Bool {
        gameState.combatLog.count > 3
    }

    private func entryColor(_ text: String) -> Color {
        if text.contains("VICTORY") || text.contains("LEVEL UP") || text.contains("LOOT") { return CombatTheme.gold }
        if text.contains("DOWN") || text.contains("DEFEAT") { return CombatTheme.enemyColor }
        if text.contains("attacks") || gameState.playerTeam.contains(where: { text.contains($0.name) }) { return CombatTheme.neonBlue }
        if gameState.livingEnemies.contains(where: { text.contains($0.name) }) || text.contains("damage") { return CombatTheme.damage }
        return CombatTheme.textMuted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasMoreEntries() {
                Text("...")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(CombatTheme.textMuted)
                    .padding(.horizontal, 10)
            }
            ForEach(Array(recentEntries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 4) {
                    Text("›")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(CombatTheme.accent)
                    Text(entry)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(entryColor(entry))
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        // Bumped left padding (16 vs 8) so text clears the iPhone notch /
        // rounded-corner safe-area on the left edge — earlier letters were
        // being clipped by the screen curve.
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
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

/// Expanded combat log — the full scrollback, shown over the HUD when the
/// player taps the 3-line strip. Tap the scrim or CLOSE to collapse.
struct FullCombatLogView: View {
    @ObservedObject var gameState: GameState
    let onClose: () -> Void

    private func entryColor(_ text: String) -> Color {
        if text.contains("VICTORY") || text.contains("LEVEL UP") || text.contains("LOOT") || text.contains("🎖") { return CombatTheme.gold }
        if text.contains("DOWN") || text.contains("DEFEAT") || text.contains("☠") { return CombatTheme.enemyColor }
        if gameState.playerTeam.contains(where: { text.contains($0.name) }) { return CombatTheme.neonBlue }
        if text.contains("damage") || text.contains("dmg") { return CombatTheme.damage }
        return Color.white.opacity(0.85)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("◆  COMBAT LOG")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(3).foregroundColor(CombatTheme.accent)
                    Spacer()
                    Button(action: onClose) {
                        Text("CLOSE")
                            .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(2)
                            .foregroundColor(CombatTheme.accent)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(CombatTheme.accent, lineWidth: 1.2)))
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(gameState.combatLog.suffix(80).enumerated()), id: \.offset) { i, entry in
                                Text("› \(entry)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(entryColor(entry))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                    }
                    .onAppear {
                        let last = max(0, gameState.combatLog.suffix(80).count - 1)
                        proxy.scrollTo(last, anchor: .bottom)   // jump to the newest entry
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 60)
            .padding(.bottom, 28)
        }
    }
}

struct CombatLogEntry: View {
    let text: String
    let index: Int
    let total: Int

    private var isRecent: Bool { index >= total - 5 }
    private var isVictory: Bool { text.contains("VICTORY") || text.contains("LEVEL UP") }

    private var textColor: Color {
        if isVictory { return CombatTheme.gold }
        if text.contains("⚠️") { return CombatTheme.damage }
        if text.contains("💀") { return CombatTheme.enemyColor }
        if text.contains("→") || text.contains("attacks") { return CombatTheme.textMuted }
        return index % 2 == 0 ? Color(hex: "555566") : Color(hex: "888899")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if isRecent {
                Text("›")
                    .foregroundColor(CombatTheme.accent)
                    .font(.system(size: 10, weight: .bold))
            } else {
                Text(" ")
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(2)
        }
    }
}

// MARK: - Loot Badge

struct LootBadge: View {
    let items: [GameState.Item]

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "gift.fill")
                    .foregroundColor(CombatTheme.gold)
                    .font(.caption)
                Text("\(items.count) loot")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CombatTheme.gold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "1A1A00"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CombatTheme.gold.opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }
}

struct IntelMetricBadge: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(tint.opacity(0.78))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

struct CombatUtilityButton: View {
    let title: String
    let value: String
    let tint: Color
    let action: () -> Void
    var disabled: Bool = false
    /// Compact variant for when the button shares a row with the status
    /// panel — drops fonts/padding so 3 buttons fit alongside StatusDisplay.
    var compact: Bool = false

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            HapticsManager.shared.buttonTap()
            action()
        }) {
            // Two size profiles. Default (compact: false) is the original
            // thumb-friendly utility chip used elsewhere. The compact
            // profile is used when the utility row is merged onto the
            // status line — same shape, smaller fonts/padding so MODE +
            // LAY LOW + INTEL fit beside the player card.
            VStack(spacing: compact ? 1 : 3) {
                Text(title)
                    .font(.system(size: compact ? 9 : 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(disabled ? 0.35 : 0.88))
                Text(value)
                    .font(.system(size: compact ? 10 : 12, weight: .bold, design: .monospaced))
                    .foregroundColor(disabled ? CombatTheme.textMuted.opacity(0.55) : tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 6 : 12)
            .padding(.vertical, compact ? 8 : 9)
            // Compact buttons now match the StatusDisplay panel height (≈52pt)
            // so the merged HUD row looks aligned instead of having short
            // chips floating next to a taller character card.
            .frame(minHeight: compact ? 52 : 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(disabled ? Color.black.opacity(0.2) : tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(disabled ? tint.opacity(0.18) : tint.opacity(0.38), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
    }
}

struct MissionIntelCard: View {
    @ObservedObject var gameState: GameState
    let onClose: () -> Void

    private var roomTitle: String {
        RoomManager.shared.currentRoom?.title ?? "Mission Intel"
    }

    private var objectiveSummary: String {
        switch gameState.currentMissionType {
        case .stealth:
            return "Stay low for \(gameState.missionTargetTurns) turns."
        case .assault:
            return "Eliminate the hostile force."
        case .extraction:
            return "Reach extraction at (\(gameState.extractionX),\(gameState.extractionY))."
        }
    }

    private var progressSummary: String? {
        switch gameState.currentMissionType {
        case .stealth:
            return "Progress \(gameState.currentTurnCount)/\(gameState.missionTargetTurns)"
        case .assault:
            return nil
        case .extraction:
            return "Exit tile is marked with a green glow."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(roomTitle.uppercased())
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.96))
                        .lineLimit(1)
                    Text("MISSION INTEL")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.accent.opacity(0.82))
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(CombatTheme.textMuted.opacity(0.9))
                        // 44×44 invisible tap area — Apple's minimum touch
                        // target. Icon stays small visually; the hit box
                        // doesn't.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                IntelMetricBadge(label: "ROUND", value: "R\(gameState.roundNumber)", tint: CombatTheme.secondary)
                IntelMetricBadge(label: "ENEMIES", value: "\(gameState.livingEnemies.count)/\(gameState.enemies.count)", tint: CombatTheme.enemyColor)
                if gameState.missionRequiresData {
                    IntelMetricBadge(
                        label: "DATA CORE",
                        value: gameState.dataAcquired ? "ACQUIRED" : "PENDING",
                        tint: gameState.dataAcquired ? CombatTheme.accent : Color(hex: "00D4FF")
                    )
                }
                IntelMetricBadge(label: "TRACE", value: "\(gameState.traceLevel)/\(gameState.traceThreshold)", tint: gameState.traceTier >= 2 ? CombatTheme.enemyColor : CombatTheme.accent)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    intelSection("OBJECTIVE", text: objectiveSummary)

                    if let progressSummary {
                        intelSection("PROGRESS", text: progressSummary)
                    }

                    intelSection("MISSION TYPE", text: "\(gameState.missionTypeLabel)\n\(gameState.missionTypeHint)")
                    intelSection("PRESSURE", text: gameState.generateCombinedPressurePreview())
                    intelSection("REACTION", text: "Corp: \(gameState.generateWorldReactionMessage())\nGang: \(gameState.generateGangReactionMessage())")
                    intelSection(
                        "PAYOUT",
                        text: """
                        Base \(gameState.baseMissionPayout)  Risk +\(gameState.riskBonus)
                        Total \(gameState.finalMissionPayout)
                        \(gameState.generateRewardPreview())
                        """
                    )
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CombatTheme.panelBG.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CombatTheme.panelEdge.opacity(0.52), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    private func intelSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(CombatTheme.textWhite.opacity(0.8))
            Text(text)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(CombatTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Corner Bracket Helper

struct CornerBracket: View {
    let size: CGFloat = 12
    let lineWidth: CGFloat = 2
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let inset: CGFloat = 4

            // Top-left bracket
            path.move(to: CGPoint(x: inset, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: inset))

            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .frame(width: size, height: size)
    }
}
