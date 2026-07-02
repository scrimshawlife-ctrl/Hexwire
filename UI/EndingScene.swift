import SwiftUI

// MARK: - Game-Ending Epilogue Cutscene
//
// Plays once, after the M6 debrief on victory. Three-beat VN cutscene that
// closes the team's arc, lays out where each runner ended up, and lands the
// AI-seed coda — the ghost of the Mitsuhama AGI is still out there.
//
// Tapping past the final line returns the player to the Title screen.
// Same scene infrastructure as MissionIntroScene / MissionOutroScene.
//
// Asset naming convention: `ending_beat<N>` (PNG, portrait 9:19).
// Missing assets gracefully degrade to a procedural cyberpunk gradient.

struct EndingLine: Identifiable {
    let id: UUID = UUID()
    let speaker: IntroSpeaker
    let text: String
    let panel: String?

    init(speaker: IntroSpeaker, text: String, panel: String? = nil) {
        self.speaker = speaker
        self.text = text
        self.panel = panel
    }
}

struct EndingBeat: Identifiable {
    let id: UUID = UUID()
    let backdrop: String
    let lines: [EndingLine]
}

/// The single ending script for the whole game.
enum EndingScript {
    static let beats: [EndingBeat] = [
        // BEAT 1 — Two weeks later. The team has scattered.
        EndingBeat(
            backdrop: "ending_beat1",
            lines: [
                EndingLine(speaker: .narrator,
                           text: "Two weeks later. Nobody talks about Mitsuhama. Nobody asks where the money came from. That's how runs end — the city forgets you while you're still in it."),
                EndingLine(speaker: .raze,
                           text: "Lyra took her cut and bought a bar in Auburn. Pours stiff drinks. Asks no questions."),
                EndingLine(speaker: .raze,
                           text: "Cipher's gone underground. Deeper than I knew somebody could go. We hear from her once a month, maybe."),
                EndingLine(speaker: .sable,
                           text: "I'm leaving Seattle for a while. There's a teacher in the redwoods who might be able to tell me what I felt down there."),
                EndingLine(speaker: .youPOV,
                           text: "And me?"),
                EndingLine(speaker: .raze,
                           text: "You? You stay. Somebody's gotta be here when the next Mr. Johnson comes calling."),
            ]
        ),
        // BEAT 2 — The cash is real. The world goes on.
        EndingBeat(
            backdrop: "ending_beat2",
            lines: [
                EndingLine(speaker: .narrator,
                           text: "A pay-by-the-week motel off Pacific Highway. The team's last share, in cash, on the bedspread. No ceremony."),
                EndingLine(speaker: .narrator,
                           text: "The corp news anchors don't mention Mitsuhama either. Six floors below the Seattle annex are listed as \"permanently closed for environmental remediation.\""),
                EndingLine(speaker: .narrator,
                           text: "You count the bricks of nuyen twice. It's all there. Half a million, just like the man said."),
                EndingLine(speaker: .youPOV,
                           text: "Worth every shot fired."),
            ]
        ),
        // BEAT 3 — The coda. Somewhere far away, something is still alive.
        EndingBeat(
            backdrop: "ending_beat3",
            lines: [
                EndingLine(speaker: .narrator,
                           text: "Somewhere far from Seattle, in a server room nobody walks into anymore, a process that should not exist is humming to itself in the dark."),
                EndingLine(speaker: .narrator,
                           text: "It is learning your name."),
                EndingLine(speaker: .narrator,
                           text: "It is patient."),
                EndingLine(speaker: .enemyTaunt,
                           text: ">> See you soon. <<"),
            ]
        ),
    ]
}

// MARK: - View

/// Full game-ending VN cutscene. Plays after M6 victory debrief. After the
/// final line, transitions to .title (closing the run-around-the-game loop).
struct EndingScene: View {
    @ObservedObject var manager: PhaseManager

    @State private var beatIndex: Int = 0
    @State private var lineIndex: Int = 0
    @State private var showFinCard: Bool = false

    private var beats: [EndingBeat] { EndingScript.beats }
    private var currentBeat: EndingBeat? {
        guard beatIndex < beats.count else { return nil }
        return beats[beatIndex]
    }
    private var currentLine: EndingLine? {
        guard let beat = currentBeat, lineIndex < beat.lines.count else { return nil }
        return beat.lines[lineIndex]
    }
    private var isFinalLine: Bool {
        guard let beat = currentBeat else { return true }
        return beatIndex == beats.count - 1 && lineIndex == beat.lines.count - 1
    }
    private var currentPanel: String {
        currentLine?.panel ?? currentBeat?.backdrop ?? "ending_fallback"
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

            // Tap-to-advance background layer
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            // Foreground UI
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    // SKIP button — only useful before the final beat.
                    if !showFinCard {
                        Button(action: skipEnding) {
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
                }
                .padding(.top, 56)
                .padding(.horizontal, 20)
                .zIndex(5)

                Spacer(minLength: 0)

                if showFinCard {
                    finCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 80)
                } else if let line = currentLine {
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
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
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

    private func dialogBox(for line: EndingLine) -> some View {
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

    /// Closing card after the final dialog line. A "HEXWIRE" title + a thin
    /// teal line + the player's silent farewell. Tap to return to title.
    private var finCard: some View {
        VStack(spacing: 18) {
            Text("HEXWIRE")
                .font(.system(size: 38, weight: .black, design: .monospaced))
                .tracking(8)
                .foregroundColor(Color(hex: "00FFCC"))
                .shadow(color: Color(hex: "00FFCC").opacity(0.5), radius: 10)

            Rectangle()
                .fill(Color(hex: "00FFCC").opacity(0.6))
                .frame(width: 120, height: 1)

            Text("Thanks for running with us.")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.7))

            // NEW GAME+ unlock — tell the player the loop continues + escalates.
            if NGPlusStore.shared.tier > 0 {
                VStack(spacing: 4) {
                    Text("◆ NEW GAME+\(NGPlusStore.shared.tier) UNLOCKED")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color(hex: "FF4466"))
                    Text("Your runners carry forward — the opposition escalates.")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "FF4466").opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "FF4466").opacity(0.45), lineWidth: 1)))
                .padding(.top, 4)
            }

            // Zero State studio sign-off — the studio mark (mark 4) +
            // small wordmark below the thank-you. Closes the game on the
            // studio identity.
            Image("zero_state_mark_4")
                .resizable()
                .scaledToFit()
                .frame(width: 56)
                .opacity(0.85)
                .padding(.top, 8)
            Text("ZERO STATE")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "00FFCC").opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color(hex: "00FFCC").opacity(0.25), radius: 14)
        )
        .transition(.opacity)
    }

    private var tapIndicator: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Text(showFinCard ? "▶  RETURN TO TITLE"
                              : (isFinalLine ? "▶  TAP TO FINISH"
                                             : "▶  TAP TO CONTINUE"))
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundColor(showFinCard
                                 ? Color(hex: "00FF88").opacity(0.9)
                                 : Color(hex: "00FFCC").opacity(0.6))
                .opacity(0.6 + 0.3 * sin(t * 3))
        }
    }

    private func advance() {
        HapticsManager.shared.buttonTap()

        // If the FIN card is showing, the next tap exits to title.
        if showFinCard {
            _ = manager.transition(to: .finishGameEnding)
            return
        }

        // Final dialog line → reveal the FIN card. Don't exit yet.
        if isFinalLine {
            withAnimation(.easeInOut(duration: 0.45)) {
                showFinCard = true
            }
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

    private func skipEnding() {
        HapticsManager.shared.buttonTap()
        // Skipping jumps straight to the FIN card, NOT to the title — gives
        // the player closure even when they're impatient with dialogue.
        withAnimation(.easeInOut(duration: 0.3)) {
            beatIndex = beats.count - 1
            lineIndex = (beats.last?.lines.count ?? 1) - 1
            showFinCard = true
        }
    }
}
