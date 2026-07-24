import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Player-input-path certification.
///
/// WP6's MissionCertificationTests drive AUTHORITY directly — `applyRoomEntry`
/// to walk rooms, `requestExtractionResolution` to extract. A real player never
/// calls those. They move a runner onto a tile, and the move commit decides
/// what that tile means. That translation layer had no coverage, and it is
/// exactly where side contracts broke: extraction resolved perfectly at the
/// authority level while walking onto the pad reached it, so contracts were
/// uncompletable with every test green (2026-07-23 device pass).
///
/// These tests enter one layer up — through `moveCharacter`, the same call the
/// tap handler makes — and assert that stepping on a tile does the thing the
/// tile promises. Doors are deliberately excluded: they are tap-only by design
/// (BattleScene bypasses moveCharacter there so a transition can't trigger
/// endTurn mid-fade).
@MainActor
final class StepOnSemanticsTests: XCTestCase {

    private let gs = GameState.shared
    private let persistenceKeys = [
        "HexWire.MissionStats.v1", "HexWire.MissionStats.v1.lastGood",
        "HexWire.PlayerNuyen.v1", "HexWire.PaidThisRun.v1",
        "HexWire.Roster.v1", "HexWire.Roster.v1.lastGood",
        "HexWire.NGPlusTier.v1", "HexWire.FactionAttention.v1",
    ]
    private var snapshot: [String: Any] = [:]
    private var savedTeam: [Character] = []
    private var savedTier = 0

    override func setUp() async throws {
        snapshot = [:]
        for key in persistenceKeys {
            if let v = UserDefaults.standard.object(forKey: key) { snapshot[key] = v }
        }
        savedTeam = gs.playerTeam
        savedTier = NGPlusStore.shared.tier
        MissionStatsStore.shared.resetAll()
        NGPlusStore.shared.tier = 0
        MissionStatsStore.shared.resetFactionAttention()
        RosterStore.shared.reset()
        gs.factionAttention = [.corp: 0, .gang: 0, .unknown: 0]
    }

    override func tearDown() async throws {
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

    /// Walk the party to the mission's extraction room and clear everything on
    /// the way, leaving the run one player move away from finishing.
    ///
    /// Room traversal uses authority (`applyRoomEntry`) deliberately — that is
    /// SETUP, and it is already certified by WP6. The thing under test is the
    /// final step onto the pad, which goes through `moveCharacter`.
    ///
    /// `clearFinalRoom: false` leaves the last room's opposition alive so the
    /// negative cases have something to be blocked by.
    @discardableResult
    private func walkToExtractionRoom(mission id: String = "Mission001",
                                      clearFinalRoom: Bool = true) throws -> Character {
        guard let mission = MissionLoader.shared.loadMultiRoomMission(named: id),
              RoomManager.shared.loadMission(named: id) != nil else {
            throw XCTSkip("mission JSONs not bundled")
        }
        _ = gs.prepareMissionForCombat(named: id)
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false

        var extractionRoom: Room?
        for (i, room) in mission.rooms.enumerated() {
            if i > 0 {
                gs.applyRoomEntry(to: room, enemies: [], pendingSpawns: [],
                                  spawnAnchor: room.playerSpawn)
            }
            let isFinal = RoomManager.shared.roomHasExtraction(room)
            if isFinal { extractionRoom = room }
            // Leave the final room hot when the test asked for it. applyRoomEntry
            // above was handed an empty enemy list (it is a setup call), so the
            // opposition has to be built here or "enemies alive" would be a lie.
            if isFinal && !clearFinalRoom {
                gs.enemies = room.enemies.map { spawn in
                    let e = MissionSetupService.makeEnemy(gameState: gs,
                                                          for: spawn.type,
                                                          archetype: .enforcer)
                    e.positionX = spawn.x
                    e.positionY = spawn.y
                    return e
                }
                break
            }
            gs.pendingSpawns = []
            for enemy in gs.enemies {
                enemy.currentHP = 0
                gs.handleEnemyKilledByEnvironment(enemy, cause: "test")
            }
            _ = RoomManager.shared.markCurrentRoomCleared()
        }
        guard let finalRoom = extractionRoom else {
            throw XCTSkip("\(id): no room exposes an extraction objective")
        }
        if RoomManager.shared.currentRoom?.id != finalRoom.id {
            gs.applyRoomEntry(to: finalRoom, enemies: [], pendingSpawns: [],
                              spawnAnchor: finalRoom.playerSpawn)
            if clearFinalRoom {
                gs.pendingSpawns = []
                gs.enemies.forEach { $0.currentHP = 0 }
                _ = RoomManager.shared.markCurrentRoomCleared()
            }
        }
        guard let runner = gs.playerTeam.first(where: { $0.isAlive }) else {
            throw XCTSkip("no living runner")
        }
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        gs.characterHasMovedThisTurn[runner.id] = false
        runner.hasActedThisRound = false
        return runner
    }

    /// Reset the per-turn move budget so a test can take another step.
    private func refreshMove(_ runner: Character) {
        gs.characterHasMovedThisTurn[runner.id] = false
        runner.hasActedThisRound = false
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
    }

    private func firstTile(_ type: TileType) -> (x: Int, y: Int)? {
        for (y, row) in gs.currentMissionTiles.enumerated() {
            if let x = row.firstIndex(of: type.rawValue) { return (x: x, y: y) }
        }
        return nil
    }

    private var someoneIsOnThePad: Bool {
        gs.livingPlayers.contains { $0.positionX == gs.extractionX && $0.positionY == gs.extractionY }
    }

    private var runResolved: Bool {
        gs.extractionAnimationInProgress || gs.combatEnded || gs.missionComplete
    }

    // MARK: - Extraction

    /// THE regression. Walking onto an armed pad must end the run, with no tap
    /// and no enemy phase — the only two things that used to trigger it.
    func testWalkingOntoArmedExtractionPadResolvesTheRun() throws {
        let runner = try walkToExtractionRoom()
        XCTAssertGreaterThanOrEqual(gs.extractionX, 0, "extraction coords must be set")
        if gs.missionRequiresData && !gs.dataAcquired {
            _ = gs.requestObjectiveDataAcquired(source: "step-on-test")
        }
        XCTAssertTrue(RoomManager.shared.isExtractionActive(),
                      "a fully cleared mission must arm extraction")

        gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)

        XCTAssertTrue(someoneIsOnThePad, "the move committed")
        XCTAssertTrue(runResolved, "stepping onto an armed pad must resolve the run")
    }

    /// The mirror case. A pad that is NOT armed must stay inert — stepping on
    /// it cannot end a run that still has enemies in it.
    func testWalkingOntoPadWithEnemiesAliveDoesNotResolve() throws {
        let runner = try walkToExtractionRoom(clearFinalRoom: false)
        XCTAssertGreaterThanOrEqual(gs.extractionX, 0, "extraction coords must be set")
        try XCTSkipIf(gs.livingEnemies.isEmpty, "final room authored with no enemies")

        gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)

        XCTAssertFalse(runResolved,
                       "a pad must not extract while the room still has living enemies")
    }

    /// Stepping on and off and on again must not stack two resolutions — the
    /// adjudicator runs on EVERY move commit now, so idempotency matters.
    func testRepeatedStepsOnPadResolveOnlyOnce() throws {
        let runner = try walkToExtractionRoom()
        XCTAssertGreaterThanOrEqual(gs.extractionX, 0, "extraction coords must be set")
        if gs.missionRequiresData && !gs.dataAcquired {
            _ = gs.requestObjectiveDataAcquired(source: "step-on-test")
        }
        XCTAssertTrue(RoomManager.shared.isExtractionActive(),
                      "a fully cleared mission must arm extraction")

        gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)
        XCTAssertTrue(runResolved)
        let firstFlag = gs.extractionAnimationInProgress

        refreshMove(runner)
        gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)

        XCTAssertEqual(gs.extractionAnimationInProgress, firstFlag,
                       "re-stepping must not queue a second extraction")
    }

    /// A move onto ordinary floor must not resolve anything. Guards against an
    /// over-eager adjudicator that fires on any move once the room is clear.
    func testWalkingOntoPlainFloorResolvesNothing() throws {
        let runner = try walkToExtractionRoom()
        guard let floor = firstTile(.floor) else { throw XCTSkip("no floor tile") }
        try XCTSkipIf(floor.x == gs.extractionX && floor.y == gs.extractionY,
                      "picked the pad by accident")

        gs.moveCharacter(id: runner.id, toTileX: floor.x, toTileY: floor.y)

        XCTAssertFalse(runResolved, "stepping on plain floor must not end the run")
    }

    /// Data-gated missions must hold the pad shut until the terminal is cracked.
    /// Sweeps for a mission that actually carries the gate rather than assuming
    /// M1 does — asserting against a mission with no terminal proves nothing.
    func testDataGatedMissionDoesNotExtractBeforeTheTerminalIsCracked() throws {
        var gated = 0
        for id in MissionCertificationTests.allMissionIds {
            RoomManager.shared.unloadMission()
            gs.extractionAnimationInProgress = false
            gs.missionComplete = false
            gs.combatEnded = false

            guard let runner = try? walkToExtractionRoom(mission: id) else { continue }
            guard gs.missionRequiresData, !gs.dataAcquired, gs.extractionX >= 0 else { continue }
            gated += 1

            gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)

            XCTAssertFalse(runResolved,
                           "\(id): extraction must stay locked until the data objective is met")

            // And once the objective IS met, the same step must go through.
            _ = gs.requestObjectiveDataAcquired(source: "step-on-test")
            refreshMove(runner)
            gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)
            XCTAssertTrue(runResolved,
                          "\(id): with data acquired, stepping on the pad must resolve")
        }
        XCTAssertGreaterThan(gated, 0, "no shipped mission exercised the data gate")
    }

    // MARK: - Move budget

    /// The step-on hook must not become a way to move twice in one turn.
    func testSecondMoveInSameTurnIsRejected() throws {
        let runner = try walkToExtractionRoom()
        guard let floor = firstTile(.floor) else { throw XCTSkip("no floor tile") }
        gs.moveCharacter(id: runner.id, toTileX: floor.x, toTileY: floor.y)
        let after = (x: runner.positionX, y: runner.positionY)

        // No refreshMove() — the budget is spent.
        gs.moveCharacter(id: runner.id, toTileX: floor.x + 1, toTileY: floor.y)

        XCTAssertEqual(runner.positionX, after.x, "second move in a turn must be refused")
        XCTAssertEqual(runner.positionY, after.y, "second move in a turn must be refused")
    }

    // MARK: - Cross-mission sweep

    /// Every shipped mission whose opening room has a pad must extract on a
    /// walk-on. Catches a mission-specific data/geometry quirk that a single
    /// M1 test would miss.
    func testEveryMissionWithAnOpeningPadExtractsOnWalkOn() throws {
        var checked = 0
        for id in MissionCertificationTests.allMissionIds {
            RoomManager.shared.unloadMission()
            gs.extractionAnimationInProgress = false
            gs.missionComplete = false
            gs.combatEnded = false

            guard let runner = try? walkToExtractionRoom(mission: id) else { continue }
            XCTAssertGreaterThanOrEqual(gs.extractionX, 0, "\(id): extraction coords unset")
            if gs.missionRequiresData && !gs.dataAcquired {
                _ = gs.requestObjectiveDataAcquired(source: "sweep")
            }
            XCTAssertTrue(RoomManager.shared.isExtractionActive(),
                          "\(id): a fully cleared mission must arm extraction")

            gs.moveCharacter(id: runner.id, toTileX: gs.extractionX, toTileY: gs.extractionY)
            XCTAssertTrue(runResolved, "\(id): walking onto the armed pad must resolve the run")
            checked += 1
        }
        try XCTSkipIf(checked == 0, "no mission exposed an armed pad in its opening room")
    }
}
#endif
