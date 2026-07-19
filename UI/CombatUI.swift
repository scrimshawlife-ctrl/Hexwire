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
