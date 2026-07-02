import SwiftUI

/// Reusable "how to play" overlay used by all the data-extraction mini-games.
/// Shows the mini-game's name, an accent strip, 2-4 numbered rules with icons,
/// and a START button. Held in front of gameplay until the player taps START.
///
/// Each game owns its own `showBriefing: Bool` state — toggle it false in the
/// onStart closure and the host view will dismiss this overlay.
struct MiniGameBriefing: View {
    let title: String                    // e.g. "DATA CONDUIT"
    let subtitle: String                 // e.g. "LANE RUNNER PROTOCOL"
    let accent: Color                    // accent color for borders + START button
    let rules: [BriefingRule]
    let onStart: () -> Void

    /// OPTIONAL — when set, replaces the single START button with one
    /// button per difficulty option. Tap fires `onStartWithDifficulty`
    /// passing the selected option index (0 = first / easiest).
    /// Mini-games that don't need difficulty selection just leave this nil
    /// and the existing single START path is unchanged.
    var difficulties: [DifficultyOption]? = nil
    var onStartWithDifficulty: ((Int) -> Void)? = nil

    struct DifficultyOption {
        let label: String       // e.g. "EASY"
        let detail: String      // one-line description shown beneath the label
        let color: Color
    }

    var body: some View {
        ZStack {
            // Fully opaque backdrop — briefing sits in the same ZStack as the
            // mini-game's HUD/canvas, so any transparency here lets the
            // gameplay chrome bleed through and reads as visual noise.
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("// BREACH PROTOCOL")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.6))
                Rectangle()
                    .fill(accent.opacity(0.5))
                    .frame(width: 80, height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        ruleRow(rule)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(Color(hex: "0A0A14").opacity(0.85))
                .overlay(Rectangle().stroke(accent.opacity(0.5), lineWidth: 1))

                if let difficulties = difficulties, let pickStart = onStartWithDifficulty {
                    // Difficulty-picker variant — vertical stack of buttons.
                    // Each option tints its own button + shows one-line detail.
                    VStack(spacing: 10) {
                        Text("SELECT DIFFICULTY")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(3)
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.bottom, 2)
                        ForEach(Array(difficulties.enumerated()), id: \.offset) { idx, opt in
                            Button(action: {
                                HapticsManager.shared.buttonTap()
                                pickStart(idx)
                            }) {
                                VStack(spacing: 2) {
                                    Text(opt.label)
                                        .font(.system(size: 13, weight: .black, design: .monospaced))
                                        .tracking(3)
                                        .foregroundColor(.black)
                                    Text(opt.detail)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.black.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(opt.color)
                                .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                            }
                        }
                    }
                    .frame(maxWidth: 280)
                } else {
                    Button(action: {
                        HapticsManager.shared.buttonTap()
                        onStart()
                    }) {
                        Text("⟫  START  ⟪")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .tracking(3)
                            .foregroundColor(.black)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 14)
                            .background(accent)
                            .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                    }
                    .frame(minHeight: 50)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func ruleRow(_ rule: BriefingRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.iconName)
                .font(.system(size: 22))
                .foregroundColor(rule.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(rule.color)
                Text(rule.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

struct BriefingRule {
    let iconName: String       // SF Symbol name
    let color: Color
    let title: String
    let detail: String
}
