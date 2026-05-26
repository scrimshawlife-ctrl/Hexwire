import SwiftUI
import Combine

// MARK: - M4.5 "Basement Brawl" — Raze solo duel (SF2-lite pit fighter)
//
// Real-time 2D fighting scene. Raze (player) vs one of 5 fixed-order enemies.
//
// FLOW
//   • Each wave starts in .entering — enemy walks in from off-screen right
//     with a walk animation (bob + sway). Player can move during entrance
//     but can't be hit. Banner names the enemy.
//   • Then .fighting — enemy AI runs, both fighters duke it out.
//   • Then .finishing — winner pose, wave clears or game ends.
//
// CONTROLS
//   Drag arena    → moves Raze in 2D
//   JAB           → fast +1, short range, 0.32s cooldown
//   STRIKE        → med +2, mid range, 0.55s cooldown
//   HEAVY         → slow +3, long range, 0.95s cooldown
//   BLOCK (hold)  → absorb incoming damage
//
//   Auto-lunge: if you tap an attack and Raze is JUST out of range, she
//   takes a forward step into range — taps always feel responsive.

// MARK: - Models

private enum PlayerAttack {
    case jab, strike, heavy
    var damage: Int { self == .jab ? 1 : self == .strike ? 2 : 3 }
    var cooldown: Double { self == .jab ? 0.28 : self == .strike ? 0.50 : 0.85 }
    var rangeX: CGFloat { self == .jab ? 105 : self == .strike ? 140 : 175 }
    var rangeY: CGFloat { self == .jab ? 80 : self == .strike ? 100 : 125 }
    var poseHold: Double { self == .jab ? 0.30 : self == .strike ? 0.42 : 0.62 }
    /// Stun duration applied to Raze on a whiff. JAB is safe; STRIKE/HEAVY
    /// commit you and leave you open if you miss. Pushes the player to
    /// pick the right tool for the spacing — not just spam HEAVY.
    var whiffStun: Double { self == .jab ? 0.0 : self == .strike ? 0.30 : 0.65 }
    /// Symbol shown in the combo HUD banner.
    var comboSymbol: String { self == .jab ? "J" : self == .strike ? "S" : "H" }
}

/// What kind of enemy this is in mechanical terms — drives the unique
/// per-enemy mechanics layered on top of the base AI.
private enum BrawlArchetype {
    case standard       // brawler — vanilla AI
    case armored        // slugger — only HEAVY hits damage him; JAB/STRIKE chip 0
    case combo          // razorgirl — chains 2 strikes back-to-back, no recover gap
    case ranged         // bodyguard — pistol, fires from far X; only STEP BACK / Y-dodge avoids
    case boss           // vargas — multi-phase, phase 3 unblockable
}

private enum EnemyAIPhase {
    case entering      // walking in from off-screen right
    case readying      // 3-2-1-FIGHT countdown, no attacks
    case approaching
    case winding
    case striking
    case recovering
    case dying
}

private struct EnemyProfile {
    let maxHP: Int
    let approachSpeed: CGFloat
    let bobSpeed: CGFloat
    let windupTime: Double
    let strikeTime: Double
    let recoverTime: Double
    let attackRangeX: CGFloat
    let attackRangeY: CGFloat
    let attackDamage: Int
    let label: String
    let archetype: BrawlArchetype
    /// 0 = no armor, 1 = only HEAVY pierces. Set with armored archetype.
    let armorBreakLevel: Int
}

private func enemyProfile(for enemy: BasementBrawlScene.WaveEnemy, vargasPhase: Int = 1) -> EnemyProfile {
    switch enemy {
    case .brawler:
        // Training-wheel enemy — slow windup, low damage. Teaches the loop.
        return EnemyProfile(maxHP: 6, approachSpeed: 75, bobSpeed: 25,
                            windupTime: 1.20, strikeTime: 0.30, recoverTime: 1.00,
                            attackRangeX: 100, attackRangeY: 75,
                            attackDamage: 2, label: "PIT BRAWLER",
                            archetype: .standard, armorBreakLevel: 0)
    case .slugger:
        // ARMORED: only HEAVY pierces. JAB/STRIKE deal 0 dmg → "TINK!"
        // Forces the player to commit to HEAVY (which has whiff stun).
        return EnemyProfile(maxHP: 9, approachSpeed: 48, bobSpeed: 20,
                            windupTime: 1.20, strikeTime: 0.38, recoverTime: 0.95,
                            attackRangeX: 95, attackRangeY: 70,
                            attackDamage: 3, label: "CHROME SLUGGER",
                            archetype: .armored, armorBreakLevel: 1)
    case .razorgirl:
        // COMBO: very short recover — chains TWO strikes back-to-back.
        // Standing block doesn't survive both hits; parry or dodge needed.
        return EnemyProfile(maxHP: 6, approachSpeed: 100, bobSpeed: 45,
                            windupTime: 0.75, strikeTime: 0.20, recoverTime: 0.40,
                            attackRangeX: 95, attackRangeY: 75,
                            attackDamage: 2, label: "RAZORGIRL",
                            archetype: .combo, armorBreakLevel: 0)
    case .bodyguard:
        // RANGED: fires from huge X. STEP BACK doesn't dodge, only Y-drag does.
        return EnemyProfile(maxHP: 7, approachSpeed: 55, bobSpeed: 25,
                            windupTime: 1.00, strikeTime: 0.28, recoverTime: 0.85,
                            attackRangeX: 230, attackRangeY: 80,
                            attackDamage: 3, label: "SUIT + PISTOL",
                            archetype: .ranged, armorBreakLevel: 0)
    case .vargas:
        switch vargasPhase {
        case 1:
            return EnemyProfile(maxHP: 16, approachSpeed: 60, bobSpeed: 25,
                                windupTime: 1.10, strikeTime: 0.32, recoverTime: 0.90,
                                attackRangeX: 145, attackRangeY: 85,
                                attackDamage: 3, label: "VARGAS — PHASE 1",
                                archetype: .boss, armorBreakLevel: 0)
        case 2:
            return EnemyProfile(maxHP: 16, approachSpeed: 80, bobSpeed: 35,
                                windupTime: 0.85, strikeTime: 0.30, recoverTime: 0.65,
                                attackRangeX: 165, attackRangeY: 90,
                                attackDamage: 3, label: "VARGAS — PHASE 2",
                                archetype: .boss, armorBreakLevel: 0)
        default:
            // OVERLOAD: short windup, big damage, partial armor — only HEAVY
            // breaks his guard like the Slugger. Real test of mastery.
            return EnemyProfile(maxHP: 16, approachSpeed: 110, bobSpeed: 45,
                                windupTime: 0.55, strikeTime: 0.28, recoverTime: 0.40,
                                attackRangeX: 175, attackRangeY: 100,
                                attackDamage: 4, label: "VARGAS — OVERLOAD",
                                archetype: .boss, armorBreakLevel: 1)
        }
    }
}

// MARK: - Scene

struct BasementBrawlScene: View {
    @ObservedObject var manager: PhaseManager

    // MARK: Tuning
    private let maxHP = 10

    /// Damage multiplier when comboing different attack types in sequence.
    /// JAB→STRIKE→HEAVY hits scale as 1x, 1.5x, 2x base damage.
    private let comboBaseDamageMult: [Int: Double] = [1: 1.0, 2: 1.5, 3: 2.0]

    /// Window after a hit lands during which the NEXT (different) attack
    /// counts as a combo continuation.
    private let comboGraceWindow: Double = 0.8

    /// How close to the end of the enemy's windup BLOCK must be tapped to
    /// register a perfect parry (stuns enemy, full counter window).
    private let parryWindow: Double = 0.25
    /// Enemy stun duration on a successful parry.
    private let parryStunDuration: Double = 1.5
    /// Chip damage dealt when player blocks a hit (can't perma-block).
    private let blockChipDamage: Int = 1

    // Raze drag bounds (offset from her stance position)
    private let razeMoveXRange: ClosedRange<CGFloat> = -30...210
    private let razeMoveYRange: ClosedRange<CGFloat> = -110...110

    /// How far Raze auto-steps when you tap-attack just-out-of-range.
    private let autoLungeMax: CGFloat = 80

    // Enemy X is a screen offset from the right anchor (+110). Positive
    // values push the enemy farther RIGHT (off-screen at entry), 0 puts
    // them at the fight-stance position on the right side of the arena.
    // Negative would mean walking toward (past) Raze.
    // Stance is intentionally OUTSIDE attack range — the enemy has to
    // step in once more during .approaching before they can wind up,
    // giving the player a reaction window after the FIGHT! cue.
    private let enemyStanceX: CGFloat = 45
    /// Off-screen-right starting X for the entrance walk-in (positive = right).
    private let enemyEntryX: CGFloat = 240

    // MARK: Wave model

    enum WaveEnemy: String, CaseIterable {
        case brawler, slugger, razorgirl, bodyguard, vargas
        var label: String {
            switch self {
            case .brawler:   return "PIT BRAWLER"
            case .slugger:   return "CHROME SLUGGER"
            case .razorgirl: return "RAZORGIRL"
            case .bodyguard: return "SUIT + PISTOL"
            case .vargas:    return "VARGAS — THE BROKER"
            }
        }
    }

    // MARK: State

    @State private var waveIndex: Int = 0
    @State private var playerHP: Int = 10
    @State private var enemyHP: Int = 6
    @State private var gameOver: Bool = false
    @State private var didWin: Bool = false

    // Raze position (drag-controlled)
    @State private var razeX: CGFloat = 0
    @State private var razeY: CGFloat = 0
    @State private var razeDragStart: CGSize = .zero

    // Raze action state
    @State private var razeAttackPose: PlayerAttack? = nil
    @State private var razeAttackHold: Double = 0
    @State private var razeCooldown: Double = 0
    @State private var razeIsBlocking: Bool = false
    @State private var playerHitFlash: Double = 0
    /// Brief invulnerability granted by STEP BACK so mistimed dodges still work.
    @State private var razeIFrames: Double = 0
    /// Raze is stunned after whiffing STRIKE/HEAVY — can't attack/move during this.
    @State private var razeStunTimer: Double = 0
    /// Tracks the moment BLOCK was tapped — used to detect perfect parries
    /// (block-tap within the last `parryWindow` seconds of enemy windup).
    @State private var blockTappedAt: Date? = nil

    // Combo system
    @State private var comboLastAttack: PlayerAttack? = nil
    @State private var comboCount: Int = 0
    @State private var comboTimer: Double = 0
    @State private var comboBannerHold: Double = 0
    @State private var comboBannerText: String = ""

    // Enemy stun (set by perfect parry)
    @State private var enemyStunTimer: Double = 0
    /// Razorgirl-style combo: after the first strike, chain immediately
    /// into a 2nd windup without the usual recovery gap.
    @State private var enemyComboFired: Bool = false
    /// Extra recovery added when the enemy whiffs an attack. Creates the
    /// "whiff punish" window that's the heart of fighting-game offense.
    @State private var whiffRecoveryBonus: Double = 0

    // Enemy state. enemyX = screen offset from right anchor (+110).
    // Starts at +220 (off-screen right) and walks LEFT to 0 (stance).
    @State private var enemyX: CGFloat = 220
    @State private var enemyY: CGFloat = 0
    @State private var enemyYTarget: CGFloat = 0
    @State private var enemyAI: EnemyAIPhase = .entering
    @State private var enemyStateTimer: Double = 0
    @State private var enemyHitFlash: Double = 0
    @State private var vargasPhase: Int = 1

    // Countdown shown after enemy finishes walking in
    @State private var readyCountdownText: String = ""

    // Walk animation tracking
    @State private var razePrevX: CGFloat = 0
    @State private var razePrevY: CGFloat = 0
    @State private var razeMovingTimer: Double = 0
    @State private var razeWalkClock: Double = 0
    @State private var enemyPrevX: CGFloat = 220
    @State private var enemyPrevY: CGFloat = 0
    @State private var enemyMovingTimer: Double = 0
    @State private var enemyWalkClock: Double = 0

    // Hitstop + screen shake
    @State private var hitStopTimer: Double = 0
    @State private var shakeAmount: CGFloat = 0

    // Feedback bloom
    @State private var feedbackText: String = ""
    @State private var feedbackColor: String = "FFFFFF"
    @State private var feedbackHold: Double = 0

    @State private var tutorialDismissed: Bool = false

    @State private var razeImage: UIImage?
    @State private var enemyImage: UIImage?

    @State private var slashOverlayAlpha: Double = 0

    @State private var statusBanner: String = ""
    @State private var statusBannerExpires: Date = .distantPast

    @State private var ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    @State private var lastFrameAt: Date = Date()

    private var currentEnemy: WaveEnemy {
        WaveEnemy.allCases[min(waveIndex, WaveEnemy.allCases.count - 1)]
    }
    private var currentProfile: EnemyProfile {
        enemyProfile(for: currentEnemy, vargasPhase: vargasPhase)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { screenGeo in
            ZStack(alignment: .top) {
                (currentEnemy == .vargas
                    ? Image("m4_5_office")
                    : Image("m4_5_pit"))
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenGeo.size.width, height: screenGeo.size.height)
                    .clipped()
                    .overlay(Color.black.opacity(0.30))
                    .offset(x: shakeAmount, y: shakeAmount * 0.5)

                arenaView
                    .frame(width: screenGeo.size.width)

                hudHeader
                    .frame(width: screenGeo.size.width)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    controlBar
                    Spacer(minLength: 0).frame(height: 34)
                }
                .frame(width: screenGeo.size.width, height: screenGeo.size.height)

                rangeIndicator
                    .frame(width: screenGeo.size.width)

                if feedbackHold > 0 { feedbackOverlay }
                if !statusBanner.isEmpty { bannerOverlay }
                if comboBannerHold > 0 { comboBannerOverlay }
                if !readyCountdownText.isEmpty { readyCountdownOverlay }
                if !tutorialDismissed && !gameOver { tutorialOverlay }
                if gameOver { endOverlay }
            }
            .frame(width: screenGeo.size.width, height: screenGeo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            startBrawl()
            razeImage  = BasementBrawlSpriteCache.shared.image(named: razeSpriteName)
            enemyImage = BasementBrawlSpriteCache.shared.image(named: enemySpriteName)
        }
        .onChange(of: razeSpriteName) { _, newName in
            razeImage = BasementBrawlSpriteCache.shared.image(named: newName)
        }
        .onChange(of: enemySpriteName) { _, newName in
            enemyImage = BasementBrawlSpriteCache.shared.image(named: newName)
        }
        .onReceive(ticker) { _ in tick() }
    }

    // MARK: HUD

    private var hudHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RAZE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color(hex: "00FF88"))
                    hpBar(value: playerHP, max: maxHP, color: "00FF88")
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("WAVE \(waveIndex + 1)/5")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color(hex: "00FFCC"))
                    if currentEnemy == .vargas {
                        Text("P\(vargasPhase)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "FF6633"))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(currentProfile.label)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(hex: "FF3344"))
                        .lineLimit(1)
                    hpBar(value: enemyHP, max: currentProfile.maxHP, color: "FF3344", reverse: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 54)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.85), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        )
    }

    private func hpBar(value: Int, max: Int, color: String, reverse: Bool = false) -> some View {
        // Segment width auto-shrinks as max HP grows so the bar still fits.
        let segW: CGFloat = max <= 8 ? 18 : max <= 12 ? 11 : 9
        return HStack(spacing: 2) {
            ForEach(0..<max, id: \.self) { i in
                let active = (i < value)
                Rectangle()
                    .fill(active ? Color(hex: color) : Color.black.opacity(0.6))
                    .frame(width: segW, height: 10)
                    .overlay(Rectangle().stroke(Color(hex: color), lineWidth: 1))
            }
        }
        .environment(\.layoutDirection, reverse ? .rightToLeft : .leftToRight)
    }

    // MARK: Arena

    @ViewBuilder
    private var arenaView: some View {
        ZStack {
            // Foot shadow under Raze — pulses with bob to sell the walk
            Ellipse()
                .fill(Color.black.opacity(0.50))
                .frame(width: 90 - razeBob * 1.4, height: 14 - razeBob * 0.5)
                .blur(radius: 2)
                .offset(x: -90 + razeX, y: 220)

            // Foot shadow under enemy
            Ellipse()
                .fill(Color.black.opacity(0.55))
                .frame(width: enemyShadowWidth - enemyBob * 1.5, height: 16 - enemyBob * 0.6)
                .blur(radius: 2)
                .offset(x: 110 + enemyX, y: enemyShadowYOffset)

            // Raze sprite
            ZStack {
                if let img = razeImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .id("raze")
                } else {
                    Rectangle().fill(Color(hex: "00FF88").opacity(0.4))
                        .overlay(Text("RAZE").foregroundColor(.white))
                }
            }
            .frame(width: 280, height: 280)
            .opacity(playerHitFlash > 0 ? 0.5 : (razeIFrames > 0 ? 0.7 : 1.0))
            .scaleEffect(playerHitFlash > 0 ? 0.95 : 1.0)
            .rotationEffect(.degrees(razeStunTimer > 0
                ? sin(Date().timeIntervalSince1970 * 25) * 8
                : (razeMovingTimer > 0.05 ? sin(razeWalkClock * 11) * 2.5 : 0)))
            .offset(x: -90 + razeX, y: 80 + razeY - razeBob)
            // Cyan ghost-trail during i-frames so the dodge reads visually
            .overlay(
                razeIFrames > 0
                    ? Color(hex: "33C0FF").opacity(0.45).blendMode(.plusLighter)
                        .frame(width: 280, height: 280)
                        .offset(x: -90 + razeX, y: 80 + razeY - razeBob)
                    : nil
            )
            // "STUN" indicator when player whiffed STRIKE/HEAVY
            .overlay(
                razeStunTimer > 0
                    ? Text("STUN!")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "FF9933"))
                        .shadow(color: .black, radius: 3)
                        .offset(x: -90 + razeX, y: 80 + razeY - razeBob - 120)
                    : nil
            )

            // Enemy sprite
            ZStack {
                if let img = enemyImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .id("enemy")
                } else {
                    Rectangle().fill(Color(hex: "FF3344").opacity(0.4))
                        .overlay(Text(currentEnemy.label).foregroundColor(.white))
                }
            }
            .frame(width: enemyDisplayWidth, height: enemyDisplayHeight)
            .modifier(EnemyHitFlash(active: enemyHitFlash > 0))
            .scaleEffect(enemyHitFlash > 0 ? 1.05 : 1.0)
            .rotationEffect(.degrees(enemyMovingTimer > 0.05 ? sin(enemyWalkClock * 9) * 3 : 0))
            .offset(x: 110 + enemyX, y: 60 + enemyY - enemyBob)
            // Bright red wash on the sprite during the windup tell
            .overlay(
                enemyAI == .winding
                    ? Color(hex: "FF3344").opacity(0.55).blendMode(.plusLighter)
                        .offset(x: 110 + enemyX, y: 60 + enemyY - enemyBob)
                    : nil
            )

            // Pulsing red ring around the enemy during the windup — pure attention-grabber
            if enemyAI == .winding {
                let pulse = 1.0 + sin(enemyStateTimer * 12) * 0.10
                Rectangle()
                    .stroke(Color(hex: "FF1133"), lineWidth: 4)
                    .frame(width: enemyDisplayWidth * 0.95 * pulse,
                           height: enemyDisplayHeight * 0.7 * pulse)
                    .shadow(color: Color(hex: "FF1133").opacity(0.9), radius: 12)
                    .offset(x: 110 + enemyX, y: 60 + enemyY - enemyBob)
                    .allowsHitTesting(false)
                // Big floating "!" above the enemy head
                Text("!")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "FF1133"))
                    .shadow(color: .white.opacity(0.7), radius: 6)
                    .offset(x: 110 + enemyX,
                            y: 60 + enemyY - enemyBob - enemyDisplayHeight * 0.55
                                + CGFloat(sin(enemyStateTimer * 16)) * 4)
                    .allowsHitTesting(false)
            }

            // Parry stun — golden ring + stars indicator
            if enemyStunTimer > 0 {
                Rectangle()
                    .stroke(Color(hex: "FFE044"), lineWidth: 4)
                    .frame(width: enemyDisplayWidth * 0.95,
                           height: enemyDisplayHeight * 0.7)
                    .shadow(color: Color(hex: "FFE044").opacity(0.9), radius: 14)
                    .offset(x: 110 + enemyX, y: 60 + enemyY - enemyBob)
                    .allowsHitTesting(false)
                Text("✦ ✦ ✦")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(Color(hex: "FFE044"))
                    .offset(x: 110 + enemyX,
                            y: 60 + enemyY - enemyBob - enemyDisplayHeight * 0.55)
                    .allowsHitTesting(false)
            }

            // In-range reticle around enemy — green when Raze can land HEAVY
            if razeInJabRange && enemyAI != .entering && enemyAI != .readying && enemyAI != .dying && enemyAI != .winding && enemyStunTimer <= 0 {
                Rectangle()
                    .stroke(Color(hex: "00FF88").opacity(0.7), lineWidth: 2)
                    .frame(width: enemyDisplayWidth * 0.85, height: enemyDisplayHeight * 0.6)
                    .offset(x: 110 + enemyX, y: 60 + enemyY - enemyBob)
                    .allowsHitTesting(false)
            }

            if slashOverlayAlpha > 0 {
                Path { path in
                    path.move(to: CGPoint(x: 140, y: 80))
                    path.addLine(to: CGPoint(x: 340, y: 320))
                    path.move(to: CGPoint(x: 160, y: 130))
                    path.addLine(to: CGPoint(x: 360, y: 380))
                }
                .stroke(Color.white, lineWidth: 4)
                .blur(radius: 2)
                .opacity(slashOverlayAlpha)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let dx = razeDragStart.width + value.translation.width
                    let dy = razeDragStart.height + value.translation.height
                    razeX = max(razeMoveXRange.lowerBound, min(razeMoveXRange.upperBound, dx))
                    razeY = max(razeMoveYRange.lowerBound, min(razeMoveYRange.upperBound, dy))
                }
                .onEnded { _ in
                    razeDragStart = CGSize(width: razeX, height: razeY)
                }
        )
    }

    private var enemyDisplayHeight: CGFloat {
        switch currentEnemy {
        case .brawler:   return 360
        case .slugger:   return 420
        case .razorgirl: return 340
        case .bodyguard: return 380
        case .vargas:    return 460
        }
    }
    private var enemyDisplayWidth: CGFloat { enemyDisplayHeight * 0.7 }
    private var enemyShadowWidth: CGFloat { enemyDisplayHeight * 0.32 }
    private var enemyShadowYOffset: CGFloat { 60 + enemyDisplayHeight * 0.42 }

    private var razeBob: CGFloat {
        razeMovingTimer > 0.05 ? CGFloat(sin(razeWalkClock * 12)) * 5 : 0
    }
    private var enemyBob: CGFloat {
        enemyMovingTimer > 0.05 ? CGFloat(sin(enemyWalkClock * 9)) * 6 : 0
    }

    private var rangeIndicator: some View {
        HStack {
            Spacer()
            Text(rangeStatusText)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(2)
                .foregroundColor(rangeStatusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(rangeStatusColor, lineWidth: 1)
                        )
                )
                .padding(.top, 130)
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var rangeStatusText: String {
        if enemyAI == .entering { return "INCOMING" }
        if enemyAI == .readying { return "READY..." }
        return razeInJabRange ? "IN RANGE" : "OUT OF RANGE — DRAG TO CLOSE"
    }
    private var rangeStatusColor: Color {
        if enemyAI == .entering || enemyAI == .readying { return Color(hex: "FFC844") }
        return razeInJabRange ? Color(hex: "00FF88") : Color(hex: "FF9933")
    }

    // MARK: Controls

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                attackButton(label: "JAB",    hex: "00DDFF", attack: .jab)
                attackButton(label: "STRIKE", hex: "00FF88", attack: .strike)
                attackButton(label: "HEAVY",  hex: "FF6633", attack: .heavy)
            }
            HStack(spacing: 8) {
                stepBackButton
                blockButton
            }
        }
        .padding(.horizontal, 12)
    }

    private var stepBackButton: some View {
        let isAvailable = !gameOver && tutorialDismissed && enemyAI != .entering && enemyAI != .readying
        return Text("← STEP BACK")
            .font(.system(size: 12, weight: .black, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: isAvailable ? "33C0FF" : "777777").opacity(isAvailable ? 1.0 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.3), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard isAvailable else { return }
                performStepBack()
            }
    }

    /// Tap-to-retreat. Pushes Raze ~80px back toward home (capped at home),
    /// briefly grants i-frames so the move is useful even when mistimed.
    /// Resets the drag anchor so the next drag picks up from the new position.
    private func performStepBack() {
        let stepDistance: CGFloat = 80
        razeX = max(razeMoveXRange.lowerBound, razeX - stepDistance)
        razeDragStart = CGSize(width: razeX, height: razeY)
        razeIFrames = 0.55   // generous window so the tap doesn't have to be frame-perfect
        playerHitFlash = 0.08
        HapticsManager.shared.buttonTap()
        showFeedback("STEPPED BACK", color: "33C0FF")
    }

    private func attackButton(label: String, hex: String, attack: PlayerAttack) -> some View {
        let isAvailable = razeCooldown <= 0 && razeStunTimer <= 0 && !razeIsBlocking && !gameOver && tutorialDismissed && enemyAI != .entering && enemyAI != .readying
        return Text(label)
            .font(.system(size: 14, weight: .black))
            .foregroundColor(isAvailable ? .black : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: hex).opacity(isAvailable ? 1.0 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(color: Color(hex: hex).opacity(isAvailable ? 0.5 : 0), radius: 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isAvailable else { return }
                performAttack(attack)
            }
    }

    private var blockButton: some View {
        Text(razeIsBlocking ? "BLOCKING" : "BLOCK (HOLD)")
            .font(.system(size: 13, weight: .black))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(razeIsBlocking ? Color(hex: "FFC844") : Color(hex: "AAAAAA"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.3), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            // The press starts the block immediately AND tries to parry —
            // a perfect-timed press in the last ~0.25s of windup negates
            // damage entirely and stuns the enemy for a counter window.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !razeIsBlocking {
                            razeIsBlocking = true
                            tryParry()
                        }
                    }
                    .onEnded { _ in razeIsBlocking = false }
            )
    }

    // MARK: Sprite resolvers

    /// Resolve to the first existing sprite name in `candidates`.
    /// Lets us prefer real walk frames when present and fall back to idle.
    private func firstAvailable(_ candidates: [String]) -> String {
        for name in candidates {
            if BasementBrawlSpriteCache.shared.image(named: name) != nil {
                return name
            }
        }
        return candidates.last ?? ""
    }

    private var razeSpriteName: String {
        if gameOver && didWin    { return "raze_right_victory_0" }
        if playerHitFlash > 0    { return "raze_right_hit_0" }
        if razeStunTimer > 0     { return "raze_right_hit_0" }
        if razeAttackHold > 0    { return "raze_right_attack_0" }
        if razeIsBlocking        { return "raze_right_idle_1" }
        if razeMovingTimer > 0.05 {
            // Prefer dedicated walk frames if shipped; fall back to alternating idles.
            let phase = Int(razeWalkClock * 6) % 2
            return firstAvailable([
                "raze_right_walk_\(phase)",
                phase == 0 ? "raze_right_idle_0" : "raze_right_idle_1"
            ])
        }
        return "raze_right_idle_0"
    }

    private var enemySpriteName: String {
        let base: String
        switch currentEnemy {
        case .brawler:   base = "brawler"
        case .slugger:   base = "slugger"
        case .razorgirl: base = "razorgirl"
        case .bodyguard: base = "bodyguard"
        case .vargas:    base = "vargas"
        }
        if enemyAI == .dying { return "\(base)_down_0" }

        if currentEnemy == .vargas {
            switch enemyAI {
            case .winding:    return "vargas_phase\(vargasPhase)_charge"
            case .striking:   return "vargas_phase\(vargasPhase)_attack"
            default:
                if enemyMovingTimer > 0.05 {
                    let phase = Int(enemyWalkClock * 5) % 2
                    return firstAvailable([
                        "vargas_walk_\(phase)",
                        phase == 0 ? "vargas_idle_0" : "vargas_idle_1"
                    ])
                }
                return vargasPhase == 1 ? "vargas_idle_0" : "vargas_idle_1"
            }
        }

        switch enemyAI {
        case .winding, .striking:
            return "\(base)_attack_0"
        case .entering, .readying, .approaching, .recovering:
            if enemyMovingTimer > 0.05 {
                let phase = Int(enemyWalkClock * 5) % 2
                return firstAvailable([
                    "\(base)_walk_\(phase)",
                    "\(base)_idle_0"
                ])
            }
            return "\(base)_idle_0"
        case .dying:
            return "\(base)_down_0"
        }
    }

    // MARK: - Game loop

    private func startBrawl() {
        playerHP = maxHP
        waveIndex = 0
        beginWave()
    }

    private func beginWave() {
        let profile = currentProfile
        enemyHP = profile.maxHP
        razeX = 0; razeY = 0
        razeDragStart = .zero
        razePrevX = 0; razePrevY = 0
        enemyX = enemyEntryX     // far right, walks LEFT to stance
        enemyPrevX = enemyEntryX
        // Enemy enters with a Y offset from Raze's home — so the player has
        // to consciously line up Y to land hits AND the default standoff is
        // not in the enemy's attack-Y window. Forces positioning play.
        enemyY = -45
        enemyPrevY = -45
        enemyYTarget = -45
        enemyAI = .entering
        enemyStateTimer = 0
        readyCountdownText = ""
        enemyStunTimer = 0
        enemyComboFired = false
        whiffRecoveryBonus = 0
        razeStunTimer = 0
        comboLastAttack = nil
        comboCount = 0
        comboTimer = 0
        comboBannerHold = 0
        razeAttackPose = nil
        razeAttackHold = 0
        razeCooldown = 0
        razeIsBlocking = false
        razeMovingTimer = 0
        enemyMovingTimer = 0
        vargasPhase = 1
        showBanner("WAVE \(waveIndex + 1) — \(profile.label) INCOMING")
    }

    private func tick() {
        guard !gameOver, tutorialDismissed else {
            lastFrameAt = Date()
            return
        }
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastFrameAt))
        lastFrameAt = now

        if hitStopTimer > 0 {
            hitStopTimer = max(0, hitStopTimer - dt)
            return
        }

        if playerHitFlash > 0 { playerHitFlash = max(0, playerHitFlash - dt) }
        if razeIFrames > 0    { razeIFrames    = max(0, razeIFrames    - dt) }
        if razeStunTimer > 0  { razeStunTimer  = max(0, razeStunTimer  - dt) }
        if enemyHitFlash > 0  { enemyHitFlash  = max(0, enemyHitFlash  - dt) }
        if enemyStunTimer > 0 { enemyStunTimer = max(0, enemyStunTimer - dt) }
        if razeAttackHold > 0 { razeAttackHold = max(0, razeAttackHold - dt) }
        if razeCooldown > 0   { razeCooldown   = max(0, razeCooldown   - dt) }
        if comboTimer > 0 {
            comboTimer = max(0, comboTimer - dt)
            if comboTimer == 0 {
                comboLastAttack = nil
                comboCount = 0
            }
        }
        if comboBannerHold > 0 { comboBannerHold = max(0, comboBannerHold - dt) }
        if feedbackHold > 0   { feedbackHold   = max(0, feedbackHold   - dt) }
        if slashOverlayAlpha > 0 { slashOverlayAlpha = max(0, slashOverlayAlpha - dt * 4) }
        if shakeAmount > 0 {
            shakeAmount = max(0, shakeAmount - CGFloat(dt) * 80)
            shakeAmount *= -1
        }
        if !statusBanner.isEmpty && Date() > statusBannerExpires { statusBanner = "" }

        // ---- Walk-animation tracking ----
        let razeMoved = abs(razeX - razePrevX) > 0.5 || abs(razeY - razePrevY) > 0.5
        if razeMoved {
            razeMovingTimer = 0.18
        } else if razeMovingTimer > 0 {
            razeMovingTimer = max(0, razeMovingTimer - dt)
        }
        razePrevX = razeX
        razePrevY = razeY
        if razeMovingTimer > 0 { razeWalkClock += dt }

        let enemyMoved = abs(enemyX - enemyPrevX) > 0.5 || abs(enemyY - enemyPrevY) > 0.5
        if enemyMoved {
            enemyMovingTimer = 0.20
        } else if enemyMovingTimer > 0 {
            enemyMovingTimer = max(0, enemyMovingTimer - dt)
        }
        enemyPrevX = enemyX
        enemyPrevY = enemyY
        if enemyMovingTimer > 0 { enemyWalkClock += dt }

        tickEnemyAI(dt: dt)
    }

    private func tickEnemyAI(dt: Double) {
        let profile = currentProfile
        enemyStateTimer += dt

        // Parry-stun: enemy is frozen, no decisions, no Y drift. Recovery
        // resumes in .approaching when the stun ends.
        if enemyStunTimer > 0 {
            return
        }

        // Bob Y toward target
        enemyY += (enemyYTarget - enemyY) * CGFloat(dt * 2.0)

        switch enemyAI {
        case .entering:
            // Walk in from off-screen-right (+220) to stance position (0).
            // Steady speed, no attacks until we arrive.
            let walkSpeed = profile.approachSpeed * 0.85
            if enemyX > enemyStanceX {
                enemyX = max(enemyStanceX, enemyX - CGFloat(dt) * walkSpeed)
            } else {
                // Hold the staggered Y through readying — keeps the
                // standoff feeling off-axis so the player has to use the
                // arena, not just stand still.
                enterEnemyState(.readying)
            }

        case .readying:
            // 3-2-1-FIGHT countdown. No attacks, enemy idles at stance.
            // Player can position freely during this window.
            let t = enemyStateTimer
            if t < 0.8 {
                if readyCountdownText != "3" { readyCountdownText = "3" }
            } else if t < 1.6 {
                if readyCountdownText != "2" { readyCountdownText = "2" }
            } else if t < 2.4 {
                if readyCountdownText != "1" { readyCountdownText = "1" }
            } else if t < 3.2 {
                if readyCountdownText != "FIGHT!" {
                    readyCountdownText = "FIGHT!"
                    HapticsManager.shared.selectAffirm()
                }
            } else {
                readyCountdownText = ""
                enemyYTarget = razeY + CGFloat.random(in: -30...30)
                // Short grace after FIGHT! — just enough to react to the
                // first windup, not long enough to be free hits. Players
                // can't passively eat the round, they have to actually fight.
                razeIFrames = 1.2
                enterEnemyState(.approaching)
            }

        case .approaching:
            let gap = combatGap
            if gap > profile.attackRangeX * 0.85 {
                // Walk LEFT toward Raze — decrease enemyX (can go negative to close)
                enemyX = max(-60, enemyX - CGFloat(dt) * profile.approachSpeed)
            }
            if enemyStateTimer.truncatingRemainder(dividingBy: 1.4) < dt {
                enemyYTarget = razeY + CGFloat.random(in: -40...40)
            }
            if gap <= profile.attackRangeX
               && abs(enemyY - razeY) <= profile.attackRangeY * 1.2 {
                enterEnemyState(.winding)
            }

        case .winding:
            if enemyStateTimer >= profile.windupTime {
                enterEnemyState(.striking)
            }

        case .striking:
            if enemyStateTimer >= profile.strikeTime {
                if profile.archetype == .combo && !enemyComboFired {
                    // Razorgirl follow-up: chain into a fast 2nd windup,
                    // skipping most of the windup duration. Players need to
                    // react to TWO incoming strikes back-to-back — block
                    // first, parry second, or step back for both.
                    enemyComboFired = true
                    enemyAI = .winding
                    enemyStateTimer = profile.windupTime * 0.55
                } else {
                    enemyComboFired = false
                    enterEnemyState(.recovering)
                }
            }

        case .recovering:
            if enemyStateTimer >= profile.recoverTime + whiffRecoveryBonus {
                whiffRecoveryBonus = 0
                enemyYTarget = CGFloat.random(in: -50...50)
                enterEnemyState(.approaching)
            }

        case .dying:
            if enemyStateTimer >= 1.2 {
                advanceWave()
            }
        }
    }

    private func enterEnemyState(_ next: EnemyAIPhase) {
        enemyAI = next
        enemyStateTimer = 0

        if next == .striking {
            let profile = currentProfile
            let inX = combatGap <= profile.attackRangeX
            let inY = abs(enemyY - razeY) <= profile.attackRangeY
            if inX && inY {
                if razeIFrames > 0 {
                    HapticsManager.shared.buttonTap()
                    showFeedback("DODGED!", color: "33C0FF")
                    // Whiffed enemy attack — they pay for it with extra
                    // recovery (skipping their normal recover, going right
                    // into a vulnerable open window).
                    extendEnemyRecoveryAfterMiss()
                } else if razeIsBlocking {
                    // Chip damage — perma-blocking still bleeds you out
                    HapticsManager.shared.attackHit()
                    applyDamageToPlayer(amount: blockChipDamage)
                    showFeedback("BLOCKED — −\(blockChipDamage) chip", color: "FFC844")
                } else {
                    applyDamageToPlayer(amount: profile.attackDamage)
                    showFeedback("HIT — −\(profile.attackDamage) HP", color: "FF3344")
                }
            } else {
                // Enemy whiffed via spacing — punish them with longer recovery
                extendEnemyRecoveryAfterMiss()
            }
        }
    }

    private func advanceWave() {
        if waveIndex + 1 >= WaveEnemy.allCases.count {
            endGame(win: true)
        } else {
            // Wave-clear breather: refund 2 HP (capped at max).
            // Keeps the mission survivable across all 5 fights without
            // making it trivial — you can still get worn down.
            playerHP = min(maxHP, playerHP + 2)
            showFeedback("WAVE CLEAR — +2 HP", color: "00FF88")
            waveIndex += 1
            beginWave()
        }
    }

    // MARK: - Input

    /// Visual gap between Raze's right edge and enemy's left edge, in the
    /// same unit scale as PlayerAttack.rangeX / EnemyProfile.attackRangeX
    /// (~50 = melee touch, ~200 = arena's-length apart at entrance).
    private var combatGap: CGFloat {
        // razeScreenX = -90 + razeX ; enemyScreenX = 110 + enemyX
        // visual gap = (110 + enemyX) - (-90 + razeX) = 200 + enemyX - razeX
        // Subtract a fudge factor so the AI's existing 100/180 range tunings
        // still produce a sensible in-range threshold at the stance distance.
        return (200 + enemyX - razeX) - 100
    }

    private var razeInJabRange: Bool {
        let attack = PlayerAttack.heavy
        return combatGap <= attack.rangeX && abs(enemyY - razeY) <= attack.rangeY
    }

    /// Auto-lunge: if a tap-attack is just out of range, snap Raze forward
    /// up to `autoLungeMax` px so the tap always feels responsive.
    private func performAttack(_ attack: PlayerAttack) {
        // Stunned (from whiffing STRIKE/HEAVY) = no inputs accepted
        guard razeStunTimer <= 0 else { return }

        razeAttackPose = attack
        razeAttackHold = attack.poseHold
        razeCooldown = attack.cooldown

        let lungeShortfall = combatGap - attack.rangeX
        if lungeShortfall > 0 && lungeShortfall <= autoLungeMax {
            let step = min(lungeShortfall + 4, autoLungeMax)
            razeX = min(razeMoveXRange.upperBound, razeX + step)
            razeDragStart = CGSize(width: razeX, height: razeY)
        }

        let inX = combatGap <= attack.rangeX
        let inY = abs(enemyY - razeY) <= attack.rangeY
        let profile = currentProfile

        if inX && inY {
            // --- COMBO SYSTEM ---
            // Chain bonus: if the previous attack was a DIFFERENT type and
            // landed within `comboGraceWindow`, scale damage up.
            // JAB→STRIKE→HEAVY at full chain = 1x → 1.5x → 2x base damage.
            let isCombo = (comboLastAttack != nil && comboLastAttack != attack && comboTimer > 0)
            let newCount = isCombo ? min(3, comboCount + 1) : 1
            let mult = comboBaseDamageMult[newCount] ?? 1.0
            var dmg = Int((Double(attack.damage) * mult).rounded())

            // --- ARMOR ---
            // Slugger / Vargas-Phase-3 ignore non-HEAVY hits.
            var pierced = true
            if profile.armorBreakLevel >= 1 && attack != .heavy {
                dmg = 0
                pierced = false
            }

            applyDamageToEnemy(amount: dmg)
            if !pierced {
                showFeedback("TINK! armor", color: "AAAAAA")
            } else if isCombo {
                comboCount = newCount
                comboLastAttack = attack
                comboTimer = comboGraceWindow
                triggerComboBanner()
                let label = "COMBO ×\(newCount) — \(attack.comboSymbol) (−\(dmg))"
                showFeedback(label, color: attack == .jab ? "00DDFF" : attack == .strike ? "00FF88" : "FF6633")
            } else {
                comboCount = 1
                comboLastAttack = attack
                comboTimer = comboGraceWindow
                let label: String
                switch attack {
                case .jab:    label = "JAB — −\(dmg) HP"
                case .strike: label = "STRIKE — −\(dmg) HP"
                case .heavy:  label = "HEAVY HIT — −\(dmg) HP"
                }
                showFeedback(label, color: attack == .jab ? "00DDFF" : attack == .strike ? "00FF88" : "FF6633")
            }
        } else {
            // WHIFF — STRIKE/HEAVY commit you, leaving an opening for counter
            if attack.whiffStun > 0 {
                razeStunTimer = attack.whiffStun
            }
            // Whiffs break combo
            comboLastAttack = nil
            comboCount = 0
            comboTimer = 0
            showFeedback(inX ? "WHIFF — off-line" : "WHIFF — too far", color: "FF9933")
        }
    }

    private func triggerComboBanner() {
        let labels = ["", "HIT!", "DOUBLE!", "TRIPLE COMBO!"]
        comboBannerText = labels[min(comboCount, 3)]
        comboBannerHold = 1.0
    }

    /// Punish whiffed enemy attacks with extra recovery — the open window
    /// where the player should be jamming JAB/STRIKE/HEAVY for free damage.
    private func extendEnemyRecoveryAfterMiss() {
        whiffRecoveryBonus = 0.6
    }

    private func applyDamageToEnemy(amount: Int) {
        guard amount > 0 else {
            // Armor-bounce — still play a hit flash for feedback
            enemyHitFlash = 0.12
            shakeAmount = 2
            HapticsManager.shared.buttonTap()
            return
        }
        enemyHP = max(0, enemyHP - amount)
        enemyHitFlash = 0.20
        slashOverlayAlpha = 0.85
        hitStopTimer = 0.06
        shakeAmount = CGFloat(amount) * 4
        HapticsManager.shared.attackHit()

        if currentEnemy == .vargas {
            // HP thresholds re-tuned for the new 16 HP boss
            if vargasPhase == 1 && enemyHP <= 11 {
                vargasPhase = 2
                showBanner("VARGAS — PHASE 2")
            } else if vargasPhase == 2 && enemyHP <= 5 {
                vargasPhase = 3
                showBanner("VARGAS — OVERLOAD")
            }
        }

        if enemyHP == 0 {
            enterEnemyState(.dying)
            HapticsManager.shared.enemyKilled()
        }
    }

    /// Called when BLOCK is tapped (not held). If we tap inside the last
    /// `parryWindow` seconds of an enemy windup, that's a perfect parry —
    /// enemy gets stunned for `parryStunDuration`, full counter window.
    private func tryParry() {
        guard enemyAI == .winding else { return }
        let profile = currentProfile
        let timeUntilStrike = profile.windupTime - enemyStateTimer
        guard timeUntilStrike >= 0 && timeUntilStrike <= parryWindow else { return }
        enemyStunTimer = parryStunDuration
        // Cancel the wind-up — they don't strike, they get stunned
        enemyAI = .recovering
        enemyStateTimer = 0
        whiffRecoveryBonus = parryStunDuration
        HapticsManager.shared.victory()
        slashOverlayAlpha = 0.95
        showFeedback("⚡ PERFECT PARRY!", color: "FFE044")
        showBanner("COUNTER OPENING — STRIKE NOW")
    }

    private func applyDamageToPlayer(amount: Int) {
        playerHP = max(0, playerHP - amount)
        playerHitFlash = 0.22
        shakeAmount = CGFloat(amount) * 5
        HapticsManager.shared.playerDamaged()
        if playerHP == 0 { endGame(win: false) }
    }

    // MARK: - End game

    private func endGame(win: Bool) {
        guard !gameOver else { return }
        gameOver = true
        didWin = win
        if win {
            HapticsManager.shared.victory()
            SFXManager.shared.play("mission_victory")
            let score = 400 + playerHP * 60 + 500
            MissionStatsStore.shared.recordVictory(
                missionId: "Mission004_5",
                score: score,
                dataAcquired: true,
                grimoireAcquired: false
            )
        } else {
            HapticsManager.shared.defeat()
            SFXManager.shared.play("mission_defeat")
        }
    }

    private func exitBrawl() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .endBrawl(won: didWin))
    }

    // MARK: - Overlays

    private var feedbackOverlay: some View {
        VStack {
            Spacer()
            Text(feedbackText)
                .font(.system(size: 17, weight: .black))
                .foregroundColor(Color(hex: feedbackColor))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: feedbackColor), lineWidth: 2)
                        )
                )
                .shadow(color: Color(hex: feedbackColor).opacity(0.6), radius: 10)
                .padding(.bottom, 200)
                .opacity(min(1.0, feedbackHold / 0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var comboBannerOverlay: some View {
        VStack {
            Spacer().frame(height: 220)
            Text(comboBannerText)
                .font(.system(size: comboCount >= 3 ? 38 : 28, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "FFE044"))
                .tracking(2)
                .shadow(color: Color(hex: "FFE044").opacity(0.9), radius: 14)
                .scaleEffect(1.0 + CGFloat(max(0, comboBannerHold - 0.7)) * 0.6)
                .opacity(min(1.0, comboBannerHold * 1.2))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var readyCountdownOverlay: some View {
        let isFight = readyCountdownText == "FIGHT!"
        return VStack {
            Spacer()
            Text(readyCountdownText)
                .font(.system(size: isFight ? 72 : 110, weight: .black, design: .monospaced))
                .tracking(isFight ? 8 : 0)
                .foregroundColor(isFight ? Color(hex: "00FF88") : Color(hex: "FFC844"))
                .shadow(color: (isFight ? Color(hex: "00FF88") : Color(hex: "FFC844")).opacity(0.7),
                        radius: 18)
                .scaleEffect(isFight ? 1.0 : 1.15)
                .opacity(0.95)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var bannerOverlay: some View {
        VStack {
            Text(statusBanner)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(Color(hex: "00FFCC"))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "00FFCC"), lineWidth: 1)
                        )
                )
                .padding(.top, 160)
            Spacer()
        }
        .transition(.opacity)
    }

    private var tutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer().frame(height: 50)
                Text("BASEMENT BRAWL")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(Color(hex: "00FF88"))
                Text("Five enemies. Raze solo. Real-time.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                Spacer().frame(height: 6)

                Group {
                    Text("DRAG arena  →  move Raze in 2D")
                        .foregroundColor(.white)
                    Text("JAB / STRIKE / HEAVY  →  chain for combo!")
                        .foregroundColor(Color(hex: "FFE044"))
                    Text("← STEP  →  hop back + i-frames")
                        .foregroundColor(Color(hex: "33C0FF"))
                    Text("BLOCK  hold = absorb (chip dmg)")
                        .foregroundColor(Color(hex: "FFC844"))
                    Text("BLOCK  tap @ red flash = PARRY!")
                        .foregroundColor(Color(hex: "FFE044"))
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)

                Spacer().frame(height: 6)
                Text("Combo damages stack: J→S→H = 1× → 1.5× → 2×\nWhiff STRIKE/HEAVY and you're stunned — JAB is safe\nSlugger has armor — only HEAVY pierces him\nRazorgirl chains TWO strikes — parry the second!")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)

                Spacer()

                Button(action: {
                    HapticsManager.shared.selectAffirm()
                    tutorialDismissed = true
                    lastFrameAt = Date()
                }) {
                    Text("BEGIN")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: "00FF88"))
                        )
                        .shadow(color: Color(hex: "00FF88").opacity(0.6), radius: 12)
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(didWin ? "VARGAS DOWN" : "TAGGED")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(didWin ? Color(hex: "00FF88") : Color(hex: "FF3344"))
                Text(didWin
                     ? "MEKTON file recovered.\nTime to make Drachenwerk pay."
                     : "Vargas got the call out.\nBack to the safehouse — lesson learned.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(action: exitBrawl) {
                    Text("CONTINUE")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.black)
                        .frame(width: 200, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(didWin ? Color(hex: "00FF88") : Color(hex: "FF3344"))
                        )
                }
            }
        }
    }

    // MARK: - Helpers

    private func showBanner(_ text: String) {
        statusBanner = text
        statusBannerExpires = Date().addingTimeInterval(2.2)
    }

    private func showFeedback(_ text: String, color: String) {
        feedbackText = text
        feedbackColor = color
        feedbackHold = 1.4
    }
}

// MARK: - Sprite Cache + ViewModifier

final class BasementBrawlSpriteCache {
    static let shared = BasementBrawlSpriteCache()
    private var cache: [String: UIImage] = [:]
    private init() {}

    func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL
            .appendingPathComponent("Sprites/frames")
            .appendingPathComponent("\(name).png")
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = img
        return img
    }
}

private struct EnemyHitFlash: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.colorMultiply(Color(red: 1.0, green: 0.65, blue: 0.65))
        } else {
            content
        }
    }
}
