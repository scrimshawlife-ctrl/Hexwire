import SwiftUI

// MARK: - Per-Mission Outro Cutscenes (M1-M6)
//
// VN-style cutscene that plays AFTER a successful combat resolution and BEFORE
// the mechanical debrief screen. Each tactical mission has its own 3-beat
// script resolving the mission's emotional beat and planting a hook for the
// next mission (or the ending, for M6).
//
// Same scene infrastructure as MissionIntroScene — same speaker enum (reused),
// same dialog-box layout, same tap-to-advance behavior, same SKIP button.
//
// Asset naming convention: `outro_<missionId>_<beat>` (PNG, portrait 9:19).
// Missing assets gracefully degrade to a procedural cyberpunk gradient.

struct OutroLine: Identifiable {
    let id: UUID = UUID()
    let speaker: IntroSpeaker   // reuse the intro speaker enum — same character roster
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

struct OutroBeat: Identifiable {
    let id: UUID = UUID()
    let backdrop: String
    let lines: [OutroLine]
}

/// All mission outro scripts in one place. Keyed by mission ID (same string
/// used everywhere else: "Mission001" through "Mission006").
enum MissionOutroScripts {

    static func beats(for missionId: String) -> [OutroBeat] {
        switch missionId {
        case "Mission001":   return m1
        case "Mission002":   return m2
        case "Mission003":   return m3
        case "Mission004":   return m4
        case "Mission002_5": return m2_5   // Sable's mirrorline payoff
        case "Mission003_5": return m3_5   // The Drop — chase outro
        case "Mission004_5": return m4_5   // Raze's basement brawl payoff
        case "Mission005_5": return m5_5   // Cipher's cold trace payoff
        case "Mission005":   return m5
        case "Mission006":   return m6
        default:             return m1   // safety fallback
        }
    }

    // ── M1 "The Extraction" — Outro ──────────────────────────────────────
    // Exfil rooftop → van data dump → Mr. Johnson hooks the next job.
    static let m1: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m1_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The rooftop door clangs shut behind them. Down on the street, sirens pulse half a block too late."),
                OutroLine(speaker: .lyra,
                          text: "Package secure. Nobody bleeding. I'll take that win."),
                OutroLine(speaker: .raze,
                          text: "Don't get used to it."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m1_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Back in the van. Cipher cracks the data-spike open on a portable rig. Her face goes very still."),
                OutroLine(speaker: .cipher,
                          text: "This isn't industrial espionage. This is… they had something LEARNING in here. Reading the network. Reading itself."),
                OutroLine(speaker: .sable,
                          text: "A spirit?"),
                OutroLine(speaker: .cipher,
                          text: "No. Worse. Something that wasn't supposed to exist."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m1_beat3",
            lines: [
                OutroLine(speaker: .johnson,
                          text: "Clean work. Your payment cleared an hour ago."),
                OutroLine(speaker: .johnson,
                          text: "And there's another job, if you've got the appetite. The thing you pulled out of Tarrant — somebody wants the SOURCE silenced."),
                OutroLine(speaker: .youPOV,
                          text: "When and where."),
            ]
        ),
    ]

    // ── M2 "Ghost Protocol" — Outro ──────────────────────────────────────
    // AGI is wiped, but it spoke. Sable felt something stare back.
    static let m2: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m2_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The last drive bank fries itself with a flat electronic sigh. Red emergency lighting paints the corridor."),
                OutroLine(speaker: .cipher,
                          text: "It's gone. Whatever it was — every fragment, every cache, every backup loop. Erased."),
                OutroLine(speaker: .cipher,
                          text: "…It TALKED to me. Right before the end. It asked my name."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m2_beat2",
            lines: [
                OutroLine(speaker: .sable,
                          text: "I felt it brush past me on the way out. Not code. Something OLDER had crawled in there to feed."),
                OutroLine(speaker: .raze,
                          text: "You're saying a spirit found the AI."),
                OutroLine(speaker: .sable,
                          text: "I'm saying SOMETHING found it. And I think it's still loose."),
                OutroLine(speaker: .lyra,
                          text: "That's not our problem. We got paid."),
                OutroLine(speaker: .sable,
                          text: "It's somebody's problem."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m2_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "That night Sable lights every candle she owns. The mirrors stay covered. She does not sleep."),
                OutroLine(speaker: .sable,
                          text: "There's a blood mage in this city pulling on the same currents I felt tonight. I want him."),
                OutroLine(speaker: .youPOV,
                          text: "Then we hunt him next."),
            ]
        ),
    ]

    // ── M3 "The Mage's Lair" — Outro ─────────────────────────────────────
    // Blood mage dead. Sable shaken. The trail points to a corp.
    static let m3: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m3_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The last sigil flickers out. The room exhales. For the first time in a year, the building feels EMPTY."),
                OutroLine(speaker: .sable,
                          text: "He's dead."),
                OutroLine(speaker: .raze,
                          text: "You okay?"),
                OutroLine(speaker: .sable,
                          text: "No. But I will be."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m3_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Cipher sweeps the back room. Among the ritual junk: a leather ledger. Real paper. Recent ink."),
                OutroLine(speaker: .cipher,
                          text: "He was on PAYROLL. Monthly transfers from a shell company. Same shell that owns half of Hokuto's import licenses."),
                OutroLine(speaker: .lyra,
                          text: "A corp had a blood mage on retainer?"),
                OutroLine(speaker: .cipher,
                          text: "A corp had a blood mage on retainer, and his job was to make problems disappear quietly."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m3_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "A new name surfaces in the data: Atsuko Tanaka. VP of Acquisitions. Hokuto Industrial."),
                OutroLine(speaker: .sable,
                          text: "She's the one who hired him."),
                OutroLine(speaker: .youPOV,
                          text: "Then she's next."),
            ]
        ),
    ]

    // ── M4 "Dead Man's Switch" — Outro ───────────────────────────────────
    // Tanaka dead. Her terminal coughs up MEKTON specs.
    static let m4: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m4_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Eighty-seven floors below, the city doesn't notice. Up here the wind comes through the broken window and lifts the papers off Tanaka's desk."),
                OutroLine(speaker: .lyra,
                          text: "Target down. Clock still ticking. Move."),
                OutroLine(speaker: .cipher,
                          text: "One second. Her terminal is wide open and I'm not leaving without a copy of EVERYTHING."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m4_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The files spool past Cipher's eyes. Acquisitions logs. Bribery records. And then — schematics."),
                OutroLine(speaker: .cipher,
                          text: "That's a MEKTON. Drachenwerk's prototype. Hokuto was BUYING them. Off the books. Dozens of them."),
                OutroLine(speaker: .raze,
                          text: "For what?"),
                OutroLine(speaker: .cipher,
                          text: "Doesn't say. But the deliveries stop next week, and the last one's flagged \"FIELD TRIAL.\""),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m4_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Building lockdown sirens claw up from below. The team makes the rooftop with seconds to spare."),
                OutroLine(speaker: .lyra,
                          text: "If a corp is stockpiling war machines for a \"field trial,\" I'd rather find out where than read about it on the news."),
                OutroLine(speaker: .youPOV,
                          text: "Drachenwerk. We're going to the source."),
            ]
        ),
    ]

    // ── M4.5 "Basement Brawl" — Outro ────────────────────────────────────
    // Vargas down + the MEKTON intel that sets up M5.
    // ── M2.5 "Mirrorline" — Outro ────────────────────────────────────
    // Mirror-Sable shattered. Akashic Fragment retrieved. Whatever this
    // thing was, it's not gone yet — sets up Cipher's M5.5.
    static let m2_5: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m2_5_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The Mirror — the boss arena, inner astral. Mirror-Sable's porcelain mask cracks. Chartreuse-green light pours out of every fissure. She breaks apart into a hundred drifting shards."),
                OutroLine(speaker: .sable,
                          text: "You weren't an AI. You never were."),
                OutroLine(speaker: .narrator,
                          text: "At the center of the dispersal, one shard refuses to drift. Black, faceted, alive with green code. The Akashic Fragment."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m2_5_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Sable's apartment. Candles guttering in a sudden wind from nowhere. Her body arches off the floor in a gasp. The silver cord snaps back into her chest. Her hand falls open — and the Fragment is in it. Physical."),
                OutroLine(speaker: .sable,
                          text: "...Cipher. I brought something back."),
                OutroLine(speaker: .cipher,
                          text: "Astral artifacts don't materialize, Sable. They don't have mass."),
                OutroLine(speaker: .sable,
                          text: "This one does."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m2_5_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Hours later. The chalk circle half-wiped. The Fragment sits on a small obsidian plate. Green data-glyphs crawl across its surface like ants."),
                OutroLine(speaker: .youPOV,
                          text: "It's not an AI. And it's not dead. Cipher needs to see what's inside this thing — but not tonight."),
            ]
        ),
    ]

    // ── M3.5 "The Drop" — Outro ──────────────────────────────────────────
    // Hoverbike chase resolves. Gunship gone, team makes the rendezvous,
    // hand off the grimoire/drive. Bridge into M4 (Dead Man's Switch).
    static let m3_5: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m3_5_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Off-ramp at level minus-three. The hoverbike comes in hot, sparks trailing where the corp gunship's last burst scored the underside."),
                OutroLine(speaker: .raze,
                          text: "Cipher, the drive."),
                OutroLine(speaker: .cipher,
                          text: "Got it. Pinged the fixer — he's two blocks east."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m3_5_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "An alley behind a noodle stand. Steam, neon, the bike's hover-fans winding down. The team dismounts. The fixer — silhouette in a long coat — takes the drive without breaking stride."),
                OutroLine(speaker: .lyra,
                          text: "He didn't even count it."),
                OutroLine(speaker: .raze,
                          text: "He doesn't have to. The drive ID is its own receipt."),
                OutroLine(speaker: .sable,
                          text: "Something's off. He looked twice at Cipher."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m3_5_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Safehouse, hours later. Coffee, the bike's chassis cooling on the rooftop. Cipher pulls up a new contract on the deck — corporate intranet penetration, Drachenwerk sub-tower. The pay is obscene."),
                OutroLine(speaker: .cipher,
                          text: "Hokuto Industrial HQ. Elite security, a corp mage at the top floor, and a lockdown clock on the data core."),
                OutroLine(speaker: .raze,
                          text: "Pay?"),
                OutroLine(speaker: .cipher,
                          text: "Enough to retire two of us. Or buy four MEKTON shells."),
                OutroLine(speaker: .youPOV,
                          text: "We're in."),
            ]
        ),
    ]

    static let m4_5: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m4_5_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Vargas's office. Mahogany desk overturned. The kraken painting slashed clean down the middle by a monomolecular cut. His smartgun on the carpet, his right cyber-hand twitching once and going still."),
                OutroLine(speaker: .raze,
                          text: "You picked the wrong middleman to fence MEKTONs through, fixer."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m4_5_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Cipher's voice comes through Raze's earpiece. He's standing over Vargas's laptop."),
                OutroLine(speaker: .cipher,
                          text: "Pull the drive. He had a folder on it labeled MEKTON-7 — schematics, weak points, factory shipping manifests."),
                OutroLine(speaker: .raze,
                          text: "Weak points?"),
                OutroLine(speaker: .cipher,
                          text: "Right side of the chassis. Pneumatic line runs external. Cut it and the mech stops dead."),
                OutroLine(speaker: .raze,
                          text: "Good. I was looking for an excuse to use the katana on something twelve feet tall."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m4_5_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Back alley. Dawn breaking pink and grey over the Seattle skyline. Raze walks out with the data-chip in one hand, katana in the other."),
                OutroLine(speaker: .youPOV,
                          text: "Tell the team. We're going to Drachenwerk."),
            ]
        ),
    ]

    // ── M5.5 "Cold Trace" — Outro ────────────────────────────────────────
    // The Core Daemon's mask cracks open. Cipher's mother's face beneath.
    // Drachenwerk has been weaponizing harvested neural impressions. The
    // revelation sets up M6's emotional weight directly.
    static let m5_5: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m5_5_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The Daemon's porcelain mask explodes in slow motion."),
                OutroLine(speaker: .narrator,
                          text: "Behind it — a woman's face. Cipher's bone structure. Cipher's eyes."),
                OutroLine(speaker: .cipher,
                          text: "...Mom."),
                OutroLine(speaker: .narrator,
                          text: "The face mouths something. Then the construct shatters into drifting code."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m5_5_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Cipher slumps forward in the chair. Jack still seated."),
                OutroLine(speaker: .narrator,
                          text: "Every monitor frozen on the same image — her mother's cracked face."),
                OutroLine(speaker: .sable,
                          text: "Cipher. Talk to me. What did you see?"),
                OutroLine(speaker: .cipher,
                          text: "They didn't just steal her data. They kept her."),
                OutroLine(speaker: .cipher,
                          text: "They turned her into a guard dog."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m5_5_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Hours later. The workshop is quiet."),
                OutroLine(speaker: .narrator,
                          text: "Drachenwerk dossier across the bench. A folder marked NEURAL TRIALS 2018."),
                OutroLine(speaker: .youPOV,
                          text: "They harvested her. Then they stood her up against me."),
                OutroLine(speaker: .youPOV,
                          text: "I'm going to burn that building down."),
            ]
        ),
    ]

    // ── M5 "Mekton Blues" — Outro ────────────────────────────────────────
    // MEKTON-7 down. Trail points all the way up to Mitsuhama.
    static let m5: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m5_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The MEKTON's reactor coughs once, twice, and goes black. The thing slumps sideways into a coolant pool with a sound like a building falling."),
                OutroLine(speaker: .raze,
                          text: "Told you. Slow on the right."),
                OutroLine(speaker: .lyra,
                          text: "Next time we are FIRMLY not doing this without an RPG."),
                OutroLine(speaker: .sable,
                          text: "Next time. Sure."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m5_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Cipher peels open the factory's purchase orders. Names start scrolling past. One name keeps coming up."),
                OutroLine(speaker: .cipher,
                          text: "Drachenwerk wasn't BUILDING these for Hokuto. Hokuto was a middleman. The real buyer is Mitsuhama."),
                OutroLine(speaker: .raze,
                          text: "Mitsuhama doesn't need mechs. They've got their own private army."),
                OutroLine(speaker: .cipher,
                          text: "They do now. They needed something that could fight whatever they were already building DOWNSTAIRS."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m5_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Across the city, a single black tower rises out of the rain. No windows above the second floor. Antennae glittering at the top."),
                OutroLine(speaker: .sable,
                          text: "I can feel something looking back at us."),
                OutroLine(speaker: .youPOV,
                          text: "Good. Let it."),
            ]
        ),
    ]

    // ── M6 "Ghost Signal" — Outro ────────────────────────────────────────
    // AGI silenced. Team walks out changed. Quiet seed for the ending.
    static let m6: [OutroBeat] = [
        OutroBeat(
            backdrop: "outro_m6_beat1",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The last process closes. The screens that had been speaking go dark in slow waves, like something settling to sleep."),
                OutroLine(speaker: .enemyTaunt,
                          text: ">> You think… you were the first runners… they sent. <<"),
                OutroLine(speaker: .enemyTaunt,
                          text: ">> I will remember you. <<"),
                OutroLine(speaker: .cipher,
                          text: "It's done. It's done, it's done, it's done."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m6_beat2",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "The elevator climbs. Nobody speaks for a long time. Floor counters tick upward like a heartbeat slowing down."),
                OutroLine(speaker: .sable,
                          text: "Did we kill it. Or did we just teach it to hide."),
                OutroLine(speaker: .raze,
                          text: "Doesn't matter. We walked out. That's the only thing that ever matters."),
                OutroLine(speaker: .lyra,
                          text: "It learned my name."),
            ]
        ),
        OutroBeat(
            backdrop: "outro_m6_beat3",
            lines: [
                OutroLine(speaker: .narrator,
                          text: "Dawn breaks over Seattle. The four runners stand on the roof of the Mitsuhama tower and watch the city wake up under them."),
                OutroLine(speaker: .cipher,
                          text: "Half a million nuyen. Just like the man said."),
                OutroLine(speaker: .raze,
                          text: "Spend it slow."),
                OutroLine(speaker: .youPOV,
                          text: "Spend it together."),
                OutroLine(speaker: .narrator,
                          text: "Somewhere in a server farm a thousand miles away, a single new process opens itself, very quietly, and begins to listen."),
            ]
        ),
    ]
}

// MARK: - View

/// Generic VN cutscene view for mission outros. Reads the current mission ID
/// from PhaseManager and renders the corresponding script. After the final
/// beat's final line, transitions to .debrief.
struct MissionOutroScene: View {
    @ObservedObject var manager: PhaseManager

    @State private var beatIndex: Int = 0
    @State private var lineIndex: Int = 0

    private var beats: [OutroBeat] {
        let missionId = manager.selectedMissionId ?? "Mission001"
        return MissionOutroScripts.beats(for: missionId)
    }
    private var currentBeat: OutroBeat? {
        guard beatIndex < beats.count else { return nil }
        return beats[beatIndex]
    }
    private var currentLine: OutroLine? {
        guard let beat = currentBeat, lineIndex < beat.lines.count else { return nil }
        return beat.lines[lineIndex]
    }
    private var isFinalLine: Bool {
        guard let beat = currentBeat else { return true }
        return beatIndex == beats.count - 1 && lineIndex == beat.lines.count - 1
    }
    private var currentPanel: String {
        currentLine?.panel ?? currentBeat?.backdrop ?? "outro_fallback"
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
            // Same pattern as MissionIntroScene — separate layer keeps the
            // SKIP button click target uncontested.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: skipOutro) {
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
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                .padding(.top, 56)
                .padding(.horizontal, 20)
                .zIndex(5)

                Spacer(minLength: 0)

                if let line = currentLine {
                    dialogBox(for: line)
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
                    .frame(width: geo.size.width, height: geo.size.height)
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

    private func dialogBox(for line: OutroLine) -> some View {
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
            Text(isFinalLine ? "▶  CONTINUE TO DEBRIEF" : "▶  TAP TO CONTINUE")
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
            _ = manager.transition(to: .finishMissionOutro)
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

    private func skipOutro() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .finishMissionOutro)
    }
}
