import SwiftUI

/// Picks the right mini-game for the current mission's data terminal.
///
///   • Mission 2 (Ghost Protocol)       → LaneRunner       (twitch — perspective)
///   • Mission 3 (The Mage's Lair)      → GlyphPattern     (memory — Simon Says)
///   • Mission 4 (Dead Man's Switch)    → CypherCracker    (timing — spinning rings)
///   • Mission 5 (Mekton Blues)         → PacketRouter     (strategy — node graph)
///   • Mission 6 (Ghost Signal)         → AGIFaceoff       (boss — tap + swipe)
///   • Anything else                    → MatrixMiniGameView fallback
///
/// `gameState.currentMissionDisplayId` is the source of truth for the routing
/// key (set by MissionSetupService at mission load).
struct MatrixMiniGameRouter: View {
    @ObservedObject var gameState: GameState
    let onComplete: (Bool) -> Void

    var body: some View {
        switch gameState.currentMissionDisplayId {
        case "Mission002":
            LaneRunnerMiniGame(gameState: gameState, onComplete: onComplete)
        case "Mission003":
            GlyphPatternMiniGame(gameState: gameState, onComplete: onComplete)
        case "Mission004":
            CypherCrackerMiniGame(gameState: gameState, onComplete: onComplete)
        case "Mission005":
            PacketRouterMiniGame(gameState: gameState, onComplete: onComplete)
        case "Mission006":
            AGIFaceoffMiniGame(gameState: gameState, onComplete: onComplete)
        default:
            MatrixMiniGameView(gameState: gameState, onComplete: onComplete)
        }
    }
}
