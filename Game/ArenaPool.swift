import Foundation

// MARK: - Arena Pool
//
// Ten purpose-built replay arenas (Missions/ArenaRooms.json) that the
// GAUNTLET and the CONTRACT BOARD draw from — replacing the old approach of
// reusing story missions wholesale (which dragged story briefings along and
// had no matching background art, since backgrounds key off
// "<missionId>_<roomId>.png" and synthetic ids match nothing).
//
// Each arena ships:
//   • a 12×7 authored tile layout with ONE exit door and an authored squad
//   • its own background art slot: "Sprites/backgrounds/<arenaId>.png"
//     (e.g. arena_01.png). Arenas render only their own art — they never
//     fall back to a story-mission room background.
//
// Generation rules:
//   • Gauntlet floor = 2–3 random arenas CHAINED by their exit doors; the
//     LAST room's door becomes the extraction tile ("it'll just be a door").
//   • Contract = 1 sealed arena, same door→extraction conversion.

enum ArenaPool {

    struct Entry: Codable {
        let room: Room
        let exitDoor: SpawnPoint
    }

    /// Decodes ArenaRooms.json — the Room fields plus each room's exit door.
    private struct FileFormat: Codable {
        let rooms: [Room]
    }
    private struct DoorFile: Codable {
        struct DoorEntry: Codable { let id: String; let exitDoor: SpawnPoint }
        let rooms: [DoorEntry]
    }

    private static var cache: [Entry]?

    /// Load the arena pool from the bundle (dev fallback: repo path).
    static func load() -> [Entry] {
        if let cache { return cache }
        var data: Data?
        if let url = Bundle.main.url(forResource: "ArenaRooms", withExtension: "json", subdirectory: "Missions") {
            data = try? Data(contentsOf: url)
        }
        if data == nil, let url = Bundle.main.url(forResource: "ArenaRooms", withExtension: "json") {
            data = try? Data(contentsOf: url)
        }
        if data == nil {
            // Dev/simulator fallback (same pattern as MissionLoader).
            let devURL = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()          // Game/
                .deletingLastPathComponent()          // repo root
                .appendingPathComponent("Missions/ArenaRooms.json")
            data = try? Data(contentsOf: devURL)
        }
        guard let data,
              let rooms = try? JSONDecoder().decode(FileFormat.self, from: data).rooms,
              let doors = try? JSONDecoder().decode(DoorFile.self, from: data).rooms else {
            dlog("[ArenaPool] ⚠️ failed to load ArenaRooms.json")
            return []
        }
        let doorById = Dictionary(uniqueKeysWithValues: doors.map { ($0.id, $0.exitDoor) })
        let entries = rooms.compactMap { room -> Entry? in
            guard let door = doorById[room.id] else { return nil }
            return Entry(room: room, exitDoor: door)
        }
        cache = entries
        return entries
    }

    static func entry(id: String) -> Entry? {
        load().first { $0.room.id == id }
    }

    /// The last room of any generated run: exit door tile becomes the
    /// EXTRACTION tile (walk out through the door).
    static func finalRoom(from entry: Entry, title: String? = nil) -> Room {
        var map = entry.room.map
        map[entry.exitDoor.y][entry.exitDoor.x] = TileType.extraction.rawValue
        return Room(
            id: entry.room.id,
            title: title ?? entry.room.title,
            map: map,
            playerSpawn: entry.room.playerSpawn,
            extractionPoint: entry.exitDoor,
            enemies: entry.room.enemies,
            connections: [],
            removeOnFirstKill: entry.room.removeOnFirstKill,
            bossSpawn: nil
        )
    }

    /// A mid-run room: exit door connects onward to `next`.
    static func chainedRoom(from entry: Entry, to next: Entry) -> Room {
        Room(
            id: entry.room.id,
            title: entry.room.title,
            map: entry.room.map,
            playerSpawn: entry.room.playerSpawn,
            extractionPoint: nil,
            enemies: entry.room.enemies,
            connections: [RoomConnection(
                targetRoomId: next.room.id,
                triggerTileX: entry.exitDoor.x,
                triggerTileY: entry.exitDoor.y,
                targetSpawnX: next.room.playerSpawn.x,
                targetSpawnY: next.room.playerSpawn.y
            )],
            removeOnFirstKill: entry.room.removeOnFirstKill,
            bossSpawn: nil
        )
    }

    /// Build a chained multi-arena mission (gauntlet floors). The arena ids
    /// must exist in the pool; unknown ids are skipped.
    static func chainedMission(id: String, title: String, briefing: String,
                               summary: String, difficulty: String,
                               arenaIds: [String]) -> MultiRoomMission? {
        let entries = arenaIds.compactMap { entry(id: $0) }
        guard !entries.isEmpty else { return nil }
        var rooms: [Room] = []
        for (i, e) in entries.enumerated() {
            if i == entries.count - 1 {
                rooms.append(finalRoom(from: e))
            } else {
                rooms.append(chainedRoom(from: e, to: entries[i + 1]))
            }
        }
        return MultiRoomMission(
            id: id,
            title: title,
            description: briefing,
            difficulty: difficulty,
            briefing: briefing,
            missionCompleteSummary: summary,
            rooms: rooms,
            extractionType: "door"
        )
    }

    /// Pick `count` distinct arena ids at random (gauntlet floor rolls).
    static func randomArenaIds(count: Int) -> [String] {
        Array(load().map { $0.room.id }.shuffled().prefix(max(1, count)))
    }

    /// Deterministic single-arena pick for contract seeds.
    static func arenaId(forSeed seed: Int) -> String? {
        let pool = load()
        guard !pool.isEmpty else { return nil }
        var z = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        let idx = Int((z ^ (z >> 31)) % UInt64(pool.count))
        return pool[idx].room.id
    }
}
