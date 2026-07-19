import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Spawn placement and seeded replay-encounter tests.
/// Tile legend: 0 floor, 1 wall, 2 cover, 3 door, 4 extraction, 5 terminal.
@MainActor
final class ReplaySpawnTests: XCTestCase {

    // MARK: - Party spawn placement (pure)

    func testGroupSpawnSlotsAreDeterministicDistinctAndWalkable() {
        let map = [
            [1, 1, 1, 1, 1, 1],
            [1, 0, 0, 2, 0, 1],
            [1, 0, 1, 0, 0, 1],
            [1, 1, 1, 1, 1, 1],
        ]
        let anchor = SpawnPoint(x: 1, y: 1)
        let a = MissionSetupService.findGroupSpawnSlots(map: map, anchor: anchor, count: 4)
        let b = MissionSetupService.findGroupSpawnSlots(map: map, anchor: anchor, count: 4)
        XCTAssertEqual(a.map { "\($0.x),\($0.y)" }, b.map { "\($0.x),\($0.y)" },
                       "same inputs must place the party identically")
        XCTAssertEqual(Set(a.map { "\($0.x),\($0.y)" }).count, a.count, "no two runners share a tile")
        for p in a {
            XCTAssertTrue(p.y >= 0 && p.y < map.count && p.x >= 0 && p.x < map[0].count,
                          "spawn (\(p.x),\(p.y)) out of bounds")
            let t = map[p.y][p.x]
            XCTAssertTrue([0, 2, 5].contains(t), "spawn (\(p.x),\(p.y)) on non-walkable tile \(t)")
        }
    }

    func testGroupSpawnSlotsExcludeDoorsExtractionAndOccupiedTiles() {
        let map = [
            [3, 0, 0, 4, 0],
            [0, 0, 0, 0, 0],
        ]
        let occupied: Set<String> = ["1,0"]   // an enemy stands here
        let slots = MissionSetupService.findGroupSpawnSlots(
            map: map, anchor: SpawnPoint(x: 0, y: 0), count: 4, occupied: occupied)
        for p in slots {
            XCTAssertNotEqual(map[p.y][p.x], 3, "runner must not spawn on a door")
            XCTAssertNotEqual(map[p.y][p.x], 4, "runner must not spawn on the extraction pad")
            XCTAssertFalse(occupied.contains("\(p.x),\(p.y)"), "runner must not spawn on an enemy")
        }
    }

    func testGroupSpawnSlotsOnCrampedMapUseAnchorOverflowDeterministically() {
        // Documented fallback contract: when the room genuinely can't fit the
        // team, every DISTINCT walkable tile is used first, and the remainder
        // repeat the anchor (runners stack visually rather than spawning
        // out-of-bounds or on walls).
        let map = [[1, 0, 1], [1, 0, 1]]   // only two walkable tiles
        let anchor = SpawnPoint(x: 1, y: 0)
        let slots = MissionSetupService.findGroupSpawnSlots(map: map, anchor: anchor, count: 4)
        XCTAssertEqual(slots.count, 4, "caller always receives a slot per runner")
        for p in slots {
            XCTAssertTrue(p.y >= 0 && p.y < 2 && p.x >= 0 && p.x < 3, "in bounds")
            XCTAssertEqual(map[p.y][p.x], 0, "walls are never spawn slots, even in overflow")
        }
        let unique = Set(slots.map { "\($0.x),\($0.y)" })
        XCTAssertEqual(unique, ["1,0", "1,1"], "both walkable tiles are used")
        let overflow = slots.dropFirst(unique.count)
        XCTAssertTrue(overflow.allSatisfy { $0.x == anchor.x && $0.y == anchor.y },
                      "overflow runners stack on the anchor, deterministically")
        // And the whole placement is reproducible.
        let again = MissionSetupService.findGroupSpawnSlots(map: map, anchor: anchor, count: 4)
        XCTAssertEqual(again.map { "\($0.x),\($0.y)" }, slots.map { "\($0.x),\($0.y)" })
    }

    // MARK: - NG+ extra enemy placement

    func testNGPlusExtraEnemiesRespectOccupancyFloorAndCount() {
        let store = NGPlusStore.shared
        let savedTier = store.tier
        defer { store.tier = savedTier }

        store.tier = 0
        XCTAssertTrue(MissionSetupService.ngPlusExtraEnemies(
            gameState: GameState.shared, map: [[0, 0], [0, 0]], occupied: []).isEmpty,
            "first playthrough gets no extra enemies")

        store.tier = 1   // extraEnemiesPerRoom == 1
        let map = [
            [1, 1, 1],
            [0, 2, 0],   // one cover tile — extras must land on FLOOR only
            [0, 0, 0],
        ]
        let occupied: Set<String> = ["0,2", "1,2", "2,2", "0,1"]  // bottom row + one more taken
        let extras = MissionSetupService.ngPlusExtraEnemies(
            gameState: GameState.shared, map: map, occupied: occupied)
        XCTAssertEqual(extras.count, 1)
        for e in extras {
            XCTAssertEqual(map[e.positionY][e.positionX], 0, "extra enemy must stand on floor")
            XCTAssertFalse(occupied.contains("\(e.positionX),\(e.positionY)"),
                           "extra enemy must not stack on an occupied tile")
        }
    }

    // MARK: - Seeded replay squad rerolls

    private let statsKeys = [
        "HexWire.MissionStats.v1", "HexWire.MissionStats.v1.lastGood",
        "HexWire.PlayerNuyen.v1", "HexWire.PaidThisRun.v1",
    ]
    private var statsSnapshot: [String: Any] = [:]

    private func snapshotStats() {
        statsSnapshot = [:]
        for key in statsKeys {
            if let v = UserDefaults.standard.object(forKey: key) { statsSnapshot[key] = v }
        }
    }

    private func restoreStats() {
        MissionStatsStore.shared.resetAll()   // zero memory+disk BEFORE restoring
        for key in statsKeys { UserDefaults.standard.removeObject(forKey: key) }
        for (key, v) in statsSnapshot { UserDefaults.standard.set(v, forKey: key) }
        RoomManager.shared.unloadMission()
        GameState.shared.currentMissionDisplayId = nil
        GameState.shared.missionAttemptId = 0
    }

    /// Load a real authored mission and return a room with enough enemies to
    /// make reroll assertions meaningful.
    private func loadReplayFixture() throws -> Room {
        snapshotStats()
        guard let mission = RoomManager.shared.loadMission(named: "Mission005") else {
            throw XCTSkip("Mission005 JSON not bundled in test host")
        }
        guard let room = mission.rooms.first(where: { $0.enemies.count >= 3 }) else {
            throw XCTSkip("no room with ≥3 enemies in Mission005")
        }
        GameState.shared.currentMissionDisplayId = "Mission005"
        MissionStatsStore.shared.resetAll()
        // attempts > 0 marks this a REPLAY, which arms the reroll path.
        MissionStatsStore.shared.recordVictory(missionId: "Mission005", score: 1)
        return room
    }

    func testFirstClearKeepsAuthoredSquadVerbatim() throws {
        snapshotStats()
        defer { restoreStats() }
        guard let mission = RoomManager.shared.loadMission(named: "Mission005"),
              let room = mission.rooms.first(where: { $0.enemies.count >= 3 }) else {
            throw XCTSkip("Mission005 fixture unavailable")
        }
        GameState.shared.currentMissionDisplayId = "Mission005"
        MissionStatsStore.shared.resetAll()   // zero attempts = first clear
        let squad = MissionSetupService.replaySquad(for: room, gameState: GameState.shared)
        XCTAssertEqual(squad.map(\.type), room.enemies.map(\.type),
                       "first clears must field the hand-authored squad")
    }

    func testReplaySquadIsDeterministicForSameAttempt() throws {
        defer { restoreStats() }
        let room = try loadReplayFixture()
        GameState.shared.missionAttemptId = 424_242
        let a = MissionSetupService.replaySquad(for: room, gameState: GameState.shared)
        let b = MissionSetupService.replaySquad(for: room, gameState: GameState.shared)
        XCTAssertEqual(a.map(\.type), b.map(\.type),
                       "same attempt + room must rebuild the same squad (no door-flap scumming)")
    }

    func testReplaySquadKeepsPositionsDelaysAndThreatBudget() throws {
        defer { restoreStats() }
        let room = try loadReplayFixture()
        GameState.shared.missionAttemptId = 77
        let squad = MissionSetupService.replaySquad(for: room, gameState: GameState.shared)
        XCTAssertEqual(squad.count, room.enemies.count, "reroll never adds or removes slots")

        guard let mission = RoomManager.shared.currentMission else { return XCTFail() }
        var authoredPool = Set<String>()
        for r in mission.rooms {
            for s in r.enemies where MissionSetupService.spawnCost[s.type] != nil {
                authoredPool.insert(s.type)
            }
        }
        for (orig, rolled) in zip(room.enemies, squad) {
            XCTAssertEqual(rolled.x, orig.x, "authored spatial design is preserved")
            XCTAssertEqual(rolled.y, orig.y)
            XCTAssertEqual(rolled.delay, orig.delay)
            if let origCost = MissionSetupService.spawnCost[orig.type] {
                guard let newCost = MissionSetupService.spawnCost[rolled.type] else {
                    return XCTFail("rerolled type \(rolled.type) has no cost — outside the budget table")
                }
                XCTAssertLessThanOrEqual(abs(newCost - origCost), 1,
                                         "\(orig.type)→\(rolled.type) breaks the ±1 threat budget")
                XCTAssertTrue(authoredPool.contains(rolled.type),
                              "\(rolled.type) was never authored in this mission")
            } else {
                XCTAssertEqual(rolled.type, orig.type,
                               "boss/unknown slots must never reroll")
            }
        }
    }

    func testDifferentAttemptsProduceVariation() throws {
        defer { restoreStats() }
        let room = try loadReplayFixture()
        var outcomes = Set<String>()
        for attempt in 1...30 {
            GameState.shared.missionAttemptId = attempt
            let squad = MissionSetupService.replaySquad(for: room, gameState: GameState.shared)
            outcomes.insert(squad.map(\.type).joined(separator: ","))
        }
        XCTAssertGreaterThan(outcomes.count, 1,
                             "30 attempts should not all roll the identical squad")
    }
}
#endif
