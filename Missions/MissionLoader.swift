import Foundation

// MARK: - Mission Data Structures

/// Represents the full mission definition loaded from JSON.
struct Mission: Codable {
    let id: String
    let title: String
    let description: String
    let difficulty: String?
    let width: Int
    let height: Int
    let playerSpawn: SpawnPoint
    let extractionPoint: SpawnPoint
    let map: [[Int]]
    let enemies: [EnemySpawn]

    /// Convert raw map ints into TileType 2D array
    var tileMap: [[TileType]] {
        map.map { row in row.map { TileType(rawValue: $0) ?? .floor } }
    }
}

/// Player or extraction spawn point
struct SpawnPoint: Codable {
    let x: Int
    let y: Int
}

/// An enemy that spawns on the map with a delay (in turns).
struct EnemySpawn: Codable {
    let type: String   // "guard", "drone", "elite"
    let x: Int
    let y: Int
    let delay: Int     // spawn after N turns have passed
}

// MARK: - Multi-Room Mission Types
// (Consolidated here from Room.swift on 2026-04-19 to work around an Xcode
//  indexing issue where MultiRoomMission wasn't resolving across files.)

/// A single room within a multi-room mission.
/// Each room has its own tile map and enemies, linked to other rooms via door connections.
struct Room: Codable, Identifiable {
    let id: String
    let title: String
    let map: [[Int]]          // 10x18 tile grid
    let playerSpawn: SpawnPoint
    let extractionPoint: SpawnPoint?  // nil = no extraction in this room (use doors to exit)
    let enemies: [EnemySpawn]
    let connections: [RoomConnection]

    /// Optional list of tiles that should be converted to floor (walkable) the
    /// first time an enemy is killed in this room. Used for dynamic barriers
    /// like Mission 1 / Security Wing's central caution barriers — they block
    /// movement until the first guard goes down, then drop.
    let removeOnFirstKill: [SpawnPoint]?

    /// Optional boss that spawns AFTER the room's regular enemies are
    /// cleared. Used by M5 r2 (Mekton Blues finale) — drops a Combat Mech
    /// in once the lesser ones are down, with a full audio/visual reveal.
    /// While the boss is alive, normal reinforcement spawns are suppressed.
    let bossSpawn: BossSpawn?

    /// Convert raw map ints into TileType 2D array
    var tileMap: [[TileType]] {
        map.map { row in row.map { TileType(rawValue: $0) ?? .floor } }
    }
}

/// Boss spawn record. Triggered once per room from `onRoomCleared` when the
/// last regular enemy dies. The boss enemy is added to gameState.enemies
/// in place of marking the room cleared, so the player must defeat THIS
/// before the room counts as won.
struct BossSpawn: Codable {
    let type: String        // enemy archetype key — "mech" for the M5 boss
    let x: Int
    let y: Int
}

/// A doorway leading from one room to another.
/// A door tile (TileType.door = 3) on the map acts as the trigger.
struct RoomConnection: Codable {
    /// Which room this connects to
    let targetRoomId: String
    /// The tile on THIS room's map that triggers the transition (usually a door tile)
    let triggerTileX: Int
    let triggerTileY: Int
    /// Where the player spawns on entry into the target room (usually opposite side)
    let targetSpawnX: Int
    let targetSpawnY: Int
}

/// Extended mission that supports multiple linked rooms.
struct MultiRoomMission: Codable {
    let id: String
    let title: String
    let description: String
    let difficulty: String?         // shown on the briefing badge; nil → "MODERATE"
    let briefing: String?           // story/plot text shown at mission start
    let missionCompleteSummary: String?  // shown on victory
    let rooms: [Room]
    /// How runners exfil at the end of the run. nil → "helicopter". Values:
    ///   "helicopter" : helipad — animated heli lands, takes off
    ///   "ladder"     : climb-out (e.g. M3 ritual chamber roof access)
    ///   "door"       : walk through a door (e.g. M5 mech bay freight elevator)
    let extractionType: String?

    /// The room the player starts in.
    var startRoomId: String {
        rooms.first?.id ?? rooms[0].id
    }
}

// MARK: - Mission Loader

/// Loads mission JSON and constructs Mission objects.
final class MissionLoader {

    static let shared = MissionLoader()

    private init() {}

    /// Load a mission by name (without .json extension).
    /// First tries the app bundle (for bundled missions), then falls back to the
    /// project directory for development workflow.
    func loadMission(named name: String) -> Mission? {
        // Try bundle subdirectory first (production)
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Missions") {
            return loadMission(from: url)
        }
        // Fallback: root bundle (some Xcode configurations)
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            return loadMission(from: url)
        }
        // Development fallback: load directly from the project Missions/ directory
        // This makes the game work in preview/simulation without needing a full bundle install
        let projectMissionsURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Missions/
            .appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: projectMissionsURL.path) {
            return loadMission(from: projectMissionsURL)
        }
        dlog("MissionLoader: Mission '\(name)' not found in bundle or project directory")
        return nil
    }

    /// Load a multi-room mission by name.
    func loadMultiRoomMission(named name: String) -> MultiRoomMission? {
        // ── ENDLESS GAUNTLET ── the synthetic "Gauntlet" id never has a JSON
        // of its own: resolve it to the current floor's underlying story
        // mission (stable pick per floor), with id/title overridden so the
        // whole downstream pipeline (setup, stats, debrief) sees "Gauntlet".
        if name == GauntletStore.gauntletMissionId {
            return loadGauntletFloorMission()
        }
        // ── SIDE CONTRACTS ── synthetic "Contract_t<tier>_<seed>" ids resolve
        // to one sealed room of a story mission (see ContractStore).
        if ContractStore.isContractId(name) {
            return loadContractMission(id: name)
        }
        // Any REAL mission load stands a previously-armed gauntlet down —
        // the player backed out of the gauntlet briefing and picked a story
        // mission, so no floor scaling may leak onto it and its victory must
        // not advance the floor. No-op when the gauntlet isn't armed.
        GauntletStore.shared.disarmForNonGauntletLoad()
        ContractStore.shared.disarmForNonContractLoad()
        let multiName = name.hasSuffix("_multi") ? name : "\(name)_multi"
        // Try bundle Missions/ subdirectory first (preferred bundling)
        if let url = Bundle.main.url(forResource: multiName, withExtension: "json", subdirectory: "Missions") {
            dlog("MissionLoader: Found multi-room mission '\(multiName)' in Missions/ subdir")
            return loadMultiRoomMission(from: url)
        }
        // CRITICAL FIX: also try bundle root (this is where single-room JSONs are
        // found on device, and the multi-room JSONs ship the same way).
        if let url = Bundle.main.url(forResource: multiName, withExtension: "json") {
            dlog("MissionLoader: Found multi-room mission '\(multiName)' at bundle root")
            return loadMultiRoomMission(from: url)
        }
        // Fallback to project directory (dev/simulator only — won't work on device)
        let projectURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("\(multiName).json")
        if FileManager.default.fileExists(atPath: projectURL.path) {
            dlog("MissionLoader: Found multi-room mission '\(multiName)' at project path \(projectURL.path)")
            return loadMultiRoomMission(from: projectURL)
        }
        dlog("MissionLoader: ⚠️ Multi-room mission '\(multiName)' not found in bundle subdir, bundle root, or project dir — falling back to single-room")
        // Diagnostic: dump what JSON files DO exist in the bundle so we know what's wrong
        if let bundlePath = Bundle.main.resourcePath {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(atPath: bundlePath) {
                let jsons = contents.filter { $0.hasSuffix(".json") }
                dlog("MissionLoader: bundle root JSON files = \(jsons)")
            }
            let missionsDir = (bundlePath as NSString).appendingPathComponent("Missions")
            if let contents = try? fm.contentsOfDirectory(atPath: missionsDir) {
                let jsons = contents.filter { $0.hasSuffix(".json") }
                dlog("MissionLoader: bundle Missions/ JSON files = \(jsons)")
            } else {
                dlog("MissionLoader: bundle has no Missions/ subdirectory")
            }
        }
        return nil
    }

    /// Resolve the synthetic "Gauntlet" mission id to the current floor's
    /// underlying story mission.
    ///
    /// The returned MultiRoomMission is a copy of the underlying mission with:
    /// • `id` overridden to "Gauntlet" — so MissionSetupService sets
    ///   currentMissionDisplayId = "Gauntlet" and the victory records under
    ///   the "Gauntlet" stats record, NOT the story mission's (keeps campaign
    ///   completion + paidThisRun clean).
    /// • `title` overridden to "GAUNTLET — FLOOR N: <original title>" so the
    ///   briefing/debrief make the mode + depth obvious.
    /// Everything else (rooms, briefing, summary, extraction type) passes
    /// through untouched — the floor IS that mission, just harder.
    ///
    /// Arming happens here, lazily at LOAD time, precisely so the mission-
    /// select card needs no arm/disarm choreography: backing out of the
    /// briefing is harmless (the next real-mission load disarms, see above),
    /// and re-entering simply re-arms with the SAME persisted floor pick.
    /// Resolve a contract id to a single-room synthetic mission: pick the
    /// offer's vetted room, SEAL it (no connections, no boss), guarantee an
    /// extraction objective, and override id/title so stats/payout record
    /// under the contract. Arms ContractStore AFTER the underlying load
    /// (whose normal branch runs the disarms).
    private func loadContractMission(id: String) -> MultiRoomMission? {
        let store = ContractStore.shared
        guard let offer = store.offer(withId: id) else {
            dlog("MissionLoader: ⚠️ contract id '\(id)' has no live offer")
            return nil
        }
        guard let arenaId = ArenaPool.arenaId(forSeed: offer.seed),
              let entry = ArenaPool.entry(id: arenaId) else {
            dlog("MissionLoader: ⚠️ contract '\(id)' failed to resolve an arena")
            return nil
        }
        // Any real-mission state currently armed stands down first.
        GauntletStore.shared.disarmForNonGauntletLoad()
        let sealed = ArenaPool.finalRoom(from: entry, title: offer.title)
        store.armForContractLoad(offer)
        dlog("MissionLoader: contract \(id) → \(arenaId)")
        let difficulty = offer.tier >= 3 ? "HARD" : (offer.tier == 2 ? "HIGH" : "MODERATE")
        return MultiRoomMission(
            id: offer.id,
            title: "CONTRACT — \(offer.title)",
            description: offer.blurb,
            difficulty: difficulty,
            briefing: "\(offer.employer) is paying ¥\(offer.basePay.formatted()) base. \(offer.blurb) Site: \(entry.room.title). Clear the room and take the door.",
            missionCompleteSummary: "Contract fulfilled. \(offer.employer) transfers the fee — no questions, no names.",
            rooms: [sealed],
            extractionType: "door"
        )
    }

    private func loadGauntletFloorMission() -> MultiRoomMission? {
        let store = GauntletStore.shared
        ContractStore.shared.disarmForNonContractLoad()
        let arenaIds = store.arenaIdsForCurrentFloor()
        let names = arenaIds.compactMap { ArenaPool.entry(id: $0)?.room.title }
            .joined(separator: " → ")
        // NO story reuse: the gauntlet is its own thing — random arenas,
        // generic pit flavor, extraction door on the last room.
        guard let mission = ArenaPool.chainedMission(
            id: GauntletStore.gauntletMissionId,
            title: "GAUNTLET — FLOOR \(store.currentFloor)",
            briefing: "The pit broadcasts floor \(store.currentFloor): \(names). No fixer, no story — just the next squad and the exit door. Clear every arena and walk out.",
            summary: "Floor \(store.currentFloor) cleared. The pit is already loading the next one.",
            difficulty: store.currentFloor >= 6 ? "EXTREME" : (store.currentFloor >= 3 ? "HARD" : "HIGH"),
            arenaIds: arenaIds
        ) else {
            dlog("MissionLoader: ⚠️ Gauntlet floor \(store.currentFloor) failed to build from arenas \(arenaIds)")
            return nil
        }
        store.armForGauntletLoad()
        dlog("MissionLoader: Gauntlet floor \(store.currentFloor) → \(arenaIds)")
        return mission
    }

    /// Load multi-room mission from URL.
    func loadMultiRoomMission(from url: URL) -> MultiRoomMission? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(MultiRoomMission.self, from: data)
        } catch {
            dlog("MissionLoader: Failed to load multi-room mission from \(url): \(error)")
            return nil
        }
    }

    /// Load mission from a file URL.
    func loadMission(from url: URL) -> Mission? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(Mission.self, from: data)
        } catch {
            dlog("MissionLoader: Failed to load mission from \(url): \(error)")
            return nil
        }
    }

    /// Build a TileMap from a Mission.
    func buildTileMap(from mission: Mission) -> TileMap {
        return TileMap(tiles: mission.tileMap)
    }

    /// Get all enemy spawn definitions from a mission.
    func getEnemySpawns(from mission: Mission) -> [EnemySpawn] {
        return mission.enemies
    }
}