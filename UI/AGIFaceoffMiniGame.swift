import SwiftUI
import Combine

/// AGI FACE-OFF — Mission 6's boss-tier data-extraction mini-game.
///
/// Premise: the runner is now jacked DIRECTLY into the AGI's consciousness.
/// A glitching pixel-art AGI face fills the centre of the screen. Six
/// "exploit zones" cycle through dormant → warning → vulnerable → cooldown
/// on the AGI's armour plates (temples / eyes / forehead / jaw). Tap each
/// one inside its vulnerability window to land an exploit and damage the
/// AGI. Meanwhile the AGI fires "code waves" — expanding glyph rings —
/// that you must SWIPE across to deflect before they hit you.
///
/// Inputs:
///   • TAP an exploit zone   → tries to land an exploit (must be vulnerable)
///   • SWIPE anywhere        → deflects every active wave that's mid-flight
///
/// Win:  drain the AGI's HP to 0 before the trace bar fills.
/// Lose: trace bar fills.
struct AGIFaceoffMiniGame: View {
    @ObservedObject var gameState: GameState
    let onComplete: (Bool) -> Void

    // MARK: - Tuning

    private let agiMaxHP = 100
    /// Damage dealt per successful exploit-zone tap.
    private let exploitDamage = 12
    /// Trace damage from a missed code wave (it slipped past you).
    private let waveTraceDamage: CGFloat = 0.16
    /// Trace damage from tapping an exploit zone in the wrong phase.
    private let wrongTapTraceDamage: CGFloat = 0.06
    /// Background trace drift per second.
    private let traceDrift: CGFloat = 0.012
    /// Lifetime of the "vulnerable" phase of an exploit zone (seconds).
    private let vulnerableDuration: Double = 1.5
    /// Pre-vulnerable warning window (yellow telegraph).
    private let warningDuration: Double = 0.8
    /// Total time a code wave takes to reach the screen edge.
    private let waveLifetime: Double = 1.6
    /// Seconds between code-wave spawns. Decreases as AGI takes damage.
    private let baseWaveSpawnInterval: Double = 2.6
    /// Seconds between exploit zones cycling.
    private let exploitRefreshInterval: Double = 2.0

    // MARK: - Models

    enum ExploitPhase {
        case dormant       // not active
        case warning       // yellow pulse — telegraphs an upcoming opening
        case vulnerable    // cyan ring — tap NOW
        case cooldown      // dim — just-used or just-missed
    }

    struct ExploitZone: Identifiable {
        let id: Int
        var phase: ExploitPhase = .dormant
        /// Seconds remaining in the current phase.
        var remaining: Double = 0
    }

    struct CodeWave: Identifiable {
        let id = UUID()
        var spawnedAt: Double      // elapsed time when the wave fired
        var deflected: Bool = false
        var dealtDamage: Bool = false
        let glyph: String          // glyph drawn around the ring
        let color: Color
    }

    enum FaceMood {
        case neutral
        case hit         // briefly when an exploit lands
        case attacking   // briefly when AGI fires a wave
        case rage        // when HP < 30%
    }

    // MARK: - State

    @State private var agiHP: Int = 100
    @State private var traceBar: CGFloat = 0
    @State private var elapsed: Double = 0
    @State private var exploitZones: [ExploitZone] = []
    @State private var waves: [CodeWave] = []
    @State private var mood: FaceMood = .neutral
    @State private var moodRemaining: Double = 0
    @State private var glitchPhase: Double = 0
    @State private var pulseTime: Double = 0
    @State private var gameOver: Bool = false
    @State private var didWin: Bool = false
    @State private var lastSwipeTime: Double = -10

    @State private var tickTimer: AnyCancellable?
    @State private var waveSpawnTimer: AnyCancellable?
    /// `elapsed` when the last wave spawned (-1 = none yet). Drives spawn
    /// pacing off actual spawn cadence rather than the (despawning) waves array.
    @State private var lastWaveSpawnedAt: Double = -1
    @State private var nextExploitTime: Double = 0
    @State private var pulseTimer: AnyCancellable?
    @State private var rainTimer: AnyCancellable?
    @State private var codeRain: [RainColumn] = []
    @State private var chiptune: ChiptunePlayer? = nil

    // MARK: - Tutorial / onboarding

    /// Onboarding phase. Each phase teaches one input at a time, then the
    /// real fight starts.
    enum TutorialPhase {
        case briefing       // intro card showing rules — gameplay paused
        case exploitsOnly   // first vulnerable exploit, no waves; teaches TAP
        case wavesOnly      // first wave, no exploits; teaches SWIPE
        case full           // real fight — both at once
    }
    @State private var tutorialPhase: TutorialPhase = .briefing
    @State private var tutorialStepCompleted: Int = 0   // counters for advancement
    @State private var swipeHintRemaining: Double = 0   // seconds the "SWIPE!" prompt is up

    struct RainColumn: Identifiable {
        let id = UUID()
        var x: CGFloat
        var headY: CGFloat
        var glyphs: [String]
        var speed: CGFloat
    }
    private static let rainPool: [String] = [
        "0", "1", "F", "7", "A", "C", "E", "9", "B3", "FF", "C0", "DE",
    ]

    // MARK: - Face anchor positions (normalised within face canvas)

    /// Exploit zones map onto these anchors on the AGI face.
    /// 0 = left temple, 1 = right temple, 2 = left eye, 3 = right eye,
    /// 4 = forehead, 5 = jaw.
    private static let faceAnchors: [CGPoint] = [
        CGPoint(x: 0.20, y: 0.22),   // left temple
        CGPoint(x: 0.80, y: 0.22),   // right temple
        CGPoint(x: 0.32, y: 0.42),   // left eye
        CGPoint(x: 0.68, y: 0.42),   // right eye
        CGPoint(x: 0.50, y: 0.18),   // forehead
        CGPoint(x: 0.50, y: 0.78),   // jaw
    ]
    private static let anchorLabels: [String] = [
        "TMPL", "TMPL", "EYE", "EYE", "FRNT", "JAW"
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "10000A"), Color(hex: "08010A"), Color(hex: "10000A")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                objectiveBanner
                faceArea
                hud
                touchHint
            }
            .padding(.bottom, 28)

            // Tutorial / briefing overlay — shown first before any gameplay.
            if tutorialPhase == .briefing {
                briefingOverlay
            }
        }
        .onAppear {
            initialise()
            startTimers()
            startAudio()
        }
        .onDisappear {
            cancelTimers()
            chiptune?.stop()
            chiptune = nil
        }
    }

    /// Full-screen briefing card explaining how to play. Player taps START
    /// to dismiss and begin the tutorial.
    private var briefingOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("// BREACH PROTOCOL")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color(hex: "FF3344"))
                Text("AGI FACE-OFF")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FFFFFF"))
                Rectangle()
                    .fill(Color(hex: "FF3344").opacity(0.5))
                    .frame(width: 80, height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    briefingRow(icon: "hand.point.up.fill",
                                color: Color(hex: "00FFCC"),
                                title: "TAP CYAN RETICLES",
                                detail: "Cyan brackets flash on the AGI's armor. Tap them to land an exploit and damage the AGI.")
                    briefingRow(icon: "hand.draw.fill",
                                color: Color(hex: "FFCC00"),
                                title: "SWIPE THE CODE WAVES",
                                detail: "Glowing rings expand from the AGI's face. Swipe ANY direction across the screen to deflect them before they hit you.")
                    briefingRow(icon: "shield.fill",
                                color: Color(hex: "FF3344"),
                                title: "TRACE = DEATH",
                                detail: "Missed waves and wrong taps fill the trace bar. Drain the AGI's HP before the bar fills.")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(Color(hex: "1A0608").opacity(0.85))
                .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.5), lineWidth: 1))

                Button(action: {
                    HapticsManager.shared.buttonTap()
                    tutorialPhase = .exploitsOnly
                    // Schedule first exploit immediately
                    nextExploitTime = elapsed + 0.4
                }) {
                    Text("⟫  START BREACH  ⟪")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 14)
                        .background(Color(hex: "00FFCC"))
                        .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                }
                .frame(minHeight: 50)
            }
            .padding(.horizontal, 24)
        }
    }

    private func briefingRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(color)
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    /// One-line, big, can't-miss-it instruction above the face. Updates
    /// based on the current tutorial phase + what's on screen.
    private var objectiveBanner: some View {
        let (text, color): (String, Color) = {
            if gameOver {
                return (didWin ? "// AGI BREACHED" : "// CONNECTION LOST",
                        didWin ? Color(hex: "00FFCC") : Color(hex: "FF3344"))
            }
            switch tutorialPhase {
            case .briefing:
                return ("READY?", Color(hex: "FFCC00"))
            case .exploitsOnly:
                return ("TAP THE CYAN RETICLE",  Color(hex: "00FFCC"))
            case .wavesOnly:
                return ("SWIPE TO DEFLECT THE WAVE", Color(hex: "FFCC00"))
            case .full:
                if waves.contains(where: { !$0.deflected && !$0.dealtDamage }) &&
                   exploitZones.contains(where: { $0.phase == .vulnerable }) {
                    return ("TAP RETICLE — SWIPE WAVE", Color(hex: "FFFFFF"))
                } else if waves.contains(where: { !$0.deflected && !$0.dealtDamage }) {
                    return ("SWIPE TO DEFLECT", Color(hex: "FFCC00"))
                } else if exploitZones.contains(where: { $0.phase == .vulnerable }) {
                    return ("TAP THE EXPLOIT", Color(hex: "00FFCC"))
                } else {
                    return ("DRAIN AGI INTEGRITY", Color(hex: "FF3344"))
                }
            }
        }()
        return Text(text)
            .font(.system(size: 13, weight: .black, design: .monospaced))
            .tracking(2)
            .foregroundColor(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Rectangle().stroke(color.opacity(0.7), lineWidth: 1))
            )
            .padding(.bottom, 6)
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "FF3344"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6))
                Text("// AGI FACE-OFF")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FF3344"))
                Circle().fill(Color(hex: "FF00AA"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6 + .pi))
            }
            Text("BREACH THE AGI — TAP EXPLOITS, SWIPE THE WAVES")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private var faceArea: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color(hex: "1A0608"))
                    .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.45), lineWidth: 1))
                    .overlay(Rectangle().stroke(Color(hex: "FF00AA").opacity(0.18), lineWidth: 3))

                Canvas { ctx, size in
                    drawCodeRain(ctx: ctx, size: size)
                    drawScanlines(ctx: ctx, size: size)
                    drawAGIFace(ctx: ctx, size: size)
                    drawExploitZones(ctx: ctx, size: size)
                    drawCodeWaves(ctx: ctx, size: size)
                    drawSwipeHint(ctx: ctx, size: size)
                }

                // AGI HP bar overlay (top of the face area)
                VStack {
                    HStack(spacing: 0) {
                        Text("AGI INTEGRITY")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "FF3344"))
                            .padding(.trailing, 6)
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .frame(height: 8)
                                .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.7), lineWidth: 1))
                            Rectangle()
                                .fill(Color(hex: "FF3344"))
                                .frame(width: max(0, CGFloat(agiHP) / CGFloat(agiMaxHP)) * (geo.size.width - 96), height: 8)
                        }
                        .frame(maxWidth: .infinity)
                        Text("\(agiHP)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "FF3344"))
                            .padding(.leading, 8)
                            .frame(width: 36)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    Spacer()
                }

                if gameOver {
                    Color.black.opacity(0.78)
                    VStack(spacing: 6) {
                        Text(didWin ? "AGI BREACHED" : "AGI BURNED YOU")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(didWin ? Color(hex: "00FFCC") : Color(hex: "FF3344"))
                        Text(didWin ? "// CONSCIOUSNESS DUMPED" : "// JACKED OUT, MIND INTACT")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.8))
                    .overlay(
                        Rectangle().stroke(didWin ? Color(hex: "00FFCC") : Color(hex: "FF3344"), lineWidth: 1.5)
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { _ in handleSwipe() }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .padding(.horizontal, 8)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            statusBlock(label: "EXPLOITS",
                        value: "\(exploitsLanded) HIT",
                        color: Color(hex: "00FFCC"))
            statusBlock(label: "DEFLECTS",
                        value: "\(wavesDeflected) / \(wavesSpawned)",
                        color: Color(hex: "FFCC00"))
            statusBlock(label: "MOOD",
                        value: moodLabel,
                        color: moodColor)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @State private var exploitsLanded: Int = 0
    @State private var wavesDeflected: Int = 0
    @State private var wavesSpawned: Int = 0

    private var moodLabel: String {
        switch mood {
        case .neutral:   return "WATCHING"
        case .hit:       return "REELING"
        case .attacking: return "ATTACKING"
        case .rage:      return "RAGING"
        }
    }
    private var moodColor: Color {
        switch mood {
        case .neutral:   return Color(hex: "FFCC00")
        case .hit:       return Color(hex: "00FFCC")
        case .attacking: return Color(hex: "FF8833")
        case .rage:      return Color(hex: "FF3344")
        }
    }

    private var touchHint: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TAP + SWIPE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                Text("Tap cyan exploit zones — swipe to deflect waves.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "00FFCC").opacity(0.75))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("TRACE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: "FF3344").opacity(0.85))
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 80, height: 8)
                        .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.7), lineWidth: 1))
                    Rectangle()
                        .fill(Color(hex: "FF3344"))
                        .frame(width: max(0, min(1, traceBar)) * 80, height: 8)
                }
            }
            Button(action: {
                HapticsManager.shared.buttonTap()
                chiptune?.sfxBail()
                finishGame(success: false)
            }) {
                Text("BAIL")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(Color(hex: "FF3344"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.65))
                            .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.7), lineWidth: 1))
                    )
            }
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func statusBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .overlay(Rectangle().stroke(color.opacity(0.4), lineWidth: 1))
        )
    }

    // MARK: - Drawing

    /// Computes the centred face-canvas frame inside the available area.
    /// The face is a square that fits within the height with a margin.
    private func faceFrame(in size: CGSize) -> CGRect {
        let dim = min(size.width, size.height) - 60
        let x = (size.width - dim) / 2
        let y = (size.height - dim) / 2 + 6
        return CGRect(x: x, y: y, width: dim, height: dim)
    }

    private func drawCodeRain(ctx: GraphicsContext, size: CGSize) {
        for col in codeRain {
            for (i, g) in col.glyphs.enumerated() {
                let y = col.headY - CGFloat(i) * 14
                guard y >= -14, y <= size.height + 14 else { continue }
                let alpha = max(0, 1.0 - Double(i) * 0.08)
                let color = i == 0
                    ? Color.white.opacity(alpha * 0.55)
                    : Color(hex: "FF3344").opacity(alpha * 0.30)
                ctx.draw(
                    Text(g).font(.system(size: 11, weight: .regular, design: .monospaced))
                          .foregroundColor(color),
                    at: CGPoint(x: col.x, y: y)
                )
            }
        }
    }

    private func drawScanlines(ctx: GraphicsContext, size: CGSize) {
        let alpha = 0.05 + sin(pulseTime * 2.5) * 0.03
        var y: CGFloat = 0
        while y < size.height {
            ctx.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                with: .color(Color(hex: "FF3344").opacity(alpha))
            )
            y += 3
        }
    }

    /// AGI face — pixel-art rendering with mood-dependent frame swap.
    private func drawAGIFace(ctx: GraphicsContext, size: CGSize) {
        let frame = faceFrame(in: size)
        // Glitch jitter when hit / raging
        let jx = (mood == .hit || mood == .rage) ? CGFloat(sin(glitchPhase * 18)) * 2 : 0
        let jy = (mood == .hit || mood == .rage) ? CGFloat(cos(glitchPhase * 21)) * 2 : 0
        let palette = AGIFaceoffMiniGame.facePalette(mood: mood)
        let pattern = AGIFaceoffMiniGame.facePattern(mood: mood)
        let cols = pattern.first?.count ?? 0
        let rows = pattern.count
        guard cols > 0, rows > 0 else { return }
        // Scale pixels to fit face frame
        let pixelScale = min(frame.width / CGFloat(cols), frame.height / CGFloat(rows))
        let originX = frame.midX - CGFloat(cols) * pixelScale / 2 + jx
        let originY = frame.midY - CGFloat(rows) * pixelScale / 2 + jy
        // Subtle red halo around face for menace
        let halo = frame.insetBy(dx: -10, dy: -10)
        ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "FF3344").opacity(0.08)))

        for (row, line) in pattern.enumerated() {
            for (col, ch) in line.enumerated() {
                guard ch != ".",
                      let idx = Int(String(ch)),
                      idx >= 1, idx <= palette.count else { continue }
                let rect = CGRect(
                    x: originX + CGFloat(col) * pixelScale,
                    y: originY + CGFloat(row) * pixelScale,
                    width: pixelScale + 0.5,    // +0.5 to avoid hairline gaps
                    height: pixelScale + 0.5
                )
                ctx.fill(Path(rect), with: .color(palette[idx - 1]))
            }
        }

        // Glitch lines when raging — horizontal slices that shift the rendered face
        if mood == .rage {
            for _ in 0..<3 {
                let sliceY = frame.minY + CGFloat.random(in: 0...frame.height)
                let slice = CGRect(x: frame.minX, y: sliceY, width: frame.width, height: 2)
                ctx.fill(Path(slice), with: .color(Color(hex: "FF3344").opacity(0.4)))
            }
        }
    }

    private func drawExploitZones(ctx: GraphicsContext, size: CGSize) {
        let frame = faceFrame(in: size)
        for (i, zone) in exploitZones.enumerated() {
            guard i < AGIFaceoffMiniGame.faceAnchors.count else { continue }
            let anchor = AGIFaceoffMiniGame.faceAnchors[i]
            let cx = frame.minX + anchor.x * frame.width
            let cy = frame.minY + anchor.y * frame.height
            // Bumped 2026-05 (was 36) — playtest showed the reticles were
            // hard to tap accurately with a fingertip. 48 is closer to the
            // 44pt minimum tap target Apple recommends.
            let zoneSize: CGFloat = 48
            let r = CGRect(x: cx - zoneSize/2, y: cy - zoneSize/2,
                           width: zoneSize, height: zoneSize)

            switch zone.phase {
            case .dormant:
                continue   // not drawn
            case .warning:
                // Yellow telegraph — small reticle pulsing in
                let progress = 1.0 - zone.remaining / warningDuration
                let pSize = zoneSize * (0.4 + 0.6 * CGFloat(progress))
                let pr = CGRect(x: cx - pSize/2, y: cy - pSize/2,
                                width: pSize, height: pSize)
                ctx.stroke(Path(ellipseIn: pr),
                           with: .color(Color(hex: "FFCC00").opacity(0.55)),
                           lineWidth: 2)
                // Crosshair
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: cx - 6, y: cy))
                        p.addLine(to: CGPoint(x: cx + 6, y: cy))
                        p.move(to: CGPoint(x: cx, y: cy - 6))
                        p.addLine(to: CGPoint(x: cx, y: cy + 6))
                    },
                    with: .color(Color(hex: "FFCC00").opacity(0.85)),
                    lineWidth: 1
                )
            case .vulnerable:
                // Cyan reticle — tap NOW
                let pulse = 1.0 + 0.18 * sin(pulseTime * 8)
                let outerR = zoneSize * pulse
                let halo = CGRect(x: cx - outerR/2, y: cy - outerR/2,
                                  width: outerR, height: outerR)
                ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "00FFCC").opacity(0.30)))
                ctx.stroke(Path(ellipseIn: r),
                           with: .color(Color(hex: "00FFCC")),
                           lineWidth: 2.2)
                // Inner reticle bracket
                let bw: CGFloat = 8
                ctx.stroke(
                    Path { p in
                        // top-left corner
                        p.move(to: CGPoint(x: cx - zoneSize/2 + 2, y: cy - zoneSize/2 + bw))
                        p.addLine(to: CGPoint(x: cx - zoneSize/2 + 2, y: cy - zoneSize/2 + 2))
                        p.addLine(to: CGPoint(x: cx - zoneSize/2 + bw, y: cy - zoneSize/2 + 2))
                        // top-right
                        p.move(to: CGPoint(x: cx + zoneSize/2 - bw, y: cy - zoneSize/2 + 2))
                        p.addLine(to: CGPoint(x: cx + zoneSize/2 - 2, y: cy - zoneSize/2 + 2))
                        p.addLine(to: CGPoint(x: cx + zoneSize/2 - 2, y: cy - zoneSize/2 + bw))
                        // bottom-right
                        p.move(to: CGPoint(x: cx + zoneSize/2 - 2, y: cy + zoneSize/2 - bw))
                        p.addLine(to: CGPoint(x: cx + zoneSize/2 - 2, y: cy + zoneSize/2 - 2))
                        p.addLine(to: CGPoint(x: cx + zoneSize/2 - bw, y: cy + zoneSize/2 - 2))
                        // bottom-left
                        p.move(to: CGPoint(x: cx - zoneSize/2 + bw, y: cy + zoneSize/2 - 2))
                        p.addLine(to: CGPoint(x: cx - zoneSize/2 + 2, y: cy + zoneSize/2 - 2))
                        p.addLine(to: CGPoint(x: cx - zoneSize/2 + 2, y: cy + zoneSize/2 - bw))
                    },
                    with: .color(Color(hex: "00FFCC")),
                    lineWidth: 2
                )
                // Label
                ctx.draw(
                    Text(AGIFaceoffMiniGame.anchorLabels[i])
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFCC")),
                    at: CGPoint(x: cx, y: cy + zoneSize/2 + 6)
                )
            case .cooldown:
                // Brief grey pulse to confirm result
                let alpha = max(0.0, zone.remaining / 0.4) * 0.5
                ctx.stroke(Path(ellipseIn: r),
                           with: .color(Color(hex: "888888").opacity(alpha)),
                           lineWidth: 1.5)
            }
        }
    }

    /// Big animated "SWIPE!" prompt overlay — fires when a new wave spawns
    /// for the player's first few waves so they understand what to do.
    private func drawSwipeHint(ctx: GraphicsContext, size: CGSize) {
        guard swipeHintRemaining > 0 else { return }
        let frame = faceFrame(in: size)
        let progress = 1.0 - swipeHintRemaining / (waveLifetime * 0.6)
        let alpha = min(1.0, swipeHintRemaining * 2.5)   // fade out at end

        // Draw two animated arrows — one from the right, one from the left,
        // sliding inward. Big and obvious.
        let centerY = frame.midY
        let arrowSpan: CGFloat = 110
        let offsetX: CGFloat = 18 + 26 * CGFloat(sin(pulseTime * 8))   // pulses in/out

        // Left arrow: pointing right
        drawSwipeArrow(ctx: ctx,
                       at: CGPoint(x: frame.minX - 8 + offsetX, y: centerY),
                       width: arrowSpan,
                       direction: .right,
                       color: Color(hex: "FFCC00").opacity(alpha))

        // Right arrow: pointing left
        drawSwipeArrow(ctx: ctx,
                       at: CGPoint(x: frame.maxX + 8 - offsetX, y: centerY),
                       width: arrowSpan,
                       direction: .left,
                       color: Color(hex: "FFCC00").opacity(alpha))

        // Big SWIPE! label
        let label = "SWIPE!"
        ctx.draw(
            Text(label)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: "FFCC00").opacity(alpha)),
            at: CGPoint(x: frame.midX, y: frame.minY + 20)
        )
        ctx.draw(
            Text("ANY DIRECTION TO DEFLECT")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: "FFCC00").opacity(alpha * 0.85)),
            at: CGPoint(x: frame.midX, y: frame.minY + 38)
        )
        _ = progress  // (reserved for future progress-driven effects)
    }

    private enum SwipeArrowDirection { case left, right }

    private func drawSwipeArrow(ctx: GraphicsContext, at center: CGPoint, width: CGFloat,
                                 direction: SwipeArrowDirection, color: Color) {
        // Draws a chunky 8-bit arrow: line + triangular head.
        let half = width / 2
        let tipX = direction == .right ? center.x + half : center.x - half
        let tailX = direction == .right ? center.x - half : center.x + half
        // Shaft
        var shaft = Path()
        shaft.move(to: CGPoint(x: tailX, y: center.y))
        shaft.addLine(to: CGPoint(x: tipX, y: center.y))
        ctx.stroke(shaft, with: .color(color), lineWidth: 4)
        // Head triangle
        var head = Path()
        let headSize: CGFloat = 14
        let inwardX = direction == .right ? tipX - headSize : tipX + headSize
        head.move(to: CGPoint(x: tipX, y: center.y))
        head.addLine(to: CGPoint(x: inwardX, y: center.y - headSize))
        head.addLine(to: CGPoint(x: inwardX, y: center.y + headSize))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }

    /// Code waves — expanding rings of glyphs spreading outward from the
    /// face centre. They live for `waveLifetime` seconds. After ~70% of
    /// their lifetime, an undeflected wave deals trace damage.
    private func drawCodeWaves(ctx: GraphicsContext, size: CGSize) {
        let frame = faceFrame(in: size)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let maxR = max(size.width, size.height) * 0.7
        for w in waves where !w.deflected {
            let age = elapsed - w.spawnedAt
            let progress = max(0, min(1, age / waveLifetime))
            let r = CGFloat(progress) * maxR
            // Ring with glyphs sprinkled around it
            let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
            let alpha = max(0, 1.0 - progress * 0.65)
            ctx.stroke(Path(ellipseIn: ringRect),
                       with: .color(w.color.opacity(alpha * 0.70)),
                       lineWidth: 2)
            // Inner softer ring
            ctx.stroke(Path(ellipseIn: ringRect.insetBy(dx: 4, dy: 4)),
                       with: .color(w.color.opacity(alpha * 0.30)),
                       lineWidth: 4)
            // Glyphs around the ring
            let glyphCount = 16
            for i in 0..<glyphCount {
                let theta = Double(i) * (2 * .pi / Double(glyphCount)) + age * 0.6
                let gx = center.x + CGFloat(cos(theta)) * r
                let gy = center.y + CGFloat(sin(theta)) * r
                ctx.draw(
                    Text(w.glyph).font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(w.color.opacity(alpha)),
                    at: CGPoint(x: gx, y: gy)
                )
            }
        }
        // Deflected waves: draw briefly as a "shattered" particle ring fading
        for w in waves where w.deflected {
            let age = elapsed - w.spawnedAt
            let progress = max(0, min(1, age / waveLifetime))
            let r = CGFloat(progress) * maxR
            let alpha = max(0, 1.0 - progress)
            // Particle dots scattered along ring
            for i in 0..<20 {
                let theta = Double(i) * (2 * .pi / 20)
                let jitter = CGFloat.random(in: -8...8)
                let gx = center.x + CGFloat(cos(theta)) * (r + jitter)
                let gy = center.y + CGFloat(sin(theta)) * (r + jitter)
                let dot = CGRect(x: gx - 2, y: gy - 2, width: 4, height: 4)
                ctx.fill(Path(ellipseIn: dot),
                         with: .color(Color(hex: "00FFCC").opacity(alpha)))
            }
        }
    }

    // MARK: - AGI face pixel art

    /// Returns the pattern + palette for the AGI face given its current mood.
    private static func facePattern(mood: FaceMood) -> [String] {
        switch mood {
        case .rage:
            // Glitched/cracked face — eyes bigger, mouth open, cracks
            return [
                ".......1111111.......",
                ".....1111111111111...",
                "....11111111111111...",
                "...1112222222222111..",
                "..11122334434443221..",
                "..11124444444444421..",
                "..11124444444444421..",
                "..11122334434443221..",
                "..1112222222222111...",
                "..1111111111111111...",
                "..1144441141441441...",
                "..1144441141441441...",
                "..1144441141441441...",
                "..1111111111111111...",
                "..11.135333333.11....",
                "..11.155333355.11....",
                "..11.135333333.11....",
                "..1111111111111111...",
                "....11111111111......",
                "......11111..........",
            ]
        default:
            // Neutral / hit / attacking — same base pattern, palette swap
            // 1 = hull dark, 2 = hull mid, 3 = mouth grille, 4 = eye glow,
            // 5 = highlight teeth/accent.
            return [
                ".......1111111.......",
                ".....1111111111111...",
                "....11111111111111...",
                "...1112222222222111..",
                "..11122223344322211..",
                "..11122223344322211..",
                "..11122222222222211..",
                "..1112222222222111...",
                "..1111111111111111...",
                "..114411144411144....",
                "..114411144411144....",
                "..1111111111111111...",
                "..11.122222222.11....",
                "..11.123333333.11....",
                "..11.155555555.11....",
                "..11.123333333.11....",
                "..11.122222222.11....",
                "..1111111111111111...",
                "....11111111111......",
                "......1111...........",
            ]
        }
    }

    /// Returns the palette for the AGI face given its current mood.
    /// Index 1 in the pattern → palette[0], etc.
    private static func facePalette(mood: FaceMood) -> [Color] {
        switch mood {
        case .neutral:
            return [
                Color(hex: "33161E"),    // 1 hull dark crimson
                Color(hex: "5E2630"),    // 2 hull mid
                Color(hex: "22050A"),    // 3 mouth grille
                Color(hex: "FF3344"),    // 4 eye glow red
                Color(hex: "FFAA88"),    // 5 highlight teeth
            ]
        case .hit:
            // Briefly washed out / flashed — lighter
            return [
                Color(hex: "552A33"),
                Color(hex: "884050"),
                Color(hex: "330A11"),
                Color(hex: "FFFFFF"),    // eyes flash white
                Color(hex: "FFEEDD"),
            ]
        case .attacking:
            // Pre-fire telegraph — eyes brighter
            return [
                Color(hex: "33161E"),
                Color(hex: "6E2A36"),
                Color(hex: "22050A"),
                Color(hex: "FF6688"),
                Color(hex: "FFAA88"),
            ]
        case .rage:
            return [
                Color(hex: "440010"),    // darker, deeper red
                Color(hex: "770020"),
                Color(hex: "110000"),
                Color(hex: "FF0011"),    // eyes more saturated
                Color(hex: "FFFFFF"),
            ]
        }
    }

    // MARK: - Input

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard !gameOver else { return }
        let frame = faceFrame(in: size)
        // Find nearest exploit zone
        var bestIdx: Int? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for (i, _) in exploitZones.enumerated() {
            guard i < AGIFaceoffMiniGame.faceAnchors.count else { continue }
            let anchor = AGIFaceoffMiniGame.faceAnchors[i]
            let cx = frame.minX + anchor.x * frame.width
            let cy = frame.minY + anchor.y * frame.height
            let d = hypot(point.x - cx, point.y - cy)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        // Bumped 2026-05 (was 32) — wider hit acceptance so a fingertip near
        // a reticle still lands. Matches the new 48pt zone size.
        guard let idx = bestIdx, bestDist < 44 else { return }

        switch exploitZones[idx].phase {
        case .vulnerable:
            // Land an exploit
            agiHP = max(0, agiHP - exploitDamage)
            exploitsLanded += 1
            chiptune?.sfxRingLock()
            HapticsManager.shared.attackHit()
            exploitZones[idx].phase = .cooldown
            exploitZones[idx].remaining = 0.4
            // Make AGI react
            setMood(.hit, for: 0.4)
            if agiHP <= 0 {
                chiptune?.sfxWin()
                finishGame(success: true)
            } else if agiHP < agiMaxHP * 30 / 100 {
                // Permanent rage state once below 30% HP
                setMood(.rage, for: 999)
            }
        case .warning:
            // Tapped too early — small trace penalty
            traceBar = min(1.0, traceBar + wrongTapTraceDamage)
            chiptune?.sfxRingMiss()
            exploitZones[idx].phase = .cooldown
            exploitZones[idx].remaining = 0.4
        case .dormant:
            // Dormant zones are NOT DRAWN — punishing a tap near an
            // invisible anchor read as random trace loss on empty art.
            break
        case .cooldown:
            break
        }
    }

    private func handleSwipe() {
        guard !gameOver else { return }
        // Mark all currently-active waves as deflected, but only those within
        // the deflect window (i.e. they haven't yet "arrived"). Late swipes
        // miss waves that already dealt damage.
        var deflectedAny = false
        for i in waves.indices where !waves[i].deflected && !waves[i].dealtDamage {
            let age = elapsed - waves[i].spawnedAt
            let progress = age / waveLifetime
            if progress < 0.78 {
                waves[i].deflected = true
                wavesDeflected += 1
                deflectedAny = true
            }
        }
        lastSwipeTime = elapsed
        if deflectedAny {
            chiptune?.sfxLaneSwitch()
            HapticsManager.shared.buttonTap()
        }
    }

    // MARK: - Tick

    private func startTimers() {
        let dt: TimeInterval = 1.0 / 60.0
        tickTimer = Timer.publish(every: dt, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick(dt: dt) }
        pulseTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in pulseTime += 0.05 }
        var cols: [RainColumn] = []
        for _ in 0..<14 { cols.append(makeRainColumn()) }
        codeRain = cols
        rainTimer = Timer.publish(every: 0.07, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                for i in codeRain.indices {
                    codeRain[i].headY += codeRain[i].speed
                    if codeRain[i].headY > 460 {
                        codeRain[i] = makeRainColumn(resetTop: true)
                    }
                }
            }
    }

    private func cancelTimers() {
        tickTimer?.cancel()
        waveSpawnTimer?.cancel()
        pulseTimer?.cancel()
        rainTimer?.cancel()
    }

    private func tick(dt: TimeInterval) {
        guard !gameOver else { return }
        // Briefing pauses gameplay clock entirely — player gets to read.
        if tutorialPhase == .briefing { return }
        elapsed += dt
        glitchPhase += dt * 2

        // Trace drift is much gentler during the tutorial phases (small
        // background drift only, no pressure ramp) so the player has time
        // to learn without dying.
        let pressure: CGFloat
        let driftMul: CGFloat
        switch tutorialPhase {
        case .briefing:
            pressure = 0; driftMul = 0
        case .exploitsOnly, .wavesOnly:
            pressure = 0; driftMul = 0.25
        case .full:
            pressure = 1.0 - CGFloat(agiHP) / CGFloat(agiMaxHP)
            driftMul = 1.0
        }
        traceBar += traceDrift * CGFloat(dt) * driftMul * (1.0 + pressure * 1.4)
        if traceBar >= 1.0 {
            chiptune?.sfxLose()
            finishGame(success: false)
            return
        }

        // Swipe-hint countdown
        if swipeHintRemaining > 0 {
            swipeHintRemaining = max(0, swipeHintRemaining - dt)
        }

        // Mood timeout
        if moodRemaining > 0 {
            moodRemaining -= dt
            if moodRemaining <= 0 && mood != .rage {
                mood = (agiHP < agiMaxHP * 30 / 100) ? .rage : .neutral
            }
        }

        // Exploit zone phase advancement
        for i in exploitZones.indices {
            exploitZones[i].remaining -= dt
            if exploitZones[i].remaining <= 0 {
                advanceExploitPhase(at: i)
            }
        }

        // Trigger new exploit cycles, gated by tutorial phase.
        let exploitsAllowed = tutorialPhase == .exploitsOnly || tutorialPhase == .full
        if exploitsAllowed && elapsed >= nextExploitTime {
            triggerNextExploit()
            let interval = exploitRefreshInterval * (1.0 - 0.30 * Double(pressure))
            nextExploitTime = elapsed + interval
        }

        // Spawn waves, gated by tutorial phase.
        let wavesAllowed = tutorialPhase == .wavesOnly || tutorialPhase == .full
        if wavesAllowed {
            let waveInterval = baseWaveSpawnInterval * (1.0 - 0.45 * Double(pressure))
            // In wavesOnly tutorial, waves come slower and ONE at a time so
            // the player can practice the swipe.
            let tutorialPaced = tutorialPhase == .wavesOnly
            let onlyOneAtATime = tutorialPaced && waves.contains(where: { !$0.deflected && !$0.dealtDamage })
            if !onlyOneAtATime {
                // Pace off the last SPAWN time, not waves.last — waves despawn
                // at ~2.0s, so reading the array let the interval collapse to
                // ~2.0s and the tuned 2.6s base (+ ramp) never applied.
                if lastWaveSpawnedAt < 0 {
                    if elapsed >= 1.0 { spawnWave() }
                } else if elapsed - lastWaveSpawnedAt >= waveInterval {
                    spawnWave()
                }
            }
        }

        // Apply wave damage when waves complete their lifetime undeflected
        for i in waves.indices where !waves[i].deflected && !waves[i].dealtDamage {
            let age = elapsed - waves[i].spawnedAt
            if age >= waveLifetime * 0.95 {
                waves[i].dealtDamage = true
                traceBar = min(1.0, traceBar + waveTraceDamage)
                chiptune?.sfxHit()
                HapticsManager.shared.playerKilled()
                setMood(.attacking, for: 0.3)
            }
        }
        // Despawn old waves
        waves.removeAll { elapsed - $0.spawnedAt > waveLifetime + 0.4 }

        // Tutorial advancement
        advanceTutorialIfReady()
    }

    /// Move tutorialPhase forward once the player has demonstrated each input.
    private func advanceTutorialIfReady() {
        switch tutorialPhase {
        case .exploitsOnly:
            // Once player lands 2 exploits, advance to waves tutorial.
            if exploitsLanded >= 2 {
                tutorialPhase = .wavesOnly
                tutorialStepCompleted = wavesDeflected   // baseline for next phase
            }
        case .wavesOnly:
            // Once player deflects 2 waves, advance to full game.
            if wavesDeflected - tutorialStepCompleted >= 2 {
                tutorialPhase = .full
                // Reset wave + exploit pacing so the real fight starts fresh
                nextExploitTime = elapsed + 0.6
            }
        default:
            break
        }
    }

    private func advanceExploitPhase(at i: Int) {
        switch exploitZones[i].phase {
        case .dormant:
            // Will be started by triggerNextExploit
            break
        case .warning:
            exploitZones[i].phase = .vulnerable
            exploitZones[i].remaining = vulnerableDuration
        case .vulnerable:
            // Window expired without a tap — small trace penalty
            traceBar = min(1.0, traceBar + 0.04)
            exploitZones[i].phase = .cooldown
            exploitZones[i].remaining = 0.6
        case .cooldown:
            exploitZones[i].phase = .dormant
            exploitZones[i].remaining = 0
        }
    }

    private func triggerNextExploit() {
        // Pick a random dormant zone
        let candidates = exploitZones.indices.filter { exploitZones[$0].phase == .dormant }
        guard let idx = candidates.randomElement() else { return }
        exploitZones[idx].phase = .warning
        exploitZones[idx].remaining = warningDuration
    }

    private func spawnWave() {
        let glyph = AGIFaceoffMiniGame.rainPool.randomElement() ?? "1"
        let palette: [Color] = [Color(hex: "FF3344"), Color(hex: "FF8833"), Color(hex: "FF00AA")]
        let color = palette.randomElement() ?? Color(hex: "FF3344")
        waves.append(CodeWave(spawnedAt: elapsed, glyph: glyph, color: color))
        lastWaveSpawnedAt = elapsed
        wavesSpawned += 1
        chiptune?.sfxICEAlert()
        setMood(.attacking, for: 0.25)
        // Show the big "SWIPE!" prompt for the first half of the wave's
        // lifetime — drives home the action the first few times. Stops
        // showing once the player has deflected 4+ waves (they get it).
        if wavesDeflected < 4 {
            swipeHintRemaining = waveLifetime * 0.6
        }
    }

    private func setMood(_ m: FaceMood, for seconds: Double) {
        mood = m
        moodRemaining = seconds
    }

    // MARK: - Lifecycle

    private func initialise() {
        agiHP = agiMaxHP
        traceBar = 0
        elapsed = 0
        glitchPhase = 0
        exploitZones = AGIFaceoffMiniGame.faceAnchors.indices.map {
            ExploitZone(id: $0, phase: .dormant, remaining: 0)
        }
        waves = []
        gameOver = false
        didWin = false
        mood = .neutral
        moodRemaining = 0
        exploitsLanded = 0
        wavesDeflected = 0
        wavesSpawned = 0
        // Stagger the first exploit trigger so the player has a moment.
        nextExploitTime = 0.8
    }

    private func startAudio() {
        let player = ChiptunePlayer()
        player?.startMelody()
        chiptune = player
    }

    private func finishGame(success: Bool) {
        guard !gameOver else { return }
        gameOver = true
        didWin = success
        // Score = (exploits × 60) + (deflects × 25) + 200 win bonus -
        // (5 × elapsed). Boss fight has more individual actions so the
        // ceiling sits comfortably above 1000 for a clean run.
        if success, let id = gameState.currentMissionDisplayId {
            let score = max(0, exploitsLanded * 60 + wavesDeflected * 25 + 200 - Int(elapsed * 5))
            MissionStatsStore.shared.recordMiniGameScore(missionId: id, score: score)
        }
        cancelTimers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            chiptune?.stop()
            chiptune = nil
            onComplete(success)
        }
    }

    private func makeRainColumn(resetTop: Bool = false) -> RainColumn {
        let pool = AGIFaceoffMiniGame.rainPool
        let len = Int.random(in: 6...12)
        var glyphs: [String] = []
        for _ in 0..<len { glyphs.append(pool.randomElement() ?? "0") }
        return RainColumn(
            x: CGFloat.random(in: 8...380),
            headY: resetTop ? CGFloat.random(in: -120 ... -10) : CGFloat.random(in: -80...460),
            glyphs: glyphs,
            speed: CGFloat.random(in: 1.2...3.2)
        )
    }
}
