import SpriteKit

/// Main SpriteKit scene for battle rendering and interaction.
final class BattleScene: SKScene {

    private enum EnemyIntentKind {
        case attack
        case move
        case defend
        case support
        case special
        case heavy
    }

    // MARK: - Properties

    private var tileMap: TileMap?
    /// Bottom padding added to scene height so the bottom row sits above the CombatUI bar.
    private let mapBottomPadding: CGFloat = 0
    /// Cached map dimensions for coordinate conversion — derived from the TileMap instance.
    /// Pointy-top odd-r bounding box:
    ///   width  = cols · hexColSpacing + R/2       (right-side pointy vertex extends 0.5R)
    ///   height = (rows + 0.5) · hexRowSpacing     (odd-col shift adds half a row down)
    private var mapPixelWidth: CGFloat { CGFloat(TileMap.mapWidth) * TileMap.hexColSpacing + TileMap.hexRadius * 0.5 }
    private var mapPixelHeight: CGFloat { (CGFloat(tileMap?.mapHeight ?? 9) + 0.5) * TileMap.hexRowSpacing }
    /// Scene-space offset of the tile map's bottom-left corner.
    /// With scene.size = map pixel dims and .aspectFit, this is (.zero) — map fills scene exactly.
    /// Scene-space Y offset applied to camera target; positive lowers the camera so the map sits higher on screen.
    private let firstTurnCameraYOffset: CGFloat = 36
    private var mapOrigin: CGPoint {
        CGPoint(
            x: max(0, (self.size.width  - mapPixelWidth)  / 2),
            y: max(0, (self.size.height - mapPixelHeight) / 2)
        )
    }
    private var characterNodes: [UUID: SKNode] = [:]
    private var selectedCharacterNode: SKNode?
    private var currentTurnIndex: Int = 0
    private var lastRenderedTraceTier: Int = -1

    /// Movement range for BFS pathfinding — 4 hexes per turn (SR5 sprint range for tactical mobility)
    private var movementRange: Int { return 2 }

    /// Current room ID — synced with RoomManager.currentRoomId during transitions.
    var currentRoomId: String = "room_0"

    /// Turn order list — set externally from TurnManager
    var turnOrder: [Character] = []

    /// Fade overlay for room transitions — stored so fadeOutFromTransition
    /// can use a direct reference instead of a name-based child lookup.
    private var fadeNode: SKNode?

    /// Track which door tiles have been auto-opened so we don't re-trigger.
    private var openedDoorKeys: Set<String> = []

    /// Blocks player input during enemy phase — set to true when player takes an action
    /// that ends their turn, and false when runEnemyPhase() completes.
    private var playerInputLocked: Bool = false

    /// Tracks whether an enemy phase is currently running.
    private var isEnemyPhaseRunning: Bool = false

    /// Timestamp (from update's currentTime) when isPlayerInputBlocked was last set to true.
    /// Used by the safety timeout to force-unblock if the enemy phase notification never fires.
    private var inputBlockedSince: TimeInterval?

    /// Tracks which character triggered the most recent door transition.
    /// Only this character gets moved to the connection target spawn — others keep their positions.
    private var doorTransitionCharacterId: UUID?

    /// First-tap timestamp of the "hack the terminal" warning. When the player
    /// tries to leave a room that still contains an unhacked required terminal,
    /// we BLOCK the transition once and post a warning. A second tap on the
    /// door within `warnConfirmWindow` seconds confirms they want to skip the
    /// terminal anyway and lets the transition through. Reset to nil when the
    /// room changes.
    private var lastTerminalWarningAt: Date?
    private let warnConfirmWindow: TimeInterval = 5.0

    // MARK: - Pending Initial Load
    // BattleSceneView stashes these BEFORE presentScene; didMove processes them AFTER
    // the view is attached. This eliminates timing issues around scene.size / mapOrigin
    // that caused characters to be invisible on first render.
    private var pendingInitialTileMap: TileMap?
    private var pendingInitialRoomId: String?
    private var pendingInitialCharacters: [Character] = []
    private var pendingInitialEnemies: [Enemy] = []

    /// Called by BattleSceneView BEFORE presentScene. Stashes the initial tilemap and
    /// roster so didMove can perform the actual loadMap/placeCharacter/placeEnemy with
    /// the view attached and scene.size final.
    func scheduleInitialLoad(tileMap: TileMap, roomId: String, characters: [Character], enemies: [Enemy]) {
        self.pendingInitialTileMap = tileMap
        self.pendingInitialRoomId = roomId
        self.pendingInitialCharacters = characters
        self.pendingInitialEnemies = enemies
    }

    // MARK: - Scene Setup

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(hex: "#05060A")  // near-black, makes hex gaps look good
        // Now that the view is attached, make scene.size match the view bounds so
        // mapOrigin centers the map correctly in the viewport.
        fitSceneToView()
        setupCamera()
        positionCameraOnMap()
        setupEnemyNotifications()
        setupRoomNotifications()
        setupLongPressRecognizer()
        EffectsManager.shared.addRainEffect(to: self)

        // Process pending initial load NOW, with the view attached and scene sized.
        // This is the single-source-of-truth path for first-frame characters/enemies.
        if let tmap = pendingInitialTileMap {
            if childNode(withName: "TileMap") == nil {
                loadMap(tmap)
            }
            if let rid = pendingInitialRoomId { currentRoomId = rid }
            for character in pendingInitialCharacters { placeCharacter(character) }
            for enemy in pendingInitialEnemies { placeEnemy(enemy) }
            let initialFocusId =
                GameState.shared.activeCharacterId
                ?? GameState.shared.selectedCharacterId
                ?? pendingInitialCharacters.first(where: { $0.isAlive })?.id
            pendingInitialTileMap = nil
            pendingInitialRoomId = nil
            pendingInitialCharacters = []
            pendingInitialEnemies = []
            if let initialFocusId {
                focusCamera(on: initialFocusId)
                showSelectionRing(for: initialFocusId)
                updatePlayerIdleAnimations(activeId: initialFocusId)
            } else {
                positionCameraOnMap()
            }
            dlog("[BattleScene] didMove: initial load complete, characterNodes=\(characterNodes.count)")
        }

        // Safety net: if the first-frame handoff raced and the pending arrays were empty,
        // reconcile directly from GameState once the scene is live. This makes the scene
        // robust against SwiftUI / SpriteKit timing weirdness during the title → briefing → combat hop.
        syncCombatantsFromGameState(reason: "didMove")
        DispatchQueue.main.async { [weak self] in
            self?.syncCombatantsFromGameState(reason: "didMove-async")
        }

        // Camera-attached overlays: vignette + scanlines. Adding to the camera
        // ensures they stay fixed on screen regardless of camera position.
        if let cam = camera {
            // Vignette — dark border around the viewport edge
            let vignette = SKShapeNode(rectOf: CGSize(width: self.size.width * 1.6, height: self.size.height * 1.6))
            vignette.fillColor = .clear
            vignette.strokeColor = UIColor.black.withAlphaComponent(0.35)
            vignette.lineWidth = self.size.width * 0.28
            vignette.position = .zero   // camera center
            vignette.zPosition = 90
            vignette.name = "vignette"
            cam.addChild(vignette)

            // Subtle CRT scanlines — fixed overlay on viewport
            addSubtleScanlines(to: cam)
        }
        refreshTraceVisuals(force: true)
    }

    private func addSubtleScanlines(to parent: SKNode) {
        let scanlineNode = SKNode()
        scanlineNode.zPosition = 85
        scanlineNode.name = "subtleScanlines"

        // Camera space: (0,0) = center. Scanlines cover full viewport.
        let scanlineSpacing: CGFloat = 3
        let startY = -size.height / 2
        let endY = size.height / 2
        var y: CGFloat = startY

        while y < endY {
            let scanline = SKShapeNode(rectOf: CGSize(width: size.width, height: 0.5))
            scanline.fillColor = UIColor.black.withAlphaComponent(0.05)
            scanline.strokeColor = .clear
            scanline.position = CGPoint(x: 0, y: y)
            scanlineNode.addChild(scanline)
            y += scanlineSpacing
        }

        parent.addChild(scanlineNode)
    }

    /// Add a UIKit long-press recognizer to the SKView so a sustained press
    /// on a character or enemy tile surfaces their info-dossier sheet. Single
    /// taps still flow through `touchesBegan` → `handleTileTap` for
    /// move/select/attack — long-press doesn't consume that path.
    private func setupLongPressRecognizer() {
        guard let view = self.view else { return }
        let lpr = UILongPressGestureRecognizer(target: self,
                                               action: #selector(handleLongPress(_:)))
        lpr.minimumPressDuration = 0.45
        lpr.allowableMovement = 12
        lpr.delaysTouchesBegan = false
        view.addGestureRecognizer(lpr)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Only fire on .began so we don't spam multiple sheet requests.
        guard gesture.state == .began else { return }
        guard let view = self.view else { return }
        // Convert UIKit point → scene point via SpriteKit's helper.
        let viewPoint = gesture.location(in: view)
        let scenePoint = convertPoint(fromView: viewPoint)
        // Same hex math as touchesBegan.
        let rawX = Int((scenePoint.x - mapOrigin.x) / TileMap.hexColSpacing)
        let clampedX = max(0, min(rawX, TileMap.mapWidth - 1))
        let colYOffset: CGFloat = (clampedX % 2 == 1) ? TileMap.hexRowSpacing / 2.0 : 0
        let rawY = Int((scenePoint.y - mapOrigin.y - colYOffset) / TileMap.hexRowSpacing)
        let clampedY = max(0, min(rawY, (tileMap?.mapHeight ?? 9) - 1))

        // Find a character or enemy at this tile; ignore if neither.
        if let char = GameState.shared.playerTeam.first(where: {
            $0.positionX == clampedX && $0.positionY == clampedY && $0.isAlive
        }) {
            HapticsManager.shared.selectionChanged()
            NotificationCenter.default.post(
                name: .entityInfoRequested,
                object: nil,
                userInfo: ["kind": "player", "characterId": char.id.uuidString]
            )
        } else if let enemy = GameState.shared.enemies.first(where: {
            $0.positionX == clampedX && $0.positionY == clampedY && $0.isAlive
        }) {
            HapticsManager.shared.selectionChanged()
            NotificationCenter.default.post(
                name: .entityInfoRequested,
                object: nil,
                userInfo: ["kind": "enemy", "enemyId": enemy.id.uuidString]
            )
        }
    }

    private func setupRoomNotifications() {
        NotificationCenter.default.addObserver(forName: .roomTransitionStarted, object: nil, queue: .main) { [weak self] _ in
            self?.performRoomTransitionFade()
        }
        NotificationCenter.default.addObserver(forName: .roomTransitionCompleted, object: nil, queue: .main) { [weak self] _ in
            self?.handleRoomTransitionCompleted()
        }
        // Room navigation arrows in CombatUI
        NotificationCenter.default.addObserver(forName: .roomNavigationRequested, object: nil, queue: .main) { [weak self] notification in
            guard let dir = notification.userInfo?["direction"] as? String else { return }
            self?.handleRoomNavigationArrow(direction: dir)
        }
        NotificationCenter.default.addObserver(forName: .roomCleared, object: nil, queue: .main) { [weak self] _ in
            self?.refreshObjectiveMarkers()
        }
        NotificationCenter.default.addObserver(forName: .grimoireAcquired, object: nil, queue: .main) { [weak self] _ in
            self?.handleGrimoireAcquired()
        }
        NotificationCenter.default.addObserver(forName: .barriersDropped, object: nil, queue: .main) { [weak self] note in
            guard let coords = note.userInfo?["tiles"] as? [[String: Int]] else { return }
            self?.dropBarrierTiles(coords: coords)
        }
        NotificationCenter.default.addObserver(forName: .extractionAnimationRequested, object: nil, queue: .main) { [weak self] note in
            guard let x = note.userInfo?["x"] as? Int,
                  let y = note.userInfo?["y"] as? Int else { return }
            // The notification queue is `.main`, so the closure already runs
            // on the main thread, but Swift's strict concurrency check needs
            // an explicit @MainActor hop to verify it.
            Task { @MainActor [weak self] in
                let type = RoomManager.shared.currentMission?.extractionType ?? "helicopter"
                switch type {
                case "ladder":
                    self?.playLadderExtractionAnimation(extractionX: x, extractionY: y)
                case "door":
                    self?.playDoorExtractionAnimation(extractionX: x, extractionY: y)
                case "rooftop_heli":
                    // M4 — heli is already parked on the rooftop. Skip the
                    // dramatic descent and just animate the takeoff.
                    self?.playRooftopHeliExtraction(extractionX: x, extractionY: y)
                default:
                    self?.playExtractionHelicopterAnimation(extractionX: x, extractionY: y)
                }
            }
        }
    }

    // MARK: - Helicopter Extraction Animation

    /// Plays the helicopter extraction sequence over the given extraction tile.
    /// 1. Players fade out (beamed up)
    /// 2. Heli appears at the tile, spins up, hovers
    /// 3. Heli ascends and flies off-screen
    /// 4. On completion, posts .extractionAnimationCompleted and calls
    ///    CombatFlowController.finalizeExtractionAfterAnimation so the debrief shows.
    /// Park a stationary helicopter on the extraction tile of the current room
    /// (if there is one). Loaded at room start so the player sees the heli
    /// waiting for them on the helipad. Removed when the actual extraction
    /// animation begins so the animated heli takes over.
    func addStationaryExtractionHelicopter() {
        // Remove any previous stationary heli (e.g. from a different room)
        childNode(withName: "stationaryHeli")?.removeFromParent()

        // Skip stationary heli for non-helicopter extraction types
        // (ladder = climb-out, door = freight elevator, etc.).
        // "rooftop_heli" (M4) also wants the parked heli visible during play —
        // its takeoff sequence reuses this same stationary node.
        let type = RoomManager.shared.currentMission?.extractionType ?? "helicopter"
        guard type == "helicopter" || type == "rooftop_heli" else { return }

        // Only show if there's an active extraction tile in the current room
        guard let _ = RoomManager.shared.currentRoom else {
            if !hasExtractionTile() { return }
            placeStationaryHeli()
            return
        }
        guard RoomManager.shared.isExtractionActive() else { return }
        placeStationaryHeli()
    }

    /// Returns true if the active tile map contains an extraction tile.
    private func hasExtractionTile() -> Bool {
        guard let tm = self.tileMap else { return false }
        for row in tm.tiles { if row.contains(.extraction) { return true } }
        return false
    }

    private func placeStationaryHeli() {
        let extractX = GameState.shared.extractionX
        let extractY = GameState.shared.extractionY
        let center = TileMap.tileCenter(x: extractX, y: extractY)
        let mapNode = childNode(withName: "TileMap") ?? self
        let origin = mapNode.position

        guard let idleTex = loadHeliTexture("idle_0") else { return }
        let heli = SKSpriteNode(texture: idleTex)
        // Preserve source aspect — chopper PNG is ~228×130 (≈1.75:1). Forcing
        // 3.4×3.0 hex-radii (≈1.13:1) was stretching it vertically and reading
        // as the bottom (landing skids) being cut off. Width-anchor at 3.4
        // hex-radii; height follows the source aspect.
        let heliW: CGFloat = TileMap.hexRadius * 3.4
        let heliH: CGFloat = heliW * (idleTex.size().height / max(1, idleTex.size().width))
        heli.size = CGSize(width: heliW, height: heliH)
        // Anchor centered. The y-offset lifts the sprite so its BOTTOM edge
        // sits AT the tile center — with anchor (0.5, 0.5) the sprite extends
        // ±heliH/2 from the position, so the multiplier must be 0.5 (not 0.35)
        // to fully clear the lower play-area / HUD edge. The previous 0.35
        // left ~15% of the chopper's lower body (skids/wash) dangling below
        // tile center where it got visually cropped — that was the "M1 heli
        // is cut off at the bottom" bug. 0.55 hovers it just slightly above
        // the pad for a "parked, blades idling" read.
        heli.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        heli.position = CGPoint(x: origin.x + center.x,
                                y: origin.y + center.y + heliH * 0.55)
        heli.zPosition = 8     // above background, below characters
        heli.alpha = 0.92
        heli.name = "stationaryHeli"
        addChild(heli)

        // Slow rotor idle cycle (3 frames at 0.45s each — feels grounded, not poised to take off)
        let idleFrames = (0..<3).compactMap { loadHeliTexture("idle_\($0)") }
        if idleFrames.count >= 2 {
            heli.run(SKAction.repeatForever(SKAction.animate(with: idleFrames, timePerFrame: 0.45)))
        }
    }

    private func playExtractionHelicopterAnimation(extractionX: Int, extractionY: Int) {
        playerInputLocked = true

        let center = TileMap.tileCenter(x: extractionX, y: extractionY)
        let mapNode = childNode(withName: "TileMap") ?? self
        let mapOriginPos = mapNode.position
        // Pre-compute heliH so `landedPos` can lift the chopper UP by 0.55×H.
        // Anchor is centered (0.5, 0.5), so the sprite extends ±heliH/2 from
        // its position. A 0.55 multiplier puts the BOTTOM edge slightly
        // ABOVE the tile center — keeping the entire sprite (including the
        // chopper's lower skids / rotor downwash) inside the visible play
        // area. Previous 0.35 was too conservative and left ~15% of the
        // image getting clipped by the HUD / lower tile-grid edge.
        let landedHeliW: CGFloat = TileMap.hexRadius * 3.4
        let landedHeliH: CGFloat = landedHeliW * (130.0 / 228.0)   // source aspect
        let landedPos = CGPoint(x: mapOriginPos.x + center.x,
                                y: mapOriginPos.y + center.y + landedHeliH * 0.55)

        // Remove any leftover stationary heli from a previous load.
        childNode(withName: "stationaryHeli")?.removeAllActions()
        childNode(withName: "stationaryHeli")?.removeFromParent()
        // Also clear any in-flight extraction heli (defensive — should never
        // exist, but if a prior animation didn't finish cleanly, kill it).
        childNode(withName: "extractionHelicopter")?.removeAllActions()
        childNode(withName: "extractionHelicopter")?.removeFromParent()

        // Load all the per-phase rotor-cycle frame sets. The sprite sheet
        // gives us the SAME chopper position with the rotor at 3 different
        // blade angles per phase — so cycling these now actually animates
        // the rotor properly (no body wobble like the bad cuts before).
        // Used as the body texture cycle in setRotor() below.
        let idleFrames      = (0..<3).compactMap { loadHeliTexture("idle_\($0)") }
        let hoverFrames     = (0..<3).compactMap { loadHeliTexture("hover_\($0)") }
        let spinFrames      = (0..<3).compactMap { loadHeliTexture("spinup_\($0)") }
        let takeoffFrames   = (0..<3).compactMap { loadHeliTexture("takeoff_\($0)") }
        let ascendFrames    = (0..<3).compactMap { loadHeliTexture("ascending_\($0)") }
        let departingFrames = (0..<3).compactMap { loadHeliTexture("departing_\($0)") }
        // Legacy "flightFrames" alias for descent — uses idle frames since
        // the sheet has no separate flight column.
        let flightFrames = idleFrames

        // First-frame fallback chain — descent uses flight (= idle) as start.
        let firstTex: SKTexture? = flightFrames.first
            ?? hoverFrames.first
            ?? loadHeliTexture("idle_0")

        // Spawn well above the visible scene so the heli flies in from above.
        let skyOffset: CGFloat = self.size.height * 0.65 + 200
        let skyStart = CGPoint(x: landedPos.x - 80, y: landedPos.y + skyOffset)

        let heli = SKSpriteNode()
        if let tex = firstTex { heli.texture = tex }
        // Size using source aspect — same fix as stationary heli, prevents
        // the vertical stretch that read as a "cut-off bottom."
        let heliW: CGFloat = TileMap.hexRadius * 3.4
        let heliH: CGFloat = {
            guard let tex = firstTex else { return TileMap.hexRadius * 3.0 }
            return heliW * (tex.size().height / max(1, tex.size().width))
        }()
        heli.size = CGSize(width: heliW, height: heliH)
        // Centered anchor — same fix as the stationary heli. The `landedPos`
        // y-offset above (landedHeliH * 0.55) lifts the BOTTOM edge of the
        // sprite to ~0.05H ABOVE the tile center, keeping the whole canvas
        // (including the chopper's lower skids / rotor downwash) inside the
        // visible play area. Anchor (0.5, 0.5) is just centered; the lift
        // does all the work.
        heli.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        heli.position = skyStart
        heli.zPosition = 60
        heli.alpha = 1.0
        heli.setScale(0.55)   // small at the start of descent (perspective)
        heli.name = "extractionHelicopter"
        addChild(heli)

        // The helicopter sprite-sheet's "flight/hover/spinup/takeoff" frames
        // are different CAMERA ANGLES of the chopper, not rotor-only animation
        // states. Cycling between them rapidly made the whole body appear to
        // spin/wobble. We lock the body to a single texture and add a
        // procedural ROTOR overlay — a fast-spinning thin black ellipse
        // positioned at the rotor head + a faint translucent disc for
        // motion-blur — so the rotor LOOKS like it's whirling without
        // touching the body texture.
        let rotorContainer = SKNode()
        rotorContainer.name = "heliRotor"
        // Position relative to the chopper sprite — rotor sits near the top
        // of the body (sprite is anchored center, so +y from center).
        // With heli.size.height = 108, the rotor head is roughly +30px above
        // sprite center. Tuned by visual fit.
        rotorContainer.position = CGPoint(x: 0, y: 30)
        rotorContainer.zPosition = 0.5  // above the body texture
        heli.addChild(rotorContainer)

        // ── Real rotor frames take precedence ─────────────────────────────
        // Drop frames named rotor_0.png … rotor_3.png (or as many as you
        // have, named consecutively starting at 0) into
        // Sprites/effects/helicopter/, and we'll cycle them as a real
        // SKSpriteNode on the rotor head — same camera angle, just blade
        // rotation. Frame duration is set per phase by setRotor().
        var rotorFrameTextures: [SKTexture] = []
        if let resourceURL = Bundle.main.resourceURL {
            for i in 0..<8 {
                let url = resourceURL.appendingPathComponent("Sprites/effects/helicopter/rotor_\(i).png")
                guard let img = UIImage(contentsOfFile: url.path) else { break }
                rotorFrameTextures.append(SKTexture(image: img))
            }
        }
        let rotorSprite: SKSpriteNode? = {
            guard let first = rotorFrameTextures.first else { return nil }
            // Size the rotor sprite to match the chopper's rotor disc footprint.
            // We assume the source frame's PNG is already cropped to just the
            // rotor (transparent body), at roughly chopper-rotor proportions.
            let s = SKSpriteNode(texture: first)
            // Default to a width similar to the previous procedural disc; the
            // sprite's own aspect drives the height.
            let targetWidth: CGFloat = 90
            let scale = targetWidth / max(1, s.size.width)
            s.setScale(scale)
            s.zPosition = 1
            return s
        }()
        if let rs = rotorSprite {
            rotorContainer.addChild(rs)
            dlog("[BattleScene] heli rotor: using \(rotorFrameTextures.count) sprite frame(s)")
        } else {
            // ── Procedural fallback ─────────────────────────────────────
            // No rotor sprite frames found — fall back to the motion-blur
            // disc + thin streak so the rotor still reads as spinning.
            // This is a placeholder; real frames look better.
            let rotorDiscOuter = SKShapeNode(ellipseOf: CGSize(width: 76, height: 14))
            rotorDiscOuter.fillColor = UIColor.black.withAlphaComponent(0.18)
            rotorDiscOuter.strokeColor = .clear
            rotorDiscOuter.zPosition = 0
            rotorContainer.addChild(rotorDiscOuter)

            let rotorDiscInner = SKShapeNode(ellipseOf: CGSize(width: 60, height: 6))
            rotorDiscInner.fillColor = UIColor.black.withAlphaComponent(0.42)
            rotorDiscInner.strokeColor = .clear
            rotorDiscInner.zPosition = 1
            rotorContainer.addChild(rotorDiscInner)

            let bladeHint = SKShapeNode(rectOf: CGSize(width: 70, height: 1.2), cornerRadius: 0.6)
            bladeHint.fillColor = UIColor.black.withAlphaComponent(0.55)
            bladeHint.strokeColor = .clear
            bladeHint.zPosition = 2
            rotorContainer.addChild(bladeHint)

            let hub = SKShapeNode(circleOfRadius: 2.5)
            hub.fillColor = UIColor(white: 0.25, alpha: 1.0)
            hub.strokeColor = UIColor(white: 0.05, alpha: 1.0)
            hub.lineWidth = 0.5
            hub.zPosition = 3
            rotorContainer.addChild(hub)
        }

        // setRotor: drives the rotor visual per phase.
        //
        // Priority order:
        //   1. Real rotor sprite frames (rotor_*.png) — cycle them on a
        //      transparent overlay above the body. Most accurate.
        //   2. Body-texture cycle — phase frames (idle_0..2, hover_0..2,
        //      etc.) are "same chopper, rotor at different blade angles."
        //      Cycling them animates the in-body rotor.
        //   3. Procedural disc overlay — last-ditch rotating ellipse if
        //      neither sprite frames nor body frames exist.
        //
        // The procedural overlay (option 3) used to render on top of
        // option 2's body cycle, producing a double-rotor look. Hide it
        // whenever option 1 or 2 is active.
        func setRotor(_ frames: [SKTexture], timePerFrame: TimeInterval) {
            // Option 1: dedicated rotor sprite frames.
            if let rs = rotorSprite, rotorFrameTextures.count >= 2 {
                heli.removeAction(forKey: "rotorCycle")
                rotorContainer.isHidden = false
                rs.removeAction(forKey: "rotorSpriteCycle")
                let cycle = SKAction.animate(with: rotorFrameTextures,
                                              timePerFrame: timePerFrame,
                                              resize: false, restore: false)
                rs.run(SKAction.repeatForever(cycle), withKey: "rotorSpriteCycle")
                return
            }
            // Option 2: body-texture cycle. Hide the procedural overlay so
            // it doesn't render on top of the body's baked-in rotor.
            if frames.count >= 2 {
                heli.removeAction(forKey: "rotorCycle")
                let cycle = SKAction.animate(with: frames,
                                              timePerFrame: timePerFrame,
                                              resize: false, restore: false)
                heli.run(SKAction.repeatForever(cycle), withKey: "rotorCycle")
                rotorContainer.isHidden = true
                rotorContainer.removeAction(forKey: "spin")
                return
            }
            // Option 3: procedural overlay (last resort).
            rotorContainer.isHidden = false
            let revolutionDuration = max(0.06, min(0.11, timePerFrame))
            rotorContainer.removeAction(forKey: "spin")
            rotorContainer.run(
                SKAction.repeatForever(
                    SKAction.rotate(byAngle: .pi * 2, duration: revolutionDuration)
                ),
                withKey: "spin"
            )
        }
        // Kick off an initial rotor spin so it reads as "running" while the
        // sprite is descending from the sky. Phases below adjust the speed.
        setRotor(flightFrames, timePerFrame: 0.06)

        // Phase 1 — DESCENT (4.0s, slower + smoother). Single locked body
        // texture. easeInEaseOut + extended duration reads as a real chopper
        // settling in. Bumped 3.0 → 4.0 per playtest note "make heli movement
        // a bit slower and smoother."
        setRotor(flightFrames, timePerFrame: 0.06)
        let descend = SKAction.group([
            SKAction.move(to: landedPos, duration: 4.0),
            SKAction.scale(to: 1.0, duration: 4.0)
        ])
        descend.timingMode = .easeInEaseOut

        // Triggered VFX: ~1s code-rain burst behind the chopper, kicked off
        // ~0.4s into descent so it reads as the chopper "breaking through"
        // the data atmosphere on approach. Procedural cyan glyphs falling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self,
                  let heli = self.childNode(withName: "extractionHelicopter")
            else { return }
            EffectsManager.shared.emitChopperCodeRain(behind: heli, in: self)
        }

        // Helipad ambience — pulse ring on the pad (looping) + dust swirl that
        // intensifies during touchdown/lift-off. Both are no-ops if their VFX
        // PNGs haven't been sliced yet.
        let padNodeName = "heliPadVFX"
        childNode(withName: padNodeName)?.removeFromParent()
        let padContainer = SKNode()
        padContainer.position = landedPos
        padContainer.zPosition = 5  // under the heli (z=60), above floor tiles
        padContainer.name = padNodeName
        addChild(padContainer)
        if let pulse = VFXManager.shared.makeAmbientNode(effect: .floorRing, baseDuration: 1.4) {
            pulse.position = .zero
            padContainer.addChild(pulse)
        }
        // Dust loop that lives under the chopper for the entire animation —
        // alpha-blended so it reads as actual dust, not a glow.
        if let dust = VFXManager.shared.makeAmbientNode(effect: .dust, baseDuration: 1.0) {
            dust.position = CGPoint(x: 0, y: -8)
            dust.alpha = 0.0
            dust.run(SKAction.fadeAlpha(to: 0.55, duration: 0.6))
            padContainer.addChild(dust)
        }

        // Phase 2 — TOUCHDOWN bob (0.6s, smoother). Slight easing so the
        // chopper settles instead of jerking on contact.
        let bobDown = SKAction.moveBy(x: 0, y: -3, duration: 0.28)
        bobDown.timingMode = .easeInEaseOut
        let bobUp = SKAction.moveBy(x: 0, y: 3, duration: 0.32)
        bobUp.timingMode = .easeInEaseOut
        let touchdown = SKAction.sequence([bobDown, bobUp])

        // Phase 3 — runners board + heli idles on pad (2.2s total).
        // 2026-05-10: was "fade in place". Runners now actually WALK to the
        // helicopter then fade as they "board it" — visually clear that they
        // left the map. waitOnPad bumped 1.4 → 2.2s so the walk + fade has
        // time to complete before takeoff.
        let onLanded = SKAction.run { [weak self] in
            guard let self = self else { return }
            // Switch to hover/idle frames (slower rotor) while parked.
            setRotor(hoverFrames, timePerFrame: 0.12)
            // Walk each living player to the heli, then fade out as they board.
            // Only player characters — enemies should be dead/cleared by now.
            let boardPos = self.tileCenter(extractionX, extractionY)
            for char in GameState.shared.playerTeam where char.isAlive {
                guard let node = self.characterNodes[char.id] else { continue }
                let walk = SKAction.move(to: boardPos, duration: 1.0)
                walk.timingMode = .easeIn
                let fade = SKAction.fadeOut(withDuration: 0.5)
                // Walk first, then fade as they reach/enter the chopper.
                node.run(SKAction.sequence([walk, fade]))
            }
            // Touchdown dust burst — one-shot.
            if let burst = VFXManager.shared.makeBurstNode(effect: .dust, totalDuration: 0.6) {
                burst.position = landedPos
                burst.zPosition = 6
                self.addChild(burst)
            }
        }
        let waitOnPad = SKAction.wait(forDuration: 2.2)

        // Phase 4 — SPIN-UP rotor (0.5s).
        let spinUp = SKAction.run { setRotor(spinFrames, timePerFrame: 0.08) }
        let spinPause = SKAction.wait(forDuration: 0.5)

        // Phase 5 — LIFT-OFF (1.4s upward, slower + smoother). easeInEaseOut
        // so the chopper unsticks gradually instead of snapping skyward.
        // Was 1.0s/easeIn.
        let liftOffPhase = SKAction.run { [weak self] in
            setRotor(takeoffFrames, timePerFrame: 0.07)
            // Second dust burst as the chopper kicks off.
            if let self = self,
               let burst = VFXManager.shared.makeBurstNode(effect: .dust, totalDuration: 0.7) {
                burst.position = landedPos
                burst.zPosition = 6
                self.addChild(burst)
            }
        }
        let liftOff = SKAction.moveBy(x: 0, y: 40, duration: 1.4)
        liftOff.timingMode = .easeInEaseOut

        // Phase 6 — ASCEND off-screen (4.0s, slower + smoother). easeInEaseOut
        // so the chopper accelerates gradually rather than yanking upward.
        // Bumped 3.0 → 4.0 to match the new descent pacing.
        let ascendPhase = SKAction.run { setRotor(ascendFrames, timePerFrame: 0.10) }
        let ascend = SKAction.group([
            SKAction.move(to: CGPoint(x: landedPos.x + 80, y: landedPos.y + skyOffset),
                          duration: 4.0),
            SKAction.scale(to: 0.55, duration: 4.0)
        ])
        ascend.timingMode = .easeInEaseOut

        // Phase 7 — DEPART fade (0.7s). Body texture stays locked — the
        // departingFrames cycle would spin the body (see flight-frame note
        // above).
        _ = departingFrames
        let depart = SKAction.fadeOut(withDuration: 0.7)

        // Final closure — must run BEFORE removeFromParent so the node still
        // ticks when this fires. Resets state + tells the game logic the
        // animation is done and combat can finalize.
        let onComplete = SKAction.run { [weak self] in
            // Fade out pad VFX with the chopper.
            self?.childNode(withName: "heliPadVFX")?
                .run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            CombatFlowController.completeExtractionFinalize()
        }

        let sequence = SKAction.sequence([
            descend,
            touchdown,
            onLanded,
            waitOnPad,
            spinUp,
            spinPause,
            liftOffPhase,
            liftOff,
            ascendPhase,
            ascend,
            depart,
            onComplete,
            SKAction.removeFromParent()
        ])
        heli.run(sequence, withKey: "heliSequence")

        // Belt-and-suspenders: a dispatched timer that fires the same
        // finalize as a safety net.
        // 2026-05-10: 10s → 13s. After waitOnPad bumped to 2.2s,
        // animation grew to ~9.8s.
        // 2026-05-14: 13s → 14s. Smoother descent (2.5→3.0s), touchdown
        // (0.4→0.6s) and ascend (2.5→3.0s) pushed the full sequence to
        // ~11s — keep ~3s of safety-net lead.
        // 2026-05-18: 14s → 17s. Slower + smoother heli per playtest:
        // descent 3.0→4.0, liftOff 1.0→1.4, ascend 3.0→4.0. Total ~13.4s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 17.0) { [weak self] in
            CombatFlowController.completeExtractionFinalize()
            self?.playerInputLocked = false
            self?.childNode(withName: "extractionHelicopter")?.removeFromParent()
            self?.childNode(withName: "heliPadVFX")?.removeFromParent()
        }
    }

    /// Door extraction: runners walk to the extraction tile and fade out as
    /// they walk through (e.g. M5 mech bay freight elevator). No helicopter.
    /// Rooftop helicopter extraction (M4 "Dead Man's Switch"). The chopper
    /// is already parked on the helipad (placed by
    /// `addStationaryExtractionHelicopter`). This sequence skips the
    /// dramatic flying-in descent the user called "dumb-looking" and just
    /// has the runners walk to the heli + the parked heli take off.
    ///
    /// Flow:
    ///   1. Each runner walks to the extraction tile and fades out (boarding)
    ///   2. Quick rotor SFX kick + dust burst
    ///   3. Stationary heli ascends + drifts off-screen
    ///   4. Finalize extraction
    private func playRooftopHeliExtraction(extractionX: Int, extractionY: Int) {
        playerInputLocked = true
        let center = TileMap.tileCenter(x: extractionX, y: extractionY)
        let mapNode = childNode(withName: "TileMap") ?? self
        let originX = mapNode.position.x + center.x
        let originY = mapNode.position.y + center.y

        // 1. Walk + fade the runners (staggered, like the door pattern).
        var staggerDelay: TimeInterval = 0
        let livingCount = max(1, characterNodes.count)
        let staggerPerChar: TimeInterval = 0.45
        for (_, node) in characterNodes {
            let board = SKAction.sequence([
                SKAction.wait(forDuration: staggerDelay),
                SKAction.move(to: CGPoint(x: originX, y: originY), duration: 0.6),
                SKAction.fadeOut(withDuration: 0.4)
            ])
            node.run(board)
            staggerDelay += staggerPerChar
        }

        // Total board time: stagger * count + final fade.
        let boardEnd = TimeInterval(livingCount) * staggerPerChar + 0.4

        // 2. After everyone's aboard, spin up + take off the parked heli.
        run(SKAction.sequence([
            SKAction.wait(forDuration: boardEnd + 0.2),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                guard let heli = self.childNode(withName: "stationaryHeli") as? SKSpriteNode else {
                    // Heli not placed (e.g. asset missing) — finalize anyway.
                    return
                }
                heli.alpha = 1.0   // un-fade from the 0.92 idle state
                heli.zPosition = 60
                // Rotor spin-up SFX bed.
                SFXManager.shared.playLoop("extraction_chopper", volume: 0.55)
                // Brief dust burst beneath the heli.
                if let burst = VFXManager.shared.makeBurstNode(effect: .dust, totalDuration: 0.7) {
                    burst.position = heli.position
                    burst.zPosition = 6
                    self.addChild(burst)
                }
                // Cycle the heli's idle frames so the rotor reads as spinning
                // while it lifts (the body-texture-cycle animates baked-in
                // rotor blades). If frames are missing, the body just stays
                // on its single texture — still acceptable.
                let frames = (0..<3).compactMap { self.loadHeliTexture("ascending_\($0)") }
                if frames.count >= 2 {
                    heli.run(SKAction.repeatForever(
                        SKAction.animate(with: frames, timePerFrame: 0.10,
                                         resize: false, restore: false)))
                }
                // Liftoff: small bob up first, then ascend + scale down + drift.
                let bob = SKAction.sequence([
                    SKAction.moveBy(x: 0, y: -2, duration: 0.18),
                    SKAction.moveBy(x: 0, y: 2, duration: 0.18)
                ])
                bob.timingMode = .easeInEaseOut
                let skyOffset: CGFloat = self.size.height * 0.65 + 200
                let ascend = SKAction.group([
                    SKAction.moveBy(x: 60, y: skyOffset, duration: 3.5),
                    SKAction.scale(to: 0.55, duration: 3.5),
                    SKAction.fadeAlpha(to: 0.0, duration: 3.5)
                ])
                ascend.timingMode = .easeIn
                heli.run(SKAction.sequence([
                    bob,
                    SKAction.wait(forDuration: 0.4),
                    ascend,
                    SKAction.run {
                        SFXManager.shared.stopLoop("extraction_chopper")
                    },
                    SKAction.removeFromParent()
                ]))
            }
        ]))

        // 3. Finalize once the heli has cleared the screen. Total budget:
        //    boardEnd + 0.2 (spin-up wait) + 0.36 (bob) + 0.4 (pause) + 3.5
        //    (ascend) ≈ boardEnd + 4.5. Add 0.5s buffer.
        let totalDuration = boardEnd + 5.0
        run(SKAction.sequence([
            SKAction.wait(forDuration: totalDuration),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                GameState.shared.extractionAnimationInProgress = false
                NotificationCenter.default.post(name: .extractionAnimationCompleted, object: nil)
                CombatFlowController.finalizeExtractionAfterAnimation(gameState: GameState.shared)
                self.playerInputLocked = false
            }
        ]))
    }

    private func playDoorExtractionAnimation(extractionX: Int, extractionY: Int) {
        playerInputLocked = true
        let center = TileMap.tileCenter(x: extractionX, y: extractionY)
        let mapNode = childNode(withName: "TileMap") ?? self
        let originX = mapNode.position.x + center.x
        let originY = mapNode.position.y + center.y

        var staggerDelay: TimeInterval = 0
        let livingCount = max(1, characterNodes.count)
        let staggerPerChar: TimeInterval = 1.0
        for (_, node) in characterNodes {
            let exit = SKAction.sequence([
                SKAction.wait(forDuration: staggerDelay),
                SKAction.move(to: CGPoint(x: originX, y: originY), duration: 0.7),
                SKAction.fadeOut(withDuration: 0.5)
            ])
            node.run(exit)
            staggerDelay += staggerPerChar
        }

        let totalDuration = TimeInterval(livingCount) * staggerPerChar + 0.5
        run(SKAction.sequence([
            SKAction.wait(forDuration: totalDuration),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                GameState.shared.extractionAnimationInProgress = false
                NotificationCenter.default.post(name: .extractionAnimationCompleted, object: nil)
                CombatFlowController.finalizeExtractionAfterAnimation(gameState: GameState.shared)
                self.playerInputLocked = false
            }
        ]))
    }

    /// Ladder / climb-out extraction: characters climb out of the room
    /// (e.g. M3 ritual chamber's roof access skylight). No helicopter.
    /// Called from playExtractionAnimation when extractionType == "ladder".
    private func playLadderExtractionAnimation(extractionX: Int, extractionY: Int) {
        playerInputLocked = true
        // Each runner moves UP toward the extraction tile, then fades out
        // as if climbing through the ceiling.
        let center = TileMap.tileCenter(x: extractionX, y: extractionY)
        let mapNode = childNode(withName: "TileMap") ?? self
        let originX = mapNode.position.x + center.x
        let originY = mapNode.position.y + center.y

        // Stagger each character so they appear to climb one-by-one
        var staggerDelay: TimeInterval = 0
        let livingCount = max(1, characterNodes.count)
        let staggerPerChar: TimeInterval = 1.6
        for (_, node) in characterNodes {
            let climb = SKAction.sequence([
                SKAction.wait(forDuration: staggerDelay),
                SKAction.group([
                    // drift toward the extraction tile
                    SKAction.move(to: CGPoint(x: originX, y: originY), duration: 0.8),
                    SKAction.fadeAlpha(to: 0.85, duration: 0.8)
                ]),
                // climb upward off-screen as they go through the roof
                SKAction.group([
                    SKAction.moveBy(x: 0, y: 280, duration: 1.4),
                    SKAction.scale(by: 0.5, duration: 1.4),
                    SKAction.fadeOut(withDuration: 1.4)
                ])
            ])
            node.run(climb)
            staggerDelay += staggerPerChar
        }

        // Total duration: (livingCount × stagger) + final climb 1.4
        let totalDuration = TimeInterval(livingCount) * staggerPerChar + 1.4 + 0.5
        let finalize = SKAction.sequence([
            SKAction.wait(forDuration: totalDuration),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                GameState.shared.extractionAnimationInProgress = false
                NotificationCenter.default.post(name: .extractionAnimationCompleted, object: nil)
                CombatFlowController.finalizeExtractionAfterAnimation(gameState: GameState.shared)
                self.playerInputLocked = false
            }
        ])
        run(finalize)
    }

    /// Load the Zero State studio sigil that's overlaid on the room
    /// transition card. The mark lives in the asset catalog (it's used
    /// elsewhere via SwiftUI `Image("zero_state_mark_4")`); SpriteKit
    /// needs a UIImage→SKTexture hop to render it. Returns nil if the
    /// asset isn't shipped — the transition still works without the
    /// seal (the room name + rule remain).
    private func roomTransitionSigilTexture() -> SKTexture? {
        guard let img = UIImage(named: "zero_state_mark_4") else { return nil }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }

    private func loadHeliTexture(_ name: String) -> SKTexture? {
        // Try Sprites/effects/helicopter/<name>.png
        if let resourcePath = Bundle.main.resourcePath {
            let path = resourcePath + "/Sprites/effects/helicopter/" + name + ".png"
            if let img = UIImage(contentsOfFile: path) {
                return SKTexture(image: img)
            }
        }
        // Dev fallback via #file
        let url = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sprites")
            .appendingPathComponent("effects")
            .appendingPathComponent("helicopter")
            .appendingPathComponent("\(name).png")
        if let img = UIImage(contentsOfFile: url.path) {
            return SKTexture(image: img)
        }
        return nil
    }

    /// Visually mark wall tiles that just retracted (barrier-drop on first
    /// kill). The pathfinding side has already mutated `currentMissionTiles`,
    /// so we:
    /// (a) delete the procedural wall SKNode,
    /// (b) clone a chunk of the room's BACKGROUND TEXTURE from a clean-floor
    ///     reference tile and stamp it over the barrier tile so the painted
    ///     barrier art is occluded with matching floor pixels (no flat-color
    ///     "patch" — actual sampled floor), and
    /// (c) fire a brief amber spark to sell the "barrier disengaged" beat.
    private func dropBarrierTiles(coords: [[String: Int]]) {
        guard let mapNode = childNode(withName: "TileMap") else { return }
        let bg = childNode(withName: "roomBackground") as? SKSpriteNode
        let bgTex = bg?.texture
        let bgSize = bg?.size ?? .zero

        for c in coords {
            guard let x = c["x"], let y = c["y"] else { continue }
            // Fade + remove the wall sprite so pathfinding visualisation matches.
            mapNode.childNode(withName: "tile_\(x)_\(y)")?.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.35),
                SKAction.removeFromParent()
            ]))

            let center = TileMap.tileCenter(x: x, y: y)

            // ── Floor patch from real BG pixels ──────────────────────────
            // Sample a tile-sized rectangle from the room background image,
            // taken from a clean-floor offset (3 rows below the barrier; if
            // that's off the map, 3 rows above). The crop is rendered as an
            // SKSpriteNode on top of the barrier tile so the painted-in
            // barrier art is occluded with floor pixels that match the rest
            // of the room. Falls through to a no-op if the BG texture isn't
            // available — the wall sprite is already gone, so worst case
            // the player sees the BG-painted barrier with no overlay.
            if let bgTex = bgTex,
               let bg = bg,
               bgSize.width > 0, bgSize.height > 0 {

                // Pick a clean-floor SOURCE tile. Try +3 rows down first,
                // fall back to -3 rows up. Both are heuristic: M1's barrier
                // is roughly mid-map, so either side has open floor.
                let sourceY: Int = {
                    let down = y + 3
                    if down < (tileMap?.mapHeight ?? 0) { return down }
                    return max(0, y - 3)
                }()
                let sourceCenter = TileMap.tileCenter(x: x, y: sourceY)

                // Convert tile centers to BG-local coordinates. The bg sprite
                // has anchor (0,0), positioned at mapOrigin, so a scene point
                // (sx, sy) maps to bg-local (sx - mapOrigin.x, sy - mapOrigin.y).
                // Tile centers are returned WITHOUT mapOrigin offset (they're
                // local to the tilemap), so we use them directly here.
                let patchSize = CGSize(width: TileMap.hexRadius * 2.3,
                                       height: TileMap.hexRadius * 2.0)

                // Normalised SKTexture rect (origin bottom-left, 0..1).
                // Add a tiny inset so we don't pick up the next tile's edge.
                let cropX = (sourceCenter.x - patchSize.width / 2) / bgSize.width
                let cropYRaw = (sourceCenter.y - patchSize.height / 2) / bgSize.height
                let cropW = patchSize.width  / bgSize.width
                let cropH = patchSize.height / bgSize.height

                // Clamp into [0,1] so we never request out-of-range pixels.
                let cx = max(0, min(1 - cropW, cropX))
                let cy = max(0, min(1 - cropH, cropYRaw))
                let normRect = CGRect(x: cx, y: cy, width: cropW, height: cropH)

                let cropTex = SKTexture(rect: normRect, in: bgTex)
                let patch = SKSpriteNode(texture: cropTex, size: patchSize)
                patch.position = CGPoint(x: center.x, y: center.y)
                patch.alpha = 0
                patch.zPosition = -29   // just above the bg (-30), below tile outlines (>=0)
                patch.name = "barrierPatch_\(x)_\(y)"

                // The patch is added to mapNode so it scrolls with the map.
                mapNode.addChild(patch)
                _ = bg  // keep ref-warm in case future code wants it
                patch.run(SKAction.fadeIn(withDuration: 0.4))
            }

            // Brief amber spark at the tile to sell "barrier disengaged".
            let spark = SKShapeNode(circleOfRadius: 4)
            spark.fillColor = UIColor(hex: "#FFAA00")
            spark.strokeColor = .clear
            spark.glowWidth = 6
            spark.position = center
            spark.zPosition = 6
            spark.alpha = 0.85
            mapNode.addChild(spark)
            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 2.5, duration: 0.4),
                    SKAction.fadeOut(withDuration: 0.4)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    /// Handle LEFT/RIGHT arrow tap from CombatUI — navigate to adjacent room without a door.
    private func handleRoomNavigationArrow(direction: String) {
        GameState.shared.addLog("Use the marked door tile to move between rooms.")
    }

    private func handleRoomTransitionCompleted() {
        guard let targetRoom = RoomManager.shared.pendingRoomTransition else { return }
        // Defensive guard: if a transition fires for the room we're already
        // in, treat it as a no-op. Without this, a spurious re-fire would
        // wipe `GameState.shared.enemies` (line below sets it from the
        // targetRoom spec) — which is the exact symptom of "no enemies in
        // range" mid-fight even though enemies are visible on screen.
        let currentId = GameState.shared.currentRoomId
        if !currentId.isEmpty,
           currentId == targetRoom.id,
           !GameState.shared.enemies.isEmpty {
            dlog("[BattleScene] ⚠️ duplicate transition to current room \(currentId) — ignoring (would have wiped \(GameState.shared.enemies.count) enemies)")
            GameState.shared.addLog("⚠ stray room transition ignored (room=\(currentId))")
            // Still clear the pending flags so we don't loop forever.
            RoomManager.shared.completeTransition(to: targetRoom)
            return
        }
        // Belt-and-suspenders reset of per-room first-kill state at the
        // earliest point of the transition, in case loadRoom's later reset is
        // shadowed by any state leak through async paths.
        GameState.shared.firstKillProcessedInRoom = false

        // Determine spawn position for this transition. Per playtest spec
        // 2026-05-23: spawn must always reflect which DOOR the party came
        // through — never default back to the room's original spawn just
        // because the room was previously entered.
        //
        // - Any door-driven transition (first OR back nav): use the
        //   connection's targetSpawn — that IS the tile next to the door
        //   you walked through.
        // - Arrow navigation (no connection context): fall back to the
        //   room's playerSpawn.
        //
        // Previous behavior put back-nav at room.playerSpawn, which read
        // as "always re-enter from the top of the room" regardless of
        // which door you used — exactly the bug the playtest flagged.
        let spawnX: Int
        let spawnY: Int
        let isBackNavigation = RoomManager.shared.isRoomEntered(targetRoom.id)
        if let connX = RoomManager.shared.pendingConnectionTargetX,
           let connY = RoomManager.shared.pendingConnectionTargetY {
            let resolved = validatedSpawnX(in: targetRoom, proposedX: connX, proposedY: connY)
            spawnX = resolved.x
            spawnY = resolved.y
            dlog("[BattleScene] room transition (\(isBackNavigation ? "back-nav-via-door" : "first-entry")) target=\(targetRoom.id) requestedSpawn=(\(connX),\(connY)) resolvedSpawn=(\(spawnX),\(spawnY)) tile=\(targetRoom.map[spawnY][spawnX])")
        } else {
            // No connection context — pure arrow nav. Fall back to room's
            // playerSpawn.
            spawnX = targetRoom.playerSpawn.x
            spawnY = targetRoom.playerSpawn.y
            dlog("[BattleScene] room transition (arrow) target=\(targetRoom.id) using room.playerSpawn=(\(spawnX),\(spawnY))")
        }

        // Set living character positions for this room entry. playerTeam keeps the
        // whole squad roster, including downed runners, but only living runners are
        // projected into the active room.
        if spawnX >= 0 {
            // Track tiles already chosen this transition — passed into
            // validatedSpawnX so two runners can never land on the same hex.
            var occupied: Set<String> = []
            var livingSpawnOffset = 0
            for i in GameState.shared.playerTeam.indices {
                guard GameState.shared.playerTeam[i].isAlive else { continue }
                let candidate = validatedSpawnX(in: targetRoom,
                                                proposedX: spawnX + livingSpawnOffset,
                                                proposedY: spawnY,
                                                avoiding: occupied)
                GameState.shared.playerTeam[i].positionX = candidate.x
                GameState.shared.playerTeam[i].positionY = candidate.y
                occupied.insert("\(candidate.x),\(candidate.y)")
                dlog("Room transition: char=\(GameState.shared.playerTeam[i].name) x=\(candidate.x) y=\(candidate.y)")
                livingSpawnOffset += 1
            }
        }

        // Mark room as entered (for future back-navigation)
        RoomManager.shared.markRoomEntered(targetRoom.id)

        // Replace GameState enemies with this room's enemies only.
        // Cleared rooms stay empty on return; uncleared rooms honor delayed spawns.
        var newEnemies: [Enemy] = []
        var newPendingSpawns: [GameState.PendingSpawn] = []
        if !RoomManager.shared.isRoomCleared(targetRoom.id) {
            for enemySpawn in targetRoom.enemies {
            let enemy: Enemy
            switch enemySpawn.type {
            case "guard":   enemy = Enemy.corpGuard()
            case "drone":   enemy = Enemy.securityDrone()
            case "elite":   enemy = Enemy.eliteGuard()
            case "mage":    enemy = Enemy.corpMage()
            case "healer":  enemy = Enemy.medic()
            case "mech":    enemy = Enemy.combatMech()
            case "sniper":  enemy = Enemy.sniper()
            case "bruiser": enemy = Enemy.bruiser()
            case "spider":  enemy = Enemy.spiderDrone()
            case "riot":    enemy = Enemy.riotTrooper()
            default:        enemy = Enemy.corpGuard()
            }
            enemy.positionX = enemySpawn.x
            enemy.positionY = enemySpawn.y
                if enemySpawn.delay == 0 {
                    newEnemies.append(enemy)
                } else {
                    // BUG FIX 2026-05-10: JSON `delay` is an OFFSET ("N enemy
                    // phases after entering this room"), but
                    // processDelayedSpawns checks against the cumulative
                    // gameState.enemyPhaseCount which keeps ticking up
                    // across rooms. Storing delay raw caused R2's "delay 2"
                    // spawns to be treated as already due when entering R2
                    // late in the mission — they'd fire on the first
                    // enemy phase in R2 (or never appear noticeably,
                    // depending on what the player was doing). Store as
                    // absolute target so the offset semantic is preserved.
                    // (Matches ReinforcementService's pattern at
                    // ReinforcementService.swift:88.)
                    let dueAt = GameState.shared.enemyPhaseCount + enemySpawn.delay
                    newPendingSpawns.append(GameState.PendingSpawn(enemy: enemy, delayRounds: dueAt))
                }
            }
        }
        GameState.shared.enemies = newEnemies
        GameState.shared.pendingSpawns = newPendingSpawns

        RoomManager.shared.completeTransition(to: targetRoom)

        // Sync GameState's current room ID
        GameState.shared.currentRoomId = targetRoom.id

        // Recompute extraction objective for the room we just entered.
        // Priority:
        // 1) explicit room extractionPoint
        // 2) extraction tile embedded in map
        // 3) first room connection trigger tile (fallback objective)
        if let extraction = targetRoom.extractionPoint {
            GameState.shared.extractionX = extraction.x
            GameState.shared.extractionY = extraction.y
            if RoomManager.shared.isExtractionActive(in: targetRoom) {
                GameState.shared.addLog("Extraction active at (\(extraction.x), \(extraction.y))")
            } else {
                GameState.shared.addLog("Clear this room to activate extraction.")
            }
        } else if let mapExtraction = firstExtractionTile(in: targetRoom.map) {
            GameState.shared.extractionX = mapExtraction.x
            GameState.shared.extractionY = mapExtraction.y
            if RoomManager.shared.isExtractionActive(in: targetRoom) {
                GameState.shared.addLog("Extraction active at (\(mapExtraction.x), \(mapExtraction.y))")
            } else {
                GameState.shared.addLog("Clear this room to activate extraction.")
            }
        } else if let firstConn = targetRoom.connections.first {
            GameState.shared.extractionX = firstConn.triggerTileX
            GameState.shared.extractionY = firstConn.triggerTileY
            GameState.shared.addLog("Find a way through to: \(firstConn.targetRoomId)")
        }

        // Update tiles for enemy pathfinding
        GameState.shared.updateTilesForCurrentRoom(targetRoom.map)

        // Clear stale door-open state from previous room
        openedDoorKeys.removeAll()

        // Reset combat state for the new room
        CombatFlowController.resetTurnTracking(gameState: GameState.shared)
        CombatFlowController.restorePlayerControlAfterEnemyPhase(gameState: GameState.shared)

        // Reload the room with living characters only; downed runners remain in
        // playerTeam for roster/history but are not active room participants.
        loadRoom(targetRoom, characters: GameState.shared.livingPlayers, enemies: newEnemies)

        // Start a fresh round in the new room
        GameState.shared.beginRound()

        // Fade back in
        fadeOutFromTransition()

        GameState.shared.addLog("Arrived at: \(targetRoom.title)")
    }

    private func firstExtractionTile(in map: [[Int]]) -> (x: Int, y: Int)? {
        for (y, row) in map.enumerated() {
            if let x = row.firstIndex(of: TileType.extraction.rawValue) {
                return (x: x, y: y)
            }
        }
        return nil
    }

    private func setupEnemyNotifications() {
        NotificationCenter.default.addObserver(forName: .characterLevelUp, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["characterId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            self?.playLevelUpEffect(on: id)
        }

        NotificationCenter.default.addObserver(forName: .enemyHit, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["enemyId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            let dmg = userInfo["damage"] as? Int ?? 0
            self?.playHitEffect(on: id, damage: dmg)
        }
        NotificationCenter.default.addObserver(forName: .enemyDied, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["enemyId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            self?.playDeathEffect(on: id)
            // Belt-and-suspenders: ensure once-per-room kill effects (drop
            // `removeOnFirstKill` barriers etc.) fire on EVERY death path,
            // not just the ones routed through performAttack/blitz/spell.
            // The handler is idempotent via `firstKillProcessedInRoom`, so
            // calling it again is a no-op once the flag is set.
            Task { @MainActor in
                CombatFlowController.handleEnemyKillForRoomEffects(gameState: GameState.shared)
                // M3 boss-phase-2 hook: when the corp mage at the altar dies
                // in the Ritual Chamber, his TRUE form (the boss mage)
                // manifests on the same tile. Service is idempotent — only
                // fires once per mission attempt.
                CombatFlowController.checkMageBossPhase2(gameState: GameState.shared,
                                                         deadEnemyId: id)
                // Boss-death music kill — drop the boss track and let the
                // post-combat moment breathe in silence. Applies to every
                // proper boss kill (M5 mech, M6 AGI, M3 bossmage true form).
                if let dead = GameState.shared.enemies.first(where: { $0.id == id }) {
                    let arch = dead.archetype.lowercased()
                    if arch == "bossmech" || arch == "bossagi" || arch == "bossmage" {
                        MusicManager.shared.stop()
                        SFXManager.shared.stopAllLoops()
                        let tag: String = {
                            switch arch {
                            case "bossmech": return "[M5] MEKTON-7 down. Silence."
                            case "bossagi":  return "[M6] AGI-PRIME terminated. Silence."
                            case "bossmage": return "[M3] Sato is dead. The wards collapse."
                            default:         return ""
                            }
                        }()
                        GameState.shared.addLog(tag)
                    }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .enemyMoved, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["enemyId"] as? String,
                  let id = UUID(uuidString: idStr),
                  let newX = userInfo["x"] as? Int,
                  let newY = userInfo["y"] as? Int else { return }
            dlog("[BattleScene] .enemyMoved received — enemyId=\(idStr), to=(\(newX),\(newY))")
            self?.animateEnemyMove(id: id, toX: newX, toY: newY)
        }
        NotificationCenter.default.addObserver(forName: .playerDied, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["playerId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            self?.playDeathEffect(on: id)
        }
        NotificationCenter.default.addObserver(forName: .dataTerminalHacked, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let x = userInfo["x"] as? Int,
                  let y = userInfo["y"] as? Int else { return }
            self?.tileMap?.markTerminalHacked(x: x, y: y)
        }
        NotificationCenter.default.addObserver(forName: .enemySpawned, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["enemyId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            Task { @MainActor in
                // Find the newly spawned enemy in GameState and place it on the map
                if let enemy = GameState.shared.enemies.first(where: { $0.id == id }) {
                    self.placeEnemy(enemy)
                    self.playRoundStartEffect()
                    // M6 AGI boss MATERIALIZES — start at alpha 0 and fade
                    // in over 2.5s so it reads as an emergence, not a pop-in.
                    // The audio cascade (arrival_glitch → manifestation →
                    // voice) is timed against this same window.
                    if enemy.archetype == "bossagi", let node = self.characterNodes[id] {
                        node.alpha = 0.0
                        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 2.5)
                        fadeIn.timingMode = .easeIn
                        node.run(fadeIn)
                    }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .roundStarted, object: nil, queue: .main) { [weak self] _ in
            self?.playRoundStartEffect()
        }

        // MARK: spell + skill visual hooks
        // Each observer hops to @MainActor explicitly — the queue is .main
        // so the closure body already runs on the main thread, but Swift's
        // strict concurrency analysis can't prove that without the Task hop.
        NotificationCenter.default.addObserver(forName: .healEffect, object: nil, queue: .main) { [weak self] notification in
            let amount = (notification.userInfo?["amount"] as? Int) ?? 0
            guard let idStr = notification.userInfo?["targetId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            Task { @MainActor [weak self] in
                guard let self = self, let node = self.characterNodes[id] else { return }
                EffectsManager.shared.emitHeal(at: node.position, in: self, amount: amount)
                // Refresh the target's HP bar / label — the heal mutates
                // currentHP on the Character/Enemy in place but the visual
                // wasn't getting an updateHP call (only damage paths did).
                // So the bar stayed at its pre-heal fill until the next
                // hit. Push the new values to the sprite now.
                if let char = GameState.shared.playerTeam.first(where: { $0.id == id && $0.isAlive }) {
                    SpriteManager.shared.updateHP(
                        on: node,
                        currentHP: char.currentHP, maxHP: char.maxHP,
                        currentStun: char.currentStun, maxStun: char.maxStun,
                        level: char.level, isPlayer: true
                    )
                } else if let enemy = GameState.shared.enemies.first(where: { $0.id == id && $0.isAlive }) {
                    SpriteManager.shared.updateHP(
                        on: node,
                        currentHP: enemy.currentHP, maxHP: enemy.maxHP,
                        currentStun: enemy.currentStun, maxStun: enemy.maxStun
                    )
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .fireballEffect, object: nil, queue: .main) { [weak self] notification in
            guard let x = notification.userInfo?["x"] as? Int,
                  let y = notification.userInfo?["y"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitFireball(at: self.tileCenter(x, y), in: self)
            }
        }
        NotificationCenter.default.addObserver(forName: .boltEffect, object: nil, queue: .main) { [weak self] notification in
            guard let fx = notification.userInfo?["fromX"] as? Int,
                  let fy = notification.userInfo?["fromY"] as? Int,
                  let tx = notification.userInfo?["toX"] as? Int,
                  let ty = notification.userInfo?["toY"] as? Int else { return }
            let hex = (notification.userInfo?["color"] as? String) ?? "#AA66FF"
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitMagicBolt(
                    from: self.tileCenter(fx, fy),
                    to:   self.tileCenter(tx, ty),
                    color: UIColor(hex: hex),
                    in: self)
            }
        }
        NotificationCenter.default.addObserver(forName: .shockEffect, object: nil, queue: .main) { [weak self] notification in
            guard let fx = notification.userInfo?["fromX"] as? Int,
                  let fy = notification.userInfo?["fromY"] as? Int,
                  let tx = notification.userInfo?["toX"] as? Int,
                  let ty = notification.userInfo?["toY"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitShockBolt(
                    from: self.tileCenter(fx, fy),
                    to:   self.tileCenter(tx, ty),
                    in: self)
            }
        }
        NotificationCenter.default.addObserver(forName: .blitzEffect, object: nil, queue: .main) { [weak self] notification in
            guard let x = notification.userInfo?["x"] as? Int,
                  let y = notification.userInfo?["y"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitSlashArc(at: self.tileCenter(x, y), in: self)
            }
        }
        NotificationCenter.default.addObserver(forName: .intimidateEffect, object: nil, queue: .main) { [weak self] notification in
            guard let x = notification.userInfo?["x"] as? Int,
                  let y = notification.userInfo?["y"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitIntimidateWave(at: self.tileCenter(x, y), in: self)
            }
        }
        NotificationCenter.default.addObserver(forName: .gunfireEffect, object: nil, queue: .main) { [weak self] notification in
            guard let fx = notification.userInfo?["fromX"] as? Int,
                  let fy = notification.userInfo?["fromY"] as? Int,
                  let tx = notification.userInfo?["toX"] as? Int,
                  let ty = notification.userInfo?["toY"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitGunfire(
                    from: self.tileCenter(fx, fy),
                    to:   self.tileCenter(tx, ty),
                    in: self)
                // VFX burst: muzzle spark + impact spark on hit tile.
                if let muzzle = VFXManager.shared.makeBurstNode(effect: .microSpark, totalDuration: 0.25) {
                    muzzle.position = self.tileCenter(fx, fy)
                    muzzle.zPosition = 95
                    self.addChild(muzzle)
                }
                if let impact = VFXManager.shared.makeBurstNode(effect: .microSpark, totalDuration: 0.3) {
                    impact.position = self.tileCenter(tx, ty)
                    impact.zPosition = 95
                    self.addChild(impact)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .meleeStrikeEffect, object: nil, queue: .main) { [weak self] notification in
            guard let x = notification.userInfo?["x"] as? Int,
                  let y = notification.userInfo?["y"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                EffectsManager.shared.emitMeleeStrike(at: self.tileCenter(x, y), in: self)
                // VFX burst: spark on impact tile.
                if let burst = VFXManager.shared.makeBurstNode(effect: .microSpark, totalDuration: 0.3) {
                    burst.position = self.tileCenter(x, y)
                    burst.zPosition = 95
                    self.addChild(burst)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .objectivePulseRequested, object: nil, queue: .main) { [weak self] notification in
            guard let tx = notification.userInfo?["tileX"] as? Int,
                  let ty = notification.userInfo?["tileY"] as? Int,
                  let kind = notification.userInfo?["kind"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cyan for data terminals, green for extraction — reads at a
                // glance which objective the runner just stepped on.
                let color: UIColor = (kind == TileType.extraction.rawValue)
                    ? UIColor(hex: "#00FF88")
                    : UIColor(hex: "#00FFCC")
                EffectsManager.shared.emitObjectivePulse(
                    at: self.tileCenter(tx, ty), in: self, color: color)
            }
        }
        NotificationCenter.default.addObserver(forName: .hackEffect, object: nil, queue: .main) { [weak self] notification in
            guard let fx = notification.userInfo?["fromX"] as? Int,
                  let fy = notification.userInfo?["fromY"] as? Int,
                  let tx = notification.userInfo?["toX"] as? Int,
                  let ty = notification.userInfo?["toY"] as? Int else { return }
            let targetIdStr = notification.userInfo?["targetId"] as? String
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Stream of binary glyphs from decker → target.
                EffectsManager.shared.emitHack(
                    from: self.tileCenter(fx, fy),
                    to:   self.tileCenter(tx, ty),
                    in: self)
                // 0.4s cyan glitch flash + scan-line ON the hacked enemy
                // sprite. Layered with the stream so both play together.
                if let idStr = targetIdStr,
                   let id = UUID(uuidString: idStr),
                   let node = self.characterNodes[id] {
                    EffectsManager.shared.emitHackGlitch(on: node)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .characterDefend, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["characterId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            self?.playDefendEffect(on: id)
            // Re-focus camera on the defending character
            self?.focusCamera(on: id)
        }
        NotificationCenter.default.addObserver(forName: .turnChanged, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["characterId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Auto-select the new active character AND show their movement range
                self.showSelectionRing(for: id)
                CombatFlowController.requestCharacterSelectionFromScene(gameState: GameState.shared, id: id)
                self.focusCamera(on: id)
                // Selective idle animation: only the active player character animates.
                // All other player characters are frozen on their first idle frame.
                self.updatePlayerIdleAnimations(activeId: id)
            }
        }
        NotificationCenter.default.addObserver(forName: .characterSelected, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["characterId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.showSelectionRing(for: id)
                self.focusCamera(on: id)
                self.updatePlayerIdleAnimations(activeId: id)
            }
        }
        NotificationCenter.default.addObserver(forName: .playerHit, object: nil, queue: .main) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let idStr = userInfo["playerId"] as? String,
                  let id = UUID(uuidString: idStr) else { return }
            let dmg = userInfo["damage"] as? Int ?? 0
            let enemyIdStr = userInfo["enemyId"] as? String
            dlog("[BattleScene] .playerHit received — playerId=\(idStr), damage=\(dmg)")
            // Trigger attack animation on the attacking enemy
            if let eIdStr = enemyIdStr, let enemyId = UUID(uuidString: eIdStr),
               let enemyNode = self?.characterNodes[enemyId] as? SpriteNode {
                SpriteManager.shared.animate(state: .attack, target: enemyNode)
            }
            // playEnemyAttackEffect draws the slash line and plays the player flash together
            if let eIdStr = enemyIdStr, let enemyId = UUID(uuidString: eIdStr) {
                self?.playEnemyAttackEffect(enemyId: enemyId, playerId: id, damage: dmg)
            } else {
                self?.playPlayerHitEffect(on: id, damage: dmg, enemyIdStr: enemyIdStr)
            }
        }
        // FIX Issue 1: Unblock player input ONLY when all enemy animations have finished.
        // The fixed 0.8s asyncAfter was too short for multiple enemies with staggered moves.
        // GameState.enemyPhase() posts .enemyPhaseCompleted when its DispatchGroup finishes.
        NotificationCenter.default.addObserver(forName: .enemyPhaseCompleted, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playerInputLocked = false
                self.isEnemyPhaseRunning = false
                // Render layer is projection-only; combat flow owns progression state restoration.
                CombatFlowController.restorePlayerControlAfterEnemyPhase(gameState: GameState.shared)
                self.fadeOutEnemyPhaseTint()
                dlog("[BattleScene] .enemyPhaseCompleted received — player input unlocked")
            }
        }
        // Enemy-phase red tint: fade in on enemy phase start
        NotificationCenter.default.addObserver(forName: .enemyPhaseBegan, object: nil, queue: .main) { [weak self] _ in
            self?.fadeInEnemyPhaseTint()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Block input during enemy phase or when player input is locked.
        if playerInputLocked || GameState.shared.isInputBlockedByPhase {
            GameState.shared.addLog("Enemy phase — wait for your turn.")
            HapticsManager.shared.buttonTap()
            return
        }
        guard let touch = touches.first else { return }
        let sceneLocation = touch.location(in: self)

        // Reset block flag in case it got stuck (safety check)
        playerInputLocked = false

        // Flat-top odd-q touch → tile conversion using correct hex grid spacing.
        // hexColSpacing = 1.5·R, hexRowSpacing = R·√3·isoSquash — matches tileCenter exactly.
        // Odd COLUMNS shift down by hexRowSpacing/2 (column parity, not row parity).
        let rawX = Int((sceneLocation.x - mapOrigin.x) / TileMap.hexColSpacing)
        let clampedX = max(0, min(rawX, TileMap.mapWidth - 1))
        let colYOffset: CGFloat = (clampedX % 2 == 1) ? TileMap.hexRowSpacing / 2.0 : 0
        let rawY = Int((sceneLocation.y - mapOrigin.y - colYOffset) / TileMap.hexRowSpacing)
        let clampedY = max(0, min(rawY, (tileMap?.mapHeight ?? 9) - 1))

        // DEBUG: verify touch → tile conversion
        dlog("[BattleScene] touchesBegan scene=(\(sceneLocation.x),\(sceneLocation.y)) mapOrigin=(\(mapOrigin.x),\(mapOrigin.y)) colOffset=\(colYOffset) → clamped=(\(clampedX),\(clampedY))")

        // Visual feedback - always flash within clamped tile bounds
        flashTile(tileX: clampedX, tileY: clampedY)

        // Handle selection / movement
        handleTileTap(tileX: clampedX, tileY: clampedY)
    }

    /// Start idle animation on the active player character; freeze all other player characters.
    /// Called whenever .turnChanged fires so only the current actor is visually animated.
    private func updatePlayerIdleAnimations(activeId: UUID) {
        let playerIds = Set(GameState.shared.playerTeam.map { $0.id })
        for (charId, node) in characterNodes {
            guard playerIds.contains(charId), let spriteNode = node as? SpriteNode else { continue }
            if charId == activeId {
                SpriteManager.shared.animate(state: .idle, target: spriteNode)
            } else {
                SpriteManager.shared.stopIdle(target: spriteNode)
            }
        }
        refreshActiveUnitHighlight(activeId: activeId)
    }

    /// Keep one obvious ring on the currently active unit for turn readability.
    private func refreshActiveUnitHighlight(activeId: UUID?) {
        let playerIds = Set(GameState.shared.playerTeam.map(\.id))
        for (id, node) in characterNodes where playerIds.contains(id) {
            node.childNode(withName: "activeTurnRing")?.removeFromParent()
        }

        guard let activeId, let activeNode = characterNodes[activeId] else { return }
        let ring = SKShapeNode(path: TileMap.hexPath(radius: TileMap.hexRadius * 0.74))
        ring.name = "activeTurnRing"
        ring.strokeColor = UIColor(hex: "#00D8FF")
        ring.lineWidth = 3.5
        ring.glowWidth = 8
        ring.fillColor = UIColor(hex: "#00D8FF").withAlphaComponent(0.08)
        ring.position = CGPoint(x: 0, y: -3)
        ring.zPosition = 13
        activeNode.addChild(ring)

        ring.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.50, duration: 0.45),
            SKAction.fadeAlpha(to: 1.00, duration: 0.45)
        ])), withKey: "activePulse")

    }

    private func showSelectionRing(for characterId: UUID) {
        // Deselect previous and clear highlights
        if let prev = selectedCharacterNode {
            SpriteManager.shared.deselect(target: prev)
            // Restore depth-by-tileY on the formerly-selected sprite so it
            // sinks back into normal layering. Without this, the +1000
            // bump from a previous selection lingered.
            if let prevSprite = prev as? SpriteNode {
                prevSprite.zPosition = playerDepthZ(forSprite: prevSprite)
            }
        }
        clearHighlights()

        // Select new
        if let node = characterNodes[characterId] {
            SpriteManager.shared.animateSelect(target: node)
            selectedCharacterNode = node
            // Z-bump so the active runner ALWAYS renders foreground —
            // this is the path the game actually takes (turn-change /
            // characterSelected notifications), not BattleScene.selectCharacter,
            // so the z-bump must happen here too.
            if let sprite = node as? SpriteNode {
                sprite.zPosition = playerDepthZ(forSprite: sprite) + 1000
            }
            HapticsManager.shared.selectionChanged()
            let pop = SKAction.sequence([
                SKAction.scale(to: 1.05, duration: 0.08),
                SKAction.scale(to: 1.0, duration: 0.10)
            ])
            node.run(pop, withKey: "selectionPop")
            // Highlight attackable enemy tiles and movable empty tiles
            if let sprite = node as? SpriteNode {
                highlightTiles(aroundX: sprite.tileX, y: sprite.tileY)
            }
        }

        let activeId = GameState.shared.activeCharacter?.id ?? GameState.shared.currentCharacter?.id
        refreshActiveUnitHighlight(activeId: activeId)
    }

    private var highlightNodes: [SKNode] = []

    private func clearHighlights() {
        for n in highlightNodes { n.removeFromParent() }
        highlightNodes = []
    }

    private weak var selectedEnemyCueNode: SKNode?
    /// Enemy node currently bumped to +1000 by showTargetRing. Kept so we
    /// can restore its natural depthZ when the target changes — otherwise
    /// the +1000 bump would linger on the previously-targeted enemy and it
    /// would keep occluding the foreground.
    private weak var selectedEnemyNode: SKNode?

    /// Target selection strengthens the enemy's base glow without adding
    /// overhead markers or crosshairs. ALSO bumps the targeted enemy's
    /// zPosition by +1000 so the selected sprite always wins — matches the
    /// player-selection +1000 path. Previous target's z is restored to its
    /// natural depthZ first so we never strand a bump on a stale node.
    func showTargetRing(for enemyId: UUID) {
        selectedEnemyCueNode?.removeFromParent()
        selectedEnemyCueNode = nil

        // Restore previously-targeted enemy to its natural depth before
        // applying the new target's bump.
        if let prev = selectedEnemyNode as? SpriteNode {
            prev.zPosition = depthZ(forTileY: prev.tileY, isEnemy: true)
        }
        selectedEnemyNode = nil

        guard let node = characterNodes[enemyId] else { return }

        let enemy = GameState.shared.enemies.first { $0.id == enemyId }
        let isBoss = enemy.map { $0.archetype == "bossmech" || $0.archetype == "bossagi" } ?? false

        let cue = SKShapeNode(path: TileMap.hexPath(radius: isBoss ? 38 : 31))
        cue.name = "enemySelectedCue"
        cue.fillColor = UIColor(hex: "#FF2438").withAlphaComponent(0.16)
        cue.strokeColor = UIColor(hex: "#FF6A6A").withAlphaComponent(0.95)
        cue.lineWidth = 2.2
        cue.glowWidth = 7.0
        cue.position = CGPoint(x: 0, y: -8)
        cue.zPosition = 0.75

        node.addChild(cue)
        cue.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.45),
            SKAction.fadeAlpha(to: 1.0, duration: 0.45)
        ])), withKey: "selectedEnemyPulse")
        selectedEnemyCueNode = cue

        // Z-bump the targeted enemy so it always renders on top of any
        // sprite it visually overlaps — including in-front players. Mirrors
        // the player-selection bump in showSelectionRing(for:).
        if let sprite = node as? SpriteNode {
            sprite.zPosition = depthZ(forTileY: sprite.tileY, isEnemy: true) + 1000
            selectedEnemyNode = sprite
        }
    }

    /// Drop the +1000 z-bump on the currently targeted enemy. Call this
    /// when the player turn ends or selection clears so the enemy sinks
    /// back into normal depth ordering.
    func hideTargetRing() {
        selectedEnemyCueNode?.removeFromParent()
        selectedEnemyCueNode = nil
        if let prev = selectedEnemyNode as? SpriteNode {
            prev.zPosition = depthZ(forTileY: prev.tileY, isEnemy: true)
        }
        selectedEnemyNode = nil
    }

    private func highlightTiles(aroundX cx: Int, y cy: Int) {
        clearHighlights()

        // Use BFS to find all reachable tiles within movement range
        let reachableTiles = bfsReachable(fromX: cx, fromY: cy, maxSteps: movementRange)
        for tile in reachableTiles {
            let tx = tile.x, ty = tile.y
            let occupied = characterNodes.values.contains { node in
                guard let sprite = node as? SpriteNode else { return false }
                return sprite.tileX == tx && sprite.tileY == ty
            }
            if !occupied {
                let n = SKShapeNode(path: TileMap.hexPath(radius: TileMap.hexRadius - 4))
                n.strokeColor = UIColor(hex: "#00D8FF").withAlphaComponent(0.95)
                n.lineWidth = 2.5
                n.fillColor = UIColor(hex: "#00D8FF").withAlphaComponent(0.20)
                n.position = CGPoint(
                    x: tileCenter(tx, ty).x,
                    y: tileCenter(tx, ty).y
                )
                n.zPosition = 6
                n.name = "highlight"
                addChild(n)
                highlightNodes.append(n)

                // Add pulsing opacity animation for move tiles (0.4→0.8→0.4)
                let movePulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.8, duration: 0.5),
                    SKAction.fadeAlpha(to: 0.4, duration: 0.5)
                ])
                n.run(SKAction.repeatForever(movePulse))

            }
        }
    }

    private func animateCharacterMove(characterId: UUID, toTileX: Int, toTileY: Int) {
        guard let node = characterNodes[characterId] else { return }
        SpriteManager.shared.animateMove(target: node, toTileX: toTileX, toTileY: toTileY, duration: 0.3, mapOrigin: mapOrigin)
    }

    /// Set up the camera node. Call after scene.size is set (ideally after fitSceneToView).
    /// Safe to call multiple times; only creates camera once.
    func setupCamera() {
        guard self.camera == nil else { return }
        let cameraNode = SKCameraNode()
        cameraNode.name = "MainCamera"
        cameraNode.xScale = 1.0
        cameraNode.yScale = 1.0
        addChild(cameraNode)
        self.camera = cameraNode
        // Position after map is loaded so mapOrigin is valid — call positionCameraOnMap() after loadMap().
    }

    // SwiftUI overlays cover the top objective banner and the bottom combat panel.
    // These are updated from CombatView after layout so first-turn framing matches
    // the real HUD footprint on the current device instead of a hardcoded guess.
    private var topHUDInset: CGFloat = 96
    private var bottomHUDInset: CGFloat = 180

    func updateViewportInsets(top: CGFloat, bottom: CGFloat) {
        let resolvedTop = max(0, top)
        let resolvedBottom = max(0, bottom)
        let changed = abs(resolvedTop - topHUDInset) > 0.5 || abs(resolvedBottom - bottomHUDInset) > 0.5

        topHUDInset = resolvedTop
        bottomHUDInset = resolvedBottom

        guard changed, camera != nil else { return }

        positionCameraOnMap()
    }

    private func applyCameraScale(_ cam: SKCameraNode) -> CGFloat {
        // Scale to fit the UNOBSCURED play corridor between top banner and bottom
        // combat panel. The map is allowed to bleed UP behind the top
        // objective banner (where only the small info chip lives), filling
        // more of the screen vertically. Bottom kept tight so the lowest hex
        // row stays visible above the combat panel.
        let visibleWidth = max(1, size.width)
        // Treat the top inset as zero for SCALE purposes — the actual
        // visual obscuring at the top is just the floating "i" / banner chip,
        // not the full 96pt safe-area clearance. Per playtest feedback the
        // map should bleed UNDER the status bar / Dynamic Island, so the
        // top reservation was pulled from 32 → 16 → 0pt. The combat HUD's
        // proportional weight drops correspondingly.
        let scaleHeight = max(1, size.height - bottomHUDInset)
        let targetMapScreenWidth = visibleWidth * 1.36
        let targetMapScreenHeight = scaleHeight * 1.03
        let requiredScaleX = mapPixelWidth / targetMapScreenWidth
        let requiredScaleY = mapPixelHeight / targetMapScreenHeight
        let scale = max(0.68, max(requiredScaleX, requiredScaleY))
        cam.setScale(scale)
        return scale
    }

    /// Reposition camera to map center within the actually visible play corridor.
    func positionCameraOnMap() {
        guard let cam = camera else { return }
        let scale = applyCameraScale(cam)
        let visibleSize = cameraVisibleSize(scale: scale)
        // Bottom HUD is taller than the top banner, so shift the camera DOWN
        // in scene space (lower Y) by half the delta. That puts the map's visual
        // center in the middle of the unobscured strip, not the full view.
        let verticalBias = ((bottomHUDInset - topHUDInset) / 2.0) * scale

        // Per-mission/room camera nudge — increase shifts content UP in the
        // viewport (bottom of map becomes more visible). M5 r2 had its
        // bottom row clipping into the HUD, needs an extra ~14pt down.
        // Base nudge of 18pt shifts the entire play area up so the top of
        // the map reaches under the status bar / Dynamic Island, giving
        // the bottom HUD less proportional weight on screen.
        let baseUpNudge: CGFloat = 18
        let extraNudge: CGFloat = {
            let mid = GameState.shared.currentMissionDisplayId ?? ""
            let rid = GameState.shared.currentRoomId
            if mid == "Mission005" && rid == "room_2" { return baseUpNudge + 14 }
            // M3R2 was clipping the bottom of map + background. ~5% scoot up.
            if mid == "Mission003" && rid == "room_2" { return baseUpNudge + 22 }
            return baseUpNudge
        }()
        let nextPosition = CGPoint(
            x: clampedCameraCoordinate(
                desired: mapOrigin.x + mapPixelWidth / 2,
                mapStart: mapOrigin.x,
                mapLength: mapPixelWidth,
                visibleLength: visibleSize.width
            ),
            y: clampedCameraCoordinate(
                desired: mapOrigin.y + mapPixelHeight / 2 - verticalBias - firstTurnCameraYOffset - extraNudge,
                mapStart: mapOrigin.y,
                mapLength: mapPixelHeight,
                visibleLength: visibleSize.height
            )
        )
        cam.position = nextPosition
        dlog("[BattleScene] positionCameraOnMap camera=\(nextPosition) topInset=\(topHUDInset) bottomInset=\(bottomHUDInset) bias=\(verticalBias) extraNudge=\(extraNudge)")
    }

    /// Focus camera on a specific tile, clamped so map edges stay within the unobscured viewport.
    func focusCamera(on tileX: Int, y tileY: Int) {
        positionCameraOnMap()
        dlog("[BattleScene] focusCamera locked to board center; requested tile=(\(tileX),\(tileY))")
    }

    private var unobscuredViewportHeight: CGFloat {
        max(1, size.height - topHUDInset - bottomHUDInset)
    }

    private func cameraVisibleSize(scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: unobscuredViewportHeight * scale)
    }

    private func clampedCameraCoordinate(
        desired: CGFloat,
        mapStart: CGFloat,
        mapLength: CGFloat,
        visibleLength: CGFloat
    ) -> CGFloat {
        guard mapLength > visibleLength else { return desired }

        let halfVisible = visibleLength / 2.0
        let minValue = mapStart + halfVisible
        let maxValue = mapStart + mapLength - halfVisible
        return minValue <= maxValue ? max(minValue, min(maxValue, desired)) : desired
    }

    // MARK: - Scene Size / Map Fit

    /// Adjust scene size to match the SKView's bounds.
    /// IMPORTANT: Call BEFORE loadMap() so mapOrigin is computed from the correct scene.size.
    /// Adjust scene size to match the SKView's available bounds, then compute mapOrigin.
    /// IMPORTANT: Call BEFORE loadMap() so mapOrigin is computed from the correct scene.size.
    /// With scene.size = SKView bounds, the map is centered and mapOrigin ≠ zero.
    func fitSceneToView() {
        guard let view = self.view else { return }
        self.size = view.bounds.size
    }

    // MARK: - Load Map

    private func presentationTileMap(for room: Room) -> TileMap {
        var visibleMap = room.map
        if GameState.shared.dataAcquired {
            for y in visibleMap.indices {
                for x in visibleMap[y].indices where visibleMap[y][x] == TileType.dataTerminal.rawValue {
                    visibleMap[y][x] = TileType.floor.rawValue
                }
            }
        }
        if !RoomManager.shared.isExtractionActive(in: room) {
            for y in visibleMap.indices {
                for x in visibleMap[y].indices where visibleMap[y][x] == TileType.extraction.rawValue {
                    visibleMap[y][x] = TileType.floor.rawValue
                }
            }
        }
        return TileMap(tiles: visibleMap.map { row in row.map { TileType(rawValue: $0) ?? .floor } })
    }

    private func refreshObjectiveMarkers() {
        guard let room = RoomManager.shared.currentRoom,
              let mapNode = childNode(withName: "TileMap") else { return }
        mapNode.childNode(withName: "objectiveMarkers")?.removeFromParent()
        addObjectiveMarkers(to: mapNode, room: room)
    }

    private func addObjectiveMarkers(to mapNode: SKNode, room: Room) {
        let markerLayer = SKNode()
        markerLayer.name = "objectiveMarkers"
        markerLayer.zPosition = 18

        for connection in room.connections {
            addDoorMarker(
                to: markerLayer,
                x: connection.triggerTileX,
                y: connection.triggerTileY,
                cleared: RoomManager.shared.isRoomCleared(room.id)
            )
        }

        if RoomManager.shared.isExtractionActive(in: room) {
            addExtractionMarker(
                to: markerLayer,
                x: GameState.shared.extractionX,
                y: GameState.shared.extractionY
            )
        }

        mapNode.addChild(markerLayer)
    }

    /// Extraction marker: green pill centered on the helipad tile, same look
    /// as the door's UNLOCKED pill. Tappable via existing extraction-tile logic.
    private func addExtractionMarker(to layer: SKNode, x: Int, y: Int) {
        let center = TileMap.tileCenter(x: x, y: y)
        let nodeName = "extractionMarker_\(x)_\(y)"
        layer.childNode(withName: nodeName)?.removeFromParent()

        let group = SKNode()
        group.name = nodeName
        group.position = center
        group.zPosition = 1

        let accent = UIColor(hex: "#00FF88")
        let pillW: CGFloat = 64
        let pillH: CGFloat = 16
        let pill = SKShapeNode(rectOf: CGSize(width: pillW, height: pillH), cornerRadius: 4)
        pill.fillColor = UIColor.black.withAlphaComponent(0.78)
        pill.strokeColor = accent
        pill.lineWidth = 1.4
        pill.glowWidth = 5.0
        pill.position = .zero
        pill.zPosition = 0
        group.addChild(pill)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "EXTRACTION"
        label.fontSize = 9
        label.fontColor = accent
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 1
        group.addChild(label)

        pill.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7)
        ])))

        layer.addChild(group)
    }

    /// Door marker: pill-shaped label centered ON the door tile, with the text
    /// "LOCKED" (red) or "UNLOCKED" (green) depending on whether all enemies in
    /// the current room have been defeated. Tappable — handed off to
    /// handleDoorTileTap by the existing tap handler. The marker has a unique
    /// SKNode name per tile so refreshDoorMarkers() can find and rebuild it
    /// without recreating the whole objective layer.
    private func addDoorMarker(to layer: SKNode, x: Int, y: Int, cleared: Bool) {
        let center = TileMap.tileCenter(x: x, y: y)
        let nodeName = "doorMarker_\(x)_\(y)"
        layer.childNode(withName: nodeName)?.removeFromParent()

        let group = SKNode()
        group.name = nodeName
        group.position = center
        group.zPosition = 1

        let title = cleared ? "UNLOCKED" : "LOCKED"
        let accent = cleared ? UIColor(hex: "#00FF88") : UIColor(hex: "#FF3344")

        // Pill background sized to fit the text, centered on tile.
        let pillW: CGFloat = cleared ? 56 : 48
        let pillH: CGFloat = 16
        let pill = SKShapeNode(rectOf: CGSize(width: pillW, height: pillH), cornerRadius: 4)
        pill.fillColor = UIColor.black.withAlphaComponent(0.78)
        pill.strokeColor = accent
        pill.lineWidth = 1.4
        pill.glowWidth = 4.0
        pill.position = .zero
        pill.zPosition = 0
        group.addChild(pill)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = title
        label.fontSize = 9
        label.fontColor = accent
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 1
        group.addChild(label)

        // Subtle pulse so the player notices state changes (locked → unlocked).
        pill.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7)
        ])))

        layer.addChild(group)
    }

    private func addObjectiveMarker(to layer: SKNode, x: Int, y: Int, title: String, color: UIColor) {
        let center = TileMap.tileCenter(x: x, y: y)
        let ring = SKShapeNode(path: TileMap.hexPath(radius: TileMap.hexRadius + 5))
        ring.position = center
        ring.fillColor = .clear
        ring.strokeColor = color.withAlphaComponent(0.82)
        ring.lineWidth = 2.4
        ring.glowWidth = 5
        ring.zPosition = 0
        ring.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.35, duration: 0.55),
            SKAction.fadeAlpha(to: 1.0, duration: 0.55)
        ])))
        layer.addChild(ring)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = title
        label.fontSize = title.count > 5 ? 9 : 10
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: center.x, y: center.y + TileMap.hexRowSpacing * 0.72)
        label.zPosition = 1
        layer.addChild(label)
    }

    /// Load a mission's tile map.
    func loadMap(_ tileMap: TileMap) {
        let visibleTileMap: TileMap
        if let room = RoomManager.shared.currentRoom {
            visibleTileMap = presentationTileMap(for: room)
        } else {
            visibleTileMap = tileMap
        }
        self.tileMap = visibleTileMap
        addBoardBackplate(for: visibleTileMap)
        addRoomBackgroundImage(for: visibleTileMap)
        let mapNode = visibleTileMap.buildNode()
        // Center the map node in the scene so all tiles are within the camera's view.
        mapNode.position = mapOrigin
        addChild(mapNode)
        if let room = RoomManager.shared.currentRoom {
            addObjectiveMarkers(to: mapNode, room: room)
        }
        // Helicopter arrives from the sky during the extraction sequence —
        // no parked heli on the pad at room load (player calls it in by
        // touching the extraction tile, which triggers descent → land → takeoff).

        // Add ambient effects
        visibleTileMap.addAmbientEffects(to: mapNode, mapSize: visibleTileMap.size)

        // Mission-specific cyberpunk VFX (code rain, glitch bars, sparks, etc.)
        // — frames live in Sprites/vfx/ and are placed per
        // MissionVFXManifest. Density-capped at 6 ambient nodes per room.
        let vfxMissionId = currentMissionIdForVFX()
        VFXManager.shared.applyAmbientVFX(to: mapNode, missionId: vfxMissionId)

        // Coordinate labels (column/row numbers in cyan along the map's
        // top/left edges) — dev aid, disabled for playtest. Flip the gate
        // back to true if you need to debug a tile-coord issue.
        let showMapCoordinateLabels = false
        if showMapCoordinateLabels {
            addMapCoordinateLabels(tileMap: visibleTileMap)
        }

        // Re-center camera on the now-centered map.
        positionCameraOnMap()
        refreshTraceVisuals(force: true)

        dlog("[BattleScene] loadMap: mapNode at \(mapNode.position), mapSize=\(visibleTileMap.size), scene.size=\(self.size), mapOrigin=\(mapOrigin)")
    }

    /// Loads and displays a per-room background image (if one exists) sized
    /// exactly to the playable hex grid. The hex tiles drawn on top of this
    /// are transparent for floors so the background reads through.
    ///
    /// Filename convention (search order):
    ///   1. Multi-room: Sprites/backgrounds/<MissionId>_<roomId>.png
    ///                  e.g. "Mission001_room_0.png"
    ///   2. Multi-room fallback: Sprites/backgrounds/<MissionId>.png
    ///   3. Single-room: Sprites/backgrounds/<MissionId>.png
    private func addRoomBackgroundImage(for tileMap: TileMap) {
        childNode(withName: "roomBackground")?.removeFromParent()

        let candidates = roomBackgroundCandidates()
        var loaded: SKTexture? = nil
        for name in candidates {
            if let tex = SpriteManager.shared.loadBackgroundTexture(named: name) {
                loaded = tex
                dlog("[BattleScene] Loaded room background: \(name)")
                break
            }
        }
        guard let bgTex = loaded else { return }

        let bg = SKSpriteNode(texture: bgTex)
        bg.size = tileMap.size
        bg.anchorPoint = CGPoint(x: 0, y: 0)
        bg.position = CGPoint(x: mapOrigin.x, y: mapOrigin.y)
        // Above the dark backplate (-40) but below all tiles (0), characters (10+),
        // and HUD overlays.
        bg.zPosition = -30
        bg.name = "roomBackground"
        addChild(bg)
    }

    /// Resolve a stable mission identifier for VFX placement lookups.
    /// Returns "" if no mission is loaded — VFXManager handles empty input
    /// by spawning no ambient nodes.
    private func currentMissionIdForVFX() -> String {
        if let multi = RoomManager.shared.currentMission {
            let raw = multi.id
            let base = raw.replacingOccurrences(of: "_multi", with: "")
            if base.hasPrefix("run"), let n = Int(base.dropFirst("run".count)) {
                return String(format: "Mission%03d", n)
            }
            return base
        }
        return ""
    }

    /// Build the list of background filenames to search in priority order.
    private func roomBackgroundCandidates() -> [String] {
        var names: [String] = []
        // Try to find the active mission ID. Pull from the multi-room mission if
        // present, otherwise from any string we can find in the loaded mission.
        let missionId: String
        if let multi = RoomManager.shared.currentMission {
            // Multi-room mission — use its id (e.g. "run001_multi")
            // Strip "_multi" suffix and translate "runNNN" → "MissionNNN".
            let raw = multi.id
            let base = raw.replacingOccurrences(of: "_multi", with: "")
            if base.hasPrefix("run"), let n = Int(base.dropFirst("run".count)) {
                missionId = String(format: "Mission%03d", n)
            } else {
                missionId = base
            }
        } else {
            missionId = ""
        }
        if let room = RoomManager.shared.currentRoom, !missionId.isEmpty {
            names.append("\(missionId)_\(room.id).png")
        }
        if !missionId.isEmpty {
            names.append("\(missionId).png")
        }
        return names
    }

    /// Adds a deterministic backplate under the map to improve board readability and depth.
    private func addBoardBackplate(for tileMap: TileMap) {
        childNode(withName: "boardBackplate")?.removeFromParent()

        let backplate = SKShapeNode(
            rectOf: CGSize(width: tileMap.size.width + 44, height: tileMap.size.height + 36),
            cornerRadius: 16
        )
        backplate.name = "boardBackplate"
        backplate.fillColor = UIColor(hex: "#050A11").withAlphaComponent(0.88)
        backplate.strokeColor = UIColor(hex: "#1B2E43").withAlphaComponent(0.9)
        backplate.lineWidth = 1.6
        backplate.zPosition = -40
        backplate.position = CGPoint(
            x: mapOrigin.x + tileMap.size.width / 2,
            y: mapOrigin.y + tileMap.size.height / 2
        )
        addChild(backplate)

        // Subtle deterministic scan-lines clipped to the backplate footprint.
        let scanlineLayer = SKNode()
        scanlineLayer.zPosition = -39
        let lineSpacing: CGFloat = 9
        var y = -tileMap.size.height / 2
        while y <= tileMap.size.height / 2 {
            let line = SKShapeNode(rectOf: CGSize(width: tileMap.size.width + 32, height: 0.6))
            line.fillColor = UIColor(hex: "#00B8FF").withAlphaComponent(0.06)
            line.strokeColor = .clear
            line.position = CGPoint(x: 0, y: y)
            scanlineLayer.addChild(line)
            y += lineSpacing
        }
        scanlineLayer.position = backplate.position
        addChild(scanlineLayer)
    }

    private func refreshTraceVisuals(force: Bool = false) {
        let tier = GameState.shared.traceTier
        guard force || tier != lastRenderedTraceTier else { return }
        lastRenderedTraceTier = tier

        guard let backplate = childNode(withName: "boardBackplate") as? SKShapeNode else { return }
        let scanlineNodes = children
            .filter { $0.zPosition == -39 }
            .flatMap(\.children)
            .compactMap { $0 as? SKShapeNode }

        switch tier {
        case 2:
            backplate.fillColor = UIColor(hex: "#22060A").withAlphaComponent(0.9)
            backplate.strokeColor = UIColor(hex: "#FF5566").withAlphaComponent(0.9)
            for node in scanlineNodes {
                node.fillColor = UIColor(hex: "#FF5544").withAlphaComponent(0.08)
            }
        case 1:
            backplate.fillColor = UIColor(hex: "#1E1408").withAlphaComponent(0.9)
            backplate.strokeColor = UIColor(hex: "#FFAA44").withAlphaComponent(0.9)
            for node in scanlineNodes {
                node.fillColor = UIColor(hex: "#FFAA44").withAlphaComponent(0.07)
            }
        default:
            backplate.fillColor = UIColor(hex: "#050A11").withAlphaComponent(0.88)
            backplate.strokeColor = UIColor(hex: "#1B2E43").withAlphaComponent(0.9)
            for node in scanlineNodes {
                node.fillColor = UIColor(hex: "#00B8FF").withAlphaComponent(0.06)
            }
        }
    }

    private func addMapCoordinateLabels(tileMap: TileMap) {
        let labelNode = SKNode()
        labelNode.zPosition = 80
        labelNode.name = "coordinateLabels"

        // X-axis labels (column numbers) at top — use tileCenter for hex-stagger-aware x positions.
        // Use the last row to get the most accurate label positions (row 0 = bottom, mapHeight-1 = top).
        let topRowY = tileMap.mapHeight - 1
        for x in 0..<TileMap.mapWidth {
            let label = SKLabelNode(text: "\(x)")
            label.fontName = "Courier"
            label.fontSize = 8
            label.fontColor = UIColor(hex: "#00D4FF").withAlphaComponent(0.5)
            label.position = CGPoint(
                x: tileCenter(x, topRowY).x,
                y: mapOrigin.y + CGFloat(tileMap.mapHeight) * TileMap.hexRowSpacing + 12
            )
            label.zPosition = 80
            labelNode.addChild(label)
        }

        // Y-axis labels (row numbers) at left — delegate vertical position to tileCenter
        // so labels line up exactly with each row's hex center, regardless of hex orientation.
        for y in 0..<tileMap.mapHeight {
            let label = SKLabelNode(text: "\(y)")
            label.fontName = "Courier"
            label.fontSize = 8
            label.fontColor = UIColor(hex: "#00D4FF").withAlphaComponent(0.5)
            label.position = CGPoint(
                x: mapOrigin.x - 12,
                y: tileCenter(0, y).y
            )
            label.zPosition = 80
            labelNode.addChild(label)
        }

        addChild(labelNode)
    }

    /// Reconcile the visible roster directly from GameState.
    /// Used as a safety net when the initial scheduled load loses the first-frame team/enemy arrays.
    private func syncCombatantsFromGameState(reason: String) {
        guard tileMap != nil else { return }

        let desiredPlayers = GameState.shared.playerTeam.filter { $0.isAlive }
        let desiredEnemies = GameState.shared.enemies.filter { $0.isAlive }
        let desiredIds = Set(desiredPlayers.map(\.id)).union(desiredEnemies.map(\.id))

        for (id, node) in characterNodes where !desiredIds.contains(id) {
            node.removeFromParent()
            characterNodes.removeValue(forKey: id)
        }

        for character in desiredPlayers {
            if let node = characterNodes[character.id] as? SpriteNode {
                node.tileX = character.positionX
                node.tileY = character.positionY
                node.position = tileCenter(character.positionX, character.positionY)
                node.zPosition = playerDepthZ(for: character)
                node.isHidden = false
                node.alpha = 1.0
            } else {
                placeCharacter(character)
            }
        }

        for enemy in desiredEnemies {
            if let node = characterNodes[enemy.id] as? SpriteNode {
                node.tileX = enemy.positionX
                node.tileY = enemy.positionY
                node.position = tileCenter(enemy.positionX, enemy.positionY)
                node.zPosition = depthZ(forTileY: enemy.positionY, isEnemy: true)
                node.isHidden = false
                node.alpha = 1.0
            } else {
                placeEnemy(enemy)
            }
        }

        if let activeId = GameState.shared.activeCharacterId ?? GameState.shared.selectedCharacterId {
            focusCamera(on: activeId)
        } else if let first = desiredPlayers.first {
            focusCamera(on: first.positionX, y: first.positionY)
        }

        let activeId = GameState.shared.activeCharacter?.id ?? GameState.shared.currentCharacter?.id
        refreshActiveUnitHighlight(activeId: activeId)

        dlog("[BattleScene] syncCombatantsFromGameState(\(reason)) players=\(desiredPlayers.count) enemies=\(desiredEnemies.count) nodes=\(characterNodes.count)")
    }

    // MARK: - Coordinate Helpers

    /// Single source of truth for converting a tile coord to scene position.
    /// Delegates to TileMap.tileCenter(x:y:) so hex row stagger is applied consistently
    /// for both tile rendering and character/highlight placement.
    func tileCenter(_ tileX: Int, _ tileY: Int) -> CGPoint {
        let local = TileMap.tileCenter(x: tileX, y: tileY)
        dlog("[BattleScene] tileCenter(\(tileX),\(tileY)) → local=\(local) mapOrigin=\(mapOrigin)")
        return CGPoint(x: mapOrigin.x + local.x, y: mapOrigin.y + local.y)
    }

    /// 6 hex neighbours for a flat-top odd-q offset grid (column stagger).
    /// Even columns: upper-left/right neighbours use y-1.
    /// Odd columns:  upper-left/right neighbours use y (same row).
    func hexNeighbors(x: Int, y: Int) -> [(Int, Int)] {
        if x % 2 == 0 {
            return [(x,y-1),(x,y+1),(x-1,y-1),(x-1,y),(x+1,y-1),(x+1,y)]
        } else {
            return [(x,y-1),(x,y+1),(x-1,y),(x-1,y+1),(x+1,y),(x+1,y+1)]
        }
    }

    // MARK: - Character Placement

    /// Place a character sprite on the map, accounting for map centering offset.
    /// Compute zPosition from tile-Y so southern (lower-on-screen) sprites
    /// render on top of northern sprites — standard 2.5D depth-sort. Without
    /// this, two sprites at adjacent tiles fight for visibility based on
    /// whichever was added to the scene last, which is what caused M3 R0's
    /// mage to render on top of the samurai despite being "behind" him.
    /// Z-order rule (per playtest spec 2026-05-23):
    ///   1. Selection always wins (+1000 bump applied at the call site for
    ///      both player selection and enemy targeting).
    ///   2. Otherwise: higher tileY = "in front" on screen → renders on top.
    ///   3. Same-tileY tiebreak: ENEMY wins. Contested-hex (player + enemy
    ///      on the same tile during e.g. melee swap-frames) should read as
    ///      the threat being closest. Tiebreak delta is 0.1, well under the
    ///      0.5/row depth contribution so any real tileY gap still wins.
    private func depthZ(forTileY y: Int, isEnemy: Bool) -> CGFloat {
        let base: CGFloat = 40 + CGFloat(y) * 0.5
        return isEnemy ? base + 0.1 : base
    }

    /// Z for a player sprite. Standard 2.5D depth-sort by tileY: characters
    /// lower on screen (higher tileY in this game's convention) render in
    /// front. A *tiny* party-order tiebreaker is added so when teammates
    /// stand at the same tileY (e.g. M1 starting horizontal formation),
    /// the leader (Raze, idx 0) wins over teammates added to the scene
    /// later — without that, Sable's sprite covered Raze just because she
    /// was added second.
    ///
    /// Tiebreaker delta is intentionally far below the per-row contribution
    /// (`0.5 / row` vs `0.015 / index`), so any real tileY difference still
    /// wins. If Sable stands one row "in front" of Raze on screen, Sable
    /// correctly occludes him. Selection's +1000 bump still overrides on top.
    private func playerDepthZ(forTileY y: Int, partyIndex: Int) -> CGFloat {
        let base = depthZ(forTileY: y, isEnemy: false)
        let boost = CGFloat(max(0, 4 - partyIndex)) * 0.015
        return base + boost
    }

    private func playerDepthZ(for character: Character) -> CGFloat {
        let idx = GameState.shared.playerTeam.firstIndex(where: { $0.id == character.id }) ?? 0
        return playerDepthZ(forTileY: character.positionY, partyIndex: idx)
    }

    private func playerDepthZ(forSprite sprite: SpriteNode) -> CGFloat {
        let idx = GameState.shared.playerTeam.firstIndex(where: { $0.id.uuidString == sprite.characterId }) ?? 0
        return playerDepthZ(forTileY: sprite.tileY, partyIndex: idx)
    }

    func placeCharacter(_ character: Character) {
        guard character.isAlive else { return }

        // Remove any prior sprite for this id BEFORE adding a new one. If we
        // skip this, two sprites end up at the same screen position and
        // their HP labels stack — that's the "28/18" garbled-HP bug.
        let nameTag = "player_\(character.id.uuidString)"
        if let prior = characterNodes[character.id] { prior.removeFromParent() }
        for child in self.children where child.name == nameTag { child.removeFromParent() }

        // Party-index stagger lifts each runner's HP label/stun-bar group
        // by 5pt per index so the spawn-cluster's four labels form a tiny
        // vertical column instead of stacking on top of each other.
        // (Bug pattern: M1 spawn put all four party members on the same row,
        // labels rendered at identical Y and were illegible.)
        let partyIndex = GameState.shared.playerTeam.firstIndex { $0.id == character.id } ?? 0
        let node = SpriteManager.shared.createCharacter(
            type: character.archetype.rawValue,
            team: "player",
            x: character.positionX,
            y: character.positionY,
            name: character.name,
            level: character.level,
            ownerId: character.id.uuidString,
            labelStaggerIndex: partyIndex
        )
        node.name = "player_\(character.id.uuidString)"
        node.characterId = character.id.uuidString
        node.tileX = character.positionX
        node.tileY = character.positionY
        node.team = "player"
        node.position = tileCenter(character.positionX, character.positionY)
        node.zPosition = playerDepthZ(for: character)
        node.alpha = 1.0
        node.isHidden = false
        addChild(node)
        characterNodes[character.id] = node
        SpriteManager.shared.updateHP(on: node, currentHP: character.currentHP, maxHP: character.maxHP, currentStun: character.currentStun, maxStun: character.maxStun, level: character.level, isPlayer: true)
        dlog("[BattleScene] placeCharacter \(character.name) at tile(\(character.positionX),\(character.positionY)) → pos \(node.position) scene.size=\(self.size) mapOrigin=\(mapOrigin) parent=\(node.parent?.name ?? "nil")")
    }

    /// Place an enemy sprite on the map, accounting for map centering offset.
    func placeEnemy(_ enemy: Enemy) {
        // Remove any prior sprite for this id (same fix as placeCharacter
        // — orphan sprites stack their HP labels and render as garbled
        // values like "28/18" when the live label updates and the orphan's
        // doesn't).
        let nameTag = "enemy_\(enemy.id.uuidString)"
        if let prior = characterNodes[enemy.id] { prior.removeFromParent() }
        for child in self.children where child.name == nameTag { child.removeFromParent() }

        let node = SpriteManager.shared.createCharacter(
            type: enemy.archetype,
            team: "enemy",
            x: enemy.positionX,
            y: enemy.positionY,
            name: enemy.name,
            level: 1,
            ownerId: enemy.id.uuidString
        )
        node.name = "enemy_\(enemy.id.uuidString)"
        node.enemyId = enemy.id.uuidString
        node.tileX = enemy.positionX
        node.tileY = enemy.positionY
        node.team = "enemy"
        node.position = tileCenter(enemy.positionX, enemy.positionY)
        node.zPosition = depthZ(forTileY: enemy.positionY, isEnemy: true)
        node.alpha = 1.0
        node.isHidden = false

        // HP bar — floats ABOVE the enemy sprite, not on top of its torso.
        // Sprite uses anchor (0.5, 0.0) at position y=-TileMap.hexRowSpacing/2+4
        // ≈ y=-27, with display height ~70pt → sprite top at y=+43.
        // Previously the HP bar sat at y=22 which placed it MID-BODY on every
        // enemy (most visible on corpmage's purple cape). Bumped to y=58 +
        // y=66 so it clears the sprite top with a small gap.
        //
        // Boss sprites (bossmech / bossagi) are 140pt tall instead of 70 —
        // sprite top sits at y≈+113. The default y=58/66 HP bar drew INSIDE
        // the boss torso (hidden behind the larger sprite), so the player
        // saw "HP not draining" even though damage was applying. Push the
        // boss HP UI up to clear the taller body. Also widen the bar so
        // the visual matches the bigger sprite.
        let isBoss = enemy.archetype == "bossmech" || enemy.archetype == "bossagi"
        // Trimmed ~15% per playtest note — bars were chunky relative to the
        // sprite. Normal 26→22, boss 48→40. Heights stay at their fine values.
        let enemyBarWidth: CGFloat = isBoss ? 40.0 : 22.0
        let hpBarHeight: CGFloat = isBoss ? 3.5 : 3.0
        // Per-enemy stagger: when multiple enemies cluster (M5 mech bay, M6
        // server core ring), their HP bars / labels would otherwise stack at
        // the same Y. Lift each by 5pt per their array index so they form a
        // small vertical fan. Bosses don't stagger — they're alone in the
        // room visually and the bar is already pushed up off-body.
        let enemyIdx = GameState.shared.enemies.firstIndex { $0.id == enemy.id } ?? 0
        let enemyStagger: CGFloat = isBoss ? 0 : CGFloat(enemyIdx % 3) * 6.0
        let hpBarY: CGFloat = (isBoss ? 119.0 : 50.0) + enemyStagger
        let hpLabelY: CGFloat = (isBoss ? 126.0 : 56.0) + enemyStagger
        // HP-bar children are UUID-suffixed by enemy id. `SpriteManager.updateHP`
        // reads `SpriteNode.enemyId` and looks up `"hpBarFill_<uuid>"` — so even
        // if a stale duplicate ever lands in the same subtree, this enemy's
        // own bar is the one that updates. (Defense-in-depth: the duplicate
        // creation that caused the corp-guard "14/14 vs 9/18" bug was removed
        // earlier, but the suffix prevents the pattern from regressing.)
        let hpSuffix = "_\(enemy.id.uuidString)"

        let hpBarBg = SKShapeNode(rectOf: CGSize(width: enemyBarWidth, height: hpBarHeight), cornerRadius: hpBarHeight / 2)
        hpBarBg.fillColor = UIColor.black.withAlphaComponent(0.7)
        hpBarBg.strokeColor = UIColor.clear
        hpBarBg.position = CGPoint(x: 0, y: hpBarY)
        hpBarBg.zPosition = 20
        hpBarBg.name = "hpBarBg\(hpSuffix)"
        hpBarBg.userData = NSMutableDictionary()
        hpBarBg.userData?["barWidth"] = enemyBarWidth
        hpBarBg.userData?["barHeight"] = hpBarHeight
        node.addChild(hpBarBg)

        let hpBarFill = SKShapeNode()
        hpBarFill.fillColor = UIColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 0.9)
        hpBarFill.strokeColor = UIColor.clear
        hpBarFill.position = CGPoint(x: 0, y: hpBarY)
        hpBarFill.zPosition = 21
        hpBarFill.name = "hpBarFill\(hpSuffix)"
        node.addChild(hpBarFill)

        let hpLabel = SKLabelNode(text: "\(enemy.currentHP)/\(enemy.maxHP)")
        hpLabel.fontSize = isBoss ? 6.5 : 5.5
        hpLabel.fontName = "Menlo-Bold"
        hpLabel.fontColor = UIColor(red: 0.2, green: 1.0, blue: 0.3, alpha: 1.0)
        hpLabel.position = CGPoint(x: 0, y: hpLabelY)
        hpLabel.zPosition = 21
        hpLabel.name = "hpLabel\(hpSuffix)"
        node.addChild(hpLabel)

        addEnemyIntentMarker(to: node, enemy: enemy, y: hpLabelY + (isBoss ? 13 : 11))

        addChild(node)
        characterNodes[enemy.id] = node
        SpriteManager.shared.updateHP(on: node, currentHP: enemy.currentHP, maxHP: enemy.maxHP, currentStun: enemy.currentStun, maxStun: enemy.maxStun)
        dlog("[BattleScene] placeEnemy \(enemy.name) at tile(\(enemy.positionX),\(enemy.positionY)) → pos \(node.position)")
    }

    private func addEnemyIntentMarker(to node: SKNode, enemy: Enemy, y: CGFloat) {
        node.childNode(withName: "enemyIntentMarker")?.removeFromParent()

        let kind = predictedIntent(for: enemy)
        let color = intentColor(kind)
        let marker = SKNode()
        marker.name = "enemyIntentMarker"
        marker.position = CGPoint(x: 0, y: y)
        marker.zPosition = 24
        marker.alpha = intentAlpha(kind)

        let shell = SKShapeNode(rectOf: CGSize(width: 14, height: 12), cornerRadius: 4)
        shell.fillColor = UIColor.black.withAlphaComponent(0.55)
        shell.strokeColor = color.withAlphaComponent(kind == .attack || kind == .move ? 0.45 : 0.75)
        shell.lineWidth = 0.8
        shell.zPosition = 0
        marker.addChild(shell)

        let icon = makeIntentIcon(kind: kind, color: color)
        icon.setScale(0.72)
        icon.zPosition = 1
        marker.addChild(icon)

        if kind == .heavy {
            marker.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.55, duration: 0.55),
                SKAction.fadeAlpha(to: 0.95, duration: 0.55)
            ])), withKey: "intentPulse")
        }

        node.addChild(marker)
    }

    private func predictedIntent(for enemy: Enemy) -> EnemyIntentKind {
        if case .stunned = enemy.status { return .defend }
        let archetype = enemy.archetype.lowercased()
        if archetype.contains("healer") || archetype.contains("medic") {
            let woundedAllyExists = GameState.shared.livingEnemies.contains {
                $0.id != enemy.id && $0.currentHP < $0.maxHP
            }
            return woundedAllyExists ? .support : .attack
        }
        if archetype.contains("boss") || archetype.contains("mech") || archetype.contains("sniper") {
            return .heavy
        }
        if archetype.contains("mage") || archetype.contains("agi") {
            return .special
        }
        if archetype.contains("bruiser") || archetype.contains("spider") {
            return .move
        }
        if enemy.equippedWeapon?.type == .blade || enemy.equippedWeapon?.type == .unarmed {
            return .move
        }
        return .attack
    }

    private func intentColor(_ kind: EnemyIntentKind) -> UIColor {
        switch kind {
        case .attack:  return UIColor(hex: "#FF6677")
        case .move:    return UIColor(hex: "#00D8FF")
        case .defend:  return UIColor(hex: "#B8BCC8")
        case .support: return UIColor(hex: "#00FF88")
        case .special: return UIColor(hex: "#AA66FF")
        case .heavy:   return UIColor(hex: "#FFB000")
        }
    }

    private func intentAlpha(_ kind: EnemyIntentKind) -> CGFloat {
        switch kind {
        case .attack, .move, .defend: return 0.62
        case .support, .special: return 0.82
        case .heavy: return 0.92
        }
    }

    private func makeIntentIcon(kind: EnemyIntentKind, color: UIColor) -> SKNode {
        switch kind {
        case .attack:
            let icon = SKNode()
            let ring = SKShapeNode(circleOfRadius: 4.2)
            ring.strokeColor = color
            ring.lineWidth = 1.2
            ring.fillColor = .clear
            icon.addChild(ring)
            let h = SKShapeNode(rectOf: CGSize(width: 10, height: 1.2), cornerRadius: 0.6)
            h.fillColor = color
            h.strokeColor = .clear
            icon.addChild(h)
            let v = SKShapeNode(rectOf: CGSize(width: 1.2, height: 10), cornerRadius: 0.6)
            v.fillColor = color
            v.strokeColor = .clear
            icon.addChild(v)
            return icon
        case .move:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -4, y: -5))
            path.addLine(to: CGPoint(x: 4, y: 0))
            path.addLine(to: CGPoint(x: -4, y: 5))
            let arrow = SKShapeNode(path: path)
            arrow.strokeColor = color
            arrow.lineWidth = 2
            arrow.lineCap = .round
            arrow.lineJoin = .round
            arrow.fillColor = .clear
            return arrow
        case .defend:
            let shield = SKShapeNode(path: {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 5, y: 3))
                path.addLine(to: CGPoint(x: 4, y: -3))
                path.addLine(to: CGPoint(x: 0, y: -6))
                path.addLine(to: CGPoint(x: -4, y: -3))
                path.addLine(to: CGPoint(x: -5, y: 3))
                path.closeSubpath()
                return path
            }())
            shield.strokeColor = color
            shield.lineWidth = 1.4
            shield.fillColor = color.withAlphaComponent(0.18)
            return shield
        case .support:
            let icon = SKNode()
            let h = SKShapeNode(rectOf: CGSize(width: 10, height: 2.2), cornerRadius: 1)
            h.fillColor = color
            h.strokeColor = .clear
            icon.addChild(h)
            let v = SKShapeNode(rectOf: CGSize(width: 2.2, height: 10), cornerRadius: 1)
            v.fillColor = color
            v.strokeColor = .clear
            icon.addChild(v)
            return icon
        case .special:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 1, y: 6))
            path.addLine(to: CGPoint(x: -4, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: -1, y: -6))
            path.addLine(to: CGPoint(x: 5, y: 1))
            path.addLine(to: CGPoint(x: 1, y: 1))
            path.closeSubpath()
            let bolt = SKShapeNode(path: path)
            bolt.fillColor = color
            bolt.strokeColor = .clear
            return bolt
        case .heavy:
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = "!"
            label.fontSize = 12
            label.fontColor = color
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            return label
        }
    }

    /// Update character position.
    func moveCharacter(id: UUID, toX: Int, toY: Int) {
        guard let node = characterNodes[id] else { return }
        SpriteManager.shared.animateMove(target: node, toTileX: toX, toTileY: toY, mapOrigin: mapOrigin)
    }

    /// Remove a character sprite.
    func removeCharacter(id: UUID) {
        guard let node = characterNodes[id] else { return }
        let nodeName = node.name      // capture before async — pattern is "player_<uuid>" or "enemy_<uuid>"
        SpriteManager.shared.animateDeath(target: node)
        characterNodes.removeValue(forKey: id)

        // Belt-and-suspenders: schedule a HARD removal 0.6s out (animateDeath
        // is 0.5s; we add a 0.1s margin). Without this, the mage in M6 R1
        // was occasionally lingering on screen after death — the SKAction
        // chain inside animateDeath sometimes failed to run its trailing
        // removeFromParent step (likely because a competing action with the
        // same key was queued by another path). The hard remove is a no-op
        // if the node is already gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak node, weak self] in
            node?.removeFromParent()
            // Also sweep for any orphan node sharing this character's name
            // (e.g. a duplicate sprite created by a stale code path).
            guard let self = self, let nodeName = nodeName else { return }
            for child in self.children where child.name == nodeName {
                child.removeFromParent()
            }
        }
    }

    // MARK: - Selection

    /// Select a character by ID and highlight it.
    func selectCharacter(id: UUID) {
        deselectCurrent()

        guard let node = characterNodes[id] else { return }
        selectedCharacterNode = node
        SpriteManager.shared.animateSelect(target: node)

        // Z-bump: selected character ALWAYS renders in the foreground so
        // they aren't visually obstructed by other sprites at adjacent or
        // northern tiles. Unbumped on deselect (depthZ-by-tileY restored).
        if let sprite = node as? SpriteNode {
            sprite.zPosition = playerDepthZ(forSprite: sprite) + 1000
        }

        // Update UI
        NotificationCenter.default.post(
            name: .characterSelected,
            object: nil,
            userInfo: ["characterId": id.uuidString]
        )
    }

    /// Deselect the current character.
    func deselectCurrent() {
        if let node = selectedCharacterNode {
            SpriteManager.shared.deselect(target: node)
            // Restore depth-by-tileY so the previously-selected sprite
            // sinks back into normal layering. Player team is the only
            // selectable group, so isEnemy: false is safe here.
            if let sprite = node as? SpriteNode {
                sprite.zPosition = playerDepthZ(forSprite: sprite)
            }
            selectedCharacterNode = nil
        }
    }

    /// Get character at a tile position.

    // MARK: - Turn Indicator

    /// Highlight the current actor.
    func updateTurnIndicator() {
        guard !turnOrder.isEmpty, currentTurnIndex < turnOrder.count else { return }
        let current = turnOrder[currentTurnIndex]
        selectCharacter(id: current.id)

        NotificationCenter.default.post(
            name: .turnChanged,
            object: nil,
            userInfo: ["characterId": current.id.uuidString]
        )
    }

    /// Show movement range on the map.
    func showMoveRange(tiles: [(Int, Int)]) {
        tileMap?.clearHighlights()
        for (x, y) in tiles {
            tileMap?.highlightTile(at: x, y: y, color: UIColor(hex: "#00FF88"))
        }
    }

    func showAttackRange(tiles: [(Int, Int)]) {
        tileMap?.clearHighlights()
        for (x, y) in tiles {
            tileMap?.highlightTile(at: x, y: y, color: UIColor(hex: "#FF6600"))
        }
    }

    // MARK: - Room Transition

    /// Trigger a fade-to-black room transition.
    private func performRoomTransitionFade() {
        // Update currentRoomId immediately so any code checking it during transition
        // gets the NEW room's ID (prevents stale references when transition completes).
        if let targetRoom = RoomManager.shared.pendingRoomTransition {
            currentRoomId = targetRoom.id
        }

        // Create a full-screen black overlay. Attach it to the camera node so it
        // always covers the entire viewport regardless of camera position.
        // Camera-space: (0,0) = screen center, size matches the scene's viewport.
        let fade = SKSpriteNode(color: .black, size: self.size)
        fade.position = .zero   // center of camera viewport
        fade.zPosition = 500
        fade.alpha = 0
        fade.name = "fadeOverlay"

        guard let cam = camera else {
            // No camera yet — fall back to adding directly in scene space
            fade.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
            addChild(fade)
            self.fadeNode = fade
            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.4)
            fade.run(fadeIn) {
                NotificationCenter.default.post(name: .roomTransitionCompleted, object: nil)
            }
            return
        }
        cam.addChild(fade)
        self.fadeNode = fade   // store reference so fadeOutFromTransition can use it directly

        // Add room title label as child of the overlay (fades with it).
        // Timing — tuned 2026-05-18 per playtest "transitions need to take
        // a moment longer with the next room name displaying longer":
        //   0.0s  black fades in
        //   0.6s  black fully opaque, label starts fading in
        //   1.0s  label fully visible
        //   2.8s  label has held for ~1.8s, starts fading out
        //   3.1s  label gone; new room map already loaded behind black
        //   …then fadeOutFromTransition reveals the new room (0.6s)
        //
        // The label hold landed before the new room loaded, so the player
        // sees the destination name for a beat before the map reveal —
        // matches modern game room-transition pacing.
        let blackFadeInDur: TimeInterval = 0.6
        let labelHoldDur:   TimeInterval = 1.8
        if let targetRoom = RoomManager.shared.pendingRoomTransition {
            // ─── Vertical layout ───────────────────────────────────────────
            // Centering target (per playtest spec 2026-05-23): the player
            // reads the {room name + sigil mark} as ONE unit — that pair
            // needs to land centered on screen, with room name slightly
            // above true center and the mark just below. The ENTERING
            // sub-label + horizontal rule are subordinate framing and live
            // above/between the focal pair.
            //
            // Math: previous +30 offset put the room-name-to-sigil pair
            // mid at y=0 (room name 38pt above, sigil 38pt below). User
            // still saw too much empty space above the room name because
            // the room name was reading as the screen's vertical anchor.
            // Bump to +50 so the pair mid lands at y=+20 (room name reads
            // as visually anchored just above center, sigil sits just below
            // center — exactly the framing the spec calls for).
            let blockYOffset: CGFloat = 50
            let roomLabel = SKLabelNode(text: targetRoom.title.uppercased())
            roomLabel.fontName = "Helvetica-Bold"
            roomLabel.fontSize = 26
            roomLabel.fontColor = UIColor(hex: "#00FF88")
            roomLabel.position = CGPoint(x: 0, y: 8 + blockYOffset)
            roomLabel.zPosition = 1
            roomLabel.alpha = 0
            roomLabel.name = "roomTransitionLabel"
            fade.addChild(roomLabel)

            // "ENTERING" sub-label above the room name for narrative framing.
            let sub = SKLabelNode(text: "ENTERING")
            sub.fontName = "Menlo-Bold"
            sub.fontSize = 11
            sub.fontColor = UIColor(hex: "#00FFCC").withAlphaComponent(0.75)
            sub.position = CGPoint(x: 0, y: 34 + blockYOffset)
            sub.zPosition = 1
            sub.alpha = 0
            sub.name = "roomTransitionSubLabel"
            fade.addChild(sub)

            // Thin horizontal rule under the room name — adds cinematic weight.
            let rule = SKShapeNode(rectOf: CGSize(width: 140, height: 1))
            rule.fillColor = UIColor(hex: "#00FF88").withAlphaComponent(0.55)
            rule.strokeColor = .clear
            rule.position = CGPoint(x: 0, y: -16 + blockYOffset)
            rule.zPosition = 1
            rule.alpha = 0
            fade.addChild(rule)

            // Zero State studio sigil — centered seal below the room name.
            // Sized larger (60pt) and at full opacity to read like a deliberate
            // packet header against the black backdrop. Sits below the
            // horizontal rule and above the "TAP TO CONTINUE" indicator zone.
            var sigilSprite: SKSpriteNode? = nil
            if let sigilTex = roomTransitionSigilTexture() {
                let sigil = SKSpriteNode(texture: sigilTex)
                let targetW: CGFloat = 60
                let scale = targetW / max(1, sigil.size.width)
                sigil.setScale(scale)
                sigil.alpha = 0
                sigil.position = CGPoint(x: 0, y: -68 + blockYOffset)
                sigil.zPosition = 1
                sigil.name = "roomTransitionSigil"
                fade.addChild(sigil)
                sigilSprite = sigil
            }

            let labelFadeIn  = SKAction.fadeAlpha(to: 1.0, duration: 0.4)
            let labelWait    = SKAction.wait(forDuration: labelHoldDur)
            let labelFadeOut = SKAction.fadeOut(withDuration: 0.35)
            let leadIn       = SKAction.wait(forDuration: blackFadeInDur)
            let labelSeq     = SKAction.sequence([leadIn, labelFadeIn, labelWait, labelFadeOut])
            let sigilFadeIn  = SKAction.fadeAlpha(to: 0.85, duration: 0.4)
            let sigilSeq     = SKAction.sequence([leadIn, sigilFadeIn, labelWait, labelFadeOut])
            roomLabel.run(labelSeq)
            sub.run(labelSeq)
            rule.run(labelSeq)
            sigilSprite?.run(sigilSeq)
        }

        // Fade in the black overlay first; THEN hold (with label visible);
        // THEN post the transition-completed notification so the new room
        // loads while the player is still staring at the title card.
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: blackFadeInDur)
        let holdOnBlack = SKAction.wait(forDuration: 0.4 + labelHoldDur + 0.35)
        fade.run(SKAction.sequence([fadeIn, holdOnBlack])) { [weak self] in
            guard self != nil else { return }
            NotificationCenter.default.post(name: .roomTransitionCompleted, object: nil)
        }
    }

    /// Reload the scene with a new room's map after a transition fade completes.
    func loadRoom(_ room: Room, characters: [Character], enemies: [Enemy]) {
        currentRoomId = room.id
        GameState.shared.currentRoomId = room.id
        // Reset per-room first-kill tracking so the new room's
        // `removeOnFirstKill` barriers will fire on the next kill.
        GameState.shared.firstKillProcessedInRoom = false
        // Re-arm the "Jack in and hack the terminal" warning. Stale
        // confirmations from the previous room shouldn't bypass the warning
        // in a new room that also has a terminal.
        lastTerminalWarningAt = nil
        // Per-room narrative props. Currently only M3 Ritual Chamber needs
        // one — Sato's grimoire on its altar. Skipped if already acquired
        // (player came back to the room after pickup).
        spawnRoomSpecificProps(roomId: room.id)

        // Remove old tilemap
        childNode(withName: "TileMap")?.removeFromParent()
        childNode(withName: "coordinateLabels")?.removeFromParent()

        // Remove all character sprites
        for (_, node) in characterNodes {
            node.removeFromParent()
        }
        characterNodes.removeAll()

        // Build new tilemap
        let newTileMap = presentationTileMap(for: room)
        self.tileMap = newTileMap

        // Sync tiles to GameState for enemy pathfinding
        Task { @MainActor in
            GameState.shared.updateTilesForCurrentRoom(room.map)
        }
        let mapNode = newTileMap.buildNode()
        mapNode.position = mapOrigin
        addBoardBackplate(for: newTileMap)
        // Load this room's background AFTER the backplate so the BG sits above
        // the dark plate. Without this, room transitions kept the previous
        // room's BG showing because addRoomBackgroundImage() was only called
        // from loadMap (initial load), not from loadRoom (transitions).
        addRoomBackgroundImage(for: newTileMap)
        addChild(mapNode)
        addObjectiveMarkers(to: mapNode, room: room)
        // Mission-specific ambient VFX — must run on every room load,
        // not just the initial loadMap path. Without this call, transitions
        // into room_1, room_2, etc. would show no VFX.
        let vfxMissionId = currentMissionIdForVFX()
        VFXManager.shared.applyAmbientVFX(to: mapNode, missionId: vfxMissionId)
        // Heli arrives from sky on extraction — see playExtractionHelicopterAnimation.
        // No parked sprite on the pad at room load.

        // Center camera on map first — will be refined to character position below.
        positionCameraOnMap()

        // Place characters — validate every position against the NEW room's tile map.
        // Characters may carry coordinates from a different room (e.g. back-navigation or
        // first load) that land on walls, out-of-bounds tiles, or enemy spawn points here.
        // validatedSpawnX() checks room.map directly, so it's always correct for this room.
        let spawn = room.playerSpawn
        let livingCharacters = characters.filter { $0.isAlive }
        // Track tiles already chosen so siblings don't stack onto the same hex
        // when their proposed positions all fall back to the same nearest-walkable.
        var occupied: Set<String> = []
        // Pre-seed with positions that are already valid (won't be repositioned)
        // so subsequent fallback picks avoid those tiles too.
        for character in livingCharacters {
            let inBounds = character.positionY >= 0
                && character.positionY < room.map.count
                && character.positionX >= 0
                && character.positionX < (room.map.first?.count ?? 0)
            guard inBounds, !(character.positionX == 0 && character.positionY == 0) else { continue }
            let tile = room.map[character.positionY][character.positionX]
            let walkable = tile == TileType.floor.rawValue
                || tile == TileType.cover.rawValue
                || tile == TileType.door.rawValue
                || tile == TileType.extraction.rawValue
            if walkable {
                occupied.insert("\(character.positionX),\(character.positionY)")
            }
        }
        for (i, character) in livingCharacters.enumerated() {
            // Check 1: uninitialized position
            let isUnset = character.positionX == 0 && character.positionY == 0
            // Check 2: position out of bounds for this room
            let outOfBounds = character.positionY < 0
                || character.positionY >= room.map.count
                || character.positionX < 0
                || character.positionX >= (room.map.first?.count ?? 0)
            // Check 3: position is a wall / unwalkable tile in this room
            let isBlocked: Bool = {
                guard !isUnset && !outOfBounds else { return false }
                let tile = room.map[character.positionY][character.positionX]
                return tile != TileType.floor.rawValue
                    && tile != TileType.cover.rawValue
                    && tile != TileType.door.rawValue
                    && tile != TileType.extraction.rawValue
            }()
            // Check 4: another living runner is already on this exact tile
            // (caused by stale loadRoom resets stacking two runners on the
            // same coords). Treat as needing a re-spawn.
            let isStacked: Bool = {
                guard !isUnset && !outOfBounds && !isBlocked else { return false }
                return occupied.contains("\(character.positionX),\(character.positionY)")
            }()

            if isUnset || outOfBounds || isBlocked || isStacked {
                let candidate = validatedSpawnX(in: room,
                                                proposedX: spawn.x + i,
                                                proposedY: spawn.y,
                                                avoiding: occupied)
                character.positionX = candidate.x
                character.positionY = candidate.y
                dlog("[BattleScene] loadRoom: repositioned \(character.name) → (\(candidate.x),\(candidate.y)) reason: unset=\(isUnset) oob=\(outOfBounds) blocked=\(isBlocked) stacked=\(isStacked)")
            }
            occupied.insert("\(character.positionX),\(character.positionY)")
            placeCharacter(character)
        }

        // Place enemies for this room.
        for enemy in enemies {
            placeEnemy(enemy)
        }

        // Clear highlights
        clearHighlights()

        // Select first character
        if let first = livingCharacters.first {
            selectCharacter(id: first.id)

            // After room load, focus camera on the first character so they're
            // always visible — prevents spawn-at-edge-of-map invisible placement.
            focusCamera(on: first.positionX, y: first.positionY)

            // Freeze all player characters except the active one so only
            // the current actor's idle animation runs at mission start.
            updatePlayerIdleAnimations(activeId: first.id)
        }
    }

    /// Check if the given tile is a door tile in the current room.
    /// Returns false if the door has already been auto-opened.
    func isDoorTile(_ tileX: Int, _ tileY: Int) -> Bool {
        guard let tm = tileMap else { return false }
        let key = "\(tileX),\(tileY)"
        if openedDoorKeys.contains(key) { return false }  // already opened
        return tm.tiles[tileY][tileX] == .door
    }

    /// Check if the given tile is an extraction tile.
    func isExtractionTile(_ tileX: Int, _ tileY: Int) -> Bool {
        guard RoomManager.shared.isExtractionActive() else { return false }
        return tileX == GameState.shared.extractionX && tileY == GameState.shared.extractionY
    }

    /// Check if a given tile is walkable (floor, door, extraction, cover, or data terminal — NOT wall).
    func isWalkableTile(_ tileX: Int, _ tileY: Int) -> Bool {
        // Read from the LIVE mutable grid (gameState.currentMissionTiles) so
        // dynamic terrain edits — barrier drops, terminal hacks, etc. — are
        // immediately reflected in movement validation. The tileMap snapshot
        // is built once at room load and can't see runtime mutations.
        let tiles = GameState.shared.currentMissionTiles
        guard tileX >= 0, tileX < TileMap.mapWidth, tileY >= 0, tileY < tiles.count else { return false }
        guard tileX < tiles[tileY].count else { return false }
        let raw = tiles[tileY][tileX]
        guard let t = TileType(rawValue: raw) else { return false }
        return t == .floor || t == .door || t == .extraction || t == .cover || t == .dataTerminal
    }

    private func isUnhackedDataTerminal(_ tileX: Int, _ tileY: Int) -> Bool {
        let tiles = GameState.shared.currentMissionTiles
        guard tileY >= 0, tileY < tiles.count, tileX >= 0, tileX < tiles[tileY].count else { return false }
        return tiles[tileY][tileX] == TileType.dataTerminal.rawValue
    }

    /// True if the current room still has an unhacked required terminal that
    /// the player is about to walk past. Used by `handleDoorTileTap` to warn
    /// the player before they leave the room. The check uses the LIVE tile
    /// grid (`currentMissionTiles`) — once the terminal is hacked,
    /// `MissionSetupService.tilesWithoutDataTerminals` strips it from the
    /// active grid, so a successful hack naturally short-circuits this check.
    /// Place per-room narrative props. Currently only Sato's grimoire in M3R2.
    /// Hooked from `loadRoom` so it fires on every entry (including replays).
    private func spawnRoomSpecificProps(roomId: String) {
        // Strip any prior prop nodes from previous rooms.
        childNode(withName: "grimoireProp")?.removeFromParent()

        // Mission003 / Ritual Chamber — Sato's grimoire on the altar tile.
        guard GameState.shared.currentMissionDisplayId == "Mission003" else { return }
        guard roomId == "room_2" else { return }
        // If the player already grabbed it this run, don't respawn the visual.
        guard !GameState.shared.grimoireAcquired else { return }

        // Top-left corner of M3R2 (moved from center 3,5). Keeps the
        // grimoire OFF the natural spawn → boss → extraction axis so the
        // extraction tile can't auto-trigger before the player has had a
        // chance to detour for it.
        let grimoireTileX = 1
        let grimoireTileY = 1
        let tilePos = tileCenter(grimoireTileX, grimoireTileY)
        let mapNode = childNode(withName: "TileMap") ?? self
        let origin = mapNode.position

        let prop = SKNode()
        prop.name = "grimoireProp"
        prop.position = CGPoint(x: origin.x + tilePos.x, y: origin.y + tilePos.y - 6)
        prop.zPosition = 4  // above floor, below characters

        // Altar plinth — small dark hex base.
        let plinth = SKShapeNode(path: TileMap.hexPath(radius: 16))
        plinth.fillColor = UIColor(hex: "#1A0A0A").withAlphaComponent(0.85)
        plinth.strokeColor = UIColor(hex: "#FF3344").withAlphaComponent(0.55)
        plinth.lineWidth = 1.2
        plinth.zPosition = 0
        prop.addChild(plinth)

        // Pulsing red glow that pulls the eye to the altar.
        let glow = SKShapeNode(circleOfRadius: 18)
        glow.fillColor = UIColor(hex: "#FF1133").withAlphaComponent(0.20)
        glow.strokeColor = UIColor(hex: "#FF1133").withAlphaComponent(0.85)
        glow.lineWidth = 1.5
        glow.glowWidth = 4
        glow.zPosition = 1
        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.9),
            SKAction.fadeAlpha(to: 1.0, duration: 0.9)
        ])
        glow.run(SKAction.repeatForever(pulse))
        prop.addChild(glow)

        // The grimoire itself — emoji label as a stand-in for a sprite.
        let book = SKLabelNode(text: "📖")
        book.fontSize = 22
        book.verticalAlignmentMode = .center
        book.horizontalAlignmentMode = .center
        book.zPosition = 2
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 2, duration: 1.1),
            SKAction.moveBy(x: 0, y: -2, duration: 1.1)
        ])
        book.run(SKAction.repeatForever(bob))
        prop.addChild(book)

        // "GRIMOIRE" tracked label below the book — same vibe as door pills.
        let tag = SKLabelNode(text: "GRIMOIRE")
        tag.fontName = "Menlo-Bold"
        tag.fontSize = 7
        tag.fontColor = UIColor(hex: "#FF3344")
        tag.position = CGPoint(x: 0, y: -18)
        tag.zPosition = 3
        prop.addChild(tag)

        addChild(prop)
    }

    /// Called when the player picks up Sato's grimoire. Plays a brief
    /// "snatched" animation (scale up + fade out) on the prop node, then
    /// removes it. No-op if the prop isn't currently in the scene.
    private func handleGrimoireAcquired() {
        guard let prop = childNode(withName: "grimoireProp") else { return }
        let snatch = SKAction.group([
            SKAction.scale(to: 1.6, duration: 0.35),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.moveBy(x: 0, y: 22, duration: 0.35)
        ])
        snatch.timingMode = .easeOut
        prop.run(SKAction.sequence([snatch, SKAction.removeFromParent()]))
    }

    private func shouldBlockExitForUnhackedTerminal() -> Bool {
        // Only relevant on missions whose objective requires a terminal hack
        // (i.e. `dataAcquired` contributes to the score / unlocks extraction).
        guard GameState.shared.missionRequiresData else { return false }
        // Already hacked one — no warning needed.
        guard !GameState.shared.dataAcquired else { return false }
        // Scan the current room's live tile grid for any remaining terminal.
        let tiles = GameState.shared.currentMissionTiles
        for row in tiles {
            if row.contains(TileType.dataTerminal.rawValue) { return true }
        }
        return false
    }

    private func validatedSpawnX(in room: Room, proposedX: Int, proposedY: Int,
                                  avoiding: Set<String> = []) -> (x: Int, y: Int) {
        func isWalkable(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y < room.map.count, x >= 0, x < room.map[y].count else { return false }
            let tile = room.map[y][x]
            return tile == TileType.floor.rawValue || tile == TileType.cover.rawValue || tile == TileType.door.rawValue || tile == TileType.extraction.rawValue
        }
        func isFree(_ x: Int, _ y: Int) -> Bool {
            isWalkable(x, y) && !avoiding.contains("\(x),\(y)")
        }

        // Try the proposed tile first if it's free.
        if isFree(proposedX, proposedY) {
            return (proposedX, proposedY)
        }

        // Hex-aware ring search around the proposed tile — checks 6 hex
        // neighbors before falling further out. This produces a clean
        // adjacency cluster rather than diagonal stacking.
        let evenColNeighbors  = [(0,-1),(0,1),(-1,-1),(-1,0),(1,-1),(1,0)]
        let oddColNeighbors   = [(0,-1),(0,1),(-1,0),(-1,1),(1,0),(1,1)]
        var ring: [(Int, Int)] = (proposedX % 2 == 0) ? evenColNeighbors : oddColNeighbors
        var visited: Set<String> = ["\(proposedX),\(proposedY)"]
        var queue: [(Int, Int)] = ring.map { (proposedX + $0.0, proposedY + $0.1) }
        for q in queue { visited.insert("\(q.0),\(q.1)") }
        while !queue.isEmpty {
            let (cx, cy) = queue.removeFirst()
            if isFree(cx, cy) { return (cx, cy) }
            ring = (cx % 2 == 0) ? evenColNeighbors : oddColNeighbors
            for (dx, dy) in ring {
                let nx = cx + dx
                let ny = cy + dy
                let key = "\(nx),\(ny)"
                if visited.contains(key) { continue }
                visited.insert(key)
                queue.append((nx, ny))
            }
            // Bound the search to avoid runaway BFS on giant maps.
            if visited.count > 200 { break }
        }

        // Last-ditch fallback to the room's player-spawn anchor (better than
        // off-map). The caller's `avoiding` set will at least keep us off any
        // tile already taken by a sibling runner, but if nothing's reachable
        // we tolerate stacking on the spawn anchor.
        return (room.playerSpawn.x, room.playerSpawn.y)
    }

    /// Fade out after room load. Slightly longer than the fade-in so the
    /// new map reveals gracefully rather than snapping into view.
    func fadeOutFromTransition() {
        // Prefer the stored reference; fall back to child-name search in camera then scene.
        let fade: SKNode? = fadeNode
            ?? camera?.childNode(withName: "fadeOverlay")
            ?? childNode(withName: "fadeOverlay")
        guard let fade = fade else { return }
        let fadeOut = SKAction.fadeAlpha(to: 0.0, duration: 0.7)
        fadeOut.timingMode = .easeOut
        fade.run(fadeOut) { [weak self] in
            fade.removeFromParent()
            self?.fadeNode = nil
        }
    }

    // MARK: - Tap / Touch

    private func flashTile(tileX: Int, tileY: Int) {
        // Only flash if no existing flash on this tile (prevent stacking)
        if childNode(withName: "flashTile_\(tileX)_\(tileY)") != nil { return }
        HapticsManager.shared.tileTap()
        let tileNode = SKShapeNode(path: TileMap.hexPath(radius: TileMap.hexRadius - 2))
        tileNode.strokeColor = UIColor(hex: "#FFD700").withAlphaComponent(0.6)
        tileNode.lineWidth = 1.5
        tileNode.fillColor = UIColor(hex: "#FFD700").withAlphaComponent(0.15)
        tileNode.position = tileCenter(tileX, tileY)
        tileNode.zPosition = 5
        tileNode.name = "flashTile_\(tileX)_\(tileY)"
        addChild(tileNode)

        let fade = SKAction.fadeOut(withDuration: 0.25)
        let remove = SKAction.removeFromParent()
        tileNode.run(SKAction.sequence([fade, remove]))

        // Ripple effect — expanding ring
        let ripple = SKShapeNode(circleOfRadius: 5)
        ripple.strokeColor = UIColor(hex: "#FFD700").withAlphaComponent(0.5)
        ripple.lineWidth = 1.5
        ripple.fillColor = .clear
        ripple.position = tileNode.position
        ripple.zPosition = 6
        ripple.name = "flashRipple"
        addChild(ripple)
        let expand = SKAction.scale(to: 3.0, duration: 0.4)
        let fadeRipple = SKAction.fadeOut(withDuration: 0.4)
        let removeRipple = SKAction.removeFromParent()
        ripple.run(SKAction.sequence([SKAction.group([expand, fadeRipple]), removeRipple]))
    }

    private func handleTileTap(tileX: Int, tileY: Int) {
        // Guard: block all taps while player input is locked during enemy phase
        guard !playerInputLocked else {
            dlog("[BattleScene] Input locked — waiting for enemy phase")
            return
        }
        // Check extraction tile — win immediately if all enemies are cleared and player stands on it
        if isExtractionTile(tileX, tileY) {
            // Extraction resolution is GameState-authoritative.
            if let sprite = selectedCharacterNode as? SpriteNode,
               let charEntry = characterNodes.first(where: { $0.value === sprite }),
               GameState.shared.playerTeam.contains(where: { $0.id == charEntry.key && $0.isAlive }) {
                let reachable = bfsReachable(fromX: sprite.tileX, fromY: sprite.tileY, maxSteps: movementRange)
                let alreadyOnExtraction = sprite.tileX == tileX && sprite.tileY == tileY
                guard alreadyOnExtraction || reachable.contains(where: { $0.x == tileX && $0.y == tileY }) else {
                    GameState.shared.addLog("Move closer to extraction first.")
                    return
                }
                animateCharacterMove(characterId: charEntry.key, toTileX: tileX, toTileY: tileY)
                sprite.tileX = tileX
                sprite.tileY = tileY
                sprite.zPosition = playerDepthZ(forSprite: sprite)
                _ = GameState.shared.requestExtraction(characterId: charEntry.key, tileX: tileX, tileY: tileY)
            } else {
                _ = GameState.shared.requestExtraction(characterId: nil, tileX: tileX, tileY: tileY)
            }
            return
        }

        // Find what's on this tile
        var characterOnTile: (id: UUID, sprite: SpriteNode)?
        var enemyOnTile: (id: UUID, sprite: SpriteNode)?

        for (id, node) in characterNodes {
            guard let sprite = node as? SpriteNode else { continue }
            if sprite.tileX == tileX && sprite.tileY == tileY {
                if sprite.team == "player",
                   GameState.shared.playerTeam.contains(where: { $0.id == id && $0.isAlive }) {
                    characterOnTile = (id, sprite)
                } else if sprite.team == "enemy",
                          GameState.shared.enemies.contains(where: { $0.id == id && $0.isAlive }) {
                    enemyOnTile = (id, sprite)
                }
            }
        }
        // Defensive fallback: if no sprite matched but GameState says an
        // enemy is at this tile (sprite.tileX/Y can briefly desync after a
        // move animation), find that enemy's sprite node by id and route the
        // tap to attack handling instead of falling through to movement.
        if enemyOnTile == nil,
           let liveEnemy = GameState.shared.enemies.first(where: {
               $0.isAlive && $0.positionX == tileX && $0.positionY == tileY
           }),
           let node = characterNodes[liveEnemy.id] as? SpriteNode {
            enemyOnTile = (liveEnemy.id, node)
        }

        // Door tiles with an enemy on them: skip the door transition logic and go straight
        // to attack handling. The movement-into-locked-door check lives in handleDoorTileTap
        // and is not relevant when the player is tapping an enemy.
        // (Previously bound to a `doorTileWithEnemy` local — never read.)
        _ = isDoorTile(tileX, tileY) && enemyOnTile != nil

        if isDoorTile(tileX, tileY) && enemyOnTile == nil {
            if let (id, characterSprite) = characterOnTile,
               characterSprite !== selectedCharacterNode {
                showSelectionRing(for: id)
                CombatFlowController.requestCharacterSelectionFromScene(gameState: GameState.shared, id: id)
                return
            }

            handleDoorTileTap(tileX: tileX, tileY: tileY)
            return
        }

        // 1. Tap on player character -> select it (always allowed)
        if let (id, _) = characterOnTile {
            showSelectionRing(for: id)
            // Render layer emits selection intent only.
            CombatFlowController.requestCharacterSelectionFromScene(gameState: GameState.shared, id: id)
            return
        }

        // 2. Tap on enemy with a character selected -> set as target (no
        // auto-fire). Player picks the target first, then commits via the
        // ATK / SHT / HACK / SPELL HUD button. This gives them control over
        // which enemy gets hit instead of always defaulting to the first
        // option. The attack handlers fall back to nearest-living-enemy if
        // no target was set explicitly (already wired in performAttack).
        if let (_, enemySprite) = enemyOnTile {
            if GameState.shared.activeCharacterId != nil || GameState.shared.selectedCharacterId != nil {
                if let enemyId = UUID(uuidString: enemySprite.enemyId),
                   !enemySprite.enemyId.isEmpty,
                   let enemy = GameState.shared.enemies.first(where: { $0.id == enemyId && $0.isAlive }) {
                    GameState.shared.targetCharacterId = enemyId
                    GameState.shared.addLog("🎯 Targeting: \(enemy.name) — tap ATK / SHT / HACK to fire.")
                    showTargetRing(for: enemyId)
                } else {
                    GameState.shared.addLog("Cannot target this enemy.")
                }
                return
            } else {
                GameState.shared.addLog("Select a character first.")
                return
            }
        }

        // 3. Tap empty tile -> move the selected character (FREE action, no turn cost)
        guard let sprite = selectedCharacterNode as? SpriteNode else {
            GameState.shared.addLog("Select a character first.")
            return
        }

        // Block movement onto a door tile that did not route through door handling above.
        if isDoorTile(tileX, tileY) {
            GameState.shared.addLog("Cannot move onto a door tile.")
            return
        }

        guard let charEntry = characterNodes.first(where: { $0.value === sprite }) else { return }
        let charId = charEntry.key
        guard GameState.shared.playerTeam.contains(where: { $0.id == charId && $0.isAlive }) else {
            deselectCurrent()
            GameState.shared.selectedCharacterId = nil
            GameState.shared.activeCharacterId = nil
            return
        }

        if (tileMap?.tiles[tileY][tileX] ?? .floor) == .dataTerminal,
           isUnhackedDataTerminal(tileX, tileY) {
            let isAdjacent = hexNeighbors(x: sprite.tileX, y: sprite.tileY).contains(where: { neighbor in
                neighbor.0 == tileX && neighbor.1 == tileY
            })
            if isAdjacent,
               let char = GameState.shared.playerTeam.first(where: { $0.id == charId && $0.isAlive }) {
                CombatFlowController.checkDataTerminalPickup(gameState: GameState.shared, atX: tileX, y: tileY, by: char)
                return
            }
        }

        let reachable = bfsReachable(fromX: sprite.tileX, fromY: sprite.tileY, maxSteps: movementRange)
        let isInRange = reachable.contains(where: { $0.x == tileX && $0.y == tileY })

        if isInRange {
            guard let char = GameState.shared.playerTeam.first(where: { $0.id == charId && $0.isAlive }),
                  !char.hasActedThisRound,
                  GameState.shared.characterHasMovedThisTurn[charId] != true else {
                GameState.shared.addLog("This character has already used their turn.")
                return
            }
            guard isWalkableTile(tileX, tileY) else {
                GameState.shared.addLog("Cannot move to wall tile (\(tileX),\(tileY))")
                return
            }
            // Movement consumes the character's player turn. A turn is move OR action.
            animateCharacterMove(characterId: charId, toTileX: tileX, toTileY: tileY)
            GameState.shared.moveCharacter(id: charId, toTileX: tileX, toTileY: tileY)
            sprite.tileX = tileX
            sprite.tileY = tileY
            sprite.zPosition = playerDepthZ(forSprite: sprite)

            if isDoorTile(tileX, tileY) {
                openDoor(tileX: tileX, tileY: tileY)
            }
            clearHighlights()
        } else {
            // SILENT no-op: tap was on a far empty tile (not an enemy, not
            // a player, not a door, not the extraction). The user reported
            // the previous "Out of range (max 2 steps)" message firing
            // during ranged attacks — even though SHT/SPELL never go through
            // this branch. The message was misleading and added noise. Now
            // we just drop the tap silently. Distance attacks happen via
            // the SHT/SPELL buttons + an enemy target, not via tile taps.
            return
        }
    }

    /// Auto-open a door tile when the player steps adjacent to it.
    /// Changes the door tile to a floor tile so it becomes walkable.
    private func openDoor(tileX: Int, tileY: Int) {
        guard isDoorTile(tileX, tileY) else { return }
        let key = "\(tileX),\(tileY)"
        openedDoorKeys.insert(key)  // mark as opened so we don't re-trigger

        // Update the tile visual in the scene — replace door appearance with hex floor.
        if let tileNode = childNode(withName: "tile_\(tileX)_\(tileY)") {
            tileNode.removeAllChildren()
            let isEven = (tileX + tileY) % 2 == 0
            let R = TileMap.hexRadius

            // Base hex fill matching floor style
            let base = SKShapeNode(path: TileMap.hexPath(radius: R))
            base.fillColor = isEven
                ? UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1.0)
                : UIColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 1.0)
            base.strokeColor = .clear
            base.zPosition = 0
            tileNode.addChild(base)

            // Neon cyan hex border — open doorway glows slightly brighter
            let border = SKShapeNode(path: TileMap.hexPath(radius: R))
            border.fillColor = .clear
            border.strokeColor = UIColor(hex: "#00E4FF").withAlphaComponent(0.75)
            border.lineWidth = 1.5
            border.zPosition = 1
            tileNode.addChild(border)

            // Brief flash to signal the door opened
            border.run(SKAction.sequence([
                SKAction.fadeAlpha(to: 1.0, duration: 0.1),
                SKAction.fadeAlpha(to: 0.75, duration: 0.4)
            ]))
        }

        GameState.shared.addLog("Door opened at (\(tileX),\(tileY))")
        HapticsManager.shared.buttonTap()
    }

    private func handleDoorTileTap(tileX: Int, tileY: Int) {
        // Only trigger if a player character is selected and either adjacent to or standing on the door
        guard let sprite = selectedCharacterNode as? SpriteNode else {
            GameState.shared.addLog("Select a character, then step onto the door.")
            return
        }
        let standingOnDoor = sprite.tileX == tileX && sprite.tileY == tileY
        guard standingOnDoor else {
            guard RoomManager.shared.isRoomCleared(currentRoomId) else {
                GameState.shared.addLog("Door locked: clear this room first.")
                return
            }

            let reachable = bfsReachable(fromX: sprite.tileX, fromY: sprite.tileY, maxSteps: movementRange)
            guard reachable.contains(where: { $0.x == tileX && $0.y == tileY }) else {
                GameState.shared.addLog("Move closer to the door first.")
                return
            }
            guard let charEntry = characterNodes.first(where: { $0.value === sprite }) else { return }
            animateCharacterMove(characterId: charEntry.key, toTileX: tileX, toTileY: tileY)
            GameState.shared.moveCharacter(id: charEntry.key, toTileX: tileX, toTileY: tileY)
            sprite.tileX = tileX
            sprite.tileY = tileY
            sprite.zPosition = playerDepthZ(forSprite: sprite)
            GameState.shared.addLog("Door ready. Tap it again to enter.")
            clearHighlights()
            return
        }

        // Mission-objective gate: if this mission REQUIRES data, the current
        // room contains a still-unhacked terminal, and the player hasn't
        // hacked one yet, fire a one-time warning before letting them leave.
        // A second tap on the door within `warnConfirmWindow` seconds bypasses
        // the warning (they've been told; if they still want to skip the
        // bonus, that's their call).
        if shouldBlockExitForUnhackedTerminal() {
            let now = Date()
            if let lastWarn = lastTerminalWarningAt,
               now.timeIntervalSince(lastWarn) <= warnConfirmWindow {
                // Second tap within the confirm window — let them pass.
                // Clear the warning timestamp so future doors re-prompt.
                lastTerminalWarningAt = nil
            } else {
                // First tap (or stale) — warn and block.
                lastTerminalWarningAt = now
                GameState.shared.postTransientWarning(
                    "JACK IN AND HACK THE TERMINAL FIRST")
                GameState.shared.addLog(
                    "⚠️  Unhacked terminal in this room. Tap door again to leave anyway.")
                HapticsManager.shared.error()
                return
            }
        }

        // Attempt room transition
        if let targetRoom = RoomManager.shared.attemptTransition(from: currentRoomId, atTileX: tileX, y: tileY) {
            // Update GameState position to the door tile — animateCharacterMove does NOT update
            // GameState, so we must update it here so loadRoom places character at spawn correctly.
            if let charEntry = characterNodes.first(where: { $0.value === sprite }) {
                let charId = charEntry.key
                // Track WHICH character triggered the door — only this one moves to the connection spawn.
                doorTransitionCharacterId = charId
                // Update position directly (don't call moveCharacter — that would trigger endTurn
                // which would immediately kick off an enemy phase during the room fade transition).
                // NOTE: hasActedThisRound is NOT set here — the character retains their action for
                // the new room. They keep their turn, allowing all players to cycle before enemies.
                if let char = GameState.shared.playerTeam.first(where: { $0.id == charId }) {
                    char.positionX = tileX
                    char.positionY = tileY
                }
            }
            GameState.shared.addLog("Entering: \(targetRoom.title)...")
            // Mark room as entered (before beginTransition so the flag is set for handleRoomTransitionCompleted)
            RoomManager.shared.markRoomEntered(targetRoom.id)
            // Begin fade transition — do NOT animate character move here; the sprite is removed
            // on room load anyway and characters are placed at the connection's target spawn.
            RoomManager.shared.beginTransition(to: targetRoom)
            NotificationCenter.default.post(name: .roomTransitionStarted, object: nil)
        } else {
            GameState.shared.addLog("Door is locked or leads nowhere.")
        }
    }

    // MARK: - Update Loop

    /// Safety timeout: if isPlayerInputBlocked stays true for >5 seconds without
    /// .enemyPhaseCompleted firing (e.g. DispatchGroup leak or silent crash in enemy AI),
    /// force-unblock and restore the player's turn so the game doesn't freeze permanently.
    override func update(_ currentTime: TimeInterval) {
        refreshTraceVisuals()
        if GameState.shared.isInputBlockedByPhase {
            if inputBlockedSince == nil {
                inputBlockedSince = currentTime
            } else if currentTime - inputBlockedSince! > 5.0 {
                dlog("[BattleScene] ⚠️ Safety timeout: isPlayerInputBlocked stuck for >5s — force-unblocking")
                playerInputLocked = false
                isEnemyPhaseRunning = false
                // Safety fallback still routes authority through combat flow owner.
                CombatFlowController.restorePlayerControlAfterEnemyPhase(gameState: GameState.shared)
                inputBlockedSince = nil
            }
        } else {
            inputBlockedSince = nil
        }
    }

    // MARK: - Enemy Phase

    /// Runs the enemy phase: calls into GameState to process all enemy AI moves,
    /// then unlocks player input when complete.
    private func runEnemyPhase() {
        dlog("[BattleScene] enemyPhase started")
        guard playerInputLocked else {
            dlog("[BattleScene] runEnemyPhase called but input is not locked — ignoring")
            return
        }
        // Bug 3 fix: skip enemy phase if no enemies are alive
        if GameState.shared.enemies.filter({ $0.isAlive }).isEmpty {
            dlog("Forge: enemy doing turn — no enemies alive, skipping")
            // Bug 3 fix: call onRoomCleared so the door marker refreshes to DOOR
            GameState.shared.onRoomCleared()
            NotificationCenter.default.post(name: .enemyPhaseCompleted, object: nil)
            return
        }
        dlog("Forge: enemy doing turn")
        isEnemyPhaseRunning = true

        // Trigger GameState's enemy phase — this runs all enemy AI and will call
        // back via notifications (enemyMoved, enemyDied, etc.) as each enemy acts.
        // When it completes it posts .enemyPhaseCompleted to unblock player input.
        GameState.shared.enemyPhase()
    }

    // MARK: - Enemy Attack Visual

    /// Play a clear enemy attack animation: slash line from enemy to player, player flash.
    /// Called when the .playerHit notification is received (during enemy phase).
    func playEnemyAttackEffect(enemyId: UUID, playerId: UUID, damage: Int) {
        showEnemyAttackSlash(fromEnemy: enemyId, toPlayer: playerId)
        playPlayerHitEffect(on: playerId, damage: damage, enemyIdStr: enemyId.uuidString)
    }

    // MARK: - Enemy Phase Tint

    /// Subtle red overlay that tints the scene during enemy phase — provides clear
    /// visual feedback that it's not the player's turn.
    private var enemyPhaseTint: SKShapeNode?


    private func fadeInEnemyPhaseTint() {
        let tint = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        tint.fillColor = UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 0.12)
        tint.strokeColor = .clear
        tint.position = .zero
        tint.zPosition = 80
        tint.alpha = 0
        tint.name = "enemyPhaseTint"
        addChild(tint)
        enemyPhaseTint = tint
        tint.run(SKAction.fadeAlpha(to: 1.0, duration: 0.25))
    }

    private func fadeOutEnemyPhaseTint() {
        guard let tint = enemyPhaseTint else { return }
        tint.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.0, duration: 0.3),
            SKAction.removeFromParent()
        ]))
        enemyPhaseTint = nil
    }

    // MARK: - Animations

    func playHitEffect(on id: UUID, damage: Int = 0) {
        guard let node = characterNodes[id] else { return }
        SpriteManager.shared.animateHit(target: node)
        // Emit spark particles at hit location
        EffectsManager.shared.emitSparks(at: node.position, in: self, count: 14)
        // Show floating damage number
        if damage > 0 {
            EffectsManager.shared.showDamageNumber(damage, at: node.position, in: self)
        }
        // Screen shake for enemy hits
        EffectsManager.shared.screenShake(on: self, intensity: 5, duration: 0.2)
        // Update HP label if it's an enemy. `SpriteManager.updateHP` is the
        // single source of truth — it reads the UUID off the SpriteNode and
        // looks up `"hpBarFill_<uuid>"` / `"hpLabel_<uuid>"` directly. The
        // supplementary visual-rebuild block that used to live here was
        // never executing (it looked for the suffixed name before the
        // suffix was applied at creation) and was removed 2026-05-19.
        if let sprite = node as? SpriteNode,
           let enemyId = UUID(uuidString: sprite.enemyId),
           let enemy = GameState.shared.enemies.first(where: { $0.id == enemyId }) {
            SpriteManager.shared.updateHP(on: node, currentHP: enemy.currentHP, maxHP: enemy.maxHP, currentStun: enemy.currentStun, maxStun: enemy.maxStun)
        }
    }

    func playPlayerHitEffect(on id: UUID, damage: Int, enemyIdStr: String? = nil) {
        guard let node = characterNodes[id] else { return }

        // Show attack indicator: slash line from enemy to player
        if let eIdStr = enemyIdStr, let enemyId = UUID(uuidString: eIdStr),
           let enemyNode = characterNodes[enemyId] {
            showAttackSlash(from: enemyNode.position, to: node.position)
        }

        SpriteManager.shared.animateHit(target: node)
        // Show orange floating damage text. Spawn 32pt above the unit so
        // it pops off their head, mirroring showDamageNumber's offset.
        if damage > 0 {
            let spawnAt = CGPoint(x: node.position.x, y: node.position.y + 32)
            EffectsManager.shared.showCombatText("-\(damage)", at: spawnAt, in: self,
                                                 color: UIColor(hex: "#FF8800"), fontSize: 24)
        }
        // Red flash for player hits
        let flash = SKAction.run {
            for child in node.children {
                if let shape = child as? SKShapeNode {
                    let orig = shape.fillColor
                    shape.fillColor = UIColor.red.withAlphaComponent(0.6)
                    let restore = SKAction.run { shape.fillColor = orig }
                    shape.run(SKAction.sequence([
                        SKAction.wait(forDuration: 0.1),
                        restore
                    ]))
                }
            }
        }
        node.run(flash)
        EffectsManager.shared.screenShake(on: self, intensity: 8, duration: 0.25)
        // Update player HP bar
        if let sprite = node as? SpriteNode,
           !sprite.characterId.isEmpty,
           let charId = UUID(uuidString: sprite.characterId),
           let char = GameState.shared.playerTeam.first(where: { $0.id == charId }) {
            SpriteManager.shared.updateHP(on: node, currentHP: char.currentHP, maxHP: char.maxHP, currentStun: char.currentStun, maxStun: char.maxStun, level: char.level, isPlayer: true)
        }
    }

    /// Play a shield pulse effect on a defending character.
    func playDefendEffect(on id: UUID) {
        guard let node = characterNodes[id] else { return }
        // Brief blue/cyan ring expand
        let ring = SKShapeNode(circleOfRadius: 22)
        ring.strokeColor = UIColor(hex: "#4488FF")
        ring.lineWidth = 3
        ring.fillColor = UIColor(hex: "#4488FF").withAlphaComponent(0.1)
        ring.name = "shieldRing"
        ring.zPosition = 12
        ring.alpha = 0
        node.addChild(ring)

        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        let expand = SKAction.scale(to: 1.5, duration: 0.4)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        ring.run(SKAction.sequence([fadeIn, SKAction.group([expand, fadeOut]), remove]))
        HapticsManager.shared.selectionChanged()
    }

    func playLevelUpEffect(on id: UUID) {
        guard let node = characterNodes[id] else { return }
        EffectsManager.shared.emitLevelUp(at: node.position, in: self)
        // Golden flash on the sprite
        let flash = SKAction.run {
            for child in node.children {
                if let shape = child as? SKShapeNode {
                    let orig = shape.fillColor
                    let gold = UIColor(hex: "#FFD700")
                    shape.run(SKAction.sequence([
                        SKAction.run { shape.fillColor = gold },
                        SKAction.wait(forDuration: 0.15),
                        SKAction.run { shape.fillColor = orig }
                    ]))
                }
            }
        }
        node.run(flash)
    }

    func playDeathEffect(on id: UUID) {
        guard let node = characterNodes[id] else { return }
        let pos = node.position
        EffectsManager.shared.emitBlood(at: pos, in: self, count: 12)
        EffectsManager.shared.emitCyberGlitch(at: pos, in: self)
        EffectsManager.shared.screenShake(on: self, intensity: 10, duration: 0.3)
        removeCharacter(id: id)
    }

    private func animateEnemyMove(id: UUID, toX: Int, toY: Int) {
        guard let node = characterNodes[id] else {
            dlog("[BattleScene] animateEnemyMove: no node found for id=\(id)")
            return
        }

        // Emit brief smoke/ember trail at old position before moving
        let oldPos = node.position
        let trail = SKEmitterNode()
        trail.particleBirthRate = 0
        trail.numParticlesToEmit = 6
        trail.particleLifetime = 0.4
        trail.particleLifetimeRange = 0.1
        trail.particleSpeed = 15
        trail.particleSpeedRange = 10
        trail.emissionAngleRange = .pi * 2
        trail.particleAlpha = 0.6
        trail.particleAlphaSpeed = -1.5
        trail.particleScale = 0.8
        trail.particleScaleSpeed = -1.5
        trail.particleColor = UIColor(hex: "#FF4400")
        trail.particleColorBlendFactor = 1.0
        trail.position = oldPos
        trail.zPosition = 30
        addChild(trail)
        trail.run(SKAction.sequence([SKAction.wait(forDuration: 0.6), SKAction.removeFromParent()]))

        // Switch to walk animation BEFORE moving, return to idle on completion.
        // animateMove handles this for SpriteNode targets (which enemies always are).
        // The explicit call here ensures it fires even if animateMove's cast fails.
        if let sprite = node as? SpriteNode {
            SpriteManager.shared.animate(state: .walk, target: sprite)
        }
        SpriteManager.shared.animateMove(target: node, toTileX: toX, toTileY: toY, duration: 0.35, mapOrigin: mapOrigin)
        if let sprite = node as? SpriteNode {
            sprite.tileX = toX
            sprite.tileY = toY
        }
    }

    private func focusCamera(on characterId: UUID) {
        if let node = characterNodes[characterId] as? SpriteNode {
            focusCamera(on: node.tileX, y: node.tileY)
            return
        }

        if let character = GameState.shared.playerTeam.first(where: { $0.id == characterId }) {
            focusCamera(on: character.positionX, y: character.positionY)
            return
        }

        if let enemy = GameState.shared.enemies.first(where: { $0.id == characterId }) {
            focusCamera(on: enemy.positionX, y: enemy.positionY)
            return
        }

        positionCameraOnMap()
    }

    /// Enemy attack: draw an orange slash line FROM enemy TO player.
    /// This is called synchronously from runEnemyAI via the .playerHit notification
    /// BEFORE animateEnemyMove runs, so the slash appears at the attack moment.
    private func showEnemyAttackSlash(fromEnemy enemyId: UUID, toPlayer playerId: UUID) {
        guard let enemyNode = characterNodes[enemyId],
              let playerNode = characterNodes[playerId] else { return }
        showAttackSlash(from: enemyNode.position, to: playerNode.position)
    }

    /// Draw a brief orange slash line from attacker position to target position
    /// to make enemy attacks visually obvious.
    private func showAttackSlash(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return }

        let angle = atan2(dy, dx)

        // Main slash line — wider for more impact
        let slash = SKShapeNode(rectOf: CGSize(width: length, height: 4))
        slash.fillColor = UIColor(hex: "#FF4400").withAlphaComponent(0.85)
        slash.strokeColor = .clear
        slash.position = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        slash.zRotation = angle
        slash.zPosition = 25  // above characters (z=10) and HP bars (z=21)
        slash.name = "attackSlash"
        slash.alpha = 0
        addChild(slash)

        // Glow halo — wider for more dramatic effect
        let glow = SKShapeNode(rectOf: CGSize(width: length, height: 12))
        glow.fillColor = UIColor(hex: "#FF6600").withAlphaComponent(0.3)
        glow.strokeColor = .clear
        glow.position = slash.position
        glow.zRotation = angle
        glow.zPosition = 24
        glow.name = "attackSlash"
        glow.alpha = 0
        addChild(glow)

        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.05)
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        let remove = SKAction.removeFromParent()
        let wait = SKAction.wait(forDuration: 0.05)

        slash.run(SKAction.sequence([fadeIn, fadeOut, remove]))
        glow.run(SKAction.sequence([wait, fadeIn, fadeOut, remove]))

        // Impact sparks at hit location
        EffectsManager.shared.emitSparks(at: end, in: self, count: 8)
    }

    private func playRoundStartEffect() {
        // Brief flash at top of screen to signal new round
        let flashBar = SKShapeNode(rectOf: CGSize(width: mapPixelWidth, height: 6))
        flashBar.fillColor = UIColor(hex: "#00FF88").withAlphaComponent(0.3)
        flashBar.strokeColor = .clear
        flashBar.position = CGPoint(
            x: mapOrigin.x + mapPixelWidth / 2,
            y: mapOrigin.y + mapPixelHeight - 10
        )
        flashBar.zPosition = 200
        flashBar.name = "roundFlash"
        addChild(flashBar)

        let fadeUp = SKAction.moveBy(x: 0, y: -30, duration: 0.4)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let remove = SKAction.removeFromParent()
        flashBar.run(SKAction.sequence([SKAction.group([fadeUp, fadeOut]), remove]))
    }

    /// Returns all tile positions reachable within `maxSteps` steps using BFS.
    /// Respects walls and occupied tiles (enemies block, players don't block for pathfinding).
    private func bfsReachable(fromX: Int, fromY: Int, maxSteps: Int) -> [(x: Int, y: Int)] {
        var visited: Set<String> = ["\(fromX),\(fromY)"]
        var frontier: [(x: Int, y: Int, steps: Int)] = [(fromX, fromY, 0)]
        var reachable: [(x: Int, y: Int)] = []
        let mapH = tileMap?.mapHeight ?? 14

        // Get enemy positions to block movement through them
        let enemyPositions = characterNodes.values.compactMap { node -> String? in
            guard let sprite = node as? SpriteNode, sprite.team == "enemy" else { return nil }
            return "\(sprite.tileX),\(sprite.tileY)"
        }

        while !frontier.isEmpty {
            let (cx, cy, steps) = frontier.removeFirst()
            if steps >= maxSteps { continue }

            for (nx, ny) in hexNeighbors(x: cx, y: cy) {
                guard nx >= 0, nx < TileMap.mapWidth, ny >= 0, ny < mapH else { continue }
                let key = "\(nx),\(ny)"
                guard !visited.contains(key) else { continue }
                // Allow door tiles in BFS so stepping onto connection triggers remains possible.
                let tile = tileMap?.tiles[ny][nx] ?? .floor
                guard isWalkableTile(nx, ny) || tile == .door || tile == .dataTerminal else { continue }
                // Enemies block movement
                guard !enemyPositions.contains(key) else { continue }
                visited.insert(key)
                reachable.append((nx, ny))
                frontier.append((nx, ny, steps + 1))
            }
        }
        return reachable
    }
}
