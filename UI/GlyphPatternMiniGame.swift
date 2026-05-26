import SwiftUI
import Combine

/// GLYPH PATTERN — Mission 3's data-extraction mini-game.
///
/// Premise: the blood mage's lair is sealed by a magical ward. Six arcane
/// glyphs are arranged around a hex ring. The ward shows you a sequence of
/// glyphs flashing in order — you have to tap them back in the same order to
/// crack the ward.
///
/// Mechanics: classic Simon Says. Round 1 plays a 3-glyph sequence; each
/// subsequent round adds one more glyph (4, 5, 6, 7, 8). Reach round 5 (a
/// full 7-glyph chain) to break the ward.
///
/// Inputs: tap a glyph — that's it. No swipes, no drag.
struct GlyphPatternMiniGame: View {
    @ObservedObject var gameState: GameState
    let onComplete: (Bool) -> Void

    // MARK: - Tuning

    private let totalRounds = 5
    private let startingSequenceLength = 3
    private let maxMistakes = 3
    /// Seconds each glyph stays lit during PLAYBACK.
    private let playbackFlashDuration: Double = 0.55
    /// Seconds between consecutive playback flashes.
    private let playbackInterval: Double = 0.15
    /// After tapping correctly, flash the glyph green this long.
    private let correctFlashDuration: Double = 0.20
    /// After tapping wrong, flash red this long, then replay current sequence.
    private let wrongFlashDuration: Double = 0.40

    // MARK: - State

    /// Six glyphs around a hex ring. Each is a unique magical symbol.
    private static let glyphs: [String] = ["Σ", "Φ", "Ω", "Δ", "λ", "π"]
    private static let glyphColors: [Color] = [
        Color(hex: "FF4488"),   // Σ pink
        Color(hex: "44CCFF"),   // Φ cyan
        Color(hex: "FFCC44"),   // Ω yellow
        Color(hex: "AA66FF"),   // Δ purple
        Color(hex: "44FF88"),   // λ green
        Color(hex: "FF8844"),   // π orange
    ]

    enum Phase {
        case briefing
        case playback        // showing the sequence to memorise
        case awaitingInput   // player's turn to tap
        case roundComplete   // brief celebration before next round
        case finished        // win or lose
    }

    @State private var showBriefing: Bool = true
    @State private var phase: Phase = .briefing
    @State private var currentRound: Int = 1
    @State private var sequence: [Int] = []      // glyph indices in order
    @State private var playerIndex: Int = 0      // how far into sequence the player has tapped
    @State private var mistakes: Int = 0
    @State private var litGlyph: Int? = nil      // which glyph is currently flashing
    @State private var flashColor: Color? = nil  // override color while flashing
    @State private var playbackStep: Int = 0     // next index to flash during playback
    @State private var didWin: Bool = false
    @State private var elapsed: Double = 0

    @State private var pulseTimer: AnyCancellable?
    @State private var pulseTime: Double = 0
    @State private var rainTimer: AnyCancellable?
    @State private var codeRain: [RainColumn] = []
    @State private var elapsedTimer: AnyCancellable?
    @State private var chiptune: ChiptunePlayer? = nil

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

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "01040A"), Color(hex: "02060E"), Color(hex: "01040A")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                wardArea
                hud
                touchHint
            }
            .padding(.bottom, 28)

            if showBriefing {
                MiniGameBriefing(
                    title: "WARD GLYPH",
                    subtitle: "MEMORY-PATTERN PROTOCOL",
                    accent: Color(hex: "AA66FF"),
                    rules: [
                        BriefingRule(
                            iconName: "eye.fill",
                            color: Color(hex: "44CCFF"),
                            title: "WATCH THE SEQUENCE",
                            detail: "Glyphs around the hex ring flash one at a time. Memorise the order they light up in."
                        ),
                        BriefingRule(
                            iconName: "hand.point.up.fill",
                            color: Color(hex: "44FF88"),
                            title: "TAP THEM BACK IN ORDER",
                            detail: "When the playback ends, tap the glyphs in the same sequence. Each correct tap flashes green."
                        ),
                        BriefingRule(
                            iconName: "exclamationmark.triangle.fill",
                            color: Color(hex: "FF3344"),
                            title: "5 ROUNDS, 3 STRIKES",
                            detail: "Sequence grows by one each round. Three wrong taps total = ward holds, run fails."
                        ),
                    ],
                    onStart: {
                        showBriefing = false
                        startRound(1)
                    }
                )
                .zIndex(1000)
            }

            if phase == .finished {
                Color.black.opacity(0.78).ignoresSafeArea()
                VStack(spacing: 6) {
                    Text(didWin ? "WARD CRACKED" : "WARD HELD")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(didWin ? Color(hex: "44FF88") : Color(hex: "FF3344"))
                    Text(didWin ? "// DATA EXTRACTED" : "// LOCKED OUT")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.8))
                .overlay(
                    Rectangle().stroke(didWin ? Color(hex: "44FF88") : Color(hex: "FF3344"), lineWidth: 1.5)
                )
            }
        }
        .onAppear {
            startTimers()
            startAudio()
            startCodeRain()
        }
        .onDisappear {
            cancelTimers()
            chiptune?.stop()
            chiptune = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "AA66FF"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6))
                Text("// WARD GLYPH")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "AA66FF"))
                Circle().fill(Color(hex: "44FF88"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6 + .pi))
            }
            Text(phaseLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var phaseLabel: String {
        switch phase {
        case .briefing:       return "READY?"
        case .playback:       return "WATCH THE WARD"
        case .awaitingInput:  return "REPEAT THE SEQUENCE — TAP IN ORDER"
        case .roundComplete:  return "ROUND CLEAR"
        case .finished:       return didWin ? "WARD CRACKED" : "LOCKED OUT"
        }
    }

    // MARK: - Ward area (the glyph ring)

    private var wardArea: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color(hex: "08020A"))
                    .overlay(Rectangle().stroke(Color(hex: "AA66FF").opacity(0.30), lineWidth: 1))
                    .overlay(Rectangle().stroke(Color(hex: "44FF88").opacity(0.10), lineWidth: 3))

                Canvas { ctx, size in
                    drawCodeRain(ctx: ctx, size: size)
                    drawScanlines(ctx: ctx, size: size)
                    drawGlyphRing(ctx: ctx, size: size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .padding(.horizontal, 8)
    }

    // MARK: - HUD

    private var hud: some View {
        HStack(spacing: 10) {
            statusBlock(label: "ROUND",
                        value: "\(currentRound) / \(totalRounds)",
                        color: Color(hex: "44FF88"))
            statusBlock(label: "STRIKES",
                        value: "\(mistakes) / \(maxMistakes)",
                        color: Color(hex: "FF3344"))
            statusBlock(label: "TIME",
                        value: String(format: "%.1fs", elapsed),
                        color: Color(hex: "AA66FF"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var touchHint: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WATCH · REPEAT")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                Text("Memorise the flash order, then tap glyphs in sequence.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "AA66FF").opacity(0.85))
            }
            Spacer()
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

    /// Centre of the glyph ring within the ward area.
    private func ringCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Radius of the glyph ring.
    private func ringRadius(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.32
    }

    /// Position of glyph index `i` (0..5) on the ring.
    private func glyphPosition(_ i: Int, in size: CGSize) -> CGPoint {
        let cnt = ringCenter(in: size)
        let r = ringRadius(in: size)
        // Hex ring — 6 positions evenly spaced, starting at top (-π/2).
        let theta = -.pi/2 + Double(i) * (2 * .pi / 6)
        return CGPoint(x: cnt.x + CGFloat(cos(theta)) * r,
                       y: cnt.y + CGFloat(sin(theta)) * r)
    }

    private func drawCodeRain(ctx: GraphicsContext, size: CGSize) {
        for col in codeRain {
            for (i, g) in col.glyphs.enumerated() {
                let y = col.headY - CGFloat(i) * 14
                guard y >= -14, y <= size.height + 14 else { continue }
                let alpha = max(0, 1.0 - Double(i) * 0.08)
                let color = i == 0
                    ? Color.white.opacity(alpha * 0.6)
                    : Color(hex: "AA66FF").opacity(alpha * 0.30)
                ctx.draw(
                    Text(g).font(.system(size: 11, weight: .regular, design: .monospaced))
                          .foregroundColor(color),
                    at: CGPoint(x: col.x, y: y)
                )
            }
        }
    }

    private func drawScanlines(ctx: GraphicsContext, size: CGSize) {
        let alpha = 0.04 + sin(pulseTime * 2.5) * 0.02
        var y: CGFloat = 0
        while y < size.height {
            ctx.fill(
                Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                with: .color(Color(hex: "AA66FF").opacity(alpha))
            )
            y += 3
        }
    }

    private func drawGlyphRing(ctx: GraphicsContext, size: CGSize) {
        let cnt = ringCenter(in: size)
        let r = ringRadius(in: size)

        // Background hex ring outline
        let hex = UIBezierPath()
        for i in 0..<6 {
            let theta = -.pi/2 + Double(i) * (2 * .pi / 6)
            let p = CGPoint(x: cnt.x + CGFloat(cos(theta)) * r,
                            y: cnt.y + CGFloat(sin(theta)) * r)
            if i == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
        }
        hex.close()
        ctx.stroke(Path(hex.cgPath),
                   with: .color(Color(hex: "AA66FF").opacity(0.30)),
                   lineWidth: 1)

        // Centre "WARD" pulse
        let pulse = 1.0 + 0.18 * sin(pulseTime * 4)
        let centerR: CGFloat = 26 * pulse
        let centerHalo = CGRect(x: cnt.x - centerR - 6, y: cnt.y - centerR - 6,
                                width: (centerR + 6) * 2, height: (centerR + 6) * 2)
        ctx.fill(Path(ellipseIn: centerHalo),
                 with: .color(Color(hex: "AA66FF").opacity(0.18)))
        let centerRect = CGRect(x: cnt.x - 22, y: cnt.y - 22, width: 44, height: 44)
        ctx.fill(Path(ellipseIn: centerRect),
                 with: .color(Color(hex: "AA66FF").opacity(0.55)))
        ctx.stroke(Path(ellipseIn: centerRect), with: .color(.white), lineWidth: 1.5)
        ctx.draw(
            Text("WARD")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white),
            at: cnt
        )

        // Six glyphs around the ring
        let glyphRadius: CGFloat = 36
        for i in 0..<GlyphPatternMiniGame.glyphs.count {
            let pos = glyphPosition(i, in: size)
            let glyph = GlyphPatternMiniGame.glyphs[i]
            let baseColor = GlyphPatternMiniGame.glyphColors[i]
            let isLit = (litGlyph == i)

            // Halo (always shown faintly; brighter when lit)
            let haloR = glyphRadius + (isLit ? 14 : 4)
            let haloRect = CGRect(x: pos.x - haloR, y: pos.y - haloR,
                                  width: haloR * 2, height: haloR * 2)
            ctx.fill(Path(ellipseIn: haloRect),
                     with: .color(baseColor.opacity(isLit ? 0.40 : 0.10)))

            // Body
            let bodyRect = CGRect(x: pos.x - glyphRadius, y: pos.y - glyphRadius,
                                  width: glyphRadius * 2, height: glyphRadius * 2)
            let fillColor: Color = {
                if isLit, let f = flashColor { return f }
                if isLit { return baseColor }
                return baseColor.opacity(0.20)
            }()
            ctx.fill(Path(ellipseIn: bodyRect), with: .color(fillColor))
            ctx.stroke(Path(ellipseIn: bodyRect),
                       with: .color(isLit ? .white : baseColor.opacity(0.65)),
                       lineWidth: isLit ? 2.5 : 1.4)

            // Glyph character
            let glyphFontSize: CGFloat = isLit ? 28 : 22
            let glyphColor: Color = isLit ? .white : baseColor
            ctx.draw(
                Text(glyph)
                    .font(.system(size: glyphFontSize, weight: .black, design: .monospaced))
                    .foregroundColor(glyphColor),
                at: pos
            )
        }

        // Progress dots — show how many glyphs the player has tapped this round
        if phase == .awaitingInput {
            let totalDots = sequence.count
            let dotSpacing: CGFloat = 14
            let totalWidth = CGFloat(totalDots - 1) * dotSpacing
            let startX = cnt.x - totalWidth / 2
            let dotsY = cnt.y + r + 36
            for i in 0..<totalDots {
                let isDone = i < playerIndex
                let dot = CGRect(x: startX + CGFloat(i) * dotSpacing - 4,
                                 y: dotsY - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: dot),
                         with: .color(isDone
                                      ? Color(hex: "44FF88")
                                      : Color.white.opacity(0.25)))
            }
        }
    }

    // MARK: - Input

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard phase == .awaitingInput else { return }
        // Find nearest glyph within hit radius
        var bestIdx: Int? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for i in 0..<GlyphPatternMiniGame.glyphs.count {
            let pos = glyphPosition(i, in: size)
            let d = hypot(point.x - pos.x, point.y - pos.y)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        // 50pt hit radius — generous, matches the 36pt glyph + 14pt halo.
        guard let idx = bestIdx, bestDist < 50 else { return }

        let expected = sequence[playerIndex]
        if idx == expected {
            // Correct! Flash green briefly.
            chiptune?.sfxNodeHop()
            HapticsManager.shared.buttonTap()
            flashGlyph(idx, color: Color(hex: "44FF88"), duration: correctFlashDuration)
            playerIndex += 1
            if playerIndex >= sequence.count {
                roundCleared()
            }
        } else {
            // Wrong glyph — flash red, increment mistakes, replay sequence.
            chiptune?.sfxRingMiss()
            HapticsManager.shared.playerKilled()
            flashGlyph(idx, color: Color(hex: "FF3344"), duration: wrongFlashDuration)
            mistakes += 1
            if mistakes >= maxMistakes {
                phase = .finished
                didWin = false
                chiptune?.sfxLose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    finishGame(success: false)
                }
                return
            }
            // Replay the same sequence after the red flash settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + wrongFlashDuration + 0.2) {
                playerIndex = 0
                playSequence()
            }
        }
    }

    // MARK: - Round flow

    private func startRound(_ round: Int) {
        currentRound = round
        let length = startingSequenceLength + (round - 1)
        // Generate a random sequence of the required length.
        var newSeq: [Int] = []
        for _ in 0..<length {
            newSeq.append(Int.random(in: 0..<GlyphPatternMiniGame.glyphs.count))
        }
        sequence = newSeq
        playerIndex = 0
        playSequence()
    }

    private func playSequence() {
        phase = .playback
        playbackStep = 0
        flashColor = nil
        playNextStep()
    }

    private func playNextStep() {
        guard phase == .playback else { return }
        if playbackStep >= sequence.count {
            // Playback done — switch to input.
            phase = .awaitingInput
            litGlyph = nil
            return
        }
        let idx = sequence[playbackStep]
        flashGlyph(idx, color: GlyphPatternMiniGame.glyphColors[idx], duration: playbackFlashDuration)
        playbackStep += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + playbackFlashDuration + playbackInterval) {
            playNextStep()
        }
    }

    /// Briefly light up a glyph with the given color, then return to dim.
    private func flashGlyph(_ idx: Int, color: Color, duration: TimeInterval) {
        litGlyph = idx
        flashColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            // Only clear if we haven't moved on to a different glyph already.
            if litGlyph == idx {
                litGlyph = nil
                flashColor = nil
            }
        }
    }

    private func roundCleared() {
        phase = .roundComplete
        chiptune?.sfxRingLock()
        if currentRound >= totalRounds {
            // Final round won — full success.
            didWin = true
            phase = .finished
            chiptune?.sfxWin()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                finishGame(success: true)
            }
            return
        }
        // Brief celebration, then next round.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            startRound(currentRound + 1)
        }
    }

    // MARK: - Lifecycle

    private func startTimers() {
        pulseTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in pulseTime += 0.05 }
        elapsedTimer = Timer.publish(every: 0.10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard !showBriefing, phase != .finished else { return }
                elapsed += 0.10
            }
    }

    private func cancelTimers() {
        pulseTimer?.cancel()
        elapsedTimer?.cancel()
        rainTimer?.cancel()
    }

    private func startCodeRain() {
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

    private func makeRainColumn(resetTop: Bool = false) -> RainColumn {
        let pool = GlyphPatternMiniGame.rainPool
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

    private func startAudio() {
        let player = ChiptunePlayer()
        player?.startMelody()
        chiptune = player
    }

    private func finishGame(success: Bool) {
        // Score = 200 per round cleared + 100 per unused mistake + 200 win
        // bonus - 5 per second elapsed. Flawless ~30s win nets ~1450; a
        // sloppy 90s clear with 2 strikes nets ~750.
        if success, let id = gameState.currentMissionDisplayId {
            let roundsCleared = currentRound       // last round at win = totalRounds
            let strikesLeft = max(0, maxMistakes - mistakes)
            let score = roundsCleared * 200 + strikesLeft * 100 + 200 - Int(elapsed * 5)
            MissionStatsStore.shared.recordMiniGameScore(missionId: id, score: max(0, score))
        }
        cancelTimers()
        chiptune?.stop()
        chiptune = nil
        onComplete(success)
    }
}
