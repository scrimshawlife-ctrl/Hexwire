import SwiftUI
import SpriteKit
import QuartzCore

// MARK: - Mission Objective Banner

struct MissionObjectiveBanner: View {
    let missionTitle: String
    let missionId: String
    let extractionX: Int
    let extractionY: Int
    @State private var pulse: Bool = false
    @State private var isVisible: Bool = true
    @State private var hideTimer: Timer?

    /// Per-mission objective string. Each mission ships as a 3-room
    /// multi-room JSON (loaded via MissionLoader's _multi-first path),
    /// so the wording calls out the rooms / required actions in order
    /// instead of the old "Reach the ★ EXIT at north end" boilerplate.
    /// Terminal breach is explicitly named where the mission requires it.
    private var objectiveText: String {
        switch missionId {
        case "Mission001":
            // 3 rooms, no terminal — just push through to the rooftop.
            return "OBJECTIVE: Push through Courtyard → Security Wing → Rooftop ★ EXIT."
        case "Mission002":
            // 3 rooms, terminal in room_1 (AI Core Chamber).
            return "OBJECTIVE: Hack the AI Core terminal, then reach the rooftop ★ EXIT."
        case "Mission003":
            // 3 rooms, terminal in room_1 (Warded Corridor).
            return "OBJECTIVE: Hack the warded terminal, then reach the Ritual Chamber ★ EXIT."
        case "Mission004":
            // 3 rooms, terminal in room_1 (Executive Suite).
            return "OBJECTIVE: Hack the Executive Suite terminal, then reach the rooftop ★ EXIT."
        case "Mission005":
            // 3 rooms, terminal in room_1 (Factory Floor).
            return "OBJECTIVE: Hack the Factory Floor terminal, then reach the Mech Bay ★ EXIT."
        case "Mission006":
            // 3 rooms, terminal in room_1 (AI Core Vault).
            return "OBJECTIVE: Hack the AI Core Vault terminal, then escape via the Extraction Tunnel ★ EXIT."
        default:
            return "OBJECTIVE: Reach the ★ EXIT (green glow)."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                HStack(spacing: 10) {
                    // Mission icon
                    ZStack {
                        Circle()
                            .fill(Color(hex: "00FF88").opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "00FF88"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MISSION: \(missionTitle)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(Color(hex: "00FF88"))
                            .tracking(0.5)
                        Text(objectiveText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    // Toggle button
                    Button(action: {
                        withAnimation { isVisible = false }
                        hideTimer?.invalidate()
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "00FF88").opacity(0.6))
                            // 44pt invisible hit area for thumb-friendly taps.
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Extraction target badge — pulsing
                    VStack(alignment: .center, spacing: 2) {
                        Text("TARGET")
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                                .foregroundColor(Color(hex: "00FF88"))
                            Text("EXIT (\(extractionX),\(extractionY))")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "00FF88"))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "00FF88").opacity(pulse ? 0.25 : 0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(hex: "00FF88").opacity(pulse ? 0.8 : 0.4), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "0A0A14").opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "00FF88").opacity(0.3), lineWidth: 1)
                        )
                )
                .transition(.opacity)
            }
            // Collapsed-state "info" dot removed per playtest — the
            // INTEL button in the utility row provides the same info
            // on demand, so the floating green ⓘ at the top of the map
            // was redundant clutter once the banner auto-hid.
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
            startAutoHideTimer()
        }
        .onDisappear {
            hideTimer?.invalidate()
        }
    }

    private func startAutoHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation { isVisible = false }
        }
    }
}

/// Transient red-edged warning banner used for objective-gate prompts
/// ("JACK IN AND HACK THE TERMINAL FIRST", etc.). Visibility is owned by
/// `GameState.transientWarning` — this view just renders the current value
/// and styles it. Auto-clear timer lives in `GameState.postTransientWarning`.
struct TerminalWarningBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(Color(hex: "FFCC00"))
            Text(text)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "1A0A0A").opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "FFCC00").opacity(0.85), lineWidth: 1.2)
                )
                .shadow(color: Color(hex: "FFCC00").opacity(0.35), radius: 8)
        )
    }
}

@main
struct HexwireApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var phaseManager = PhaseManager()
    @ObservedObject private var gameState = GameState.shared
    @State private var showLaunchSplash = true

    var body: some View {
        ZStack {
            Color(hex: "0D0D0D").ignoresSafeArea()

            // Launch splash — Netrunner full-screen image + Zero State studio
            // logo overlaid on top for first ~3 seconds. Logo sits low on the
            // screen so it doesn't fight the splash composition.
            if showLaunchSplash {
                ZStack {
                    Image("launch_screen")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                    VStack {
                        Spacer()
                        Image("zero_state_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .opacity(0.92)
                            .padding(.bottom, 60)
                    }
                    .ignoresSafeArea(edges: .top)
                }
                .transition(.opacity)
                .zIndex(100)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeOut(duration: 0.6)) {
                            showLaunchSplash = false
                        }
                    }
                }
            }

            switch phaseManager.currentPhase {
            case .title:
                TitleView(manager: phaseManager)
            case .prologue:
                NeonLotusScene(manager: phaseManager)
            case .missionSelect:
                MissionSelectView(manager: phaseManager)
            case .briefing:
                BriefingView(manager: phaseManager)
            case .combat:
                CombatView(manager: phaseManager, gameState: gameState)
            case .missionIntro:
                MissionIntroScene(manager: phaseManager)
            case .missionOutro:
                MissionOutroScene(manager: phaseManager)
            case .dropIntro:
                DropIntroScene(manager: phaseManager)
            case .hoverbikeChase:
                HoverbikeChaseScene(manager: phaseManager)
            case .basementBrawl:
                BasementBrawlScene(manager: phaseManager)
            case .mirrorline:
                MirrorlineScene(manager: phaseManager)
            case .coldTrace:
                ColdTraceScene(manager: phaseManager)
            case .debrief:
                DebriefView(manager: phaseManager)
            case .gameEnding:
                EndingScene(manager: phaseManager)
            }
        }
        .onAppear(perform: applyDebugLaunchOverrideIfNeeded)
        .onChange(of: phaseManager.currentPhase) { _, newPhase in
            // Music + phase-stinger SFX routing per game phase.
            switch newPhase {
            case .title, .missionSelect:
                MusicManager.shared.playLoop(filename: "title", startOffset: 5)
                // Clear any ambient loop from the previous phase (chase
                // engine hum, M1 rain, etc.) so it doesn't bleed into menus.
                SFXManager.shared.stopAllLoops()
            case .prologue:
                // Prologue gets its own moody club track. Falls back to the
                // title music if the file hasn't shipped yet — no silence.
                MusicManager.shared.playLoop(filename: "prologue_lotus", startOffset: 0)
            case .missionIntro:
                // Per-mission cutscene music. Each mission can have its own
                // intro track named `intro_<missionId>_music.mp3`. Some
                // missions explicitly use a different track instead — see
                // the trackName switch.
                if let mid = phaseManager.selectedMissionId {
                    // Track name — defaults to convention, but per-mission
                    // overrides are allowed for missions that intentionally
                    // share a track with another phase (M6 reuses the
                    // title-screen track for thematic weight).
                    let trackName: String = {
                        switch mid {
                        case "Mission006":
                            // M6 finale uses the title-screen music for
                            // narrative gravitas — closing the loop.
                            return "title"
                        default:
                            // e.g. Mission001 → "intro_m1_music"
                            let suffix = mid.replacingOccurrences(of: "Mission00", with: "m")
                            return "intro_\(suffix)_music"
                        }
                    }()
                    // Per-mission startOffset — some tracks have slow
                    // intros we want to skip past for instant impact.
                    let startOffset: TimeInterval = {
                        switch mid {
                        case "Mission002":    return 10   // Neon Dystopia — skip intro
                        case "Mission002_5":  return 5    // Witch's Heartbeat — skip slow ramp
                        case "Mission004":    return 21   // Neon Dystopia (v2) — skip intro
                        case "Mission005":    return 12   // Grind State — skip slow intro
                        case "Mission005_5":  return 12   // Detachment Protocol — skip slow ambient ramp
                        case "Mission006":    return 5    // Title — skip into the meat of the track
                        default:              return 0
                        }
                    }()
                    MusicManager.shared.playLoop(filename: trackName, startOffset: startOffset)
                } else {
                    MusicManager.shared.playLoop(filename: "briefing", startOffset: 3)
                }
            case .dropIntro:
                // M3.5 cutscene — moodier pre-action track. Skip past the
                // slow intro 20s so the energy hits when the cutscene loads.
                MusicManager.shared.playLoop(filename: "drop_intro", startOffset: 20)
            case .hoverbikeChase:
                // M3.5 chase mission. Action darksynth track. Falls back if
                // the file isn't shipped — engine SFX in code will still play.
                MusicManager.shared.playLoop(filename: "chase_drop", startOffset: 0)
                // Engine hum ambient — sits at low volume under the music
                // and chase SFX. High-passed at 150Hz at the source so its
                // sub-bass doesn't clash with the music's bass line.
                // Cumulative -40% with chase SFX → 0.18 × 0.595 ≈ 0.107.
                SFXManager.shared.stopAllLoops()
                SFXManager.shared.playLoop("chase_engine_loop", volume: 0.107)
            case .basementBrawl:
                // M4.5 brawl gameplay track — industrial darksynth fight music.
                SFXManager.shared.stopAllLoops()
                MusicManager.shared.playLoop(filename: "m4_5_brawl", startOffset: 0)
            case .mirrorline:
                // M2.5 mirrorline — meditation-under-threat track. Start 5s in
                // to skip the slow drone-only ramp and land on the heartbeat.
                SFXManager.shared.stopAllLoops()
                MusicManager.shared.playLoop(filename: "m2_5_mirrorline", startOffset: 5)
            case .coldTrace:
                // M5.5 cold trace — "Cipher's Mandate" gameplay track.
                // No intro ramp, kicks in immediately — start at 0 per user direction.
                SFXManager.shared.stopAllLoops()
                MusicManager.shared.playLoop(filename: "m5_5_coldtrace", startOffset: 0)
            case .briefing:
                MusicManager.shared.playLoop(filename: "briefing", startOffset: 3)
            case .combat:
                if let mid = phaseManager.selectedMissionId {
                    MusicManager.shared.playMissionMusic(missionId: mid)
                    // Per-mission ambient bed. Volume is tiny (~0.20) so it
                    // sits well under the music — just texture, never
                    // foreground. M1 = urban rain, M3 / M6 = corp server hum.
                    SFXManager.shared.stopAllLoops()
                    switch mid {
                    case "Mission001":
                        SFXManager.shared.playLoop("ambient_rain", volume: 0.153)
                    case "Mission003":
                        SFXManager.shared.playLoop("ambient_server_hum", volume: 0.18)
                    // M6 ambient hum was persisting past the mission and into
                    // home/menu screens — yanked entirely (was hard to fully
                    // tear down on the bug-laden defeat path anyway).
                    default:
                        break
                    }
                }
                // Mission-start sting layered above the mission soundtrack.
                SFXManager.shared.play("mission_start", volume: 0.85)
            case .missionOutro:
                // Post-combat VN scene. Stop mission combat music + ambient
                // beds, then bring the mission's INTRO track back in. Reusing
                // the intro music as the outro music is intentional narrative
                // bookending — the player hears the same theme that opened
                // the run as it closes, giving each mission a sonic arc.
                // Track resolution mirrors `.missionIntro` exactly.
                SFXManager.shared.stopAllLoops()
                if let mid = phaseManager.selectedMissionId {
                    let trackName: String = {
                        switch mid {
                        case "Mission003_5":
                            // M3.5 chase outro reuses the SAME track as its
                            // intro (drop_intro). Per-design — the chase has
                            // no separate intro_m3_5_music file; the cutscene
                            // music and the outro music are the same cue.
                            return "drop_intro"
                        case "Mission006":
                            // M6 finale reuses the title track for closure
                            // (intentional thematic loop — same track that
                            // played over the prologue and M6 intro).
                            return "title"
                        default:
                            // e.g. Mission001 → "intro_m1_music"
                            let suffix = mid.replacingOccurrences(of: "Mission00", with: "m")
                            return "intro_\(suffix)_music"
                        }
                    }()
                    // Per-mission startOffset — same offsets as intro so the
                    // outro hits the same beat of the track. The outro is the
                    // intro's emotional echo, not a different cut.
                    let startOffset: TimeInterval = {
                        switch mid {
                        case "Mission002":    return 10   // Neon Dystopia — skip intro
                        case "Mission002_5":  return 5    // Witch's Heartbeat — skip slow ramp
                        case "Mission003_5":  return 20   // drop_intro — same offset as the dropIntro cutscene
                        case "Mission004":    return 21   // Neon Dystopia v2 — skip intro
                        case "Mission005":    return 12   // Grind State — skip slow intro
                        case "Mission005_5":  return 12   // Detachment Protocol — skip slow ambient ramp
                        case "Mission006":    return 5    // Title — skip into the meat
                        default:              return 0
                        }
                    }()
                    MusicManager.shared.playLoop(filename: trackName, startOffset: startOffset)
                } else {
                    // Fallback if mission ID went missing (shouldn't happen,
                    // but never let an outro scene play in dead silence).
                    MusicManager.shared.playLoop(filename: "briefing", startOffset: 3)
                }
                // Victory sting plays HERE (moved from .debrief) so the
                // emotional beat lands at the moment of resolution, not
                // after the dialog has been read.
                SFXManager.shared.play("mission_victory")
            case .debrief:
                MusicManager.shared.stop()
                SFXManager.shared.stopAllLoops()
                // Defeat sting on debrief — victory sting now plays earlier
                // on .missionOutro so it lands at the resolution moment.
                //
                // IMPORTANT: use `manager.combatWon` (PhaseManager's own
                // copy, set from the `.endCombat(won:)` payload and held
                // through subsequent transitions) — NOT `gameState.combatWon`.
                // The CombatEndOverlay's `viewDebrief()` nils out the
                // gameState copy BEFORE firing the transition, so reading
                // it here always sees `nil` and `nil != true` evaluates to
                // true. Result: the defeat sound was firing on EVERY
                // debrief — including the CONTRACT FULFILLED victory screen.
                // Check positively for `== false` so `nil` is not "defeat."
                if phaseManager.combatWon == false {
                    SFXManager.shared.play("mission_defeat")
                }
            case .gameEnding:
                // Game-end epilogue. Bespoke ending theme — full song built
                // for this scene. Plays once over the three-beat VN closer
                // and the FIN card. Loops in case the player lingers; in
                // practice the scene is shorter than the track.
                SFXManager.shared.stopAllLoops()
                MusicManager.shared.playLoop(filename: "ending_theme", startOffset: 0)
            }
        }
        .onChange(of: gameState.showMatrixMiniGame) { _, showing in
            // Silence the level audio bed (mission music + ambient loops like
            // rain / server hum / mech alarms) while a terminal mini-game is
            // open so its chiptune layer plays alone. Restored on close.
            if showing {
                MusicManager.shared.duck()
                SFXManager.shared.pauseAllLoops()
            } else {
                MusicManager.shared.unduck()
                SFXManager.shared.resumeAllLoops()
            }
        }
        .onAppear {
            // Touch the SFX singleton so its notification observers wire up
            // before the first gunfire / hit / spell event fires.
            _ = SFXManager.shared
            // Start title music IMMEDIATELY so it plays under the launch
            // splash. Skip the song's slow pre-roll by jumping 5s in.
            if phaseManager.currentPhase == .title {
                MusicManager.shared.playLoop(filename: "title", startOffset: 5)
            }
        }
    }

    private func applyDebugLaunchOverrideIfNeeded() {
        #if DEBUG
        guard phaseManager.currentPhase == .title else { return }
        guard let missionId = ProcessInfo.processInfo.environment["SR_AUTOSTART_MISSION_ID"] else { return }

        _ = phaseManager.transition(to: .startGame)
        _ = phaseManager.transition(to: .selectMission(missionId))
        _ = GameState.shared.prepareMissionForCombat(named: missionId)
        _ = phaseManager.transition(to: .beginMission)
        #endif
    }
}

// MARK: - Matrix Rain Effect

struct MatrixRainView: View {
    @State private var characters: [MatrixChar] = []
    @State private var timer: Timer?

    let columns: Int = 8

    struct MatrixChar {
        var x: CGFloat
        var y: CGFloat
        var char: String
        var opacity: Double
    }

    var body: some View {
        Canvas { context, _ in
            for char in characters {
                let text = Text(char.char)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "00FF88").opacity(char.opacity))

                context.draw(text, at: CGPoint(x: char.x, y: char.y))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            initializeCharacters()
            startAnimation()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func initializeCharacters() {
        let hexChars = ["0", "1", "A", "F", "3", "9", "C", "E"]
        let katakana = ["ヲ", "ァ", "ィ", "ウ", "ェ", "オ", "カ", "キ"]
        let allChars = hexChars + katakana

        characters = (0..<columns).map { i in
            MatrixChar(
                x: CGFloat(i) * (UIScreen.main.bounds.width / CGFloat(columns)),
                y: CGFloat.random(in: -100...0),
                char: allChars.randomElement() ?? "0",
                opacity: Double.random(in: 0.3...0.8)
            )
        }
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            for i in 0..<characters.count {
                characters[i].y += 2
                if characters[i].y > UIScreen.main.bounds.height {
                    characters[i].y = -20
                    characters[i].char = ["0", "1", "A", "F", "3", "9", "C", "E", "ヲ", "ァ", "ィ", "ウ"].randomElement() ?? "0"
                }
                characters[i].opacity = Double.random(in: 0.2...0.8)
            }
        }
    }
}

// MARK: - Title View

struct TitleView: View {
    @ObservedObject var manager: PhaseManager

    var body: some View {
        ZStack {
            Image("title_splash")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: 36)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .offset(y: 36)
            .ignoresSafeArea()

            // Extra bright text layer — clear path so text pops
            Color.black.opacity(0.15)
                .offset(y: 36)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer().frame(minHeight: 60)

                VStack(spacing: 16) {
                    Button(action: {
                        HapticsManager.shared.selectAffirm()
                        _ = manager.transition(to: .startGame)
                    }) {
                        Text("NEW RUN")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(width: 220, height: 50)
                            .background(Color(hex: "00FF88"))
                            .cornerRadius(8)
                            .shadow(color: Color(hex: "00FF88").opacity(0.5), radius: 8)
                    }
                    Button(action: {
                        HapticsManager.shared.selectAffirm()
                        _ = manager.transition(to: .viewPrologue)
                    }) {
                        Text("PROLOGUE")
                            .font(.headline)
                            .foregroundColor(Color(hex: "FF00AA"))
                            .frame(width: 220, height: 50)
                            .background(Color.black.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "FF00AA").opacity(0.8), lineWidth: 2)
                            )
                            .shadow(color: Color(hex: "FF00AA").opacity(0.35), radius: 6)
                    }
                    Button(action: {
                        HapticsManager.shared.buttonTap()
                    }) {
                        Text("CONTINUE (COMING SOON)")
                            .font(.headline)
                            .foregroundColor(Color(hex: "00FF88").opacity(0.5))
                            .frame(width: 220, height: 50)
                            .background(Color.black.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "00FF88").opacity(0.35), lineWidth: 2)
                            )
                    }
                    .disabled(true)
                }
                .padding(.bottom, 12)

                VStack(spacing: 8) {
                    // (Tagline "FOUR RUNNERS · ONE WIRE · NO WITNESSES" lives
                    // in the title_splash hero art directly under the HEXWIRE
                    // wordmark — duplicating it here as a Text shipped two
                    // copies stacked vertically on the screen. Removed
                    // 2026-05-19. If the splash art ever loses the tagline,
                    // reinstate the Text version below the buttons.)
                    Text("v0.1 // HEXWIRE PROTOTYPE")
                        .font(.system(size: 10, weight: .light, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF88").opacity(0.85))
                        .tracking(1)
                        .shadow(color: Color(hex: "00FF88").opacity(0.4), radius: 3)
                    Text("AN ORIGINAL CYBERPUNK TACTICS GAME · NOT AFFILIATED WITH ANY TABLETOP PROPERTY")
                        .font(.system(size: 8, weight: .light, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF88").opacity(0.55))
                        .tracking(1)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)

                    // Zero State studio credit — small logo + tagline at the
                    // bottom of the title menu so the studio mark is present
                    // but doesn't fight the game's hero art / buttons.
                    Image("zero_state_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 140)
                        .opacity(0.78)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(hex: "00FF88").opacity(0.25), lineWidth: 1)
                        )
                )
            }
            .padding(24)
        }
    }
}

// MARK: - Mission Select View

struct MissionSelectView: View {
    @ObservedObject var manager: PhaseManager
    @ObservedObject private var stats = MissionStatsStore.shared

    /// Mission roster. `isChase=true` denotes a side-scrolling chase mission
    /// (M3.5 "The Drop") that routes through a different phase than the
    /// standard tactical missions. All other entries use the normal
    /// selectMission → briefing → combat flow.
    private let missions: [(id: String, title: String, desc: String, risk: String, badge: String?, isChase: Bool)] = [
        ("Mission001",   "The Extraction",    "Corp facility east side. Guards on patrol, drone incoming. Reach the north exit.", "EASY",     "INTRO",  false),
        ("Mission002",   "Ghost Protocol",    "Server farm locked by rogue AI. Drone swarms on every floor. Bring firepower.",        "HIGH",     nil,      false),
        ("Mission002_5", "Mirrorline",        "Whatever was inside the AGI didn't fully die. Sable projects astrally to chase the echo. Trace sigils to banish spirits. Bring back the Akashic Fragment.", "HARD", "ASTRAL", true),
        ("Mission003",   "The Mage's Lair",   "Blood mage Sato + his hired guns. Kill the mage and his true form rises — drop the boss to claim the grimoire.",   "HARD",     "BOSS",   false),
        ("Mission003_5", "The Drop",          "Hoverbike chase down the elevated highway. Corp drones in pursuit. Ditch the heat — survive to the safehouse.", "HIGH", "CHASE", true),
        ("Mission004",   "Dead Man's Switch", "Hokuto Industrial HQ. Elite on station, mage at top floor. Beat the lockdown clock.", "EXTREME",  nil,      false),
        ("Mission004_5", "Basement Brawl",    "Drachenwerk middleman runs a fight club under his nightclub. Raze goes in solo. Parry, dodge, execute. Bring back the MEKTON file.", "HARD", "DUEL", true),
        ("Mission005",   "Mekton Blues",      "Drachenwerk industrial complex. Two elites, drone corridor, and a field medic.",      "EXTREME",  "BOSS",   false),
        ("Mission005_5", "Cold Trace",        "The Akashic Fragment isn't static data — it's a live Drachenwerk matrix entity. Cipher jacks in solo to read it from the inside. Triage ICE before the trace tags her deck.", "HARD", "DECK", true),
        ("Mission006",   "Ghost Signal",      "Caelum AI black-budget lab. Six floors deep. Hack the core, beat the countertrace.",  "EXTREME",  "FINALE", false)
    ]

    var body: some View {
        ZStack {
            // (Zero State studio sigil now renders INLINE to the left of
            // the SELECT RUN title — see HStack below. Placing the mark
            // beside the title makes it part of the title chrome instead
            // of a faint ornament floating above. Larger + higher opacity
            // than the previous header-crest treatment so it actually
            // reads at glance.)

        VStack(spacing: 24) {
            HStack(spacing: 10) {
                Image("zero_state_mark_2")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .opacity(0.95)
                Text("SELECT RUN")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(Color(hex: "00FF88"))
                    .tracking(4)
            }

            // Cumulative progress header — total best score across completed missions.
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WALLET")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "FFCC00").opacity(0.75))
                        .tracking(2)
                    Text("¥\(stats.playerNuyen.formatted())")
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "FFCC00"))
                }
                Spacer()
                VStack(alignment: .center, spacing: 2) {
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFCC").opacity(0.7))
                        .tracking(2)
                    Text("\(stats.totalScore)")
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFCC"))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RUNS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                        .tracking(2)
                    Text("\(stats.missionsCompleted) / \(missions.count)")
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF88"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "00FFCC").opacity(0.3), lineWidth: 1)
                    )
            )

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(missions.enumerated()), id: \.element.id) { index, mission in
                        let record = stats.record(for: mission.id)
                        // Number cards by their narrative slot, not their
                        // array index. Tactical missions use sequential
                        // numbering (counting only non-chase entries before
                        // them); the chase mission gets a fractional label
                        // (e.g. "3.5") so its placement reads correctly.
                        let cardNumber: String = {
                            if mission.isChase {
                                let priorTactical = missions.prefix(index).filter { !$0.isChase }.count
                                return "\(priorTactical).5"
                            } else {
                                let priorTactical = missions.prefix(index).filter { !$0.isChase }.count
                                return String(format: "%02d", priorTactical + 1)
                            }
                        }()
                        // Mission unlock progression:
                        //   • M1 always unlocked.
                        //   • Any mission already completed stays unlocked
                        //     (grandfathered access so replays work + so
                        //     existing player progress isn't gated by a
                        //     newly-added lock rule).
                        //   • Otherwise: tactical missions unlock when the
                        //     PREVIOUS tactical mission has been completed
                        //     (the chase mission is optional and does NOT
                        //     gate M4). Chase unlocks when M3 is completed.
                        let isLocked: Bool = {
                            guard index > 0 else { return false }
                            if record.completed { return false }   // already beaten = always replayable
                            let prevTactical = missions.prefix(index).reversed().first { !$0.isChase }
                            guard let prev = prevTactical else { return false }
                            return !stats.record(for: prev.id).completed
                        }()
                        MissionCard(
                            id: mission.id,
                            number: cardNumber,
                            title: mission.title,
                            description: mission.desc,
                            risk: mission.risk,
                            badge: mission.badge,
                            isLocked: isLocked,
                            isCompleted: record.completed,
                            bestScore: record.bestScore,
                            bestMiniGameScore: record.bestMiniGameScore,
                            onSelect: {
                                guard !isLocked else {
                                    HapticsManager.shared.error()
                                    return
                                }
                                HapticsManager.shared.selectAffirm()
                                // M3.5 The Drop has its own dedicated pre-chase
                                // VN (`.dropIntro`) — fired explicitly here.
                                // M4.5 Basement Brawl reuses the standard
                                // mission-intro VN infrastructure, so it
                                // routes through `.selectMission` like the
                                // tactical missions and the matrix re-routes
                                // its `.finishMissionIntro` to `.basementBrawl`.
                                if mission.id == "Mission003_5" {
                                    _ = manager.transition(to: .viewDropIntro)
                                } else {
                                    _ = manager.transition(to: .selectMission(mission.id))
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxHeight: .infinity)

            Spacer()
        }
        .padding(24)
        }   // close outer ZStack (Zero State watermark wrapper)
    }
}

struct MissionCard: View {
    let id: String
    let number: String
    let title: String
    let description: String
    let risk: String
    let badge: String?
    let isLocked: Bool
    var isCompleted: Bool = false
    var bestScore: Int = 0
    var bestMiniGameScore: Int = 0
    let onSelect: () -> Void

    private var riskColor: Color {
        switch risk {
        case "EASY":     return Color(hex: "00FFCC")
        case "MODERATE": return Color(hex: "00FF88")
        case "HIGH":     return Color(hex: "FF8800")
        case "HARD":     return Color(hex: "FF5500")
        case "EXTREME":  return Color(hex: "FF1133")
        default:         return Color.gray
        }
    }

    private var skullCount: Int {
        switch risk {
        case "EASY":     return 0
        case "MODERATE": return 1
        case "HIGH":     return 2
        case "HARD":     return 3
        case "EXTREME":  return 3
        default:         return 0
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Colored left accent bar
                Rectangle()
                    .fill(riskColor)
                    .frame(width: 4)

                // Mission number badge
                VStack {
                    Text(number)
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(riskColor)
                }
                .frame(width: 40)
                .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)

                        // Skull icons for risk level
                        HStack(spacing: 2) {
                            ForEach(0..<skullCount, id: \.self) { _ in
                                Image(systemName: "skull.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(riskColor)
                            }
                        }

                        Text(risk)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(riskColor.opacity(0.2))
                            .foregroundColor(riskColor)
                            .cornerRadius(4)
                        if let badge = badge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.3))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }
                        if isCompleted {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "00FFCC"))
                        }
                    }
                    if isCompleted && bestScore > 0 {
                        HStack(spacing: 8) {
                            Text("BEST: \(bestScore)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "00FFCC"))
                                .tracking(1)
                            if bestMiniGameScore > 0 {
                                Text("HACK: \(bestMiniGameScore)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "AA66FF"))
                                    .tracking(1)
                            }
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(riskColor.opacity(0.8))
                        .padding(.horizontal, 12)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(riskColor)
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "0F0F1E"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(riskColor.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isLocked)
    }
}

// MARK: - Briefing View

struct BriefingView: View {
    @ObservedObject var manager: PhaseManager

    @State private var loadedMission: Mission?
    // Some missions ship a multi-room JSON (Mission001_multi.json, etc.) that
    // MissionSetupService prefers over the single-room file. The briefing has
    // to load the same way or it shows mismatched HOSTILES counts (e.g. 4 from
    // the single-room JSON when the multi-room actually has 6 across rooms).
    @State private var loadedMultiRoom: MultiRoomMission?

    /// Cinematic full-screen briefing overlay shown on top of the team-roster
    /// screen. Tap-to-dismiss reveals the ACCEPT CONTRACT button. Restored
    /// 2026-05 — the redundancy with the screen below is intentional, the
    /// overlay carries flavor + at-a-glance intel and the screen below has
    /// the team roster + commit button.
    @State private var showCinematicBriefing: Bool = true

    private var missionTitle: String {
        loadedMultiRoom?.title ?? loadedMission?.title ?? manager.selectedMissionId ?? "Unknown"
    }

    private var missionDesc: String {
        loadedMultiRoom?.description ?? loadedMission?.description ?? "No description available."
    }

    /// Total hostiles across the whole mission. For multi-room missions this is
    /// the sum across every room (matches what the player will fight end-to-end);
    /// for single-room missions it's just `mission.enemies.count`.
    private var totalEnemyCount: Int {
        if let multi = loadedMultiRoom {
            return multi.rooms.reduce(0) { $0 + $1.enemies.count }
        }
        return loadedMission?.enemies.count ?? 0
    }

    private var teamRoster: [Character] {
        let team = GameState.shared.playerTeam
        return team.isEmpty ? Character.allRunners : team
    }

    private var reward: String {
        switch manager.selectedMissionId ?? "" {
        case "Mission001": return "¥15,000 + expenses"
        case "Mission002": return "¥28,000 + AI core (if recovered)"
        case "Mission003": return "¥40,000 + mage's grimoire"
        case "Mission004": return "¥50,000 + security override codes"
        case "Mission005": return "¥60,000 + Mekton prototype (if recovered)"
        case "Mission006": return "¥500,000 + AGI core data (if recovered)"
        default:            return "¥15,000"
        }
    }

    // Keep these aligned with MissionSelectView.missions risk strings — the player
    // sees the risk on the select screen and again on the briefing, and the two
    // were drifting (Mission003 said HARD on select, EXTREME on briefing; Mission005
    // said EXTREME on select, HIGH on briefing).
    private var riskLevel: String {
        switch manager.selectedMissionId ?? "" {
        case "Mission001": return "EASY"
        case "Mission002": return "HIGH"
        case "Mission003": return "HARD"
        case "Mission004": return "EXTREME"
        case "Mission005": return "EXTREME"
        default:            return "UNKNOWN"
        }
    }

    /// True if the current mission has a recoverable data terminal as a
    /// secondary objective (M2-M6 all do; M1 doesn't). Used to surface the
    /// "HACK TERMINAL" chip on the briefing so the player knows the
    /// secondary-objective payout exists before they walk in.
    private var missionHasTerminal: Bool {
        switch manager.selectedMissionId ?? "" {
        case "Mission002", "Mission003", "Mission004", "Mission005", "Mission006":
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            // (Zero State studio sigil is rendered INLINE below the
            // ACCEPT CONTRACT button — see the button block further
            // down. Footer-style placement keeps it away from the title
            // chrome and gives it breathing room as a deliberate page
            // seal.)

            VStack(spacing: 24) {
                Text("BRIEFING")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(Color(hex: "00FF88"))
                    .tracking(4)

                // Team roster with portraits
                VStack(spacing: 12) {
                    Text("TEAM ROSTER")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                        .tracking(2)

                    HStack(spacing: 12) {
                        ForEach(0..<min(4, teamRoster.count), id: \.self) { i in
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(getTeamColor(i))
                                        .frame(width: 48, height: 48)
                                    Text(String(teamRoster[i].name.prefix(1)))
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.black)
                                }
                                Text(teamRoster[i].name.prefix(6).lowercased())
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color(hex: "0F0F1E"))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    briefingRow("Mission:", missionTitle)
                    briefingRow("Risk:", riskLevel)
                    briefingRow("Pay:", reward)
                    briefingRow("Briefing:", missionDesc)
                }
                .padding(20)
                .background(Color(hex: "0F0F1E"))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "1E1E3E"), lineWidth: 1)
                )

                // Intel badges — pulled in from the old MissionBriefingOverlay
                // so this single screen carries all the at-a-glance numbers
                // (hostiles count, objective, exfil) the player previously
                // got from the redundant overlay.
                HStack(spacing: 12) {
                    IntelBadge(label: "HOSTILES", value: "\(totalEnemyCount)")
                    IntelBadge(label: "OBJECTIVE", value: "REACH EXIT")
                    if missionHasTerminal {
                        // Surface the secondary-objective chip so the player
                        // sees the bonus exists BEFORE the run — previously
                        // they'd only learn about it via the in-mission HUD
                        // "DATA: PENDING" chip, which is easy to miss.
                        IntelBadge(label: "DATA", value: "HACK TERMINAL")
                    }
                    IntelBadge(label: "EXFIL", value: "EXTRACTION PT.")
                }

                Spacer()

                Button(action: {
                    beginMission()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "00FF88"))
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "00FF88"), lineWidth: 2)
                            .opacity(0.5)

                        Text("ACCEPT CONTRACT")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.black)
                    }
                    .frame(width: 240, height: 50)
                }

                // Zero State studio sigil — footer mark below the ACCEPT
                // CONTRACT button. Centered, sized to read at glance against
                // the dark page background. Placed here (rather than as a
                // header crest above the BRIEFING title) so it doesn't
                // compete with the page chrome at the top.
                Image("zero_state_mark_1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .opacity(0.75)
                    .padding(.top, 8)
            }
            .padding(24)
            .onAppear { loadMission() }

            // Cinematic mission-briefing overlay. Player taps anywhere to
            // dismiss, then the team-roster + ACCEPT CONTRACT screen
            // underneath becomes interactive. Restored 2026-05 by request.
            if showCinematicBriefing {
                MissionBriefingOverlay(
                    mission: loadedMission,
                    enemyCountOverride: loadedMultiRoom != nil ? totalEnemyCount : nil,
                    titleOverride: loadedMultiRoom?.title,
                    descriptionOverride: loadedMultiRoom?.description,
                    missionId: manager.selectedMissionId,
                    onDismissed: { showCinematicBriefing = false }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    private func briefingRow(_ label: String, _ value: String) -> some View {
        // Label column is 96pt and pinned to a single line — "Briefing:" in
        // callout-monospaced font is wider than the old 80pt column and
        // was wrapping its colon onto its own line. The value text uses
        // `.fixedSize(horizontal: false, vertical: true)` so multi-line
        // body text wraps cleanly inside its remaining width instead of
        // truncating or pushing the column.
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.callout, design: .monospaced))
    }

    private func loadMission() {
        guard let id = manager.selectedMissionId else { return }
        // Match MissionSetupService: try multi-room first, fall back to single-room.
        // Loading both lets us prefer multi-room data for hostile counts while still
        // having the single-room Mission available as a fallback for description, etc.
        loadedMultiRoom = MissionLoader.shared.loadMultiRoomMission(named: id)
        loadedMission = MissionLoader.shared.loadMission(named: id)
    }

    private func beginMission() {
        HapticsManager.shared.selectAffirm()
        HapticsManager.shared.combatStart()
        _ = GameState.shared.prepareMissionForCombat(named: manager.selectedMissionId)
        _ = manager.transition(to: .beginMission)
    }

    private func getTeamColor(_ index: Int) -> Color {
        let colors = [
            Color(hex: "00FF88"),
            Color(hex: "00D4FF"),
            Color(hex: "FF8800"),
            Color(hex: "FF3366")
        ]
        return colors[index % colors.count]
    }
}

// MARK: - Combat View

struct CombatView: View {
    @ObservedObject var manager: PhaseManager
    @ObservedObject var gameState: GameState
    @State private var showDiagnostics = false
    @State private var showAbortConfirm = false
    @State private var objectiveBannerHeight: CGFloat = 96
    @State private var combatUIHeight: CGFloat = 180
    @State private var infoSheetPayload: CharacterInfoSheet.InfoPayload? = nil

    /// Outcome line shown on the "RUN COMPLETE" overlay. Reports the nuyen
    /// payout for the mission plus a per-mission objective-bonus line that
    /// reflects what the player ACTUALLY recovered (terminal data, grimoire,
    /// etc.) — driven by `gameState.dataAcquired` / `gameState.grimoireAcquired`.
    private var victoryText: String {
        let data = gameState.dataAcquired
        let grimoire = gameState.grimoireAcquired
        let dataLine: String = data
            ? "✓ DATA RECOVERED"
            : "✗ DATA MISSED"
        let grimLine: String = grimoire
            ? "✓ GRIMOIRE ACQUIRED"
            : "✗ GRIMOIRE LEFT BEHIND"
        switch manager.selectedMissionId ?? "" {
        case "Mission001":
            return "¥15,000 earned"
        case "Mission002":
            return "¥28,000 earned\n\(dataLine)  (+¥7,500 bonus)"
        case "Mission003":
            return "¥40,000 earned\n\(dataLine)  (+¥7,500 bonus)\n\(grimLine)  (+¥10,000 bonus)"
        case "Mission004":
            return "¥50,000 earned\n\(dataLine)  (+¥10,000 bonus)"
        case "Mission005":
            return "¥60,000 earned\n\(dataLine)  (+¥10,000 bonus)"
        case "Mission006":
            return "¥500,000 earned\n\(dataLine)  (+¥50,000 bonus)"
        default:
            return "¥15,000 earned"
        }
    }

    private var missionTitle: String {
        switch manager.selectedMissionId ?? "" {
        case "Mission001": return "The Extraction"
        case "Mission002": return "Ghost Protocol"
        case "Mission003": return "The Mage's Lair"
        case "Mission004": return "Dead Man's Switch"
        case "Mission005": return "Mekton Blues"
        case "Mission006": return "Ghost Signal"
        default:            return "Unknown Mission"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen SpriteKit board — GeometryReader gives us the real available size
            GeometryReader { geometry in
                BattleSceneView(
                    gameState: gameState,
                    missionId: manager.selectedMissionId,
                    parentSize: geometry.size,
                    topHUDInset: objectiveBannerHeight,
                    bottomHUDInset: combatUIHeight
                )
            }
            .ignoresSafeArea()

            // Overlays — shown only during active combat
            if !gameState.combatEnded {
                // CENTER: Mission objective banner — sits in the middle of
                // the screen on mission start so the character sprites at
                // the top of the map remain visible behind/around it. The
                // banner auto-hides after a few seconds (handled inside
                // MissionObjectiveBanner), at which point the play area is
                // unobstructed.
                VStack {
                    Spacer()
                    MissionObjectiveBanner(
                        missionTitle: missionTitle,
                        missionId: manager.selectedMissionId ?? "",
                        extractionX: gameState.extractionX,
                        extractionY: gameState.extractionY
                    )
                    .padding(.horizontal, 12)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: CombatTopOverlayHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    )
                    Spacer()
                }

                // TOP CENTER: transient warning banner. Renders whenever
                // GameState.transientWarning is non-nil and auto-clears via
                // the timer in postTransientWarning. Currently fires when
                // the player tries to leave a room with an unhacked required
                // terminal.
                if let warning = gameState.transientWarning {
                    VStack {
                        TerminalWarningBanner(text: warning)
                            .padding(.top, 80)
                            .padding(.horizontal, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.25), value: gameState.transientWarning)
                }

                // TOP RIGHT: abort-to-menu button + lightweight diagnostics.
                //
                // Layout note: the underlying SpriteKit map ignores safe area
                // and bleeds up under the Dynamic Island / status bar area
                // (per the camera scaling), so a safe-area-respecting button
                // landed visually ON TOP OF the map background. Here we
                // ignore the top safe area for this overlay and use an
                // explicit padding that parks the button just below the
                // Dynamic Island — clear of the status icons but high enough
                // that the play area below is unobstructed.
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            // Abort button — opens confirmation overlay so a
                            // misstap doesn't kill an in-progress mission.
                            Button(action: {
                                HapticsManager.shared.back()
                                showAbortConfirm = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("MENU")
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                }
                                .foregroundColor(Color(hex: "FF4A4A"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Color.black.opacity(0.65)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(hex: "FF4A4A").opacity(0.7), lineWidth: 1.2)
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            if showDiagnostics {
                                CombatDiagnosticsPanel(
                                    phase: manager.currentPhase,
                                    round: gameState.roundNumber,
                                    activeActorId: (gameState.activeCharacter ?? gameState.currentCharacter)?.id.uuidString,
                                    fpsText: FPSMonitor.shared.currentFPSLabel,
                                    authoritySummary: gameState.turnAuthoritySummary,
                                    traceLevel: gameState.traceLevel,
                                    traceThreshold: gameState.traceThreshold,
                                    traceTriggered: gameState.isTraceTriggered,
                                    traceEscalationLevel: gameState.traceEscalationLevel,
                                    traceGainPerSignal: gameState.traceGainPerSignal,
                                    traceRecoveryPerLayLow: gameState.traceRecoveryPerLayLow,
                                    traceTelemetrySummary: gameState.traceTelemetrySummary(),
                                    playerRole: gameState.playerRoleLabel
                                )
                            }
                        }
                        .padding(.top, 56)   // Clear Dynamic Island / status bar.
                        .padding(.trailing, 12)
                    }
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }

            // Matrix hacking mini-game overlay — fires when a runner steps
            // onto a data terminal. The router picks one of three distinct
            // mini-games based on the active mission:
            //   M2 → LaneRunner   M4 → CypherCracker   M5 → PacketRouter
            if gameState.showMatrixMiniGame {
                MatrixMiniGameRouter(gameState: gameState) { success in
                    CombatFlowController.resolveMatrixMiniGame(gameState: gameState, success: success)
                }
                .transition(.opacity)
                .zIndex(900)
            }

            // Abort-mission confirmation overlay — full-screen so taps can't
            // leak through. Tap "ABORT" → return to mission select. Tap
            // outside or "CANCEL" → dismiss and resume.
            if showAbortConfirm {
                AbortMissionOverlay(
                    onCancel: { showAbortConfirm = false },
                    onConfirm: {
                        showAbortConfirm = false
                        HapticsManager.shared.back()
                        gameState.combatEnded = false
                        gameState.combatWon = nil
                        _ = manager.transition(to: .returnToTitle)
                    }
                )
                .zIndex(940)
            }

            // Long-press info sheet — surfaces character/enemy dossier (stats
            // + archetype + lore from SHADOWRUN-LORE.md). Triggered by a
            // 0.45s press on a character or enemy tile in BattleScene.
            if let payload = infoSheetPayload {
                CharacterInfoSheet(payload: payload, onDismiss: {
                    infoSheetPayload = nil
                })
                .zIndex(945)
                .transition(.opacity)
            }

            if gameState.combatEnded {
                // Combat ended overlay — full-screen so taps can never leak to
                // the combat scene behind. Both success and failure show the
                // same control: tap to advance. Failures additionally have an
                // explicit "HOME SCREEN" button + an auto-return safety net.
                CombatEndOverlay(
                    gameState: gameState,
                    manager: manager,
                    victoryText: victoryText
                )
                .zIndex(950)
            } else {
                // SwiftUI combat UI — bottom-aligned, content-sized
                CombatUI(
                    gameState: gameState,
                    diagnosticsVisible: showDiagnostics,
                    onToggleDiagnostics: { showDiagnostics.toggle() },
                    onAttack: { gameState.performAttack() },
                    onShoot: { gameState.performShoot() },
                    onDefend: { gameState.performDefend() },
                    onSpell: { /* handled by SpellPickerSheet inside CombatUI */ },
                    onBlitz: { gameState.performBlitz() },
                    onHack: { gameState.performHack() },
                    onIntimidate: { gameState.performIntimidate() },
                    onItems: { gameState.performUseItem() },
                    onRecover: { gameState.performLayLow() },
                    onEndTurn: { gameState.endTurn() }
                )
                .background(
                    CombatTheme.background.opacity(0.92)
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CombatBottomOverlayHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onPreferenceChange(CombatTopOverlayHeightPreferenceKey.self) { height in
            objectiveBannerHeight = max(96, height)
            dlog("[CombatView] objectiveBannerHeight=\(objectiveBannerHeight)")
        }
        .onPreferenceChange(CombatBottomOverlayHeightPreferenceKey.self) { height in
            combatUIHeight = max(150, height)
            dlog("[CombatView] combatUIHeight=\(combatUIHeight)")
        }
        .onAppear { FPSMonitor.shared.start() }
        .onDisappear { FPSMonitor.shared.stop() }
        // Long-press info-sheet bridge — BattleScene posts when the player
        // long-presses a character/enemy tile, this resolves the entity from
        // GameState and shows the modal sheet.
        .onReceive(NotificationCenter.default.publisher(for: .entityInfoRequested)) { note in
            guard let kind = note.userInfo?["kind"] as? String else { return }
            switch kind {
            case "player":
                guard let idStr = note.userInfo?["characterId"] as? String,
                      let id = UUID(uuidString: idStr),
                      let char = gameState.playerTeam.first(where: { $0.id == id }) else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    infoSheetPayload = .player(char)
                }
            case "enemy":
                guard let idStr = note.userInfo?["enemyId"] as? String,
                      let id = UUID(uuidString: idStr),
                      let enemy = gameState.enemies.first(where: { $0.id == id }) else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    infoSheetPayload = .enemy(enemy)
                }
            default: break
            }
        }
    }
}

// MARK: - Abort Mission Overlay
//
// Tapped from the top-right "MENU" button during a live mission. Confirms
// before leaving so a misstap doesn't kill an in-progress run. Both buttons
// haptic-tap on press.
private struct AbortMissionOverlay: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color(hex: "FF4A4A"))
                Text("ABORT MISSION?")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: "FF4A4A"))
                Text("All progress in this mission will be lost.\nReturn to the mission select screen?")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: "C8D6FF"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 14) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(hex: "C8D6FF"))
                            .frame(minWidth: 110)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "C8D6FF").opacity(0.5), lineWidth: 1.2)
                            )
                    }
                    Button(action: onConfirm) {
                        Text("ABORT")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(minWidth: 110)
                            .padding(.vertical, 12)
                            .background(Color(hex: "AA1133"))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "0A0E18"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "FF4A4A").opacity(0.6), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal, 32)
        }
    }
}

private struct CombatTopOverlayHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 96

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CombatBottomOverlayHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 280

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CombatDiagnosticsPanel: View {
    let phase: GamePhase
    let round: Int
    let activeActorId: String?
    let fpsText: String
    let authoritySummary: String
    let traceLevel: Int
    let traceThreshold: Int
    let traceTriggered: Bool
    let traceEscalationLevel: Int
    let traceGainPerSignal: Int
    let traceRecoveryPerLayLow: Int
    let traceTelemetrySummary: String
    let playerRole: String

    private var actorLabel: String {
        guard let activeActorId, !activeActorId.isEmpty else { return "n/a" }
        return String(activeActorId.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("diag")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: "00FF88").opacity(0.75))
            Text("phase: \(phase.displayName.lowercased())")
            Text("round: \(round)")
            Text("actor: \(actorLabel)")
            Text("fps: \(fpsText)")
            Text("trace: \(traceLevel)/\(traceThreshold) trig=\(traceTriggered ? "yes" : "no")")
            Text("traceEsc: \(traceEscalationLevel)")
            Text("role: \(playerRole)")
            Text("cadence: th\(traceThreshold) +\(traceGainPerSignal) / -\(traceRecoveryPerLayLow)")
            Text(traceTelemetrySummary)
            Text(authoritySummary)
                .lineLimit(2)
                .foregroundColor(.white.opacity(0.65))
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "00FF88").opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityIdentifier("combat_diagnostics_panel")
    }
}

@MainActor
private final class FPSMonitor: ObservableObject {
    static let shared = FPSMonitor()

    @Published private(set) var currentFPSLabel: String = "n/a"

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0

    private init() {}

    func start() {
        guard displayLink == nil else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }
        lastTimestamp = 0
        frameCount = 0
        currentFPSLabel = "n/a"

        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        currentFPSLabel = "n/a"
    }

    @objc private func step(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        frameCount += 1
        let delta = link.timestamp - lastTimestamp
        guard delta >= 1 else { return }
        let fps = Int((Double(frameCount) / delta).rounded())
        currentFPSLabel = fps > 0 ? "\(fps)" : "n/a"
        frameCount = 0
        lastTimestamp = link.timestamp
    }
}

// MARK: - Battle Scene Wrapper

/// Plain SKView wrapper used by BattleSceneView.
/// BattleScene already receives touches through SpriteKit; claiming every touch here
/// breaks the SwiftUI combat HUD above it.
class ForwardingSKView: SKView {}

struct BattleSceneView: UIViewRepresentable {
    @ObservedObject var gameState: GameState
    var missionId: String?
    var parentSize: CGSize = .zero
    var topHUDInset: CGFloat = 96
    var bottomHUDInset: CGFloat = 180

    // Fixed tile map size — 10 tiles × 56pt = 560pt wide, 18 tiles × 56pt = 1008pt tall
    static let tileMapSize = CGSize(width: 560, height: 1008)

    func makeUIView(context: Context) -> SKView {
        let skView = ForwardingSKView()
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.preferredFramesPerSecond = 60
        skView.backgroundColor = .black
        // Use autoresizing mask so the view fills its superview naturally.
        // SwiftUI's GeometryReader -> ZStack -> ForwardingSKView hierarchy gives
        // us the correct bounds via the ZStack's layout pass.
        skView.translatesAutoresizingMaskIntoConstraints = true
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Give SKView an initial frame at screen size — actual bounds come from layout.
        skView.frame = UIScreen.main.bounds
        context.coordinator.skView = skView
        dlog("[BattleSceneView] makeUIView frame: \(skView.frame.size)")
        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        // Get the actual available size directly from the SKView's superview bounds.
        // This is always correct because it comes from the current layout pass.
        // parentSize (SwiftUI @State) lags behind on first render, so never use it.
        let availableSize: CGSize
        if let superviewBounds = skView.superview?.bounds, superviewBounds.width > 0, superviewBounds.height > 0 {
            availableSize = superviewBounds.size
        } else {
            availableSize = UIScreen.main.bounds.size
        }

        // Resize SKView frame to match available space. With
        // translatesAutoresizingMaskIntoConstraints=true and
        // autoresizingMask=.flexibleWidth/.flexibleHeight this should already
        // be correct from the layout pass, but this ensures it.
        if skView.frame.size != availableSize {
            skView.frame = CGRect(origin: .zero, size: availableSize)
            dlog("[BattleSceneView] Resized SKView to: \(availableSize)")
        }

        let missionToLoad = missionId ?? "Mission001"
        let resolvedTopInset = max(96, topHUDInset)
        let resolvedBottomInset = max(150, bottomHUDInset)

        if let existingScene = context.coordinator.scene {
            existingScene.updateViewportInsets(top: resolvedTopInset, bottom: resolvedBottomInset)
        }

        let hasStrictPreparedMatch =
            (context.coordinator.preparedMissionId == missionToLoad)
            && (context.coordinator.scene != nil)
            && (skView.scene === context.coordinator.scene)

        // Scene already presented for this mission — nothing to do.
        if hasStrictPreparedMatch { return }

        guard availableSize.width > 0, availableSize.height > 0 else {
            dlog("[BattleSceneView] No available size, skipping scene creation")
            return
        }

        // CRITICAL FIX: Scene size must match the SKView's available bounds (via fitSceneToView),
        // and mapOrigin is computed from (scene.size - mapPixelSize)/2.
        // This ensures the tile map is centered and the top/bottom rows are reachable.
        // fitSceneToView() is called BEFORE loadMap() so BattleScene.mapOrigin is correct.
        // With scaleMode = .aspectFit the full scene (map + letterboxing) fills the SKView.
        let missionTileMap = resolvePreparedTileMap(for: missionToLoad)
        let initialRoomId = resolveInitialRoomId(for: missionToLoad)

        guard let missionTileMap, !gameState.playerTeam.isEmpty else {
            dlog("[BattleSceneView] Missing prepared combat state for \(missionToLoad); skipping scene creation")
            return
        }

        // Scene size = map pixel dimensions. With .aspectFit, SpriteKit scales to fit the view,
        // centering the map. mapOrigin = (scene.size - mapPixelDims) / 2 is always (.zero)
        // when scene.size == mapPixelDims, keeping all coordinate math simple.
        let mapPixelW  = CGFloat(TileMap.mapWidth - 1) * TileMap.hexColSpacing + TileMap.hexRadius * 2
        let mapHeight: Int
        mapHeight = missionTileMap.mapHeight
        let mapPixelH  = (CGFloat(mapHeight) + 0.5) * TileMap.hexRowSpacing
        let sceneSize  = CGSize(width: mapPixelW, height: mapPixelH)

        // Create scene at map pixel dimensions; fitSceneToView() called below
        // (before loadMap) will override self.size to match SKView bounds.
        let scene = BattleScene(size: sceneSize)
        scene.scaleMode = .aspectFit
        // CRITICAL: anchorPoint (0,0) = bottom-left. All coordinate math (mapOrigin,
        // tileCenter, focusCamera) assumes origin at bottom-left. Default (0.5, 0.5)
        // puts origin at screen center and shifts the map off to the right.
        scene.anchorPoint = CGPoint(x: 0, y: 0)
        scene.backgroundColor = UIColor(hex: "#0D0D0D")
        scene.isUserInteractionEnabled = true
        scene.updateViewportInsets(top: resolvedTopInset, bottom: resolvedBottomInset)

        // Schedule initial load on the scene. BattleScene.didMove will call loadMap +
        // placeCharacter/placeEnemy once the view is attached and scene.size is final.
        // This is the single source of truth for the first frame — doing placement
        // before presentScene was racey (view nil → fitSceneToView was a no-op →
        // wrong scene.size → wrong mapOrigin → characters off-camera).
        scene.scheduleInitialLoad(
            tileMap: missionTileMap,
            roomId: initialRoomId,
            characters: gameState.playerTeam,
            enemies: GameState.shared.enemies
        )

        dlog("[BattleSceneView] Presenting scene size: \(scene.size), view.bounds: \(skView.bounds.size), playerTeam=\(gameState.playerTeam.count), enemies=\(GameState.shared.enemies.count)")
        skView.presentScene(scene)
        context.coordinator.scene = scene
        context.coordinator.preparedMissionId = missionToLoad
    }

    private func resolvePreparedTileMap(for missionId: String) -> TileMap? {
        let rawTiles = gameState.currentMissionTilesSnapshot
        if !rawTiles.isEmpty {
            let typedTiles = rawTiles.map { row in
                row.map { TileType(rawValue: $0) ?? .floor }
            }
            return TileMap(tiles: typedTiles)
        }

        if let multiMission = MissionLoader.shared.loadMultiRoomMission(named: missionId),
           let firstRoom = multiMission.rooms.first {
            return TileMap(tiles: firstRoom.tileMap)
        }

        if let mission = MissionLoader.shared.loadMission(named: missionId) {
            return MissionLoader.shared.buildTileMap(from: mission)
        }

        guard let fallbackMission = MissionLoader.shared.loadMission(named: "Mission001") else {
            return nil
        }

        return MissionLoader.shared.buildTileMap(from: fallbackMission)
    }

    private func resolveInitialRoomId(for missionId: String) -> String {
        if !gameState.currentRoomId.isEmpty {
            return gameState.currentRoomId
        }

        if let currentRoomId = RoomManager.shared.currentRoom?.id, !currentRoomId.isEmpty {
            return currentRoomId
        }

        if let multiMission = MissionLoader.shared.loadMultiRoomMission(named: missionId) {
            return multiMission.rooms.first?.id ?? "room_0"
        }

        return "room_0"
    }

    func makeCoordinator() -> Coordinator { Coordinator(gameState: gameState) }

    class Coordinator {
        var scene: BattleScene?
        weak var skView: SKView?
        var preparedMissionId: String?
        var gameState: GameState

        init(gameState: GameState) {
            self.gameState = gameState
            setupCombatEndObserver()
        }

        private func setupCombatEndObserver() {
            NotificationCenter.default.addObserver(
                forName: .combatAction,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let userInfo = notification.userInfo,
                      let result = userInfo["result"] as? String else { return }
                if result == "victory" || result == "defeat" {
                    let won = result == "victory"
                    DispatchQueue.main.async {
                        self?.gameState.addLog(won ? "Mission complete!" : "Mission failed.")
                    }
                }
            }
        }
    }
}

// MARK: - Combat End Overlay

/// Full-screen overlay shown the moment combat ends (victory or defeat).
/// Owns its own auto-dismiss timer so the player is never stuck if the
/// buttons fail to tap or the user just sets the device down.
///   • Victory  → tap "VIEW DEBRIEF" → debrief screen → "RETURN TO TITLE".
///   • Defeat   → tap "VIEW DEBRIEF" or "HOME SCREEN" — and after 6s with
///                no input we auto-route home so failures can't strand the
///                player on the combat scene.
struct CombatEndOverlay: View {
    @ObservedObject var gameState: GameState
    @ObservedObject var manager: PhaseManager
    let victoryText: String

    @State private var autoReturnTimer: Timer? = nil
    @State private var secondsRemaining: Int = 6

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 24) {
                // Zero State studio sigil — sits ABOVE the RUN COMPLETE / RUN
                // FAILED headline. Large (72pt) and at full opacity so it
                // reads like a mission-end seal stamped on top of the result.
                // Uses mark_3 (target glyph — distinct from the briefing and
                // mission-select corner sigils so each major screen has its
                // own).
                Image("zero_state_mark_3")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .opacity(0.95)
                    .padding(.bottom, -8)

                Text(gameState.combatWon == true ? "RUN COMPLETE" : "RUN FAILED")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(gameState.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"))
                if gameState.combatWon != nil {
                    Text(gameState.combatWon == true ? victoryText : "Mission failed — all runners down")
                        .font(.headline)
                        .foregroundColor(.gray)
                }

                // Primary: VIEW DEBRIEF
                Button(action: viewDebrief) {
                    Text("VIEW DEBRIEF")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(width: 240, height: 52)
                        .background(gameState.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"))
                        .cornerRadius(8)
                }

                // Always-present HOME SCREEN — gives the player an immediate
                // escape hatch on either outcome. Coloured to match outcome.
                Button(action: returnHome) {
                    Text("HOME SCREEN")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(gameState.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"))
                        .frame(width: 200, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    (gameState.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333")).opacity(0.6),
                                    lineWidth: 1
                                )
                        )
                }

                // Auto-return countdown only on failure — so the player is
                // never left stranded on a "RUN FAILED" screen.
                if gameState.combatWon == false {
                    Text("Auto-returning to title in \(secondsRemaining)s …")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "FF3333").opacity(0.7))
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Start auto-return safety timer on failure only
            if gameState.combatWon == false {
                secondsRemaining = 6
                autoReturnTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                    Task { @MainActor in
                        secondsRemaining -= 1
                        if secondsRemaining <= 0 {
                            t.invalidate()
                            returnHome()
                        }
                    }
                }
            }
        }
        .onDisappear {
            autoReturnTimer?.invalidate()
            autoReturnTimer = nil
        }
    }

    private func viewDebrief() {
        HapticsManager.shared.buttonTap()
        autoReturnTimer?.invalidate()
        let won = gameState.combatWon ?? false
        gameState.combatEnded = false
        gameState.combatWon = nil
        _ = manager.transition(to: .endCombat(won: won))
    }

    private func returnHome() {
        HapticsManager.shared.buttonTap()
        autoReturnTimer?.invalidate()
        gameState.combatEnded = false
        gameState.combatWon = nil
        _ = manager.transition(to: .returnToTitle)
    }
}

// MARK: - Debrief View

struct DebriefView: View {
    @ObservedObject var manager: PhaseManager

    /// Per-mission reward summary on the CONTRACT FULFILLED screen.
    /// Reads live mission-objective state (`GameState.shared.dataAcquired`,
    /// `grimoireAcquired`) so the line reflects what the player ACTUALLY
    /// recovered, not just what the mission could pay out.
    private var rewardText: String {
        guard manager.combatWon == true else { return "No payout — mission failed" }
        let data = GameState.shared.dataAcquired
        let grimoire = GameState.shared.grimoireAcquired
        let dataLine = data ? "✓ DATA RECOVERED" : "✗ DATA MISSED"
        let grimLine = grimoire ? "✓ GRIMOIRE ACQUIRED" : "✗ GRIMOIRE LEFT BEHIND"
        switch manager.selectedMissionId ?? "" {
        case "Mission001":
            return "¥15,000 earned"
        case "Mission002":
            return "¥28,000 earned\n\(dataLine)  (+¥7,500)"
        case "Mission003":
            return "¥40,000 earned\n\(dataLine)  (+¥7,500)\n\(grimLine)  (+¥10,000)"
        case "Mission004":
            return "¥50,000 earned\n\(dataLine)  (+¥10,000)"
        case "Mission005":
            return "¥60,000 earned\n\(dataLine)  (+¥10,000)"
        case "Mission006":
            return "¥500,000 earned\n\(dataLine)  (+¥50,000)"
        default:
            return "¥15,000 earned"
        }
    }

    var body: some View {
        ZStack {
            // Zero State studio sigil — centered crest above the
            // CONTRACT FULFILLED / FAILED title. Matches mission select
            // and briefing.
            VStack {
                Image("zero_state_mark_3")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .opacity(0.55)
                    .padding(.top, 6)
                Spacer()
            }
            .allowsHitTesting(false)

            VStack(spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                manager.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"),
                                lineWidth: 2
                            )
                    )

                Text(manager.combatWon == true ? "CONTRACT FULFILLED" : "CONTRACT FAILED")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(manager.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"))
            }
            .frame(height: 80)

            VStack(spacing: 16) {
                Text(rewardText)
                    .foregroundColor(manager.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"))
                    .font(.headline)
                    .multilineTextAlignment(.center)

                // Wallet balance — shows the running total nuyen after this
                // mission's payout has been credited. Only on victory (failed
                // runs don't pay out so the balance line would be misleading).
                if manager.combatWon == true {
                    HStack(spacing: 8) {
                        Text("WALLET")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "FFCC00").opacity(0.75))
                            .tracking(2)
                        Text("¥\(MissionStatsStore.shared.playerNuyen.formatted())")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(Color(hex: "FFCC00"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "FFCC00").opacity(0.45), lineWidth: 1)
                            )
                    )
                }

                // Stats display
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ROUNDS")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                        Text("\(GameState.shared.roundNumber)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ENEMIES DEFEATED")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                        // Running tally across ALL rooms — `gameState.enemies` only
                        // holds the current room's roster, so it would under-count
                        // by one (or more) rooms in multi-room missions.
                        Text("\(GameState.shared.missionEnemiesDefeated)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(hex: "0F0F1E"))
                .cornerRadius(8)

                // Secondary-objective status chips. Surface the data /
                // grimoire recovery outcome as visible chips so the player
                // immediately sees whether they got the bonus haul without
                // having to parse the multi-line reward text above. Only
                // show on victory and only for missions where the
                // objective is actually applicable.
                if manager.combatWon == true {
                    let mid = manager.selectedMissionId ?? ""
                    let hasTerminal = ["Mission002","Mission003","Mission004","Mission005","Mission006"].contains(mid)
                    let hasGrimoire = (mid == "Mission003")
                    if hasTerminal || hasGrimoire {
                        HStack(spacing: 8) {
                            if hasTerminal {
                                DebriefStatusChip(
                                    label: "DATA",
                                    acquired: GameState.shared.dataAcquired
                                )
                            }
                            if hasGrimoire {
                                DebriefStatusChip(
                                    label: "GRIMOIRE",
                                    acquired: GameState.shared.grimoireAcquired
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(Color(hex: "0A0A14"))
            .cornerRadius(12)

            Spacer()

            Button(action: {
                HapticsManager.shared.buttonTap()
                // After a successful M6 (the final mission), this button leads
                // into the game-ending epilogue instead of the menu. All other
                // debriefs (M1–M5 wins + any loss) go straight back to the
                // mission select screen.
                let isFinaleVictory = (manager.selectedMissionId == "Mission006"
                                       && manager.combatWon == true)
                if isFinaleVictory {
                    _ = manager.transition(to: .viewGameEnding)
                } else {
                    _ = manager.transition(to: .returnToTitle)
                }
            }) {
                // Button label changes for the finale-victory case so the
                // player isn't surprised by a cutscene instead of the menu.
                let isFinaleVictory = (manager.selectedMissionId == "Mission006"
                                       && manager.combatWon == true)
                Text(isFinaleVictory ? "VIEW EPILOGUE" : "RETURN TO MENU")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(width: 220, height: 50)
                    // Match the debrief outcome colour so failure debrief reads
                    // as failure instead of celebrating in green.
                    .background(manager.combatWon == true ? Color(hex: "00FF88") : Color(hex: "FF3333"))
                    .cornerRadius(8)
            }
        }
        .padding(24)
        }   // close outer ZStack (Zero State mark watermark wrapper)
    }
}

// MARK: - Debrief Status Chip

/// Visual chip for the debrief screen showing a secondary-objective
/// outcome — DATA / GRIMOIRE acquired vs missed. Green ✓ on success,
/// dim red ✗ on miss. Designed to read at a glance so the player
/// doesn't have to parse the multi-line reward text.
private struct DebriefStatusChip: View {
    let label: String
    let acquired: Bool

    var body: some View {
        let tint: Color = acquired ? Color(hex: "00FF88") : Color(hex: "FF3344")
        HStack(spacing: 6) {
            Image(systemName: acquired ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.system(size: 10))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(tint.opacity(0.75))
                Text(acquired ? "ACQUIRED" : "MISSED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tint.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Phase Manager

/// Renamed to avoid collision with combat runtime GameState class
/// Canonical active phase-flow authority for UI/runtime screen routing.
/// Transition rule edits must be specified in
/// `docs/architecture/PhaseFlowAuthorityMatrix.md` first.
@MainActor
final class PhaseManager: ObservableObject {

    @Published private(set) var currentPhase: GamePhase = .title
    @Published private(set) var selectedMissionId: String?
    @Published private(set) var combatWon: Bool?

    private var stateHistory: [GamePhase] = [.title]

    func transition(to event: StateTransition) -> Bool {
        let nextState = computeNext(from: currentPhase, event: event)
        if nextState == currentPhase { return false }

        if case .selectMission(let id) = event { selectedMissionId = id }
        if case .endCombat(let won) = event { combatWon = won }
        if case .endBrawl(let won) = event { combatWon = won }
        if case .endMirrorline(let won) = event { combatWon = won }
        if case .endColdTrace(let won) = event { combatWon = won }
        if case .endChase(let won) = event { combatWon = won }

        stateHistory.append(nextState)
        currentPhase = nextState
        return true
    }

    var stateStack: [GamePhase] { stateHistory }

    /// Canonical transition matrix implementation (active authority).
    /// Keep in lockstep with `PhaseFlowAuthorityMatrix.md`.
    private func computeNext(from state: GamePhase, event: StateTransition) -> GamePhase {
        switch (state, event) {
        case (.title, .startGame):                          return .missionSelect
        case (.title, .viewPrologue):                       return .prologue
        case (.prologue, .finishPrologue):                  return .title           // loop back, don't auto-start
        case (.prologue, .returnToTitle):                   return .title           // skip mid-scene
        case (.missionSelect, .selectMission):              return .missionIntro      // tactical missions go through cutscene first
        // Standard tactical missions (M1–M6) go intro → briefing → combat.
        // M4.5 "Basement Brawl" uses the same intro VN infrastructure but
        // routes straight from the intro into its bespoke gameplay scene —
        // no briefing screen, no hex-grid combat.
        case (.missionIntro, .finishMissionIntro):
            // Half-missions route from MissionIntro straight into their bespoke
            // gameplay scene instead of through Briefing → Combat.
            switch selectedMissionId {
            case "Mission004_5": return .basementBrawl
            case "Mission002_5": return .mirrorline
            case "Mission005_5": return .coldTrace
            default:             return .briefing
            }
        case (.missionIntro, .returnToTitle):               return .missionSelect    // skip mid-cutscene
        case (.missionSelect, .viewDropIntro):              return .dropIntro
        case (.dropIntro, .finishDropIntro):                return .hoverbikeChase
        case (.dropIntro, .returnToTitle):                  return .missionSelect    // skip mid-cutscene
        case (.missionSelect, .viewHoverbikeChase):         return .hoverbikeChase
        case (.hoverbikeChase, .finishHoverbikeChase):      return .missionSelect    // legacy/abort path
        case (.hoverbikeChase, .endChase(let won)):         return won ? .missionOutro : .debrief
        case (.hoverbikeChase, .returnToTitle):             return .missionSelect   // abort mid-chase
        // M4.5 BasementBrawl — Raze's solo melee duel. On win runs through
        // the standard mission-outro VN; on loss skips outro and goes
        // straight to the debrief (same pattern as tactical missions).
        case (.basementBrawl, .endBrawl(let won)):          return won ? .missionOutro : .debrief
        case (.basementBrawl, .returnToTitle):              return .missionSelect   // abort mid-brawl
        // M2.5 Mirrorline — Sable's solo astral sigil-tracing duel. Same
        // win→outro / loss→debrief pattern as the brawl.
        case (.mirrorline, .endMirrorline(let won)):        return won ? .missionOutro : .debrief
        case (.mirrorline, .returnToTitle):                 return .missionSelect   // abort mid-trance
        // M5.5 Cold Trace — Cipher's solo matrix-dive process-triage. Same
        // win→outro / loss→debrief pattern as the brawl + mirrorline.
        case (.coldTrace, .endColdTrace(let won)):          return won ? .missionOutro : .debrief
        case (.coldTrace, .returnToTitle):                  return .missionSelect   // abort mid-dive
        case (.briefing, .beginMission):                    return .combat
        // Victory → mission outro VN scene before scoring; defeat → straight to debrief.
        case (.combat, .endCombat(let won)):                return won ? .missionOutro : .debrief
        case (.combat, .returnToTitle):                     return .missionSelect  // abort from combat → menu
        case (.missionOutro, .finishMissionOutro):          return .debrief
        case (.missionOutro, .viewDebrief):                 return .debrief        // safety: caller-driven skip
        case (.missionOutro, .returnToTitle):               return .missionSelect  // skip mid-outro
        case (.debrief, .viewGameEnding):                   return .gameEnding     // M6 victory only — caller gates
        case (.gameEnding, .finishGameEnding):              return .title          // epilogue done → title
        case (.gameEnding, .returnToTitle):                 return .title          // skip mid-ending → title
        case (.debrief, .returnToTitle):                    return .missionSelect  // post-mission → menu (was .title)
        case (_, .returnToTitle):                           return .missionSelect  // safety catch-all → menu
        default:                                             return state
        }
    }
}

// MARK: - Mission Briefing Overlay

struct MissionBriefingOverlay: View {
    let mission: Mission?
    /// When the briefing is for a multi-room mission, the caller passes the total
    /// hostiles across all rooms so the badge isn't capped at the single-room count.
    var enemyCountOverride: Int? = nil
    var titleOverride: String? = nil
    var descriptionOverride: String? = nil
    /// Mission ID — used to decide whether to surface the "HACK TERMINAL"
    /// secondary-objective chip. Optional so legacy callers without an id
    /// still work (chip simply hides).
    var missionId: String? = nil
    /// Called after the dismiss animation finishes so the parent can hide the overlay.
    var onDismissed: (() -> Void)? = nil

    /// True if this mission has a recoverable data terminal as a secondary
    /// objective. Same rule as BriefingView.missionHasTerminal — M2-M6 do,
    /// M1 doesn't. Mirror kept here so the overlay doesn't need to read
    /// from GameState (which may not be set yet at briefing time).
    private var hasTerminal: Bool {
        switch missionId ?? "" {
        case "Mission002", "Mission003", "Mission004", "Mission005", "Mission006":
            return true
        default:
            return false
        }
    }

    @State private var opacity: Double = 0
    @State private var showContent = false
    @State private var contentOffset: CGFloat = 40

    private var missionTitle: String {
        titleOverride ?? mission?.title ?? "THE EXTRACTION"
    }

    private var missionDesc: String {
        descriptionOverride ?? mission?.description ?? "Infiltrate the corporate facility. Neutralize all hostiles. Extract at the marked point."
    }

    private var enemyCount: Int {
        if let override = enemyCountOverride { return override }
        return mission?.enemies.count ?? 4
    }

    private var dangerColor: Color {
        switch mission?.difficulty ?? "MODERATE" {
        case "EXTREME": return Color(hex: "FF3333")
        case "HIGH": return Color(hex: "FF8800")
        default: return Color(hex: "00FF88")
        }
    }

    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(opacity)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // (Zero State studio sigil is rendered INLINE below the
            // mission title — see the title VStack below. Placing it as
            // a centered crest directly under the mission name reads as
            // a "mission seal" / official packet header instead of as
            // a stray corner glyph or a too-far-away footer.)

            if showContent {
                VStack(spacing: 0) {
                    // Danger level bar
                    Rectangle()
                        .fill(dangerColor)
                        .frame(height: 3)

                    // Top section: mission name + decorative lines
                    VStack(spacing: 12) {
                        HStack {
                            ThinLine()
                            Text("MISSION BRIEFING")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(Color(hex: "00FF88").opacity(0.8))
                                .tracking(3)
                            ThinLine()
                        }

                        Text(missionTitle.uppercased())
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        // Zero State studio sigil — centered directly
                        // below the mission name. Acts as an "official
                        // mission packet seal" between the title and
                        // the operational summary, where it has open
                        // vertical breathing room and aligns visually
                        // with the centered title chrome above.
                        Image("zero_state_mark_4")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .opacity(0.85)
                            .padding(.top, 4)
                    }
                    .padding(.top, 40)

                    Spacer()

                    // Middle: story text + intel
                    VStack(spacing: 24) {
                        // Story text box
                        VStack(alignment: .leading, spacing: 10) {
                            Text("OPERATIONAL SUMMARY")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                                .tracking(2)

                            Text(missionDesc)
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.9))
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "0A0A18"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(hex: "00FF88").opacity(0.3), lineWidth: 1)
                                )
                        )

                        // Intel grid
                        // OBJECTIVE was hardcoded to "NEUTRALIZE ALL", but the in-game
                        // objective banner and the actual mission win condition are
                        // "Reach the extraction point". Showing three different
                        // objectives (briefing says NEUTRALIZE, banner says REACH EXIT,
                        // operational summary says EXTRACT + GET OUT) confused playtest.
                        HStack(spacing: 12) {
                            IntelBadge(label: "HOSTILES", value: "\(enemyCount)")
                            IntelBadge(label: "OBJECTIVE", value: "REACH EXIT")
                            if hasTerminal {
                                IntelBadge(label: "DATA", value: "HACK TERMINAL")
                            }
                            IntelBadge(label: "EXFIL", value: "EXTRACTION PT.")
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Bottom: dismiss prompt
                    VStack(spacing: 12) {
                        // Animated pulse indicator
                        Circle()
                            .fill(Color(hex: "00FF88"))
                            .frame(width: 8, height: 8)
                            .opacity(0.6)

                        Text("TAP ANYWHERE TO BEGIN")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(Color.white.opacity(0.4))
                            .tracking(2)
                    }
                    .padding(.bottom, 40)
                    .offset(y: contentOffset)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { opacity = 1.0 }
            withDelay(0.3) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showContent = true
                    contentOffset = 0
                }
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.3)) {
            showContent = false
            contentOffset = 40
            opacity = 0
        }
        // Let the fade-out finish before the parent unmounts the overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            onDismissed?()
        }
    }
}

struct ThinLine: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: "00FF88").opacity(0.3))
            .frame(height: 1)
    }
}

struct IntelBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                .tracking(1)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "0F0F1E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "1E1E3E"), lineWidth: 1)
                )
        )
    }
}

private func withDelay(_ delay: Double, animation: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: animation)
}
