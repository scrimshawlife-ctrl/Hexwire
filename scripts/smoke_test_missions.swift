import Foundation

// Mission data smoke test — validates the preconditions the room/combat code
// relies on, so the data-level version of "no enemy on entry / can't leave
// room / unreachable door" softlocks is caught in <1s without a sideload.
//
// Run:  swift scripts/smoke_test_missions.swift
// (run from the project root so the Missions/ paths resolve)
//
// Hex layout matches PathingAndAIHelpers.hexNeighbors (flat-top odd-q,
// column-parity offsets) and tileWalkable (only TileType.wall == 1 blocks).

let WALL = 1

func hexNeighbors(_ x: Int, _ y: Int) -> [(Int, Int)] {
    if x % 2 == 0 {
        return [(x,y-1),(x,y+1),(x-1,y-1),(x-1,y),(x+1,y-1),(x+1,y)]
    } else {
        return [(x,y-1),(x,y+1),(x-1,y),(x-1,y+1),(x+1,y),(x+1,y+1)]
    }
}

// Archetypes the room-transition enemy factory (BattleScene) knows. An
// unrecognized type silently falls back to a corp guard — flag it.
let KNOWN_ENEMY_TYPES: Set<String> = [
    "guard","drone","elite","mage","healer","mech","sniper","bruiser","spider",
    "riot","turret","rigger","netrunner","grenadier","juggernaut","infiltrator",
    "repairdrone","sprayer","corp","bosscorp","exec","bossmage"
]
let KNOWN_BOSS_TYPES: Set<String> = ["agi","bossagi","ai","mech","bossmech","corp","bosscorp","mage","bossmage"]

var failures: [String] = []
var warnings: [String] = []
func fail(_ m: String) { failures.append(m) }
func warn(_ m: String) { warnings.append(m) }

func intAt(_ d: [String: Any], _ k: String) -> Int? { d[k] as? Int }

func validateRoom(mission: String, roomIdx: Int, room: [String: Any], roomIds: Set<String>, isLastRoom: Bool) {
    let rid = (room["id"] as? String) ?? "room_\(roomIdx)"
    let tag = "\(mission)/\(rid)"
    guard let map = room["map"] as? [[Int]], !map.isEmpty else {
        fail("\(tag): missing/empty map"); return
    }
    let h = map.count
    let w = map[0].count
    func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < w && y >= 0 && y < h }
    func isWall(_ x: Int, _ y: Int) -> Bool { inBounds(x, y) ? map[y][x] == WALL : true }

    // Player spawn
    guard let ps = room["playerSpawn"] as? [String: Any],
          let psx = intAt(ps, "x"), let psy = intAt(ps, "y") else {
        fail("\(tag): missing playerSpawn"); return
    }
    if !inBounds(psx, psy) { fail("\(tag): playerSpawn (\(psx),\(psy)) out of bounds \(w)x\(h)") }
    else if isWall(psx, psy) { fail("\(tag): playerSpawn (\(psx),\(psy)) is on a WALL") }

    // removeOnFirstKill barriers START as walls but DROP after the room's
    // first kill — so reachability is two-phase:
    //   • barrier UP:   what you can reach before any kill (must contain a
    //                   killable enemy, else the barrier never drops)
    //   • barrier DOWN: the achievable end state (enemies/doors/extraction
    //                   must all be reachable here)
    let barrierTiles = (room["removeOnFirstKill"] as? [[String: Any]]) ?? []
    var barrierSet = Set<Int>()
    for b in barrierTiles { if let bx = intAt(b, "x"), let by = intAt(b, "y") { barrierSet.insert(by * w + bx) } }

    func bfs(barrierPassable: Bool) -> Set<Int> {
        var seen = Set<Int>()
        guard inBounds(psx, psy), !isWall(psx, psy) else { return seen }
        var stack = [(psx, psy)]
        seen.insert(psy * w + psx)
        while let (cx, cy) = stack.popLast() {
            for (nx, ny) in hexNeighbors(cx, cy) where inBounds(nx, ny) {
                let key = ny * w + nx
                let passable = !isWall(nx, ny) || (barrierPassable && barrierSet.contains(key))
                if passable, seen.insert(key).inserted { stack.append((nx, ny)) }
            }
        }
        return seen
    }
    let reachableUp = bfs(barrierPassable: false)
    let reachableDown = barrierSet.isEmpty ? reachableUp : bfs(barrierPassable: true)
    func reachableTile(_ x: Int, _ y: Int) -> Bool { reachableDown.contains(y * w + x) }

    // Enemies
    let enemies = (room["enemies"] as? [[String: Any]]) ?? []
    var delayZeroCount = 0
    var anyEnemyReachableBarrierUp = false
    for (i, e) in enemies.enumerated() {
        let type = (e["type"] as? String) ?? "?"
        let ex = intAt(e, "x") ?? -1, ey = intAt(e, "y") ?? -1
        let delay = intAt(e, "delay") ?? 0
        if delay == 0 { delayZeroCount += 1 }
        if !KNOWN_ENEMY_TYPES.contains(type) {
            warn("\(tag): enemy[\(i)] type '\(type)' unrecognized → silently becomes a corp guard")
        }
        if !inBounds(ex, ey) { fail("\(tag): enemy[\(i)] '\(type)' (\(ex),\(ey)) out of bounds") }
        else if isWall(ex, ey) { fail("\(tag): enemy[\(i)] '\(type)' spawns on a WALL (\(ex),\(ey))") }
        else if !reachableTile(ex, ey) { fail("\(tag): enemy[\(i)] '\(type)' (\(ex),\(ey)) NOT reachable even after barriers drop — unkillable, room can't clear") }
        if inBounds(ex, ey), reachableUp.contains(ey * w + ex) { anyEnemyReachableBarrierUp = true }
    }
    // A barrier room must have an enemy reachable BEFORE the drop — otherwise
    // there's nothing to kill to trigger it, and the room is sealed forever.
    if !barrierSet.isEmpty && !enemies.isEmpty && !anyEnemyReachableBarrierUp {
        fail("\(tag): removeOnFirstKill barrier but no enemy reachable before it drops — barrier can never trigger, hard softlock")
    }

    let boss = room["bossSpawn"] as? [String: Any]
    let hasBoss = boss != nil
    if let b = boss {
        let bt = (b["type"] as? String) ?? "?"
        let bx = intAt(b, "x") ?? -1, by = intAt(b, "y") ?? -1
        if !KNOWN_BOSS_TYPES.contains(bt) { warn("\(tag): bossSpawn type '\(bt)' unrecognized") }
        if inBounds(bx, by) && isWall(bx, by) { fail("\(tag): bossSpawn '\(bt)' on a WALL (\(bx),\(by))") }
        else if inBounds(bx, by) && !reachableTile(bx, by) { fail("\(tag): bossSpawn '\(bt)' (\(bx),\(by)) NOT reachable from player spawn") }
    }

    // SOFTLOCK GUARD: a room with combatants must have something to kill on
    // entry. Zero delay-0 enemies AND no boss = you enter an empty room; if a
    // door is clear-gated or a removeOnFirstKill barrier blocks, you're stuck.
    let barriers = (room["removeOnFirstKill"] as? [[String: Any]]) ?? []
    if !enemies.isEmpty && delayZeroCount == 0 && !hasBoss {
        warn("\(tag): no delay-0 enemy and no boss — room is empty on entry until a delayed spawn fires")
    }
    if !barriers.isEmpty && enemies.isEmpty && !hasBoss {
        fail("\(tag): removeOnFirstKill barrier but NO enemy to kill — barrier never drops, hard softlock")
    }

    // Connections: target rooms exist, trigger tiles reachable + not walls
    let conns = (room["connections"] as? [[String: Any]]) ?? []
    if conns.isEmpty && !isLastRoom {
        warn("\(tag): non-final room with no connections (dead end?)")
    }
    for (i, c) in conns.enumerated() {
        let target = (c["targetRoomId"] as? String) ?? "?"
        if !roomIds.contains(target) { fail("\(tag): connection[\(i)] → '\(target)' which does not exist") }
        if let tx = intAt(c, "triggerTileX"), let ty = intAt(c, "triggerTileY") {
            if !inBounds(tx, ty) { fail("\(tag): door[\(i)]→\(target) trigger (\(tx),\(ty)) out of bounds") }
            else if isWall(tx, ty) { fail("\(tag): door[\(i)]→\(target) trigger (\(tx),\(ty)) is a WALL — untappable") }
            else if !reachableTile(tx, ty) { fail("\(tag): door[\(i)]→\(target) trigger (\(tx),\(ty)) NOT reachable from player spawn — can't leave room") }
        }
        // Target spawn must be walkable in the target room
        if let target3 = mission as String?, let tsx = intAt(c, "targetSpawnX"), let tsy = intAt(c, "targetSpawnY") {
            _ = target3; _ = tsx; _ = tsy  // cross-room spawn checked in the second pass below
        }
    }

    // Extraction reachability (final room / any room declaring one)
    var extractionTiles: [(Int, Int)] = []
    for y in 0..<h { for x in 0..<w where map[y][x] == 4 { extractionTiles.append((x, y)) } }
    if let ep = room["extractionPoint"] as? [String: Any], let ex = intAt(ep, "x"), let ey = intAt(ep, "y") {
        extractionTiles.append((ex, ey))
    }
    for (ex, ey) in extractionTiles where !reachableTile(ex, ey) {
        fail("\(tag): extraction (\(ex),\(ey)) NOT reachable from player spawn — mission can't be completed")
    }
    if isLastRoom && extractionTiles.isEmpty && conns.isEmpty {
        warn("\(tag): final room has no extraction tile and no exit")
    }
}

// ── Driver ───────────────────────────────────────────────────────────────
let missionFiles = (1...6).map { "Mission00\($0)_multi.json" }
var missionsChecked = 0

for file in missionFiles {
    let path = "Missions/\(file)"
    guard let data = FileManager.default.contents(atPath: path) else {
        warn("\(file): not found (skipped)"); continue
    }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rooms = obj["rooms"] as? [[String: Any]] else {
        fail("\(file): failed to parse JSON / no rooms"); continue
    }
    missionsChecked += 1
    let roomIds = Set(rooms.compactMap { $0["id"] as? String })
    // Build a room lookup for cross-room target-spawn validation.
    var roomById: [String: [String: Any]] = [:]
    for r in rooms { if let id = r["id"] as? String { roomById[id] = r } }

    for (idx, room) in rooms.enumerated() {
        validateRoom(mission: file, roomIdx: idx, room: room, roomIds: roomIds, isLastRoom: idx == rooms.count - 1)
        // Cross-room: each connection's target spawn must be walkable in target room.
        if let conns = room["connections"] as? [[String: Any]] {
            let rid = (room["id"] as? String) ?? "room_\(idx)"
            for (i, c) in conns.enumerated() {
                guard let target = c["targetRoomId"] as? String,
                      let troom = roomById[target],
                      let tmap = troom["map"] as? [[Int]], !tmap.isEmpty,
                      let tsx = intAt(c, "targetSpawnX"), let tsy = intAt(c, "targetSpawnY") else { continue }
                let th = tmap.count, tw = tmap[0].count
                if tsx < 0 || tsx >= tw || tsy < 0 || tsy >= th {
                    fail("\(file)/\(rid): door[\(i)]→\(target) targetSpawn (\(tsx),\(tsy)) out of bounds in target")
                } else if tmap[tsy][tsx] == WALL {
                    fail("\(file)/\(rid): door[\(i)]→\(target) targetSpawn (\(tsx),\(tsy)) lands on a WALL in target")
                }
            }
        }
    }
}

// ── Report ───────────────────────────────────────────────────────────────
print("══════════════════════════════════════════════")
print(" Mission smoke test — \(missionsChecked) mission(s) checked")
print("══════════════════════════════════════════════")
if !warnings.isEmpty {
    print("\n⚠️  WARNINGS (\(warnings.count)):")
    for w in warnings { print("   • \(w)") }
}
if failures.isEmpty {
    print("\n✅ PASS — no softlock-class data failures.")
    if warnings.isEmpty { print("   (no warnings either — clean)") }
    exit(0)
} else {
    print("\n❌ FAIL (\(failures.count)):")
    for f in failures { print("   ✗ \(f)") }
    exit(1)
}
