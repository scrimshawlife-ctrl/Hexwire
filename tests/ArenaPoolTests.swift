import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Arena-pool certification: the 10 replay rooms are structurally sound,
/// chained gauntlet floors are traversable with an extraction door at the
/// end, no story content leaks into gauntlet briefings, and the randomized
/// music pool only references real tracks.
@MainActor
final class ArenaPoolTests: XCTestCase {

    private let gauntletKeys = [
        "HexWire.Gauntlet.CurrentFloor.v1", "HexWire.Gauntlet.BestFloor.v1",
        "HexWire.Gauntlet.FloorArenas.v1", "HexWire.Gauntlet.FloorMission.v1",
    ]
    private var snapshot: [String: Any] = [:]

    override func setUp() async throws {
        snapshot = [:]
        for k in gauntletKeys {
            if let v = UserDefaults.standard.object(forKey: k) { snapshot[k] = v }
        }
    }

    override func tearDown() async throws {
        GauntletStore.shared.disarmForNonGauntletLoad()
        ContractStore.shared.disarmForNonContractLoad()
        for k in gauntletKeys { UserDefaults.standard.removeObject(forKey: k) }
        for (k, v) in snapshot { UserDefaults.standard.set(v, forKey: k) }
        RoomManager.shared.unloadMission()
    }

    private func hexNeighbors(_ x: Int, _ y: Int) -> [(Int, Int)] {
        x % 2 == 0
            ? [(x, y-1), (x, y+1), (x-1, y-1), (x-1, y), (x+1, y-1), (x+1, y)]
            : [(x, y-1), (x, y+1), (x-1, y), (x-1, y+1), (x+1, y), (x+1, y+1)]
    }

    func testPoolShipsTwentyStructurallySoundArenas() {
        let pool = ArenaPool.load()
        XCTAssertEqual(pool.count, 20)
        XCTAssertEqual(Set(pool.map(\.room.id)).count, 20, "arena ids unique")
        for e in pool {
            let m = e.room.map
            XCTAssertEqual(m.count, 12, "\(e.room.id): 12 rows")
            XCTAssertTrue(m.allSatisfy { $0.count == 7 }, "\(e.room.id): 7 cols")
            XCTAssertEqual(m[e.exitDoor.y][e.exitDoor.x], TileType.door.rawValue,
                           "\(e.room.id): exitDoor marks the door tile")
            XCTAssertEqual(m.flatMap { $0 }.filter { $0 == TileType.door.rawValue }.count, 1,
                           "\(e.room.id): exactly one door")
            let spawn = e.room.playerSpawn
            XCTAssertEqual(m[spawn.y][spawn.x], TileType.floor.rawValue,
                           "\(e.room.id): spawn on floor")
            // Connectivity: spawn must reach the exit door hex-adjacently.
            let walkable: Set<Int> = [0, 2, 3, 5]
            var seen: Set<[Int]> = [[spawn.x, spawn.y]]
            var queue = [[spawn.x, spawn.y]]
            while let cur = queue.popLast() {
                for (nx, ny) in hexNeighbors(cur[0], cur[1])
                where ny >= 0 && ny < 12 && nx >= 0 && nx < 7
                   && walkable.contains(m[ny][nx]) && !seen.contains([nx, ny]) {
                    seen.insert([nx, ny]); queue.append([nx, ny])
                }
            }
            XCTAssertTrue(seen.contains([e.exitDoor.x, e.exitDoor.y]),
                          "\(e.room.id): exit door unreachable from spawn")
            // Squads: known types on legal tiles.
            XCTAssertFalse(e.room.enemies.isEmpty, "\(e.room.id): has a squad")
            for spawnDef in e.room.enemies {
                XCTAssertTrue(MissionCertificationTests.knownSpawnTypes.contains(spawnDef.type),
                              "\(e.room.id): unknown type \(spawnDef.type)")
                XCTAssertTrue([0, 2].contains(m[spawnDef.y][spawnDef.x]),
                              "\(e.room.id): \(spawnDef.type) on illegal tile")
            }
            XCTAssertNil(e.room.bossSpawn, "\(e.room.id): no scripted bosses in the pool")
        }
    }

    func testChainedMissionLinksRoomsAndEndsInExtractionDoor() {
        let ids = ["arena_01", "arena_05", "arena_10"]
        guard let mission = ArenaPool.chainedMission(
            id: "TestChain", title: "T", briefing: "b", summary: "s",
            difficulty: "HIGH", arenaIds: ids) else { return XCTFail("chain failed") }
        XCTAssertEqual(mission.rooms.map(\.id), ids)
        for (i, room) in mission.rooms.enumerated() {
            if i < mission.rooms.count - 1 {
                XCTAssertEqual(room.connections.count, 1, "\(room.id): one onward door")
                XCTAssertEqual(room.connections[0].targetRoomId, ids[i + 1])
                XCTAssertEqual(room.map[room.connections[0].triggerTileY][room.connections[0].triggerTileX],
                               TileType.door.rawValue, "\(room.id): trigger sits on the door tile")
            } else {
                XCTAssertTrue(room.connections.isEmpty, "last room is sealed")
                XCTAssertNotNil(room.extractionPoint, "last room extracts")
                XCTAssertFalse(room.map.contains { $0.contains(TileType.door.rawValue) },
                               "last room's door became the extraction tile")
                XCTAssertTrue(room.map.contains { $0.contains(TileType.extraction.rawValue) })
            }
        }
        XCTAssertEqual(mission.extractionType, "door")
    }

    func testGauntletFloorBuildsFromArenasWithNoStoryReuse() throws {
        for k in gauntletKeys { UserDefaults.standard.removeObject(forKey: k) }
        guard let mission = MissionLoader.shared.loadMultiRoomMission(
            named: GauntletStore.gauntletMissionId) else {
            throw XCTSkip("bundle resources unavailable")
        }
        XCTAssertEqual(mission.id, GauntletStore.gauntletMissionId)
        XCTAssertTrue(mission.title.hasPrefix("GAUNTLET — FLOOR"), "generic pit title, no story name")
        XCTAssertTrue(mission.rooms.allSatisfy { $0.id.hasPrefix("arena_") },
                      "floors are arena rooms, not story rooms")
        XCTAssertTrue((2...3).contains(mission.rooms.count))
        XCTAssertNotNil(mission.rooms.last?.extractionPoint, "extraction door on the last room")
        XCTAssertTrue(GauntletStore.shared.isActive)
        // The floor's arena picks are stable across briefing re-entry.
        guard let again = MissionLoader.shared.loadMultiRoomMission(
            named: GauntletStore.gauntletMissionId) else { return XCTFail() }
        XCTAssertEqual(again.rooms.map(\.id), mission.rooms.map(\.id),
                       "re-entering the briefing must not reroll the floor")
        // A story-mission load stands the gauntlet down.
        _ = MissionLoader.shared.loadMultiRoomMission(named: "Mission001")
        XCTAssertFalse(GauntletStore.shared.isActive)
    }

    func testRandomizedMusicPoolOnlyReferencesRealTracks() throws {
        let root = Bundle.main.resourcePath ?? ""
        let devRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        for name in MusicManager.randomizedRunPool {
            let bundled = FileManager.default.fileExists(atPath: "\(root)/Sounds/music/\(name).mp3")
            let inRepo = FileManager.default.fileExists(atPath: "\(devRoot)/Sounds/music/\(name).mp3")
            XCTAssertTrue(bundled || inRepo, "music pool references missing track: \(name)")
        }
    }

    func testContractArenaPickIsDeterministicPerSeed() {
        XCTAssertEqual(ArenaPool.arenaId(forSeed: 12345), ArenaPool.arenaId(forSeed: 12345))
        XCTAssertNotNil(ArenaPool.arenaId(forSeed: 1))
    }
}
#endif
