import SwiftUI
import Combine

/// PACKET ROUTER — Mission 5's data-extraction mini-game.
///
/// Premise: a circuit-board network of glowing nodes connected by edges.
/// Your data packet starts at the entry node (bottom-left); the target
/// node (top-right) is the data core. Tap an adjacent node to hop the
/// packet there. Two ICE programs patrol the same network; if an ICE lands
/// on your packet's node, you take a hit.
///
/// Some nodes are SHIELDED (cyan ring) — sitting there blocks ICE from
/// hopping onto you for one tick. Reach the target before 5 hits or the
/// trace bar fills.
///
/// Inputs (touch-only):
///   • Tap an adjacent node  → hop the packet there
///   • Tap the current node  → wait one tick (ICE still moves)
struct PacketRouterMiniGame: View {
    @ObservedObject var gameState: GameState
    let onComplete: (Bool) -> Void

    // MARK: - Tuning

    /// Eased twice — playtest still says it's tough. Each knob loosened
    /// another step: more hits, slower trace, slower ICE, more grace.
    private let maxHits = 5
    /// How fast the trace bar drifts up (per second).
    /// History: 0.018 → 0.012 → 0.016 → 0.012 → 0.009 → 0.013 (playtest:
    /// too easy after the easing pass — pushed back up).
    private let traceDrift: CGFloat = 0.013
    /// ICE moves once every this many seconds.
    /// History: 1.10 → 1.30 → 1.00 → 1.25 → 1.5 → 1.15 (re-tightened).
    private let iceTickSeconds: Double = 1.15
    /// Grace period at start of run before ICE moves at all.
    /// History: 1.5s → 2.5s → 3.0s → 2.0s (re-tightened).
    private let iceGraceSeconds: Double = 2.0

    // MARK: - Network model

    struct Node: Identifiable {
        let id: Int
        var pos: CGPoint           // normalised 0..1 in board coords
        var isShielded: Bool       // cyan-ring node — ICE can't hop onto it
        var isEntry: Bool
        var isTarget: Bool
    }

    struct Edge: Hashable {
        let a: Int
        let b: Int
        // Treat (a,b) and (b,a) as same edge for adjacency lookup.
        static func key(_ a: Int, _ b: Int) -> Edge {
            return a < b ? Edge(a: a, b: b) : Edge(a: b, b: a)
        }
    }

    // MARK: - State

    @State private var nodes: [Node] = []
    @State private var edges: [Edge] = []
    @State private var packetNodeId: Int = 0
    @State private var iceNodeIds: [Int] = []     // ICE program positions
    @State private var hits: Int = 0
    @State private var traceBar: CGFloat = 0
    @State private var packetTrail: [Int] = []    // recent packet path for visualisation
    @State private var gameOver: Bool = false
    @State private var didWin: Bool = false

    @State private var iceTimer: AnyCancellable?
    @State private var pulseTimer: AnyCancellable?
    @State private var rainTimer: AnyCancellable?
    @State private var pulseTime: Double = 0
    @State private var elapsed: Double = 0
    @State private var elapsedTimer: AnyCancellable?
    @State private var codeRain: [RainColumn] = []
    @State private var chiptune: ChiptunePlayer? = nil
    @State private var showBriefing: Bool = true

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
                boardArea
                hud
                touchHint
            }
            .padding(.bottom, 28)

            if showBriefing {
                MiniGameBriefing(
                    title: "PACKET ROUTING",
                    subtitle: "NETWORK BREACH PROTOCOL",
                    accent: Color(hex: "FFCC00"),
                    rules: [
                        BriefingRule(
                            iconName: "circle.grid.cross.fill",
                            color: Color(hex: "00FFCC"),
                            title: "TAP NODES TO MOVE",
                            detail: "You are the cyan packet (P). Tap a connected node — its edge glows yellow — to hop the packet there."
                        ),
                        BriefingRule(
                            iconName: "shield.lefthalf.fill",
                            color: Color(hex: "00FFCC"),
                            title: "CYAN RINGS = SAFE",
                            detail: "Shielded nodes (cyan halo) block ICE programs from hopping onto them. Use them as rest stops."
                        ),
                        BriefingRule(
                            iconName: "exclamationmark.octagon.fill",
                            color: Color(hex: "FF3344"),
                            title: "DODGE THE ICE",
                            detail: "Red diamonds chase your packet. Reach the magenta CORE node (top-center). 5 hits or full trace = burned."
                        ),
                    ],
                    onStart: { showBriefing = false }
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

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "FFCC00"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6))
                Text("// PACKET ROUTING")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FFCC00"))
                Circle().fill(Color(hex: "FF3344"))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(pulseTime * 6 + .pi))
            }
            Text("ROUTE PACKET TO THE CORE — DODGE ICE")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    private var boardArea: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color(hex: "020812"))
                    .overlay(Rectangle().stroke(Color(hex: "FFCC00").opacity(0.30), lineWidth: 1))
                    .overlay(Rectangle().stroke(Color(hex: "FF3344").opacity(0.10), lineWidth: 3))

                Canvas { ctx, size in
                    drawCodeRain(ctx: ctx, size: size)
                    drawScanlines(ctx: ctx, size: size)
                    drawCircuitGrid(ctx: ctx, size: size)
                    drawEdges(ctx: ctx, size: size)
                    drawNodes(ctx: ctx, size: size)
                    drawPacket(ctx: ctx, size: size)
                    drawICE(ctx: ctx, size: size)
                }

                if gameOver {
                    Color.black.opacity(0.78)
                    VStack(spacing: 6) {
                        Text(didWin ? "PACKET DELIVERED" : "ICE GOT THE PACKET")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(didWin ? Color(hex: "00FFCC") : Color(hex: "FF3344"))
                        Text(didWin ? "// CORE BREACHED" : "// ROUTE COMPROMISED")
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .padding(.horizontal, 8)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            statusBlock(label: "PATH",
                        value: "\(shortestPathLength(from: packetNodeId, to: targetNodeId)) HOPS",
                        color: Color(hex: "FFCC00"))
            statusBlock(label: "HITS",
                        value: "\(hits) / \(maxHits)",
                        color: Color(hex: "FF3344"))
            statusBlock(label: "ICE",
                        value: "\(iceNodeIds.count)",
                        color: Color(hex: "FF8833"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var touchHint: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TAP TO ROUTE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                Text("Tap an adjacent node. Cyan rings = shielded.")
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

    // MARK: - Network construction

    /// Pre-defined node positions on a 0..1 grid. The layout is hand-tuned to
    /// look like a circuit board with multiple paths from entry to target.
    /// Returns (nodes, edges).
    private func buildNetwork() -> (nodes: [Node], edges: [Edge]) {
        // 12 nodes laid out on a hex-ish grid
        let positions: [(CGFloat, CGFloat)] = [
            (0.12, 0.85),  // 0  ENTRY (bottom-left)
            (0.32, 0.78),  // 1
            (0.52, 0.85),  // 2
            (0.72, 0.78),  // 3  (right column near bottom)
            (0.20, 0.55),  // 4
            (0.42, 0.55),  // 5  (mid)
            (0.65, 0.55),  // 6
            (0.85, 0.55),  // 7
            (0.30, 0.30),  // 8
            (0.55, 0.30),  // 9  (mid-upper)
            (0.78, 0.30),  // 10
            (0.50, 0.12),  // 11 TARGET (top center) — data core
        ]
        var newNodes: [Node] = []
        for (i, (x, y)) in positions.enumerated() {
            newNodes.append(Node(
                id: i,
                pos: CGPoint(x: x, y: y),
                // Shielded nodes scattered to give the player safe rest stops.
                isShielded: [4, 6, 9].contains(i),
                isEntry: i == 0,
                isTarget: i == 11
            ))
        }
        // Edges — multiple paths up the board so player has choice
        let pairs: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3),                           // bottom row
            (0, 4), (1, 4), (1, 5), (2, 5), (3, 5), (3, 6), (3, 7),  // bottom→mid
            (4, 5), (5, 6), (6, 7),                           // mid row
            (4, 8), (5, 8), (5, 9), (6, 9), (6, 10), (7, 10), // mid→top
            (8, 9), (9, 10),                                  // top row
            (8, 11), (9, 11), (10, 11),                       // top→target
        ]
        let newEdges = pairs.map { Edge.key($0.0, $0.1) }
        return (newNodes, newEdges)
    }

    private var targetNodeId: Int { nodes.first(where: { $0.isTarget })?.id ?? 11 }

    private func neighbors(of nodeId: Int) -> [Int] {
        var result: [Int] = []
        for e in edges {
            if e.a == nodeId { result.append(e.b) }
            else if e.b == nodeId { result.append(e.a) }
        }
        return result
    }

    /// BFS shortest-path hop count between two nodes (used for HUD display).
    private func shortestPathLength(from start: Int, to end: Int) -> Int {
        if start == end { return 0 }
        var visited: Set<Int> = [start]
        var queue: [(Int, Int)] = [(start, 0)]
        while !queue.isEmpty {
            let (cur, dist) = queue.removeFirst()
            for n in neighbors(of: cur) where !visited.contains(n) {
                if n == end { return dist + 1 }
                visited.insert(n)
                queue.append((n, dist + 1))
            }
        }
        return -1
    }

    // MARK: - Drawing

    private func boardPos(_ node: Node, in size: CGSize) -> CGPoint {
        let pad: CGFloat = 30
        let w = size.width - pad * 2
        let h = size.height - pad * 2
        return CGPoint(x: pad + node.pos.x * w, y: pad + node.pos.y * h)
    }

    private func drawCodeRain(ctx: GraphicsContext, size: CGSize) {
        for col in codeRain {
            for (i, g) in col.glyphs.enumerated() {
                let y = col.headY - CGFloat(i) * 14
                guard y >= -14, y <= size.height + 14 else { continue }
                let alpha = max(0, 1.0 - Double(i) * 0.08)
                let color = i == 0
                    ? Color.white.opacity(alpha * 0.6)
                    : Color(hex: "FFCC00").opacity(alpha * 0.30)
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
                with: .color(Color(hex: "FFCC00").opacity(alpha))
            )
            y += 3
        }
    }

    /// Faint circuit-board grid background.
    private func drawCircuitGrid(ctx: GraphicsContext, size: CGSize) {
        let stride: CGFloat = 24
        let color = Color(hex: "FFCC00").opacity(0.05)
        var x: CGFloat = 0
        while x < size.width {
            ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                       with: .color(color), lineWidth: 0.5)
            x += stride
        }
        var y: CGFloat = 0
        while y < size.height {
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                       with: .color(color), lineWidth: 0.5)
            y += stride
        }
    }

    private func drawEdges(ctx: GraphicsContext, size: CGSize) {
        for e in edges {
            let a = nodes[e.a], b = nodes[e.b]
            let pa = boardPos(a, in: size)
            let pb = boardPos(b, in: size)
            let inPath = packetTrail.contains(where: { $0 == e.a }) && packetTrail.contains(where: { $0 == e.b })
            // Highlight edges adjacent to the packet's current node
            let neighbors = neighbors(of: packetNodeId)
            let isCurrentEdge = (e.a == packetNodeId && neighbors.contains(e.b)) ||
                                (e.b == packetNodeId && neighbors.contains(e.a))
            let baseAlpha: Double = isCurrentEdge ? 0.85 : 0.30
            let color: Color = inPath
                ? Color(hex: "00FFCC")
                : (isCurrentEdge ? Color(hex: "FFCC00") : Color(hex: "FFCC00").opacity(0.5))
            ctx.stroke(
                Path { p in p.move(to: pa); p.addLine(to: pb) },
                with: .color(color.opacity(baseAlpha)),
                lineWidth: isCurrentEdge ? 1.6 : 1.0
            )
        }
    }

    private func drawNodes(ctx: GraphicsContext, size: CGSize) {
        let neighbors = Set(neighbors(of: packetNodeId))
        for node in nodes {
            let pos = boardPos(node, in: size)
            let radius: CGFloat = node.isTarget ? 16 : 11
            let isCurrent = node.id == packetNodeId
            let isAdjacent = neighbors.contains(node.id)

            let fillColor: Color
            let strokeColor: Color
            if node.isTarget {
                fillColor = Color(hex: "FF00AA").opacity(0.8)
                strokeColor = .white
            } else if node.isShielded {
                fillColor = Color(hex: "00FFCC").opacity(0.18)
                strokeColor = Color(hex: "00FFCC")
            } else {
                fillColor = Color(hex: "FFCC00").opacity(0.18)
                strokeColor = Color(hex: "FFCC00")
            }

            // Outer ring for adjacency hint
            if isAdjacent && !node.isTarget {
                let halo = CGRect(x: pos.x - radius - 6, y: pos.y - radius - 6,
                                  width: (radius + 6) * 2, height: (radius + 6) * 2)
                ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "FFCC00").opacity(0.18)))
            }
            // Pulsing ring for shielded nodes
            if node.isShielded {
                let p = 1.0 + 0.20 * sin(pulseTime * 5)
                let r = radius + CGFloat(8 * p)
                let ring = CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)
                ctx.stroke(Path(ellipseIn: ring),
                           with: .color(Color(hex: "00FFCC").opacity(0.40)),
                           lineWidth: 1)
            }
            let nodeRect = CGRect(x: pos.x - radius, y: pos.y - radius,
                                  width: radius*2, height: radius*2)
            ctx.fill(Path(ellipseIn: nodeRect), with: .color(fillColor))
            ctx.stroke(Path(ellipseIn: nodeRect),
                       with: .color(strokeColor),
                       lineWidth: isCurrent ? 2.0 : 1.2)
            // Target node sparkle
            if node.isTarget {
                let s = CGRect(x: pos.x - 1.5, y: pos.y - 1.5, width: 3, height: 3)
                ctx.fill(Path(ellipseIn: s), with: .color(.white))
                ctx.draw(
                    Text("CORE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "FF00AA")),
                    at: CGPoint(x: pos.x, y: pos.y + radius + 8)
                )
            }
            if node.isEntry {
                ctx.draw(
                    Text("ENTRY")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "FFCC00").opacity(0.85)),
                    at: CGPoint(x: pos.x, y: pos.y + radius + 8)
                )
            }
        }
    }

    private func drawPacket(ctx: GraphicsContext, size: CGSize) {
        guard packetNodeId < nodes.count else { return }
        let pos = boardPos(nodes[packetNodeId], in: size)
        // Outer halo
        let halo = CGRect(x: pos.x - 18, y: pos.y - 18, width: 36, height: 36)
        ctx.fill(Path(ellipseIn: halo), with: .color(Color(hex: "00FFCC").opacity(0.30)))
        // Pulsing ring
        let pScale = 1.0 + 0.18 * sin(pulseTime * 6)
        let ring = CGRect(x: pos.x - 14 * pScale, y: pos.y - 14 * pScale,
                          width: 28 * pScale, height: 28 * pScale)
        ctx.stroke(Path(ellipseIn: ring),
                   with: .color(Color(hex: "00FFCC").opacity(0.7)),
                   lineWidth: 1.5)
        // Body
        let body = CGRect(x: pos.x - 7, y: pos.y - 7, width: 14, height: 14)
        ctx.fill(Path(ellipseIn: body), with: .color(Color(hex: "00FFCC")))
        ctx.stroke(Path(ellipseIn: body), with: .color(.white), lineWidth: 1.2)
        // "P" letter
        ctx.draw(
            Text("P").font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(.black),
            at: pos
        )
    }

    private func drawICE(ctx: GraphicsContext, size: CGSize) {
        for (idx, iceId) in iceNodeIds.enumerated() {
            guard iceId < nodes.count else { continue }
            let pos = boardPos(nodes[iceId], in: size)
            let isAdjacent = neighbors(of: packetNodeId).contains(iceId)
            let color: Color = isAdjacent ? Color(hex: "FF3344") : Color(hex: "FF8833")
            // Halo
            let halo = CGRect(x: pos.x - 20, y: pos.y - 20, width: 40, height: 40)
            ctx.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.18)))
            // Sharp diamond body
            var diamond = Path()
            diamond.move(to: CGPoint(x: pos.x, y: pos.y - 9))
            diamond.addLine(to: CGPoint(x: pos.x + 9, y: pos.y))
            diamond.addLine(to: CGPoint(x: pos.x, y: pos.y + 9))
            diamond.addLine(to: CGPoint(x: pos.x - 9, y: pos.y))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(color))
            ctx.stroke(diamond, with: .color(.white), lineWidth: 1.2)
            // ICE number tag
            ctx.draw(
                Text("ICE\(idx+1)")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundColor(color),
                at: CGPoint(x: pos.x, y: pos.y + 16)
            )
        }
    }

    // MARK: - Input

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard !gameOver, !showBriefing else { return }
        // Find nearest node within hit radius
        var bestId: Int? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for n in nodes {
            let pos = boardPos(n, in: size)
            let d = hypot(point.x - pos.x, point.y - pos.y)
            if d < bestDist {
                bestDist = d
                bestId = n.id
            }
        }
        // Bumped 2026-05 (was 28) — wider node-tap radius so taps near a
        // node count even with imprecise fingertip placement.
        guard let id = bestId, bestDist < 36 else { return }

        // Allow re-tapping the current node to "wait"
        if id == packetNodeId {
            chiptune?.sfxNodeHop()
            HapticsManager.shared.buttonTap()
            // Force one ICE tick immediately so waiting still costs time
            tickICE()
            return
        }
        // Otherwise must be a neighbor
        guard neighbors(of: packetNodeId).contains(id) else {
            chiptune?.sfxRingMiss()
            return
        }

        packetTrail.append(packetNodeId)
        if packetTrail.count > 6 { packetTrail.removeFirst(packetTrail.count - 6) }
        packetNodeId = id
        chiptune?.sfxNodeHop()
        SFXManager.shared.play("packet_route_hop", volume: 0.6)
        HapticsManager.shared.buttonTap()

        // Check immediate collision with ICE
        if iceNodeIds.contains(packetNodeId) {
            takeHit()
            return
        }
        // Win check
        if packetNodeId == targetNodeId {
            chiptune?.sfxWin()
            SFXManager.shared.play("terminal_correct", volume: 0.75)
            SFXManager.shared.play("mainframe_breach", volume: 0.65)
            finishGame(success: true)
            return
        }
        // Player move triggers an ICE tick — keeps tension high.
        tickICE()
    }

    // MARK: - Tick / lifecycle

    private func startTimers() {
        pulseTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in pulseTime += 0.05 }
        // ICE moves on its own timer too (so dawdling at a node still eventually
        // gets you caught).
        iceTimer = Timer.publish(every: iceTickSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tickICE() }
        elapsedTimer = Timer.publish(every: 0.10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard !showBriefing else { return }
                elapsed += 0.10
                let prev = traceBar
                traceBar += traceDrift * 0.10
                // Trace-warning sting fires once when the trace bar first
                // crosses the danger threshold; stops on game end (cleared
                // alongside the chiptune in cancelTimers).
                if prev < 0.7 && traceBar >= 0.7 {
                    SFXManager.shared.playLoop("trace_warning", volume: 0.4)
                }
                if traceBar >= 1.0 {
                    SFXManager.shared.stopLoop("trace_warning")
                    SFXManager.shared.play("terminal_wrong", volume: 0.7)
                    finishGame(success: false)
                }
            }
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
        iceTimer?.cancel()
        pulseTimer?.cancel()
        rainTimer?.cancel()
        elapsedTimer?.cancel()
    }

    private func tickICE() {
        guard !gameOver, !showBriefing else { return }
        // Grace period — ICE stays put for the first iceGraceSeconds after
        // briefing dismiss so the player can plan their opening move.
        guard elapsed >= iceGraceSeconds else { return }
        var newPositions: [Int] = []
        for (i, iceId) in iceNodeIds.enumerated() {
            // ICE prefers to step toward the packet — pick the neighbor with
            // shortest path to the packet's current node. With 30% randomness
            // so the player can plan around predictable ICE.
            let n = neighbors(of: iceId).filter { node in
                // Don't stack on top of another ICE
                !newPositions.contains(node) && !iceNodeIds.enumerated().contains(where: { $0.offset != i && $0.element == node })
            }
            guard !n.isEmpty else {
                newPositions.append(iceId)
                continue
            }
            // Don't hop onto a shielded node (player's safe zones). No
            // player-position exception — the old `|| $0 == packetNodeId`
            // let ICE breach a shield exactly when the player rested on it,
            // so the advertised "rest stop" mechanic never actually worked.
            let allowed = n.filter { !nodes[$0].isShielded }
            let choices = allowed.isEmpty ? n : allowed
            let next: Int
            if Double.random(in: 0..<1) < 0.3 {
                next = choices.randomElement() ?? iceId
            } else {
                next = choices.min { a, b in
                    shortestPathLength(from: a, to: packetNodeId)
                        < shortestPathLength(from: b, to: packetNodeId)
                } ?? iceId
            }
            newPositions.append(next)
        }
        iceNodeIds = newPositions

        // Warning chirp if any ICE landed adjacent to the packet
        if iceNodeIds.contains(where: { neighbors(of: packetNodeId).contains($0) }) {
            chiptune?.sfxICEAlert()
        }

        // Check collision: ICE stepped onto packet node?
        if iceNodeIds.contains(packetNodeId) {
            takeHit()
        }
    }

    private func takeHit() {
        hits += 1
        chiptune?.sfxHit()
        SFXManager.shared.play("packet_route_caught", volume: 0.65)
        HapticsManager.shared.playerKilled()
        traceBar = min(1.0, traceBar + 0.20)
        // Bump the offending ICE off the packet's node — push to a random
        // neighbor — so the player can keep playing instead of dying instantly.
        for (i, iceId) in iceNodeIds.enumerated() where iceId == packetNodeId {
            let alt = neighbors(of: iceId).filter { $0 != packetNodeId }.randomElement()
            iceNodeIds[i] = alt ?? iceId
        }
        if hits >= maxHits {
            chiptune?.sfxLose()
            SFXManager.shared.play("terminal_wrong", volume: 0.7)
            finishGame(success: false)
        }
    }

    private func initialise() {
        let net = buildNetwork()
        nodes = net.nodes
        edges = net.edges
        packetNodeId = nodes.first(where: { $0.isEntry })?.id ?? 0
        packetTrail = []
        // Two ICE programs, spawn at mid-board nodes opposite each other
        // ICE start positions — moved 2026-05 from [3, 8] to [7, 10].
        // Old positions were only 2-3 hops from the packet's ENTRY, which
        // meant ICE could reach the packet in 2 ticks (~2.6s) before the
        // player even finished reading the briefing. Both new positions are
        // a guaranteed 3 hops away — gives the player enough time to plan
        // and execute the first move.
        // Three ICE programs (was 2). With faster ticks + 3 chasers
        // there's real pressure on the player. Positions chosen so they
        // close on the packet from different directions: top-right (7),
        // top-left (8), and mid-board (5) — packet has to pick a route
        // that doesn't intersect all three.
        iceNodeIds = [7, 8, 5]
        hits = 0
        traceBar = 0
        elapsed = 0
        gameOver = false
        didWin = false
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
        SFXManager.shared.stopLoop("trace_warning")  // always silence the alarm
        // Score = base 1000 - 200 per hit - 5 per second elapsed.
        if success, let id = gameState.currentMissionDisplayId {
            let score = max(0, 1000 - hits * 200 - Int(elapsed * 5))
            MissionStatsStore.shared.recordMiniGameScore(missionId: id, score: score)
        }
        cancelTimers()
        // Linger on a WIN, snap back fast on a loss/bail.
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 1.5 : 0.9)) {
            chiptune?.stop()
            chiptune = nil
            onComplete(success)
        }
    }

    private func makeRainColumn(resetTop: Bool = false) -> RainColumn {
        let pool = PacketRouterMiniGame.rainPool
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
