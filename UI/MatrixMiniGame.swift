import SwiftUI
import Combine

/// Matrix-style maze run, 3 stages.
///
/// Theme: when a runner jacks a data terminal, this fires up. The runner's
/// avatar is a chunky pixel-art sprite; you slide a finger across the maze
/// and the runner steps along the corridors toward your touch. ICE programs
/// stalk through the corridors as their own pixel-art sprites — Trace.exe,
/// ICE Daemon, Watchdog — each with a distinct silhouette and palette.
///
/// Reach the central data core in each stage to advance. Three stages total,
/// progressively denser mazes and faster ICE. Tuned to be challenging but
/// fair on a 3" iPhone screen with finger-drag input.
///
/// Audio: full multi-voice 8-bit chiptune (lead + bass + kick drum) +
/// square-wave SFX, all generated at runtime by `ChiptunePlayer`.
struct MatrixMiniGameView: View {
    @ObservedObject var gameState: GameState
    let onComplete: (Bool) -> Void

    // MARK: - Stage definitions

    /// Stage layout: 13×13 grid. 0 = corridor, 1 = wall, 3 = data core.
    /// Designs: Stage 1 is open, Stage 2 has chambers + diagonals, Stage 3 is
    /// dense. Each stage has its core in the centre or near it.
    private static let stageMaps: [[[Int]]] = [
        // Stage 1 — Loading bay. Lots of open paths, beginner-friendly.
        [
            [1,1,1,1,1,1,1,1,1,1,1,1,1],
            [1,0,0,0,0,0,1,0,0,0,0,0,1],
            [1,0,1,1,0,1,1,1,0,1,1,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,1,0,1,0,1,0,1,0,1,0,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,1,1,0,0,0,3,0,0,0,1,1,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,0,1,0,1,0,1,0,1,0,1,0,1],
            [1,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,0,1,1,0,1,1,1,0,1,1,0,1],
            // Col 6 opened: the runner spawns at (6,11) and this row used to
            // wall that cell — player started INSIDE a block (unreachable by
            // chasers). Stages 2/3 already have (6,11) open.
            [1,0,0,0,0,0,0,0,0,0,0,0,1],
            [1,1,1,1,1,1,1,1,1,1,1,1,1],
        ],
        // Stage 2 — Server stacks. Medium density, tighter corridors.
        [
            [1,1,1,1,1,1,1,1,1,1,1,1,1],
            [1,0,1,0,0,0,0,0,0,0,1,0,1],
            [1,0,1,0,1,1,1,1,1,0,1,0,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,1,1,0,1,0,1,0,1,0,1,1,1],
            [1,0,0,0,0,0,1,0,0,0,0,0,1],
            [1,0,1,1,1,0,3,0,1,1,1,0,1],
            [1,0,0,0,0,0,1,0,0,0,0,0,1],
            [1,1,1,0,1,0,1,0,1,0,1,1,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,0,1,0,1,1,1,1,1,0,1,0,1],
            [1,0,1,0,0,0,0,0,0,0,1,0,1],
            [1,1,1,1,1,1,1,1,1,1,1,1,1],
        ],
        // Stage 3 — Core vault. Dense branches, multiple loop paths.
        [
            [1,1,1,1,1,1,1,1,1,1,1,1,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,0,1,0,1,0,1,0,1,0,1,0,1],
            [1,0,1,0,0,0,1,0,0,0,1,0,1],
            [1,0,1,1,1,0,1,0,1,1,1,0,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,1,1,0,1,0,3,0,1,0,1,1,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,0,1,1,1,0,1,0,1,1,1,0,1],
            [1,0,1,0,0,0,1,0,0,0,1,0,1],
            [1,0,1,0,1,0,1,0,1,0,1,0,1],
            [1,0,0,0,1,0,0,0,1,0,0,0,1],
            [1,1,1,1,1,1,1,1,1,1,1,1,1],
        ],
    ]

    /// Per-stage tuning.
    private struct StageConfig {
        let chasers: [ChaserKind]
        let chaserTickSeconds: Double
        let title: String
        /// Data shards that must be collected before the core unlocks. 0 = the
        /// core is open immediately (a gentle intro zone). Higher zones force
        /// you to traverse the whole maze under chase pressure instead of
        /// beelining the core.
        let shardCount: Int
    }
    private static let stageConfigs: [StageConfig] = [
        StageConfig(
            chasers: [.trace, .watchdog],
            chaserTickSeconds: 0.60,
            title: "ZONE 1 — LOADING BAY",
            shardCount: 0
        ),
        StageConfig(
            chasers: [.trace, .daemon, .watchdog],
            chaserTickSeconds: 0.46,
            title: "ZONE 2 — SERVER STACKS",
            shardCount: 2
        ),
        StageConfig(
            chasers: [.trace, .trace, .daemon, .watchdog],
            chaserTickSeconds: 0.40,
            title: "ZONE 3 — CORE VAULT",
            shardCount: 3
        ),
    ]

    // MARK: - Chaser types

    enum ChaserKind {
        case trace      // Red — angular triangle/diamond, fast turning
        case daemon     // Orange — skull silhouette, mid speed
        case watchdog   // Purple — quadruped, mid speed
        var color: Color {
            switch self {
            case .trace:    return Color(hex: "FF3344")
            case .daemon:   return Color(hex: "FF9933")
            case .watchdog: return Color(hex: "AA66FF")
            }
        }
        var label: String {
            switch self {
            case .trace:    return "TRACE.EXE"
            case .daemon:   return "ICE DAEMON"
            case .watchdog: return "WATCHDOG"
            }
        }
    }

    struct CodeChaser: Identifiable {
        let id = UUID()
        var x: Int
        var y: Int
        var kind: ChaserKind
        /// 0 / 1 — animation frame for 2-frame chaser cycles.
        var animFrame: Int = 0
    }

    /// Decorative falling-glyph column in the maze backdrop.
    struct CodeRainColumn: Identifiable {
        let id = UUID()
        var x: CGFloat
        var headY: CGFloat
        var glyphs: [String]
        var speed: CGFloat
    }

    // MARK: - State

    @State private var stageIndex: Int = 0
    @State private var grid: [[Int]] = MatrixMiniGameView.stageMaps[0]
    /// Data shards (grid value 4) left to collect before the core unlocks.
    @State private var shardsRemaining: Int = 0
    /// Brief "collect the shards first" hint shown if you touch a locked core.
    @State private var shardHintUntil: Double = 0
    @State private var playerX: Int = 6
    @State private var playerY: Int = 11
    /// 0 = legs apart, 1 = legs together — toggled on each step.
    @State private var playerWalkFrame: Int = 0
    @State private var playerFacing: Int = 0    // 0 right, 1 left

    @State private var chasers: [CodeChaser] = []
    @State private var trail: [(x: Int, y: Int)] = []

    @State private var gameOver: Bool = false
    @State private var didWin: Bool = false
    @State private var inStageTransition: Bool = false
    @State private var transitionMessage: String = ""

    @State private var chaserTimer: AnyCancellable?
    @State private var pulseTimer: AnyCancellable?
    @State private var rainTimer: AnyCancellable?
    @State private var glitchTimer: AnyCancellable?
    @State private var pulseTime: Double = 0
    @State private var glitchPhase: Double = 0
    @State private var codeRain: [CodeRainColumn] = []
    @State private var lastDragCell: (x: Int, y: Int)? = nil
    @State private var chiptune: ChiptunePlayer? = nil

    private let cellSize: CGFloat = 24
    private let mazeWidth = 13
    private let mazeHeight = 13

    /// Glyph pool for the falling code rain.
    private static let glyphPool: [String] = [
        "0", "1", "0", "1", "0", "1",
        "F", "7", "A", "C", "E", "9",
        "0xF", "0x7", "0xA", "B3", "FF", "C0", "DE",
    ]

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
                mazeArea
                hud
                touchHint
            }
            .padding(.bottom, 28)

            // Stage-transition flash overlay
            if inStageTransition {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                VStack(spacing: 6) {
                    Text(transitionMessage)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color(hex: "00FFCC"))
                    Text("// LOADING NEXT NODE …")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.7))
                .overlay(Rectangle().stroke(Color(hex: "00FFCC"), lineWidth: 1.5))
            }

            // Locked-core hint — flashes when you touch the core with shards
            // still outstanding.
            if shardHintUntil > pulseTime {
                VStack {
                    Spacer()
                    Text("◆ COLLECT ALL DATA SHARDS FIRST")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(hex: "FFC83C"))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.black.opacity(0.8))
                        .overlay(Rectangle().stroke(Color(hex: "FFC83C").opacity(0.7), lineWidth: 1))
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            initialise()
            startChasers()
            startPulse()
            startCodeRain()
            startGlitchPulse()
            startAudio()
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
                Circle()
                    .fill(Color(hex: "00FFCC"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6))
                Text("// MATRIX INTRUSION")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "00FFCC"))
                Circle()
                    .fill(Color(hex: "FF00AA"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6 + .pi))
            }
            Text(MatrixMiniGameView.stageConfigs[stageIndex].title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    // MARK: - Maze area

    private var mazeArea: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color(hex: "020812"))
                    .overlay(Rectangle().stroke(Color(hex: "00FFCC").opacity(0.30), lineWidth: 1))
                    .overlay(Rectangle().stroke(Color(hex: "FF00AA").opacity(0.10), lineWidth: 3))

                Canvas { ctx, size in
                    drawCodeRain(ctx: ctx, size: size)

                    let mazePxW = CGFloat(mazeWidth) * cellSize
                    let mazePxH = CGFloat(mazeHeight) * cellSize
                    let xOffset = (size.width - mazePxW) / 2
                    let yOffset = (size.height - mazePxH) / 2

                    drawScanlines(ctx: ctx, rect: CGRect(x: xOffset, y: yOffset, width: mazePxW, height: mazePxH))
                    drawMazeCells(ctx: ctx, xOffset: xOffset, yOffset: yOffset)
                    drawTrail(ctx: ctx, xOffset: xOffset, yOffset: yOffset)
                    drawPlayer(ctx: ctx, xOffset: xOffset, yOffset: yOffset)
                    drawChasers(ctx: ctx, xOffset: xOffset, yOffset: yOffset)
                }

                if gameOver {
                    Color.black.opacity(0.78)
                    VStack(spacing: 6) {
                        Text(didWin ? "RUN COMPLETE" : "TRACE CAUGHT YOU")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(didWin ? Color(hex: "00FFCC") : Color(hex: "FF3344"))
                        Text(didWin ? "// PAYLOAD UPLOADED — JACK OUT" : "// CONNECTION LOST")
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location, in: geo.size)
                    }
                    .onEnded { _ in
                        lastDragCell = nil
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(mazeHeight) * cellSize + 40)
        .padding(.horizontal, 8)
    }

    // MARK: - Touch hint + bail row

    private var touchHint: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FINGER DRAG")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                Text(shardsRemaining > 0
                     ? "Grab all data shards (◆), then reach the core."
                     : "Slide your runner toward the data core.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "00FFCC").opacity(0.85))
            }
            Spacer()
            Button(action: {
                HapticsManager.shared.buttonTap()
                chiptune?.sfxBail()
                finishGame(success: false)
            }) {
                Text("BAIL")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FF3344"))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(Color.black.opacity(0.65))
                            .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.7), lineWidth: 1))
                    )
            }
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    // MARK: - HUD

    private var hud: some View {
        HStack(spacing: 12) {
            statusBlock(label: "ZONE",
                        value: "\(stageIndex + 1) / \(MatrixMiniGameView.stageMaps.count)",
                        color: Color(hex: "FFCC00"))
            statusBlock(label: shardsRemaining > 0 ? "SHARDS" : "DISTANCE",
                        value: shardsRemaining > 0 ? "\(shardsRemaining) LEFT" : "\(distanceToCore())",
                        color: shardsRemaining > 0 ? Color(hex: "FFC83C") : Color(hex: "00FFCC"))
            statusBlock(label: "TRACE",
                        value: "\(chasers.count)",
                        color: Color(hex: "FF3344"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func statusBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
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

    // MARK: - Canvas drawing helpers

    private func drawCodeRain(ctx: GraphicsContext, size: CGSize) {
        for col in codeRain {
            for (i, g) in col.glyphs.enumerated() {
                let y = col.headY - CGFloat(i) * 14
                guard y >= -14, y <= size.height + 14 else { continue }
                let alpha = max(0, 1.0 - Double(i) * 0.08)
                let color = i == 0
                    ? Color.white.opacity(alpha)
                    : Color(hex: "00FF88").opacity(alpha * 0.55)
                let txt = Text(g)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(color)
                ctx.draw(txt, at: CGPoint(x: col.x, y: y))
            }
        }
    }

    private func drawScanlines(ctx: GraphicsContext, rect: CGRect) {
        let baseAlpha = 0.04
        let ripple = sin(pulseTime * 2.5) * 0.02
        let alpha = baseAlpha + ripple
        var y = rect.minY
        while y < rect.maxY {
            let line = CGRect(x: rect.minX, y: y, width: rect.width, height: 1)
            ctx.fill(Path(line), with: .color(Color(hex: "00FFCC").opacity(alpha)))
            y += 3
        }
    }

    private func drawMazeCells(ctx: GraphicsContext, xOffset: CGFloat, yOffset: CGFloat) {
        for y in 0..<mazeHeight {
            for x in 0..<mazeWidth {
                let rect = CGRect(
                    x: xOffset + CGFloat(x) * cellSize,
                    y: yOffset + CGFloat(y) * cellSize,
                    width: cellSize,
                    height: cellSize
                )
                let v = grid[y][x]
                if v == 1 {
                    drawWall(ctx: ctx, rect: rect)
                } else if v == 3 {
                    drawDataCore(ctx: ctx, rect: rect, locked: shardsRemaining > 0)
                } else if v == 4 {
                    drawShard(ctx: ctx, rect: rect)
                } else {
                    drawCorridor(ctx: ctx, rect: rect)
                }
            }
        }
    }

    private func drawCorridor(ctx: GraphicsContext, rect: CGRect) {
        let dot = CGRect(x: rect.midX - 0.6, y: rect.midY - 0.6, width: 1.2, height: 1.2)
        ctx.fill(Path(ellipseIn: dot), with: .color(Color(hex: "00FFCC").opacity(0.15)))
    }

    private func drawWall(ctx: GraphicsContext, rect: CGRect) {
        ctx.fill(Path(rect), with: .color(Color(hex: "061826")))
        ctx.stroke(
            Path(rect.insetBy(dx: -2, dy: -2)),
            with: .color(Color(hex: "00FFCC").opacity(0.10)),
            lineWidth: 3
        )
        ctx.stroke(
            Path(rect.insetBy(dx: 0.5, dy: 0.5)),
            with: .color(Color(hex: "00FFCC").opacity(0.65)),
            lineWidth: 1
        )
        ctx.stroke(
            Path(rect.insetBy(dx: 4, dy: 4)),
            with: .color(Color(hex: "FF00AA").opacity(0.15)),
            lineWidth: 0.5
        )
    }

    private func drawDataCore(ctx: GraphicsContext, rect: CGRect, locked: Bool = false) {
        // Locked (shards outstanding) → dim grey + "LOCKED"; unlocked → the
        // live magenta data core pulsing brightly.
        let coreHex = locked ? "5A6070" : "FF00AA"
        let pulse = locked ? 1.0 : 1.0 + 0.20 * sin(pulseTime * 4)
        let coreSize = cellSize * 0.78 * pulse
        let core = CGRect(
            x: rect.midX - coreSize / 2,
            y: rect.midY - coreSize / 2,
            width: coreSize,
            height: coreSize
        )
        if !locked {
            for mult in [(8.0, 0.18), (16.0, 0.10), (24.0, 0.05)] {
                let halo = core.insetBy(dx: -CGFloat(mult.0), dy: -CGFloat(mult.0))
                ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "FF00AA").opacity(mult.1)))
            }
        }
        var diamondPath = Path()
        diamondPath.move(to: CGPoint(x: core.midX, y: core.minY))
        diamondPath.addLine(to: CGPoint(x: core.maxX, y: core.midY))
        diamondPath.addLine(to: CGPoint(x: core.midX, y: core.maxY))
        diamondPath.addLine(to: CGPoint(x: core.minX, y: core.midY))
        diamondPath.closeSubpath()
        ctx.fill(diamondPath, with: .color(Color(hex: coreHex).opacity(locked ? 0.55 : 1.0)))
        ctx.stroke(diamondPath, with: .color(locked ? Color.white.opacity(0.4) : .white), lineWidth: 1.5)
        let sparkle = CGRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2)
        ctx.fill(Path(ellipseIn: sparkle), with: .color(locked ? Color.white.opacity(0.4) : .white))
        let txt = Text(locked ? "LOCKED" : "DATA")
            .font(.system(size: 7, weight: .black, design: .monospaced))
            .foregroundColor(Color(hex: coreHex))
        ctx.draw(txt, at: CGPoint(x: rect.midX, y: rect.maxY + 2))
    }

    /// Data shard — a small spinning amber chevron you must collect to unlock
    /// the core. Drawn on grid cells with value 4.
    private func drawShard(ctx: GraphicsContext, rect: CGRect) {
        let s = cellSize * 0.40 * (1.0 + 0.18 * sin(pulseTime * 5))
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for (r, a) in [(s * 1.9, 0.18), (s * 1.3, 0.30)] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(hex: "FFC83C").opacity(a)))
        }
        var dia = Path()
        dia.move(to: CGPoint(x: c.x, y: c.y - s))
        dia.addLine(to: CGPoint(x: c.x + s, y: c.y))
        dia.addLine(to: CGPoint(x: c.x, y: c.y + s))
        dia.addLine(to: CGPoint(x: c.x - s, y: c.y))
        dia.closeSubpath()
        ctx.fill(dia, with: .color(Color(hex: "FFC83C")))
        ctx.stroke(dia, with: .color(.white), lineWidth: 1)
    }

    /// Cyber-trail: fading dots at the last few cells the player visited.
    private func drawTrail(ctx: GraphicsContext, xOffset: CGFloat, yOffset: CGFloat) {
        for (i, t) in trail.enumerated() {
            let alpha = Double(i) / Double(max(1, trail.count)) * 0.55
            let cx = xOffset + CGFloat(t.x) * cellSize + cellSize / 2
            let cy = yOffset + CGFloat(t.y) * cellSize + cellSize / 2
            let dot = CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)
            ctx.fill(Path(ellipseIn: dot), with: .color(Color(hex: "00FFCC").opacity(alpha * 0.85)))
            ctx.stroke(Path(ellipseIn: dot), with: .color(Color(hex: "00FFCC").opacity(alpha)), lineWidth: 1)
        }
    }

    // MARK: - 8-bit pixel-art sprites

    /// Pixel-art renderer: strings of "0"-"9" describing pixel indices into a
    /// palette. "." = transparent. Each character draws a `pixelScale`-pt square.
    private func drawPixelArt(
        _ pattern: [String],
        ctx: GraphicsContext,
        origin: CGPoint,
        palette: [Color],
        pixelScale: CGFloat = 2.0,
        flipX: Bool = false
    ) {
        let cols = pattern.first?.count ?? 0
        for (row, line) in pattern.enumerated() {
            for (col, ch) in line.enumerated() {
                guard ch != ".", let idx = Int(String(ch)), idx >= 1, idx <= palette.count else { continue }
                let drawCol = flipX ? (cols - 1 - col) : col
                let rect = CGRect(
                    x: origin.x + CGFloat(drawCol) * pixelScale,
                    y: origin.y + CGFloat(row) * pixelScale,
                    width: pixelScale,
                    height: pixelScale
                )
                ctx.fill(Path(rect), with: .color(palette[idx - 1]))
            }
        }
    }

    /// Player runner — 2-frame walk cycle. 11×12 pixel art, 4 colours.
    /// Palette: 1=cyan-trim, 2=jacket-blue, 3=visor-glow, 4=cyber-purple-pant
    private static let playerFrames: [[String]] = [
        // Frame 0 — legs apart
        [
            "...111.....",
            "..13331....",
            "..13331....",
            "..11111....",
            "..21221....",
            ".221122....",
            ".221221....",
            "..2.22.....",
            "..4..4.....",
            "..4..4.....",
            ".44..44....",
            ".11..11....",
        ],
        // Frame 1 — legs together
        [
            "...111.....",
            "..13331....",
            "..13331....",
            "..11111....",
            "..21222....",
            ".221122....",
            ".221221....",
            "..2.22.....",
            "...44......",
            "...44......",
            "..4444.....",
            "..1111.....",
        ],
    ]
    private static let playerPalette: [Color] = [
        Color(hex: "00FFCC"),
        Color(hex: "1166AA"),
        Color(hex: "FFFFFF"),
        Color(hex: "5533AA"),
    ]

    /// Trace.exe — angular red diamond program with binary streamers.
    /// 2-frame cycle (rotated diamond + scanline shift).
    /// Palette: 1=red-base, 2=red-bright, 3=white-glint
    private static let traceFrames: [[String]] = [
        [
            "....3......",
            "...121.....",
            "..12321....",
            ".1233321...",
            "12321.12321",
            ".1233321...",
            "..12321....",
            "...121.....",
            "....3......",
            "...1.1.....",
            "..1...1....",
            ".1.....1...",
        ],
        [
            "....3......",
            "...111.....",
            "..12221....",
            ".1232321...",
            "12121.12121",
            ".1232321...",
            "..12221....",
            "...111.....",
            "....3......",
            "..1.1.1....",
            ".1...1.1...",
            "1.....1.1..",
        ],
    ]
    private static let tracePalette: [Color] = [
        Color(hex: "FF3344"),
        Color(hex: "FF7788"),
        Color(hex: "FFFFFF"),
    ]

    /// ICE Daemon — pixelated demonic skull with hollow eyes.
    /// 2-frame cycle (eyes flicker on/off).
    /// Palette: 1=orange-hull, 2=orange-bright, 3=black-eye, 4=red-iris
    private static let daemonFrames: [[String]] = [
        [
            "..11111....",
            ".1111111...",
            "111111111..",
            "11313131...",
            "11343431...",
            "111111111..",
            "11.111.11..",
            "1.11111.1..",
            "1.11111.1..",
            ".1.1.1.1...",
            "..1...1....",
        ],
        [
            "..11111....",
            ".1222221...",
            "121212121..",
            "12414141...",
            "12434321...",
            "121212121..",
            "12.222.21..",
            "1.22122.1..",
            "1.22122.1..",
            ".1.1.1.1...",
            "..1...1....",
        ],
    ]
    private static let daemonPalette: [Color] = [
        Color(hex: "FF9933"),
        Color(hex: "FFCC66"),
        Color(hex: "1A0500"),
        Color(hex: "FF3344"),
    ]

    /// Watchdog — quadruped ICE construct with red sensor eyes.
    /// 2-frame cycle (legs alternate).
    /// Palette: 1=purple-hull, 2=purple-bright, 3=white-trim, 4=red-eye
    private static let watchdogFrames: [[String]] = [
        [
            "...111.....",
            "..13331....",
            ".1144441...",
            "11144441...",
            "1.1331.1...",
            "1.1111.1...",
            "1.1.1..1...",
            "..1.1......",
            "..1.1.1....",
            "1.1...1....",
        ],
        [
            "...111.....",
            "..13331....",
            ".1144441...",
            "11144441...",
            "1.1331.1...",
            "1.1111.1...",
            "..1.1.1....",
            "..1.1......",
            "1.1.1......",
            "1.1...1....",
        ],
    ]
    private static let watchdogPalette: [Color] = [
        Color(hex: "AA66FF"),
        Color(hex: "DDAAFF"),
        Color(hex: "FFFFFF"),
        Color(hex: "FF3344"),
    ]

    private func drawPlayer(ctx: GraphicsContext, xOffset: CGFloat, yOffset: CGFloat) {
        let cellX = xOffset + CGFloat(playerX) * cellSize
        let cellY = yOffset + CGFloat(playerY) * cellSize
        let pixelScale: CGFloat = 1.7
        let frame = MatrixMiniGameView.playerFrames[playerWalkFrame % 2]
        // 11 cols × 1.7 = 18.7 wide, 12 rows × 1.7 = 20.4 tall — fits 24-pt cell.
        let spriteW = CGFloat(frame.first?.count ?? 0) * pixelScale
        let spriteH = CGFloat(frame.count) * pixelScale
        let originX = cellX + (cellSize - spriteW) / 2
        let originY = cellY + (cellSize - spriteH) / 2

        // Pulsing outer halo
        let ringScale = 1.0 + 0.15 * sin(pulseTime * 6)
        let pRect = CGRect(x: cellX + 2, y: cellY + 2, width: cellSize - 4, height: cellSize - 4)
        let ring = pRect.insetBy(dx: -CGFloat(4 * ringScale), dy: -CGFloat(4 * ringScale))
        ctx.stroke(
            Path(ellipseIn: ring),
            with: .color(Color(hex: "00FFCC").opacity(0.35)),
            lineWidth: 1.2
        )
        ctx.fill(
            Path(ellipseIn: pRect.insetBy(dx: -2, dy: -2)),
            with: .color(Color(hex: "00FFCC").opacity(0.12))
        )

        drawPixelArt(
            frame,
            ctx: ctx,
            origin: CGPoint(x: originX, y: originY),
            palette: MatrixMiniGameView.playerPalette,
            pixelScale: pixelScale,
            flipX: playerFacing == 1
        )
    }

    private func drawChasers(ctx: GraphicsContext, xOffset: CGFloat, yOffset: CGFloat) {
        for c in chasers {
            let cellX = xOffset + CGFloat(c.x) * cellSize
            let cellY = yOffset + CGFloat(c.y) * cellSize

            // Glitch jitter offset
            let jx = CGFloat(sin(glitchPhase * 8 + Double(c.x))) * 0.8
            let jy = CGFloat(cos(glitchPhase * 9 + Double(c.y))) * 0.8

            // Faint colored backplate so the sprite reads against walls
            let backRect = CGRect(
                x: cellX + 2 + jx, y: cellY + 2 + jy,
                width: cellSize - 4, height: cellSize - 4
            )
            ctx.fill(Path(ellipseIn: backRect), with: .color(c.kind.color.opacity(0.18)))
            ctx.stroke(Path(ellipseIn: backRect), with: .color(c.kind.color.opacity(0.85)), lineWidth: 1)

            // Sprite frame for this chaser
            let frames: [[String]]
            let palette: [Color]
            switch c.kind {
            case .trace:    frames = MatrixMiniGameView.traceFrames;    palette = MatrixMiniGameView.tracePalette
            case .daemon:   frames = MatrixMiniGameView.daemonFrames;   palette = MatrixMiniGameView.daemonPalette
            case .watchdog: frames = MatrixMiniGameView.watchdogFrames; palette = MatrixMiniGameView.watchdogPalette
            }
            let frame = frames[c.animFrame % frames.count]
            let pixelScale: CGFloat = 1.6
            let spriteW = CGFloat(frame.first?.count ?? 0) * pixelScale
            let spriteH = CGFloat(frame.count) * pixelScale
            let originX = cellX + (cellSize - spriteW) / 2 + jx
            let originY = cellY + (cellSize - spriteH) / 2 + jy
            drawPixelArt(
                frame,
                ctx: ctx,
                origin: CGPoint(x: originX, y: originY),
                palette: palette,
                pixelScale: pixelScale
            )

            // Glitch slice — thin colored band drawn across the sprite
            let sliceY = backRect.midY + sin(glitchPhase * 10 + Double(c.x)) * 4
            let slice = CGRect(x: backRect.minX, y: sliceY - 0.5, width: backRect.width, height: 1)
            ctx.fill(Path(slice), with: .color(c.kind.color.opacity(0.55)))
        }
    }

    // MARK: - Touch-drag input

    private func handleDrag(at point: CGPoint, in size: CGSize) {
        guard !gameOver, !inStageTransition else { return }
        let mazePxW = CGFloat(mazeWidth) * cellSize
        let mazePxH = CGFloat(mazeHeight) * cellSize
        let xOffset = (size.width - mazePxW) / 2
        let yOffset = (size.height - mazePxH) / 2
        let cx = Int(((point.x - xOffset) / cellSize).rounded(.down))
        let cy = Int(((point.y - yOffset) / cellSize).rounded(.down))
        guard cx >= 0, cx < mazeWidth, cy >= 0, cy < mazeHeight else { return }
        if let last = lastDragCell, last.x == cx, last.y == cy { return }
        lastDragCell = (cx, cy)
        stepTowards(cx: cx, cy: cy)
    }

    private func stepTowards(cx: Int, cy: Int) {
        guard !gameOver, !inStageTransition else { return }
        let dx = cx - playerX
        let dy = cy - playerY
        let preferred: [(Int, Int)] = abs(dx) >= abs(dy)
            ? [(dx.signum(), 0), (0, dy.signum())]
            : [(0, dy.signum()), (dx.signum(), 0)]
        for (sx, sy) in preferred {
            guard sx != 0 || sy != 0 else { continue }
            let nx = playerX + sx
            let ny = playerY + sy
            guard nx >= 0, nx < mazeWidth, ny >= 0, ny < mazeHeight else { continue }
            let cell = grid[ny][nx]
            guard cell != 1 else { continue }
            // Update facing if moving horizontally
            if sx > 0 { playerFacing = 0 }
            else if sx < 0 { playerFacing = 1 }
            // Push current pos onto trail before moving
            trail.append((playerX, playerY))
            if trail.count > 5 { trail.removeFirst(trail.count - 5) }
            playerX = nx
            playerY = ny
            playerWalkFrame = (playerWalkFrame + 1) % 2
            chiptune?.sfxMove()
            if cell == 4 {
                // Collect a data shard — clear the cell, tick the counter.
                grid[ny][nx] = 0
                shardsRemaining = max(0, shardsRemaining - 1)
                HapticsManager.shared.attackHit()
                chiptune?.playStageFill()
            }
            if cell == 3 {
                if shardsRemaining == 0 {
                    stageCleared()
                    return
                } else {
                    // Core is locked until every shard is in — nudge the player.
                    shardHintUntil = pulseTime + 1.8
                    HapticsManager.shared.error()
                }
            }
            checkChaserCollision()
            return
        }
    }

    // MARK: - Game logic

    private func initialise() {
        loadStage(0)
    }

    private func loadStage(_ idx: Int) {
        stageIndex = idx
        grid = MatrixMiniGameView.stageMaps[idx]
        playerX = 6; playerY = 11
        playerWalkFrame = 0
        playerFacing = 0
        trail = []

        // Spawn chasers per stage config — corner positions, alternating.
        let cfg = MatrixMiniGameView.stageConfigs[idx]
        let corners: [(Int, Int)] = [(1, 1), (11, 1), (11, 11), (1, 11)]
        var newChasers: [CodeChaser] = []
        for (i, kind) in cfg.chasers.enumerated() {
            let pos = corners[i % corners.count]
            newChasers.append(CodeChaser(x: pos.0, y: pos.1, kind: kind, animFrame: 0))
        }
        chasers = newChasers

        // Scatter data shards (grid value 4) on corridor cells away from the
        // start, the core, and the chaser corners. The core stays LOCKED until
        // they're all collected, so later zones force a full maze traversal
        // under chase pressure instead of a straight dash to the core.
        shardsRemaining = 0
        shardHintUntil = 0
        if cfg.shardCount > 0 {
            var candidates: [(Int, Int)] = []
            for y in 0..<mazeHeight {
                for x in 0..<mazeWidth where grid[y][x] == 0 {
                    let farFromStart = abs(x - 6) + abs(y - 11) >= 4
                    let notCorner = corners.allSatisfy { abs($0.0 - x) + abs($0.1 - y) >= 2 }
                    if farFromStart && notCorner { candidates.append((x, y)) }
                }
            }
            var placed = 0
            for (x, y) in candidates.shuffled() {
                guard placed < cfg.shardCount else { break }
                // Keep shards spread out — skip any too close to an already-placed one.
                grid[y][x] = 4
                placed += 1
            }
            shardsRemaining = placed
        }

        gameOver = false
        didWin = false
        lastDragCell = nil

        // Restart chaser timer at the stage's tick speed
        chaserTimer?.cancel()
        chaserTimer = Timer.publish(every: cfg.chaserTickSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tickChasers() }
    }

    /// Player reached the data core in the current stage.
    private func stageCleared() {
        chiptune?.playStageFill()
        HapticsManager.shared.attackHit()

        let nextIdx = stageIndex + 1
        if nextIdx >= MatrixMiniGameView.stageMaps.count {
            // Final stage cleared — full win.
            chiptune?.sfxWin()
            finishGame(success: true)
            return
        }

        // Show stage-cleared transition, then load the next stage after delay.
        inStageTransition = true
        transitionMessage = "ZONE \(stageIndex + 1) CLEARED"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            inStageTransition = false
            loadStage(nextIdx)
        }
    }

    private func startChasers() {
        // Initial chaser timer set in loadStage; this is a no-op safeguard.
    }

    private func startPulse() {
        pulseTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in pulseTime += 0.05 }
    }

    private func startGlitchPulse() {
        glitchTimer = Timer.publish(every: 0.06, on: .main, in: .common)
            .autoconnect()
            .sink { _ in glitchPhase += 0.06 }
    }

    private func startCodeRain() {
        var cols: [CodeRainColumn] = []
        for _ in 0..<14 {
            cols.append(makeRainColumn())
        }
        codeRain = cols
        rainTimer = Timer.publish(every: 0.07, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                for i in codeRain.indices {
                    codeRain[i].headY += codeRain[i].speed
                    if codeRain[i].headY > 380 {
                        codeRain[i] = makeRainColumn(resetTop: true)
                    }
                }
            }
    }

    private func makeRainColumn(resetTop: Bool = false) -> CodeRainColumn {
        let pool = MatrixMiniGameView.glyphPool
        let len = Int.random(in: 6...12)
        var glyphs: [String] = []
        for _ in 0..<len { glyphs.append(pool.randomElement() ?? "0") }
        let xRange: ClosedRange<CGFloat> = 8...340
        return CodeRainColumn(
            x: CGFloat.random(in: xRange),
            headY: resetTop ? CGFloat.random(in: -120 ... -10) : CGFloat.random(in: -80...380),
            glyphs: glyphs,
            speed: CGFloat.random(in: 1.4...3.4)
        )
    }

    private func startAudio() {
        let player = ChiptunePlayer()
        player?.startMelody()
        chiptune = player
    }

    private func tickChasers() {
        guard !gameOver, !inStageTransition else { return }
        var anyAdjacent = false
        for i in chasers.indices {
            let other = chasers.enumerated().compactMap { idx, c in
                idx == i ? nil : (x: c.x, y: c.y)
            }
            let stepped = stepChaserTowardPlayer(from: (chasers[i].x, chasers[i].y),
                                                 otherChasers: other)
            chasers[i].x = stepped.x
            chasers[i].y = stepped.y
            chasers[i].animFrame = (chasers[i].animFrame + 1) % 2
            let dx = chasers[i].x - playerX
            let dy = chasers[i].y - playerY
            if abs(dx) + abs(dy) <= 2 { anyAdjacent = true }
        }
        if anyAdjacent { chiptune?.sfxChaserNear() }
        checkChaserCollision()
    }

    private func stepChaserTowardPlayer(
        from pos: (x: Int, y: Int),
        otherChasers: [(x: Int, y: Int)]
    ) -> (x: Int, y: Int) {
        let candidates: [(x: Int, y: Int)] = [
            (pos.x, pos.y - 1),
            (pos.x, pos.y + 1),
            (pos.x - 1, pos.y),
            (pos.x + 1, pos.y),
        ]
        let valid = candidates.filter { c in
            guard c.x >= 0, c.x < mazeWidth, c.y >= 0, c.y < mazeHeight else { return false }
            guard grid[c.y][c.x] != 1 else { return false }
            if otherChasers.contains(where: { $0.x == c.x && $0.y == c.y }) { return false }
            return true
        }
        guard !valid.isEmpty else { return pos }
        let best = valid.min { a, b in
            let da = abs(a.x - playerX) + abs(a.y - playerY)
            let db = abs(b.x - playerX) + abs(b.y - playerY)
            return da < db
        }!
        return best
    }

    private func checkChaserCollision() {
        guard !gameOver, !inStageTransition else { return }
        for c in chasers {
            if c.x == playerX && c.y == playerY {
                chiptune?.sfxLose()
                HapticsManager.shared.playerKilled()
                finishGame(success: false)
                return
            }
        }
    }

    private func distanceToCore() -> Int {
        for y in 0..<mazeHeight {
            for x in 0..<mazeWidth where grid[y][x] == 3 {
                return abs(x - playerX) + abs(y - playerY)
            }
        }
        return 0
    }

    private func finishGame(success: Bool) {
        guard !gameOver else { return }
        gameOver = true
        didWin = success
        cancelTimers()
        // Linger on a WIN so the success banner reads; snap back fast on a
        // loss/bail — the player just wants to retry, not wait.
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 1.5 : 0.9)) {
            chiptune?.stop()
            chiptune = nil
            onComplete(success)
        }
    }

    private func cancelTimers() {
        chaserTimer?.cancel()
        rainTimer?.cancel()
        glitchTimer?.cancel()
        pulseTimer?.cancel()
    }
}
