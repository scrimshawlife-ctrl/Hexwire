import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Turn/authority guards, exactly-once mission completion, and destructible
/// cover — exercised through the real GameState authority singleton, with
/// every touched field snapshotted around each test.
@MainActor
final class TurnAuthorityTests: XCTestCase {

    private let gs = GameState.shared

    private var savedTiles: [[Int]] = []
    private var savedDestroyed: [String: [[Int]]] = [:]
    private var savedRoomId = ""
    private var savedTeam: [Character] = []
    private var savedEnemies: [Enemy] = []
    private var savedMissionType: MissionType = .stealth
    private var statsSnapshot: [String: Any] = [:]
    private let statsKeys = [
        "HexWire.MissionStats.v1", "HexWire.MissionStats.v1.lastGood",
        "HexWire.PlayerNuyen.v1", "HexWire.PaidThisRun.v1",
        "HexWire.Roster.v1", "HexWire.Roster.v1.lastGood",
    ]

    override func setUp() async throws {
        savedTiles = gs.currentMissionTiles
        savedDestroyed = gs.destroyedCoverByRoom
        savedRoomId = gs.currentRoomId
        savedTeam = gs.playerTeam
        savedEnemies = gs.enemies
        savedMissionType = gs.currentMissionType
        statsSnapshot = [:]
        for key in statsKeys {
            if let v = UserDefaults.standard.object(forKey: key) { statsSnapshot[key] = v }
        }
    }

    override func tearDown() async throws {
        gs.currentMissionTiles = savedTiles
        gs.destroyedCoverByRoom = savedDestroyed
        gs.currentRoomId = savedRoomId
        gs.playerTeam = savedTeam
        gs.enemies = savedEnemies
        gs.currentMissionType = savedMissionType
        gs.missionComplete = false
        gs.combatEnded = false
        gs.combatOutcome = .none
        gs.currentMissionDisplayId = nil
        CombatFlowController.setCombatPhase(gameState: gs, .idle)
        MissionStatsStore.shared.resetAll()   // zero memory+disk BEFORE restoring
        for key in statsKeys { UserDefaults.standard.removeObject(forKey: key) }
        for (key, v) in statsSnapshot { UserDefaults.standard.set(v, forKey: key) }
    }

    // MARK: - Turn order (TurnManager unit behavior)

    func testStartCombatBuildsFullDescendingInitiativeOrder() {
        let tm = TurnManager()
        let team = Array(Character.allRunners.prefix(2))
        let foes = [Enemy.corpGuard(), Enemy.securityDrone()]
        tm.startCombat(playerTeam: team, enemies: foes)
        XCTAssertTrue(tm.isCombatActive)
        XCTAssertEqual(tm.turnOrder.count, 4, "every combatant gets exactly one slot")
        let inits = tm.turnOrder.map(\.initiative)
        XCTAssertEqual(inits, inits.sorted(by: >), "turn order sorts by initiative, highest first")
        XCTAssertEqual(tm.roundNumber, 1)
        XCTAssertEqual(tm.currentTurnIndex, 0)
    }

    func testAdvanceTurnWrapsIntoNewRoundExactlyOnce() {
        let tm = TurnManager()
        let team = Array(Character.allRunners.prefix(1))
        tm.startCombat(playerTeam: team, enemies: [Enemy.corpGuard()])
        XCTAssertEqual(tm.roundNumber, 1)
        tm.endCurrentTurn()             // actor 1 done
        XCTAssertEqual(tm.roundNumber, 1, "round holds until the order is exhausted")
        tm.endCurrentTurn()             // actor 2 done -> wrap
        XCTAssertEqual(tm.roundNumber, 2, "completing the order advances the round once")
        XCTAssertEqual(tm.currentTurnIndex, 0)
    }

    // MARK: - End-turn authority latch (duplicate request rejection)

    func testEndTurnIsRejectedDuringEnemyPhase() {
        gs.currentMissionType = .assault
        gs.playerTeam = []
        gs.enemies = []
        CombatFlowController.setCombatPhase(gameState: gs, .enemyResolving)
        let before = gs.currentTurnCount
        gs.endTurn()   // queued tap arriving late — the phase latch must drop it
        XCTAssertEqual(gs.currentTurnCount, before,
                       "end-turn during enemy resolution must be rejected")
    }

    func testEndTurnIsRejectedAfterCombatResolved() {
        gs.currentMissionType = .assault
        CombatFlowController.setCombatPhase(gameState: gs, .combatResolved)
        let before = gs.currentTurnCount
        gs.endTurn()
        XCTAssertEqual(gs.currentTurnCount, before,
                       "end-turn after combat resolution must be rejected")
    }

    func testEndTurnInPlayerPhaseIsAcceptedExactlyOnce() {
        gs.currentMissionType = .assault
        gs.playerTeam = []          // no living runners: accepted, then phase resets
        gs.enemies = []
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        let before = gs.currentTurnCount
        gs.endTurn()
        XCTAssertEqual(gs.currentTurnCount, before + 1,
                       "a valid end-turn advances the turn count exactly once")
    }

    // MARK: - Mission completion fires exactly once

    func testMissionOutcomeFinalizesExactlyOnce() {
        gs.currentMissionType = .assault
        gs.playerTeam = Array(Character.allRunners.prefix(2))
        gs.enemies = []
        gs.missionComplete = false
        gs.combatEnded = false
        gs.currentMissionDisplayId = "Mission001"
        MissionStatsStore.shared.resetAll()
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)

        gs.finalizeCombatFromCombatFlow(won: true, missionLog: "TEST VICTORY")
        XCTAssertEqual(MissionStatsStore.shared.record(for: "Mission001").attempts, 1)
        XCTAssertTrue(gs.isCombatResolvedOrBeyond)
        let wallet = MissionStatsStore.shared.playerNuyen

        // A stray second finalize (double signal) must be swallowed whole:
        // no second attempt, no second payout.
        gs.finalizeCombatFromCombatFlow(won: true, missionLog: "DUPLICATE")
        XCTAssertEqual(MissionStatsStore.shared.record(for: "Mission001").attempts, 1,
                       "duplicate finalize must not record a second victory")
        XCTAssertEqual(MissionStatsStore.shared.playerNuyen, wallet,
                       "duplicate finalize must not pay twice")
    }

    // MARK: - Destructible cover authority

    func testDestroyCoverTileConvertsCoverRecordsAndIgnoresInvalidTargets() {
        gs.currentRoomId = "test_room"
        gs.destroyedCoverByRoom = [:]
        gs.currentMissionTiles = [
            [0, 2, 0],
            [0, 1, 0],
        ]
        gs.destroyCoverTile(x: 1, y: 0)
        XCTAssertEqual(gs.currentMissionTiles[0][1], TileType.floor.rawValue,
                       "cover converts to floor")
        XCTAssertEqual(gs.destroyedCoverByRoom["test_room"], [[1, 0]],
                       "destruction is recorded per-room for re-entry")

        gs.destroyCoverTile(x: 1, y: 1)   // a wall, not cover
        XCTAssertEqual(gs.currentMissionTiles[1][1], 1, "non-cover tiles are untouched")
        gs.destroyCoverTile(x: 99, y: 99) // out of bounds: must not trap
        XCTAssertEqual(gs.destroyedCoverByRoom["test_room"]?.count, 1,
                       "invalid targets record nothing")
    }

    func testApplyDestroyedCoverSurvivesRoomReload() {
        gs.currentRoomId = "test_room"
        gs.destroyedCoverByRoom = ["test_room": [[1, 0]]]
        // Fresh JSON reload would resurrect the crate — re-apply must re-flatten it.
        gs.currentMissionTiles = [[0, 2, 0]]
        gs.applyDestroyedCoverToCurrentTiles(roomId: "test_room")
        XCTAssertEqual(gs.currentMissionTiles[0][1], TileType.floor.rawValue,
                       "destroyed cover must not resurrect on room re-entry")
    }

    func testBarrelDetonationHitsImpactAdjacentBarrelsOnlyAndNeverChains() {
        // Find real barrel coordinates (deterministic hash) in a 20×20 field:
        // one pair of hex-adjacent barrels + one far-away barrel.
        var barrels: [(x: Int, y: Int)] = []
        for y in 0..<20 { for x in 0..<20 where TileMap.isBarrelTile(x: x, y: y) { barrels.append((x, y)) } }
        guard let pair = firstAdjacentPair(in: barrels) else {
            return XCTFail("no adjacent barrel pair in 20×20 — hash function changed?")
        }
        // An impact tile adjacent to A but NOT within blast range of B.
        guard let impact = impactNear(pair.a, excluding: pair.b) else {
            return XCTFail("no impact tile isolates the pair — adjust fixture")
        }
        guard let far = barrels.first(where: {
            CombatMechanics.hexDistance(x1: $0.x, y1: $0.y, x2: pair.a.x, y2: pair.a.y) > 4
        }) else { return XCTFail("no distant barrel found") }

        gs.currentRoomId = "test_room"
        gs.destroyedCoverByRoom = [:]
        gs.playerTeam = []      // nobody standing in the blast: tile logic only
        gs.enemies = []
        var tiles = Array(repeating: Array(repeating: 0, count: 20), count: 20)
        tiles[pair.a.y][pair.a.x] = 2
        tiles[pair.b.y][pair.b.x] = 2
        tiles[far.y][far.x] = 2
        gs.currentMissionTiles = tiles

        gs.detonateBarrelsNear(impactTiles: [(x: impact.x, y: impact.y)])

        XCTAssertEqual(gs.currentMissionTiles[pair.a.y][pair.a.x], 0,
                       "barrel in blast radius must detonate to floor")
        XCTAssertEqual(gs.currentMissionTiles[pair.b.y][pair.b.x], 2,
                       "adjacent barrel OUTSIDE the impact radius must NOT chain-detonate")
        XCTAssertEqual(gs.currentMissionTiles[far.y][far.x], 2,
                       "distant barrel must be untouched")
    }

    func testBarrelDetonationWithNoImpactTilesIsANoOp() {
        gs.currentRoomId = "test_room"
        gs.currentMissionTiles = [[2, 2], [2, 2]]
        gs.playerTeam = []
        gs.enemies = []
        gs.detonateBarrelsNear(impactTiles: [])
        XCTAssertEqual(gs.currentMissionTiles, [[2, 2], [2, 2]])
    }

    // MARK: - fixtures

    private func firstAdjacentPair(in barrels: [(x: Int, y: Int)])
        -> (a: (x: Int, y: Int), b: (x: Int, y: Int))? {
        for i in 0..<barrels.count {
            for j in (i + 1)..<barrels.count {
                if CombatMechanics.hexDistance(x1: barrels[i].x, y1: barrels[i].y,
                                               x2: barrels[j].x, y2: barrels[j].y) == 1 {
                    return (barrels[i], barrels[j])
                }
            }
        }
        return nil
    }

    /// A tile within hex-distance 1 of `a` while > 1 from `b`, so detonating
    /// near `a` can never legally reach `b`.
    private func impactNear(_ a: (x: Int, y: Int), excluding b: (x: Int, y: Int))
        -> (x: Int, y: Int)? {
        for dx in -1...1 {
            for dy in -1...1 {
                let c = (x: a.x + dx, y: a.y + dy)
                guard c.x >= 0, c.y >= 0, c.x < 20, c.y < 20 else { continue }
                if CombatMechanics.hexDistance(x1: c.x, y1: c.y, x2: a.x, y2: a.y) <= 1,
                   CombatMechanics.hexDistance(x1: c.x, y1: c.y, x2: b.x, y2: b.y) > 1 {
                    return c
                }
            }
        }
        return nil
    }
}
#endif
