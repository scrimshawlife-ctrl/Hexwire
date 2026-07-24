import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Replay-mode certification — the WP6 treatment for content WP6 never covered.
///
/// `docs/audit/MissionCertificationMatrix.md` certifies the six campaign
/// missions and mentions gauntlet, contract and arena exactly zero times. Those
/// are the newest shipped modes and the least proven: side contracts were
/// uncompletable on 2026-07-23 with the whole suite green, because nothing drove
/// them the way a player does.
///
/// Every test here finishes a run the player's way — walking a runner onto the
/// extraction pad via `moveCharacter` — rather than calling the extraction
/// intent directly. Setup (room traversal, clearing) uses authority, which WP6
/// already certifies.
@MainActor
final class ReplayModeCertificationTests: XCTestCase {

    private let gs = GameState.shared
    private let persistenceKeys = [
        "HexWire.Contracts.Offers.v1", "HexWire.Contracts.Completed.v1",
        "HexWire.MissionStats.v1", "HexWire.MissionStats.v1.lastGood",
        "HexWire.PlayerNuyen.v1", "HexWire.PaidThisRun.v1",
        "HexWire.Roster.v1", "HexWire.Roster.v1.lastGood",
        "HexWire.NGPlusTier.v1", "HexWire.FactionAttention.v1",
        "HexWire.Gauntlet.v1",
    ]
    private var snapshot: [String: Any] = [:]
    private var savedOffers: [ContractOffer] = []
    private var savedTeam: [Character] = []
    private var savedTier = 0

    override func setUp() async throws {
        snapshot = [:]
        for key in persistenceKeys {
            if let v = UserDefaults.standard.object(forKey: key) { snapshot[key] = v }
        }
        savedOffers = ContractStore.shared.offers
        savedTeam = gs.playerTeam
        savedTier = NGPlusStore.shared.tier
        MissionStatsStore.shared.resetAll()
        NGPlusStore.shared.tier = 0
        MissionStatsStore.shared.resetFactionAttention()
        RosterStore.shared.reset()
        gs.factionAttention = [.corp: 0, .gang: 0, .unknown: 0]
    }

    override func tearDown() async throws {
        ContractStore.shared.disarmForNonContractLoad()
        GauntletStore.shared.disarmForNonGauntletLoad()
        ContractStore.shared.setOffers(savedOffers)
        MissionStatsStore.shared.resetAll()
        NGPlusStore.shared.tier = savedTier
        for key in persistenceKeys { UserDefaults.standard.removeObject(forKey: key) }
        for (key, v) in snapshot { UserDefaults.standard.set(v, forKey: key) }
        gs.playerTeam = savedTeam
        gs.enemies = []
        gs.pendingSpawns = []
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false
        RoomManager.shared.unloadMission()
    }

    // MARK: - Harness

    private func resetRunState() {
        RoomManager.shared.unloadMission()
        gs.enemies = []
        gs.pendingSpawns = []
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false
    }

    private var runResolved: Bool {
        gs.extractionAnimationInProgress || gs.combatEnded || gs.missionComplete
    }

    /// Load a replay mission, clear every room, and walk the last runner onto
    /// the pad. Returns nil if the mission could not be loaded at all.
    /// `label` is only used to make failures identifiable.
    @discardableResult
    private func playThroughViaWalkOn(missionId: String, label: String) -> Bool? {
        resetRunState()
        guard let mission = MissionLoader.shared.loadMultiRoomMission(named: missionId),
              RoomManager.shared.loadMission(named: missionId) != nil else { return nil }
        _ = gs.prepareMissionForCombat(named: missionId)
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false

        var extractionRoom: Room?
        for (i, room) in mission.rooms.enumerated() {
            if i > 0 {
                gs.applyRoomEntry(to: room, enemies: [], pendingSpawns: [],
                                  spawnAnchor: room.playerSpawn)
            }
            gs.pendingSpawns = []
            for enemy in gs.enemies {
                enemy.currentHP = 0
                gs.handleEnemyKilledByEnvironment(enemy, cause: "cert")
            }
            _ = RoomManager.shared.markCurrentRoomCleared()
            if RoomManager.shared.roomHasExtraction(room) { extractionRoom = room }
        }
        guard let finalRoom = extractionRoom else {
            XCTFail("\(label): no room exposes an extraction objective")
            return false
        }
        if RoomManager.shared.currentRoom?.id != finalRoom.id {
            gs.applyRoomEntry(to: finalRoom, enemies: [], pendingSpawns: [],
                              spawnAnchor: finalRoom.playerSpawn)
            gs.enemies.forEach { $0.currentHP = 0 }
            gs.pendingSpawns = []
            _ = RoomManager.shared.markCurrentRoomCleared()
        }
        XCTAssertTrue(RoomManager.shared.isExtractionActive(),
                      "\(label): a fully cleared replay run must arm extraction")
        XCTAssertGreaterThanOrEqual(gs.extractionX, 0, "\(label): extraction coords unset")

        if gs.missionRequiresData && !gs.dataAcquired {
            _ = gs.requestObjectiveDataAcquired(source: "cert")
        }
        guard let runner = gs.playerTeam.first(where: { $0.isAlive }) else {
            XCTFail("\(label): no living runner")
            return false
        }
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        gs.characterHasMovedThisTurn[runner.id] = false
        runner.hasActedThisRound = false

        // The player's way out.
        gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)
        return runResolved
    }

    /// Seeds that reach each distinct arena, so every arena can be driven
    /// through the REAL contract path rather than constructed by hand.
    private func seedsCoveringEveryArena() -> [String: Int] {
        var found: [String: Int] = [:]
        let total = ArenaPool.load().count
        for seed in 0..<20_000 where found.count < total {
            if let id = ArenaPool.arenaId(forSeed: seed), found[id] == nil {
                found[id] = seed
            }
        }
        return found
    }

    // MARK: - Arenas

    /// EVERY arena must be able to host a completable contract. There are 20 and
    /// a player only ever sees the handful their seeds roll — a broken one could
    /// sit undiscovered for months.
    func testEveryArenaHostsACompletableContract() throws {
        let seeds = seedsCoveringEveryArena()
        try XCTSkipIf(seeds.isEmpty, "arena pool did not load")
        XCTAssertEqual(seeds.count, ArenaPool.load().count,
                       "every arena must be reachable by some contract seed")

        var played = 0
        for (arenaId, seed) in seeds.sorted(by: { $0.key < $1.key }) {
            let offer = ContractStore.makeOffer(tier: 1, seed: seed)
            ContractStore.shared.setOffers([offer])
            guard let resolved = playThroughViaWalkOn(missionId: offer.id,
                                                      label: "contract on \(arenaId)") else {
                XCTFail("\(arenaId): contract mission failed to load")
                continue
            }
            XCTAssertTrue(resolved,
                          "\(arenaId): walking onto the pad must complete the contract")
            played += 1
        }
        XCTAssertEqual(played, seeds.count, "every arena must have been played")
    }

    /// Structural gate: an arena that can't place the party or has no exit is a
    /// broken room no amount of runtime luck fixes.
    func testEveryArenaIsStructurallyPlayable() {
        let entries = ArenaPool.load()
        XCTAssertFalse(entries.isEmpty, "arena pool must load")
        for entry in entries {
            let room = entry.room
            let id = room.id
            let h = room.map.count
            XCTAssertGreaterThan(h, 0, "\(id): empty map")
            let w = room.map.first?.count ?? 0

            // Party spawn must be inside the map and not a wall.
            XCTAssertTrue(room.playerSpawn.y >= 0 && room.playerSpawn.y < h,
                          "\(id): playerSpawn off-map vertically")
            XCTAssertTrue(room.playerSpawn.x >= 0 && room.playerSpawn.x < w,
                          "\(id): playerSpawn off-map horizontally")
            XCTAssertNotEqual(room.map[room.playerSpawn.y][room.playerSpawn.x],
                              TileType.wall.rawValue, "\(id): playerSpawn inside a wall")

            // The exit door the contract turns into an extraction pad.
            XCTAssertTrue(entry.exitDoor.y >= 0 && entry.exitDoor.y < h,
                          "\(id): exitDoor off-map vertically")
            XCTAssertTrue(entry.exitDoor.x >= 0 && entry.exitDoor.x < w,
                          "\(id): exitDoor off-map horizontally")

            // Sealing the arena must actually produce a usable extraction.
            let sealed = ArenaPool.finalRoom(from: entry)
            XCTAssertNotNil(sealed.extractionPoint, "\(id): sealed room has no extraction point")
            XCTAssertTrue(RoomManager.shared.roomHasExtraction(sealed),
                          "\(id): sealed room does not register as having extraction")
            if let pt = sealed.extractionPoint {
                XCTAssertEqual(sealed.map[pt.y][pt.x], TileType.extraction.rawValue,
                               "\(id): extraction point is not an extraction tile")
            }

            // Enemies must sit on real, non-wall tiles.
            for e in room.enemies {
                XCTAssertTrue(e.y >= 0 && e.y < h && e.x >= 0 && e.x < w,
                              "\(id): enemy \(e.type) off-map at (\(e.x),\(e.y))")
                if e.y >= 0, e.y < h, e.x >= 0, e.x < w {
                    XCTAssertNotEqual(room.map[e.y][e.x], TileType.wall.rawValue,
                                      "\(id): enemy \(e.type) spawns inside a wall")
                }
                XCTAssertTrue(MissionCertificationTests.knownSpawnTypes.contains(e.type),
                              "\(id): unknown enemy type '\(e.type)' would fall back to a corp guard")
            }
        }
    }

    // MARK: - Contracts

    /// All three tiers must be completable, not just the tier-1 offer the
    /// existing board test happens to use.
    func testEveryContractTierCompletesViaWalkOn() {
        for tier in 1...3 {
            let offer = ContractStore.makeOffer(tier: tier, seed: 4200 + tier)
            ContractStore.shared.setOffers([offer])
            guard let resolved = playThroughViaWalkOn(missionId: offer.id,
                                                      label: "tier \(tier) contract") else {
                XCTFail("tier \(tier): contract mission failed to load")
                continue
            }
            XCTAssertTrue(resolved, "tier \(tier): walking onto the pad must complete the contract")
        }
    }

    // MARK: - Gauntlet

    /// Gauntlet floors must build and be completable the player's way, across
    /// the scaling band (floor composition changes at 4, scaling caps at 10).
    func testGauntletFloorsBuildAndCompleteViaWalkOn() {
        var floorsPlayed = 0
        for _ in 0..<8 {
            let floor = GauntletStore.shared.currentFloor
            guard let resolved = playThroughViaWalkOn(
                missionId: GauntletStore.gauntletMissionId,
                label: "gauntlet floor \(floor)") else {
                XCTFail("gauntlet floor \(floor): mission failed to build")
                break
            }
            XCTAssertTrue(resolved,
                          "gauntlet floor \(floor): walking onto the pad must clear the floor")
            floorsPlayed += 1
            _ = GauntletStore.shared.recordFloorVictory()
        }
        XCTAssertGreaterThanOrEqual(floorsPlayed, 8, "every sampled gauntlet floor must play")
    }

    /// A gauntlet floor is multi-room and must end in exactly one extraction —
    /// a floor with none is unfinishable, a floor with several lets the player
    /// skip arenas they were meant to fight through.
    func testGauntletFloorHasExactlyOneExtractionRoom() throws {
        resetRunState()
        guard let mission = MissionLoader.shared.loadMultiRoomMission(
            named: GauntletStore.gauntletMissionId) else {
            throw XCTSkip("gauntlet floor failed to build")
        }
        XCTAssertGreaterThan(mission.rooms.count, 1, "a gauntlet floor chains multiple arenas")
        let withExtraction = mission.rooms.filter { RoomManager.shared.roomHasExtraction($0) }
        XCTAssertEqual(withExtraction.count, 1,
                       "exactly one arena on a floor may hold the exit")
        XCTAssertEqual(withExtraction.first?.id, mission.rooms.last?.id,
                       "the exit belongs to the LAST arena on the floor")
    }

    /// Floor victory advances the pit and banks the best; defeat resets the run
    /// to floor 1 but must NOT erase the leaderboard stat — that survivorship is
    /// the whole point of bestFloor.
    func testFloorVictoryAdvancesAndDefeatResetsWithoutLosingBest() {
        let start = GauntletStore.shared.currentFloor

        // Returns the floor just COMPLETED; currentFloor is what advances.
        let completed = GauntletStore.shared.recordFloorVictory()
        XCTAssertEqual(completed, start, "return value is the floor just cleared")
        XCTAssertEqual(GauntletStore.shared.currentFloor, start + 1,
                       "a cleared floor advances the pit")
        _ = GauntletStore.shared.recordFloorVictory()
        let best = GauntletStore.shared.bestFloor
        XCTAssertGreaterThanOrEqual(best, start + 1, "best floor banks the deepest clear")

        GauntletStore.shared.recordFloorDefeat()
        XCTAssertEqual(GauntletStore.shared.currentFloor, 1,
                       "a wipe sends the next run back to floor 1")
        XCTAssertEqual(GauntletStore.shared.bestFloor, best,
                       "a wipe must not erase the banked best floor")
    }
}
#endif
