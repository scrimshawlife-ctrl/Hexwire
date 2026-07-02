import SwiftUI

// MARK: - M3.5 "The Drop" — Pre-Chase Cutscene
//
// VN-style intro that plays between "tap MISSION 3.5 on mission select" and
// "the chase gameplay starts". 3 beats, ~10 dialog lines total. Same scene
// infrastructure as NeonLotusScene (prologue), tuned for the post-M3
// rooftop-exit narrative beat.
//
// The script + visual model intentionally mirror PrologueScript so that
// later we can extract a shared MissionIntroScene type for the per-mission
// cutscenes the player asked for.

private enum DropSpeaker: String {
    case narrator
    case raze
    case sable
    case lyra
    case cipher
    case youPOV

    var displayName: String {
        switch self {
        case .narrator: return ""
        case .raze:     return "RAZE"
        case .sable:    return "SABLE"
        case .lyra:     return "LYRA"
        case .cipher:   return "CIPHER"
        case .youPOV:   return "YOU"
        }
    }

    var color: Color {
        switch self {
        case .narrator: return Color(hex: "00FFCC")
        case .raze:     return Color(hex: "FF6633")
        case .sable:    return Color(hex: "6699FF")
        case .lyra:     return Color(hex: "FFCC00")
        case .cipher:   return Color(hex: "00DDFF")
        case .youPOV:   return Color(hex: "00FF88")
        }
    }

    /// Reuse the prologue portrait assets — same cast, same wardrobe.
    var portraitAsset: String? {
        switch self {
        case .narrator, .youPOV: return nil
        case .raze:              return "portrait_raze"
        case .sable:             return "portrait_sable"
        case .lyra:              return "portrait_lyra"
        case .cipher:            return "portrait_cipher"
        }
    }
}

private struct DropLine: Identifiable {
    let id: UUID = UUID()
    let speaker: DropSpeaker
    let text: String
    /// Per-line panel override (matches PrologueLine.panel). When set, swaps
    /// the backdrop to focus on a character at the moment they speak.
    let panel: String?

    init(speaker: DropSpeaker, text: String, panel: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.panel = panel
    }
}

private struct DropBeat: Identifiable {
    let id: UUID = UUID()
    let backdrop: String
    let lines: [DropLine]
}

private enum DropScript {
    /// 2026-05-12 design decision: M3.5 is an action cutscene — no
    /// per-line portrait swaps. Each beat holds on its wide-shot backdrop
    /// (rooftop / alley / bike) for the full duration. Speaker name badges
    /// over the wide shot identify who's talking. Feels more graphic-
    /// novel cinematic than VN cuts during an urgent escape moment.
    /// (If we change our mind later, add `panel:` overrides to any line.)
    static let beats: [DropBeat] = [
        // ── BEAT 1 ────────────────────────────────────────────────────────
        // Rooftop scramble — runners climb out of the M3 ritual chamber.
        DropBeat(
            backdrop: "drop_intro_rooftop",
            lines: [
                DropLine(speaker: .narrator,
                         text: "Seattle. 03:14. Rain hammers the access ladder above the ritual chamber."),
                DropLine(speaker: .narrator,
                         text: "Whatever you pulled out of that room — the corp wants it back. Loud."),
                DropLine(speaker: .lyra,
                         text: "Move move MOVE — I'm picking up corp comm chatter on three frequencies."),
            ]
        ),

        // ── BEAT 2 ────────────────────────────────────────────────────────
        // Alley below — bike is stashed, last-second prep.
        DropBeat(
            backdrop: "drop_intro_alley",
            lines: [
                DropLine(speaker: .narrator,
                         text: "The alley. The bike — chrome and matte black, magenta underglow humming — waits behind a dumpster."),
                DropLine(speaker: .cipher,
                         text: "They tagged the drive at extraction. RFID. I can't kill the ping — it's hardware-fused."),
                DropLine(speaker: .cipher,
                         text: "We've got maybe two minutes before they pin our position."),
                DropLine(speaker: .sable,
                         text: "Then we run. The safehouse is east. I'll mask the trace as long as I can."),
            ]
        ),

        // ── BEAT 3 ────────────────────────────────────────────────────────
        // Mount up — last words before throttle.
        DropBeat(
            backdrop: "drop_intro_bike",
            lines: [
                DropLine(speaker: .narrator,
                         text: "Raze swings onto the bike. Lyra mounts behind him, SMG already up."),
                DropLine(speaker: .raze,
                         text: "Sable, Cipher — back roads. Don't be heroes. Just be invisible."),
                DropLine(speaker: .lyra,
                         text: "We'll see you at the safehouse. Or we won't."),
                DropLine(speaker: .youPOV,
                         text: "Hit the throttle."),
                DropLine(speaker: .narrator,
                         text: "The engine screams. The bike vanishes into the rain."),
            ]
        ),
    ]
}

// MARK: - View

struct DropIntroScene: View {
    @ObservedObject var manager: PhaseManager

    @State private var beatIndex: Int = 0
    @State private var lineIndex: Int = 0

    private var beats: [DropBeat] { DropScript.beats }
    private var currentBeat: DropBeat { beats[beatIndex] }
    private var currentLine: DropLine { currentBeat.lines[lineIndex] }
    private var isFinalLine: Bool {
        beatIndex == beats.count - 1 && lineIndex == currentBeat.lines.count - 1
    }
    private var currentPanel: String {
        currentLine.panel ?? currentBeat.backdrop
    }

    var body: some View {
        ZStack {
            backdropView
                .ignoresSafeArea()

            // Vignette gradient — anchors attention on the dialog box.
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

            // Dedicated tap-to-advance layer behind foreground UI so the
            // SKIP Button gets tap priority.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            // SKIP button top-right + dialog box bottom
            VStack {
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
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                }
                .zIndex(5)
                Spacer()
                dialogBox
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                tapIndicator
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdropView: some View {
        if let uiImage = UIImage(named: currentPanel) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .id(currentPanel)
                .transition(.opacity)
        } else {
            // Fallback gradient. Different palette per beat so the placeholder
            // still has SOME visual differentiation before art ships.
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

    // MARK: - Dialog Box

    private var dialogBox: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .id(currentLine.id)
        .transition(.opacity)
    }

    private var tapIndicator: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Text(isFinalLine ? "▶  HIT THE THROTTLE" : "▶  TAP TO CONTINUE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(isFinalLine
                                 ? Color(hex: "FF00AA").opacity(0.85)
                                 : Color(hex: "00FFCC").opacity(0.6))
                .opacity(0.6 + 0.3 * sin(t * 3))
        }
    }

    // MARK: - Navigation

    private func advance() {
        HapticsManager.shared.buttonTap()

        if isFinalLine {
            // Auto-into the chase gameplay — no return to mission select.
            _ = manager.transition(to: .finishDropIntro)
            return
        }

        withAnimation(.easeInOut(duration: 0.32)) {
            if lineIndex + 1 < currentBeat.lines.count {
                lineIndex += 1
            } else {
                beatIndex += 1
                lineIndex = 0
            }
        }
    }

    private func skipIntro() {
        HapticsManager.shared.buttonTap()
        _ = manager.transition(to: .finishDropIntro)
    }
}
