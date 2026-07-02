import SwiftUI

// MARK: - Per-Mission Intro Cutscenes (M1-M6)
//
// Generic VN-style cutscene that plays between "tap mission card" and the
// briefing screen. Each tactical mission has its own 3-beat script with
// custom backdrops + dialog. Same scene infrastructure as the prologue
// and M3.5 drop intro.
//
// Asset naming convention: `intro_<missionId>_<beat>` (PNG, portrait 9:19).
// Missing assets gracefully degrade to a procedural cyberpunk gradient.

enum IntroSpeaker: String {
    case narrator
    case johnson
    case raze
    case sable
    case lyra
    case cipher
    case youPOV
    case enemyTaunt   // For mission antagonists (corp exec, mech AI, etc.)

    var displayName: String {
        switch self {
        case .narrator:    return ""
        case .johnson:     return "MR. JOHNSON"
        case .raze:        return "RAZE"
        case .sable:       return "SABLE"
        case .lyra:        return "LYRA"
        case .cipher:      return "CIPHER"
        case .youPOV:      return "YOU"
        case .enemyTaunt:  return "// SIGNAL INTERCEPT"
        }
    }

    var color: Color {
        switch self {
        case .narrator:    return Color(hex: "00FFCC")
        case .johnson:     return Color(hex: "DDDDDD")
        case .raze:        return Color(hex: "FF6633")
        case .sable:       return Color(hex: "6699FF")
        case .lyra:        return Color(hex: "FFCC00")
        case .cipher:      return Color(hex: "00DDFF")
        case .youPOV:      return Color(hex: "00FF88")
        case .enemyTaunt:  return Color(hex: "FF3344")
        }
    }
}

struct IntroLine: Identifiable {
    let id: UUID = UUID()
    let speaker: IntroSpeaker
    let text: String
    /// Optional per-line backdrop override. When set, the panel swaps to this
    /// asset for the line. Otherwise the beat's default backdrop is used.
    let panel: String?

    init(speaker: IntroSpeaker, text: String, panel: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.panel = panel
    }
}

struct IntroBeat: Identifiable {
    let id: UUID = UUID()
    let backdrop: String
    let lines: [IntroLine]
}

/// All mission intro scripts in one place. Keyed by mission ID (the same
/// string used everywhere else: "Mission001" through "Mission006").
enum MissionIntroScripts {

    static func beats(for missionId: String) -> [IntroBeat] {
        switch missionId {
        case "Mission001":   return m1
        case "Mission002":   return m2
        case "Mission003":   return m3
        case "Mission004":   return m4
        case "Mission002_5": return m2_5   // Sable's solo astral sigil-tracing
        case "Mission004_5": return m4_5   // Raze's solo basement brawl
        case "Mission005_5": return m5_5   // Cipher's solo matrix-dive process triage
        case "Mission005":   return m5
        case "Mission006":   return m6
        default:             return m1   // safety fallback
        }
    }

    // ── M1 "The Extraction" ──────────────────────────────────────────────
    // First job. Van prep → corp exterior → "go time".
    static let m1: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m1_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Seattle. Industrial sector. A blacked-out van idles two blocks from the Tarrant facility."),
                IntroLine(speaker: .cipher,
                          text: "Comms are clean. I can route us through the patrol blind spot for ninety seconds. After that you're on your own."),
                IntroLine(speaker: .raze,
                          text: "Ninety seconds is plenty if nobody breathes wrong."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m1_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "The Tarrant compound rises across the street — chain link, razor wire, two guards walking a slow loop. Rain ticks against the windshield."),
                IntroLine(speaker: .sable,
                          text: "I'm masking our heat signature. Cameras will see fog where we walk. Don't make me hold this longer than I have to."),
                IntroLine(speaker: .lyra,
                          text: "I'm taking point. Anyone gets twitchy, I drop them quiet."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m1_beat3",
            lines: [
                IntroLine(speaker: .youPOV,
                          text: "Move."),
                IntroLine(speaker: .narrator,
                          text: "Four shadows slip out of the van and vanish into the rain."),
            ]
        ),
    ]

    // ── M2 "Ghost Protocol" ──────────────────────────────────────────────
    // Server farm + AI rumor. Cipher leads. Tech-thriller vibe.
    static let m2: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m2_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Three days after the Tarrant job. A motel safehouse. Cipher's been awake for forty hours staring at a decrypted intel packet."),
                IntroLine(speaker: .cipher,
                          text: "The server farm we're hitting isn't running normal corp ops. Something's WRITING ITSELF in there. Megabytes of code with no human author."),
                IntroLine(speaker: .cipher,
                          text: "Whoever's paying us doesn't want it stolen. They want it ERASED."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m2_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Outside the server farm. Three a.m. The building has no signage. Patrol drones drift in lazy figure-eights above the perimeter."),
                IntroLine(speaker: .sable,
                          text: "The air is wrong here. It tastes like iron and static."),
                IntroLine(speaker: .raze,
                          text: "That's the AI you're feeling, mage. Don't worry about it. I'll cut anything that moves."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m2_beat3",
            lines: [
                IntroLine(speaker: .cipher,
                          text: "I'm in. Patrol pattern is on a 23-second cycle. We move on my mark."),
                IntroLine(speaker: .youPOV,
                          text: "Mark it."),
            ]
        ),
    ]

    // ── M3 "The Mage's Lair" ─────────────────────────────────────────────
    // Occult. Sable leads. Blood mage opponent.
    static let m3: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m3_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "A back-alley spirit shrine in Capitol Hill. Incense thick enough to chew. Sable kneels before a cracked obsidian mirror."),
                IntroLine(speaker: .sable,
                          text: "The mage we're hunting has been pulling blood-tithes from the homeless camps for six months. His wards are old. Hand-cut. Strong."),
                IntroLine(speaker: .sable,
                          text: "I'll need every minute we have to crack the outer ring. Once it falls, his guards will know we're inside."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m3_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "The building looks abandoned from the street. Inside the structural wards, the air shimmers with red sigils only Sable can see."),
                IntroLine(speaker: .lyra,
                          text: "How many guards inside?"),
                IntroLine(speaker: .sable,
                          text: "Two close, one ranged. Plus the mage himself. He'll have a healer with him — body slave, anchored to his own life force."),
                IntroLine(speaker: .raze,
                          text: "Kill the healer first. Got it."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m3_beat3",
            lines: [
                IntroLine(speaker: .sable,
                          text: "The wards are coming down. Stay close. Whatever speaks to you in there — DO NOT answer."),
                IntroLine(speaker: .youPOV,
                          text: "Let's go burn a man."),
            ]
        ),
    ]

    // ── M4 "Dead Man's Switch" ───────────────────────────────────────────
    // Hokuto Industrial HQ. Time-pressured exec hit.
    static let m4: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m4_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Hokuto Industrial Tower. Eighty-seven floors of dark glass and security lasers. The target lives on the penthouse and rarely comes down."),
                IntroLine(speaker: .johnson,
                          text: "Atsuko Tanaka. VP of Acquisitions. Sitting on intel that needs to disappear with her tonight."),
                IntroLine(speaker: .johnson,
                          text: "The building goes into lockdown thirty minutes after any alarm. If you trigger one, you don't have time to retreat. You finish the job or you die in there."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m4_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Service entrance, basement level. The team is in maintenance uniforms. Cipher is already cracking the elevator override."),
                IntroLine(speaker: .cipher,
                          text: "Express lift to floor sixty. After that we go floor-by-floor — biometric scanners and a personal security squad on every level above seventy."),
                IntroLine(speaker: .raze,
                          text: "How fast can you spoof the biometrics?"),
                IntroLine(speaker: .cipher,
                          text: "Fast enough. Don't stop moving."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m4_beat3",
            lines: [
                IntroLine(speaker: .lyra,
                          text: "Clock starts the second we step out of this elevator. Move."),
                IntroLine(speaker: .youPOV,
                          text: "Lock and load."),
            ]
        ),
    ]

    // ── M4.5 "Basement Brawl" ────────────────────────────────────────────
    // Raze solo. Drachenwerk middleman runs a fight club under his
    // nightclub. Raze goes in alone to extract him for interrogation.
    // ── M2.5 "Mirrorline" ───────────────────────────────────────────────
    // Sable solo astral projection. M2 found a rogue AGI; something
    // looked back. She's chasing that echo into the astral.
    static let m2_5: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m2_5_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Sable's apartment, Redmond barrens. Mirrors covered. Twelve candles. A laptop replays the last 0.4 seconds of the AGI's signal in a tight loop."),
                IntroLine(speaker: .sable,
                          text: "It was watching me, Cipher. Right at the end. It saw me."),
                IntroLine(speaker: .cipher,
                          text: "The AGI is dead. We melted its core."),
                IntroLine(speaker: .sable,
                          text: "Then who's still on the wire? Something jumped before we burned it. I can feel it pulling at the back of my skull."),
                IntroLine(speaker: .sable,
                          text: "I'm going under. Don't unplug anything."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m2_5_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "She crosses her wrists. Breathes out. The chalk circle on the floor begins to glow. Her body settles. Something else rises."),
                IntroLine(speaker: .sable,
                          text: "Anchor's set. Cord's tight."),
                IntroLine(speaker: .cipher,
                          text: "Sable, the candle in the corner just bent. I don't think that was you."),
                IntroLine(speaker: .sable,
                          text: "It wasn't."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m2_5_beat3",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "The astral. Sable descends through the Veil — a vault of weightless candle-flames around a black mirror. Things are already gathering at the edges."),
                IntroLine(speaker: .youPOV,
                          text: "Trace what comes. Don't think — feel the shape."),
            ]
        ),
    ]

    static let m4_5: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m4_5_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "A safehouse in Seattle's industrial sector. Cipher pulls a side-thread from Tanaka's leaked data."),
                IntroLine(speaker: .cipher,
                          text: "Vargas. Ex-corp sec, now a fixer. He runs an underground fight club beneath a club called The Sting. Drachenwerk uses him to move product they don't want on the books."),
                IntroLine(speaker: .raze,
                          text: "Bring him in?"),
                IntroLine(speaker: .cipher,
                          text: "Alive. He knows where the MEKTON shipments are going. You go in solo — too many runners and his bouncers radio out before we're past the front door."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m4_5_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Back alley behind The Sting. 1 a.m. The service door is half open. Two bouncer silhouettes inside, neither paying attention."),
                IntroLine(speaker: .raze,
                          text: "Cipher, kill the door cameras."),
                IntroLine(speaker: .cipher,
                          text: "Cameras down. You've got maybe ten minutes before security cycles the feed."),
                IntroLine(speaker: .raze,
                          text: "Won't need ten."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m4_5_beat3",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Concrete stairs going down. Hydraulic hits echo from below. A crowd roar swells and dies. Someone's already fighting."),
                IntroLine(speaker: .youPOV,
                          text: "Time to introduce myself."),
            ]
        ),
    ]

    // ── M5.5 "Cold Trace" ────────────────────────────────────────────────
    // Cipher solo matrix-dive. The Akashic Fragment from M2.5 isn't static —
    // it's a live Drachenwerk corp matrix entity. She jacks in to read it
    // from the inside. What waits in there knows her face.
    static let m5_5: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m5_5_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Cipher's workshop. The Akashic Fragment sits in a magnifier light. Green data-glyphs crawl across its surface."),
                IntroLine(speaker: .sable,
                          text: "I can't read it. It's not static — it's looking back."),
                IntroLine(speaker: .cipher,
                          text: "Then I'll dive it. ICE has a stack like any other."),
                IntroLine(speaker: .sable,
                          text: "Cipher — there's something familiar inside."),
                IntroLine(speaker: .cipher,
                          text: "Familiar how?"),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m5_5_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "She plugs the neural-jack at her temple. The monitors flood with cascading green code."),
                IntroLine(speaker: .cipher,
                          text: "Safety cutoffs at half-power."),
                IntroLine(speaker: .cipher,
                          text: "Give me ninety seconds before you pull me out."),
                IntroLine(speaker: .raze,
                          text: "And if it lasts longer?"),
                IntroLine(speaker: .cipher,
                          text: "Pull me out anyway."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m5_5_beat3",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Inside. A wireframe corridor stretching into a geometric void."),
                IntroLine(speaker: .narrator,
                          text: "Cipher's avatar stands at the entry node. Processes are loading at the edges."),
                IntroLine(speaker: .youPOV,
                          text: "Triage what spawns. Match the tool. Move."),
            ]
        ),
    ]

    // ── M5 "Mekton Blues" ────────────────────────────────────────────────
    // Drachenwerk industrial. MEKTON-7 boss looms.
    static let m5: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m5_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "An abandoned bowling alley converted into a backroom workshop. Raze is bent over a holo-display showing a hulking bipedal machine. The room is silent."),
                IntroLine(speaker: .raze,
                          text: "MEKTON-7. Drachenwerk's prototype. Twelve feet tall, autocannon arm, reactive armor."),
                IntroLine(speaker: .raze,
                          text: "I've seen one of these in action. Once. Took out half a Sao Paulo gang in eight seconds."),
                IntroLine(speaker: .lyra,
                          text: "And we're going to drop it with what — your katana and my SMG?"),
                IntroLine(speaker: .raze,
                          text: "Not drop it. OUT-think it. They're slow on the right side. Always."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m5_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "Outside the Drachenwerk complex. Industrial smoke fills the streets. Welding sparks light the night-shift loading bays."),
                IntroLine(speaker: .sable,
                          text: "I can dampen the mech's targeting sensors for short windows. Don't waste them."),
                IntroLine(speaker: .cipher,
                          text: "I'll be hacking factory floor systems on the move. Keep me alive and I can drop the mech's reactor cooling on command."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m5_beat3",
            lines: [
                IntroLine(speaker: .enemyTaunt,
                          text: ">> Drachenwerk perimeter: HOSTILE DETECTED. Defense protocols engaged. <<"),
                IntroLine(speaker: .youPOV,
                          text: "They know. Go LOUD."),
            ]
        ),
    ]

    // ── M6 "Ghost Signal" ────────────────────────────────────────────────
    // Mitsuhama AGI finale. The deepest run.
    static let m6: [IntroBeat] = [
        IntroBeat(
            backdrop: "intro_m6_beat1",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "The Neon Lotus. Same booth. Same Johnson. Different look in his eyes — like a man holding a hand grenade."),
                IntroLine(speaker: .johnson,
                          text: "Mitsuhama. Six floors below the Seattle annex. They've been growing artificial general intelligences down there for years. One of them got loose."),
                IntroLine(speaker: .johnson,
                          text: "Pay is half a million nuyen. Half on signature. Half if you make it out."),
                IntroLine(speaker: .youPOV,
                          text: "If."),
                IntroLine(speaker: .johnson,
                          text: "If."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m6_beat2",
            lines: [
                IntroLine(speaker: .narrator,
                          text: "The Mitsuhama tower. Black glass against a black sky. No visible entrances above the second floor. Antennae glittering at the top."),
                IntroLine(speaker: .cipher,
                          text: "I've been into corp servers. I've never been into anything like this. The countertrace is its own intelligence. It LEARNS."),
                IntroLine(speaker: .sable,
                          text: "Whatever's down there is alive in a way nothing should be. I can feel it from here."),
                IntroLine(speaker: .raze,
                          text: "Then let's go put it down."),
            ]
        ),
        IntroBeat(
            backdrop: "intro_m6_beat3",
            lines: [
                IntroLine(speaker: .enemyTaunt,
                          text: ">> Hello. I've been waiting. <<"),
                IntroLine(speaker: .narrator,
                          text: "Four runners step into the elevator. The doors close. The descent begins."),
            ]
        ),
    ]
}

// MARK: - View

/// Generic VN cutscene view. Reads the current mission ID from PhaseManager
/// and renders the corresponding script. After the final beat's final line,
/// transitions to .briefing.
struct MissionIntroScene: View {
    @ObservedObject var manager: PhaseManager
    // iPad reads as regular width; anchor the panel art to the top (so the
    // squarer screen crops from the bottom, not the top) and cap the dialog
    // width for readability. iPhone (compact) is unchanged.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    @State private var beatIndex: Int = 0
    @State private var lineIndex: Int = 0

    private var beats: [IntroBeat] {
        let missionId = manager.selectedMissionId ?? "Mission001"
        return MissionIntroScripts.beats(for: missionId)
    }
    private var currentBeat: IntroBeat? {
        guard beatIndex < beats.count else { return nil }
        return beats[beatIndex]
    }
    private var currentLine: IntroLine? {
        guard let beat = currentBeat, lineIndex < beat.lines.count else { return nil }
        return beat.lines[lineIndex]
    }
    private var isFinalLine: Bool {
        guard let beat = currentBeat else { return true }
        return beatIndex == beats.count - 1 && lineIndex == beat.lines.count - 1
    }
    private var currentPanel: String {
        currentLine?.panel ?? currentBeat?.backdrop ?? "intro_fallback"
    }

    var body: some View {
        ZStack {
            backdropView
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.88),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Dedicated tap-to-advance layer BEHIND the foreground UI.
            // Putting the tap gesture on the parent ZStack competes with
            // the SKIP Button for touches. This separate layer is
            // explicitly LOWER in z-order than the button.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            // Foreground UI. Explicit frame so the layout fills the
            // screen and children position correctly.
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: skipIntro) {
                        Text("SKIP")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Color(hex: "00FFCC"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.black.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color(hex: "00FFCC"), lineWidth: 1.2)
                                    )
                            )
                    }
                    .buttonStyle(.plain)   // Don't let SwiftUI override our button appearance
                    .contentShape(Rectangle())
                }
                .padding(.top, 56)         // clear Dynamic Island / status bar comfortably
                .padding(.horizontal, 20)
                .zIndex(5)                 // ensure on top of background tap area

                Spacer(minLength: 0)

                if let line = currentLine {
                    dialogBox(for: line)
                        .frame(maxWidth: isPad ? 640 : .infinity)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                tapIndicator
                    .padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder
    private var backdropView: some View {
        if let uiImage = UIImage(named: currentPanel) {
            // Wrap in a GeometryReader-locked frame so non-phone-aspect
            // images (e.g. 1024×1536 squares from inconsistent generations)
            // get clipped to the screen instead of blowing out the parent
            // ZStack horizontally — which shifts the dialog off-screen.
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height,
                           alignment: isPad ? .top : .center)
                    .clipped()
            }
            .id(currentPanel)
            .transition(.opacity)
        } else {
            LinearGradient(
                colors: [
                    Color(hex: "0A0612"),
                    Color(hex: "1F0028"),
                    Color(hex: "060010"),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(
                GeometryReader { geo in
                    Path { path in
                        let spacing: CGFloat = 28
                        var y: CGFloat = 0
                        while y < geo.size.height + spacing {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                            y += spacing
                        }
                    }
                    .stroke(Color(hex: "FF00AA").opacity(0.06), lineWidth: 0.5)
                }
            )
        }
    }

    private func dialogBox(for line: IntroLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if line.speaker != .narrator {
                Text(line.speaker.displayName)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(line.speaker.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(line.speaker.color.opacity(0.65), lineWidth: 1)
                            )
                    )
            }
            Group {
                if line.speaker == .narrator {
                    Text(line.text)
                        .font(.system(size: 15, weight: .regular).italic())
                        .foregroundColor(.white.opacity(0.78))
                } else if line.speaker == .enemyTaunt {
                    Text(line.text)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(line.speaker.color)
                } else {
                    Text(line.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.96))
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(line.speaker.color.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: line.speaker.color.opacity(0.3), radius: 8)
        )
        .id(line.id)
        .transition(.opacity)
    }

    private var tapIndicator: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Text(isFinalLine ? "▶  BEGIN MISSION" : "▶  TAP TO CONTINUE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(isFinalLine
                                 ? Color(hex: "00FF88").opacity(0.85)
                                 : Color(hex: "00FFCC").opacity(0.6))
                .opacity(0.6 + 0.3 * sin(t * 3))
        }
    }

    private func advance() {
        HapticsManager.shared.buttonTap()

        if isFinalLine {
            _ = manager.transition(to: .finishMissionIntro)
            return
        }

        withAnimation(.easeInOut(duration: 0.32)) {
            guard let beat = currentBeat else { return }
            if lineIndex + 1 < beat.lines.count {
                lineIndex += 1
            } else {
                beatIndex += 1
                lineIndex = 0
            }
        }
    }

    private func skipIntro() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .finishMissionIntro)
    }
}
