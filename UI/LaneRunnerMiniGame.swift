import SwiftUI
import Combine

/// LANE RUNNER — Mission 2's data-extraction mini-game.
///
/// Premise: the runner has jacked into a data conduit and is sprinting
/// down a perspective wireframe tunnel toward the data core. Three lanes.
/// Obstacles fly out from the vanishing point — ICE drones, firewalls,
/// trace beams — while glowing data shards float in lanes you can scoop up.
///
/// Inputs (all touch-based):
///   • Swipe LEFT / RIGHT  → switch lane
///   • Swipe UP            → jump (clears firewalls + ground hazards)
///   • Tap                 → small forward dash (catch up to a shard)
///
/// Win: collect 10 data fragments before getting hit 3 times.
/// Lose: 3 hits or trace bar fills.
struct LaneRunnerMiniGame: View {
    @ObservedObject var gameState: GameState
    let onComplete: (Bool) -> Void

    // MARK: - Tuning

    /// Number of data shards required to extract.
    private let targetFragments = 10
    /// Number of hits the runner can take before they're burned.
    /// Tuned 2026-05 — final: 3 → 5 → 4. Half-way between brutal and easy.
    private let maxHits = 4
    /// Initial forward speed (z-units per second).
    /// Tuned 2026-05 — final pass: 0.34 (was 0.42 — felt too fast/screwy
    /// at the start). Ramps up via `+= 0.10` per data shard collected.
    /// 2026-05-10 +15% difficulty bump: 0.34 → 0.38.
    private let baseSpeed: CGFloat = 0.38
    /// Cap on forward speed.
    private let maxSpeed: CGFloat = 0.85
    /// How fast the trace bar drifts up on its own (per second).
    /// 2026-05-10 +15% difficulty bump: 0.007 → 0.0083.
    private let traceDrift: CGFloat = 0.0083
    /// Number of horizontal lanes. More lanes = more granular movement.
    private let laneCount: Int = 5
    /// Seconds at the start of the run before the FIRST obstacle spawns.
    /// Lets the player orient + practise dragging before any threat arrives.
    private let graceSeconds: Double = 2.0

    // MARK: - Obstacle model

    enum ObstacleKind {
        case drone        // single-lane red ICE — dodge by lane change
        case firewall     // 3-lane orange wall — must JUMP
        case dataShard    // single-lane cyan shard — collide to collect
        case traceBeam    // 2-lane purple beam — change to free lane

        var basePalette: [Color] {
            switch self {
            case .drone:
                return [Color(hex: "FF3344"),
                        Color(hex: "FF7788"),
                        Color(hex: "FFFFFF"),
                        Color(hex: "330000")]
            case .firewall:
                return [Color(hex: "FF8833"),
                        Color(hex: "FFCC66"),
                        Color(hex: "FFFFFF"),
                        Color(hex: "331100")]
            case .dataShard:
                return [Color(hex: "00FFCC"),
                        Color(hex: "AAFFEE"),
                        Color(hex: "FFFFFF"),
                        Color(hex: "003322")]
            case .traceBeam:
                return [Color(hex: "AA66FF"),
                        Color(hex: "DDAAFF"),
                        Color(hex: "FFFFFF"),
                        Color(hex: "220033")]
            }
        }
    }

    struct Obstacle: Identifiable {
        let id = UUID()
        var z: CGFloat                    // 0 = vanishing point, 1 = at player line
        let lanes: [Int]                  // lane indices this occupies (0/1/2)
        let kind: ObstacleKind
        var consumed: Bool = false        // resolved (collected or hit)
    }

    // MARK: - State

    /// Logical lane (0..laneCount-1). Discrete — used for collision.
    @State private var playerLane: Int = 2
    /// Visual lane position — animates smoothly toward `playerLane` for a
    /// non-snapping transition. Used only for rendering the runner sprite.
    @State private var playerLaneVisual: CGFloat = 2
    @State private var playerJumpY: CGFloat = 0       // negative when airborne
    @State private var playerJumpVel: CGFloat = 0
    @State private var playerWalkFrame: Int = 0

    @State private var obstacles: [Obstacle] = []
    @State private var dataFragments: Int = 0
    @State private var hits: Int = 0
    @State private var traceBar: CGFloat = 0
    @State private var distance: CGFloat = 0
    @State private var speed: CGFloat = 0.38   // mirrors baseSpeed; was 0.42

    @State private var gameOver: Bool = false
    @State private var didWin: Bool = false
    @State private var invulnSeconds: CGFloat = 0    // brief flash after a hit

    @State private var spawnTimer: AnyCancellable?
    @State private var tickTimer: AnyCancellable?
    @State private var pulseTimer: AnyCancellable?
    @State private var rainTimer: AnyCancellable?
    @State private var pulseTime: Double = 0

    @State private var ringScroll: CGFloat = 0         // tunnel-ring depth scroll
    @State private var codeRain: [RainColumn] = []
    /// Floating "+1 DATA" popups that fade up after a shard is collected.
    /// Lifetime ≈ 0.7s, then auto-removed in tick().
    @State private var pickupFlashes: [PickupFlash] = []
    private struct PickupFlash: Identifiable {
        let id = UUID()
        let spawnedAt: Double   // matches pulseTime (running clock)
        let lane: Int
    }
    @State private var chiptune: ChiptunePlayer? = nil
    @State private var showBriefing: Bool = true       // intro briefing card

    // MARK: - Drag input model
    //
    // Old model: each drag fired ONE lane change at a 24pt threshold, then
    // ignored further drag motion until release. To traverse multiple lanes
    // the player had to lift + re-swipe. Felt impossible.
    //
    // New model: drag tracks the runner's lane like a joystick. As soon as
    // the gesture passes a 12pt threshold it commits to an axis (horizontal
    // = lane drag, vertical-up = jump). On horizontal: target lane =
    // startLane + round(dx / dragLaneWidth). Updates continuously every
    // onChanged frame, smoothly animating the runner.

    enum DragAxis { case undecided, horizontal, vertical }
    @State private var dragAxis: DragAxis = .undecided
    @State private var dragStartLane: Int = 0
    /// Drag distance per single lane shift. A 90pt right drag → +2 lanes.
    private let dragLaneWidth: CGFloat = 45

    struct RainColumn: Identifiable {
        let id = UUID()
        var x: CGFloat
        var headY: CGFloat
        var glyphs: [String]
        var speed: CGFloat
    }

    private static let glyphPool: [String] = [
        "0", "1", "0", "1", "0", "1",
        "F", "7", "A", "C", "E", "9",
        "0xF", "0x7", "B3", "FF", "C0", "DE",
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
                tunnelArea
                hud
                touchHint
            }
            .padding(.bottom, 28)

            if showBriefing {
                MiniGameBriefing(
                    title: "DATA CONDUIT",
                    subtitle: "LANE RUNNER PROTOCOL",
                    accent: Color(hex: "00FFCC"),
                    rules: [
                        BriefingRule(
                            iconName: "arrow.left.and.right",
                            color: Color(hex: "00FFCC"),
                            title: "DRAG L/R TO MOVE",
                            detail: "Five lanes. Drag your finger horizontally — the runner slides smoothly. Drag farther to skip lanes."
                        ),
                        BriefingRule(
                            iconName: "arrow.up",
                            color: Color(hex: "FFCC00"),
                            title: "SWIPE UP TO JUMP",
                            detail: "Orange firewalls vary — full-field walls span every lane (must JUMP), partial walls cover only 3 lanes (slide to a free lane OR jump)."
                        ),
                        BriefingRule(
                            iconName: "diamond.fill",
                            color: Color(hex: "00FFCC"),
                            title: "GRAB CYAN DATA SHARDS",
                            detail: "Move into them — collect \(targetFragments) fragments before the trace bar fills or you take \(maxHits) hits."
                        ),
                    ],
                    onStart: {
                        showBriefing = false
                    }
                )
                .zIndex(1000)
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "00FFCC"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6))
                Text("// DATA CONDUIT")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "00FFCC"))
                Circle().fill(Color(hex: "FF00AA"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6 + .pi))
            }
            Text("DIVING — JACK THE STREAM, GRAB \(targetFragments) FRAGMENTS")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    // MARK: - Tunnel area

    private var tunnelArea: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color(hex: "020812"))
                    .overlay(Rectangle().stroke(Color(hex: "00FFCC").opacity(0.30), lineWidth: 1))
                    .overlay(Rectangle().stroke(Color(hex: "FF00AA").opacity(0.10), lineWidth: 3))

                Canvas { ctx, size in
                    drawCodeRain(ctx: ctx, size: size)
                    drawTunnel(ctx: ctx, size: size)
                    drawObstacles(ctx: ctx, size: size)
                    drawPlayer(ctx: ctx, size: size)
                    drawPickupFlashes(ctx: ctx, size: size)
                    drawScanlines(ctx: ctx, size: size)
                }

                if gameOver {
                    Color.black.opacity(0.78)
                    VStack(spacing: 6) {
                        Text(didWin ? "DATA EXTRACTED" : "TRACE BURNED YOU")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(didWin ? Color(hex: "00FFCC") : Color(hex: "FF3344"))
                        Text(didWin ? "// CONDUIT CLEARED" : "// CONNECTION LOST")
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
                    // Joystick-style continuous drag. Lane tracks the drag
                    // delta in real time — drag right far, runner moves right
                    // far. Drag back, runner moves back. No more
                    // "one swipe = one lane" debounce.
                    .onChanged { drag in
                        guard !showBriefing else { return }
                        let dx = drag.translation.width
                        let dy = drag.translation.height
                        let mag = max(abs(dx), abs(dy))

                        // Decide axis on first significant motion (12pt).
                        if dragAxis == .undecided {
                            guard mag >= 12 else { return }
                            if abs(dx) > abs(dy) {
                                dragAxis = .horizontal
                                dragStartLane = playerLane
                            } else if dy < 0 {
                                dragAxis = .vertical
                                tryJump()    // jumps fire immediately
                            } else {
                                // Downward drag — ignore (not a meaningful action).
                                dragAxis = .vertical
                            }
                            return
                        }

                        // Horizontal drag: continuously update lane based on
                        // distance from where the drag started.
                        if dragAxis == .horizontal {
                            let laneDelta = Int((dx / dragLaneWidth).rounded())
                            setPlayerLane(dragStartLane + laneDelta)
                        }
                        // Vertical: nothing more — jump already triggered.
                    }
                    .onEnded { drag in
                        defer {
                            dragAxis = .undecided
                        }
                        guard !showBriefing else { return }
                        // If axis never decided, the drag was below threshold
                        // → treat as a tap → small forward dash.
                        if dragAxis == .undecided {
                            speed = min(maxSpeed, speed + 0.10)
                            HapticsManager.shared.buttonTap()
                        }
                    }
            )
        }
        // Bigger play area — 480pt tall (was 380) for a more readable
        // tunnel + obstacles, and edge-to-edge horizontally. maxWidth:
        // .infinity centers the area horizontally inside the parent VStack.
        .frame(maxWidth: .infinity)
        .frame(height: 480)
        .padding(.horizontal, 2)
    }

    // MARK: - HUD + footer

    private var hud: some View {
        HStack(spacing: 10) {
            statusBlock(label: "FRAGMENTS",
                        value: "\(dataFragments) / \(targetFragments)",
                        color: Color(hex: "00FFCC"))
            statusBlock(label: "HITS",
                        value: "\(hits) / \(maxHits)",
                        color: Color(hex: "FF3344"))
            statusBlock(label: "DIST",
                        value: String(format: "%.0f", distance),
                        color: Color(hex: "FFCC00"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var touchHint: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SWIPE TO MOVE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                Text("drag ←/→ to slide lanes    swipe ↑ to jump    tap to dash")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "00FFCC").opacity(0.75))
            }
            Spacer()
            // Trace bar + bail
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

    /// Vanishing point sits roughly 30% from the top — tunnel "looks down" so
    /// the closer obstacles dominate the lower part of the frame.
    private func vanishingPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.30)
    }

    /// Y position the player sprite sits at (bottom of the tunnel view).
    private func playerBaselineY(in size: CGSize) -> CGFloat {
        size.height * 0.78
    }

    /// World-space lane center at z = 1 (the player's plane). Lanes splay out
    /// at the bottom; converge at the vanishing point. Now generalised to
    /// `laneCount` lanes — the leftmost is at `mid - spread`, rightmost at
    /// `mid + spread`, evenly spaced.
    private func laneCenterX(_ lane: Int, in size: CGSize) -> CGFloat {
        let mid = size.width / 2
        let spread = size.width * 0.30
        guard laneCount > 1 else { return mid }
        let t = CGFloat(lane) / CGFloat(laneCount - 1)   // 0..1
        return mid - spread + t * (2 * spread)
    }
    /// Float overload — used by the player sprite for animated transitions
    /// between integer lanes.
    private func laneCenterX(_ lane: CGFloat, in size: CGSize) -> CGFloat {
        let mid = size.width / 2
        let spread = size.width * 0.30
        guard laneCount > 1 else { return mid }
        let t = lane / CGFloat(laneCount - 1)
        return mid - spread + t * (2 * spread)
    }

    /// Map a (lane, z) into screen-space, applying perspective.
    private func screenPos(lane: Int, z: CGFloat, in size: CGSize) -> CGPoint {
        let vp = vanishingPoint(in: size)
        let baseY = playerBaselineY(in: size)
        let endX = laneCenterX(lane, in: size)
        let zClamped = max(0, min(1.05, z))
        // Non-linear perspective so close objects feel close
        let p = pow(zClamped, 1.4)
        let x = vp.x + (endX - vp.x) * p
        let y = vp.y + (baseY - vp.y) * p
        return CGPoint(x: x, y: y)
    }

    private func drawCodeRain(ctx: GraphicsContext, size: CGSize) {
        for col in codeRain {
            for (i, g) in col.glyphs.enumerated() {
                let y = col.headY - CGFloat(i) * 14
                guard y >= -14, y <= size.height + 14 else { continue }
                let alpha = max(0, 1.0 - Double(i) * 0.08)
                let color = i == 0
                    ? Color.white.opacity(alpha * 0.7)
                    : Color(hex: "00FF88").opacity(alpha * 0.45)
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
                with: .color(Color(hex: "00FFCC").opacity(alpha))
            )
            y += 3
        }
    }

    private func drawTunnel(ctx: GraphicsContext, size: CGSize) {
        let vp = vanishingPoint(in: size)
        let baseY = playerBaselineY(in: size)

        // Outer perspective frame — 4 lines from screen corners (at baseline-ish)
        // to the vanishing point.
        let frameColor = Color(hex: "00FFCC").opacity(0.35)
        let outerPoints: [CGPoint] = [
            CGPoint(x: 0,             y: baseY + 60),
            CGPoint(x: size.width,    y: baseY + 60),
            CGPoint(x: -50,           y: size.height + 40),
            CGPoint(x: size.width+50, y: size.height + 40),
        ]
        for p in outerPoints {
            var path = Path()
            path.move(to: p)
            path.addLine(to: vp)
            ctx.stroke(path, with: .color(frameColor.opacity(0.55)), lineWidth: 1)
        }
        // Lane separator lines
        for laneEdge in [-0.5, 0.5] as [CGFloat] {
            let mid = size.width / 2
            let spread = size.width * 0.30
            let endX = mid + laneEdge * 2 * spread / 2
            var path = Path()
            path.move(to: CGPoint(x: endX, y: baseY))
            path.addLine(to: vp)
            ctx.stroke(path, with: .color(frameColor.opacity(0.45)), lineWidth: 1)
        }

        // Tunnel rings — equally spaced in z, but they SCROLL toward the player
        // by `ringScroll` (which advances each tick). 12 rings total; recycle
        // when they pass z=1.
        let ringCount = 12
        for i in 0..<ringCount {
            let baseZ = CGFloat(i) / CGFloat(ringCount)
            let z = (baseZ + ringScroll).truncatingRemainder(dividingBy: 1.0)
            let p = pow(z, 1.4)
            // Ellipse centered at midX, perspective-scaled
            let cx = vp.x
            let cy = vp.y + (baseY - vp.y) * p
            let halfW = size.width * 0.5 * p
            let halfH = size.height * 0.18 * p
            let rect = CGRect(x: cx - halfW, y: cy - halfH, width: halfW * 2, height: halfH * 2)
            let alpha = 0.10 + 0.45 * Double(p)
            ctx.stroke(
                Path(ellipseIn: rect),
                with: .color(Color(hex: "00FFCC").opacity(alpha)),
                lineWidth: 1
            )
        }

        // Far-end glow at the vanishing point
        for radius: CGFloat in [80, 50, 20] {
            let r = CGRect(x: vp.x - radius, y: vp.y - radius, width: radius*2, height: radius*2)
            ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: "00FFCC").opacity(0.06)))
        }

        // Baseline line — the player's plane
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: 8,             y: baseY))
                p.addLine(to: CGPoint(x: size.width-8, y: baseY))
            },
            with: .color(Color(hex: "00FFCC").opacity(0.7)),
            lineWidth: 1
        )
    }

    private func drawObstacles(ctx: GraphicsContext, size: CGSize) {
        // Sort by z so far-away obstacles draw first (closer ones overdraw)
        let ordered = obstacles.sorted { $0.z < $1.z }
        for ob in ordered {
            let zClamped = max(0, min(1.0, ob.z))
            let p = pow(zClamped, 1.4)
            let scale = 0.15 + 0.85 * p
            switch ob.kind {
            case .drone:
                let lane = ob.lanes.first ?? 1
                let pos = screenPos(lane: lane, z: ob.z, in: size)
                drawDronePixelArt(ctx: ctx, center: pos, scale: scale)
            case .firewall:
                drawFirewall(ctx: ctx, ob: ob, size: size, p: p)
            case .dataShard:
                let lane = ob.lanes.first ?? 1
                let pos = screenPos(lane: lane, z: ob.z, in: size)
                drawDataShard(ctx: ctx, center: pos, scale: scale)
            case .traceBeam:
                drawTraceBeam(ctx: ctx, ob: ob, size: size, p: p)
            }
        }
    }

    private func drawDronePixelArt(ctx: GraphicsContext, center: CGPoint, scale: CGFloat) {
        // Compact 9×8 pixel-art drone: 1=red hull, 2=highlight, 3=visor, 4=engine
        let frame = [
            "..1111...",
            ".112211..",
            "11332311.",
            "11333311.",
            "11332311.",
            ".112211..",
            "..1111...",
            ".4.11.4..",
        ]
        let palette = ObstacleKind.drone.basePalette
        let pixelScale = max(1.5, scale * 3.5)
        let cols = 9, rows = 8
        let originX = center.x - CGFloat(cols) * pixelScale / 2
        let originY = center.y - CGFloat(rows) * pixelScale / 2
        drawPixelArt(frame, ctx: ctx,
                     origin: CGPoint(x: originX, y: originY),
                     palette: palette, pixelScale: pixelScale)
    }

    private func drawFirewall(ctx: GraphicsContext, ob: Obstacle, size: CGSize, p: CGFloat) {
        // Draw the wall ONLY across the lanes it actually occupies — using
        // `ob.lanes` (was previously hardcoded lanes 0 / 2 which made every
        // wall LOOK like it spanned the left ~60% while the collision logic
        // covered all 5 lanes, causing phantom hits when the player thought
        // they had dodged right). Visual now matches hitbox 1:1.
        let leftLane = ob.lanes.min() ?? 0
        let rightLane = ob.lanes.max() ?? (laneCount - 1)
        let isFullField = ob.lanes.count >= laneCount
        let leftPos = screenPos(lane: leftLane, z: ob.z, in: size)
        let rightPos = screenPos(lane: rightLane, z: ob.z, in: size)
        let height = 50 * p
        let rect = CGRect(
            x: leftPos.x - 14,
            y: leftPos.y - height,
            width: rightPos.x - leftPos.x + 28,
            height: height
        )
        let palette = ObstacleKind.firewall.basePalette
        ctx.fill(Path(rect), with: .color(palette[0].opacity(0.20 + Double(p) * 0.40)))
        ctx.stroke(Path(rect), with: .color(palette[1]), lineWidth: max(1, p * 2.2))
        // Inner brick lines for texture
        var lineY = rect.minY + 8
        let stride = max(6, p * 12)
        while lineY < rect.maxY - 4 {
            ctx.stroke(
                Path { pa in
                    pa.move(to: CGPoint(x: rect.minX + 4, y: lineY))
                    pa.addLine(to: CGPoint(x: rect.maxX - 4, y: lineY))
                },
                with: .color(palette[0].opacity(0.55)),
                lineWidth: 0.8
            )
            lineY += stride
        }
        if p > 0.45 {
            // Hint changes by type — full-field wall MUST be jumped over,
            // partial walls can also be dodged by sliding into a free lane.
            ctx.draw(
                Text(isFullField ? "FIREWALL — JUMP" : "FIREWALL — DODGE/JUMP")
                    .font(.system(size: 10 * p, weight: .black, design: .monospaced))
                    .foregroundColor(palette[1]),
                at: CGPoint(x: rect.midX, y: rect.minY - 7 * p)
            )
        }
    }

    private func drawDataShard(ctx: GraphicsContext, center: CGPoint, scale: CGFloat) {
        // Cyan diamond shard with halo + sparkle.
        let halfSize = 8 + 14 * scale
        let halo = CGRect(x: center.x - halfSize - 6,
                          y: center.y - halfSize - 6,
                          width: (halfSize + 6) * 2, height: (halfSize + 6) * 2)
        ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "00FFCC").opacity(0.18)))
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - halfSize))
        path.addLine(to: CGPoint(x: center.x + halfSize, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + halfSize))
        path.addLine(to: CGPoint(x: center.x - halfSize, y: center.y))
        path.closeSubpath()
        ctx.fill(path, with: .color(Color(hex: "00FFCC")))
        ctx.stroke(path, with: .color(.white), lineWidth: 1.4)
        // Sparkle dot
        let sparkle = CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)
        ctx.fill(Path(ellipseIn: sparkle), with: .color(.white))
    }

    private func drawTraceBeam(ctx: GraphicsContext, ob: Obstacle, size: CGSize, p: CGFloat) {
        // Two-lane purple beam (vertical bars)
        let palette = ObstacleKind.traceBeam.basePalette
        for lane in ob.lanes {
            let pos = screenPos(lane: lane, z: ob.z, in: size)
            let w: CGFloat = max(8, 26 * p)
            let h: CGFloat = max(40, 80 * p)
            let rect = CGRect(x: pos.x - w/2, y: pos.y - h, width: w, height: h)
            ctx.fill(Path(rect), with: .color(palette[0].opacity(0.45)))
            ctx.stroke(Path(rect), with: .color(palette[1]), lineWidth: max(1, p * 1.8))
            // Inner zigzag lightning
            var zig = Path()
            let steps = 4
            zig.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
            for s in 1...steps {
                let yy = rect.minY + (rect.height - 4) * CGFloat(s) / CGFloat(steps) + 2
                let dx: CGFloat = (s % 2 == 0) ? -3 : 3
                zig.addLine(to: CGPoint(x: rect.midX + dx, y: yy))
            }
            ctx.stroke(zig, with: .color(palette[2].opacity(0.85)), lineWidth: 1.2)
        }
    }

    /// The runner sprite — pixel art at the player's current lane + jump offset.
    /// Uses the *visual* lane (animated float) so the runner slides smoothly
    /// between lanes instead of teleporting.
    /// Render floating "+1 DATA" popups for recently-collected shards.
    /// Pops up from the player's lane and fades over ~0.7s.
    private func drawPickupFlashes(ctx: GraphicsContext, size: CGSize) {
        let lifetime: Double = 0.7
        for flash in pickupFlashes {
            let age = pulseTime - flash.spawnedAt
            guard age >= 0, age <= lifetime else { continue }
            let progress = age / lifetime
            let cx = laneCenterX(flash.lane, in: size)
            let baseY = playerBaselineY(in: size)
            // Float upward + fade out
            let cy = baseY - 30 - CGFloat(progress) * 50
            let alpha = 1.0 - progress
            // Glow rectangle behind text
            let glowRect = CGRect(x: cx - 28, y: cy - 12, width: 56, height: 22)
            ctx.fill(Path(roundedRect: glowRect, cornerRadius: 4),
                     with: .color(Color(hex: "00FFCC").opacity(alpha * 0.18)))
            // The text
            ctx.draw(
                Text("+1 DATA")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: "00FFCC").opacity(alpha)),
                at: CGPoint(x: cx, y: cy)
            )
        }
    }

    private func drawPlayer(ctx: GraphicsContext, size: CGSize) {
        let baseY = playerBaselineY(in: size)
        let cx = laneCenterX(playerLaneVisual, in: size)
        let cy = baseY + playerJumpY     // jump lifts player upward (negative Y)

        // Floor halo so the runner reads as grounded
        let halo = CGRect(x: cx - 22, y: baseY - 5, width: 44, height: 12)
        ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "00FFCC").opacity(0.30)))

        // Pulsing ring around runner
        let ringScale = 1.0 + 0.15 * sin(pulseTime * 6)
        let ring = CGRect(x: cx - 18 * ringScale, y: cy - 22 * ringScale,
                          width: 36 * ringScale, height: 36 * ringScale)
        ctx.stroke(Path(ellipseIn: ring),
                   with: .color(Color(hex: "00FFCC").opacity(0.45)),
                   lineWidth: 1.2)

        // 11×12 pixel-art runner (re-uses the look from MatrixMiniGameView)
        let frame = LaneRunnerMiniGame.runnerFrames[playerWalkFrame % 2]
        let pixelScale: CGFloat = 2.4
        let cols = frame.first?.count ?? 0
        let rows = frame.count
        let originX = cx - CGFloat(cols) * pixelScale / 2
        let originY = cy - CGFloat(rows) * pixelScale + 6   // sit so feet touch baseline
        // Flash-flicker if invuln
        let alpha: Double = invulnSeconds > 0 ? (Int(pulseTime * 20) % 2 == 0 ? 0.4 : 1.0) : 1.0
        var subCtx = ctx
        subCtx.opacity = alpha
        drawPixelArt(frame, ctx: subCtx,
                     origin: CGPoint(x: originX, y: originY),
                     palette: LaneRunnerMiniGame.runnerPalette,
                     pixelScale: pixelScale)
    }

    /// Runner pixel-art frames (2-frame walk cycle).
    private static let runnerFrames: [[String]] = [
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
    private static let runnerPalette: [Color] = [
        Color(hex: "00FFCC"),
        Color(hex: "1166AA"),
        Color(hex: "FFFFFF"),
        Color(hex: "5533AA"),
    ]

    /// Generic pixel-art renderer.
    private func drawPixelArt(
        _ pattern: [String],
        ctx: GraphicsContext,
        origin: CGPoint,
        palette: [Color],
        pixelScale: CGFloat = 2.0
    ) {
        for (row, line) in pattern.enumerated() {
            for (col, ch) in line.enumerated() {
                guard ch != ".",
                      let idx = Int(String(ch)),
                      idx >= 1, idx <= palette.count else { continue }
                let rect = CGRect(
                    x: origin.x + CGFloat(col) * pixelScale,
                    y: origin.y + CGFloat(row) * pixelScale,
                    width: pixelScale,
                    height: pixelScale
                )
                ctx.fill(Path(rect), with: .color(palette[idx - 1]))
            }
        }
    }

    // MARK: - Input

    private func tryLaneChange(_ direction: Int) {
        setPlayerLane(playerLane + direction)
    }

    /// Set the player's lane to an absolute index. Called continuously during
    /// a horizontal drag — clamps to the lane count and only fires SFX +
    /// animation when the lane actually changes.
    private func setPlayerLane(_ target: Int) {
        guard !gameOver else { return }
        let clamped = max(0, min(laneCount - 1, target))
        guard clamped != playerLane else { return }
        playerLane = clamped
        withAnimation(.easeOut(duration: 0.14)) {
            playerLaneVisual = CGFloat(clamped)
        }
        playerWalkFrame = (playerWalkFrame + 1) % 2
        chiptune?.sfxLaneSwitch()
        HapticsManager.shared.buttonTap()
    }

    private func tryJump() {
        guard !gameOver else { return }
        // Tuned 2026-05 — final jump tuning: -260 → -340 → -420 initial vel.
        // Pairs with reduced gravity (1100 → 750) for ~1.1s airtime, which
        // is wide enough to reliably clear a firewall whose danger window
        // is ~0.45s. The jump still feels snappy on input (apex in ~0.55s)
        // but gives a forgiving window above ground.
        playerJumpVel = -420
        chiptune?.sfxJump()
        HapticsManager.shared.buttonTap()
    }

    // MARK: - Tick / collision

    private func startTimers() {
        let dt: TimeInterval = 1.0 / 60.0
        tickTimer = Timer.publish(every: dt, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick(dt: CGFloat(dt)) }
        // Spawn obstacles on a separate timer.
        // Tuned 2026-05 — final: 0.55 → 0.85 → 1.2 → 1.0 → 0.87s.
        // 2026-05-10 +15% difficulty bump: 1.0 → 0.87s (more obstacles).
        spawnTimer = Timer.publish(every: 0.87, on: .main, in: .common)
            .autoconnect()
            .sink { _ in spawnObstacle() }
        pulseTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in pulseTime += 0.05 }
        // Code-rain ticker
        var cols: [RainColumn] = []
        for _ in 0..<14 { cols.append(makeRainColumn()) }
        codeRain = cols
        rainTimer = Timer.publish(every: 0.07, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                for i in codeRain.indices {
                    codeRain[i].headY += codeRain[i].speed
                    if codeRain[i].headY > 420 {
                        codeRain[i] = makeRainColumn(resetTop: true)
                    }
                }
            }
    }

    private func cancelTimers() {
        tickTimer?.cancel()
        spawnTimer?.cancel()
        pulseTimer?.cancel()
        rainTimer?.cancel()
    }

    private func tick(dt: CGFloat) {
        guard !gameOver, !showBriefing else { return }

        // Speed ramp
        // Slower ramp — was 0.025/sec → 0.012/sec. Takes ~45s to hit max
        // speed instead of ~25s, giving the player breathing room.
        // 2026-05-10 +15% difficulty bump: 0.012 → 0.0138.
        speed = min(maxSpeed, speed + dt * 0.0138)
        distance += speed * dt * 60   // arbitrary distance unit

        // Tunnel ring scroll for parallax
        ringScroll = (ringScroll + speed * dt * 0.6).truncatingRemainder(dividingBy: 1.0)

        // Ambient trace drift (more if more hits — pressure builds)
        traceBar += traceDrift * dt + dt * 0.0008 * CGFloat(hits)
        if traceBar >= 1.0 { finishGame(success: false); return }

        // Jump physics
        if playerJumpVel != 0 || playerJumpY < 0 {
            // Final gravity tuning: 1100 → 750. Combined with the higher
            // initial vel (-420), peak height is similar but airtime
            // extends to ~1.1s — a comfortably wide window to clear
            // firewalls that are in the player's lane.
            playerJumpVel += 750 * dt
            playerJumpY += playerJumpVel * dt
            if playerJumpY >= 0 {
                playerJumpY = 0
                playerJumpVel = 0
            }
        }

        // Walk frame toggling — running cadence
        playerWalkFrame = Int(distance / 6) % 2

        // Invuln countdown
        if invulnSeconds > 0 { invulnSeconds = max(0, invulnSeconds - dt) }

        // Move obstacles
        for i in obstacles.indices {
            obstacles[i].z += speed * dt
        }

        // Collision detection — when an obstacle's z crosses 1.0, resolve
        for i in obstacles.indices where !obstacles[i].consumed {
            if obstacles[i].z >= 0.95 && obstacles[i].z <= 1.05 {
                resolveObstacle(at: i)
            }
        }

        // Despawn obstacles that have passed
        obstacles.removeAll { $0.z > 1.15 }
        // Despawn old pickup-flash popups (lifetime = 0.7s in the renderer).
        pickupFlashes.removeAll { pulseTime - $0.spawnedAt > 0.8 }

        // Win check
        if dataFragments >= targetFragments {
            chiptune?.sfxWin()
            finishGame(success: true)
        }
    }

    private func resolveObstacle(at i: Int) {
        guard !obstacles[i].consumed else { return }
        let ob = obstacles[i]
        let inLane = ob.lanes.contains(playerLane)
        // Player is jumping if their Y offset is significantly negative
        let isJumping = playerJumpY < -10

        switch ob.kind {
        case .drone:
            if inLane && !isJumping && invulnSeconds == 0 {
                takeHit()
            }
        case .firewall:
            // PHANTOM-HIT FIX: was `if !isJumping && invulnSeconds == 0`,
            // which hit the player even when their lane wasn't part of the
            // firewall's lane set — they'd see the firewall on the right
            // half of the screen, be in the left lane, and still take
            // damage with no visible hit. Now requires the player to be IN
            // one of the firewall's lanes AND not jumping.
            if inLane && !isJumping && invulnSeconds == 0 {
                takeHit()
            }
        case .dataShard:
            if inLane {
                dataFragments += 1
                chiptune?.sfxCollect()
                HapticsManager.shared.attackHit()
                obstacles[i].consumed = true
                // Spawn a "+1 DATA" floating popup at the pickup point so
                // the player gets clear visual feedback the shard was
                // collected (audio + haptic alone wasn't enough — user
                // reported it felt confusing).
                pickupFlashes.append(PickupFlash(
                    spawnedAt: pulseTime,
                    lane: ob.lanes.first ?? playerLane
                ))
            }
        case .traceBeam:
            if inLane && !isJumping && invulnSeconds == 0 {
                // Trace beam adds extra trace bar damage on top of an HP hit
                traceBar = min(1.0, traceBar + 0.20)
                takeHit()
            }
        }
    }

    private func takeHit() {
        hits += 1
        invulnSeconds = 1.2
        chiptune?.sfxHit()
        HapticsManager.shared.playerKilled()
        if hits >= maxHits {
            finishGame(success: false)
        }
    }

    // MARK: - Spawn

    private func spawnObstacle() {
        guard !gameOver, !showBriefing else { return }
        // Grace period — first 3 seconds spawn nothing so the player can
        // orient + practise dragging without any threat on screen.
        // We use `distance` as a proxy for elapsed gameplay time
        // (post-briefing). distance grows at 60 * speed per second.
        let secondsSinceStart = Double(distance) / (60.0 * Double(baseSpeed))
        guard secondsSinceStart >= graceSeconds else { return }
        // Avoid overlap with existing far obstacles in same z window
        let hasNearbyAtBack = obstacles.contains(where: { $0.z < 0.18 })
        if hasNearbyAtBack { return }

        // Weighted random pick — middle-ground difficulty.
        // 2026-05-10 +15% difficulty bump: shifted 5pts from shards to
        // hazards. Mix is now 33% drone / 30% shard / 22% firewall /
        // 15% trace (was 30/35/20/15).
        let roll = Int.random(in: 0..<100)
        let kind: ObstacleKind
        let lanes: [Int]
        let allLanes = Array(0..<laneCount)
        if roll < 33 {
            kind = .drone
            lanes = [Int.random(in: 0..<laneCount)]
        } else if roll < 63 {
            kind = .dataShard
            lanes = [Int.random(in: 0..<laneCount)]
        } else if roll < 85 {
            kind = .firewall                 // 22% total
            // 50/50 split between full-field walls (must JUMP) and partial
            // 3-lane walls (DODGE by sliding into a free lane OR jump).
            // Adds variety + lets the player use horizontal movement to
            // beat firewalls, not just the jump button.
            if Bool.random() {
                lanes = allLanes
            } else {
                let start = Int.random(in: 0...(laneCount - 3))
                lanes = [start, start + 1, start + 2]
            }
        } else {
            kind = .traceBeam                // 15% — unchanged
            let start = Int.random(in: 0..<(laneCount - 1))
            lanes = [start, start + 1]
        }
        obstacles.append(Obstacle(z: 0, lanes: lanes, kind: kind))
    }

    // MARK: - Init / lifecycle

    private func initialise() {
        // Start in the center lane of however many lanes are configured.
        let center = laneCount / 2
        playerLane = center
        playerLaneVisual = CGFloat(center)
        playerJumpY = 0
        playerJumpVel = 0
        playerWalkFrame = 0
        obstacles = []
        dataFragments = 0
        hits = 0
        traceBar = 0
        distance = 0
        speed = baseSpeed
        gameOver = false
        didWin = false
        invulnSeconds = 0
        ringScroll = 0
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
        // Compute mini-game score on win and record it in the mission stats
        // store. Score = (fragments × 50) + bonus for unused HP + bonus for
        // unfilled trace bar. ~1000 cap on a flawless run.
        if success, let id = gameState.currentMissionDisplayId {
            let hpBonus = max(0, (maxHits - hits) * 80)
            let traceBonus = Int(max(0, (1.0 - traceBar) * 200))
            let score = dataFragments * 50 + hpBonus + traceBonus
            MissionStatsStore.shared.recordMiniGameScore(missionId: id, score: score)
        }
        cancelTimers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            chiptune?.stop()
            chiptune = nil
            onComplete(success)
        }
    }

    // MARK: - Code rain

    private func makeRainColumn(resetTop: Bool = false) -> RainColumn {
        let pool = LaneRunnerMiniGame.glyphPool
        let len = Int.random(in: 6...12)
        var glyphs: [String] = []
        for _ in 0..<len { glyphs.append(pool.randomElement() ?? "0") }
        return RainColumn(
            x: CGFloat.random(in: 8...380),
            headY: resetTop ? CGFloat.random(in: -120 ... -10) : CGFloat.random(in: -80...420),
            glyphs: glyphs,
            speed: CGFloat.random(in: 1.2...3.2)
        )
    }
}
