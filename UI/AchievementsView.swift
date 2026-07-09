import SwiftUI

// MARK: - AchievementsView
//
// "RECORDS" board reachable from mission select. Deliberately ZERO new
// tracking plumbing: every achievement is EVALUATED LIVE from state the game
// already persists (MissionStatsStore records/wallet, RosterStore levels &
// chrome, NGPlusStore tier, GauntletStore depth) — so historical progress
// unlocks retroactively and there are no counters to migrate or corrupt.
// The trade-off (documented, intentional): transient feats that leave no
// persisted trace (e.g. "win a mission with no damage taken") can't be
// achievements until a counter exists for them.

struct Achievement: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let icon: String        // SF Symbol
    let unlocked: Bool
    /// Optional "2/6"-style progress hint shown while locked.
    var progress: String? = nil
}

enum AchievementBoard {
    /// The six tactical campaign missions (interstitials scored separately).
    private static let tacticalIds = ["Mission001", "Mission002", "Mission003",
                                      "Mission004", "Mission005", "Mission006"]
    private static let interstitialIds = ["Mission002_5", "Mission003_5",
                                          "Mission004_5", "Mission005_5"]
    /// Missions with a data-terminal hack mini-game.
    private static let hackIds = ["Mission002", "Mission003", "Mission004",
                                  "Mission005", "Mission006"]

    @MainActor
    static func evaluate() -> [Achievement] {
        let stats = MissionStatsStore.shared
        let roster = RosterStore.shared.loadCanonical()
        let ngTier = NGPlusStore.shared.tier

        func rec(_ id: String) -> MissionRecord { stats.record(for: id) }
        let tacticalDone = tacticalIds.filter { rec($0).completed }.count
        let interstitialsDone = interstitialIds.filter { rec($0).completed }.count
        let sRanks = tacticalIds.filter { MissionStatsStore.rank(forScore: rec($0).bestScore) == "S" }.count
        let hacksDone = hackIds.filter { rec($0).bestMiniGameScore > 0 }.count
        let maxLevel = roster.map(\.level).max() ?? 1
        let maxChrome = roster.map { $0.cyberware.count }.max() ?? 0
        let bestFloor = GauntletStore.shared.bestFloor

        return [
            Achievement(id: "first_blood", title: "First Blood",
                        blurb: "Complete The Extraction.",
                        icon: "drop.fill",
                        unlocked: rec("Mission001").completed),
            Achievement(id: "campaign", title: "Campaign Clear",
                        blurb: "Complete all six tactical contracts.",
                        icon: "flag.checkered",
                        unlocked: tacticalDone == tacticalIds.count,
                        progress: "\(tacticalDone)/\(tacticalIds.count)"),
            Achievement(id: "side_jobs", title: "Between the Lines",
                        blurb: "Complete all four side operations.",
                        icon: "arrow.triangle.branch",
                        unlocked: interstitialsDone == interstitialIds.count,
                        progress: "\(interstitialsDone)/\(interstitialIds.count)"),
            Achievement(id: "s_rank", title: "S-Tier Operative",
                        blurb: "Earn an S rank on any tactical contract.",
                        icon: "star.fill",
                        unlocked: sRanks >= 1),
            Achievement(id: "flawless", title: "Flawless Syndicate",
                        blurb: "Hold an S rank on all six tactical contracts.",
                        icon: "crown.fill",
                        unlocked: sRanks == tacticalIds.count,
                        progress: "\(sRanks)/\(tacticalIds.count)"),
            Achievement(id: "clean_hands", title: "Clean Hands",
                        blurb: "Beat the data-terminal hack on every wired contract.",
                        icon: "terminal.fill",
                        unlocked: hacksDone == hackIds.count,
                        progress: "\(hacksDone)/\(hackIds.count)"),
            Achievement(id: "ng1", title: "Running Hot",
                        blurb: "Enter New Game+.",
                        icon: "flame.fill",
                        unlocked: ngTier >= 1),
            Achievement(id: "ng3", title: "Treadmill Legend",
                        blurb: "Reach New Game+3.",
                        icon: "infinity",
                        unlocked: ngTier >= 3,
                        progress: "NG+\(ngTier)"),
            Achievement(id: "quarter_mil", title: "Quarter Million",
                        blurb: "Hold ¥250,000 in the wallet at once.",
                        icon: "yensign.circle.fill",
                        unlocked: stats.playerNuyen >= 250_000,
                        progress: "¥\(stats.playerNuyen.formatted())"),
            Achievement(id: "chromed", title: "Chromed Up",
                        blurb: "Install 3 pieces of cyberware on one runner.",
                        icon: "cpu.fill",
                        unlocked: maxChrome >= 3,
                        progress: "\(maxChrome)/3"),
            Achievement(id: "full_conversion", title: "Full Conversion",
                        blurb: "Install 6 pieces of cyberware on one runner.",
                        icon: "gearshape.2.fill",
                        unlocked: maxChrome >= 6,
                        progress: "\(maxChrome)/6"),
            Achievement(id: "veteran", title: "Veteran Runner",
                        blurb: "Level any runner to 10.",
                        icon: "figure.walk.motion",
                        unlocked: maxLevel >= 10,
                        progress: "LVL \(maxLevel)"),
            Achievement(id: "deep_dive", title: "Deep Dive",
                        blurb: "Reach floor 3 of the Endless Gauntlet.",
                        icon: "arrow.down.to.line",
                        unlocked: bestFloor >= 3,
                        progress: bestFloor > 0 ? "FLOOR \(bestFloor)" : nil),
            Achievement(id: "abyss", title: "Abyss Walker",
                        blurb: "Reach floor 6 of the Endless Gauntlet.",
                        icon: "tornado",
                        unlocked: bestFloor >= 6,
                        progress: bestFloor > 0 ? "FLOOR \(bestFloor)" : nil),
        ]
    }
}

/// Full-screen records board. Same visual language as the shop/roster covers:
/// dark backdrop, monospaced cyberpunk chrome, green = earned.
struct AchievementsView: View {
    let onDismiss: () -> Void
    @State private var achievements: [Achievement] = []

    var body: some View {
        ZStack {
            Color(hex: "05070D").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("RECORDS")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "00FFCC")).tracking(2)
                    Spacer()
                    let earned = achievements.filter(\.unlocked).count
                    Text("\(earned)/\(achievements.count)")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF88"))
                    Button(action: { HapticsManager.shared.back(); onDismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24)).foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(achievements) { a in
                            achievementRow(a)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { achievements = AchievementBoard.evaluate() }
    }

    private func achievementRow(_ a: Achievement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.icon)
                .font(.system(size: 18))
                .foregroundColor(a.unlocked ? Color(hex: "00FF88") : .white.opacity(0.25))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill((a.unlocked ? Color(hex: "00FF88") : Color.white).opacity(0.08))
                        .overlay(Circle().stroke((a.unlocked ? Color(hex: "00FF88") : Color.white).opacity(0.25), lineWidth: 1))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title.uppercased())
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(a.unlocked ? .white : .white.opacity(0.45))
                Text(a.blurb)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(a.unlocked ? 0.6 : 0.35))
                    .lineLimit(2)
            }
            Spacer()
            if a.unlocked {
                Text("EARNED")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: "00FF88"))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "00FF88").opacity(0.12))
                        .overlay(Capsule().stroke(Color(hex: "00FF88").opacity(0.5), lineWidth: 1)))
            } else if let p = a.progress {
                Text(p)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(a.unlocked ? 0.05 : 0.02))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke((a.unlocked ? Color(hex: "00FF88") : Color.white).opacity(a.unlocked ? 0.3 : 0.08), lineWidth: 1))
        )
    }
}
