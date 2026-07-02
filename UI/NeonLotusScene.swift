import SwiftUI

// MARK: - Prologue Content Model
//
// Pre-M1 "Neon Lotus" VN-style recruit cinematic. 5 beats, ~15-20 dialog lines
// total. Player taps to advance. Each beat sets a backdrop image and one or
// more dialog entries, each with optional portrait + speaker badge.
//
// Adding/editing beats: just modify `PrologueScript.beats` below — view auto-
// adapts. Image assets are looked up by name in Assets.xcassets; missing art
// falls back to a procedural cyberpunk gradient so the scene runs cleanly
// before the BG / portrait images ship.

enum PrologueSpeaker: String {
    case narrator
    case johnson
    case raze
    case sable
    case lyra
    case cipher
    case youPOV       // player POV ("you")

    var displayName: String {
        switch self {
        case .narrator: return ""
        case .johnson:  return "MR. JOHNSON"
        case .raze:     return "RAZE"
        case .sable:    return "SABLE"
        case .lyra:     return "LYRA"
        case .cipher:   return "CIPHER"
        case .youPOV:   return "YOU"
        }
    }

    /// Accent color used for the name badge.
    var color: Color {
        switch self {
        case .narrator: return Color(hex: "00FFCC")
        case .johnson:  return Color(hex: "DDDDDD")
        case .raze:     return Color(hex: "FF6633")
        case .sable:    return Color(hex: "6699FF")
        case .lyra:     return Color(hex: "FFCC00")
        case .cipher:   return Color(hex: "00DDFF")
        case .youPOV:   return Color(hex: "00FF88")
        }
    }

    /// Image asset name for the portrait. Missing assets gracefully degrade
    /// to a colored silhouette placeholder.
    var portraitAsset: String? {
        switch self {
        case .narrator, .youPOV: return nil   // narration / first-person
        case .johnson:           return "portrait_johnson"
        case .raze:              return "portrait_raze"
        case .sable:             return "portrait_sable"
        case .lyra:              return "portrait_lyra"
        case .cipher:            return "portrait_cipher"
        }
    }
}

enum PrologueSide {
    case left, right
}

struct PrologueLine: Identifiable {
    let id: UUID = UUID()
    let speaker: PrologueSpeaker
    let side: PrologueSide   // legacy; no longer used after full-bleed redesign
    let text: String
    /// Optional override — full-bleed panel image for THIS line. When set,
    /// the scene swaps to this image instead of using the beat's `backdrop`.
    /// Used to cut to a character-centered shot the moment they speak (e.g.
    /// the Johnson booth shot when Johnson starts pitching).
    let panel: String?

    init(speaker: PrologueSpeaker, side: PrologueSide, text: String, panel: String? = nil) {
        self.speaker = speaker
        self.side = side
        self.text = text
        self.panel = panel
    }
}

struct PrologueBeat: Identifiable {
    let id: UUID = UUID()
    /// Image asset name for the full-bleed backdrop behind the dialog.
    /// Used as the default panel for all lines in the beat unless a line
    /// overrides via `PrologueLine.panel`.
    let backdrop: String
    /// Ordered dialog lines for this beat. Each tap advances to the next line;
    /// the panel image crossfades when the next line specifies a new panel
    /// (or when the beat changes).
    let lines: [PrologueLine]
}

enum PrologueScript {
    /// The full 5-beat prologue. Order matters — beats play top to bottom.
    static let beats: [PrologueBeat] = [
        // ── BEAT 1 ────────────────────────────────────────────────────────
        // Wide shot of the Neon Lotus exterior. Rain. Neon sign flickering.
        PrologueBeat(
            backdrop: "prologue_lotus_exterior",
            lines: [
                PrologueLine(speaker: .narrator, side: .left,
                             text: "Seattle, 2087. Two hours past midnight."),
                PrologueLine(speaker: .narrator, side: .left,
                             text: "Three weeks since your last job. Rent's due. The coffin-motel doesn't take credit."),
                PrologueLine(speaker: .narrator, side: .left,
                             text: "You got a meet. Mr. Johnson. Booth 7. Don't be late."),
            ]
        ),

        // ── BEAT 2 ────────────────────────────────────────────────────────
        // Inside Neon Lotus. Establishing wide shot (uses interior bg),
        // then cuts to Johnson's full-bleed character panel the moment he
        // speaks.
        PrologueBeat(
            backdrop: "prologue_lotus_interior",
            lines: [
                PrologueLine(speaker: .narrator, side: .left,
                             text: "A man in a charcoal suit waits with a half-empty glass. Eyes like he's already calculating your worth."),
                PrologueLine(speaker: .johnson, side: .right,
                             text: "You came alone. Good. I don't like a crowd.",
                             panel: "portrait_johnson"),
                PrologueLine(speaker: .johnson, side: .right,
                             text: "I have a job. Bio-research lab in the Tarrant Industries tower. Six floors of corp security between you and a server they think no one knows about.",
                             panel: "portrait_johnson"),
                PrologueLine(speaker: .johnson, side: .right,
                             text: "I need that server pulled. Clean. No witnesses, no signal, no name in the police feed in the morning.",
                             panel: "portrait_johnson"),
                PrologueLine(speaker: .johnson, side: .right,
                             text: "Pays seventy-five thousand nuyen. Half on signature. Half on extraction.",
                             panel: "portrait_johnson"),
                PrologueLine(speaker: .johnson, side: .right,
                             text: "But you can't run this alone. You're going to need a team.",
                             panel: "portrait_johnson"),
                PrologueLine(speaker: .youPOV, side: .left,
                             text: "I've got names."),
            ]
        ),

        // ── BEAT 3 ────────────────────────────────────────────────────────
        // Raze arrives — street samurai, comes in cool.
        PrologueBeat(
            backdrop: "prologue_lotus_interior",
            lines: [
                PrologueLine(speaker: .narrator, side: .left,
                             text: "The door slides. A figure in a battered leather jacket drifts to your booth — slow, deliberate, like a man who's never lost a fight he started."),
                PrologueLine(speaker: .raze, side: .left,
                             text: "Heard you needed a blade.",
                             panel: "portrait_raze"),
                PrologueLine(speaker: .raze, side: .left,
                             text: "I'll take half upfront. Whatever's in front of me at the end — I'll cut it down. That's the deal.",
                             panel: "portrait_raze"),
                PrologueLine(speaker: .youPOV, side: .right,
                             text: "Welcome aboard, Raze.",
                             panel: "portrait_raze"),
            ]
        ),

        // ── BEAT 4 ────────────────────────────────────────────────────────
        // Sable arrives — mage, mystical entry.
        PrologueBeat(
            backdrop: "prologue_lotus_interior",
            lines: [
                PrologueLine(speaker: .narrator, side: .left,
                             text: "The temperature drops three degrees. The bar lights flicker. A woman in a hood slides into the booth without a sound."),
                PrologueLine(speaker: .sable, side: .left,
                             text: "I felt the contract in the air an hour ago. Corporate. Bio-research. Lots of locked doors.",
                             panel: "portrait_sable"),
                PrologueLine(speaker: .sable, side: .left,
                             text: "I open doors. I close eyes. My price is the same as Raze's. Don't ask me anything else.",
                             panel: "portrait_sable"),
                PrologueLine(speaker: .youPOV, side: .right,
                             text: "Done. Sit down, Sable.",
                             panel: "portrait_sable"),
            ]
        ),

        // ── BEAT 5 ────────────────────────────────────────────────────────
        // Lyra arrives — kicks the door. Cipher already at the bar.
        PrologueBeat(
            backdrop: "prologue_lotus_interior",
            lines: [
                PrologueLine(speaker: .narrator, side: .left,
                             text: "The door doesn't slide. It bangs. Hard. Heads turn."),
                PrologueLine(speaker: .lyra, side: .left,
                             text: "Sorry I'm late. Job in Tacoma ran long. Anyone shot at yet, or am I early enough to get paid?",
                             panel: "portrait_lyra"),
                PrologueLine(speaker: .narrator, side: .left,
                             text: "From the bar, a fifth pair of eyes lifts from a glowing cyberdeck. Cyan light flickers behind a thin neural-jack port. They walk over without being asked."),
                PrologueLine(speaker: .cipher, side: .right,
                             text: "Tarrant Industries. Six-floor server stack. Quantum-shielded core.",
                             panel: "portrait_cipher"),
                PrologueLine(speaker: .cipher, side: .right,
                             text: "I already know the route. I'm in for a third of the cut and root access to whatever's on that drive.",
                             panel: "portrait_cipher"),
                PrologueLine(speaker: .johnson, side: .right,
                             text: "...A bold opening offer.",
                             panel: "portrait_johnson"),
                PrologueLine(speaker: .youPOV, side: .left,
                             text: "Cipher's right. We move tonight."),
                PrologueLine(speaker: .narrator, side: .left,
                             text: "RUNNERS ASSEMBLED."),
                PrologueLine(speaker: .narrator, side: .left,
                             text: "The Hexwire is live."),
            ]
        ),
    ]
}

// MARK: - Neon Lotus Scene View

/// VN-style prologue view. Full-screen backdrop, optional portrait composited
/// on left or right, dialog box anchored to the bottom. Tap anywhere to
/// advance to the next line; at the end of the script the manager
/// transitions back to the title via `.finishPrologue`.
struct NeonLotusScene: View {
    @ObservedObject var manager: PhaseManager

    @State private var beatIndex: Int = 0
    @State private var lineIndex: Int = 0
    @State private var textRevealProgress: Double = 1.0   // 0..1 (reserved for future typewriter)
    @State private var backdropOpacity: Double = 1.0
    @State private var portraitOpacity: Double = 1.0

    private var beats: [PrologueBeat] { PrologueScript.beats }
    private var currentBeat: PrologueBeat { beats[beatIndex] }
    private var currentLine: PrologueLine { currentBeat.lines[lineIndex] }
    private var isFinalLine: Bool {
        beatIndex == beats.count - 1 && lineIndex == currentBeat.lines.count - 1
    }
    /// Per-line panel override falls back to the beat's default backdrop.
    /// This is how we cut to a character-centered shot the moment they speak.
    private var currentPanel: String {
        currentLine.panel ?? currentBeat.backdrop
    }

    var body: some View {
        ZStack {
            // ── Backdrop ─────────────────────────────────────────────
            backdropView
                .ignoresSafeArea()
                .opacity(backdropOpacity)

            // ── Vignette (focuses attention on dialog) ───────────────
            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Dedicated tap-to-advance layer behind foreground UI so the
            // SKIP Button isn't competing with the .onTapGesture below.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            // (Small overlay portraits removed — panels are full-bleed now,
            //  so the character IS the backdrop when they speak.)

            // ── Dialog Box + Skip Button ─────────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Button(action: skipPrologue) {
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
                    .padding(.top, 56)        // clear Dynamic Island
                    .padding(.trailing, 20)
                }
                .zIndex(5)
                Spacer()
                dialogBox
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Tap-to-advance indicator ─────────────────────────────
            VStack {
                Spacer()
                tapIndicator
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var backdropView: some View {
        if let uiImage = UIImage(named: currentPanel) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .id(currentPanel)               // forces transition on panel swap
                .transition(.opacity)
        } else {
            // Procedural fallback — atmospheric cyberpunk gradient.
            // Lets the scene run before BG art ships.
            LinearGradient(
                colors: [
                    Color(hex: "100020"),
                    Color(hex: "1A0030"),
                    Color(hex: "060010"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                // Faint hex grid overlay for cyberpunk flavor
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

    // (Small-portrait overlay views removed in the full-bleed redesign —
    //  see the `panel:` field on PrologueLine for the current approach.)

    private var dialogBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Speaker name badge (omitted for pure narration)
            if currentLine.speaker != .narrator {
                Text(currentLine.speaker.displayName)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(currentLine.speaker.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(currentLine.speaker.color.opacity(0.65), lineWidth: 1)
                            )
                    )
            }
            // Dialog body — narration is italicized + dimmer, speakers are
            // bolder + brighter.
            Group {
                if currentLine.speaker == .narrator {
                    Text(currentLine.text)
                        .font(.system(size: 15, weight: .regular).italic())
                        .foregroundColor(.white.opacity(0.78))
                } else {
                    Text(currentLine.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.96))
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(currentLine.speaker.color.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: currentLine.speaker.color.opacity(0.3), radius: 8)
        )
        .id(currentLine.id)   // forces transition on line change
        .transition(.opacity)
    }

    private var tapIndicator: some View {
        // TimelineView so the gentle pulse actually animates at 30fps,
        // signaling to the player that the screen IS interactive.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Text(isFinalLine ? "TAP TO RETURN" : "▶  TAP TO CONTINUE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(Color(hex: "00FFCC").opacity(0.6))
                .opacity(0.6 + 0.3 * sin(t * 3))
        }
    }

    // MARK: - Navigation

    private func advance() {
        HapticsManager.shared.buttonTap()

        if isFinalLine {
            _ = manager.transition(to: .finishPrologue)
            return
        }

        // Advance line within current beat, or move to next beat if exhausted.
        // The backdropView uses `.id(currentPanel)` + `.transition(.opacity)`
        // so it auto-crossfades whenever the panel image string changes
        // (either via a per-line `panel` override OR a new beat).
        withAnimation(.easeInOut(duration: 0.32)) {
            if lineIndex + 1 < currentBeat.lines.count {
                lineIndex += 1
            } else {
                beatIndex += 1
                lineIndex = 0
            }
        }
    }

    private func skipPrologue() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .finishPrologue)
    }
}
