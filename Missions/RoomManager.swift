import Foundation
import SpriteKit

// MARK: - Room Manager

/// Manages multi-room missions: tracks current room, handles transitions.
@MainActor
final class RoomManager: ObservableObject {

    static let shared = RoomManager()

    @Published private(set) var currentMission: MultiRoomMission?
    @Published private(set) var currentRoom: Room?
    @Published private(set) var currentRoomIndex: Int = 0
    @Published private(set) var isTransitioning: Bool = false

    /// Current room ID — BattleScene reads this to pass to attemptTransition.
    var currentRoomId: String { currentRoom?.id ?? "" }

    /// Set when a room transition is complete — BattleScene reads this to reload the map.
    var pendingRoomTransition: Room?

    /// Target spawn position from the RoomConnection used for door transitions.
    /// This is set by attemptTransition() so handleRoomTransitionCompleted can use
    /// connection.targetSpawn instead of room.playerSpawn.
    var pendingConnectionTargetX: Int?
    var pendingConnectionTargetY: Int?

    /// Tracks which rooms have been entered (for position-preservation on back-navigation).
    /// A room is "entered" if the player has loaded it at least once.
    /// First entry uses spawn; back-navigation preserves the player's last position in that room.
    private var enteredRoomIds: Set<String> = []
    private var clearedRoomIds: Set<String> = []
    /// Rooms where a reinforcement wave has already been deployed. Limits each
    /// room to one wave so kills don't trigger an infinite spawn loop.
    private var roomsWithDeployedReinforcements: Set<String> = []
    /// Rooms whose `bossSpawn` boss has been spawned. Used by `onRoomCleared`
    /// to differentiate "regulars cleared, boss should drop in" from "boss
    /// is dead, room is truly clear".
    var bossDeployedRoomIds: Set<String> = []
    /// Rooms whose boss spawn is scheduled but not yet executed (used for
    /// the M6 AGI suspense delay — between "regulars dead" and "boss
    /// appears" the room is in limbo). `onRoomCleared` checks this so the
    /// intercept doesn't re-fire during the delay window and queue a
    /// duplicate spawn.
    var bossPendingRoomIds: Set<String> = []
    /// Rooms whose `removeOnFirstKill` barriers have already dropped. The drop
    /// only mutates the live tile grid; every room (re)entry rebuilds tiles
    /// from JSON, and a cleared room has no enemies left to re-trigger the
    /// drop — without this set, re-entering M1 room_1 restores the wall row
    /// permanently and the mission can never be finished.
    var barrierDroppedRoomIds: Set<String> = []
    /// How many times the player has RE-entered each room (first entry = 0).
    /// Seeds the backtrack-patrol roll so a given visit always rolls the same
    /// way — walking out and back in can't be used to re-roll a patrol you
    /// didn't like, but successive visits still differ.
    private var reentryCounts: [String: Int] = [:]
    /// Rooms that have already coughed up a backtrack patrol this mission.
    /// One patrol per room per attempt — without this, a corridor between two
    /// objectives becomes an infinite XP/nuyen faucet.
    var patrolRespawnedRoomIds: Set<String> = []

    /// Bump and return the re-entry index for a room (0 on first entry).
    @discardableResult
    func noteRoomEntry(_ roomId: String) -> Int {
        let next = (reentryCounts[roomId] ?? -1) + 1
        reentryCounts[roomId] = next
        return next
    }

    func reentryCount(_ roomId: String) -> Int { reentryCounts[roomId] ?? 0 }

    /// Re-apply this room's already-dropped barriers (as floor) to a tile grid
    /// rebuilt from JSON. Call from every model/visual tile-build path.
    func applyDroppedBarriers(to tiles: inout [[Int]], room: Room) {
        guard barrierDroppedRoomIds.contains(room.id),
              let drops = room.removeOnFirstKill else { return }
        for p in drops where p.y >= 0 && p.y < tiles.count && p.x >= 0 && p.x < tiles[p.y].count {
            tiles[p.y][p.x] = TileType.floor.rawValue
        }
    }

    /// Mark a room as entered (call before beginTransition so the flag is set
    /// before handleRoomTransitionCompleted checks it).
    func markRoomEntered(_ roomId: String) {
        enteredRoomIds.insert(roomId)
    }

    /// Returns true if the player has entered this room at least once before.
    func isRoomEntered(_ roomId: String) -> Bool {
        enteredRoomIds.contains(roomId)
    }

    /// True if the door at this tile (in the given room) leads BACK to a room
    /// the player has already entered. Backtracking doors are usable even when
    /// the current room isn't cleared, so the player can return for a missed
    /// objective.
    func doorIsBacktrack(inRoom roomId: String, tileX x: Int, y: Int) -> Bool {
        guard let room = currentMission?.rooms.first(where: { $0.id == roomId }),
              let conn = room.connections.first(where: {
                  $0.triggerTileX == x && $0.triggerTileY == y
              }) else { return false }
        return isRoomEntered(conn.targetRoomId)
    }

    private init() {}

    // MARK: - Setup

    /// Load a multi-room mission by id.
    @discardableResult
    func loadMission(named id: String) -> MultiRoomMission? {
        if let mission = MissionLoader.shared.loadMultiRoomMission(named: id) {
            currentMission = mission
            currentRoom = mission.rooms.first
            currentRoomIndex = 0
            enteredRoomIds.removeAll()
            clearedRoomIds.removeAll()
            roomsWithDeployedReinforcements.removeAll()
            bossDeployedRoomIds.removeAll()
            bossPendingRoomIds.removeAll()
            barrierDroppedRoomIds.removeAll()
            reentryCounts.removeAll()
            patrolRespawnedRoomIds.removeAll()
            return mission
        }
        return nil
    }

    func unloadMission() {
        currentMission = nil
        currentRoom = nil
        currentRoomIndex = 0
        isTransitioning = false
        pendingRoomTransition = nil
        pendingConnectionTargetX = nil
        pendingConnectionTargetY = nil
        enteredRoomIds.removeAll()
        clearedRoomIds.removeAll()
        roomsWithDeployedReinforcements.removeAll()
        bossDeployedRoomIds.removeAll()
        bossPendingRoomIds.removeAll()
        barrierDroppedRoomIds.removeAll()
        reentryCounts.removeAll()
        patrolRespawnedRoomIds.removeAll()
    }

    /// Mark a room as having received its reinforcement wave so future
    /// kill-clears in the same room do not trigger another wave.
    /// Returns true if this is the first wave for this room.
    @discardableResult
    func markReinforcementsDeployed(in roomId: String) -> Bool {
        roomsWithDeployedReinforcements.insert(roomId).inserted
    }

    func haveReinforcementsBeenDeployed(in roomId: String) -> Bool {
        roomsWithDeployedReinforcements.contains(roomId)
    }

    @discardableResult
    func markCurrentRoomCleared() -> Bool {
        guard let roomId = currentRoom?.id else { return false }
        let inserted = clearedRoomIds.insert(roomId).inserted
        dlog("[RoomManager] markCurrentRoomCleared() room=\(roomId) newlyInserted=\(inserted) clearedRoomIds now = \(Array(clearedRoomIds))")
        return inserted
    }

    /// Reverse the cleared-state flag — used when reinforcements spawn into
    /// a previously-cleared room. The door re-locks until the new wave dies.
    @discardableResult
    func unmarkCurrentRoomCleared() -> Bool {
        guard let roomId = currentRoom?.id else { return false }
        let removed = clearedRoomIds.remove(roomId) != nil
        if removed {
            dlog("[RoomManager] unmarkCurrentRoomCleared() room=\(roomId) — door re-locks for reinforcement wave")
        }
        return removed
    }

    /// Same as `unmarkCurrentRoomCleared` but targeted by id — the room
    /// transition needs this because it runs BEFORE `completeTransition`, so
    /// `currentRoom` is still the room being left, not the one being entered.
    @discardableResult
    func unmarkRoomCleared(_ roomId: String) -> Bool {
        let removed = clearedRoomIds.remove(roomId) != nil
        if removed {
            dlog("[RoomManager] unmarkRoomCleared() room=\(roomId) — door re-locks for backtrack patrol")
        }
        return removed
    }

    func isRoomCleared(_ roomId: String) -> Bool {
        let cleared = clearedRoomIds.contains(roomId)
        dlog("[RoomManager] isRoomCleared(\(roomId)) = \(cleared) clearedRoomIds = \(Array(clearedRoomIds))")
        return cleared
    }

    var areAllRoomsCleared: Bool {
        guard let rooms = currentMission?.rooms, !rooms.isEmpty else { return false }
        return rooms.allSatisfy { clearedRoomIds.contains($0.id) }
    }

    func roomHasExtraction(_ room: Room) -> Bool {
        if room.extractionPoint != nil { return true }
        return room.map.contains { row in row.contains(TileType.extraction.rawValue) }
    }

    func isExtractionActive(in room: Room? = nil) -> Bool {
        guard let mission = currentMission else { return true }
        let checkedRoom = room ?? currentRoom
        guard let checkedRoom else { return false }
        return areAllRoomsCleared
            && roomHasExtraction(checkedRoom)
            && mission.rooms.contains { $0.id == checkedRoom.id }
    }

    /// Called by BattleScene when player steps on a door tile.
    /// Returns the target Room if a transition should occur.
    func attemptTransition(from roomId: String, atTileX x: Int, y: Int) -> Room? {
        // FIX 3: block room transitions when player is dead
        guard !GameState.shared.playerIsDead else { return nil }
        guard !isTransitioning else { return nil }
        guard let room = currentMission?.rooms.first(where: { $0.id == roomId }) else { return nil }

        // Find a connection from this room at the given tile
        guard let connection = room.connections.first(where: {
            $0.triggerTileX == x && $0.triggerTileY == y
        }) else { return nil }

        // Backtracking to a room you've ALREADY entered is always allowed —
        // a player who left a room without finishing an optional objective
        // (e.g. an un-hacked terminal) can walk back through the door they
        // came in. Cleared rooms stay empty on return (see
        // handleRoomTransitionCompleted), so this is safe. Progressing into a
        // NEW room still requires clearing the current one first.
        let isBacktrack = isRoomEntered(connection.targetRoomId)
        if !isBacktrack {
            guard isRoomCleared(room.id) else {
                GameState.shared.addLog("Door locked: clear this room first.")
                return nil
            }
        }

        // BOSS DOOR-LOCK (per playtest 2026-05-23):
        // Even when the cleared-flag is set, a still-living boss locks ALL
        // doors in the current room. This prevents the race where the
        // regular-enemy death path marks the room cleared before the boss
        // spawn fires (e.g. M3R2 mageBossPhase2 deferred spawn). Without
        // this guard, players could flee the boss room mid-fight, come
        // back to find the boss wiped (enemies array rebuilt from JSON on
        // re-entry, boss never re-spawns) AND the grimoire un-pickup-able
        // because the actual boss death never registered.
        let bossPresent = GameState.shared.enemies.contains { e in
            // Any boss archetype seals the door — the old hardcoded list missed
            // "bosscorp" (Vera), whose whole fight could be skipped by walking out.
            e.isAlive && e.archetype.lowercased().hasPrefix("boss")
        }
        // A scheduled-but-not-yet-spawned boss (M6 AGI suspense beat) seals
        // the doors too — leaving during the 2.5s window abandoned the fight.
        let bossIncoming = currentRoom.map { bossPendingRoomIds.contains($0.id) } ?? false
        if bossPresent || bossIncoming {
            GameState.shared.addLog("Door sealed — the boss won't let you leave.")
            return nil
        }

        // Find the target room
        guard let targetRoom = currentMission?.rooms.first(where: { $0.id == connection.targetRoomId }) else {
            return nil
        }

        // Spawn placement: ALWAYS the connection's authored targetSpawn, for
        // forward and backward alike. Each connection already authors the tile
        // beside the door it leads to, so walking back through a door puts you
        // where that door actually is — the mirror of how you left.
        //
        // The previous special case sent backtrackers to targetRoom.playerSpawn
        // instead. That is the room's ORIGINAL entry point, at the far end from
        // the door you just came through: returning M1 room_2 → room_1 landed
        // the squad at (3,9), the top, when the connection authors (2,1) at the
        // bottom. It also contradicted BattleScene's own transition comment
        // (playtest 2026-05-23), which had already settled on door-driven
        // spawns for both directions — the two disagreed and this side won.
        pendingConnectionTargetX = connection.targetSpawnX
        pendingConnectionTargetY = connection.targetSpawnY

        return targetRoom
    }

    /// Begin the transition to a new room.
    /// The scene should call this, then perform the fade, then call completeTransition.
    func beginTransition(to targetRoom: Room) {
        // FIX 3: block transitions when player is dead
        guard !GameState.shared.playerIsDead else { return }
        isTransitioning = true
        pendingRoomTransition = targetRoom
    }

    /// Complete the transition — update current room state.
    func completeTransition(to room: Room) {
        currentRoom = room
        currentRoomIndex = currentMission?.rooms.firstIndex(where: { $0.id == room.id }) ?? 0
        isTransitioning = false
        pendingRoomTransition = nil
        pendingConnectionTargetX = nil
        pendingConnectionTargetY = nil
    }

    /// Cancel an in-progress transition (e.g., if combat state changed).
    func cancelTransition() {
        isTransitioning = false
        pendingRoomTransition = nil
    }

    /// Spawn position for the current room.
    var currentSpawn: SpawnPoint {
        currentRoom?.playerSpawn ?? SpawnPoint(x: 1, y: 16)
    }

    /// Build a TileMap for the current room.
    func currentTileMap() -> TileMap? {
        guard let room = currentRoom else { return nil }
        return TileMap(tiles: room.tileMap)
    }
}
