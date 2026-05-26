import Foundation
import SpriteKit
import UIKit

// MARK: - VFXManager
//
// Loads cyberpunk VFX frame sequences from `Sprites/vfx/` and instantiates
// looping ambient nodes per mission. Filenames follow the convention:
//   vfx_<key>_<NN>.png   e.g. vfx_code_cyan_01.png ... vfx_code_cyan_08.png
//
// If a frame set isn't present on disk (user hasn't sliced the atlas yet),
// the loader logs once and `makeAmbientNode` returns nil so the scene runs
// without crashing — VFX simply don't appear until the PNGs ship.
//
// Per-mission placement is data-driven via `MissionVFXManifest`. Call
// `applyAmbientVFX(to:missionId:)` from BattleScene after a room map loads.
//
@MainActor
final class VFXManager {

    static let shared = VFXManager()
    private init() {}

    /// Master kill-switch for ALL VFX (ambient room placement + helicopter pad
    /// loops + combat bursts). Flipped OFF 2026-05 while the artwork is being
    /// reworked — flip back to `true` to re-enable everything in one place
    /// without re-touching call sites.
    static let isEnabled = false

    // MARK: Texture cache

    private var frameCache: [String: [SKTexture]] = [:]
    private var loadedKeys: Set<String> = []
    private var missingKeysLogged: Set<String> = []

    /// Try filenames `vfx_<key>_01.png` ... `vfx_<key>_NN.png` until one
    /// fails. Caches the resulting array.
    func frames(for key: String, maxFrames: Int = 8) -> [SKTexture] {
        if let cached = frameCache[key] { return cached }
        var frames: [SKTexture] = []
        for i in 1...maxFrames {
            let name = String(format: "vfx_%@_%02d", key, i)
            if let tex = loadVFXTexture(named: name + ".png") {
                tex.filteringMode = .nearest
                frames.append(tex)
            } else {
                break
            }
        }
        if frames.isEmpty {
            if !missingKeysLogged.contains(key) {
                missingKeysLogged.insert(key)
                dlog("[VFXManager] No frames found for key=\(key) — slice atlas into Sprites/vfx/ as vfx_\(key)_01.png …")
            }
        } else {
            loadedKeys.insert(key)
            dlog("[VFXManager] Loaded \(frames.count) frames for key=\(key)")
        }
        frameCache[key] = frames
        return frames
    }

    private func loadVFXTexture(named filename: String) -> SKTexture? {
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("Sprites/vfx").appendingPathComponent(filename)
            if let img = UIImage(contentsOfFile: url.path) {
                return SKTexture(image: img)
            }
        }
        if let resourcePath = Bundle.main.resourcePath {
            let path = resourcePath + "/Sprites/vfx/" + filename
            if let img = UIImage(contentsOfFile: path) {
                return SKTexture(image: img)
            }
        }
        let sourceURL = URL(fileURLWithPath: #file)
        let url = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sprites/vfx")
            .appendingPathComponent(filename)
        if let img = UIImage(contentsOfFile: url.path) {
            return SKTexture(image: img)
        }
        return nil
    }

    // MARK: - VFX Effect descriptors

    /// All ambient effect identifiers that map to a `<key>` filename prefix.
    /// `frames(for:)` resolves "code_cyan" → vfx_code_cyan_01.png …
    enum Effect: String {
        case codeCyan          = "code_cyan"
        case codeRed           = "code_red"
        case codePurple        = "code_purple"
        case glitchBar         = "glitch_bar"
        case glitchScan        = "glitch_scan"
        case arcBlue           = "arc_blue"
        case arcYellow         = "arc_yellow"
        case smoke             = "smoke"
        case dust              = "dust"
        case embers            = "embers"
        case digitalParticles  = "digital"
        case floorRing         = "floor_ring"
        case floorArrow        = "floor_arrow"
        case microSpark        = "micro_spark"
        case microFlicker      = "micro_flicker"
        // ── Mission 04 — corrupted blood-tech aesthetic (added 2026-05) ─────
        case bloodStream       = "blood_stream"     // dripping vein/glow streams
        case rune              = "rune"             // glitching glyph rings
        case arcCorrupt        = "arc_corrupt"      // red + purple arcs
        case bloodMist         = "blood_mist"       // low-hang red atmosphere
        case ash               = "ash"              // soot/heat haze
        case corruptionCrack   = "corruption_crack" // creeping floor/wall cracks
        case aztechGold        = "aztech_gold"      // contrast clean tech edges
        case ritualPulse       = "ritual_pulse"     // floor ring pulse, ritual circles

        /// Recommended SpriteKit blend mode per the user's spec.
        var blendMode: SKBlendMode {
            switch self {
            case .codeCyan, .codeRed, .codePurple,
                 .arcBlue, .arcYellow, .arcCorrupt,
                 .glitchBar, .glitchScan,
                 .digitalParticles, .embers,
                 .floorRing, .floorArrow,
                 .microSpark, .microFlicker,
                 .bloodStream, .rune, .corruptionCrack,
                 .aztechGold, .ritualPulse:
                return .add
            case .smoke, .dust, .bloodMist, .ash:
                return .alpha
            }
        }

        /// Default per-effect base alpha. Tuned 2026-05 for SUBTLE ambience —
        /// the previous values (0.45-0.85) made effects pop too aggressively.
        /// Now max ~0.45, with atmospherics down to 0.18-0.25 so they read
        /// as "the room's mood" not "active VFX."
        var baseAlpha: CGFloat {
            switch self {
            // Bumped 2026-05 — previous values (0.18-0.45) were so faint
            // nothing was visible against dark mission backgrounds.
            case .smoke, .dust, .bloodMist, .ash:           return 0.50
            case .glitchBar, .glitchScan:                   return 0.65
            case .embers, .digitalParticles:                return 0.70
            case .microFlicker:                             return 0.80
            case .floorRing, .floorArrow,
                 .ritualPulse, .corruptionCrack:            return 0.55
            case .aztechGold:                               return 0.55
            case .codeCyan, .codeRed, .codePurple,
                 .bloodStream:                              return 0.75
            case .arcBlue, .arcYellow, .arcCorrupt,
                 .microSpark:                               return 0.85
            case .rune:                                     return 0.65
            }
        }

        /// Default size in points. SCALED DOWN from previous version which
        /// rendered way too large and dominated the screen. 64×64 is roughly
        /// one hex-tile diameter — readable ambient without overwhelming.
        var defaultSize: CGSize {
            switch self {
            // Bumped 2026-05 — previous values were too small to read.
            case .codeCyan, .codeRed, .codePurple,
                 .bloodStream:
                return CGSize(width: 80, height: 200)
            case .glitchBar, .glitchScan, .aztechGold:
                return CGSize(width: 180, height: 24)
            case .floorRing, .floorArrow, .ritualPulse:
                return CGSize(width: 96, height: 96)
            case .microSpark, .microFlicker:
                return CGSize(width: 36, height: 36)
            case .bloodMist, .ash:
                return CGSize(width: 150, height: 90)
            default:
                return CGSize(width: 80, height: 80)
            }
        }

        /// **Render mode** — animation strategy per effect.
        /// `.frameLoop` plays sliced frames sequentially (good for code rain,
        /// smoke that genuinely morphs, sparks).
        /// `.staticProp` picks just the FIRST frame and animates it via code
        /// (rotate/scale-pulse/drift). Used for "variant" effects whose atlas
        /// frames are different DESIGNS rather than animation states (runes,
        /// floor rings, aztech gold, corruption cracks). This avoids the
        /// "shifting images" jank the user reported.
        var renderMode: RenderMode {
            switch self {
            // Variants — different designs, not animation frames
            case .rune, .corruptionCrack, .aztechGold,
                 .floorRing, .ritualPulse:
                return .staticProp
            // Sequential frames — code drips, smoke morphs, sparks pop
            case .codeCyan, .codeRed, .codePurple,
                 .bloodStream, .smoke, .dust, .bloodMist, .ash,
                 .embers, .digitalParticles,
                 .glitchBar, .glitchScan,
                 .arcBlue, .arcYellow, .arcCorrupt,
                 .floorArrow,
                 .microSpark, .microFlicker:
                return .frameLoop
            }
        }
    }

    /// Animation strategy for an Effect.
    enum RenderMode {
        case frameLoop    // play sliced frames in sequence
        case staticProp   // first frame only, animate via SKAction
    }

    // MARK: - Node factory

    /// Per-effect default loop duration (seconds for one full cycle).
    /// Slow → smoke/mist atmosphere, mid → code/runes/embers/floor pulses,
    /// fast → glitch/sparks/electric. Tuned 2026-05 to fix "janky" timing.
    private static func defaultLoopDuration(for effect: Effect) -> TimeInterval {
        switch effect {
        case .smoke, .dust, .bloodMist, .ash:           return 2.6
        case .embers, .digitalParticles,
             .bloodStream, .rune, .corruptionCrack,
             .ritualPulse, .floorRing, .aztechGold:    return 1.6
        case .codeCyan, .codeRed, .codePurple:          return 1.1
        case .floorArrow:                               return 1.4
        case .glitchBar, .glitchScan:                   return 0.55
        case .arcBlue, .arcYellow, .arcCorrupt:         return 0.45
        case .microSpark, .microFlicker:                return 0.35
        }
    }

    /// Build a looping VFX node, or nil if frames are missing.
    /// Randomizes start frame + speed within ±15% so multiple instances
    /// don't tick in lockstep. Pass `baseDuration = 0` to use the per-effect
    /// default from `defaultLoopDuration(for:)` (recommended).
    func makeAmbientNode(effect: Effect, baseDuration: TimeInterval = 0) -> SKSpriteNode? {
        guard Self.isEnabled else { return nil }
        let f = frames(for: effect.rawValue)
        guard !f.isEmpty else { return nil }

        // ── Per-instance opacity jitter (75–100% of base alpha) ─────────
        // Multiple instances of the same effect now read as organic variation
        // instead of duplicates ticking in lockstep.
        let alphaJitter = CGFloat.random(in: 0.75...1.0)
        let instanceAlpha = effect.baseAlpha * alphaJitter

        let sprite = SKSpriteNode()
        sprite.size = effect.defaultSize
        sprite.alpha = instanceAlpha
        sprite.blendMode = effect.blendMode
        sprite.zPosition = 8  // above floor tiles (0..2.3), below characters (10+)

        switch effect.renderMode {
        case .frameLoop:
            let dur = (baseDuration > 0) ? baseDuration : Self.defaultLoopDuration(for: effect)
            let startIdx = Int.random(in: 0..<f.count)
            let rotated = Array(f[startIdx...]) + Array(f[..<startIdx])
            let speedJitter = Double.random(in: 0.85...1.15)
            let frameDur = (dur * speedJitter) / Double(rotated.count)
            sprite.texture = rotated.first
            let anim = SKAction.animate(with: rotated, timePerFrame: frameDur,
                                        resize: false, restore: false)
            sprite.run(SKAction.repeatForever(anim), withKey: "vfxLoop")

        case .staticProp:
            // Pick a random variant once, then animate via code only.
            let chosen = f[Int.random(in: 0..<f.count)]
            sprite.texture = chosen
            applyStaticPropAnimation(to: sprite, effect: effect)
        }
        return sprite
    }

    /// Drive variant effects (runes, floor rings, aztech gold, corruption
    /// cracks) with code-based motion instead of frame swapping. Each effect
    /// gets a tailored loop so they don't all rotate at the same speed.
    private func applyStaticPropAnimation(to sprite: SKSpriteNode, effect: Effect) {
        switch effect {
        case .rune:
            // Slow rotation + alpha breathing.
            let dur = TimeInterval.random(in: 6.0...9.0)
            sprite.run(SKAction.repeatForever(
                SKAction.rotate(byAngle: -.pi * 2, duration: dur)))
            let breathe = SKAction.sequence([
                SKAction.fadeAlpha(to: sprite.alpha * 0.6, duration: 1.4),
                SKAction.fadeAlpha(to: sprite.alpha,       duration: 1.4)
            ])
            sprite.run(SKAction.repeatForever(breathe), withKey: "vfxBreathe")

        case .floorRing, .ritualPulse:
            // Scale-pulse + slow rotate.
            let baseScale = sprite.xScale
            let pulse = SKAction.sequence([
                SKAction.scale(to: baseScale * 1.10, duration: 1.2),
                SKAction.scale(to: baseScale * 0.95, duration: 1.2)
            ])
            pulse.timingMode = .easeInEaseOut
            sprite.run(SKAction.repeatForever(pulse), withKey: "vfxPulse")
            sprite.run(SKAction.repeatForever(
                SKAction.rotate(byAngle: .pi * 2,
                                duration: TimeInterval.random(in: 14.0...20.0))))

        case .aztechGold:
            // Slow horizontal scan-line drift.
            let drift = SKAction.sequence([
                SKAction.moveBy(x: 6, y: 0, duration: 2.4),
                SKAction.moveBy(x: -6, y: 0, duration: 2.4)
            ])
            drift.timingMode = .easeInEaseOut
            sprite.run(SKAction.repeatForever(drift), withKey: "vfxDrift")
            let breathe = SKAction.sequence([
                SKAction.fadeAlpha(to: sprite.alpha * 0.5, duration: 1.6),
                SKAction.fadeAlpha(to: sprite.alpha,       duration: 1.6)
            ])
            sprite.run(SKAction.repeatForever(breathe), withKey: "vfxBreathe")

        case .corruptionCrack:
            // Cracks are mostly static — just gentle alpha flicker so they
            // read as creeping/spreading without actual movement.
            let flicker = SKAction.sequence([
                SKAction.fadeAlpha(to: sprite.alpha * 0.4, duration: 0.8),
                SKAction.fadeAlpha(to: sprite.alpha,       duration: 0.8),
                SKAction.fadeAlpha(to: sprite.alpha * 0.7, duration: 0.4),
                SKAction.fadeAlpha(to: sprite.alpha,       duration: 0.4)
            ])
            sprite.run(SKAction.repeatForever(flicker), withKey: "vfxFlicker")

        default:
            break
        }
    }

    // MARK: - Burst / one-shot

    /// One-shot burst (e.g. spark on hit). Removes self when done.
    func makeBurstNode(effect: Effect, totalDuration: TimeInterval = 0.35) -> SKSpriteNode? {
        guard Self.isEnabled else { return nil }
        let f = frames(for: effect.rawValue)
        guard !f.isEmpty else { return nil }
        let sprite = SKSpriteNode(texture: f.first)
        sprite.size = effect.defaultSize
        sprite.alpha = effect.baseAlpha
        sprite.blendMode = effect.blendMode
        sprite.zPosition = 95
        let frameDur = totalDuration / Double(f.count)
        let anim = SKAction.animate(with: f, timePerFrame: frameDur, resize: false, restore: false)
        sprite.run(SKAction.sequence([anim, .removeFromParent()]))
        return sprite
    }

    // MARK: - Mission ambient placement

    /// Spawn ambient VFX for the given mission/room into `scene`. Removes any
    /// previously-placed ambient nodes (tagged "vfxAmbient") first.
    /// Density rule: capped at 6 background VFX per room.
    func applyAmbientVFX(to scene: SKNode, missionId: String) {
        // Always wipe any pre-existing ambient nodes so when the kill-switch
        // is OFF we leave behind a clean scene.
        scene.enumerateChildNodes(withName: "//vfxAmbient") { node, _ in
            node.removeFromParent()
        }
        guard Self.isEnabled else {
            dlog("[VFXManager] applyAmbientVFX: disabled (isEnabled=false)")
            return
        }

        let placements = MissionVFXManifest.placements(for: missionId)
        dlog("[VFXManager] applyAmbientVFX missionId='\(missionId)' → \(placements.count) placements")
        guard !placements.isEmpty else { return }

        // Anchor positions — derived from the current scene's tilemap if we
        // can find one, otherwise default to a centered spread.
        let anchors = MissionVFXManifest.computeAnchors(in: scene)

        var spawned = 0
        let maxAmbient = 3   // hard cap — keep mission ambience SUBTLE
        for placement in placements where spawned < maxAmbient {
            let count = min(placement.count, maxAmbient - spawned)
            for _ in 0..<count {
                guard let node = makeAmbientNode(effect: placement.effect) else {
                    dlog("[VFXManager]   skipped \(placement.effect.rawValue): no frames")
                    continue
                }
                node.name = "vfxAmbient"
                node.position = anchors.position(for: placement.placement)
                node.zPosition = placement.zPosition
                scene.addChild(node)
                dlog("[VFXManager]   placed \(placement.effect.rawValue) @ \(node.position) z=\(node.zPosition) alpha=\(node.alpha)")
                spawned += 1
                if spawned >= maxAmbient { break }
            }
        }
        dlog("[VFXManager] applyAmbientVFX done — spawned=\(spawned)")
    }
}

// MARK: - Mission VFX Manifest

/// Where in the scene each ambient VFX lives.
enum VFXPlacementKind {
    case randomWall
    case randomCorner
    case randomFloor
    case nearTerminal
    case sceneCenter
    case extractionPad
}

struct VFXPlacement {
    let effect: VFXManager.Effect
    let placement: VFXPlacementKind
    let count: Int
    let zPosition: CGFloat
}

@MainActor
enum MissionVFXManifest {

    /// Per-mission ambient placement spec. The mission display id is the key
    /// (e.g. "Mission001", "Mission002", etc.) — falls back to the mission
    /// type name if the id isn't matched.
    static func placements(for missionId: String) -> [VFXPlacement] {
        let normalized = missionId.lowercased()
        if normalized.contains("001") || normalized.contains("extraction") {
            return mission01_ExtractionYard
        } else if normalized.contains("002") || normalized.contains("ghost") {
            return mission02_GhostProtocol
        } else if normalized.contains("003") || normalized.contains("mage") {
            return mission03_MageLair
        } else if normalized.contains("004") || normalized.contains("deadman") || normalized.contains("dead_man") {
            return mission04_DeadMansSwitch
        } else if normalized.contains("005") || normalized.contains("mekton") || normalized.contains("factory") {
            return mission05_MektonBlues
        } else if normalized.contains("006") || normalized.contains("aicore") || normalized.contains("ai_core") {
            return mission06_AICore
        }
        return []
    }

    // ── Density-cap reduced 2026-05 ─────────────────────────────────────
    // Previously 5-6 ambient nodes per room felt cluttered. Now 2-3 max,
    // with one signature effect per room + one supporting atmospheric.
    // "Less is more" per the user's spec.

    // MISSION 01 — corp yard: a wisp of smoke, occasional flicker.
    static let mission01_ExtractionYard: [VFXPlacement] = [
        VFXPlacement(effect: .smoke,         placement: .randomCorner, count: 1, zPosition: 22),
        VFXPlacement(effect: .microFlicker,  placement: .randomWall,   count: 1, zPosition: 27)
    ]

    // MISSION 02 — Ghost Protocol / datacenter: SIGNATURE = code rain.
    static let mission02_GhostProtocol: [VFXPlacement] = [
        VFXPlacement(effect: .codeCyan,         placement: .randomWall,    count: 2, zPosition: 24),
        VFXPlacement(effect: .digitalParticles, placement: .randomCorner,  count: 1, zPosition: 26)
    ]

    // MISSION 03 — Mage Lair: SIGNATURE = embers + ritual pulse.
    static let mission03_MageLair: [VFXPlacement] = [
        VFXPlacement(effect: .embers,    placement: .nearTerminal,  count: 1, zPosition: 26),
        VFXPlacement(effect: .floorRing, placement: .sceneCenter,   count: 1, zPosition: 5)
    ]

    // MISSION 04 — Dead Man's Switch: SIGNATURE = blood stream + rune (variant).
    static let mission04_DeadMansSwitch: [VFXPlacement] = [
        VFXPlacement(effect: .bloodStream,     placement: .randomWall,    count: 1, zPosition: 24),
        VFXPlacement(effect: .rune,            placement: .nearTerminal,  count: 1, zPosition: 27),
        VFXPlacement(effect: .bloodMist,       placement: .randomCorner,  count: 1, zPosition: 6)
    ]

    // MISSION 05 — Mekton Blues / factory: SIGNATURE = sparks + electric.
    static let mission05_MektonBlues: [VFXPlacement] = [
        VFXPlacement(effect: .arcBlue,    placement: .randomWall,   count: 1, zPosition: 28),
        VFXPlacement(effect: .microSpark, placement: .randomFloor,  count: 1, zPosition: 28)
    ]

    // MISSION 06 — AI Core: SIGNATURE = purple code + glitch (last room).
    static let mission06_AICore: [VFXPlacement] = [
        VFXPlacement(effect: .codePurple,       placement: .randomWall,   count: 2, zPosition: 24),
        VFXPlacement(effect: .glitchBar,        placement: .nearTerminal, count: 1, zPosition: 30)
    ]

    // MARK: Anchor resolution

    struct Anchors {
        let walls: [CGPoint]
        let corners: [CGPoint]
        let floors: [CGPoint]
        let terminals: [CGPoint]
        let center: CGPoint

        func position(for kind: VFXPlacementKind) -> CGPoint {
            switch kind {
            case .randomWall:     return walls.randomElement()    ?? center
            case .randomCorner:   return corners.randomElement()  ?? center
            case .randomFloor:    return floors.randomElement()   ?? center
            case .nearTerminal:   return terminals.randomElement() ?? center
            case .sceneCenter:    return center
            case .extractionPad:  return center
            }
        }
    }

    /// Walk the scene's tile-map nodes (named "tile_<x>_<y>") and bucket
    /// candidate positions for each placement kind. If no tiles are tagged,
    /// we just return a single-center anchor so VFX still appear.
    static func computeAnchors(in scene: SKNode) -> Anchors {
        var walls: [CGPoint] = []
        var corners: [CGPoint] = []
        var floors: [CGPoint] = []
        var terminals: [CGPoint] = []

        let gameState = GameState.shared
        let tiles = gameState.currentMissionTiles
        let height = tiles.count
        let width = tiles.first?.count ?? 0
        let wallRaw = TileType.wall.rawValue
        let termRaw = TileType.dataTerminal.rawValue

        for y in 0..<height {
            for x in 0..<width where x < tiles[y].count {
                let raw = tiles[y][x]
                let p = TileMap.tileCenter(x: x, y: y)
                if raw == wallRaw {
                    walls.append(p)
                    let isCorner = (x == 0 || x == width - 1) && (y == 0 || y == height - 1)
                    if isCorner { corners.append(p) }
                } else if raw == termRaw {
                    terminals.append(p)
                } else {
                    floors.append(p)
                }
            }
        }
        if corners.isEmpty { corners = walls }
        if walls.isEmpty   { walls   = floors }
        if terminals.isEmpty { terminals = floors }

        let center = floors.isEmpty
            ? CGPoint.zero
            : floors[floors.count / 2]
        return Anchors(walls: walls, corners: corners, floors: floors,
                       terminals: terminals, center: center)
    }
}
