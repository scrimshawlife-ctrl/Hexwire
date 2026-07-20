import Foundation

// MARK: - Contract Board
//
// Procedural one-room SIDE CONTRACTS that recombine EXISTING content — no
// new maps or art (same recombination philosophy as the Endless Gauntlet,
// whose integration pattern this file mirrors on purpose):
//
// • The board always holds three offers, one per tier (1–3). Each offer is
//   a single vetted room lifted from a story mission, SEALED (connections
//   stripped, boss rooms excluded), with a deterministic signature squad —
//   the offer's seed drives MissionSetupService.replaySquad, so retrying a
//   failed contract faces the same opposition ("the intel was accurate"),
//   while every fresh offer rolls a new squad.
// • MissionLoader intercepts the synthetic id ("Contract_t<tier>_<seed>"),
//   resolves the underlying room, and arms ContractStore — exactly the
//   Gauntlet arm/disarm shape, so backing out of a briefing or picking a
//   story mission can never leak contract state.
// • Completion is notification-driven (OutcomePipeline's `.combatAction`):
//   victory consumes the offer and rolls a fresh one at the same tier;
//   defeat keeps the offer on the board for a retry. Pay flows through the
//   normal recordVictory path (basePayout knows contract tiers), so the
//   faction-heat reward multiplier applies to contracts for free.

// MARK: - Offer model

struct ContractOffer: Codable, Equatable, Identifiable {
    let seed: Int
    let sourceMissionId: String
    let tier: Int              // 1–3: pay band + enemy display level
    let employer: String
    let title: String
    let blurb: String

    /// Synthetic mission id. The tier is encoded so MissionStatsStore can
    /// price a contract without needing the store's offer list.
    var id: String { "Contract_t\(tier)_\(seed)" }
    var basePay: Int { ContractStore.basePay(tier: tier) }
}

// MARK: - Contract Store

final class ContractStore: ObservableObject {
    static let shared = ContractStore()

    static let contractIdPrefix = "Contract_"
    static func isContractId(_ id: String?) -> Bool {
        id?.hasPrefix(contractIdPrefix) == true
    }

    /// Contracts draw their sites from the ArenaPool (dedicated replay
    /// rooms with their own art) — the arena is picked deterministically
    /// from the offer seed at load time.

    static func basePay(tier: Int) -> Int {
        switch tier {
        case 3:  return 16_000
        case 2:  return 11_000
        default: return 7_000
        }
    }

    // ── Flavor tables (seed-picked, deterministic per offer) ──
    static let employers = [
        "MR. JOHNSON", "AZTECH BROKER", "HALO COLLECTIVE", "THE UNDERNET",
        "EX-RENRAKU FIXER", "DOCKSIDE TRIAD", "ZERO STATE", "THE BELL COURIERS",
    ]
    static let jobTitles = [
        "SMASH & GRAB", "SILENCE THE FLOOR", "REPO RUN", "WETWORK LITE",
        "CLEAR THE NEST", "ASSET DENIAL", "NO WITNESSES", "SEND A MESSAGE",
    ]
    static let blurbs = [
        "In, down, out. The room is sealed — nobody leaves before you do.",
        "The employer wants the floor swept. Every hostile, no exceptions.",
        "Quick contract, honest pay. The opposition disagrees on both counts.",
        "Off-book job. If it goes loud, it was always going to go loud.",
    ]

    // ── State ──

    @Published private(set) var offers: [ContractOffer] = []
    /// Armed while an in-flight contract mission is loaded. Session-only —
    /// a force-quit mid-contract drops the attempt without consuming the offer.
    @Published private(set) var isActive = false
    private(set) var activeOffer: ContractOffer?
    /// Lifetime completed-contract count (achievement / flavor stat).
    @Published private(set) var completedCount: Int

    private let offersKey = "HexWire.Contracts.Offers.v1"
    private let completedKey = "HexWire.Contracts.Completed.v1"

    private init() {
        completedCount = UserDefaults.standard.integer(forKey: completedKey)
        if let data = UserDefaults.standard.data(forKey: offersKey),
           let decoded = try? JSONDecoder().decode([ContractOffer].self, from: data) {
            offers = decoded
        }
        ensureBoardFilled()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(offers) {
            UserDefaults.standard.set(data, forKey: offersKey)
        }
        UserDefaults.standard.set(completedCount, forKey: completedKey)
    }

    // MARK: - Offer generation

    /// Deterministic mixer for flavor picks off the offer seed.
    private static func mix(_ seed: Int, _ salt: Int) -> Int {
        var z = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15 &* UInt64(salt + 1)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int(truncatingIfNeeded: z ^ (z >> 31)) & Int.max
    }

    static func makeOffer(tier: Int, seed: Int) -> ContractOffer {
        return ContractOffer(
            seed: seed,
            sourceMissionId: ArenaPool.arenaId(forSeed: seed) ?? "arena_01",
            tier: tier,
            employer: employers[mix(seed, 2) % employers.count],
            title: jobTitles[mix(seed, 3) % jobTitles.count],
            blurb: blurbs[mix(seed, 4) % blurbs.count]
        )
    }

    /// Top the board up to one offer per tier (fresh random seeds).
    func ensureBoardFilled() {
        var changed = false
        for tier in 1...3 where !offers.contains(where: { $0.tier == tier }) {
            offers.append(ContractStore.makeOffer(tier: tier, seed: Int.random(in: 1..<Int.max)))
            changed = true
        }
        offers.sort { $0.tier < $1.tier }
        if changed { persist() }
    }

    func offer(withId id: String) -> ContractOffer? {
        offers.first { $0.id == id }
    }

    /// Replace the whole board (test/debug seam — offer state is otherwise
    /// only mutated through the run lifecycle).
    func setOffers(_ newOffers: [ContractOffer]) {
        offers = newOffers.sorted { $0.tier < $1.tier }
        persist()
    }

    // MARK: - Room resolution helpers (used by MissionLoader)

    /// A sealed contract room must resolve an extraction objective. If the
    /// source room has neither an explicit extractionPoint nor a map
    /// extraction tile, synthesize one on the walkable floor tile farthest
    /// from the player spawn (deterministic scan order).
    static func syntheticExtraction(for room: Room) -> SpawnPoint? {
        if room.extractionPoint != nil { return room.extractionPoint }
        if room.map.contains(where: { $0.contains(TileType.extraction.rawValue) }) { return nil }
        var best: SpawnPoint?
        var bestDist = -1
        for y in room.map.indices {
            for x in room.map[y].indices where room.map[y][x] == TileType.floor.rawValue {
                let d = CombatMechanics.hexDistance(x1: room.playerSpawn.x, y1: room.playerSpawn.y,
                                                   x2: x, y2: y)
                if d > bestDist { bestDist = d; best = SpawnPoint(x: x, y: y) }
            }
        }
        return best
    }

    // MARK: - Arming / disarming (Gauntlet pattern)

    func armForContractLoad(_ offer: ContractOffer) {
        _ = ContractService.shared   // ensure the mission-end observer exists
        activeOffer = offer
        guard !isActive else { return }
        isActive = true
    }

    /// Any REAL (non-contract) mission load stands an armed contract down.
    func disarmForNonContractLoad() {
        guard isActive else { return }
        isActive = false
        activeOffer = nil
    }

    // MARK: - Run lifecycle (driven by ContractService)

    /// Contract fulfilled: consume the offer and roll a fresh one at the
    /// same tier. Pay is handled by the normal recordVictory path.
    func recordContractVictory() {
        guard let done = activeOffer else { return }
        offers.removeAll { $0.id == done.id }
        completedCount += 1
        isActive = false
        activeOffer = nil
        ensureBoardFilled()
        persist()
    }

    /// Party wipe: the offer stays on the board for a retry (same seed →
    /// the same signature squad — the intel was accurate).
    func recordContractDefeat() {
        isActive = false
        activeOffer = nil
    }
}

// MARK: - Contract Service

/// Mission-end observer — the Gauntlet's notification-driven shape, so
/// OutcomePipeline and GameState need no edits.
final class ContractService {
    static let shared = ContractService()

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .combatAction, object: nil, queue: .main
        ) { note in
            ContractService.handleCombatOutcome(note)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private static func handleCombatOutcome(_ note: Notification) {
        let store = ContractStore.shared
        guard store.isActive,
              let result = note.userInfo?["result"] as? String else { return }
        switch result {
        case "victory": store.recordContractVictory()
        case "defeat":  store.recordContractDefeat()
        default: break
        }
    }
}
