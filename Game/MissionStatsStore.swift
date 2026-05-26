import Foundation
import Combine

/// Per-mission completion + best-score record for display on the mission menu.
struct MissionRecord: Codable, Equatable {
    var bestScore: Int
    var attempts: Int
    var lastCompletedAt: Date?
    /// Best score achieved on the mission's data-terminal mini-game (lane
    /// runner / cypher crack / packet route / glyph ward / agi face-off).
    /// 0 if the player has never won the mini-game on this mission.
    var bestMiniGameScore: Int = 0

    static let empty = MissionRecord(bestScore: 0, attempts: 0, lastCompletedAt: nil, bestMiniGameScore: 0)
    var completed: Bool { lastCompletedAt != nil }
}

/// Persistent store of per-mission stats. Backed by UserDefaults so completion
/// + best scores survive app relaunches. Singleton — read by MissionCard for
/// the badge, written by OutcomePipeline / finalizeCombat on a successful run.
final class MissionStatsStore: ObservableObject {
    static let shared = MissionStatsStore()

    @Published private(set) var records: [String: MissionRecord] = [:]

    /// Persistent runner-nuyen balance. Accumulates across mission victories,
    /// survives app relaunches. Reflects the same payout figures shown on the
    /// debrief screen so the wallet matches what the runner believes they've
    /// banked. v0.1: spend-side is purely cosmetic (no shop) — it's an
    /// achievement-tracking total. Spent in future updates.
    @Published private(set) var playerNuyen: Int = 0

    private let storageKey = "ShadowrunGame.MissionStats.v1"
    private let nuyenStorageKey = "ShadowrunGame.PlayerNuyen.v1"

    /// Per-mission base payout (matches the debrief screens). Bonus amounts
    /// (data / grimoire) live in `bonusFor(...)` below. Kept here as the
    /// single source of truth so the debrief text, wallet credit, and the
    /// mission select reward preview all read the same numbers.
    static func basePayout(missionId: String) -> Int {
        switch missionId {
        case "Mission001":   return 15_000
        case "Mission002":   return 28_000
        case "Mission002_5": return 15_000   // mirrorline = solo astral bonus
        case "Mission003":   return 40_000
        case "Mission003_5": return 10_000   // chase = clean exfil bonus
        case "Mission004":   return 50_000
        case "Mission004_5": return 12_000   // basement brawl = solo melee bonus
        case "Mission005":   return 60_000
        case "Mission005_5": return 35_000   // cold trace = solo decker run + Neural Imprint
        case "Mission006":   return 500_000
        default:             return 15_000
        }
    }

    /// Data-acquisition bonus (terminal hack) per mission.
    static func dataBonus(missionId: String) -> Int {
        switch missionId {
        case "Mission002":   return 7_500
        case "Mission002_5": return 5_000   // Akashic Fragment recovered
        case "Mission003":   return 7_500
        case "Mission004":   return 10_000
        case "Mission005":   return 10_000
        case "Mission005_5": return 8_000   // Neural Imprint extracted
        case "Mission006":   return 50_000
        default:             return 0
        }
    }

    /// Grimoire bonus (M3 only).
    static func grimoireBonus(missionId: String) -> Int {
        missionId == "Mission003" ? 10_000 : 0
    }

    private init() {
        load()
        runMigrations()
    }

    // MARK: - Migrations

    /// Idempotent one-shot migrations run once per app install on the first
    /// access of the shared store. Each migration is gated by its own
    /// UserDefaults flag so it never replays after running successfully.
    private func runMigrations() {
        migrateBackfillChaseCompletion()
    }

    /// Players who beat M3.5 "The Drop" BEFORE the chase's victory-record
    /// wiring shipped (2026-05-18) have no Mission003_5 entry in their stats,
    /// so the mission card still shows as not-completed even though they
    /// played + won it. Detect that footprint — M1/M2/M3 done, M3.5 missing —
    /// and backfill a completion entry once. Flag persists, never replays.
    private func migrateBackfillChaseCompletion() {
        let flagKey = "ShadowrunGame.Migration.ChaseBackfill.v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        let m1Done = (records["Mission001"]?.completed ?? false)
        let m2Done = (records["Mission002"]?.completed ?? false)
        let m3Done = (records["Mission003"]?.completed ?? false)
        let chaseDone = (records["Mission003_5"]?.completed ?? false)

        // Eligible: progressed past M3 (proves they unlocked + would have
        // played the chase to reach M4) but no chase record exists.
        if m1Done && m2Done && m3Done && !chaseDone {
            var rec = records["Mission003_5"] ?? .empty
            rec.attempts = max(1, rec.attempts)
            rec.bestScore = max(rec.bestScore, 800)   // neutral mid-tier score
            rec.lastCompletedAt = Date()
            records["Mission003_5"] = rec
            save()
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    func record(for missionId: String) -> MissionRecord {
        records[missionId] ?? .empty
    }

    /// Total best score across every mission completed at least once.
    var totalScore: Int {
        records.values.reduce(0) { $0 + $1.bestScore }
    }

    /// Number of distinct missions completed at least once.
    var missionsCompleted: Int {
        records.values.filter { $0.completed }.count
    }

    /// Register a victory. Pass the score you computed at finalize time and the
    /// mission id (e.g. "Mission001"). Updates best score (max), increments
    /// attempts, stamps lastCompletedAt, and persists.
    ///
    /// Optionally credit nuyen to the persistent wallet based on what the
    /// runner actually recovered this run (`dataAcquired` / `grimoireAcquired`).
    /// Wallet credits are per-attempt, not per-best — repeating a mission re-pays.
    func recordVictory(missionId: String, score: Int,
                       dataAcquired: Bool = false,
                       grimoireAcquired: Bool = false) {
        var rec = records[missionId] ?? .empty
        rec.attempts += 1
        rec.bestScore = max(rec.bestScore, score)
        rec.lastCompletedAt = Date()
        records[missionId] = rec
        // Credit the wallet — base payout always paid on victory; bonus
        // payouts only paid when the corresponding objective was hit.
        var credit = MissionStatsStore.basePayout(missionId: missionId)
        if dataAcquired     { credit += MissionStatsStore.dataBonus(missionId: missionId) }
        if grimoireAcquired { credit += MissionStatsStore.grimoireBonus(missionId: missionId) }
        playerNuyen += credit
        save()
    }

    /// Record the player's best score for a single mini-game victory.
    /// Stored separately from the full-mission score so it persists even if
    /// the player bails the mission afterwards. Updates `bestMiniGameScore`
    /// with `max(prev, score)`.
    func recordMiniGameScore(missionId: String, score: Int) {
        var rec = records[missionId] ?? .empty
        rec.bestMiniGameScore = max(rec.bestMiniGameScore, score)
        records[missionId] = rec
        save()
    }

    /// Clear ALL records (debug menu / restart-from-scratch use).
    func resetAll() {
        records = [:]
        playerNuyen = 0
        save()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: MissionRecord].self, from: data) {
            records = decoded
        }
        playerNuyen = UserDefaults.standard.integer(forKey: nuyenStorageKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(playerNuyen, forKey: nuyenStorageKey)
    }

    // MARK: - Score Calculation

    /// Computes the player's score for a mission victory.
    /// Components:
    ///   • survival   : 400 per living runner (max 1600)
    ///   • kills      : 80 per enemy defeated
    ///   • objective  : 250 if `dataAcquired` (mission required hacking)
    ///   • efficiency : up to 600 bonus, 20 lost per round taken (so a 5-round
    ///                  run banks 500, a 30-round run banks nothing)
    /// Floor at 0; no upper cap so dominant runs feel rewarding.
    static func computeScore(
        enemiesDefeated: Int,
        livingPlayers: Int,
        roundsTaken: Int,
        dataAcquired: Bool
    ) -> Int {
        let survival = min(4, livingPlayers) * 400
        let kills = enemiesDefeated * 80
        let objective = dataAcquired ? 250 : 0
        let efficiency = max(0, 600 - roundsTaken * 20)
        return survival + kills + objective + efficiency
    }
}
