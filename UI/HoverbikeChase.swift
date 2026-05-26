import SwiftUI
import Combine

// MARK: - Hoverbike Chase Mission (M3.5 "The Drop")
//
// Side-scrolling chase set between M3 and M4 narratively. The runners just
// climbed out of the Ritual Chamber and the corp tagged them on the way
// out — now they're fleeing down the elevated highway on a hoverbike with
// drones in pursuit and a gunship inbound for the finale.
//
// Gameplay:
//   • 3 vertical lanes on the highway. Swipe up/down to switch lanes.
//   • Tap anywhere to fire Lyra's SMG at pursuing drones.
//   • Civilian hovercars are same-direction obstacles (slower traffic).
//   • Energy barriers are vertical hazards — must change lane to dodge.
//   • Drones approach from the right, take 2 hits each.
//   • After ~60s, the corp gunship arrives as the boss — 5 hits to down.
//   • Win = down the gunship. Lose = 3 hits taken.
//
// Visual layering (back to front):
//   1. Far skyline (slowest scroll)
//   2. Mid layer overpass
//   3. Bike + drones + obstacles (action plane)
//   4. Road foreground (fastest scroll)
//   5. HUD overlay

struct HoverbikeChaseScene: View {
    @ObservedObject var manager: PhaseManager

    // MARK: - Tuning
    /// Per-mission SFX mix multiplier — applied to every play() call in
    /// this scene. Cumulative -40% (was -30% then trimmed another -15%)
    /// so the chase audio sits cleaner against the music. 0.7 × 0.85 ≈ 0.595.
    private let chaseSfxMix: Float = 0.595

    /// Wraps SFXManager.play with the per-mission mix scaling so we don't
    /// repeat the multiplier at every call site.
    private func playSfx(_ name: String, volume: Float? = nil) {
        let base = volume ?? SFXManager.shared.targetVolume
        SFXManager.shared.play(name, volume: base * chaseSfxMix)
    }

    private let maxHp: Int = 3
    /// Boss HP — bumped 16 → 24 so the gunship fight lasts longer.
    /// At ~3 bullets per tap, ~8 successful taps needed to down it (most
    /// will miss given boss movement + dodging incoming).
    private let bossHp: Int = 24
    /// Seconds before the boss gunship appears. Pushed 35 → 55 so the
    /// dodging-traffic phase before the boss feels substantial. Total
    /// mission ~90-120s of active play depending on player skill.
    private let bossArrivalSeconds: Double = 55
    /// REMOVED — auto-win-by-survival used to fire at 95s and end the run
    /// without a real boss kill. Now the boss is the ONLY win condition.
    /// (Player can still BAIL out at any time for a manual end.)

    // MARK: - State
    @State private var hp: Int = 3
    @State private var bossHpRemaining: Int = 5
    // 2026-05-12 redesign: bike has continuous 2D position within a play
    // zone (was 3-lane). User can drag in any direction.
    @State private var bikePos: CGPoint = CGPoint(x: 0.5, y: 0.78)
    @State private var bikeTargetPos: CGPoint = CGPoint(x: 0.5, y: 0.78)
    @State private var elapsed: Double = 0
    @State private var pulseTime: Double = 0
    @State private var distance: CGFloat = 0
    @State private var speed: CGFloat = 1.0              // scroll speed multiplier
    @State private var isFiring: Bool = false
    @State private var firingPulseEnd: Double = 0        // pulseTime when fire flash ends
    @State private var iframeUntil: Double = 0           // invuln countdown after hit
    @State private var bossActive: Bool = false
    @State private var bossX: CGFloat = 1.15             // 0..1 of screen width (offscreen right)
    @State private var bossY: CGFloat = 0.78             // y target (continuous, no lanes)
    @State private var bossYVisual: CGFloat = 0.5
    @State private var bossYSwapAt: Double = 0
    @State private var obstacles: [Obstacle] = []
    @State private var drones: [Drone] = []
    @State private var bullets: [Bullet] = []
    @State private var enemyBullets: [EnemyBullet] = []
    @State private var bgOffsetFar: CGFloat = 0
    @State private var bgOffsetMid: CGFloat = 0
    @State private var bgOffsetRoad: CGFloat = 0
    @State private var gameOver: Bool = false
    @State private var didWin: Bool = false
    @State private var showBriefing: Bool = true
    @State private var dragStartBikePos: CGPoint = CGPoint(x: 0.5, y: 0.78)
    @State private var dragActive: Bool = false
    /// Last pulseTime at which the bike-swerve SFX fired. Cooldown gates
    /// the SFX so a single sustained drag doesn't spam it.
    @State private var lastSwerveAt: Double = 0
    /// Bike position when the last swerve SFX fired — used to detect
    /// "significant new movement" before re-triggering.
    @State private var lastSwerveBikePos: CGPoint = CGPoint(x: 0.5, y: 0.78)
    @State private var tickTimer: AnyCancellable?
    @State private var spawnTimer: AnyCancellable?

    // MARK: - Models

    enum ObstacleKind: String {
        case carA, carB, barrier
    }

    struct Obstacle: Identifiable {
        let id: UUID = UUID()
        var x: CGFloat           // 0..1 of screen width
        var y: CGFloat           // 0..1 of screen height (continuous, no lanes)
        let kind: ObstacleKind
        var consumed: Bool = false
        /// Horizontal velocity in screen-fractions per second. POSITIVE for
        /// stationary/ahead obstacles (the bike is "approaching" them — they
        /// appear to slide rightward as the world scrolls past).
        var vx: CGFloat
    }

    struct Drone: Identifiable {
        let id: UUID = UUID()
        var x: CGFloat           // 0..1 of screen width
        var y: CGFloat           // 0..1 of screen height
        var hp: Int = 2
        var consumed: Bool = false
        var nextFireAt: Double   // pulseTime
    }

    /// Player bullet — fired from the bike toward the right.
    /// Each tap spawns three bullets fanning out (straight back, diagonal
    /// up, diagonal down) so a single shot can catch a pursuer regardless
    /// of which lane they're in.
    struct Bullet: Identifiable {
        let id: UUID = UUID()
        var x: CGFloat
        var y: CGFloat   // 0..1 of screen height (no fixed lane — lets us angle shots)
        var vx: CGFloat  // horizontal velocity (positive = rightward toward pursuers)
        var vy: CGFloat  // vertical velocity (positive = downward, negative = upward)
    }

    /// Enemy bullet — fired from a drone or gunship, travels toward the bike.
    struct EnemyBullet: Identifiable {
        let id: UUID = UUID()
        var x: CGFloat
        var y: CGFloat           // 0..1 of screen height (uses absolute Y since fired from variable spots)
        var vx: CGFloat
        var vy: CGFloat
    }

    // MARK: - Layout helpers
    // 2026-05-12 redesign: bike + threats live in a continuous 2D play
    // zone (lower portion of screen, over the road foreground layer).
    // No lane snapping — drag in any direction to position the bike.
    private let playMinX: CGFloat = 0.12
    private let playMaxX: CGFloat = 0.88
    private let playMinY: CGFloat = 0.62
    private let playMaxY: CGFloat = 0.92

    private func clampBike(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: max(playMinX, min(playMaxX, p.x)),
            y: max(playMinY, min(playMaxY, p.y))
        )
    }

    /// Random y within the play zone (used for spawning obstacles + drones).
    private func randomPlayY() -> CGFloat {
        CGFloat.random(in: (playMinY + 0.03) ... (playMaxY - 0.03))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Parallax backgrounds (back to front) ──────────────────
                // Layered so:
                //   • far skyline occupies the top ~40% (clearly distant)
                //   • mid layer fills middle ~25% (overpass + city texture)
                //   • road fills lower ~40% (where the gameplay happens)
                // The mid layer is dimmed because its art has its own
                // hovercars + signs that would compete visually with the
                // actual gameplay obstacles.
                parallaxLayer("chase_bg_far",
                              offset: bgOffsetFar,
                              y: 0.10, height: 0.38, in: geo,
                              fallbackTint: Color(hex: "1A0030"),
                              tint: 1.0)
                parallaxLayer("chase_bg_mid",
                              offset: bgOffsetMid,
                              y: 0.42, height: 0.22, in: geo,
                              fallbackTint: Color(hex: "120024"),
                              tint: 0.55)
                parallaxLayer("chase_bg_road",
                              offset: bgOffsetRoad,
                              y: 0.60, height: 0.40, in: geo,
                              fallbackTint: Color(hex: "0A0014"),
                              tint: 1.0)

                // ── Obstacles (between road and bike, but visually overlap)
                ForEach(obstacles.filter { !$0.consumed }) { ob in
                    obstacleView(ob, in: geo)
                }

                // ── Drones (small fast enemies) ───────────────────────────
                ForEach(drones.filter { !$0.consumed }) { d in
                    droneView(d, in: geo)
                }

                // ── Enemy bullets (red tracers) ───────────────────────────
                // Larger + glowing so the player can actually SEE incoming
                // shots in time to dodge (was 8pt, easy to miss).
                ForEach(enemyBullets) { b in
                    ZStack {
                        Circle()
                            .fill(Color(hex: "FF3344").opacity(0.35))
                            .frame(width: 24, height: 24)
                            .blur(radius: 4)
                        Circle()
                            .fill(Color(hex: "FF3344"))
                            .frame(width: 12, height: 12)
                            .shadow(color: Color(hex: "FF3344"), radius: 8)
                    }
                    .position(x: b.x * geo.size.width, y: b.y * geo.size.height)
                }

                // ── Player bullets (cyan tracers) ─────────────────────────
                // Three bullets per tap fan out: straight, diagonal up, down.
                // Render rotated to match velocity angle. Bigger + more glow
                // so they read clearly as the player's shots.
                ForEach(bullets) { b in
                    ZStack {
                        Capsule()
                            .fill(Color(hex: "00FFCC").opacity(0.35))
                            .frame(width: 44, height: 10)
                            .blur(radius: 4)
                        Capsule()
                            .fill(Color(hex: "00FFCC"))
                            .frame(width: 30, height: 5)
                            .shadow(color: Color(hex: "00FFCC"), radius: 8)
                    }
                    .rotationEffect(.radians(atan2(Double(b.vy), Double(b.vx))))
                    .position(x: b.x * geo.size.width, y: b.y * geo.size.height)
                }

                // ── Player bike ───────────────────────────────────────────
                bikeView(in: geo)

                // ── Boss gunship ──────────────────────────────────────────
                if bossActive {
                    gunshipView(in: geo)
                }

                // ── HUD ───────────────────────────────────────────────────
                hudView
                    .padding(.top, 36)
                    .padding(.horizontal, 16)

                // ── Briefing card ─────────────────────────────────────────
                if showBriefing {
                    briefingCard
                        .zIndex(1000)
                }

                // ── Game-over overlay ─────────────────────────────────────
                if gameOver {
                    gameOverOverlay
                        .zIndex(1100)
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .onAppear {
            initialise()
            startTimers()
        }
        .onDisappear {
            tickTimer?.cancel()
            spawnTimer?.cancel()
        }
    }

    // MARK: - Backgrounds (parallax)

    @ViewBuilder
    private func parallaxLayer(_ name: String,
                                offset: CGFloat,
                                y: CGFloat, height: CGFloat,
                                in geo: GeometryProxy,
                                fallbackTint: Color,
                                tint: Double = 1.0) -> some View {
        let layerW = geo.size.width
        let layerH = geo.size.height * height
        let yCenter = geo.size.height * (y + height / 2)
        // Wrap the offset so we have a positive value in [0, layerW] that
        // determines where image 1 sits. Image 2 is placed one layerW to
        // the right, so as offset grows the pair scrolls leftward
        // seamlessly (each image cycles into and out of the clipping window).
        let wrapped = offset.truncatingRemainder(dividingBy: layerW)

        ZStack(alignment: .leading) {
            if let img = UIImage(named: name) {
                // Scroll RIGHTWARD: as `wrapped` grows, image 1 slides right
                // off the screen and image 2 comes in from the left.
                // Matches the bike's facing direction — bike faces+moves
                // LEFT in world space, so the world should appear to flow
                // RIGHTWARD across the camera (left-to-right).
                Image(uiImage: img)
                    .resizable()
                    .frame(width: layerW, height: layerH)
                    .offset(x: wrapped)
                Image(uiImage: img)
                    .resizable()
                    .frame(width: layerW, height: layerH)
                    .offset(x: wrapped - layerW)
            } else {
                LinearGradient(
                    colors: [fallbackTint.opacity(0.85), fallbackTint],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: layerW, height: layerH)
            }
        }
        .frame(width: layerW, height: layerH)
        .clipped()
        .opacity(tint)
        .position(x: layerW / 2, y: yCenter)
    }

    // MARK: - Sprite views

    @ViewBuilder
    private func bikeView(in geo: GeometryProxy) -> some View {
        let assetName = isFiring ? "chase_bike_firing" : "chase_bike_idle"
        // Bigger bike — was 0.42, bumped to 0.58 so it reads as the hero of
        // the scene rather than getting lost amongst BG detail.
        let bikeSize = geo.size.width * 0.58
        let alpha: Double = iframeUntil > pulseTime
            ? (Int(pulseTime * 14) % 2 == 0 ? 0.45 : 1.0)
            : 1.0
        ZStack {
            if let img = UIImage(named: assetName) {
                // Tried .blendMode(.plusLighter) to suppress the source PNG's
                // grey gradient halo — but it washed out the dark bike body
                // and riders. Reverted. The soft halo reads as ambient bike
                // glow against the road and isn't actually distracting.
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: bikeSize)
                    .opacity(alpha)
                    .shadow(color: Color(hex: "FF00AA").opacity(0.35), radius: 12)
            } else {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: "FF00AA"), Color(hex: "00DDFF")],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: bikeSize, height: bikeSize * 0.35)
                    .opacity(alpha)
            }
        }
        .position(x: bikePos.x * geo.size.width,
                  y: bikePos.y * geo.size.height + sin(pulseTime * 4) * 2)
    }

    @ViewBuilder
    private func droneView(_ d: Drone, in geo: GeometryProxy) -> some View {
        let size = geo.size.width * 0.18
        let yBob = sin(pulseTime * 5 + Double(d.x)) * 3
        if let img = UIImage(named: "chase_drone") {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: size)
                .position(x: d.x * geo.size.width,
                          y: d.y * geo.size.height + yBob)
        } else {
            Circle()
                .fill(Color(hex: "881100"))
                .overlay(
                    Circle().fill(Color(hex: "FF3344"))
                        .frame(width: size * 0.4, height: size * 0.4)
                )
                .frame(width: size, height: size)
                .position(x: d.x * geo.size.width,
                          y: d.y * geo.size.height)
        }
    }

    @ViewBuilder
    private func obstacleView(_ ob: Obstacle, in geo: GeometryProxy) -> some View {
        let xPos = ob.x * geo.size.width
        let yPos = ob.y * geo.size.height
        switch ob.kind {
        case .carA, .carB:
            let assetName = (ob.kind == .carA) ? "chase_car_a" : "chase_car_b"
            let w = geo.size.width * 0.30
            if let img = UIImage(named: assetName) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w)
                    .position(x: xPos, y: yPos)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "224466"))
                    .frame(width: w, height: w * 0.45)
                    .position(x: xPos, y: yPos)
            }
        case .barrier:
            // Barrier height roughly matches a single lane band (~12% of
            // screen height). Was 0.32 — that's bigger than the entire
            // 3-lane play area and dominated the screen.
            let h = geo.size.height * 0.12
            if let img = UIImage(named: "chase_barrier") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: h)
                    .position(x: xPos, y: yPos)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(hex: "FF00AA"), Color(hex: "00DDFF")],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: h)
                    .shadow(color: Color(hex: "FF00AA"), radius: 8)
                    .position(x: xPos, y: yPos)
            }
        }
    }

    @ViewBuilder
    private func gunshipView(in geo: GeometryProxy) -> some View {
        let size = geo.size.width * 0.70   // Bigger — actually presence
        ZStack {
            if let img = UIImage(named: "chase_gunship") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size)
                    .shadow(color: Color(hex: "FF3344").opacity(0.55), radius: 14)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "554433"))
                    .frame(width: size, height: size * 0.55)
            }
        }
        .position(x: bossX * geo.size.width,
                  y: bossYVisual * geo.size.height + sin(pulseTime * 2) * 4)
    }

    // MARK: - HUD

    private var hudView: some View {
        VStack {
            HStack(alignment: .top) {
                // HP pips on the left
                VStack(alignment: .leading, spacing: 4) {
                    Text("HP")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color(hex: "FF3344"))
                    HStack(spacing: 4) {
                        ForEach(0..<maxHp, id: \.self) { i in
                            Image(systemName: i < hp ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(i < hp ? Color(hex: "FF3344") : .white.opacity(0.25))
                        }
                    }
                }
                Spacer()
                // Title + distance
                VStack(alignment: .trailing, spacing: 2) {
                    Text("// THE DROP")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color(hex: "FF00AA"))
                    Text(String(format: "DIST %.0fm", distance))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFCC"))
                    if bossActive {
                        bossHpBar
                    }
                }
            }
            Spacer()
            Button(action: bailOut) {
                Text("BAIL")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FF3344"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(hex: "FF3344").opacity(0.6), lineWidth: 1)
                            )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, 36)
        }
    }

    private var bossHpBar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("CORP GUNSHIP")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: "FF3344"))
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 120, height: 8)
                    .overlay(Rectangle().stroke(Color(hex: "FF3344"), lineWidth: 1))
                Rectangle()
                    .fill(Color(hex: "FF3344"))
                    .frame(width: 120 * CGFloat(bossHpRemaining) / CGFloat(bossHp), height: 8)
            }
        }
    }

    // MARK: - Briefing + Game-over UI

    private var briefingCard: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("MISSION 3.5")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(Color(hex: "FF00AA").opacity(0.7))
                Text("THE DROP")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(hex: "FF00AA"))
                Text("Highway exfil. Corp tagged the data drive\non the way out — drones in pursuit.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 8) {
                    briefingRule(icon: "arrow.up.and.down.and.arrow.left.and.right", color: Color(hex: "00FFCC"),
                                 title: "DRAG TO MOVE", detail: "Steer the bike in any direction to dodge")
                    briefingRule(icon: "burst.fill", color: Color(hex: "00FF88"),
                                 title: "TAP", detail: "Fire Lyra's SMG at drones chasing from behind")
                    briefingRule(icon: "exclamationmark.triangle.fill", color: Color(hex: "FFCC00"),
                                 title: "DON'T GET HIT", detail: "Dodge traffic ahead + bullets behind. Take down the corp gunship to escape.")
                }
                .padding(.top, 8)
                Button(action: {
                    HapticsManager.shared.buttonTap()
                    withAnimation(.easeIn(duration: 0.25)) { showBriefing = false }
                }) {
                    Text("RIDE")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.black)
                        .frame(width: 200, height: 44)
                        .background(Color(hex: "00FF88"))
                        .cornerRadius(6)
                }
                .padding(.top, 10)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "FF00AA").opacity(0.55), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal, 22)
        }
    }

    private func briefingRule(icon: String, color: Color,
                              title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(color)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(didWin ? "ESCAPED" : "TAGGED")
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(didWin ? Color(hex: "00FF88") : Color(hex: "FF3344"))
                Text(didWin
                     ? "Data drive delivered.\nThe heat will cool — give it a few days."
                     : "Corp got the drive back.\nThe contract is busted. Lay low.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button(action: {
                    HapticsManager.shared.buttonTap()
                    // Win → outro VN → debrief. Loss → straight to debrief.
                    // Mirrors the M4.5 / M5.5 endBrawl/endColdTrace pattern.
                    // PhaseManager.transition() captures the won bool and
                    // sets combatWon internally (see endChase handler).
                    _ = manager.transition(to: .endChase(won: didWin))
                }) {
                    Text("RETURN")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.black)
                        .frame(width: 200, height: 44)
                        .background(didWin ? Color(hex: "00FF88") : Color(hex: "FF3344"))
                        .cornerRadius(6)
                }
                .padding(.top, 8)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke((didWin ? Color(hex: "00FF88") : Color(hex: "FF3344")).opacity(0.7),
                                    lineWidth: 1.5)
                    )
            )
        }
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        // 2D continuous drag. The bike's target position tracks the drag
        // delta in real time — drag right, bike slides right. Drag up,
        // bike slides up. Sub-pixel-precise movement within the play zone.
        //
        // Tap detection: if release happens with no drag movement
        // (total < 12pt), treat as a tap → fire weapon. Otherwise it was
        // a movement drag.
        //
        // Drag distance is mapped to screen-fraction movement: 1pt drag →
        // ~0.0025 screen units (so a 200pt drag = ~half the screen).
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard !showBriefing, !gameOver else { return }
                if !dragActive {
                    dragActive = true
                    dragStartBikePos = bikePos
                }
                // 1:1 drag — 1pt of drag = 1pt of bike movement on screen.
                // Mapping to screen-fraction by dividing by typical iPhone
                // screen width (~400pt for the play area).
                let dxFraction = drag.translation.width / 400.0
                let dyFraction = drag.translation.height / 400.0
                let prevBike = bikePos
                bikePos = clampBike(CGPoint(
                    x: dragStartBikePos.x + dxFraction,
                    y: dragStartBikePos.y + dyFraction
                ))

                // Swerve SFX trigger — tightened so sustained drags don't
                // re-trigger it. Three gates:
                //   • moved >0.12 of screen since last fire (significant
                //     repositioning, not a small adjust)
                //   • >0.8s cooldown (longer pause between swerves)
                //   • current-frame drag velocity is meaningful (>0.004),
                //     so a paused drag doesn't keep firing while held
                let moveDelta = hypot(bikePos.x - lastSwerveBikePos.x,
                                      bikePos.y - lastSwerveBikePos.y)
                let prevDelta = hypot(bikePos.x - prevBike.x,
                                      bikePos.y - prevBike.y)
                if moveDelta > 0.12,
                   pulseTime > lastSwerveAt + 0.8,
                   prevDelta > 0.004 {
                    playSfx("bike_swerve")
                    lastSwerveAt = pulseTime
                    lastSwerveBikePos = bikePos
                }
            }
            .onEnded { drag in
                defer { dragActive = false }
                guard !showBriefing, !gameOver else { return }
                let totalMag = max(abs(drag.translation.height), abs(drag.translation.width))
                // Stationary release → fire. Drag release → just leave bike
                // where it ended.
                if totalMag < 12 {
                    fireWeapon()
                }
            }
    }

    // MARK: - Firing

    private func fireWeapon() {
        guard !gameOver, !showBriefing else { return }
        // Spawn THREE bullets fanning out from the bike: one straight back
        // (vy=0), one diagonal up (negative vy), one diagonal down. Lets a
        // single shot catch pursuers regardless of their vertical offset.
        let originX = bikePos.x + 0.04   // slight offset right of bike (Lyra's gun is at back)
        let originY = bikePos.y
        let vxStraight: CGFloat = 1.6
        let vxAngled: CGFloat   = 1.55
        let vyAngled: CGFloat   = vxAngled * 0.18
        bullets.append(Bullet(x: originX, y: originY, vx: vxStraight, vy: 0))
        bullets.append(Bullet(x: originX, y: originY, vx: vxAngled,   vy: -vyAngled))
        bullets.append(Bullet(x: originX, y: originY, vx: vxAngled,   vy:  vyAngled))
        isFiring = true
        firingPulseEnd = pulseTime + 0.28   // longer flash so the firing
                                            // sprite is actually visible
        // SMG fires every tap — kept 20% lower than the rest of the chase
        // SFX so a rapid-fire player doesn't drown the music + ambient mix.
        playSfx("gunshot_smg", volume: SFXManager.shared.targetVolume * 0.8)
        HapticsManager.shared.buttonTap()
    }

    // MARK: - Lifecycle

    private func initialise() {
        hp = maxHp
        bossHpRemaining = bossHp
        // Bike starts at center-bottom of play zone (visually anchored
        // over the road, with room to move in all 4 directions).
        bikePos = CGPoint(x: 0.5, y: 0.78)
        bikeTargetPos = bikePos
        elapsed = 0
        pulseTime = 0
        distance = 0
        speed = 1.0
        bossActive = false
        bossX = 1.15
        bossY = 0.78
        bossYVisual = 0.78
        obstacles = []
        drones = []
        bullets = []
        enemyBullets = []
        bgOffsetFar = 0
        bgOffsetMid = 0
        bgOffsetRoad = 0
        gameOver = false
        didWin = false
        // Initial iframe ~3s so the player has time to read the scene + try
        // a drag without immediate damage. Combined with the 3.5s spawn
        // grace this means roughly: scene visible → 0.5s try-drag window
        // → first obstacle starts approaching from far left.
        iframeUntil = 3.0
    }

    private func startTimers() {
        let dt: TimeInterval = 1.0 / 60.0
        tickTimer = Timer.publish(every: dt, on: .main, in: .common)
            .autoconnect()
            .sink { _ in tick(dt: CGFloat(dt)) }
        // Spawn cadence — 1.4s between spawns (was 0.9s). Keeps the screen
        // less cluttered and gives the player time to react to each threat.
        spawnTimer = Timer.publish(every: 1.4, on: .main, in: .common)
            .autoconnect()
            .sink { _ in spawnEntity() }
    }

    // MARK: - Tick (per-frame update)

    private func tick(dt: CGFloat) {
        guard !showBriefing, !gameOver else { return }

        pulseTime += Double(dt)
        elapsed += Double(dt)
        distance += speed * dt * 30   // arbitrary unit

        // Ramp speed slowly up to 1.6× over the mission duration.
        speed = min(1.6, speed + dt * 0.008)

        // Parallax scrolling — far is slowest, road is fastest.
        bgOffsetFar  = (bgOffsetFar  + speed * dt * 14).truncatingRemainder(dividingBy: 4000)
        bgOffsetMid  = (bgOffsetMid  + speed * dt * 38).truncatingRemainder(dividingBy: 4000)
        bgOffsetRoad = (bgOffsetRoad + speed * dt * 95).truncatingRemainder(dividingBy: 4000)

        // Move obstacles (ahead-of-bike traffic + barriers). vx is positive
        // — they move RIGHTWARD across the screen as the bike "passes" them.
        // Spawned at the LEFT edge, exit on the right.
        for i in obstacles.indices {
            obstacles[i].x += dt * obstacles[i].vx * speed
        }
        obstacles.removeAll { $0.x > 1.2 || $0.consumed }

        // Move drones leftward (chasers from behind, catching up to bike).
        // Spawned on the RIGHT edge, drift across screen, exit on the left.
        for i in drones.indices {
            drones[i].x -= dt * 0.18 * speed
        }
        // Drones fire periodically. Cadence loosened so a single drone
        // doesn't pin the player with rapid shots.
        for i in drones.indices where drones[i].x > 0.20 && drones[i].x < 1.0 {
            if pulseTime >= drones[i].nextFireAt {
                spawnEnemyBulletFromDrone(drones[i])
                drones[i].nextFireAt = pulseTime + Double.random(in: 3.8 ... 5.5)
            }
        }
        drones.removeAll { $0.x < -0.2 || $0.consumed }

        // Move bullets along their (vx, vy) velocity.
        for i in bullets.indices {
            bullets[i].x += dt * bullets[i].vx
            bullets[i].y += dt * bullets[i].vy
        }
        bullets.removeAll { $0.x > 1.2 || $0.y < -0.05 || $0.y > 1.1 }

        // Move enemy bullets toward bike (continuous velocity set at spawn).
        for i in enemyBullets.indices {
            enemyBullets[i].x += dt * enemyBullets[i].vx
            enemyBullets[i].y += dt * enemyBullets[i].vy
        }
        enemyBullets.removeAll { $0.x < -0.05 || $0.x > 1.2 || $0.y < -0.05 || $0.y > 1.1 }

        // Firing pulse expiry
        if isFiring && pulseTime > firingPulseEnd {
            isFiring = false
        }

        // Boss arrival
        if !bossActive && elapsed >= bossArrivalSeconds {
            spawnBoss()
        }
        if bossActive {
            tickBoss(dt: dt)
        }

        // Removed auto-win-by-time-survival. Boss kill is now the only
        // win path (or manual BAIL for end-without-victory).

        // Collisions
        resolveCollisions()
    }

    // MARK: - Spawning

    private func spawnEntity() {
        guard !showBriefing, !gameOver, !bossActive else { return }
        // Grace period — no spawns for the first 3.5s so the player can
        // orient + try the drag controls before the first hazard lands.
        guard elapsed > 3.5 else { return }

        // Don't stack threats too tightly:
        //   • Obstacles enter from LEFT (x=-0.1) and travel RIGHT.
        //   • Drones enter from RIGHT (x=1.1) and travel LEFT.
        let recentObstacle = obstacles.contains(where: { $0.x < 0.18 })
        let recentDrone    = drones.contains(where: { $0.x > 0.85 })

        // Random Y within the play zone. For the first 8 seconds, bias the
        // spawn away from the bike's current Y so the opener isn't brutal.
        var spawnY = randomPlayY()
        if elapsed < 8.0 && abs(spawnY - bikePos.y) < 0.08 {
            // Re-roll once to a safer Y far from the bike.
            spawnY = bikePos.y > (playMinY + playMaxY) / 2
                ? CGFloat.random(in: playMinY ... (bikePos.y - 0.08))
                : CGFloat.random(in: (bikePos.y + 0.08) ... playMaxY)
        }

        let roll = Int.random(in: 0..<100)
        if roll < 35 {
            // Drone chaser — spawn at right edge, will drift leftward.
            guard !recentDrone else { return }
            drones.append(Drone(
                x: 1.1, y: spawnY,
                nextFireAt: pulseTime + Double.random(in: 1.5 ... 3.0)
            ))
        } else if roll < 75 {
            // Civilian hovercar — spawned at left edge (ahead of bike), the
            // bike passes them as it overtakes. They scroll rightward.
            guard !recentObstacle else { return }
            let kind: ObstacleKind = Bool.random() ? .carA : .carB
            // Slower vx so player has reaction time. Cars are ~3-4s from
            // spawn to bike position.
            obstacles.append(Obstacle(x: -0.1, y: spawnY, kind: kind, vx: 0.18))
        } else {
            // Energy barrier — static highway hazard, scrolls right with
            // the world as the bike passes. Slower than before (0.45 → 0.32)
            // so reaction window is ~2s instead of ~1.3s.
            guard !recentObstacle else { return }
            obstacles.append(Obstacle(x: -0.1, y: spawnY, kind: .barrier, vx: 0.32))
        }
    }

    private func spawnEnemyBulletFromDrone(_ d: Drone) {
        // Bullet originates at the drone's position and aims toward the
        // bike's CURRENT position (not predictive — player can dodge by
        // moving anywhere in the 2D play zone).
        let dx = bikePos.x - d.x
        let dy = bikePos.y - d.y
        let mag = max(0.01, sqrt(dx * dx + dy * dy))
        let v: CGFloat = 0.40
        enemyBullets.append(EnemyBullet(
            x: d.x, y: d.y,
            vx: dx / mag * v, vy: dy / mag * v
        ))
        playSfx("gunshot_pistol", volume: 0.6)
    }

    private func spawnBoss() {
        bossActive = true
        bossX = 1.15
        bossYVisual = (playMinY + playMaxY) / 2
        bossY = bossYVisual
        bossYSwapAt = pulseTime + 3.0
        // Clear smaller threats — boss is the focal challenge.
        drones.removeAll()
        obstacles.removeAll()
        playSfx("agi_arrival_glitch", volume: 0.7)
    }

    private func tickBoss(dt: CGFloat) {
        // Boss slides in from the right to ~0.78 of screen, then bobs and
        // wanders vertically periodically while firing.
        let targetX: CGFloat = 0.78
        if bossX > targetX {
            bossX -= dt * 0.18
        }
        // Smoothly chase the current Y target.
        bossYVisual += (bossY - bossYVisual) * dt * 2.0

        // Periodically pick a new Y target somewhere in the play zone.
        if pulseTime >= bossYSwapAt {
            bossY = CGFloat.random(in: playMinY ... playMaxY)
            bossYSwapAt = pulseTime + Double.random(in: 2.0 ... 3.5)
        }

        // Fire pattern: a 5-bullet spread every 1.4s when boss is near
        // steady state position. Bigger spread + faster cadence + more
        // bullets so the boss actually feels dangerous rather than
        // background scenery.
        if bossX < targetX + 0.05 && pulseTime.truncatingRemainder(dividingBy: 1.4) < dt {
            for yOffset in [-0.08, -0.04, 0, 0.04, 0.08] as [CGFloat] {
                let dx = bikePos.x - bossX
                let dy = bikePos.y + yOffset - bossYVisual
                let mag = max(0.01, sqrt(dx * dx + dy * dy))
                let v: CGFloat = 0.65
                enemyBullets.append(EnemyBullet(
                    x: bossX, y: bossYVisual,
                    vx: dx / mag * v, vy: dy / mag * v
                ))
            }
            playSfx("mech_autocannon", volume: 0.55)
        }
    }

    // MARK: - Collisions

    private func resolveCollisions() {
        // Player bullets vs drones — 2D distance check (no lanes).
        for bi in bullets.indices.reversed() where bi < bullets.count {
            let b = bullets[bi]
            for di in drones.indices where !drones[di].consumed {
                if abs(drones[di].x - b.x) < 0.07 && abs(drones[di].y - b.y) < 0.05 {
                    drones[di].hp -= 1
                    bullets.remove(at: bi)
                    playSfx("hit_metal", volume: 0.7)
                    if drones[di].hp <= 0 {
                        drones[di].consumed = true
                    }
                    break
                }
            }
        }
        // Player bullets vs boss.
        if bossActive {
            for bi in bullets.indices.reversed() where bi < bullets.count {
                let b = bullets[bi]
                if abs(bossX - b.x) < 0.10 && abs(bossYVisual - b.y) < 0.10 {
                    bossHpRemaining -= 1
                    bullets.remove(at: bi)
                    playSfx("hit_metal")
                    if bossHpRemaining <= 0 {
                        bossActive = false
                        playSfx("agi_death")
                        finishGame(win: true)
                        return
                    }
                }
            }
        }
        // Player vs obstacles — 2D bounding-box check around the bike.
        // Hitbox is slightly smaller than the sprite for forgiveness.
        if pulseTime > iframeUntil {
            for i in obstacles.indices where !obstacles[i].consumed {
                let ob = obstacles[i]
                if abs(ob.x - bikePos.x) < 0.08 && abs(ob.y - bikePos.y) < 0.06 {
                    takeHit()
                    obstacles[i].consumed = true
                    break
                }
            }
        }
        // Player vs enemy bullets.
        if pulseTime > iframeUntil {
            for bi in enemyBullets.indices.reversed() {
                let b = enemyBullets[bi]
                if abs(b.x - bikePos.x) < 0.04 && abs(b.y - bikePos.y) < 0.04 {
                    takeHit()
                    enemyBullets.remove(at: bi)
                    break
                }
            }
        }
    }

    private func takeHit() {
        hp -= 1
        iframeUntil = pulseTime + 1.2
        playSfx("player_hit")
        HapticsManager.shared.playerKilled()
        if hp <= 0 {
            finishGame(win: false)
        }
    }

    // MARK: - End / bail

    private func finishGame(win: Bool) {
        guard !gameOver else { return }
        gameOver = true
        didWin = win
        tickTimer?.cancel()
        spawnTimer?.cancel()
        if win {
            HapticsManager.shared.victory()
            playSfx("mission_victory")
            // Record the chase as a completed mission so the mission-select
            // card flips to "completed" + the base payout credits the wallet.
            // Score blends time-survived + boss-down bonus so a slow win still
            // banks something and a clean win banks more.
            // Faster win = higher score (1500 floor at long fights, up to
            // ~1500 if the gunship drops fast). Caps so a slow win still pays.
            let chaseScore = max(500, 1500 - Int(elapsed * 4) + hp * 100)
            MissionStatsStore.shared.recordVictory(
                missionId: "Mission003_5",
                score: chaseScore,
                dataAcquired: false,
                grimoireAcquired: false
            )
        } else {
            HapticsManager.shared.defeat()
            playSfx("mission_defeat")
        }
    }

    private func bailOut() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .finishHoverbikeChase)
    }
}
