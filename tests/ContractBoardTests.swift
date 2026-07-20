import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Contract-board certification: offer generation/persistence, synthetic
/// mission resolution, signature squads, the run lifecycle, and a full
/// end-to-end contract playthrough on the WP6 harness pattern.
@MainActor
final class ContractBoardTests: XCTestCase {

    private let gs = GameState.shared
    private let keys = [
        "HexWire.Contracts.Offers.v1", "HexWire.Contracts.Completed.v1",
        "HexWire.MissionStats.v1", "HexWire.MissionStats.v1.lastGood",
        "HexWire.PlayerNuyen.v1", "HexWire.PaidThisRun.v1",
        "HexWire.Roster.v1", "HexWire.Roster.v1.lastGood",
        "HexWire.NGPlusTier.v1", "HexWire.FactionAttention.v1",
    ]
    private var snapshot: [String: Any] = [:]
    private var savedOffers: [ContractOffer] = []
    private var savedTeam: [Character] = []
    private var savedTier = 0

    override func setUp() async throws {
        snapshot = [:]
        for k in keys { if let v = UserDefaults.standard.object(forKey: k) { snapshot[k] = v } }
        savedOffers = ContractStore.shared.offers
        savedTeam = gs.playerTeam
        savedTier = NGPlusStore.shared.tier
        NGPlusStore.shared.tier = 0
        MissionStatsStore.shared.resetAll()
        MissionStatsStore.shared.resetFactionAttention()
        gs.factionAttention = [.corp: 0, .gang: 0, .unknown: 0]
    }

    override func tearDown() async throws {
        ContractStore.shared.disarmForNonContractLoad()
        ContractStore.shared.setOffers(savedOffers)
        MissionStatsStore.shared.resetAll()
        NGPlusStore.shared.tier = savedTier
        for k in keys { UserDefaults.standard.removeObject(forKey: k) }
        for (k, v) in snapshot { UserDefaults.standard.set(v, forKey: k) }
        gs.playerTeam = savedTeam
        gs.enemies = []
        gs.pendingSpawns = []
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false
        gs.combatOutcome = .none   // stale terminal outcomes re-latch missionComplete via syncLegacyState
        gs.currentMissionDisplayId = nil
        CombatFlowController.setCombatPhase(gameState: gs, .idle)
        // Invalidate any pending 14s extraction safety-net timers scheduled
        // during this test — their attempt-token guard makes this the
        // designed kill switch (otherwise a timer fires mid-later-test and
        // re-finalizes the mission).
        gs.missionAttemptId += 1
        RoomManager.shared.unloadMission()
    }

    // MARK: - Offers

    func testBoardAlwaysHoldsOneOfferPerTier() {
        ContractStore.shared.setOffers([])
        ContractStore.shared.ensureBoardFilled()
        let tiers = ContractStore.shared.offers.map(\.tier).sorted()
        XCTAssertEqual(tiers, [1, 2, 3])
    }

    func testOfferGenerationIsDeterministicPerSeed() {
        let a = ContractStore.makeOffer(tier: 2, seed: 777)
        let b = ContractStore.makeOffer(tier: 2, seed: 777)
        XCTAssertEqual(a, b, "same seed must produce the identical offer")
        XCTAssertTrue(ContractStore.missionPoolByTier[2]!.contains(a.sourceMissionId))
        XCTAssertEqual(a.id, "Contract_t2_777")
    }

    func testContractPayoutTiersAndDisplayLevels() {
        XCTAssertEqual(MissionStatsStore.basePayout(missionId: "Contract_t1_5"), ContractStore.basePay(tier: 1))
        XCTAssertEqual(MissionStatsStore.basePayout(missionId: "Contract_t2_5"), ContractStore.basePay(tier: 2))
        XCTAssertEqual(MissionStatsStore.basePayout(missionId: "Contract_t3_5"), ContractStore.basePay(tier: 3))
        XCTAssertEqual(MissionStatsStore.enemyDisplayLevel(missionId: "Contract_t3_5", archetype: "guard"), 3)
        XCTAssertEqual(MissionStatsStore.enemyDisplayLevel(missionId: "Contract_t1_5", archetype: "bossmech"), 2)
    }

    // MARK: - Synthetic mission resolution

    func testContractMissionResolvesToSealedSingleRoom() throws {
        let offer = ContractStore.makeOffer(tier: 2, seed: 4242)
        ContractStore.shared.setOffers([offer])
        guard let mission = MissionLoader.shared.loadMultiRoomMission(named: offer.id) else {
            throw XCTSkip("mission JSONs not bundled in test host")
        }
        XCTAssertEqual(mission.id, offer.id, "stats/payout must record under the contract id")
        XCTAssertEqual(mission.rooms.count, 1, "contracts are single-room jobs")
        let room = mission.rooms[0]
        XCTAssertTrue(room.connections.isEmpty, "contract rooms are sealed")
        XCTAssertNil(room.bossSpawn, "scripted bosses never appear in contracts")
        XCTAssertFalse(room.enemies.isEmpty, "contract rooms ship an authored squad")
        XCTAssertTrue(RoomManager.shared.roomHasExtraction(room),
                      "a sealed room must resolve an extraction objective")
        XCTAssertTrue(ContractStore.shared.isActive, "loader must arm the contract")
        XCTAssertEqual(ContractStore.shared.activeOffer?.id, offer.id)

        // Loading a REAL mission stands the contract down (Gauntlet pattern).
        _ = MissionLoader.shared.loadMultiRoomMission(named: "Mission001")
        XCTAssertFalse(ContractStore.shared.isActive, "real mission load must disarm")
    }

    func testSyntheticExtractionPicksFarthestFloorTileWhenMissing() {
        let room = Room(id: "r", title: "t",
                        map: [[0, 0, 0, 0, 0]],
                        playerSpawn: SpawnPoint(x: 0, y: 0),
                        extractionPoint: nil,
                        enemies: [], connections: [],
                        removeOnFirstKill: nil, bossSpawn: nil)
        let p = ContractStore.syntheticExtraction(for: room)
        XCTAssertEqual(p?.x, 4, "farthest floor tile from spawn")
        // Rooms that already have an objective are left alone.
        let withMapTile = Room(id: "r", title: "t", map: [[0, 4]],
                               playerSpawn: SpawnPoint(x: 0, y: 0), extractionPoint: nil,
                               enemies: [], connections: [], removeOnFirstKill: nil, bossSpawn: nil)
        XCTAssertNil(ContractStore.syntheticExtraction(for: withMapTile),
                     "map extraction tile wins — no synthetic point")
    }

    // MARK: - Signature squads

    func testContractSquadIsTheOfferSeedNotTheAttemptCounter() throws {
        let offer = ContractStore.makeOffer(tier: 2, seed: 9001)
        ContractStore.shared.setOffers([offer])
        guard let mission = MissionLoader.shared.loadMultiRoomMission(named: offer.id) else {
            throw XCTSkip("mission JSONs not bundled")
        }
        _ = RoomManager.shared.loadMission(named: offer.id)
        gs.currentMissionDisplayId = offer.id
        let room = mission.rooms[0]

        gs.missionAttemptId = 1
        let first = MissionSetupService.replaySquad(for: room, gameState: gs)
        gs.missionAttemptId = 99   // a RETRY bumps the attempt counter…
        let retry = MissionSetupService.replaySquad(for: room, gameState: gs)
        XCTAssertEqual(first.map(\.type), retry.map(\.type),
                       "…but the signature squad stays pinned to the offer seed")
    }

    // MARK: - Run lifecycle

    func testVictoryConsumesOfferAndRefillsDefeatKeepsIt() {
        let offer = ContractStore.makeOffer(tier: 1, seed: 31337)
        ContractStore.shared.setOffers([offer])
        let before = ContractStore.shared.completedCount

        ContractStore.shared.armForContractLoad(offer)
        ContractStore.shared.recordContractDefeat()
        XCTAssertNotNil(ContractStore.shared.offer(withId: offer.id),
                        "defeat keeps the offer on the board for a retry")
        XCTAssertFalse(ContractStore.shared.isActive)

        ContractStore.shared.armForContractLoad(offer)
        ContractStore.shared.recordContractVictory()
        XCTAssertNil(ContractStore.shared.offer(withId: offer.id),
                     "victory consumes the offer")
        XCTAssertEqual(ContractStore.shared.completedCount, before + 1)
        XCTAssertEqual(ContractStore.shared.offers.map(\.tier).sorted(), [1, 2, 3],
                       "the board refills to one offer per tier")
    }

    // MARK: - End-to-end: accept → clear → extract → paid → consumed

    func testContractPlaysThroughToPayoutEndToEnd() throws {
        let offer = ContractStore.makeOffer(tier: 1, seed: 5150)
        ContractStore.shared.setOffers([offer])
        guard MissionLoader.shared.loadMultiRoomMission(named: offer.id) != nil,
              let mission = RoomManager.shared.loadMission(named: offer.id) else {
            throw XCTSkip("mission JSONs not bundled")
        }
        _ = gs.prepareMissionForCombat(named: offer.id)
        gs.missionComplete = false
        gs.combatEnded = false
        XCTAssertEqual(gs.currentMissionDisplayId, offer.id)
        XCTAssertTrue(ContractStore.shared.isActive)

        gs.enemies.forEach { $0.currentHP = 0 }
        gs.pendingSpawns = []
        _ = RoomManager.shared.markCurrentRoomCleared()
        XCTAssertTrue(RoomManager.shared.isExtractionActive(in: mission.rooms[0]))
        if gs.missionRequiresData && !gs.dataAcquired {
            _ = gs.requestObjectiveDataAcquired(source: "contract-test")
        }
        guard let runner = gs.playerTeam.first(where: { $0.isAlive }) else {
            return XCTFail("no living runner")
        }
        runner.positionX = gs.extractionX
        runner.positionY = gs.extractionY
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        XCTAssertEqual(gs.requestExtractionResolution(
            characterId: runner.id, tileX: gs.extractionX, tileY: gs.extractionY), .accepted)
        XCTAssertEqual(gs.requestExtractionSequenceCompleted(), .accepted)

        XCTAssertTrue(gs.missionComplete, "contract completes through the normal pipeline")
        XCTAssertEqual(MissionStatsStore.shared.record(for: offer.id).attempts, 1)
        XCTAssertGreaterThan(MissionStatsStore.shared.playerNuyen, 0,
                             "tier pay lands in the wallet")
        XCTAssertNil(ContractStore.shared.offer(withId: offer.id),
                     "the fulfilled offer leaves the board")
        XCTAssertEqual(ContractStore.shared.offers.map(\.tier).sorted(), [1, 2, 3],
                       "a fresh tier-1 offer replaces it")
        XCTAssertFalse(ContractStore.shared.isActive)
    }
}
#endif
