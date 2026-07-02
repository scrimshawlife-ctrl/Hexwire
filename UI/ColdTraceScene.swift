import SwiftUI
import Combine

// MARK: - M5.5 "Cold Trace" — Cipher solo matrix dive (process triage)
//
// Real-time process-triage scene. Cipher (player) jacks into the Akashic
// Fragment — a live Drachenwerk matrix entity — to read it from the inside.
// Multiple "processes" (ICE constructs) spawn around her on countdown
// timers; she has to neutralize each with the matching command tool before
// the timer runs out.
//
// FLOW
//   .entering           — brief "DESCENDING" narration overlay
//   .crustTutorial      — Layer 1: 1 process at a time, learn the loop
//   .siftEscalation     — Layer 2: 2-3 simultaneous, faster spawns
//   .daemonBoss         — Layer 3: the Core Daemon, 3-phase boss
//   .victory / .defeat  — end
//
// CONTROLS
//   3 tool buttons at the bottom of the screen:
//     DECRYPT  (cyan)     — counters Lockbit + (sustained) Cipherwall
//     OVERLOAD (orange)   — counters Hunter-Killer
//     SPOOF    (magenta)  — counters Sniffer
//   Tap a tool → auto-targets the most-urgent matching process.
//   HOLD a tool (sustained) → fills the Cipherwall's decrypt-meter.
//   Wrong tool tap → small self-damage. Process expires → full damage.
//
// TRACE (the namesake)
//   A SYSTEM TRACE meter rises passively (faster the deeper you dive) and
//   jumps on every mistake (expired process / wrong tool); clean banishes
//   bleed it back down. If it caps, the system gets a LOCK: a ~5s sweep with
//   accelerated spawns + chip damage Cipher must ride out (red edge wash).
//   Finishing the dive without ever being locked = a "GHOST RUN" score bonus.
//
// OVERCLOCK (the release)
//   Clean banishes charge an OVERCLOCK meter; pop it for a ~4.5s bullet-time
//   blitz — ICE/boss/spawns crawl, every banish is instant (even HOLD-type),
//   and the trace drains. The power-fantasy counter-pole to the trace lock.
//
// SMARTER ICE (staged reads — ramps by layer)
//   Sift adds POLYMORPH (masquerades as a different-tool type until it tells).
//   The Daemon layer adds SHIELDED (needs a crack-then-banish) and FORKBOMB
//   (splits in two if you let it linger). Crust stays clean.
//
// ATMOSPHERE
//   Screen shake + banish-chain flashes + layer glitch-wipes; the Daemon
//   taunts you in matrix-text; the world corrupts (glitch slices + phantom
//   glyphs) deeper into the dive.

// MARK: - Models

/// Command-tool the player selects from the bottom action row.
enum ColdTraceTool: String, CaseIterable {
    case decrypt
    case overload
    case spoof

    /// Display label for the button + feedback.
    var label: String {
        switch self {
        case .decrypt:  return "DECRYPT"
        case .overload: return "OVERLOAD"
        case .spoof:    return "SPOOF"
        }
    }
    /// Hex tint — drives button color, ring color, particle color.
    var hex: String {
        switch self {
        case .decrypt:  return "00DDFF"
        case .overload: return "FF8833"
        case .spoof:    return "FF44CC"
        }
    }
    /// Custom asset icon (the four `tool_*_icon` assets that already ship).
    var iconAssetName: String {
        switch self {
        case .decrypt:  return "tool_decrypt_icon"
        case .overload: return "tool_overload_icon"
        case .spoof:    return "tool_spoof_icon"
        }
    }
    /// SF Symbol fallback if the asset isn't present.
    var systemImage: String {
        switch self {
        case .decrypt:  return "key.fill"
        case .overload: return "bolt.fill"
        case .spoof:    return "theatermasks.fill"
        }
    }
}

/// ICE archetype = one kind of process. Determines which tool counters it,
/// its damage on expiration, and whether it's a HOLD-type (sustained input).
enum IceArchetype: String, CaseIterable {
    case lockbit       // ─ DECRYPT  — basic encryption layer
    case hk            // ─ OVERLOAD — aggressive Hunter-Killer drone
    case sniffer       // ─ SPOOF    — tracer eye
    case cipherwall    // ─ DECRYPT (sustained) — high-grade encryption wall

    var label: String {
        switch self {
        case .lockbit:    return "LOCKBIT"
        case .hk:         return "HUNTER-KILLER"
        case .sniffer:    return "SNIFFER"
        case .cipherwall: return "CIPHERWALL"
        }
    }
    /// The tool the player must use to neutralize this ICE.
    var counterTool: ColdTraceTool {
        switch self {
        case .lockbit, .cipherwall: return .decrypt
        case .hk:                   return .overload
        case .sniffer:              return .spoof
        }
    }
    /// HOLD-type ICE — requires sustained tool-press until sustain meter fills.
    var isHoldType: Bool { self == .cipherwall }
    /// Sustain duration (seconds) the player must HOLD the tool to crack it.
    var sustainDuration: Double { self == .cipherwall ? 1.6 : 0 }
    /// Countdown before damage tick (seconds to neutralize).
    var countdownTime: Double {
        switch self {
        case .lockbit:    return 4.5
        case .hk:         return 3.2
        case .sniffer:    return 3.8
        case .cipherwall: return 6.5   // longer because it's a hold
        }
    }
    /// Damage dealt to Cipher's deck if process expires.
    var damageOnExpire: Int {
        switch self {
        case .lockbit:    return 1
        case .hk:         return 2
        case .sniffer:    return 1
        case .cipherwall: return 2
        }
    }
}

/// One live ICE process. Drifts inward from its spawn point over time;
/// `countdown` decreases. If banished > 0 it's fading out and will be culled.
struct ColdTraceProcess: Identifiable, Equatable {
    let id = UUID()
    let archetype: IceArchetype
    /// Position in normalized arena space (-1...+1 around Cipher).
    var position: CGPoint
    /// Direction unit vector pointing toward Cipher (center).
    var direction: CGVector
    /// Seconds remaining before the process expires + damages Cipher.
    var countdown: Double
    /// Initial countdown — used by the visual countdown ring (% remaining).
    let maxCountdown: Double
    /// Fade-out timer post-banish (0 = alive, → 1 = fully dissipated).
    var banished: Double = 0
    /// For HOLD-type processes — progress 0...1 of the sustained decrypt.
    var sustainProgress: Double = 0

    // MARK: Smarter-ICE modifiers (staged by layer — see applyModifiers)
    /// Polymorph — masquerades as this archetype until `revealIn` hits 0; the
    /// player must wait for the tell. The REAL counter is always `archetype`.
    var disguisedAs: IceArchetype? = nil
    var revealIn: Double = 0
    /// Shielded — extra correct taps needed before it banishes.
    var shieldHits: Int = 0
    /// Forkbomb — splits into two if it lingers past its danger threshold.
    var forks: Bool = false
    var hasForked: Bool = false

    /// What the player SEES (disguise until revealed). Counter logic always
    /// uses the real `archetype`.
    var shownArchetype: IceArchetype { disguisedAs ?? archetype }
}

/// Boss attack-phase machine (same pattern as MirrorlineScene's Mirror-Sable).
private enum DaemonAttackPhase: Equatable {
    case idle
    case strikingP1       // P1 — direct strike, can be deflected by ANY correct tool tap
    case chainingP2       // P2 — chained sequence, must tap the correct 3-tool combo
    case drainingP3       // P3 — sustained drain, must tap a tool every ~0.6s to break free
}

// MARK: - Scene

struct ColdTraceScene: View {
    @ObservedObject var manager: PhaseManager

    // MARK: Tuning
    private let maxHP: Int = 8
    /// How long an OVERCLOCK blitz lasts (seconds).
    private let overclockDuration: Double = 4.5
    /// World-time scale while overclocked — ICE/boss/spawns crawl; you don't.
    private let overclockTimeScale: Double = 0.35

    // MARK: Stages
    enum Stage: Equatable {
        case entering             // narrative beat fade-in
        case crustTutorial        // Layer 1 — single process at a time
        case siftEscalation       // Layer 2 — multi-process, faster
        case daemonBoss           // Layer 3 — boss
        case victory
        case defeat
    }

    // MARK: State
    @State private var stage: Stage = .entering
    @State private var stageTimer: Double = 0
    @State private var playerHP: Int = 8
    @State private var processes: [ColdTraceProcess] = []
    @State private var nextSpawnAt: Double = 1.5
    @State private var spawnedThisStage: Int = 0
    @State private var spawnGoalThisStage: Int = 4

    // Tool state (which button is currently pressed; nil if none)
    @State private var heldTool: ColdTraceTool? = nil
    @State private var heldStartedAt: Date? = nil
    /// Last tool-tap feedback (a small badge that flashes near the tool button).
    @State private var lastTappedTool: ColdTraceTool? = nil
    @State private var lastToolFeedbackHold: Double = 0

    // Boss state
    @State private var bossPhase: Int = 1
    @State private var bossHP: Int = 22
    @State private var bossAttackPhase: DaemonAttackPhase = .idle
    @State private var bossAttackTimer: Double = 0
    @State private var bossCastingTool: ColdTraceTool = .decrypt
    @State private var bossCastWindupDuration: Double = 0
    @State private var bossSummonCooldown: Double = 0
    @State private var bossRevealShown: Bool = false
    /// For P2 (chain) — the sequence of tools the player must tap in order.
    @State private var bossChainSequence: [ColdTraceTool] = []
    @State private var bossChainProgress: Int = 0
    // Just-in-time boss tutorials: the first time each Daemon attack type fires,
    // show a prominent how-to callout (the upfront wall is minutes old by then)
    // and give that first cast extra time to read it.
    @State private var taughtP1 = false
    @State private var taughtP2 = false
    @State private var taughtP3 = false
    @State private var bossTutorialText: String = ""
    @State private var bossTutorialUntil: Double = 0   // clock-based expiry
    /// For P3 (drain) — countdown timer the player must reset by tapping any tool.
    @State private var bossDrainTickAt: Double = 0

    // MARK: Trace ("Cold Trace") — the system hunting the runner.
    // Rises passively (faster the deeper you dive) and jumps on every mistake;
    // clean banishes bleed it back down. If it caps, the system gets a LOCK on
    // Cipher: a ~5s danger sweep (accelerated spawns + chip damage) she has to
    // ride out. This is the mechanic the mission is named for.
    @State private var trace: Double = 0          // 0...1 system-trace meter
    @State private var traceLocked: Bool = false  // system has a lock — danger window
    @State private var traceLockTimer: Double = 0 // seconds left in the lock sweep
    @State private var traceChipAt: Double = 0    // countdown to next lock chip-damage
    @State private var traceLockCount: Int = 0    // total locks this run (scoring)

    // MARK: OVERCLOCK — the power moment. Built by clean, fast banishes; pop it
    // for a short bullet-time blitz where ICE/boss/spawns crawl, your banishes
    // are instant (even HOLD-type), and the trace drains. The release pole that
    // answers the trace lock's pressure pole.
    @State private var overclock: Double = 0       // 0...1 charge
    @State private var overclockActive: Bool = false
    @State private var overclockTimer: Double = 0  // seconds left while active

    // Overlays
    @State private var bannerText: String = ""
    @State private var bannerExpires: Date = .distantPast
    @State private var tutorialDismissed: Bool = false
    @State private var feedbackText: String = ""
    @State private var feedbackColor: String = "FFFFFF"
    @State private var feedbackHold: Double = 0
    @State private var hitFlash: Double = 0
    @State private var shakeAmount: Double = 0     // decaying screen-shake magnitude (pts)
    @State private var endGameOver: Bool = false

    // Juice + atmosphere
    @State private var clock: Double = 0           // monotonic seconds (never reset)
    @State private var chainCount: Int = 0         // consecutive clean banishes
    @State private var chainExpireAt: Double = 0
    @State private var wipeFlash: Double = 0       // layer-transition glitch wipe
    @State private var daemonLine: String = ""     // Daemon taunt text
    @State private var daemonLineExpires: Date = .distantPast
    @State private var lastTauntAt: Double = -100
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

                // Active process orbs orbiting Cipher
                // Core Daemon — anchored UPPER-REAR. Drawn BEFORE Cipher so she
                // visually occludes any silhouette overlap, and the boss reads
                // as "looming in the back" rather than competing for center stage.
                // Slight off-center X + smaller scale + dimmer opacity sells the
                // depth gap so they never appear to clash.
                if stage == .daemonBoss && !bossRevealShown {
                    // Larger + always in motion: drifts side-to-side, bobs, and
                    // "breathes" so the Core Daemon reads as a live, looming
                    // entity rather than a static decal. (Drives off `clock`.)
                    daemonView
                        .scaleEffect(0.98 + 0.04 * sin(clock * 1.4))
                        .opacity(0.94)
                        .position(x: geo.size.width / 2 - 22 + CGFloat(sin(clock * 0.7)) * 30,
                                  y: geo.size.height * 0.31 + CGFloat(sin(clock * 1.6)) * 16)  // nudged down clear of the HUD bars
                }

                // Process orbit + Cipher anchored at the LOWER third of screen.
                // Both move together so processes always orbit Cipher's plane
                // and never drift up into the daemon's airspace.
                processesLayer(geo: geo)

                // Cipher matrix-avatar — anchored low-center, slightly offset
                // OPPOSITE the daemon so the two silhouettes form a diagonal
                // composition instead of a head-on stack.
                cipherView
                    .position(x: geo.size.width / 2 + (stage == .daemonBoss ? 24 : 0),
                              y: geo.size.height * 0.62)

                // Boss attack prompt — sigil ring + instruction text.
                // Sits in the buffer zone between the daemon (top) and Cipher
                // (bottom) so it never overlaps either sprite.
                if stage == .daemonBoss && bossAttackPhase != .idle {
                    bossAttackPromptOverlay
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.40)
                        .allowsHitTesting(false)
                }

                // First-time how-to callout for each Daemon attack type.
                if clock < bossTutorialUntil && !bossTutorialText.isEmpty {
                    Text(bossTutorialText)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(16)
                        .frame(maxWidth: 340)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.92))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "FF44CC"), lineWidth: 1.5))
                        )
                        .shadow(color: Color(hex: "FF44CC").opacity(0.6), radius: 14)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.18)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Phantom atmosphere (Daemon layer) + matrix corruption.
                if stage == .daemonBoss { phantomGlyphs(geo: geo) }
                if corruptionIntensity > 0.01 { corruptionOverlay(geo: geo) }

                // Red edge wash while the system has a lock.
                if traceLocked { traceLockVignette }
                // Neon bloom while overclocked.
                if overclockActive { overclockOverlay }

                // HUD
                hudHeader.frame(width: geo.size.width)

                // Daemon trash-talk.
                if !daemonLine.isEmpty { daemonLineOverlay }

                // Tool buttons at bottom (OVERCLOCK control sits just above them)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    overclockButton
                    toolBar
                    Spacer(minLength: 0).frame(height: 30)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                if wipeFlash > 0 {
                    Rectangle()
                        .fill(Color(hex: "AAF0FF").opacity(wipeFlash * 0.55))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if !bannerText.isEmpty { bannerOverlay }
                if feedbackHold > 0 { feedbackOverlay }
                if !tutorialDismissed && !endGameOver { tutorialOverlay }
                if endGameOver { endOverlay }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(x: CGFloat(sin(stageTimer * 90) * shakeAmount),
                    y: CGFloat(cos(stageTimer * 71) * shakeAmount))
        }
        .ignoresSafeArea()
        .onAppear { startMission() }
        .onReceive(ticker) { _ in tick() }
    }

    // MARK: Backdrop

    private var backdropName: String {
        switch stage {
        case .crustTutorial:      return "m5_5_crust"
        case .siftEscalation:     return "m5_5_sift"
        case .daemonBoss:         return "m5_5_daemon"
        case .entering:           return "m5_5_crust"   // pre-show the crust during fade-in
        case .victory, .defeat:   return "m5_5_daemon"
        }
    }

    private var backdropView: some View {
        Image(backdropName)
            .resizable()
            .scaledToFill()
            .overlay(Color.black.opacity(stage == .entering ? 0.7 : 0.25))
    }

    // MARK: Cipher avatar

    @ViewBuilder
    private var cipherView: some View {
        let img = BasementBrawlSpriteCache.shared.image(named: cipherSpriteName)
        if let img {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 280)
                .opacity(hitFlash > 0 ? 0.55 : 1.0)
                .scaleEffect(hitFlash > 0 ? 0.95 : 1.0)
        } else {
            // Pre-asset fallback — labelled box
            Rectangle()
                .fill(Color(hex: "00FF88").opacity(0.3))
                .frame(width: 80, height: 200)
                .overlay(Text("CIPHER").foregroundColor(.white))
        }
    }

    /// Picks the right Cipher frame based on her current state.
    private var cipherSpriteName: String {
        if endGameOver && didWin    { return "cipher_avatar_victory_0" }
        if hitFlash > 0             { return "cipher_avatar_hit_0" }
        if lastToolFeedbackHold > 0.5 { return "cipher_avatar_command_0" }
        // Subtle breathing cycle every ~1.4s
        let breath = Int(Date().timeIntervalSinceReferenceDate * 0.7) % 2
        return breath == 0 ? "cipher_avatar_idle_0" : "cipher_avatar_idle_1"
    }

    // MARK: Daemon boss

    @ViewBuilder
    private var daemonView: some View {
        let img = BasementBrawlSpriteCache.shared.image(named: daemonSpriteName)
        if let img {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 300)
        }
    }

    private var daemonSpriteName: String {
        if endGameOver && didWin { return "daemon_reveal" }
        if bossHP <= 0           { return "daemon_reveal" }
        switch bossAttackPhase {
        case .strikingP1: return "daemon_p1_strike"
        case .chainingP2: return "daemon_p2_chain"
        case .drainingP3: return "daemon_p3_drain"
        case .idle:
            // Gentle 3-frame idle sway (~1.6 fps) so the daemon breathes
            // instead of standing frozen. Frames cycle daemon_idle_0/1/2.
            return "daemon_idle_\(Int(stageTimer * 1.6) % 3)"
        }
    }

    // MARK: Process layer (the ICE constructs floating around Cipher)

    @ViewBuilder
    private func processesLayer(geo: GeometryProxy) -> some View {
        ForEach(processes) { p in
            let cx = geo.size.width / 2
            let cy = geo.size.height * 0.62   // matches cipherView's lowered center
            let r = min(geo.size.width, geo.size.height) * 0.42
            let x = cx + p.position.x * r
            let y = cy + p.position.y * r
            let shown = p.shownArchetype           // disguise until revealed
            let hex = shown.counterTool.hex
            let disguised = p.disguisedAs != nil
            // Polymorph scramble flicker while still masquerading.
            let flicker = disguised ? (0.5 + 0.5 * sin(stageTimer * 24 + Double(p.position.x) * 9)) : 1.0

            ZStack {
                // Forkbomb tell — twin offset rings warn of an imminent split.
                if p.forks && !p.hasForked && p.banished == 0 {
                    Circle().stroke(Color(hex: hex).opacity(0.35), lineWidth: 2)
                        .frame(width: 96, height: 96).offset(x: 11, y: 7)
                    Circle().stroke(Color(hex: hex).opacity(0.35), lineWidth: 2)
                        .frame(width: 96, height: 96).offset(x: -11, y: -7)
                }

                // Sprite (idle / attack / banish frame)
                if let img = BasementBrawlSpriteCache.shared.image(named: processSpriteName(p)) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .opacity((1.0 - p.banished * 0.85) * flicker)
                        .scaleEffect(1.0 + p.banished * 0.3)
                } else {
                    Circle()
                        .stroke(Color(hex: hex), lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .overlay(Text(shown.label)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundColor(.white))
                        .opacity(flicker)
                }

                // Shielded — dashed ring; needs an extra correct tap to crack.
                if p.shieldHits > 0 && p.banished == 0 {
                    Circle()
                        .stroke(Color.white.opacity(0.85),
                                style: StrokeStyle(lineWidth: 2.5, dash: [5, 5]))
                        .frame(width: 114, height: 114)
                }

                // Countdown ring around the sprite — shrinks as it approaches expiry
                if p.banished == 0 {
                    Image("process_ring")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(hex: hex))
                        .frame(width: 130, height: 130)
                        .opacity(0.85)
                        .overlay(
                            Circle()
                                .trim(from: 0, to: CGFloat(max(0, min(1, p.countdown / p.maxCountdown))))
                                .stroke(Color(hex: hex),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 124, height: 124)
                        )
                }

                // Tool-hint glyph badge — sits below the sprite. While a
                // polymorph is scrambled it shows "??" so the player has to
                // wait for the reveal instead of reading the (fake) type.
                if p.banished == 0 {
                    VStack(spacing: 1) {
                        Spacer().frame(height: 92)
                        Text(disguised ? "??" : shown.counterTool.label)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.black.opacity(0.75))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color(hex: hex), lineWidth: 1)
                                    )
                            )
                            .foregroundColor(Color(hex: hex))
                    }
                    .frame(width: 130, height: 130)
                }

                // HOLD-type sustain progress bar (under the sprite)
                if p.archetype.isHoldType && p.banished == 0 && p.sustainProgress > 0 {
                    VStack {
                        Spacer().frame(height: 116)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 80, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: p.archetype.counterTool.hex))
                                .frame(width: 80 * CGFloat(p.sustainProgress), height: 5)
                        }
                    }
                    .frame(width: 130, height: 140)
                }
            }
            .position(x: x, y: y)
        }
    }

    /// Pick the right sprite frame for a process based on whether it's
    /// idle / about to expire / mid-banish.
    private func processSpriteName(_ p: ColdTraceProcess) -> String {
        let base: String
        switch p.shownArchetype {
        case .lockbit:    base = "lockbit"
        case .hk:         base = "hk"
        case .sniffer:    base = "sniffer"
        case .cipherwall: base = "cipherwall"
        }
        if p.banished > 0 {
            return "\(base)_banish_0"
        }
        // Last second before expiry → switch to attack pose
        if p.countdown < 1.0 {
            return "\(base)_attack_0"
        }
        return "\(base)_idle_0"
    }

    // MARK: HUD

    private var hudHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CIPHER")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color(hex: "00DDFF"))
                    hpBar(value: playerHP, max: maxHP, color: "00DDFF")
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(stageLabel)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(hex: "AACCEE"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if stage == .daemonBoss {
                        Text("PHASE \(bossPhase)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "FF44CC"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if stage == .daemonBoss {
                        Text("DAEMON")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "FF44CC"))
                        hpBar(value: bossHP, max: 22, color: "FF44CC", reverse: true)
                    } else {
                        Text(spawnProgressText)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "AACCEE"))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 54)

            traceBar
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
        // FIXED total width so a 22-segment boss bar can't balloon past the
        // screen and shove the bars off-edge — segment width scales to fit.
        let totalW: CGFloat = 116
        let spacing: CGFloat = 2
        let segW = Swift.max(3, (totalW - spacing * CGFloat(Swift.max(1, max - 1))) / CGFloat(max))
        return HStack(spacing: spacing) {
            ForEach(0..<max, id: \.self) { i in
                let active = (i < value)
                Rectangle()
                    .fill(active ? Color(hex: color) : Color.black.opacity(0.6))
                    .frame(width: segW, height: 10)
                    .overlay(Rectangle().stroke(Color(hex: color), lineWidth: 1))
            }
        }
        .frame(width: totalW, alignment: reverse ? .trailing : .leading)
        .environment(\.layoutDirection, reverse ? .rightToLeft : .leftToRight)
    }

    /// SYSTEM TRACE meter — the system's progress toward locking Cipher.
    private var traceBar: some View {
        let pct = trace
        let col: String = traceLocked
            ? "FF2222"
            : (pct > 0.66 ? "FF6622" : (pct > 0.33 ? "FFCC22" : "33CCAA"))
        let pulse = traceLocked ? 0.5 + 0.5 * sin(stageTimer * 9) : 1.0
        return VStack(spacing: 2) {
            HStack {
                Text(traceLocked ? "⚠ TRACE LOCKED" : "SYSTEM TRACE")
                    .font(.system(size: 8, weight: .black, design: .monospaced)).tracking(2)
                    .foregroundColor(Color(hex: col))
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: col))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.6))
                    Capsule().fill(Color(hex: col))
                        .frame(width: g.size.width * CGFloat(pct))
                }
            }
            .frame(height: 6)
        }
        .opacity(traceLocked ? pulse : 1.0)
        .shadow(color: traceLocked ? Color(hex: "FF2222") : .clear, radius: 8)
        .padding(.horizontal, 14)
    }

    /// Red pulsing edge wash while the system has a lock on Cipher.
    private var traceLockVignette: some View {
        let pulse = 0.35 + 0.35 * sin(stageTimer * 9)
        return Rectangle()
            .strokeBorder(Color(hex: "FF2222").opacity(pulse), lineWidth: 14)
            .blur(radius: 6)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// OVERCLOCK charge / activate control, sits just above the tool row.
    private var overclockButton: some View {
        let ready = overclock >= 1.0 && !overclockActive
        let accent = "00FFD0"
        let label = overclockActive ? "OVERCLOCK ACTIVE"
                  : (ready ? "OVERCLOCK — TAP" : "OVERCLOCK")
        let fill = overclockActive ? max(0, overclockTimer / overclockDuration) : overclock
        let glow = ready || overclockActive
        return Button(action: { tryOverclock() }) {
            VStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(2)
                    .foregroundColor(Color(hex: accent))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.55))
                        Capsule().fill(Color(hex: accent))
                            .frame(width: g.size.width * CGFloat(fill))
                    }
                }
                .frame(height: 7)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: accent).opacity(glow ? 0.95 : 0.4), lineWidth: ready ? 2 : 1))
            )
            .shadow(color: glow ? Color(hex: accent).opacity(0.7) : .clear, radius: ready ? 10 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }

    /// Saturated neon wash + edge bloom while overclocked.
    private var overclockOverlay: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "00FFD0").opacity(0.12),
                                    Color(hex: "FF00E0").opacity(0.12)],
                           startPoint: .top, endPoint: .bottom)
                .blendMode(.screen)
            Rectangle()
                .strokeBorder(Color(hex: "00FFD0").opacity(0.5), lineWidth: 12)
                .blur(radius: 8)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Daemon trash-talk — magenta matrix-text near the top.
    private var daemonLineOverlay: some View {
        Text(daemonLine)
            .font(.system(size: 13, weight: .black, design: .monospaced)).tracking(3)
            .foregroundColor(Color(hex: "FF44CC"))
            .shadow(color: Color(hex: "FF44CC").opacity(0.85), radius: 6)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.6)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 116)
            .allowsHitTesting(false)
    }

    /// Matrix corruption — faint magenta edge wash that deepens with the layer
    /// and trace, plus transient glitch slices.
    @ViewBuilder
    private func corruptionOverlay(geo: GeometryProxy) -> some View {
        let ci = corruptionIntensity
        Rectangle()
            .strokeBorder(Color(hex: "FF44CC").opacity(0.14 * ci), lineWidth: 30)
            .blur(radius: 14)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Non-interactive phantom glyphs drifting in the Daemon's airspace —
    /// pure atmosphere (a crowded, corrupted mind).
    private func phantomGlyphs(geo: GeometryProxy) -> some View {
        ForEach(0..<3, id: \.self) { i in
            let t = stageTimer * (0.3 + Double(i) * 0.12) + Double(i) * 2.1
            let rad = min(geo.size.width, geo.size.height) * (0.30 + Double(i) * 0.08)
            Image("process_ring")
                .resizable().renderingMode(.template)
                .foregroundColor(Color(hex: "FF44CC"))
                .frame(width: 54, height: 54)
                .opacity(0.05 + 0.04 * sin(t * 2))
                .position(x: geo.size.width / 2 + CGFloat(cos(t)) * rad,
                          y: geo.size.height * 0.48 + CGFloat(sin(t)) * rad)
        }
        .allowsHitTesting(false)
    }

    private var spawnProgressText: String {
        switch stage {
        case .crustTutorial:   return "CRUST \(spawnedThisStage)/\(spawnGoalThisStage)"
        case .siftEscalation:  return "SIFT \(spawnedThisStage)/\(spawnGoalThisStage)"
        default:               return ""
        }
    }

    private var stageLabel: String {
        switch stage {
        case .entering:           return "DESCENDING"
        case .crustTutorial:      return "THE CRUST"
        case .siftEscalation:     return "THE SIFT"
        case .daemonBoss:         return "THE DAEMON"
        case .victory, .defeat:   return "END"
        }
    }

    // MARK: Tool bar (action buttons at the bottom)

    private var toolBar: some View {
        HStack(spacing: 10) {
            toolButton(.decrypt)
            toolButton(.overload)
            toolButton(.spoof)
        }
        .padding(.horizontal, 14)
    }

    private func toolButton(_ tool: ColdTraceTool) -> some View {
        let isAvailable = tutorialDismissed && !endGameOver
        let isPressed = (heldTool == tool)
        let isFlashing = (lastTappedTool == tool && lastToolFeedbackHold > 0)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: tool.hex)
                        .opacity(isAvailable ? (isPressed ? 1.0 : 0.85) : 0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: Color(hex: tool.hex).opacity(isFlashing ? 0.9 : (isPressed ? 0.6 : 0.3)),
                        radius: isFlashing ? 16 : 8)

            VStack(spacing: 4) {
                if let img = UIImage(named: tool.iconAssetName) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.black)
                }
                Text(tool.label)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isAvailable else { return }
                    if heldTool != tool {
                        heldTool = tool
                        heldStartedAt = Date()
                        toolPressBegin(tool)
                    }
                }
                .onEnded { _ in
                    guard isAvailable else { return }
                    if heldTool == tool {
                        toolPressEnd(tool)
                        heldTool = nil
                        heldStartedAt = nil
                    }
                }
        )
    }

    // MARK: - Game loop

    private func startMission() {
        playerHP = maxHP
        stage = .entering
        stageTimer = 0
        processes = []
        spawnedThisStage = 0
        spawnGoalThisStage = 4
        nextSpawnAt = 1.5
        heldTool = nil
        heldStartedAt = nil
        bossPhase = 1
        bossHP = 22
        resetBossAttack()
        bossRevealShown = false
        trace = 0; traceLocked = false; traceLockTimer = 0; traceChipAt = 0; traceLockCount = 0
        overclock = 0; overclockActive = false; overclockTimer = 0
        shakeAmount = 0
        clock = 0; chainCount = 0; chainExpireAt = 0; wipeFlash = 0
        daemonLine = ""; lastTauntAt = -100
        taughtP1 = false; taughtP2 = false; taughtP3 = false
        bossTutorialText = ""; bossTutorialUntil = 0
        showBanner("DESCENDING — THE CRUST")
    }

    private func resetBossAttack() {
        bossAttackPhase = .idle
        bossAttackTimer = 0
        bossCastingTool = .decrypt
        bossSummonCooldown = 0
        bossCastWindupDuration = 0
        bossChainSequence = []
        bossChainProgress = 0
        bossDrainTickAt = 0
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
        clock += dt
        if hitFlash > 0 { hitFlash = max(0, hitFlash - dt) }
        if shakeAmount > 0 { shakeAmount = max(0, shakeAmount - dt * 55) }
        if wipeFlash > 0 { wipeFlash = max(0, wipeFlash - dt * 2.4) }
        if !daemonLine.isEmpty, Date() > daemonLineExpires { daemonLine = "" }
        if feedbackHold > 0 { feedbackHold = max(0, feedbackHold - dt) }
        if lastToolFeedbackHold > 0 { lastToolFeedbackHold = max(0, lastToolFeedbackHold - dt) }
        if !bannerText.isEmpty, Date() > bannerExpires { bannerText = "" }

        // OVERCLOCK runs on real time; everything else (ICE, boss, spawns) is
        // scaled down while it's active — bullet time for the world, not you.
        if overclockActive {
            overclockTimer -= dt
            if overclockTimer <= 0 { endOverclock() }
        }
        let worldDt = overclockActive ? dt * overclockTimeScale : dt

        tickStage(dt: worldDt)
        tickProcesses(dt: worldDt)
        tickHeldTool(dt: worldDt)
        tickTrace(dt: dt)   // trace logic uses real time (drains during overclock)
    }

    // MARK: - Trace meter

    private func tickTrace(dt: Double) {
        if traceLocked {
            traceLockTimer -= dt
            traceChipAt -= dt
            if traceChipAt <= 0 {
                traceChipAt = 2.0
                applyDamageToPlayer(amount: 1)
                if !endGameOver { showFeedback("TRACE SWEEP — −1 HP", color: "FF3344") }
            }
            if traceLockTimer <= 0 { releaseTraceLock() }
            return
        }
        // While overclocked you're ahead of the system — the trace bleeds out.
        if overclockActive { addTrace(-0.10 * dt); return }
        // Passive rise — deeper layers run hotter.
        let rise: Double
        switch stage {
        case .crustTutorial:  rise = 0.010
        case .siftEscalation: rise = 0.020
        case .daemonBoss:     rise = 0.024
        default:              rise = 0
        }
        addTrace(rise * dt)
    }

    /// Adjust the trace meter. Positive = the system gains on you (mistakes),
    /// negative = a clean banish cools it. Capping triggers a lock sweep.
    private func addTrace(_ d: Double) {
        guard !traceLocked, !endGameOver else { return }
        trace = max(0, min(1.0, trace + d))
        if trace >= 1.0 { enterTraceLock() }
    }

    private func enterTraceLock() {
        traceLocked = true
        trace = 1.0
        traceLockCount += 1
        traceLockTimer = 5.0
        traceChipAt = 1.0          // first sweep lands ~1s in
        hitFlash = 0.3
        showBanner("⚠ TRACE LOCKED — EVADE")
        showFeedback("SYSTEM HAS YOUR SIGNAL", color: "FF3344")
        HapticsManager.shared.playerDamaged()
        SFXManager.shared.play("agi_arrival_glitch")
        triggerShake(8)
        daemonTaunt(.lock)
    }

    private func releaseTraceLock() {
        traceLocked = false
        trace = 0.45               // shaken, but still warm
        showBanner("TRACE SHAKEN — KEEP MOVING")
        showFeedback("SIGNAL LOST", color: "BBFF44")
        SFXManager.shared.play("terminal_correct")
    }

    // MARK: - Overclock

    private func tryOverclock() {
        guard overclock >= 1.0, !overclockActive, !endGameOver, tutorialDismissed else { return }
        overclockActive = true
        overclockTimer = overclockDuration
        overclock = 0
        showBanner("⚡ OVERCLOCK — JACK THE CLOCK")
        showFeedback("TIME IS YOURS", color: "00FFD0")
        HapticsManager.shared.victory()
        SFXManager.shared.play("agi_arrival_glitch")
        triggerShake(6)
        daemonTaunt(.overclock)
    }

    private func endOverclock() {
        overclockActive = false
        overclockTimer = 0
        showFeedback("OVERCLOCK FADED", color: "00FFD0")
    }

    private func tickStage(dt: Double) {
        switch stage {
        case .entering:
            // Brief descent narration before Crust kicks in
            if stageTimer >= 1.5 {
                transitionTo(.crustTutorial)
            }
        case .crustTutorial:
            spawnLogic(dt: dt, interval: 3.2, maxLive: 1, allowed: [.lockbit, .hk, .sniffer])
            if spawnedThisStage >= spawnGoalThisStage && processes.allSatisfy({ $0.banished > 0 }) {
                transitionTo(.siftEscalation)
            }
        case .siftEscalation:
            spawnLogic(dt: dt, interval: 2.2, maxLive: 2, allowed: IceArchetype.allCases)
            if spawnedThisStage >= spawnGoalThisStage && processes.allSatisfy({ $0.banished > 0 }) {
                transitionTo(.daemonBoss)
            }
        case .daemonBoss:
            tickDaemon(dt: dt)
        case .victory, .defeat:
            break
        }
    }

    private func transitionTo(_ next: Stage) {
        stage = next
        stageTimer = 0
        processes = []
        spawnedThisStage = 0
        // Layer-change glitch wipe + jolt (skip the pre-Crust narrative fade
        // and the end states).
        if next == .crustTutorial || next == .siftEscalation || next == .daemonBoss {
            wipeFlash = 0.7
            triggerShake(6)
        }
        switch next {
        case .crustTutorial:
            spawnGoalThisStage = 7
            showBanner("THE CRUST — match the tool")
        case .siftEscalation:
            spawnGoalThisStage = 12
            playerHP = min(maxHP, playerHP + 1)
            showFeedback("LAYER CLEAR — +1 HP", color: "BBFF44")
            showBanner("THE SIFT — multiple processes")
        case .daemonBoss:
            playerHP = min(maxHP, playerHP + 1)
            showFeedback("LAYER CLEAR — +1 HP", color: "BBFF44")
            showBanner("THE DAEMON — she wears your face")
            resetBossAttack()
        case .victory:
            endGame(win: true)
        case .defeat:
            endGame(win: false)
        case .entering:
            break
        }
    }

    private func spawnLogic(dt: Double, interval: Double, maxLive: Int, allowed: [IceArchetype]) {
        guard spawnedThisStage < spawnGoalThisStage else { return }
        // While the trace has a lock, the system floods you — faster spawns and
        // one extra simultaneous process to ride out.
        let effInterval = traceLocked ? interval * 0.5 : interval
        let effMaxLive  = traceLocked ? maxLive + 1 : maxLive
        let liveCount = processes.filter { $0.banished == 0 }.count
        guard liveCount < effMaxLive else { return }
        nextSpawnAt -= dt
        if nextSpawnAt <= 0 {
            spawnProcess(allowed: allowed)
            nextSpawnAt = effInterval
        }
    }

    private func spawnProcess(allowed: [IceArchetype]) {
        // Cipher-related restriction during Crust: cycle through archetypes
        // in order so the player sees each tool used once.
        let kind: IceArchetype
        if stage == .crustTutorial {
            kind = allowed[spawnedThisStage % allowed.count]
        } else {
            kind = allowed.randomElement() ?? .lockbit
        }
        // Random spawn angle on the rim of the arena
        let angle = Double.random(in: 0..<(2 * .pi))
        let spawnPos = CGPoint(x: cos(angle), y: sin(angle))
        let dirToCenter = CGVector(
            dx: -spawnPos.x / hypot(spawnPos.x, spawnPos.y),
            dy: -spawnPos.y / hypot(spawnPos.x, spawnPos.y)
        )
        var p = ColdTraceProcess(
            archetype: kind,
            position: spawnPos,
            direction: dirToCenter,
            countdown: kind.countdownTime,
            maxCountdown: kind.countdownTime
        )
        applyModifiers(to: &p)
        processes.append(p)
        spawnedThisStage += 1
    }

    /// Stage-gated complexity ramp: Crust stays clean, Sift introduces the
    /// polymorph read, the Daemon layer can throw shields + forkbombs too.
    /// At most one modifier per process so the screen stays readable.
    private func applyModifiers(to p: inout ColdTraceProcess) {
        switch stage {
        case .siftEscalation:
            if Int.random(in: 0..<100) < 30 { disguise(&p) }
        case .daemonBoss:
            let roll = Int.random(in: 0..<100)
            if roll < 26 {
                disguise(&p)
            } else if roll < 50 && !p.archetype.isHoldType {
                p.shieldHits = 1
            } else if roll < 68 && !p.archetype.isHoldType {
                p.forks = true
            }
        default:
            break   // Crust — pure
        }
    }

    /// Make a process masquerade as a DIFFERENT-tool archetype until it tells.
    private func disguise(_ p: inout ColdTraceProcess) {
        let fakes = IceArchetype.allCases.filter { $0.counterTool != p.archetype.counterTool }
        if let fake = fakes.randomElement() {
            p.disguisedAs = fake
            p.revealIn = 1.3
        }
    }

    /// Split a forkbomb into two faster children that drift in from its spot.
    private func forkProcess(parentIndex i: Int) {
        guard processes.indices.contains(i) else { return }
        let parent = processes[i]
        processes[i].banished = 0.01   // parent dissipates into its forks
        showFeedback("FORKBOMB SPLIT", color: parent.archetype.counterTool.hex)
        triggerShake(3)
        HapticsManager.shared.playerDamaged()
        for k in 0..<2 {
            var pos = parent.position
            pos.x += (k == 0 ? 0.13 : -0.13)
            pos.y += (k == 0 ? 0.07 : -0.07)
            let mag = max(0.001, hypot(pos.x, pos.y))
            let dir = CGVector(dx: -pos.x / mag, dy: -pos.y / mag)
            let ct = parent.archetype.countdownTime * 0.6
            let child = ColdTraceProcess(
                archetype: parent.archetype,
                position: pos,
                direction: dir,
                countdown: ct,
                maxCountdown: ct
            )
            processes.append(child)
        }
    }

    private func tickProcesses(dt: Double) {
        for i in processes.indices {
            // Fade banished out
            if processes[i].banished > 0 {
                processes[i].banished = min(1.0, processes[i].banished + dt * 3)
                continue
            }
            // Tick down the countdown
            processes[i].countdown -= dt
            // Slow inward drift — visualizes urgency
            let driftSpeed = 0.06
            processes[i].position.x += processes[i].direction.dx * CGFloat(driftSpeed * dt)
            processes[i].position.y += processes[i].direction.dy * CGFloat(driftSpeed * dt)

            // Polymorph reveal — the "tell" lands; flip to the true type.
            if processes[i].disguisedAs != nil {
                processes[i].revealIn -= dt
                if processes[i].revealIn <= 0 {
                    let real = processes[i].archetype
                    processes[i].disguisedAs = nil
                    triggerShake(2)
                    showFeedback("ICE UNMASKED — \(real.label)", color: real.counterTool.hex)
                }
            }
            // Forkbomb — if it lingers past its danger threshold, it splits.
            if processes[i].forks && !processes[i].hasForked
                && processes[i].countdown <= processes[i].maxCountdown * 0.4 {
                processes[i].hasForked = true
                forkProcess(parentIndex: i)
            }
        }
        // Resolve expirations
        var indicesToRemove: [Int] = []
        for (i, p) in processes.enumerated() {
            if p.banished >= 1.0 {
                indicesToRemove.append(i)
            } else if p.banished == 0 && p.countdown <= 0 {
                applyDamageToPlayer(amount: p.archetype.damageOnExpire)
                showFeedback("\(p.archetype.label) EXECUTED — −\(p.archetype.damageOnExpire) HP", color: "FF3344")
                addTrace(0.14)   // an executed process spikes the trace hard
                breakChain()
                daemonTaunt(.mistake)
                indicesToRemove.append(i)
            }
        }
        for i in indicesToRemove.reversed() {
            processes.remove(at: i)
        }
    }

    /// Drive the HOLD-tool sustain logic. While a tool is held, the closest
    /// matching HOLD-type process fills its sustain meter. When the meter
    /// hits 1.0 the process is banished.
    private func tickHeldTool(dt: Double) {
        guard let held = heldTool else { return }
        // Find the most-urgent HOLD-type process that's countered by this tool
        var bestIdx: Int? = nil
        var bestCountdown: Double = .infinity
        for (i, p) in processes.enumerated() where p.banished == 0
            && p.archetype.isHoldType
            && p.archetype.counterTool == held
        {
            if p.countdown < bestCountdown {
                bestCountdown = p.countdown
                bestIdx = i
            }
        }
        guard let idx = bestIdx else { return }
        let arch = processes[idx].archetype
        let progress = processes[idx].sustainProgress + dt / arch.sustainDuration
        processes[idx].sustainProgress = min(1.0, progress)
        if processes[idx].sustainProgress >= 1.0 {
            banishProcess(at: idx, with: held)
        }
    }

    // MARK: - Tool press handling

    private func toolPressBegin(_ tool: ColdTraceTool) {
        lastTappedTool = tool
        lastToolFeedbackHold = 0.8

        // Boss-active interactions take priority over normal triage — but
        // only when the tap actually addresses the cast. P1/P2 casts run up
        // to ~7s while summoned processes keep 3.2–4.5s countdowns; routing
        // EVERY tap to the boss made those processes uncounterable (and
        // punished the matching tool as a wrong deflect).
        if stage == .daemonBoss && bossAttackPhase != .idle {
            if bossTapAddressesCast(tool) || !hasLiveProcess(counteredBy: tool) {
                handleBossToolTap(tool)
                return
            }
            // Tool counters a live process instead — fall through to triage.
        }

        // Otherwise — instant-tap mode: find a non-HOLD process this tool counters.
        // (HOLD processes resolve in tickHeldTool while the button is held.)
        // During OVERCLOCK every matching process — even HOLD-type — banishes
        // on a single tap, so you can blitz the whole board.
        var bestIdx: Int? = nil
        var bestCountdown: Double = .infinity
        for (i, p) in processes.enumerated() where p.banished == 0
            && (overclockActive || !p.archetype.isHoldType)
            && p.archetype.counterTool == tool
        {
            if p.countdown < bestCountdown {
                bestCountdown = p.countdown
                bestIdx = i
            }
        }

        if let idx = bestIdx {
            banishProcess(at: idx, with: tool)
            return
        }

        // If no instant target exists but a HOLD-type matches, the held-loop
        // will pick that up. So only chip damage if there's NO matching live
        // process at all.
        let hasHoldMatch = processes.contains { p in
            p.banished == 0 && p.archetype.isHoldType && p.archetype.counterTool == tool
        }
        if !hasHoldMatch {
            // Wasted action — small self-chip (only if there ARE live targets at all)
            let hasAnyLive = processes.contains { $0.banished == 0 }
            if hasAnyLive && !overclockActive {
                applyDamageToPlayer(amount: 1)
                showFeedback("WRONG TOOL — no target for \(tool.label)", color: "FF9933")
                addTrace(0.06)   // a wasted action lets the trace creep up
                breakChain()
                daemonTaunt(.mistake)
            } else {
                showFeedback("\(tool.label) — no target", color: tool.hex)
            }
        }
    }

    private func toolPressEnd(_ tool: ColdTraceTool) {
        // Nothing special — held-tool resolution already happened in tickHeldTool.
        // Reset any partial sustain progress on the still-alive process so the
        // player has to commit to a full hold, not a tap.
        for i in processes.indices where processes[i].banished == 0
            && processes[i].archetype.isHoldType
            && processes[i].archetype.counterTool == tool
            && processes[i].sustainProgress < 1.0
        {
            processes[i].sustainProgress = 0
        }
    }

    private func banishProcess(at idx: Int, with tool: ColdTraceTool) {
        guard processes.indices.contains(idx) else { return }
        // Shielded ICE: the first correct hit cracks the shield; you need a
        // second to banish. OVERCLOCK smashes straight through.
        if !overclockActive && processes[idx].shieldHits > 0 {
            processes[idx].shieldHits -= 1
            showFeedback("SHIELD CRACKED — hit it again", color: tool.hex)
            HapticsManager.shared.buttonTap()
            SFXManager.shared.play("hit_metal")
            triggerShake(2)
            return
        }
        processes[idx].banished = 0.01   // kick off fade
        let arch = processes[idx].archetype
        showFeedback("\(tool.label) → \(arch.label) BANISHED", color: tool.hex)
        HapticsManager.shared.attackHit()
        triggerShake(3)
        registerChain()
        if overclockActive {
            addTrace(-0.12)                              // banishing in overclock really cools it
        } else {
            addTrace(-0.06)                              // a clean banish cools the trace down
            overclock = min(1.0, overclock + 0.12)       // ...and charges the OVERCLOCK
        }
        if stage == .daemonBoss {
            bossHP = max(0, bossHP - 1)
        }
    }

    // MARK: - Daemon AI

    private func tickDaemon(dt: Double) {
        // HP-phase progression (15 HP): 15-11 = P1, 10-6 = P2, 5-0 = P3.
        if bossHP <= 7 && bossPhase < 3 {
            bossPhase = 3
            resetBossAttack()
            showBanner("PHASE 3 — THE DRAIN")
            processes.removeAll()
            wipeFlash = 0.7; triggerShake(7); daemonTaunt(.phase)
        } else if bossHP <= 14 && bossPhase < 2 {
            bossPhase = 2
            resetBossAttack()
            showBanner("PHASE 2 — CHAIN")
            wipeFlash = 0.7; triggerShake(7); daemonTaunt(.phase)
        }

        // P1 + P2 keep summoning ICE processes
        if bossPhase <= 2 {
            let maxLive = bossPhase == 1 ? 1 : 2
            let summonInterval: Double = bossPhase == 1 ? 4.5 : 6.0
            let liveCount = processes.filter { $0.banished == 0 }.count
            if liveCount < maxLive {
                bossSummonCooldown -= dt
                if bossSummonCooldown <= 0 {
                    spawnProcess(allowed: IceArchetype.allCases)
                    bossSummonCooldown = summonInterval
                }
            }
        }

        tickDaemonAttack(dt: dt)

        if bossHP <= 0 {
            transitionTo(.victory)
        }
    }

    /// Daemon attack-phase machine. Mirrors MirrorlineScene's pattern.
    private func tickDaemonAttack(dt: Double) {
        bossAttackTimer += dt
        switch bossAttackPhase {

        case .idle:
            let idleInterval: Double
            switch bossPhase {
            case 1:  idleInterval = 7.0
            case 2:  idleInterval = 5.5
            default: idleInterval = 0.5   // P3 starts almost immediately
            }
            if bossAttackTimer >= idleInterval {
                beginDaemonCast()
            }

        case .strikingP1:
            if bossAttackTimer >= bossCastWindupDuration {
                applyDamageToPlayer(amount: 2)
                showFeedback("DAEMON STRUCK — −2 HP", color: "FF3344")
                bossAttackPhase = .idle
                bossAttackTimer = 0
            }

        case .chainingP2:
            if bossAttackTimer >= bossCastWindupDuration {
                applyDamageToPlayer(amount: 2)
                showFeedback("CHAIN FAILED — −2 HP", color: "FF3344")
                bossAttackPhase = .idle
                bossAttackTimer = 0
            }

        case .drainingP3:
            // P3 drain: player must tap a tool every `drainTickInterval`
            // seconds or take a chip damage. The boss takes 1 damage per
            // correctly-rhythmed tap (handled in handleBossToolTap).
            let drainTickInterval: Double = 1.6
            bossDrainTickAt += dt
            if bossDrainTickAt >= drainTickInterval {
                applyDamageToPlayer(amount: 1)
                showFeedback("DRAIN HOLDS — −1 HP", color: "FF3344")
                bossDrainTickAt = 0
            }
            // P3 doesn't return to idle — only ends when bossHP hits 0
        }
    }

    private func beginDaemonCast() {
        bossAttackTimer = 0
        switch bossPhase {
        case 1:
            // P1: a single strike — any correct tool tap deflects it
            bossCastingTool = ColdTraceTool.allCases.randomElement() ?? .decrypt
            if !taughtP1 {
                taughtP1 = true
                bossCastWindupDuration = 5.5   // extra time to read the first one
                showBossTutorial("DEFLECT\nShe charges ONE tool. Tap that SAME tool back at her before the ring empties.")
            } else {
                bossCastWindupDuration = 3.5
            }
            bossAttackPhase = .strikingP1
            showBanner("DEFLECT — tap the charged tool")
        case 2:
            // P2: chained 3-tool sequence — player must tap in order
            bossChainSequence = (0..<3).map { _ in ColdTraceTool.allCases.randomElement() ?? .decrypt }
            bossChainProgress = 0
            if !taughtP2 {
                taughtP2 = true
                bossCastWindupDuration = 7.0
                showBossTutorial("CHAIN\nTap the shown tools IN ORDER — left to right — before the ring empties.")
            } else {
                bossCastWindupDuration = 4.5
            }
            bossAttackPhase = .chainingP2
            showBanner("CHAIN — tap the tools IN ORDER")
        default:
            // P3: sustained drain — never returns to idle, mash a tool to keep alive
            bossCastWindupDuration = .infinity
            bossDrainTickAt = 0
            bossAttackPhase = .drainingP3
            if !taughtP3 {
                taughtP3 = true
                showBossTutorial("DRAIN\nShe's locked onto you. MASH any tool over and over to break the hold.")
            }
            showBanner("DRAIN — mash any tool to break free")
        }
        HapticsManager.shared.error()
    }

    /// True when the tapped tool is the one the current boss cast wants —
    /// the correct P1 deflect, or the next P2 chain link. Anything else is a
    /// candidate to fall through to normal process triage.
    private func bossTapAddressesCast(_ tool: ColdTraceTool) -> Bool {
        switch bossAttackPhase {
        case .strikingP1:
            return tool == bossCastingTool
        case .chainingP2:
            return bossChainProgress < bossChainSequence.count
                && tool == bossChainSequence[bossChainProgress]
        default:
            return true   // P3 / other phases keep their existing routing
        }
    }

    /// True when a live (un-banished) process is countered by this tool —
    /// instant-tap or HOLD-type alike.
    private func hasLiveProcess(counteredBy tool: ColdTraceTool) -> Bool {
        processes.contains { $0.banished == 0 && $0.archetype.counterTool == tool }
    }

    private func handleBossToolTap(_ tool: ColdTraceTool) {
        switch bossAttackPhase {

        case .strikingP1:
            // Any correct tool tap deflects; wrong tool = self-chip but cast continues
            if tool == bossCastingTool {
                bossHP = max(0, bossHP - 2)
                showFeedback("DEFLECTED — \(tool.label)", color: "BBFF44")
                bossAttackPhase = .idle
                bossAttackTimer = 0
                HapticsManager.shared.attackHit()
            } else {
                applyDamageToPlayer(amount: 1)
                showFeedback("WRONG TOOL — \(tool.label) ≠ \(bossCastingTool.label)", color: "FF9933")
            }

        case .chainingP2:
            // Must tap in correct sequence — wrong tap resets progress + chips Sable
            if bossChainProgress < bossChainSequence.count
                && tool == bossChainSequence[bossChainProgress]
            {
                bossChainProgress += 1
                showFeedback("CHAIN \(bossChainProgress)/\(bossChainSequence.count)", color: tool.hex)
                if bossChainProgress >= bossChainSequence.count {
                    bossHP = max(0, bossHP - 3)
                    showFeedback("CHAIN BROKEN — −3 HP", color: "BBFF44")
                    bossAttackPhase = .idle
                    bossAttackTimer = 0
                    HapticsManager.shared.attackHit()
                }
            } else {
                applyDamageToPlayer(amount: 1)
                showFeedback("CHAIN MISSED — restart", color: "FF9933")
                bossChainProgress = 0
            }

        case .drainingP3:
            // Mash a tool to break the drain — every tap chunks the boss + resets drain timer
            bossHP = max(0, bossHP - 1)
            bossDrainTickAt = 0   // reset the damage-tick window
            showFeedback("DRAIN \(tool.label) → −1 HP", color: tool.hex)
            HapticsManager.shared.attackHit()

        case .idle:
            break
        }
    }

    // MARK: - Damage + end

    private func applyDamageToPlayer(amount: Int) {
        playerHP = max(0, playerHP - amount)
        hitFlash = 0.22
        triggerShake(Double(amount) * 5 + 4)
        HapticsManager.shared.playerDamaged()
        if playerHP == 0 {
            transitionTo(.defeat)
        }
    }

    /// Bump the screen-shake magnitude (decays in tick).
    private func triggerShake(_ amount: Double) {
        shakeAmount = max(shakeAmount, amount)
    }

    // MARK: - Chain (juice)

    private func registerChain() {
        if clock < chainExpireAt { chainCount += 1 } else { chainCount = 1 }
        chainExpireAt = clock + 2.2
        if chainCount >= 3 {
            showFeedback("CHAIN ×\(chainCount)", color: "FFE044")
            triggerShake(2)
            if chainCount == 4 || chainCount == 8 { daemonTaunt(.respect) }
        }
    }

    private func breakChain() { chainCount = 0 }

    // MARK: - Daemon voice + corruption

    private enum TauntKind { case mistake, lock, overclock, respect, phase }

    /// The entity speaks once it notices you (Sift onward). Cooldown-gated.
    private func daemonTaunt(_ kind: TauntKind) {
        guard stage == .siftEscalation || stage == .daemonBoss else { return }
        guard clock - lastTauntAt > 2.5 else { return }
        lastTauntAt = clock
        let lines: [String]
        switch kind {
        case .mistake:   lines = ["SLOPPY.", "PREDICTABLE.", "I FELT THAT.", "IS THAT ALL?"]
        case .lock:      lines = ["I SEE YOU NOW.", "RUN, LITTLE TRACE.", "CAUGHT."]
        case .overclock: lines = ["CUTE.", "FASTER, THEN.", "SHOW ME."]
        case .respect:   lines = ["...IMPRESSIVE.", "WHO TRAINED YOU?", "YOU DON'T BELONG HERE."]
        case .phase:     lines = ["DEEPER. GOOD.", "I AM EVERYWHERE IN HERE.", "YOU WEAR MY PATIENCE."]
        }
        if let line = lines.randomElement() {
            daemonLine = line
            daemonLineExpires = Date().addingTimeInterval(2.0)
        }
    }

    /// 0 (clean) → 1 (heavily corrupted). Scales by layer + current trace.
    private var corruptionIntensity: Double {
        let base: Double
        switch stage {
        case .siftEscalation: base = 0.22
        case .daemonBoss:     base = 0.55
        default:              base = 0
        }
        return min(1.0, base + trace * 0.4)
    }

    private func endGame(win: Bool) {
        guard !endGameOver else { return }
        endGameOver = true
        didWin = win
        bossRevealShown = win
        if win {
            HapticsManager.shared.victory()
            SFXManager.shared.play("mission_victory")
            // Reflect the objective in the live flag the DEBRIEF reads — without
            // this it credited the data bonus in the stats store but still
            // showed "✗ DATA MISSED" and omitted the bonus from the on-screen
            // total. The Neural Imprint IS the objective of this run.
            GameState.shared.dataAcquired = true
            // Flawless dive bonus — slipping the whole run without ever giving
            // the system a lock is the skill ceiling the trace meter creates.
            let flawless = (traceLockCount == 0) ? 250 : 0
            let score = 300 + playerHP * 50 + 500 + flawless
            if flawless > 0 { showFeedback("GHOST RUN — never traced (+250)", color: "00FFCC") }
            MissionStatsStore.shared.recordVictory(
                missionId: "Mission005_5",
                score: score,
                dataAcquired: true,    // Neural Imprint
                grimoireAcquired: false
            )
        } else {
            HapticsManager.shared.defeat()
            SFXManager.shared.play("mission_defeat")
        }
    }

    private func exitMission() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .endColdTrace(won: didWin))
    }

    // MARK: - Overlays

    private var bossAttackPromptOverlay: some View {
        let phaseHex: String
        let promptText: String
        switch bossAttackPhase {
        case .strikingP1:
            phaseHex = bossCastingTool.hex
            promptText = "DEFLECT  →  \(bossCastingTool.label)"
        case .chainingP2:
            phaseHex = "FF44CC"
            let remaining = bossChainSequence.dropFirst(bossChainProgress)
            let chainStr = remaining.map(\.label).joined(separator: " · ")
            promptText = "CHAIN  →  \(chainStr)"
        case .drainingP3:
            phaseHex = "FF3344"
            promptText = "TAP ANY TOOL · KEEP TAPPING"
        case .idle:
            phaseHex = "FFFFFF"
            promptText = ""
        }
        let timeLeft: Double = max(0, bossCastWindupDuration - bossAttackTimer)
        let pct: Double = bossCastWindupDuration.isFinite && bossCastWindupDuration > 0
            ? max(0, min(1, timeLeft / bossCastWindupDuration))
            : 1.0   // P3 has no countdown ring
        return ZStack {
            if bossAttackPhase != .drainingP3 {
                Circle()
                    .trim(from: 0, to: CGFloat(pct))
                    .stroke(Color(hex: phaseHex),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 130, height: 130)
                    .shadow(color: Color(hex: phaseHex).opacity(0.7), radius: 10)
            }
            VStack(spacing: 8) {
                if bossAttackPhase == .strikingP1 {
                    Image(systemName: bossCastingTool.systemImage)
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(Color(hex: phaseHex))
                }
                if bossAttackPhase == .chainingP2 {
                    // Show the chain as an ORDERED row of tool icons: tapped ones
                    // dim + checked, the NEXT one bright + pulsing, the rest faint.
                    Text("TAP IN ORDER")
                        .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(3)
                        .foregroundColor(Color(hex: phaseHex))
                    HStack(spacing: 8) {
                        ForEach(Array(bossChainSequence.enumerated()), id: \.offset) { idx, tool in
                            let done = idx < bossChainProgress
                            let next = idx == bossChainProgress
                            ZStack {
                                Circle()
                                    .fill(Color(hex: tool.hex).opacity(done ? 0.2 : (next ? 1.0 : 0.35)))
                                    .frame(width: 34, height: 34)
                                Image(systemName: done ? "checkmark" : tool.systemImage)
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(done ? .white.opacity(0.6) : .black)
                            }
                            .overlay(Circle().stroke(Color(hex: tool.hex), lineWidth: next ? 2.5 : 1))
                            .scaleEffect(next ? 1.15 : 1.0)
                            .shadow(color: next ? Color(hex: tool.hex) : .clear, radius: 8)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
                } else {
                    Text(promptText)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.75))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color(hex: phaseHex), lineWidth: 1)
                                )
                        )
                }
            }
        }
    }

    private var bannerOverlay: some View {
        VStack {
            Text(bannerText)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(Color(hex: "AACCEE"))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "AACCEE"), lineWidth: 1)
                        )
                )
                .padding(.top, 160)
            Spacer()
        }
        .transition(.opacity)
    }

    private var feedbackOverlay: some View {
        VStack {
            Spacer()
            Text(feedbackText)
                .font(.system(size: 16, weight: .black))
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
                .shadow(color: Color(hex: feedbackColor).opacity(0.55), radius: 10)
                .padding(.bottom, 180)
                .opacity(min(1.0, feedbackHold / 0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var tutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 12) {
                Spacer().frame(height: 40)
                Text("COLD TRACE")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(Color(hex: "00DDFF"))
                Text("Cipher solo, inside the Akashic Fragment.\nTriage incoming processes — match the tool.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                Spacer().frame(height: 6)

                Group {
                    toolRow(.decrypt,  desc: "DECRYPT  (cyan)    vs Lockbit + Cipherwall")
                    toolRow(.overload, desc: "OVERLOAD (orange)  vs Hunter-Killer")
                    toolRow(.spoof,    desc: "SPOOF    (magenta) vs Sniffer")
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                Spacer().frame(height: 6)
                Text("Each process shows its required tool. Tap the\nmatching tool button to neutralize it. CIPHERWALL\nis HOLD-type — press and hold until the bar fills.\nWrong tool = self-chip. Expired process = full damage.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)

                Spacer().frame(height: 8)
                Text("THE CORE DAEMON  (final layer)")
                    .font(.system(size: 12, weight: .black, design: .monospaced)).tracking(2)
                    .foregroundColor(Color(hex: "FF44CC"))
                Text("DEFLECT — it charges ONE tool; tap that SAME tool back before the ring fills.\nCHAIN — it shows a sequence of tools; tap them IN ORDER, left to right.\nDRAIN — tap ANY tool over and over to shake it off.")
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
                    Text("JACK IN")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: "00DDFF"))
                        )
                        .shadow(color: Color(hex: "00DDFF").opacity(0.6), radius: 12)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 40)
            }
        }
    }

    private func toolRow(_ tool: ColdTraceTool, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 20, weight: .black))
                .frame(width: 26)
                .foregroundColor(Color(hex: tool.hex))
            Text(desc)
                .foregroundColor(Color(hex: tool.hex))
        }
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                if didWin {
                    // The reveal moment as the hero shot — the boss's true face
                    if let img = BasementBrawlSpriteCache.shared.image(named: "daemon_reveal") {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 280)
                            .shadow(color: Color(hex: "FF44CC").opacity(0.5), radius: 24)
                    }
                }
                Text(didWin ? "NEURAL IMPRINT" : "TRACE LOCKED")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(didWin ? Color(hex: "BBFF44") : Color(hex: "FF3344"))
                Text(didWin
                     ? "Mom wasn't a memory. She was a guard dog.\nDrachenwerk burns."
                     : "Trace caught the dive. Cipher's deck offline —\nback to flesh, lesson learned.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
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

    // MARK: - Helpers

    private func showBanner(_ text: String) {
        bannerText = text
        bannerExpires = Date().addingTimeInterval(2.4)
    }

    /// Prominent first-time how-to callout for a Daemon attack type (~5s).
    private func showBossTutorial(_ text: String) {
        bossTutorialText = text
        bossTutorialUntil = clock + 5.0
    }

    private func showFeedback(_ text: String, color: String) {
        feedbackText = text
        feedbackColor = color
        feedbackHold = 1.4
    }
}
