import XCTest
#if canImport(HexWire)
@testable import HexWire

/// WP6 logic-level mission certification: drives the REAL authority pipeline
/// (prepareMissionForCombat → room walk via applyRoomEntry → clear → extract
/// → finalize → persist) for every shipped multi-room mission. Visual/touch
/// layers are certified separately (simulator launch smoke + device pass) —
/// see docs/audit/MissionCertificationMatrix.md.
@MainActor
final class MissionCertificationTests: XCTestCase {

    static let allMissionIds = ["Mission001", "Mission002", "Mission003",
                                "Mission004", "Mission005", "Mission006"]

    /// Union of MissionSetupService.makeEnemy and BattleScene's factory switch.
    static let knownSpawnTypes: Set<String> = [
        "guard", "drone", "elite", "mage", "bossmage", "healer", "mech",
        "sniper", "bruiser", "spider", "riot", "turret", "rigger", "netrunner",
        "grenadier", "juggernaut", "infiltrator", "repairdrone", "sprayer",
        "corp", "bosscorp", "exec",
    ]
    static let knownBossTypes: Set<String> = ["agi", "corp", "mech"]

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
        // Deterministic baseline: first playthrough, zero attention, no stats.
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
        gs.combatOutcome = .none   // stale terminal outcomes re-latch missionComplete via syncLegacyState
        gs.dataAcquired = false
        gs.currentMissionDisplayId = nil
        CombatFlowController.setCombatPhase(gameState: gs, .idle)
        // Invalidate any pending 14s extraction safety-net timers scheduled
        // during this test — their attempt-token guard makes this the
        // designed kill switch (otherwise a timer fires mid-later-test and
        // re-finalizes the mission).
        gs.missionAttemptId += 1
        RoomManager.shared.unloadMission()
    }

    // MARK: - Helpers

    private func loadMission(_ id: String) throws -> MultiRoomMission {
        guard let mission = RoomManager.shared.loadMission(named: id) else {
            throw XCTSkip("\(id) JSON not bundled in test host")
        }
        return mission
    }

    /// Breadth-first order over the mission's room graph from the first room.
    private func reachableRooms(of mission: MultiRoomMission) -> [Room] {
        var order: [Room] = []
        var seen = Set<String>()
        var queue = [mission.rooms[0]]
        seen.insert(mission.rooms[0].id)
        while !queue.isEmpty {
            let room = queue.removeFirst()
            order.append(room)
            for conn in room.connections where !seen.contains(conn.targetRoomId) {
                if let next = mission.rooms.first(where: { $0.id == conn.targetRoomId }) {
                    seen.insert(next.id)
                    queue.append(next)
                }
            }
        }
        return order
    }

    private func inBounds(_ x: Int, _ y: Int, map: [[Int]]) -> Bool {
        y >= 0 && y < map.count && x >= 0 && x < map[y].count
    }

    // MARK: - 1. Load + room graph integrity (all missions)

    func testAllMissionsLoadWithSoundRoomGraphs() throws {
        for id in Self.allMissionIds {
            let mission = try loadMission(id)
            XCTAssertFalse(mission.rooms.isEmpty, "\(id): no rooms")
            XCTAssertEqual(Set(mission.rooms.map(\.id)).count, mission.rooms.count,
                           "\(id): duplicate room ids")
            for room in mission.rooms {
                XCTAssertFalse(room.map.isEmpty, "\(id)/\(room.id): empty map")
                XCTAssertTrue(inBounds(room.playerSpawn.x, room.playerSpawn.y, map: room.map),
                              "\(id)/\(room.id): playerSpawn out of bounds")
                XCTAssertNotEqual(room.map[room.playerSpawn.y][room.playerSpawn.x],
                                  TileType.wall.rawValue,
                                  "\(id)/\(room.id): playerSpawn inside a wall")
                for conn in room.connections {
                    XCTAssertTrue(mission.rooms.contains { $0.id == conn.targetRoomId },
                                  "\(id)/\(room.id): connection → missing room \(conn.targetRoomId)")
                    XCTAssertTrue(inBounds(conn.triggerTileX, conn.triggerTileY, map: room.map),
                                  "\(id)/\(room.id): connection trigger out of bounds")
                }
                for spawn in room.enemies {
                    XCTAssertTrue(Self.knownSpawnTypes.contains(spawn.type),
                                  "\(id)/\(room.id): unsupported enemy type '\(spawn.type)'")
                    XCTAssertTrue(inBounds(spawn.x, spawn.y, map: room.map),
                                  "\(id)/\(room.id): spawn \(spawn.type) out of bounds")
                    XCTAssertNotEqual(room.map[spawn.y][spawn.x], TileType.wall.rawValue,
                                      "\(id)/\(room.id): spawn \(spawn.type) inside a wall")
                    XCTAssertGreaterThanOrEqual(spawn.delay, 0,
                                                "\(id)/\(room.id): negative spawn delay")
                }
                if let boss = room.bossSpawn {
                    XCTAssertTrue(Self.knownBossTypes.contains(boss.type),
                                  "\(id)/\(room.id): unsupported boss type '\(boss.type)'")
                }
                // Every room must resolve SOME objective: extraction or a way onward.
                XCTAssertTrue(room.extractionPoint != nil
                              || room.map.contains(where: { $0.contains(TileType.extraction.rawValue) })
                              || !room.connections.isEmpty,
                              "\(id)/\(room.id): dead-end room with no objective")
            }
            XCTAssertEqual(reachableRooms(of: mission).count, mission.rooms.count,
                           "\(id): unreachable rooms exist")
            XCTAssertTrue(mission.rooms.contains { RoomManager.shared.roomHasExtraction($0) },
                          "\(id): no extraction room anywhere")
        }
    }

    // MARK: - 2. Combat setup (all missions)

    func testAllMissionsPrepareForCombatWithPlacedSquadAndAuthoredOpposition() throws {
        for id in Self.allMissionIds {
            _ = try loadMission(id)
            let resolved = gs.prepareMissionForCombat(named: id)
            XCTAssertEqual(resolved, id, "\(id): setup resolved to \(resolved)")
            XCTAssertEqual(gs.currentMissionDisplayId, id)
            XCTAssertFalse(gs.playerTeam.isEmpty, "\(id): no squad")
            XCTAssertFalse(gs.currentMissionTiles.isEmpty, "\(id): no live tile map")
            for runner in gs.playerTeam where runner.isAlive {
                XCTAssertTrue(inBounds(runner.positionX, runner.positionY, map: gs.currentMissionTiles),
                              "\(id): \(runner.name) placed out of bounds")
                XCTAssertNotEqual(gs.currentMissionTiles[runner.positionY][runner.positionX],
                                  TileType.wall.rawValue,
                                  "\(id): \(runner.name) placed inside a wall")
            }
            let authored = RoomManager.shared.currentRoom?.enemies.count ?? 0
            XCTAssertEqual(gs.enemies.count + gs.pendingSpawns.count, authored,
                           "\(id): opposition (\(gs.enemies.count)+\(gs.pendingSpawns.count) pending) ≠ authored \(authored) at NG+0/zero attention")
            RoomManager.shared.unloadMission()
        }
    }

    // MARK: - 3. Full transition walk (all missions, every room)

    func testAllMissionsTransitionThroughEveryRoom() throws {
        for id in Self.allMissionIds {
            let mission = try loadMission(id)
            _ = gs.prepareMissionForCombat(named: id)
            for room in reachableRooms(of: mission).dropFirst() {
                gs.applyRoomEntry(to: room, enemies: [], pendingSpawns: [],
                                  spawnAnchor: room.playerSpawn)
                XCTAssertEqual(gs.currentRoomId, room.id, "\(id): room id desync")
                XCTAssertEqual(RoomManager.shared.currentRoom?.id, room.id,
                               "\(id): RoomManager desync")
                XCTAssertEqual(gs.currentMissionTiles, room.map, "\(id)/\(room.id): tiles not installed")
                for runner in gs.playerTeam where runner.isAlive {
                    XCTAssertNotEqual(gs.currentMissionTiles[runner.positionY][runner.positionX],
                                      TileType.wall.rawValue,
                                      "\(id)/\(room.id): \(runner.name) transitioned into a wall")
                }
            }
            RoomManager.shared.unloadMission()
        }
    }

    // MARK: - 4. Victory: clear → extract → payout → persist (all missions)

    func testAllMissionsCompleteViaExtractionWithPayoutAndPersistence() throws {
        for id in Self.allMissionIds {
            MissionStatsStore.shared.resetAll()
            let mission = try loadMission(id)
            _ = gs.prepareMissionForCombat(named: id)
            gs.missionComplete = false
            gs.combatEnded = false

            // Walk every room, clearing opposition as we go; finish in a room
            // that has extraction.
            var extractionRoom: Room?
            for (i, room) in reachableRooms(of: mission).enumerated() {
                if i > 0 {
                    gs.applyRoomEntry(to: room, enemies: [], pendingSpawns: [],
                                      spawnAnchor: room.playerSpawn)
                }
                gs.enemies.forEach { $0.currentHP = 0 }
                gs.pendingSpawns = []
                _ = RoomManager.shared.markCurrentRoomCleared()
                if RoomManager.shared.roomHasExtraction(room) { extractionRoom = room }
            }
            guard let finalRoom = extractionRoom else {
                return XCTFail("\(id): no extraction room reached")
            }
            if RoomManager.shared.currentRoom?.id != finalRoom.id {
                gs.applyRoomEntry(to: finalRoom, enemies: [], pendingSpawns: [],
                                  spawnAnchor: finalRoom.playerSpawn)
                gs.enemies.forEach { $0.currentHP = 0 }
                _ = RoomManager.shared.markCurrentRoomCleared()
            }
            XCTAssertTrue(RoomManager.shared.areAllRoomsCleared, "\(id): rooms not all cleared")
            XCTAssertTrue(RoomManager.shared.isExtractionActive(in: finalRoom),
                          "\(id): extraction not active after full clear")

            if gs.missionRequiresData && !gs.dataAcquired {
                XCTAssertEqual(gs.requestObjectiveDataAcquired(source: "cert-harness"), .accepted)
            }
            guard let runner = gs.playerTeam.first(where: { $0.isAlive }) else {
                return XCTFail("\(id): no living runner")
            }
            runner.positionX = gs.extractionX
            runner.positionY = gs.extractionY
            CombatFlowController.setCombatPhase(gameState: gs, .playerInput)

            let result = gs.requestExtractionResolution(
                characterId: runner.id, tileX: gs.extractionX, tileY: gs.extractionY)
            XCTAssertEqual(result, .accepted, "\(id): extraction request refused")
            XCTAssertTrue(gs.extractionAnimationInProgress, "\(id): extraction did not arm")
            XCTAssertEqual(gs.requestExtractionSequenceCompleted(), .accepted,
                           "\(id): extraction completion refused")

            XCTAssertTrue(gs.missionComplete, "\(id): mission did not complete")
            let record = MissionStatsStore.shared.record(for: id)
            XCTAssertEqual(record.attempts, 1, "\(id): victory not recorded exactly once")
            XCTAssertTrue(record.completed, "\(id): completion not stamped")
            XCTAssertGreaterThan(MissionStatsStore.shared.playerNuyen, 0, "\(id): no payout")
            if id != "Mission006" {   // finale clears paidThisRun for the next campaign run
                XCTAssertTrue(MissionStatsStore.shared.paidThisRun.contains(id),
                              "\(id): first-clear payment not latched")
            }
            // Save/resume: a fresh decode of the persisted blob (what a
            // relaunch would load) must contain this completion.
            guard let blob = UserDefaults.standard.data(forKey: "HexWire.MissionStats.v1"),
                  let decoded = try? JSONDecoder().decode([String: MissionRecord].self, from: blob),
                  decoded[id]?.completed == true else {
                return XCTFail("\(id): completion did not persist to disk")
            }
            RoomManager.shared.unloadMission()
            gs.missionComplete = false
            gs.combatEnded = false
        }
    }

    // MARK: - 5. Defeat path pays nothing (all missions)

    func testAllMissionsDefeatRecordsNoVictoryAndNoPayout() throws {
        for id in Self.allMissionIds {
            MissionStatsStore.shared.resetAll()
            _ = try loadMission(id)
            _ = gs.prepareMissionForCombat(named: id)
            gs.missionComplete = false
            gs.combatEnded = false
            CombatFlowController.setCombatPhase(gameState: gs, .playerInput)

            for runner in gs.playerTeam { runner.currentHP = 0; runner.status = .dead }
            gs.checkCombatEnd()

            XCTAssertTrue(gs.combatEnded, "\(id): defeat did not end combat")
            XCTAssertEqual(MissionStatsStore.shared.record(for: id).attempts, 0,
                           "\(id): defeat must not record a victory")
            XCTAssertEqual(MissionStatsStore.shared.playerNuyen, 0,
                           "\(id): defeat must not pay")
            RoomManager.shared.unloadMission()
            gs.missionComplete = false
            gs.combatEnded = false
        }
    }

    // MARK: - 6. Replay rerolls stay inside the authored envelope (all missions)

    func testAllMissionsReplayRerollsRespectBudgetAndPool() throws {
        for id in Self.allMissionIds {
            MissionStatsStore.shared.resetAll()
            let mission = try loadMission(id)
            gs.currentMissionDisplayId = id
            MissionStatsStore.shared.recordVictory(missionId: id, score: 1)   // arm replay
            gs.missionAttemptId = 991

            var pool = Set<String>()
            for r in mission.rooms {
                for s in r.enemies where MissionSetupService.spawnCost[s.type] != nil {
                    pool.insert(s.type)
                }
            }
            for room in mission.rooms {
                let a = MissionSetupService.replaySquad(for: room, gameState: gs)
                let b = MissionSetupService.replaySquad(for: room, gameState: gs)
                XCTAssertEqual(a.map(\.type), b.map(\.type),
                               "\(id)/\(room.id): reroll not deterministic within attempt")
                XCTAssertEqual(a.count, room.enemies.count, "\(id)/\(room.id): slot count changed")
                for (orig, rolled) in zip(room.enemies, a) {
                    XCTAssertEqual(rolled.x, orig.x, "\(id)/\(room.id): position changed")
                    XCTAssertEqual(rolled.delay, orig.delay, "\(id)/\(room.id): delay changed")
                    if let cost = MissionSetupService.spawnCost[orig.type], pool.count > 1 {
                        guard let newCost = MissionSetupService.spawnCost[rolled.type] else {
                            XCTFail("\(id)/\(room.id): rerolled to uncosted '\(rolled.type)'"); continue
                        }
                        XCTAssertLessThanOrEqual(abs(newCost - cost), 1,
                                                 "\(id)/\(room.id): budget broken \(orig.type)→\(rolled.type)")
                        XCTAssertTrue(pool.contains(rolled.type),
                                      "\(id)/\(room.id): '\(rolled.type)' not authored in this mission")
                    } else {
                        XCTAssertEqual(rolled.type, orig.type,
                                       "\(id)/\(room.id): boss/unique slot rerolled")
                    }
                }
            }
            gs.missionAttemptId = 0
            RoomManager.shared.unloadMission()
        }
    }
}
#endif
