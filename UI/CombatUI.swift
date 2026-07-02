import SwiftUI

// MARK: - Theme Colors

struct CombatTheme {
    static let background  = Color(hex: "000000")
    static let panelBG     = Color(hex: "0A0A14")
    static let panelEdge   = Color(hex: "00FF88").opacity(0.4)
    static let accent      = Color(hex: "00FF88")
    static let damage      = Color(hex: "FF6600")
    static let enemyColor  = Color(hex: "FF3333")
    static let secondary   = Color(hex: "444466")
    static let textWhite   = Color.white
    static let textMuted   = Color(hex: "888899")
    static let gold       = Color(hex: "FFD700")
    // New neon colors
    static let neonPink    = Color(hex: "FF0080")
    static let neonBlue    = Color(hex: "00D4FF")
    static let neonPurple  = Color(hex: "8B00FF")
    static let darkPanel   = Color(hex: "06060E")
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000)>>16)/255.0
        let g = Double((rgb & 0x00FF00)>>8)/255.0
        let b = Double(rgb & 0x0000FF)/255.0
        self.init(red: r, green: g, blue: b)
    }
}

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

// MARK: - Turn Indicator Banner

struct TurnIndicatorBanner: View {
    let isEnemyTurn: Bool
    let roundNumber: Int
    @ObservedObject var gameState: GameState

    @State private var pulseScale: CGFloat = 1.0

    private var currentCharName: String {
        gameState.activeCharacter?.name ?? gameState.currentCharacter?.name ?? "UNKNOWN"
    }

    private var currentCharHasMoved: Bool {
        guard let char = gameState.activeCharacter ?? gameState.currentCharacter else { return false }
        return gameState.characterHasMovedThisTurn[char.id] == true
    }

    private var turnStateTitle: String {
        if isEnemyTurn { return "ENEMY TURN" }
        return currentCharHasMoved ? "MOVE USED" : "YOUR TURN"
    }

    private var turnStateColor: Color {
        if isEnemyTurn { return Color(hex: "FF3333") }
        return currentCharHasMoved ? CombatTheme.gold : CombatTheme.accent
    }

    var body: some View {
        HStack(spacing: 5) {
            // Turn state pill — slightly narrower padding to make room for
            // the metric chips that moved up from line 2 of the HUD.
            HStack(spacing: 4) {
                if isEnemyTurn {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8))
                    Text(turnStateTitle)
                        .font(.system(size: 9, weight: .black))
                } else {
                    Image(systemName: currentCharHasMoved ? "arrowshape.turn.up.right.fill" : "play.fill")
                        .font(.system(size: 8))
                    VStack(spacing: 0) {
                        Text(turnStateTitle)
                            .font(.system(size: 9, weight: .black))
                        Text(currentCharName)
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
            .foregroundColor(turnStateColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnemyTurn
                          ? Color(hex: "FF3333").opacity(0.15)
                          : turnStateColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isEnemyTurn
                                    ? Color(hex: "FF3333").opacity(0.5)
                                    : turnStateColor.opacity(0.4), lineWidth: 1)
                    )
            )
            .scaleEffect(pulseScale)
            .onAppear {
                if !isEnemyTurn {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.05
                    }
                }
            }

            Spacer(minLength: 0)

            // ROUND chip — replaces the old "R1" text pill so the metric
            // matches the chip style used for ENEMY / TRACE alongside it.
            IntelMetricBadge(label: "ROUND", value: "R\(roundNumber)", tint: CombatTheme.secondary)

            // Skull icon retained as a visual cue, then ENEMY chip with the
            // count in the same chip style as ROUND / TRACE.
            Text("💀")
                .font(.system(size: 12))
            IntelMetricBadge(label: "ENEMY", value: "\(gameState.livingEnemies.count)", tint: CombatTheme.enemyColor)

            // TRACE chip moves up here from the old line-2 chip column.
            IntelMetricBadge(
                label: "TRACE",
                value: "\(gameState.traceLevel)/\(gameState.traceThreshold)",
                tint: gameState.traceTier >= 2 ? CombatTheme.enemyColor : CombatTheme.accent
            )

            // DATA chip is conditional — only shows on missions that
            // require a terminal hack.
            if gameState.missionRequiresData {
                IntelMetricBadge(
                    label: "DATA",
                    value: gameState.dataAcquired ? "GOT" : "...",
                    tint: gameState.dataAcquired ? CombatTheme.accent : Color(hex: "00D4FF")
                )
            }

            // LOOT chip — only shows when the team has picked something up.
            // Moved up from the conditional status strip so the HUD stays
            // smooth: appearing loot used to push the action bar down
            // because it lived in a row that grew/shrank with state. As a
            // chip on line 1, it just slots in beside the other metrics.
            if !gameState.loot.isEmpty {
                IntelMetricBadge(
                    label: "LOOT",
                    value: "\(gameState.loot.count)",
                    tint: CombatTheme.gold
                )
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CombatTheme.panelBG.opacity(0.8))
        )
    }
}

// MARK: - Main Combat UI

// MARK: - Hit Preview Card

struct HitPreviewCard: View {
    let preview: CombatMechanics.HitPreview

    private var hitChancePct: Int { Int((preview.estimatedHitChance * 100).rounded()) }

    private var hitColor: Color {
        if preview.blocked               { return CombatTheme.textMuted }
        if preview.estimatedHitChance > 0.60 { return CombatTheme.accent }
        if preview.estimatedHitChance > 0.35 { return Color.yellow }
        return CombatTheme.enemyColor
    }

    var body: some View {
        Group {
            if preview.blocked {
                // Blocked state: LOS, range, or another hard pre-attack gate.
                HStack(spacing: 6) {
                    Text(preview.actionLabel)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(CombatTheme.enemyColor)
                        .cornerRadius(3)
                    Image(systemName: preview.reason == "Move adjacent first" ? "figure.walk.circle.fill" : "xmark.shield.fill")
                        .foregroundColor(CombatTheme.enemyColor)
                        .font(.system(size: 11))
                    Text(preview.reason == "Move adjacent first" ? "MELEE ONLY - MOVE ADJACENT" : "NO LOS - \(preview.reason ?? "blocked")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(CombatTheme.enemyColor)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CombatTheme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(CombatTheme.enemyColor.opacity(0.4), lineWidth: 1))
                )
            } else {
                // Normal preview state
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(preview.actionLabel)
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(hitColor)
                                .cornerRadius(3)
                            Text(preview.weaponName.uppercased())
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.textMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Text(preview.targetName.uppercased())
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 88, alignment: .leading)

                    Rectangle()
                        .fill(CombatTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: 28)

                    // Hit chance %
                    VStack(spacing: 1) {
                        Text("HIT")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Text("\(hitChancePct)%")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(hitColor)
                    }

                    Rectangle()
                        .fill(CombatTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: 28)

                    // Dice pools
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("ATK")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.textMuted)
                            Text("\(preview.attackPool)d6")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 4) {
                            Text("DEF")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.textMuted)
                            Text("\(preview.defensePool)d6")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            if preview.coverBonus > 0 {
                                Text("+\(preview.coverBonus)cov")
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .foregroundColor(CombatTheme.gold)
                            }
                        }
                    }

                    Rectangle()
                        .fill(CombatTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: 28)

                    // Estimated damage
                    VStack(spacing: 1) {
                        Text("DMG")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Text("~\(Int(preview.estimatedDamage.rounded()))")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.damage)
                        Text("W\(preview.weaponDamage)")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                    }

                    Spacer()

                    // LOS checkmark
                    VStack(spacing: 1) {
                        Text("LOS")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(CombatTheme.accent)
                    }

                    VStack(spacing: 1) {
                        Text("COST")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Text("TURN")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.gold)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CombatTheme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(hitColor.opacity(0.45), lineWidth: 1))
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hitChancePct)
    }
}

struct HitPreviewStrip: View {
    let previews: [CombatMechanics.HitPreview]
    var notice: String? = nil

    private var targetName: String {
        previews.first?.targetName.uppercased() ?? "TARGET"
    }

    private var stripColor: Color {
        if previews.allSatisfy(\.blocked) { return CombatTheme.enemyColor }
        if previews.contains(where: { $0.estimatedHitChance > 0.60 }) { return CombatTheme.accent }
        if previews.contains(where: { $0.estimatedHitChance > 0.35 }) { return Color.yellow }
        return CombatTheme.enemyColor
    }

    var body: some View {
        HStack(spacing: 5) {
            if previews.isEmpty {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(CombatTheme.gold)
                Text(notice ?? "END TURN")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(CombatTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 3) {
                    Text("TGT")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.textMuted)
                    Text(targetName)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 72, alignment: .leading)

                ForEach(Array(previews.enumerated()), id: \.offset) { _, preview in
                    CompactHitPreviewPill(preview: preview)
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Image(systemName: notice == nil ? "checkmark.circle.fill" : "arrowshape.turn.up.right.fill")
                        .font(.system(size: 10))
                        .foregroundColor(notice == nil
                                         ? (previews.allSatisfy(\.blocked) ? CombatTheme.textMuted : CombatTheme.accent)
                                         : CombatTheme.gold)
                    Text(notice ?? "TURN")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CombatTheme.panelBG)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(stripColor.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

private struct CompactHitPreviewPill: View {
    let preview: CombatMechanics.HitPreview

    private var hitChancePct: Int {
        Int((preview.estimatedHitChance * 100).rounded())
    }

    private var tint: Color {
        if preview.blocked { return CombatTheme.enemyColor }
        if preview.estimatedHitChance > 0.60 { return CombatTheme.accent }
        if preview.estimatedHitChance > 0.35 { return Color.yellow }
        return CombatTheme.enemyColor
    }

    private var blockedLabel: String {
        preview.reason == "Move adjacent first" ? "ADJ" : "NO LOS"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(preview.actionLabel)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tint)
                .cornerRadius(3)

            if preview.blocked {
                Text(blockedLabel)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(tint)
            } else {
                Text("\(hitChancePct)%")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(tint)
                Text("~\(Int(preview.estimatedDamage.rounded()))")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(CombatTheme.damage)
                Text("\(preview.attackPool)/\(preview.defensePool)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(CombatTheme.textMuted)
                if preview.coverBonus > 0 {
                    Text("+\(preview.coverBonus)c")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.gold)
                }
            }
        }
        .lineLimit(1)
    }
}

// MARK: - CombatUI

struct CombatUI: View {
    @ObservedObject var gameState: GameState
    let diagnosticsVisible: Bool
    let onToggleDiagnostics: () -> Void
    let onAttack: () -> Void
    let onShoot: () -> Void
    let onOverwatch: () -> Void
    let onDefend: () -> Void
    let onSpell: () -> Void
    let onBlitz: () -> Void
    let onHack: () -> Void
    let onIntimidate: () -> Void
    let onItems: () -> Void
    let onRecover: () -> Void
    let onEndTurn: () -> Void
    @State private var showingItemPicker = false
    @State private var showingSpellPicker = false
    @State private var isEnemyTurnDisplay: Bool = false
    @State private var showingMissionIntel = false
    @State private var showFullLog = false   // tap the 3-line log to expand it full-screen

    private var specialAbilityTitle: String {
        switch (gameState.activeCharacter ?? gameState.currentCharacter)?.archetype {
        case .streetSam: return "BLITZ"
        case .mage:      return "SPELL"
        case .decker:    return "HACK"
        case .face:      return "INTIM"
        default:         return "SPL"
        }
    }

    private var specialAbilityIcon: String {
        switch (gameState.activeCharacter ?? gameState.currentCharacter)?.archetype {
        case .streetSam: return "bolt.fill"
        case .mage:      return "sparkles"
        case .decker:    return "cpu.fill"
        case .face:      return "person.wave.2.fill"
        default:         return "sparkles"
        }
    }

    private var specialAbilityColor: Color {
        switch (gameState.activeCharacter ?? gameState.currentCharacter)?.archetype {
        case .streetSam: return Color(hex: "FF6633")
        case .mage:      return Color(hex: "6699FF")
        case .decker:    return Color(hex: "00DDFF")
        case .face:      return Color(hex: "FFCC00")
        default:         return Color(hex: "6699FF")
        }
    }

    private var specialAbilityAction: () -> Void {
        switch (gameState.activeCharacter ?? gameState.currentCharacter)?.archetype {
        case .streetSam: return onBlitz
        case .mage:      return { showingSpellPicker = true }
        case .decker:    return onHack
        case .face:      return onIntimidate
        default:         return onSpell
        }
    }

    private var isEnemyTurn: Bool {
        gameState.combatPhase == .enemyResolving || gameState.isEnemyPhaseRunning
    }

    private var arePlayerControlsDisabled: Bool {
        !gameState.isPlayerInputPhase || gameState.isInputBlockedByPhase
    }

    private var hasActedThisRound: Bool {
        guard let char = gameState.activeCharacter ?? gameState.currentCharacter else { return false }
        return char.hasActedThisRound
    }

    private var hasMovedThisTurn: Bool {
        guard let char = gameState.activeCharacter ?? gameState.currentCharacter else { return false }
        return gameState.characterHasMovedThisTurn[char.id] == true
    }

    private var activeRunner: Character? {
        gameState.activeCharacter ?? gameState.currentCharacter
    }

    private var actionStateDisabledReason: String? {
        if gameState.isCombatResolvedOrBeyond { return "USED" }
        if hasActedThisRound { return "USED" }
        if hasMovedThisTurn { return "MOVED" }
        return nil
    }

    private var selectedOrNearestEnemy: Enemy? {
        guard let runner = activeRunner else { return nil }
        if let targetId = gameState.targetCharacterId,
           let selected = gameState.enemies.first(where: { $0.id == targetId && $0.isAlive }) {
            return selected
        }
        return gameState.livingEnemies
            .map { ($0, gameState.hexDistance(x1: runner.positionX, y1: runner.positionY, x2: $0.positionX, y2: $0.positionY)) }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    private var attackDisabledReason: String? {
        if let reason = actionStateDisabledReason { return reason }
        guard !gameState.livingEnemies.isEmpty else { return "NO TARGET" }
        if let preview = gameState.attackPreview, preview.blocked {
            return preview.reason == "Move adjacent first" ? "RANGE" : "NO LOS"
        }
        return nil
    }

    private var shootDisabledReason: String? {
        if let reason = actionStateDisabledReason { return reason }
        guard activeRunner?.archetype != .streetSam else { return "RANGE" }
        guard !gameState.livingEnemies.isEmpty else { return "NO TARGET" }
        if let preview = gameState.shootPreview, preview.blocked {
            return preview.reason == "Move adjacent first" ? "RANGE" : "NO LOS"
        }
        return nil
    }

    private var specialDisabledReason: String? {
        if let reason = actionStateDisabledReason { return reason }
        guard let runner = activeRunner else { return nil }
        switch runner.archetype {
        case .mage:
            let cheapestSpell = SpellType.allCases.map(\.manaCost).min() ?? 0
            return runner.currentMana < cheapestSpell ? "NO MANA" : nil
        case .decker:
            if runner.currentMana < 2 { return "NO MANA" }
            guard let target = selectedOrNearestEnemy else { return "NO TARGET" }
            return gameState.isLineBlockedByWall(
                fromX: runner.positionX,
                fromY: runner.positionY,
                toX: target.positionX,
                toY: target.positionY
            ) ? "NO LOS" : nil
        default:
            return nil
        }
    }

    private var itemDisabledReason: String? {
        actionStateDisabledReason
    }

    private var hasMultipleRooms: Bool {
        (RoomManager.shared.currentMission?.rooms.count ?? 0) > 1
    }

    private var currentRoomIndex: Int {
        RoomManager.shared.currentRoomIndex
    }

    private func navigateRoomLeft() {
        HapticsManager.shared.buttonTap()
        NotificationCenter.default.post(name: .roomNavigationRequested, object: nil, userInfo: ["direction": "left"])
    }

    private func navigateRoomRight() {
        HapticsManager.shared.buttonTap()
        NotificationCenter.default.post(name: .roomNavigationRequested, object: nil, userInfo: ["direction": "right"])
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 2) {
                // Turn indicator banner + a compact HELP (?) on HUD line 1.
                // HELP lived on line 2 as a 4th chip, which crowded that row and
                // made it reflow/break when the MODE chip changed width (STREET
                // ⇄ SIGNAL). Moving it up here keeps line 2 to the stable 3-chip
                // layout (MODE / LAY LOW / INTEL) and keeps help one tap away.
                HStack(spacing: 5) {
                    TurnIndicatorBanner(
                        isEnemyTurn: isEnemyTurn || isEnemyTurnDisplay,
                        roundNumber: gameState.roundNumber,
                        gameState: gameState
                    )
                    Button(action: { TutorialCoach.shared.showMenu = true }) {
                        Text("?")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(Color(hex: "FFCC00"))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                            .overlay(Circle().stroke(Color(hex: "FFCC00").opacity(0.6), lineWidth: 1))
                    }
                    .accessibilityIdentifier("help_tutorial_button")
                }

                // (TeamRosterBar removed 2026-05 — selection happens by tapping
                // a runner directly on the map, the in-HUD roster picker was
                // redundant and ate vertical real estate.)
                // (Room navigation arrows removed — players navigate between
                // rooms via door tiles on the map.)

                // Line 2 of the HUD — status panel + utility chips on the
                // same row. Pre-rework this was two separate rows:
                //   • StatusDisplay alongside a right-side chip column
                //     (ROUND/ENEMY/DATA/TRACE)
                //   • Below it, the utility row with MODE/LAY LOW/INTEL/DIAG
                // The chip column moved up into the TurnIndicatorBanner so
                // those three buttons could be promoted to line 2, killing
                // the old line 3 entirely. DIAG (dev-only diagnostics
                // overlay) is dropped — was clutter for players.
                HStack(alignment: .center, spacing: 6) {
                    StatusDisplay(gameState: gameState)
                        .frame(maxWidth: .infinity)

                    CombatUtilityButton(
                        title: "MODE",
                        value: gameState.actionMode == .street ? "STREET" : "SIGNAL +\(gameState.signalDiceBonus)d",
                        tint: gameState.actionMode == .street ? CombatTheme.accent : Color(hex: "FF8800"),
                        action: {
                            gameState.actionMode = (gameState.actionMode == .street) ? .signal : .street
                            // The signature risk/reward dial had NO feedback —
                            // give the flip a distinct toast + SFX so the stance
                            // change actually reads.
                            if gameState.actionMode == .signal {
                                gameState.postTransientWarning("▶ SIGNAL — RUNNING HOT (+\(gameState.signalDiceBonus)d · TRACE builds)", duration: 2.0)
                                SFXManager.shared.play("hack_intrusion", volume: 0.7)
                                HapticsManager.shared.victory()
                                // First time you go loud, surface the SIGNAL/TRACE card.
                                TutorialCoach.shared.enqueue(.signalHeat)
                            } else {
                                gameState.postTransientWarning("◼ STREET — QUIET (TRACE cools)", duration: 1.6)
                                SFXManager.shared.play("terminal_correct", volume: 0.5)
                                HapticsManager.shared.buttonTap()
                            }
                        },
                        compact: true
                    )
                    .accessibilityIdentifier("action_mode_toggle_button")

                    CombatUtilityButton(
                        title: "LAY LOW",
                        value: hasActedThisRound ? "USED" : (gameState.traceLevel > 0 ? "−\(gameState.layLowRecoveryAmount) ♨" : "BRACE"),
                        tint: Color(hex: "B8BCC8"),
                        action: onRecover,
                        disabled: gameState.isCombatResolvedOrBeyond || arePlayerControlsDisabled || hasActedThisRound || hasMovedThisTurn,
                        compact: true
                    )
                    .accessibilityIdentifier("trace_recover_button")

                    CombatUtilityButton(
                        title: "INTEL",
                        value: showingMissionIntel ? "HIDE" : "SHOW",
                        tint: CombatTheme.accent,
                        action: { showingMissionIntel.toggle() },
                        compact: true
                    )
                    .accessibilityIdentifier("toggle_intel_button")
                    // (HELP moved to HUD line 1 — see the TurnIndicatorBanner row
                    // above. Keeping line 2 at 3 chips fixes the STREET/SIGNAL
                    // reflow that made this row look broken.)
                }

                // Conditional status strip — renders only when at least one
                // indicator is active. PROGRESS / RESISTING / MISSION OUTCOME
                // need to be visible when they fire (game-state callouts).
                // LOOT moved up to the line-1 chip row so it doesn't push the
                // HUD's vertical layout around when it appears.
                let showStealth = gameState.currentMissionType == .stealth
                let showEscalation = gameState.traceEscalationLevel >= 1 && gameState.playerRole == .street
                let showOutcome = gameState.isCombatResolvedOrBeyond
                let showMoveSpent = hasMovedThisTurn && !hasActedThisRound && !isEnemyTurn
                if showStealth || showEscalation || showOutcome {
                    HStack(spacing: 8) {
                        if showStealth {
                            Text("PROGRESS \(gameState.currentTurnCount)/\(gameState.missionTargetTurns)")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(gameState.isMissionCompleteCompat ? CombatTheme.accent : CombatTheme.textMuted)
                        }
                        if showEscalation {
                            Text("RESISTING ESCALATION")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.accent.opacity(0.9))
                        }
                        if showOutcome {
                            Text(gameState.isCombatVictoryLike ? "RUN COMPLETE" : "RUN FAILED")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(gameState.isCombatVictoryLike ? CombatTheme.accent : CombatTheme.enemyColor)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)
                }

                // Action buttons. Street Samurai is melee-only — disable SHT
                // so the player can't tap it for that runner.
                let activeArchetype = (gameState.activeCharacter ?? gameState.currentCharacter)?.archetype
                ActionBar(
                    onAttack: onAttack,
                    onShoot: onShoot,
                    onOverwatch: onOverwatch,
                    onDefend: onDefend,
                    onItems: { showingItemPicker = true },
                    onSpecial: specialAbilityAction,
                    specialTitle: specialAbilityTitle,
                    specialIcon: specialAbilityIcon,
                    specialColor: specialAbilityColor,
                    onEndTurn: onEndTurn,
                    actionDisabled: gameState.isCombatResolvedOrBeyond || arePlayerControlsDisabled || hasActedThisRound || hasMovedThisTurn,
                    endTurnDisabled: gameState.isCombatResolvedOrBeyond || arePlayerControlsDisabled,
                    attackDisabledReason: attackDisabledReason,
                    shootDisabledReason: shootDisabledReason,
                    specialDisabledReason: specialDisabledReason,
                    itemDisabledReason: itemDisabledReason,
                    shootDisabled: activeArchetype == .streetSam
                )

                // Hit preview — shown when a target is selected
                let previewRows = [gameState.attackPreview, gameState.shootPreview].compactMap { $0 }
                if !previewRows.isEmpty || showMoveSpent {
                    HitPreviewStrip(
                        previews: previewRows,
                        notice: showMoveSpent ? "MOVE USED - END TURN" : nil
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Combat log — tap to expand the full scrollback over the HUD.
                CombatLogView(gameState: gameState)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(CombatTheme.accent.opacity(0.7))
                            .padding(6)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { HapticsManager.shared.buttonTap(); showFullLog = true }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .background(
                Rectangle()
                    .fill(CombatTheme.background.opacity(0.90))
            )

            if showingMissionIntel {
                MissionIntelCard(
                    gameState: gameState,
                    onClose: {
                        HapticsManager.shared.buttonTap()
                        showingMissionIntel = false
                    }
                )
                .padding(.trailing, 10)
                .padding(.bottom, 230)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Item picker sheet overlay
            if showingItemPicker {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { showingItemPicker = false }
                ItemPickerSheet(
                    gameState: gameState,
                    showingPicker: $showingItemPicker,
                    onUseItem: onEndTurn
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Spell picker sheet overlay (mage only)
            if showingSpellPicker {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { showingSpellPicker = false }
                SpellPickerSheet(
                    gameState: gameState,
                    showingPicker: $showingSpellPicker
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Expanded combat log — full scrollback overlaying the HUD; tap
            // anywhere (or CLOSE) to collapse back to the 3-line strip.
            if showFullLog {
                FullCombatLogView(gameState: gameState, onClose: { showFullLog = false })
                    .transition(.opacity)
            }

            // First-time tutorial cards (combat basics / doors / terminals)
            // appear at the top of the screen. The overlay is non-blocking
            // when no card is showing.
            TutorialCoachOverlay()
        }
        .animation(.easeInOut(duration: 0.2), value: showingItemPicker)
        .animation(.easeInOut(duration: 0.2), value: showingSpellPicker)
        .animation(.easeInOut(duration: 0.22), value: showingMissionIntel)
        .animation(.easeInOut(duration: 0.18), value: showFullLog)
        .animation(.easeInOut(duration: 0.25), value: isEnemyTurnDisplay)
        .onAppear { enqueueTutorialTipsForCurrentRoom() }
        .onChange(of: RoomManager.shared.currentRoomIndex) { _, _ in
            enqueueTutorialTipsForCurrentRoom()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enemyPhaseBegan)) { _ in
            guard !gameState.livingEnemies.isEmpty else { return }
            withAnimation { isEnemyTurnDisplay = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerTurnResumed)) { _ in
            withAnimation { isEnemyTurnDisplay = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .enemyPhaseCompleted)) { _ in
            withAnimation { isEnemyTurnDisplay = false }
        }
    }

    /// Decide which first-time tutorial cards apply to the current scene
    /// state. Called on combat-view appear and on each room transition so
    /// the door / terminal cards land the first time the player can
    /// actually see one. Each card auto-suppresses if its UserDefaults
    /// flag is already set, so this is safe to call repeatedly.
    private func enqueueTutorialTipsForCurrentRoom() {
        // Combat basics + utility row HUD: always queue on first combat.
        // The combat-basics card covers movement (2 tiles), targeting and
        // the bottom action bar; the utility-row card covers the top row
        // (MODE / LAY LOW / INTEL). They show in that order so the
        // player learns the inner loop first.
        TutorialCoach.shared.enqueue(.combatBasics)
        TutorialCoach.shared.enqueue(.utilityRow)

        // Scan the active room's tile grid for terminals (cyan) and doors
        // (yellow). Only enqueue the relevant cards if at least one of
        // each tile is present so the cards land contextually — door tip
        // when there's actually a door to use, terminal tip when there's
        // actually a terminal on screen.
        let tiles = gameState.currentMissionTiles
        var hasTerminal = false
        var hasDoor = false
        for row in tiles {
            for cell in row {
                if cell == TileType.dataTerminal.rawValue { hasTerminal = true }
                if cell == TileType.door.rawValue { hasDoor = true }
                if hasTerminal && hasDoor { break }
            }
            if hasTerminal && hasDoor { break }
        }
        if hasDoor { TutorialCoach.shared.enqueue(.doors) }
        if hasTerminal { TutorialCoach.shared.enqueue(.terminals) }
    }
}

#if DEBUG
struct CombatUI_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CombatUI(
                gameState: GameState.shared,
                diagnosticsVisible: false,
                onToggleDiagnostics: {},
                onAttack: {},
                onShoot: {},
                onOverwatch: {},
                onDefend: {},
                onSpell: {},
                onBlitz: {},
                onHack: {},
                onIntimidate: {},
                onItems: {},
                onRecover: {},
                onEndTurn: {}
            )
        }
    }
}
#endif
