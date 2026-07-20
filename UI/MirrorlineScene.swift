import SwiftUI
import Combine

// MARK: - M2.5 "Mirrorline" — Sable solo astral sigil-tracing
//
// Real-time gesture-combat scene. Sable is stationary in the center of
// the screen; astral predators drift toward her from the edges. The
// player traces ELEMENTAL SIGILS with one finger to banish them.
//
// FLOW
//   .entering       — descent narration / fade-in
//   .veilTutorial   — Layer 1: single enemies, one sigil each, teaches the loop
//   .staticEscalation — Layer 2: multi-enemy, faster, flickering weaknesses
//   .mirrorBoss     — Layer 3: Mirror-Sable, 3 phases
//   .victory / .defeat — end states
//
// SIGILS
//   ○ Circle  → WARD          (cyan,    AOE banish)              vs Shade
//   △ Triangle → MANABOLT     (red,     single-target heavy)     vs Wraith
//   ↓ Vertical → ICE LANCE    (pale,    line damage)             vs Skitter
//   ⌇ Zigzag  → LIGHTNING     (yellow,  chains to 3)             vs Cluster
//   ◌ Spiral  → SOUL DRAIN    (magenta, damage + heal)           vs Hungerling
//
// Correct sigil = full damage + banish. Wrong sigil = chip damage to
// the nearest enemy + 1 self-chip to Sable as a flow penalty.
//
// NOTE: Sprite assets, FX textures, and music are still being generated;
// the scene renders text-fallback rectangles where sprites haven't shipped
// so it's playable and testable today.

// MARK: - Sigil types + recognition

enum SigilType: String, CaseIterable {
    case ward       // ○
    case manabolt   // △
    case iceLance   // ↓
    case lightning  // ⌇
    case soulDrain  // ◌
    case unknown

    var label: String {
        switch self {
        case .ward:      return "WARD"
        case .manabolt:  return "MANABOLT"
        case .iceLance:  return "ICE LANCE"
        case .lightning: return "LIGHTNING"
        case .soulDrain: return "SOUL DRAIN"
        case .unknown:   return "—"
        }
    }
    /// Color tint on the gesture trail + the banish FX.
    var hex: String {
        switch self {
        case .ward:      return "00DDFF"
        case .manabolt:  return "FF3344"
        case .iceLance:  return "AACCEE"
        case .lightning: return "FFD633"
        case .soulDrain: return "FF44AA"
        case .unknown:   return "AAAAAA"
        }
    }
    /// Glyph rendered next to enemies (debug + tutorial hint).
    /// Kept for feedback strings where mixing text + symbols is awkward.
    var glyph: String {
        switch self {
        case .ward:      return "○"
        case .manabolt:  return "△"
        case .iceLance:  return "↓"
        case .lightning: return "↯"   // was ⌇ — many system fonts lack it
        case .soulDrain: return "@"   // was ◌ — dotted-circle renders invisibly
        case .unknown:   return "?"
        }
    }

    /// Optional SF Symbol name for the sigil. Used by `sigilIcon(_:)` so
    /// the prominent UI renderings (tutorial row, boss prompt) never blank
    /// on a missing glyph the way the raw Unicode characters can.
    var systemImage: String? {
        switch self {
        case .ward:      return "circle"
        case .manabolt:  return "triangle"
        case .iceLance:  return "arrow.down"
        case .lightning: return "bolt.fill"
        case .soulDrain: return "hurricane"
        case .unknown:   return nil
        }
    }
}

/// Renders a sigil as an SF Symbol where available, falling back to the
/// text glyph. Single source of truth for "show this sigil somewhere
/// prominent" so all the places using it stay visually consistent.
@ViewBuilder
private func sigilIcon(_ sig: SigilType, size: CGFloat, weight: Font.Weight = .black) -> some View {
    if let sym = sig.systemImage {
        Image(systemName: sym)
            .font(.system(size: size, weight: weight))
    } else {
        Text(sig.glyph)
            .font(.system(size: size, weight: weight))
    }
}

/// Heuristic gesture classifier — analyses a stroke's point cloud and
/// returns the best-matching sigil. Generous on accuracy so a wobbly
/// circle still classifies as a circle. Refine the thresholds as we
/// playtest; the public interface is stable.
enum SigilRecognizer {

    static func classify(points: [CGPoint]) -> SigilType {
        guard points.count >= 8 else { return .unknown }

        // ---- Basic bbox + path-length features ----
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = max(1, maxX - minX)
        let height = max(1, maxY - minY)
        let bbDiag = sqrt(width * width + height * height)
        guard bbDiag > 40 else { return .unknown }       // too small / a tap

        var pathLen: CGFloat = 0
        for i in 1..<points.count {
            pathLen += hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y)
        }
        let startEndDist = hypot(points.last!.x - points.first!.x,
                                 points.last!.y - points.first!.y)
        let closure = startEndDist / bbDiag   // 0 = closed loop, 1 = open straight line
        let aspect  = height / width
        let netDY   = points.last!.y - points.first!.y
        let netDX   = points.last!.x - points.first!.x

        // ---- Heading-based features ----
        // Sampled headings between every Nth point, with a 3px minimum step
        // so micro-tremor doesn't generate phantom heading-deltas (this was
        // the main source of "circle accidentally classified as triangle"
        // when a player's finger jittered).
        let segLen = max(1, points.count / 24)
        var headings: [CGFloat] = []
        for i in Swift.stride(from: segLen, to: points.count, by: segLen) {
            let dx = points[i].x - points[i - segLen].x
            let dy = points[i].y - points[i - segLen].y
            if hypot(dx, dy) > 3 { headings.append(atan2(dy, dx)) }
        }
        var horizFlips = 0
        var vertFlips = 0
        var sharpCorners = 0      // heading-deltas > 95°
        var totalTurning: CGFloat = 0
        var prevDX: CGFloat = 0
        var prevDY: CGFloat = 0
        // SIGNED corners — every significant turn (> 50°) recorded WITH its
        // rotational direction (+ left / − right). This is the key to telling
        // a triangle from lightning: a triangle turns the SAME way at every
        // corner (all +, or all −), while a lightning zigzag ALTERNATES
        // (+, −, +). A circle has no big corners at all. Far more robust than
        // counting corners against a single angle threshold.
        var corners: [CGFloat] = []
        let cornerGate = CGFloat.pi * (50.0 / 180.0)
        for i in 1..<headings.count {
            var delta = headings[i] - headings[i-1]
            while delta >  .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            totalTurning += abs(delta)
            if abs(delta) > .pi * (95.0 / 180.0) { sharpCorners += 1 }
            if abs(delta) > cornerGate { corners.append(delta) }
            // hard horizontal/vertical reversals — used for zigzag
            let dx = cos(headings[i])
            let dy = sin(headings[i])
            if dx * prevDX < -0.3 { horizFlips += 1 }
            if dy * prevDY < -0.3 { vertFlips += 1 }
            prevDX = dx
            prevDY = dy
        }
        let maxCorner = corners.map { abs($0) }.max() ?? 0
        // Count direction reversals between consecutive significant corners.
        var signAlternations = 0
        for i in 1..<max(1, corners.count) where i < corners.count {
            if (corners[i] > 0) != (corners[i-1] > 0) { signAlternations += 1 }
        }

        // ---- 1. Vertical stroke → Ice Lance (top-to-bottom slash) ----
        if aspect > 2.0 && netDY > height * 0.55 && sharpCorners <= 1 {
            return .iceLance
        }

        // ---- 2. Zigzag → Lightning (CHECK BEFORE TRIANGLE) ----
        // The signature is ALTERNATING corners (zig then zag), regardless of
        // how closed the shape ends up — a Z/N reverses rotational direction
        // at least once. Backed up by the old horizontal/vertical flip test.
        if corners.count >= 2 && pathLen > bbDiag * 1.1 &&
           (signAlternations >= 1 ||
            (horizFlips >= 1 && abs(netDX) > width * 0.30) ||
            (vertFlips  >= 1 && abs(netDY) > height * 0.30)) {
            return .lightning
        }

        // ---- 3. Triangle → Manabolt ----
        // Angular CLOSED shape whose corners all turn the SAME direction
        // (signAlternations == 0). The consistent-rotation test is what stops
        // a slightly-open triangle from being mistaken for lightning above,
        // and the real corners (maxCorner) stop a smooth circle landing here.
        if corners.count >= 2 && signAlternations == 0 && closure < 0.55 &&
           maxCorner > .pi * (55.0 / 180.0) && pathLen > bbDiag * 1.15 {
            return .manabolt
        }

        // ---- 4. Circle → Ward (smooth closed/near-closed loop) ----
        // No sharp corners + lots of smooth turning. maxCorner gate keeps an
        // angular triangle out even if its corners happened to read soft.
        let bboxCircumference = .pi * (width + height) / 2
        if closure < 0.35 && pathLen > bboxCircumference * 0.55
           && sharpCorners <= 1 && maxCorner < .pi * (80.0 / 180.0)
           && totalTurning > .pi * 1.3 {
            return .ward
        }

        // ---- 5. Soul Drain → an OPEN CURVED SWEEP ----
        if aspect < 1.0 && abs(netDX) > width * 0.45 && closure > 0.25
           && sharpCorners == 0 && totalTurning > .pi * 0.6 {
            return .soulDrain
        }

        // ---- 6. Fallback: ambiguous-but-cornered → Manabolt ----
        if corners.count >= 1 && closure > 0.15 && pathLen > bbDiag * 1.3 {
            return .manabolt
        }

        return .unknown
    }
}

// MARK: - Astral enemy archetypes

enum AstralEnemy: String, CaseIterable {
    case shade      // weak to ward
    case wraith     // weak to manabolt
    case skitter    // weak to iceLance
    case cluster    // weak to lightning
    case hungerling // weak to soulDrain

    var weakness: SigilType {
        switch self {
        case .shade:      return .ward
        case .wraith:     return .manabolt
        case .skitter:    return .iceLance
        case .cluster:    return .lightning
        case .hungerling: return .soulDrain
        }
    }
    var label: String {
        switch self {
        case .shade:      return "SHADE"
        case .wraith:     return "WRAITH"
        case .skitter:    return "SKITTER"
        case .cluster:    return "CLUSTER"
        case .hungerling: return "HUNGERLING"
        }
    }
    /// Approach speed in normalized arena units / second.
    /// 1.0 = takes ~1s to cross from spawn edge to center.
    var approachSpeed: Double {
        switch self {
        case .shade:      return 0.07   // slow drifter
        case .wraith:     return 0.10   // steady
        case .skitter:    return 0.18   // fast, mobile
        case .cluster:    return 0.08   // slow cluster
        case .hungerling: return 0.11   // bloated, mid-speed
        }
    }
}

/// A single live spirit on the arena. Position is normalized (-1, +1)
/// where (0,0) is Sable's center and (±1, ±1) is screen-edge corners.
struct AstralSpirit: Identifiable {
    let id = UUID()
    let kind: AstralEnemy
    var position: CGPoint        // -1...+1 in each axis
    var direction: CGVector      // unit vector toward center
    /// 0 = full health (still drifting); 1 = banished (fading out).
    var banished: Double = 0
    /// Brief red flash for a WRONG-sigil trace — decays on its own and does
    /// NOT cull the spirit (a wrong trace must not banish it; the old code
    /// nudged `banished`, which the tick then advanced to removal).
    var hitDing: Double = 0
    /// Static-layer flicker: re-rolls the weakness mid-approach so the
    /// player has to read the new icon. nil = no flicker.
    var flickerWeakness: SigilType?
    var spawnedAt: Date = Date()

    var effectiveWeakness: SigilType {
        flickerWeakness ?? kind.weakness
    }
}

// MARK: - Boss attack phases
//
// Drives what the boss is doing right now within whatever overall HP-phase
// (1/2/3) she's in. Each HP-phase reuses the same machine but with different
// timing and a different mechanic for the player to respond to.

private enum BossAttackPhase: Equatable {
    case idle           // between attacks — boss is just standing
    case castingP1      // P1: slow cast at Sable. Lands after windup unless interrupted.
    case castingP2      // P2: counter prompt — player traces opposing sigil.
    case projectingP3   // P3: ghost sigil shown — player traces it directly.
}

// MARK: - Scene

struct MirrorlineScene: View {
    @ObservedObject var manager: PhaseManager

    // MARK: Tuning

    private let maxHP: Int = 8
    private let killReward: Int = 0   // base score updates handled at end

    // MARK: Phase machine

    enum Stage: Equatable {
        case entering          // narrative fade-in / "DESCENDING" banner
        case veilTutorial      // Layer 1 — single-enemy waves
        case staticEscalation  // Layer 2 — multi-enemy, flicker
        case mirrorBoss        // Layer 3 — boss
        case victory
        case defeat
    }

    // MARK: State

    @State private var stage: Stage = .entering
    @State private var stageTimer: Double = 0
    @State private var playerHP: Int = 8

    /// Victory beat — once the boss HP hits 0 we hold on her banish sprite
    /// for a moment (so the player SEES the defeat) before the end overlay.
    @State private var bossDefeated = false
    @State private var bossBanishOpacity: Double = 1.0

    /// Currently-active astral spirits drifting in toward Sable.
    @State private var spirits: [AstralSpirit] = []
    /// Next spawn target time within current stage.
    @State private var nextSpawnAt: Double = 1.0
    /// How many spirits have spawned in the current layer (drives stage progression).
    @State private var spawnedThisStage: Int = 0
    /// Target spawn count to clear the current layer.
    @State private var spawnGoalThisStage: Int = 3

    // Gesture state — points are collected in screen space (not normalized).
    @State private var currentStrokePoints: [CGPoint] = []
    @State private var lastClassifiedSigil: SigilType = .unknown
    @State private var lastSigilLabelHold: Double = 0

    // Boss state (Mirror-Sable)
    @State private var bossPhase: Int = 1
    @State private var bossHP: Int = 12
    @State private var bossOpeningTimer: Double = 0    // counter-window after parry/dodge

    // Boss attack-phase machine. Drives the per-phase mechanic:
    //   P1 — slow cast at Sable (interrupt by banishing her summons)
    //   P2 — counter prompt: player traces opposing sigil
    //   P3 — mirror-trace: player traces the projected sigil
    @State private var bossAttackPhase: BossAttackPhase = .idle
    @State private var bossAttackTimer: Double = 0       // elapsed in current attack phase
    @State private var bossCastingSigil: SigilType = .unknown
    @State private var bossSummonCooldown: Double = 0
    @State private var bossCastWindupDuration: Double = 0   // how long the current windup is

    // Overlays
    @State private var bannerText: String = ""
    @State private var bannerExpires: Date = .distantPast
    @State private var tutorialDismissed: Bool = false
    @State private var feedbackText: String = ""
    @State private var feedbackColor: String = "FFFFFF"
    @State private var feedbackHold: Double = 0
    @State private var hitFlash: Double = 0
    @State private var endGameOver: Bool = false
    @State private var didWin: Bool = false

    // Ticker
    @State private var ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    @State private var lastFrameAt: Date = Date()

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backdropView
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Astral spirit layer
                spiritsLayer(geo: geo)

                // Mirror-Sable boss — anchored above-rear during boss stage
                if stage == .mirrorBoss {
                    mirrorSableView
                        .position(x: geo.size.width / 2, y: geo.size.height / 2 - 160)
                }

                // Sable center anchor. During the .mirrorBoss stage she moves
                // slightly down + left and shrinks 15% so her silhouette no
                // longer clashes with the towering Mirror-Sable above. Outside
                // the boss stage she stays centered at full scale.
                sableView
                    .scaleEffect(stage == .mirrorBoss ? 0.85 : 1.0)
                    .position(
                        x: geo.size.width / 2 + (stage == .mirrorBoss ? -28 : 0),
                        y: geo.size.height / 2 + (stage == .mirrorBoss ? 60 : 20)
                    )

                // Sigil trail — the player's currently-drawn stroke
                sigilTrail
                    .allowsHitTesting(false)

                // Boss attack prompt — sigil glyph + windup timer ring
                if stage == .mirrorBoss && bossAttackPhase != .idle {
                    bossAttackPromptOverlay
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.40)
                        .allowsHitTesting(false)
                }

                // HUD
                hudHeader.frame(width: geo.size.width)

                // Last-classified sigil readout (transient)
                if lastSigilLabelHold > 0 {
                    sigilReadout
                        .frame(width: geo.size.width)
                }

                if !bannerText.isEmpty { bannerOverlay }
                if feedbackHold > 0 { feedbackOverlay }
                if !tutorialDismissed && !endGameOver { tutorialOverlay }
                if endGameOver { endOverlay }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { v in
                        guard !endGameOver, tutorialDismissed else { return }
                        if currentStrokePoints.isEmpty {
                            currentStrokePoints.append(v.startLocation)
                        }
                        currentStrokePoints.append(v.location)
                    }
                    .onEnded { _ in
                        guard !endGameOver, tutorialDismissed else { return }
                        let pts = currentStrokePoints
                        currentStrokePoints = []
                        if pts.count >= 5 {
                            resolveSigil(SigilRecognizer.classify(points: pts))
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear { startMission() }
        .onReceive(ticker) { _ in tick() }
    }

    // MARK: Sprite resolvers

    /// Picks the right Sable frame based on what she's doing.
    /// Falls through to idle_0 as the default.
    private var sableSpriteName: String {
        if endGameOver && didWin    { return "sable_astral_victory_0" }
        if hitFlash > 0             { return "sable_astral_hit_0" }
        if lastSigilLabelHold > 0.6 { return "sable_astral_cast_0" }
        // Subtle breathing cycle between the two idle frames every ~1.4s
        let breath = Int(Date().timeIntervalSinceReferenceDate * 0.7) % 2
        return breath == 0 ? "sable_astral_idle_0" : "sable_astral_idle_1"
    }

    /// Picks the right Mirror-Sable frame based on her current AI state.
    /// Active casts/counters/stares use the specific pose; otherwise she
    /// alternates idle_0 / idle_1 for a slow breathing cycle.
    private var mirrorSableSpriteName: String {
        if endGameOver && didWin { return "mirror_sable_banish" }
        if bossHP <= 0           { return "mirror_sable_banish" }
        // Active attack-phase poses
        switch bossAttackPhase {
        case .castingP1:    return "mirror_sable_p1_cast"
        case .castingP2:    return "mirror_sable_p2_counter"
        case .projectingP3: return "mirror_sable_p3_stare"
        case .idle:
            // Slow breathe between attacks
            let breath = Int(Date().timeIntervalSinceReferenceDate * 0.55) % 2
            return breath == 0 ? "mirror_sable_idle_0" : "mirror_sable_idle_1"
        }
    }

    @ViewBuilder
    private var mirrorSableView: some View {
        if let img = BasementBrawlSpriteCache.shared.image(named: mirrorSableSpriteName) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 280)
                .opacity(bossDefeated ? bossBanishOpacity : (bossHP > 0 ? 1.0 : 0.0))
                // Pulsing chartreuse glow under her — sets her apart from
                // the green-hued minions she summons.
                .background(
                    Circle()
                        .fill(Color(hex: "BBFF44").opacity(0.18))
                        .frame(width: 240, height: 240)
                        .blur(radius: 24)
                )
        } else {
            // Pre-asset fallback
            VStack(spacing: 4) {
                Text("◇")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(Color(hex: "BBFF44"))
                Text("MIRROR-SABLE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "BBFF44"))
            }
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var backdropView: some View {
        let img: String = {
            switch stage {
            case .mirrorBoss:        return "m2_5_mirror"
            case .staticEscalation:  return "m2_5_static"
            default:                 return "m2_5_veil"
            }
        }()
        if UIImage(named: img) != nil {
            Image(img)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.25))
        } else {
            // Pre-asset fallback — gradient void
            LinearGradient(
                colors: [Color(hex: "0A0A1F"), Color(hex: "1A0A24"), Color(hex: "0A0A1F")],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func spiritsLayer(geo: GeometryProxy) -> some View {
        ForEach(spirits) { spirit in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            // Map normalized (-1...+1) to actual screen coords. Spawn radius
            // ≈ shorter screen dimension * 0.55 so they always come from
            // off-screen edges.
            let r = min(geo.size.width, geo.size.height) * 0.55
            let x = cx + spirit.position.x * r
            let y = cy + spirit.position.y * r

            spiritSprite(spirit)
                .position(x: x, y: y)
        }
    }

    @ViewBuilder
    private func spiritSprite(_ s: AstralSpirit) -> some View {
        let name = "\(s.kind.rawValue)_idle_0"
        ZStack {
            // Sprites live in the Sprites/frames/ folder reference, not the
            // asset catalog — same loader pattern as the brawl scene.
            if let img = BasementBrawlSpriteCache.shared.image(named: name) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                // Pre-asset fallback — glyph badge tinted to its weakness sigil
                ZStack {
                    Circle()
                        .fill(Color(hex: s.effectiveWeakness.hex).opacity(0.30))
                    Circle()
                        .stroke(Color(hex: s.effectiveWeakness.hex), lineWidth: 2)
                    VStack(spacing: 2) {
                        sigilIcon(s.effectiveWeakness, size: 32)
                            .foregroundColor(Color(hex: s.effectiveWeakness.hex))
                        Text(s.kind.label)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
        .frame(width: 80, height: 80)
        // CURRENT-weakness badge, ALWAYS shown. Floats DIRECTLY ABOVE the
        // sprite (playtest 2026-07-19: overlapping the head hid the art).
        // Without it, an art-rendered spirit gave no cue when its weakness
        // was static-scrambled — the player drew the kind's BASE weakness
        // and got "wrong sigil".
        .overlay(alignment: .top) {
            weaknessBadge(s)
                .offset(y: -32)
        }
        .opacity(1.0 - s.banished)
        .scaleEffect(1.0 - s.banished * 0.4)
        // Wrong-sigil ding: a brief red overlay that fades, leaving the
        // spirit fully alive.
        .overlay(
            Circle()
                .fill(Color(hex: "FF3344"))
                .opacity(s.hitDing * 0.5)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
    }

    /// The weakness badge shown above each spirit. A spirit whose weakness
    /// was STATIC-SCRAMBLED (flickerWeakness set — its sigil no longer
    /// matches its body color, e.g. a red wraith demanding LIGHTNING) gets a
    /// dashed ring + rapid flicker so the mismatch reads as the static
    /// mechanic doing its thing, not as a wrong badge.
    @ViewBuilder
    private func weaknessBadge(_ s: AstralSpirit) -> some View {
        let color = Color(hex: s.effectiveWeakness.hex)
        let scrambled = s.flickerWeakness != nil
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 26, height: 26)
            if scrambled {
                Circle()
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
                    .frame(width: 26, height: 26)
            } else {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 26, height: 26)
            }
            sigilIcon(s.effectiveWeakness, size: 16)
                .foregroundColor(color)
        }
        .modifier(StaticScrambleFlicker(active: scrambled))
    }

    /// Rapid opacity flicker for static-scrambled weakness badges. Inert when
    /// `active` is false so normal badges render rock-steady.
    private struct StaticScrambleFlicker: ViewModifier {
    let active: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dim ? 0.45 : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
        }
    }

    @ViewBuilder
    private var sableView: some View {
        if let img = BasementBrawlSpriteCache.shared.image(named: sableSpriteName) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 240)
                .opacity(hitFlash > 0 ? 0.5 : 1.0)
        } else {
            ZStack {
                Circle()
                    .stroke(Color(hex: "AACCEE").opacity(0.6), lineWidth: 2)
                    .frame(width: 110, height: 110)
                Text("SABLE")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "AACCEE"))
            }
            .opacity(hitFlash > 0 ? 0.5 : 0.95)
        }
    }

    @ViewBuilder
    private var sigilTrail: some View {
        if currentStrokePoints.count >= 2 {
            // Line trail
            Path { path in
                path.move(to: currentStrokePoints.first!)
                for p in currentStrokePoints.dropFirst() {
                    path.addLine(to: p)
                }
            }
            .stroke(
                Color(hex: "AACCEE"),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color(hex: "AACCEE").opacity(0.8), radius: 6)

            // Sparkle glow at the cursor (current stroke endpoint)
            if let tip = currentStrokePoints.last {
                Image("sigil_trail")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .blendMode(.plusLighter)
                    .position(tip)
                    .allowsHitTesting(false)
            }
        }
    }

    private var hudHeader: some View {
        VStack(spacing: 6) {
            // Title row — compact LABELS ONLY. The HP bars used to live in the
            // left/right columns here, where the player's 8-segment bar ran
            // wide, collided with the centre stage label and got clipped
            // ("pushed to left, can't read all"). Bars now have their own
            // centred row below so they're always fully readable.
            HStack(alignment: .top, spacing: 10) {
                Text("SABLE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "AACCEE"))
                Spacer()
                VStack(spacing: 2) {
                    Text(stageLabel)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(hex: "00FFCC"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if stage == .mirrorBoss {
                        Text("PHASE \(bossPhase)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "FFE044"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Spacer()
                if stage == .mirrorBoss {
                    Text("MIRROR")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(hex: "BBFF44"))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("LAYER")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "FFFFFF").opacity(0.7))
                        Text("\(spawnedThisStage)/\(spawnGoalThisStage)")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(Color(hex: "AACCEE"))
                    }
                }
            }

            // HP bar(s) — own centred row, full readable width. During the
            // mirror-boss fight both bars sit side-by-side, centred (versus
            // framing); otherwise just the player's bar, centred.
            if stage == .mirrorBoss {
                HStack(spacing: 18) {
                    hpBar(value: playerHP, max: maxHP, color: "AACCEE")
                    hpBar(value: bossHP, max: 12, color: "BBFF44", reverse: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                hpBar(value: playerHP, max: maxHP, color: "AACCEE")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 54)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.78), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        )
    }

    private func hpBar(value: Int, max: Int, color: String, reverse: Bool = false) -> some View {
        let segW: CGFloat = max <= 8 ? 16 : 11
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

    private var stageLabel: String {
        switch stage {
        case .entering:           return "DESCENDING"
        case .veilTutorial:       return "THE VEIL"
        case .staticEscalation:   return "THE STATIC"
        case .mirrorBoss:         return "THE MIRROR"
        case .victory, .defeat:   return "END"
        }
    }

    private var sigilReadout: some View {
        VStack {
            Spacer().frame(height: 130)
            HStack(spacing: 8) {
                sigilIcon(lastClassifiedSigil, size: 22)
                Text(lastClassifiedSigil.label)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(2)
            }
            .foregroundColor(Color(hex: lastClassifiedSigil.hex))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: lastClassifiedSigil.hex), lineWidth: 1)
                    )
            )
            .opacity(min(1.0, lastSigilLabelHold / 0.5))
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// Big floating prompt during a boss attack-phase: the sigil glyph she's
    /// casting + a shrinking timer ring + per-phase instruction text.
    /// Player sees this and traces accordingly to interrupt/counter/match.
    private var bossAttackPromptOverlay: some View {
        let castedSigilHex = bossCastingSigil.hex
        let countered = opposingSigil(of: bossCastingSigil)
        let timeLeft: Double = max(0, bossCastWindupDuration - bossAttackTimer)
        let pct: Double = bossCastWindupDuration > 0
            ? max(0, min(1, timeLeft / bossCastWindupDuration))
            : 0
        return ZStack {
            // Timer ring — shrinks toward 0 as the windup expires
            Circle()
                .trim(from: 0, to: CGFloat(pct))
                .stroke(Color(hex: castedSigilHex),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 130, height: 130)
                .shadow(color: Color(hex: castedSigilHex).opacity(0.7), radius: 10)

            // The sigil glyph in the center
            sigilIcon(bossCastingSigil, size: 64)
                .foregroundColor(Color(hex: castedSigilHex))

            // Per-phase instruction label below the ring
            VStack {
                Spacer().frame(height: 150)
                Text(promptCallout(forCounter: countered))
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color(hex: castedSigilHex), lineWidth: 1)
                            )
                    )
            }
        }
    }

    /// Builds the right per-phase instruction string for the boss prompt.
    private func promptCallout(forCounter c: SigilType) -> String {
        switch bossAttackPhase {
        case .castingP1:
            return "INTERRUPT — CLEAR HER SUMMONS"
        case .castingP2:
            return "COUNTER  →  \(c.glyph) \(c.label)"
        case .projectingP3:
            return "TRACE  →  \(bossCastingSigil.glyph) \(bossCastingSigil.label)"
        case .idle:
            return ""
        }
    }

    private var bannerOverlay: some View {
        VStack {
            Spacer().frame(height: 175)
            Text(bannerText)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(Color(hex: "AACCEE"))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.85))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "AACCEE"), lineWidth: 1))
                )
            Spacer()
        }
        .allowsHitTesting(false)
    }

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
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: feedbackColor), lineWidth: 2))
                )
                .shadow(color: Color(hex: feedbackColor).opacity(0.6), radius: 10)
                .padding(.bottom, 90)
                .opacity(min(1.0, feedbackHold / 0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var tutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                Spacer().frame(height: 30)
                Text("MIRRORLINE")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(Color(hex: "AACCEE"))
                Text("Sable solo, astral plane.\nThree layers. Trace sigils to banish what comes.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                Spacer().frame(height: 4)

                // Per-sigil reference card with the gesture motion described
                Group {
                    sigilRow(.ward,      desc: "WARD       — closed circle   vs Shade")
                    sigilRow(.manabolt,  desc: "MANABOLT   — sharp triangle  vs Wraith")
                    sigilRow(.iceLance,  desc: "ICE LANCE  — vertical slash  vs Skitter")
                    sigilRow(.lightning, desc: "LIGHTNING  — zigzag (≥2 turns) vs Cluster")
                    sigilRow(.soulDrain, desc: "SOUL DRAIN — sideways C / arc  vs Hungerling")
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                Spacer().frame(height: 4)
                Text("DRAW anywhere on screen. Match the icon on\nthe incoming spirit. Wrong sigil = self-chip.\nA spirit reaching Sable costs 1 HP.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // ── BOSS PHASE BRIEFING ──
                Spacer().frame(height: 6)
                Text("THE MIRROR — 3 PHASES")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FFE044"))
                VStack(alignment: .leading, spacing: 5) {
                    bossPhaseRow(
                        phase: "P1",
                        title: "SUMMONS",
                        body: "Banish the spirits she throws. Each banish chips her HP."
                    )
                    bossPhaseRow(
                        phase: "P2",
                        title: "COUNTER",
                        body: "She casts a sigil at YOU. Trace the OPPOSING sigil before her ring fills:\n• Ward ↔ Manabolt   • Ice ↔ Lightning   • Drain = universal."
                    )
                    bossPhaseRow(
                        phase: "P3",
                        title: "MIRROR-TRACE",
                        body: "She projects a sigil. Trace exactly what you see. Each match chunks her HP. Miss = -1 HP."
                    )
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                Spacer().frame(height: 8)
                Button(action: {
                    HapticsManager.shared.selectAffirm()
                    tutorialDismissed = true
                    lastFrameAt = Date()
                }) {
                    Text("DESCEND")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "AACCEE")))
                        .shadow(color: Color(hex: "AACCEE").opacity(0.6), radius: 12)
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 20)
            }   // ScrollView
        }
    }

    private func sigilRow(_ sig: SigilType, desc: String) -> some View {
        HStack(spacing: 10) {
            sigilIcon(sig, size: 20)
                .frame(width: 26)
                .foregroundColor(Color(hex: sig.hex))
            Text(desc)
                .foregroundColor(Color(hex: sig.hex))
        }
    }

    /// One row in the boss-phase briefing inside the tutorial.
    private func bossPhaseRow(phase: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(phase)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "FFE044")))
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(Color(hex: "FFE044"))
            }
            Text(body)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.leading, 2)
        }
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                // Akashic Fragment hero shot on victory — slow gentle hover
                if didWin {
                    Image("akashic_fragment")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 220)
                        .shadow(color: Color(hex: "BBFF44").opacity(0.65), radius: 24)
                        .modifier(GentleHoverModifier())
                }
                Text(didWin ? "AKASHIC FRAGMENT" : "ASTRAL BREACH")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(didWin ? Color(hex: "BBFF44") : Color(hex: "FF3344"))
                Text(didWin
                     ? "You brought it back. It shouldn't have mass.\nCipher will want to see this."
                     : "Cord severed. The mirror keeps the rest.\nBack to the body, lesson learned.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(action: exitMission) {
                    Text("CONTINUE")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.black)
                        .frame(width: 200, height: 44)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(didWin ? Color(hex: "BBFF44") : Color(hex: "FF3344")))
                }
            }
        }
    }

    // MARK: - Game loop

    private func startMission() {
        playerHP = maxHP
        stage = .entering
        stageTimer = 0
        spirits = []
        spawnedThisStage = 0
        spawnGoalThisStage = 3
        bossPhase = 1
        bossHP = 12
        resetBossAttack()
        showBanner("DESCENDING — THE VEIL")
    }

    /// Resets the boss attack state. Called at mission start and at every
    /// HP-phase boundary so we never carry a stale castingP1 into P2.
    private func resetBossAttack() {
        bossAttackPhase = .idle
        bossAttackTimer = 0
        bossCastingSigil = .unknown
        bossSummonCooldown = 0.0
        bossCastWindupDuration = 0
    }

    private func tick() {
        guard tutorialDismissed, !endGameOver else {
            lastFrameAt = Date()
            return
        }
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastFrameAt))
        lastFrameAt = now

        stageTimer += dt
        if hitFlash > 0 { hitFlash = max(0, hitFlash - dt) }
        if feedbackHold > 0 { feedbackHold = max(0, feedbackHold - dt) }
        if lastSigilLabelHold > 0 { lastSigilLabelHold = max(0, lastSigilLabelHold - dt) }
        if !bannerText.isEmpty, Date() > bannerExpires { bannerText = "" }

        tickStage(dt: dt)
        tickSpirits(dt: dt)
    }

    private func tickStage(dt: Double) {
        switch stage {
        case .entering:
            // Brief 1.5s descent narration before Veil kicks in
            if stageTimer >= 1.5 {
                transitionTo(.veilTutorial)
            }
        case .veilTutorial:
            spawnLogic(dt: dt, interval: 3.0, maxLive: 1)
            if spawnedThisStage >= spawnGoalThisStage && spirits.isEmpty {
                transitionTo(.staticEscalation)
            }
        case .staticEscalation:
            spawnLogic(dt: dt, interval: 2.0, maxLive: 2)
            if spawnedThisStage >= spawnGoalThisStage && spirits.isEmpty {
                transitionTo(.mirrorBoss)
            }
        case .mirrorBoss:
            // HP-phase progression: 12-9 = P1, 8-5 = P2, 4-1 = P3.
            // resetBossAttack() at boundaries so stale casts don't leak across.
            if bossHP <= 4 && bossPhase < 3 {
                bossPhase = 3
                resetBossAttack()
                showBanner("PHASE 3 — THE STARE")
                spirits.removeAll()  // P3 is pure trace duel; no spirits
            } else if bossHP <= 8 && bossPhase < 2 {
                bossPhase = 2
                resetBossAttack()
                showBanner("PHASE 2 — COUNTER OR DIE")
            }

            // P1 + P2 keep summoning spirits on a cooldown. P3 doesn't.
            if bossPhase <= 2 {
                let maxLive = bossPhase == 1 ? 1 : 2
                let summonInterval: Double = bossPhase == 1 ? 4.0 : 5.5
                if spirits.count < maxLive {
                    bossSummonCooldown -= dt
                    if bossSummonCooldown <= 0 {
                        spawnSpirit()
                        bossSummonCooldown = summonInterval
                    }
                }
            }

            // A dead boss casts no spells — without this guard, a cast that
            // was mid-windup when the killing trace landed could still time
            // out and damage (or kill) the player during the 1.6s death
            // beat, recording a DEFEAT for a fight that was already won.
            if !bossDefeated {
                tickBossAttack(dt: dt)
            }

            if bossHP <= 0 && !bossDefeated {
                // Hold on the banish sprite for a beat so the defeat reads,
                // THEN roll to the victory/debrief overlay. Banish any spirits
                // still on screen so they visibly dissolve too.
                bossDefeated = true
                resetBossAttack()
                for i in spirits.indices where spirits[i].banished == 0 {
                    spirits[i].banished = 0.01
                }
                SFXManager.shared.play("mirror_banish")
                HapticsManager.shared.enemyKilled()
                withAnimation(.easeIn(duration: 0.6).delay(0.85)) {
                    bossBanishOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    transitionTo(.victory)
                }
            }
        case .victory, .defeat:
            break
        }
    }

    // MARK: - Boss attack machine

    /// Drives the boss's attack-state clock — picks when she starts a new
    /// cast/counter/projection and resolves the auto-damage if the player
    /// fails to respond before the windup completes.
    private func tickBossAttack(dt: Double) {
        bossAttackTimer += dt
        switch bossAttackPhase {

        case .idle:
            // Time-between-attacks scales with phase. P1 is slow + dangerous,
            // P2 is faster + counter-able, P3 is rapid-fire trace prompts.
            let idleInterval: Double
            switch bossPhase {
            case 1:  idleInterval = 6.5
            case 2:  idleInterval = 4.0
            default: idleInterval = 2.0
            }
            if bossAttackTimer >= idleInterval {
                beginBossCast()
            }

        case .castingP1:
            // Big windup → if it expires, Sable eats 2 damage.
            // PLAYER COUNTERPLAY: banish her active summons fast enough
            // that there's no spirit drifting in — when she's about to land
            // the cast, a final-warning haptic fires.
            if bossAttackTimer >= bossCastWindupDuration {
                applyDamageToPlayer(amount: 2)
                showFeedback("MIRROR-CAST STRUCK — −2 HP", color: "FF3344")
                bossAttackPhase = .idle
                bossAttackTimer = 0
            }

        case .castingP2:
            // Counter window — player must trace OPPOSING sigil.
            // Auto-damage on timeout. Damage is lower than P1 since this
            // happens way more often.
            if bossAttackTimer >= bossCastWindupDuration {
                applyDamageToPlayer(amount: 2)
                showFeedback("COUNTER MISSED — −2 HP", color: "FF3344")
                bossAttackPhase = .idle
                bossAttackTimer = 0
            }

        case .projectingP3:
            // Mirror-trace prompt. Auto-damage on timeout, but lighter (1)
            // because P3 hits the player with prompt-after-prompt.
            if bossAttackTimer >= bossCastWindupDuration {
                applyDamageToPlayer(amount: 1)
                showFeedback("MIRROR HOLDS — −1 HP", color: "FF3344")
                bossAttackPhase = .idle
                bossAttackTimer = 0
            }
        }
    }

    /// Kick off a new boss cast — pick a random sigil, switch into the
    /// right attack-phase, and set the windup duration based on phase.
    private func beginBossCast() {
        let sigils: [SigilType] = SigilType.allCases.filter { $0 != .unknown }
        bossCastingSigil = sigils.randomElement() ?? .ward
        bossAttackTimer = 0
        switch bossPhase {
        case 1:
            bossAttackPhase = .castingP1
            bossCastWindupDuration = 3.0   // long, dramatic, lots of room to react
        case 2:
            bossAttackPhase = .castingP2
            bossCastWindupDuration = 2.3   // tighter — counter-or-die window
        default:
            bossAttackPhase = .projectingP3
            bossCastWindupDuration = 2.0   // fastest — pure trace pressure
        }
        HapticsManager.shared.error()
    }

    /// Opposing-sigil pairs. SoulDrain is a universal self-pair so the
    /// player can counter ANY P2 cast by tracing the spiral — but it
    /// damages Sable as a tradeoff (handled in resolveSigil).
    private func opposingSigil(of s: SigilType) -> SigilType {
        switch s {
        case .ward:      return .manabolt
        case .manabolt:  return .ward
        case .iceLance:  return .lightning
        case .lightning: return .iceLance
        case .soulDrain: return .soulDrain
        case .unknown:   return .unknown
        }
    }

    private func transitionTo(_ next: Stage) {
        stage = next
        stageTimer = 0
        spirits = []
        spawnedThisStage = 0
        switch next {
        case .veilTutorial:
            spawnGoalThisStage = 3
            showBanner("THE VEIL — banish them")
        case .staticEscalation:
            spawnGoalThisStage = 5
            // +1 HP refund between layers (capped at max)
            playerHP = min(maxHP, playerHP + 1)
            showFeedback("LAYER CLEAR — +1 HP", color: "BBFF44")
            showBanner("THE STATIC — the air is wrong")
        case .mirrorBoss:
            playerHP = min(maxHP, playerHP + 1)
            showFeedback("LAYER CLEAR — +1 HP", color: "BBFF44")
            showBanner("THE MIRROR — she wears your face")
        case .victory:
            endGame(win: true)
        case .defeat:
            endGame(win: false)
        case .entering:
            break
        }
    }

    private func spawnLogic(dt: Double, interval: Double, maxLive: Int) {
        guard spawnedThisStage < spawnGoalThisStage else { return }
        guard spirits.count < maxLive else { return }
        nextSpawnAt -= dt
        if nextSpawnAt <= 0 {
            spawnSpirit()
            nextSpawnAt = interval
        }
    }

    private func spawnSpirit() {
        let kind: AstralEnemy
        switch stage {
        case .veilTutorial:
            // Veil teaches the 5 archetypes — cycle in a fixed order
            // so the player sees one of each.
            let order: [AstralEnemy] = [.shade, .wraith, .skitter]
            kind = order[spawnedThisStage % order.count]
        case .staticEscalation:
            // Rotate through all 5 with some randomness
            kind = AstralEnemy.allCases.randomElement() ?? .shade
        case .mirrorBoss:
            // Boss summons reflect her current phase color
            kind = AstralEnemy.allCases.randomElement() ?? .wraith
        default:
            kind = .shade
        }

        // Random spawn angle on the rim of the arena
        let angle = Double.random(in: 0..<(2 * .pi))
        let spawnPos = CGPoint(x: cos(angle), y: sin(angle))
        let dirToCenter = CGVector(
            dx: -spawnPos.x / hypot(spawnPos.x, spawnPos.y),
            dy: -spawnPos.y / hypot(spawnPos.x, spawnPos.y)
        )
        // Flicker re-rolls the weakness in the static-escalation stage so the
        // player must re-read the badge. Pick a RANDOM other weakness — the
        // old `.first(where:)` deterministically returned shade's weakness
        // (ward) for nearly everything, so every flicker became "vs ward".
        let flicker: SigilType? = (stage == .staticEscalation && Bool.random())
            ? AstralEnemy.allCases.filter { $0 != kind }.randomElement()?.weakness
            : nil
        let spirit = AstralSpirit(
            kind: kind,
            position: spawnPos,
            direction: dirToCenter,
            flickerWeakness: flicker
        )
        spirits.append(spirit)
        spawnedThisStage += 1
    }

    private func tickSpirits(dt: Double) {
        for i in spirits.indices {
            // Decay the wrong-sigil flash (independent of banish/cull).
            if spirits[i].hitDing > 0 {
                spirits[i].hitDing = max(0, spirits[i].hitDing - dt * 3)
            }
            // Fade banished spirits out then remove
            if spirits[i].banished > 0 {
                spirits[i].banished = min(1.0, spirits[i].banished + dt * 3)
                continue
            }
            // Drift toward center
            let speed = spirits[i].kind.approachSpeed
            spirits[i].position.x += spirits[i].direction.dx * CGFloat(speed * dt)
            spirits[i].position.y += spirits[i].direction.dy * CGFloat(speed * dt)
        }
        // Resolve impacts at center
        var indicesToRemove: [Int] = []
        for (i, s) in spirits.enumerated() {
            // Within ~0.1 normalized units of center = it touched Sable
            let dist = hypot(s.position.x, s.position.y)
            if s.banished >= 1.0 {
                indicesToRemove.append(i)
            } else if dist < 0.10 && s.banished == 0 {
                applyDamageToPlayer(amount: 1)
                showFeedback("\(s.kind.label) BREACHED — −1 HP", color: "FF3344")
                indicesToRemove.append(i)
            }
        }
        for i in indicesToRemove.reversed() {
            spirits.remove(at: i)
        }
    }

    // MARK: - Resolving a cast sigil

    private func resolveSigil(_ sig: SigilType) {
        lastClassifiedSigil = sig
        lastSigilLabelHold = 1.4

        // Bad cast — wobbly nothing or stroke too short
        if sig == .unknown {
            showFeedback("MISCAST", color: "AAAAAA")
            return
        }

        // BOSS-ACTIVE RESOLUTION — interrupt the per-phase mechanic first.
        // Each attack-phase wants the player to do something specific; if
        // the player satisfies it, we damage the boss; if not, we still
        // fall through to normal spirit-targeting where useful (P1).
        if stage == .mirrorBoss && bossAttackPhase != .idle {
            switch bossAttackPhase {

            case .castingP1:
                // P1: cast is interrupted by banishing all her summons.
                // Sigils thrown directly at the boss while no spirits are
                // up = small chip + cancel her cast.
                if spirits.allSatisfy({ $0.banished > 0 }) {
                    bossHP = max(0, bossHP - 1)
                    showFeedback("CAST INTERRUPTED — \(sig.glyph)", color: "BBFF44")
                    bossAttackPhase = .idle
                    bossAttackTimer = 0
                    HapticsManager.shared.attackHit()
                    return
                }
                // Otherwise fall through to spirit-banish logic below.

            case .castingP2:
                let opposing = opposingSigil(of: bossCastingSigil)
                if sig == opposing {
                    bossHP = max(0, bossHP - 2)
                    showFeedback("COUNTERED — \(sig.label)", color: "00FF88")
                    bossAttackPhase = .idle
                    bossAttackTimer = 0
                    HapticsManager.shared.attackHit()
                    return
                } else if sig == .soulDrain && bossCastingSigil != .soulDrain {
                    // Spiral = universal counter, but tradeoff: only 1 boss
                    // damage AND Sable takes 1 chip from the drain.
                    bossHP = max(0, bossHP - 1)
                    applyDamageToPlayer(amount: 1)
                    showFeedback("DRAIN-COUNTER — costly", color: "FF44AA")
                    bossAttackPhase = .idle
                    bossAttackTimer = 0
                    return
                } else {
                    applyDamageToPlayer(amount: 1)
                    showFeedback("WRONG COUNTER — \(sig.label) ≠ \(opposing.label)",
                                 color: "FF9933")
                    // Don't reset attack phase — they still need to counter
                    // the original cast or eat the full 2 dmg.
                    return
                }

            case .projectingP3:
                if sig == bossCastingSigil {
                    bossHP = max(0, bossHP - 2)
                    showFeedback("MIRROR TRACED — \(sig.label)", color: "BBFF44")
                    bossAttackPhase = .idle
                    bossAttackTimer = 0
                    HapticsManager.shared.attackHit()
                    return
                } else {
                    applyDamageToPlayer(amount: 1)
                    showFeedback("WRONG TRACE — \(sig.label) ≠ \(bossCastingSigil.label)",
                                 color: "FF9933")
                    return
                }

            case .idle:
                break
            }
        }

        // Resolve which spirit this sigil acts on. PREFER the nearest spirit
        // whose weakness matches the drawn sigil — so with 2+ spirits on
        // screen, a correct sigil banishes the one it actually counters
        // instead of being rejected because a different spirit was nearer.
        // Only fall back to the nearest (for the wrong-sigil penalty) when
        // NOTHING on screen is weak to what was drawn.
        guard let target = nearestActiveSpirit(matching: sig) ?? nearestActiveSpirit() else {
            showFeedback("\(sig.label) — no target", color: sig.hex)
            return
        }

        if sig == target.0.effectiveWeakness {
            // Banish — full effect. Bonus: ward and lightning AOE multiple targets.
            banish(spiritAt: target.1, with: sig)
            if sig == .ward {
                // Ward = AOE radius — also damage other spirits in proximity to target
                for (i, s) in spirits.enumerated() where i != target.1 && s.banished == 0 {
                    let dx = s.position.x - target.0.position.x
                    let dy = s.position.y - target.0.position.y
                    if hypot(dx, dy) < 0.45 && sig == s.effectiveWeakness {
                        banish(spiritAt: i, with: sig)
                    }
                }
            } else if sig == .lightning {
                // Chain to 2 more weak-to-lightning spirits
                var chained = 0
                for (i, s) in spirits.enumerated() where i != target.1 && s.banished == 0 && chained < 2 {
                    if s.effectiveWeakness == .lightning {
                        banish(spiritAt: i, with: sig)
                        chained += 1
                    }
                }
            } else if sig == .soulDrain {
                // Heal +1 HP on banish
                playerHP = min(maxHP, playerHP + 1)
                showFeedback("SOUL DRAIN +1 HP", color: sig.hex)
            }
            HapticsManager.shared.attackHit()
        } else {
            // Wrong sigil — flash the target (does NOT banish it) and self-chip
            // Sable. The spirit keeps drifting; you must trace the right sigil.
            spirits[target.1].hitDing = 1.0
            applyDamageToPlayer(amount: 1)
            showFeedback("WRONG SIGIL — \(sig.label) vs \(target.0.effectiveWeakness.label)",
                         color: "FF9933")
        }
    }

    private func banish(spiritAt idx: Int, with sig: SigilType) {
        guard spirits.indices.contains(idx) else { return }
        spirits[idx].banished = 0.01   // kick off the fade-out tween
        showFeedback("\(sig.glyph) \(sig.label) — \(spirits[idx].kind.label) BANISHED",
                     color: sig.hex)
        if stage == .mirrorBoss {
            // Banishing minions during the boss fight chips the boss
            bossHP = max(0, bossHP - 1)
        }
    }

    private func nearestActiveSpirit() -> (AstralSpirit, Int)? {
        var best: (AstralSpirit, Int, CGFloat)? = nil
        for (i, s) in spirits.enumerated() where s.banished == 0 {
            let d = hypot(s.position.x, s.position.y)
            if best == nil || d < best!.2 {
                best = (s, i, d)
            }
        }
        if let b = best { return (b.0, b.1) }
        return nil
    }

    /// Nearest active spirit whose weakness MATCHES `sig`. With 2+ spirits on
    /// screen, a correct sigil for the farther one used to be judged "wrong"
    /// because resolution blindly targeted the nearest; this targets by sigil.
    private func nearestActiveSpirit(matching sig: SigilType) -> (AstralSpirit, Int)? {
        var best: (AstralSpirit, Int, CGFloat)? = nil
        for (i, s) in spirits.enumerated() where s.banished == 0 && s.effectiveWeakness == sig {
            let d = hypot(s.position.x, s.position.y)
            if best == nil || d < best!.2 {
                best = (s, i, d)
            }
        }
        if let b = best { return (b.0, b.1) }
        return nil
    }

    private func applyDamageToPlayer(amount: Int) {
        // No posthumous losses: the win is already locked in.
        guard !bossDefeated else { return }
        playerHP = max(0, playerHP - amount)
        hitFlash = 0.22
        HapticsManager.shared.playerDamaged()
        if playerHP == 0 {
            transitionTo(.defeat)
        }
    }

    // MARK: - End

    private func endGame(win: Bool) {
        guard !endGameOver else { return }
        endGameOver = true
        didWin = win
        if win {
            HapticsManager.shared.victory()
            SFXManager.shared.play("mission_victory")
            // Report the objective to authority so the debrief shows
            // "✓ DATA RECOVERED" (+ counts the bonus) instead of a false
            // "✗ DATA MISSED".
            _ = GameState.shared.requestObjectiveDataAcquired(source: "mirrorline")
            let score = 300 + playerHP * 50 + 400
            MissionStatsStore.shared.recordVictory(
                missionId: "Mission002_5",
                score: score,
                dataAcquired: true,         // Akashic Fragment
                grimoireAcquired: false
            )
        } else {
            HapticsManager.shared.defeat()
            SFXManager.shared.play("mission_defeat")
        }
    }

    private func exitMission() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .endMirrorline(won: didWin))
    }

    // MARK: - Helpers

    private func showBanner(_ text: String) {
        bannerText = text
        bannerExpires = Date().addingTimeInterval(2.2)
    }

    private func showFeedback(_ text: String, color: String) {
        feedbackText = text
        feedbackColor = color
        feedbackHold = 1.4
    }
}

// MARK: - Helpers

/// Slow, subtle vertical hover used for the Akashic Fragment hero shot on
/// the victory overlay. Driven by TimelineView so it idles without needing
/// scene state.
private struct GentleHoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            content
                .offset(y: CGFloat(sin(t * 1.4)) * 6)
                .rotationEffect(.degrees(sin(t * 0.7) * 2.5))
        }
    }
}

