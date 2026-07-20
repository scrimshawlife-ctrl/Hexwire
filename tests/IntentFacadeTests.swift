import XCTest
#if canImport(HexWire)
@testable import HexWire

/// WP4 safeguards: every migrated intent path gets accepted / rejected /
/// duplicate / invalid-phase / invalid-actor / invalid-destination /
/// exactly-once coverage, exercised through the real GameState authority.
@MainActor
final class IntentFacadeTests: XCTestCase {

    private let gs = GameState.shared

    private var savedTiles: [[Int]] = []
    private var savedTeam: [Character] = []
    private var savedEnemies: [Enemy] = []
    private var savedMissionType: MissionType = .stealth
    private var savedMoved: [UUID: Bool] = [:]

    override func setUp() async throws {
        savedTiles = gs.currentMissionTiles
        savedTeam = gs.playerTeam
        savedEnemies = gs.enemies
        savedMissionType = gs.currentMissionType
        savedMoved = gs.characterHasMovedThisTurn
        gs.currentMissionType = .assault
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false
        gs.combatOutcome = .none   // stale terminal outcomes re-latch missionComplete via syncLegacyState
    }

    override func tearDown() async throws {
        gs.currentMissionTiles = savedTiles
        gs.playerTeam = savedTeam
        gs.enemies = savedEnemies
        gs.currentMissionType = savedMissionType
        gs.characterHasMovedThisTurn = savedMoved
        gs.missionComplete = false
        gs.combatEnded = false
        gs.extractionAnimationInProgress = false
        gs.combatOutcome = .none   // stale terminal outcomes re-latch missionComplete via syncLegacyState
        gs.selectedCharacterId = nil
        gs.activeCharacterId = nil
        gs.targetCharacterId = nil
        CombatFlowController.setCombatPhase(gameState: gs, .idle)
        RoomManager.shared.unloadMission()
    }

    // MARK: - requestEndTurn

    func testEndTurnAcceptedInPlayerPhase() {
        gs.playerTeam = []
        gs.enemies = []
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        let before = gs.currentTurnCount
        XCTAssertEqual(gs.requestEndTurn(), .accepted)
        XCTAssertEqual(gs.currentTurnCount, before + 1)
    }

    func testEndTurnRejectedInEnemyPhaseAndAfterResolution() {
        CombatFlowController.setCombatPhase(gameState: gs, .enemyResolving)
        XCTAssertFalse(gs.requestEndTurn().isAccepted, "duplicate during enemy phase")
        CombatFlowController.setCombatPhase(gameState: gs, .combatResolved)
        XCTAssertFalse(gs.requestEndTurn().isAccepted, "after resolution")
    }

    func testEndTurnRejectedWhenMissionOver() {
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        gs.missionComplete = true
        let before = gs.currentTurnCount
        XCTAssertFalse(gs.requestEndTurn().isAccepted)
        XCTAssertEqual(gs.currentTurnCount, before, "no turn advance after mission end")
    }

    // MARK: - requestMove

    private func makeMoveFixture() -> Character {
        let runner = Character.allRunners[0]
        runner.currentHP = runner.maxHP
        runner.hasActedThisRound = false
        runner.positionX = 0; runner.positionY = 0
        gs.playerTeam = [runner]
        gs.enemies = []
        gs.characterHasMovedThisTurn = [:]
        gs.currentMissionTiles = [
            [0, 0, 1, 3],
            [0, 0, 0, 0],
        ]
        CombatFlowController.setCombatPhase(gameState: gs, .playerInput)
        return runner
    }

    func testMoveAcceptedUpdatesPositionExactlyOnce() {
        let runner = makeMoveFixture()
        XCTAssertEqual(gs.requestMove(unitID: runner.id, toTileX: 1, toTileY: 1), .accepted)
        XCTAssertEqual(runner.positionX, 1)
        XCTAssertEqual(runner.positionY, 1)
        // Duplicate move the same turn: rejected, position unchanged.
        XCTAssertFalse(gs.requestMove(unitID: runner.id, toTileX: 0, toTileY: 1).isAccepted)
        XCTAssertEqual(runner.positionX, 1, "second move this turn must not mutate position")
    }

    func testMoveRejectsInvalidActorDeadActorAndWrongPhase() {
        let runner = makeMoveFixture()
        XCTAssertFalse(gs.requestMove(unitID: UUID(), toTileX: 1, toTileY: 1).isAccepted,
                       "unknown actor")
        runner.currentHP = 0
        runner.status = .dead
        XCTAssertFalse(gs.requestMove(unitID: runner.id, toTileX: 1, toTileY: 1).isAccepted,
                       "dead actor")
        runner.currentHP = runner.maxHP
        runner.status = .wounded
        CombatFlowController.setCombatPhase(gameState: gs, .enemyResolving)
        XCTAssertFalse(gs.requestMove(unitID: runner.id, toTileX: 1, toTileY: 1).isAccepted,
                       "no player input during enemy phase")
    }

    func testMoveRejectsInvalidDestinations() {
        let runner = makeMoveFixture()
        XCTAssertFalse(gs.requestMove(unitID: runner.id, toTileX: 9, toTileY: 9).isAccepted,
                       "out of bounds")
        XCTAssertFalse(gs.requestMove(unitID: runner.id, toTileX: 2, toTileY: 0).isAccepted,
                       "wall")
        XCTAssertFalse(gs.requestMove(unitID: runner.id, toTileX: 3, toTileY: 0).isAccepted,
                       "door tiles route through transitions")
        XCTAssertEqual(runner.positionX, 0, "rejected moves never mutate position")
        XCTAssertNil(gs.characterHasMovedThisTurn[runner.id],
                     "rejected moves must not consume the move budget")
    }

    // MARK: - requestAttack

    func testAttackRejectedOutsidePlayerPhase() {
        gs.playerTeam = []
        gs.enemies = []
        CombatFlowController.setCombatPhase(gameState: gs, .enemyResolving)
        XCTAssertFalse(gs.requestAttack().isAccepted)
    }

    // MARK: - requestTargetSelection / requestSelectionCleared

    func testTargetSelectionValidatesSelectionAndTarget() {
        let runner = Character.allRunners[0]
        let foe = Enemy.corpGuard()
        gs.playerTeam = [runner]
        gs.enemies = [foe]
        gs.selectedCharacterId = nil
        gs.activeCharacterId = nil
        gs.targetCharacterId = nil

        XCTAssertFalse(gs.requestTargetSelection(enemyId: foe.id).isAccepted,
                       "no character selected → rejected")
        gs.selectedCharacterId = runner.id
        XCTAssertFalse(gs.requestTargetSelection(enemyId: UUID()).isAccepted,
                       "unknown enemy → rejected")
        foe.currentHP = 0
        XCTAssertFalse(gs.requestTargetSelection(enemyId: foe.id).isAccepted,
                       "dead enemy → rejected")
        foe.currentHP = foe.maxHP
        XCTAssertEqual(gs.requestTargetSelection(enemyId: foe.id), .accepted)
        XCTAssertEqual(gs.targetCharacterId, foe.id)
        // Duplicate re-target of the same enemy is a legal no-op re-accept.
        XCTAssertEqual(gs.requestTargetSelection(enemyId: foe.id), .accepted)
        XCTAssertEqual(gs.targetCharacterId, foe.id)
    }

    func testSelectionClearedIsIdempotent() {
        gs.selectedCharacterId = UUID()
        gs.activeCharacterId = UUID()
        XCTAssertEqual(gs.requestSelectionCleared(), .accepted)
        XCTAssertNil(gs.selectedCharacterId)
        XCTAssertNil(gs.activeCharacterId)
        XCTAssertEqual(gs.requestSelectionCleared(), .accepted, "duplicate clear is harmless")
    }

    // MARK: - requestObjectiveDataAcquired (exactly once)

    func testObjectiveDataAcquiredExactlyOnce() {
        gs.dataAcquired = false
        XCTAssertEqual(gs.requestObjectiveDataAcquired(source: "test"), .accepted)
        XCTAssertTrue(gs.dataAcquired)
        XCTAssertFalse(gs.requestObjectiveDataAcquired(source: "test").isAccepted,
                       "duplicate objective report must be rejected")
        XCTAssertTrue(gs.dataAcquired, "flag stays set")
        gs.dataAcquired = false
    }

    // MARK: - requestExtractionSequenceCompleted (exactly once)

    func testExtractionSequenceCompletionRequiresInFlightAndFiresOnce() {
        gs.playerTeam = []
        gs.enemies = []
        XCTAssertFalse(gs.requestExtractionSequenceCompleted().isAccepted,
                       "nothing in flight → rejected")
        // In-flight, but combat already ended: the flag clears and finalize's
        // internal latch (guard !combatEnded) swallows the second finalize —
        // state converges without a duplicate payout.
        gs.extractionAnimationInProgress = true
        gs.combatEnded = true
        XCTAssertEqual(gs.requestExtractionSequenceCompleted(), .accepted)
        XCTAssertFalse(gs.extractionAnimationInProgress)
        XCTAssertFalse(gs.requestExtractionSequenceCompleted().isAccepted,
                       "duplicate completion signal must be rejected")
        gs.combatEnded = false
    }

    // MARK: - applyRoomEntry (room-transition authority)

    func testApplyRoomEntrySyncsAuthorityStateAndExtractionObjective() throws {
        guard let mission = RoomManager.shared.loadMission(named: "Mission005"),
              mission.rooms.count >= 2 else {
            throw XCTSkip("Mission005 fixture unavailable")
        }
        let targetRoom = mission.rooms[1]
        let runner = Character.allRunners[0]
        gs.playerTeam = [runner]
        gs.destroyedCoverByRoom = [:]

        let foe = Enemy.corpGuard()
        foe.positionX = 2; foe.positionY = 2
        gs.applyRoomEntry(to: targetRoom,
                          enemies: [foe],
                          pendingSpawns: [],
                          spawnAnchor: targetRoom.playerSpawn)

        XCTAssertEqual(gs.currentRoomId, targetRoom.id, "authority room id syncs")
        XCTAssertFalse(gs.firstKillProcessedInRoom, "first-kill tracking resets")
        XCTAssertTrue(gs.enemies.contains(where: { $0.id == foe.id }),
                      "constructed spawn list installed")
        XCTAssertEqual(gs.currentMissionTiles, targetRoom.map, "live tile map updated")
        XCTAssertEqual(RoomManager.shared.currentRoom?.id, targetRoom.id,
                       "room manager transition completed")
        // Extraction objective follows the documented priority chain.
        if let explicit = targetRoom.extractionPoint {
            XCTAssertEqual(gs.extractionX, explicit.x)
            XCTAssertEqual(gs.extractionY, explicit.y)
        } else if let embedded = GameState.firstExtractionTile(in: targetRoom.map) {
            XCTAssertEqual(gs.extractionX, embedded.x)
            XCTAssertEqual(gs.extractionY, embedded.y)
        } else if let conn = targetRoom.connections.first {
            XCTAssertEqual(gs.extractionX, conn.triggerTileX)
            XCTAssertEqual(gs.extractionY, conn.triggerTileY)
        }
        // The squad landed on walkable tiles of the new room.
        XCTAssertTrue([0, 2, 5].contains(targetRoom.map[runner.positionY][runner.positionX]),
                      "squad placement stays on walkable tiles")
    }
}
#endif
