
import SpriteKit

/// Tile types for the 2D grid map
enum TileType: Int {
    case floor = 0
    case wall = 1
    case cover = 2
    case door = 3
    case extraction = 4
    case dataTerminal = 5
}

/// 2D tile grid renderer using SpriteKit.
/// Uses FLAT-TOP hexagons arranged in an odd-q (column-offset) grid, matching the
/// reference cyberpunk hex tile art which draws isometric flat-top hex faces
/// (flat top + bottom, pointy left + right, wide-and-short aspect ≈ 2:1).
final class TileMap {

    // MARK: - Constants

    /// Kept for legacy code that references it (touch radii, etc.). NOT used for grid spacing.
    static let tileSize: CGFloat = 72
    static let mapWidth: Int = 7
    /// Flat-top hex circumradius (vertex-to-vertex horizontal half).
    /// Hex width (vertex-to-vertex) = 2R; hex height (edge-to-edge) = R·√3·isoSquash.
    static let hexRadius: CGFloat = 36
    /// Isometric Y-squash — controls hex vertical compression.
    ///
    /// The tile art cells are 341×256 px with a FLAT-TOP hex face occupying roughly
    /// 282w × 141h px in the top portion of each cell. That gives a face aspect of
    /// ~2.0 (wide and short).
    ///
    /// For a flat-top hex the aspect = (2R) / (R·√3·isoSquash) = 2/(√3·isoSquash).
    /// Solving for isoSquash at W/H=2.0 → isoSquash = 2/(√3·2) = 1/√3 ≈ 0.577.
    ///
    /// isoSquash ≈ 0.577 makes the programmatic hex outline match the art's drawn
    /// hex face shape, so the grid outline, tile PNG, character footprint, and
    /// highlights all align pixel-for-pixel.
    static let isoSquash: CGFloat = 0.5774

    // ── Derived hex grid spacing (the ONLY values used for tile/character placement) ──────
    //
    //  Flat-top hex tessellation (odd-q offset — ODD COLUMNS shift DOWN vertically):
    //    • horizontal column-to-column: Δx = 1.5·R               (columns interlock)
    //    • vertical   row-to-row:       Δy = R·√3·iso            (flat edges shared)
    //    • odd cols shift down:         Δy/2 = R·√3·iso / 2
    //
    //  With R=36, isoSquash≈0.577:
    //    hexColSpacing = 54   px (1.5·R)
    //    hexRowSpacing ≈ 36   px (R·√3·iso = 36·1.732·0.577 = 35.99)
    //
    static let hexColSpacing: CGFloat = hexRadius * 1.5                     // 1.5R = 54
    static let hexRowSpacing: CGFloat = hexRadius * 1.7320508 * isoSquash   // R√3·iso ≈ 35.99

    // MARK: - Explosive Barrel Tiles (single source of truth)

    /// TRUE if a cover tile at (x, y) is an EXPLOSIVE BARREL stack rather than
    /// an inert crate. This is the ONE deterministic rule shared by rendering
    /// (createHexTile draws the toxic-barrel props on these tiles) and combat
    /// (GameState.detonateBarrelsNear checks it before blowing a cover tile up),
    /// so what the player SEES as barrels is exactly what detonates.
    ///
    /// History: the barrel art in addCoverProps used to be picked by a seed the
    /// renderer no longer feeds it (the cover-prop pass went dormant when cover
    /// art moved into the room background images) — there was NO live, stable
    /// "which cover tile is a barrel" choice at all. This coordinate hash makes
    /// the choice deterministic: same tile → same answer on every load, no
    /// stored state needed. Two large odd multipliers (the classic spatial-hash
    /// primes) keep neighbouring tiles from clumping into all-barrel rows.
    ///
    /// Rate: ~25% of cover tiles read as barrels (hash % 4 == 1 — matching the
    /// 1-in-4 share the old addCoverProps variant table gave the barrel look).
    ///
    /// NOTE: callers must ALSO confirm the tile is currently cover (== 2) in
    /// the LIVE map — a barrel that already detonated is floor and this
    /// position-only helper will still return true for its coordinates.
    static func isBarrelTile(x: Int, y: Int) -> Bool {
        let h = (x &* 73_856_093) ^ (y &* 19_349_663)
        return abs(h) % 4 == 1
    }

    // MARK: - Coordinate Helpers (single source of truth)

    /// Local position of a tile's center within the TileMap container node.
    /// Flat-top hex odd-q layout: adjacent column centers are hexColSpacing apart,
    /// adjacent row centers are hexRowSpacing apart, odd columns shift DOWN by hexRowSpacing/2.
    /// ALL tile placement, character placement, and touch detection must call this.
    static func tileCenter(x: Int, y: Int) -> CGPoint {
        let colOffset: CGFloat = (x % 2 == 1) ? hexRowSpacing / 2.0 : 0
        return CGPoint(
            x: CGFloat(x) * hexColSpacing + hexRadius,
            y: CGFloat(y) * hexRowSpacing + hexRowSpacing / 2.0 + colOffset
        )
    }

    /// Per-instance map height derived from the tiles array passed at init.
    let mapHeight: Int

    // MARK: - Properties

    let tiles: [[TileType]]
    let size: CGSize

    private var tileNodes: [[SKNode?]]

    /// Floor texture file chosen once per room (contiguous look). Picked in init()
    /// from a small curated list using the tile grid's content as a deterministic
    /// hash so the SAME room always gets the SAME floor, and different rooms pick
    /// different floors — giving each area visual identity without random noise.
    private let floorTextureFile: String

    // MARK: - Init

    init(tiles: [[TileType]]) {
        self.tiles = tiles
        self.mapHeight = tiles.count
        // Map bounding box for flat-top odd-q hex layout:
        //   width  = cols · colSpacing + hexRadius/2  (right-side pointy vertex extends 0.5R)
        //   height = (rows + 0.5) · rowSpacing        (odd cols shift half a row down)
        self.size = CGSize(
            width:  CGFloat(TileMap.mapWidth) * TileMap.hexColSpacing + TileMap.hexRadius * 0.5,
            height: (CGFloat(self.mapHeight) + 0.5) * TileMap.hexRowSpacing
        )
        self.tileNodes = Array(repeating: Array(repeating: nil, count: TileMap.mapWidth), count: self.mapHeight)

        // Pick one floor variant for the entire room (contiguous, cohesive look).
        // Hash = row-count × col-count × checksum-of-tile-types. Deterministic: the
        // same tile grid always produces the same hash, so a given room uses the
        // same floor variant on every load.
        let floorVariants = [
            "tilesheet_3_r1c2.png",   // teal grid (cyberpunk industrial)
            "tilesheet_3_r4c2.png",   // cobblestone (alley / street)
            "tilesheet_1_r5c1.png",   // dark stone (clean cyberpunk floor)
        ]
        var checksum: Int = tiles.count &* 31 &+ (tiles.first?.count ?? 0)
        for row in tiles {
            for t in row { checksum = (checksum &* 33) &+ t.rawValue }
        }
        let idx = abs(checksum) % floorVariants.count
        self.floorTextureFile = floorVariants[idx]
    }

    convenience init(width: Int, height: Int, defaultTile: TileType = .floor) {
        let tiles = Array(repeating: Array(repeating: defaultTile, count: width), count: height)
        self.init(tiles: tiles)
    }

    // MARK: - Hex Geometry

    /// Build a FLAT-TOP hexagon CGPath centered at (0,0) with the given circumradius.
    /// Flat-top: vertex at right (0°) and left (180°), flat edges on top and bottom.
    /// This matches the reference cyberpunk hex tile art which draws isometric
    /// flat-top hex faces (wide-and-short, aspect ≈ 2:1 with isoSquash ≈ 0.577).
    static func hexPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            // Flat-top: first vertex at 0°, stepping 60° each time.
            // Vertices land at: 0° (right), 60° (upper-right), 120° (upper-left),
            //                   180° (left), 240° (lower-left), 300° (lower-right).
            let angle = CGFloat(i) * CGFloat.pi / 3.0
            let px = radius * cos(angle)
            // Y squashed by isoSquash for the isometric perspective look
            let py = radius * sin(angle) * TileMap.isoSquash
            if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
            else       { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Rendering

    /// Build and return a container node with all tile sprites.
    func buildNode() -> SKNode {
        let container = SKNode()
        container.name = "TileMap"

        for y in 0..<self.mapHeight {
            for x in 0..<TileMap.mapWidth {
                let tileType = tiles[y][x]
                let node = createHexTile(type: tileType, x: x, y: y)
                container.addChild(node)
                tileNodes[y][x] = node
            }
        }

        return container
    }

    // MARK: - Sprite-Sheet Tile Loading
    //
    // Place the tile sprite sheets in Sprites/tiles/ with these exact names:
    //   tilesheet_1.png  (first image — fire/bar/shop/door/mech tiles, 3×6 grid, 1024×1536px)
    //   tilesheet_2.png  (second image — crates/terminal/barrels/helipad tiles, 3×6 grid, 1024×1536px)
    //   tilesheet_3.png  (third image — stone/grate/circuit/hazard tiles, 3×6 grid, 1024×1536px)
    //
    // Grid positions used per tile type (sheet, col, row) — all verified:
    //   floor variants  : (3, 2, 1) teal grid  |  (3, 2, 4) cobblestone  |  (3, 0, 1) server cables
    //   cover variants  : (2, 0, 1) crate stack ✓  |  (2, 1, 2) toxic barrels ✓  |  (3, 1, 1) hazard stripes ✓
    //   door            : (1, 1, 3) orange sliding door ✓
    //   extraction      : (2, 1, 4) helipad H2 marking ✓
    //   wall            : fully procedural (dark void — no sprite needed)

    /// Load a tile texture from a sprite sheet at the given grid position.
    /// sheetName: filename in Sprites/tiles/. cols/rows: grid dimensions. col/row: 0-indexed position.
    private func loadTileFromSheet(sheetName: String, cols: Int, rows: Int, col: Int, row: Int) -> SKTexture? {
        guard let sheet = SpriteManager.shared.loadTileTexture(named: sheetName) else { return nil }
        let fw = 1.0 / CGFloat(cols)
        let fh = 1.0 / CGFloat(rows)
        // SpriteKit texture coords: (0,0) = bottom-left, y flipped from image top-down
        let skY = 1.0 - CGFloat(row + 1) * fh
        let rect = CGRect(x: CGFloat(col) * fw, y: skY, width: fw, height: fh)
        let cropped = SKTexture(rect: rect, in: sheet)
        cropped.filteringMode = .linear
        return cropped
    }

    /// Build a hex-clipped tile from art texture.
    ///
    /// Strategy: scale the sprite UNIFORMLY (preserving art aspect — no stretching)
    /// so the PNG's drawn flat-top hex face covers our programmatic hex in BOTH axes,
    /// then hex-mask to crop the overflow. This ensures the texture's visible hex edges
    /// line up precisely with our hex grid, with no dark border gaps and no stretched art.
    ///
    /// Measurements from reference PNGs (341×256 flat-top hex faces):
    ///   NEW ART (2026-05 sheet refresh): hex face is larger but its bottom 1/6
    ///   is occupied by a bright V-shaped neon "platform side" glow that breaks
    ///   floor continuity (every tile reads as a separate floating platform).
    ///   We deliberately measure the FLOOR-PATTERN region only, excluding the
    ///   bottom neon glow, so when the sprite is scaled and hex-masked the
    ///   neon falls *outside* the hex shape and gets clipped.
    ///   • Floor region (excluding bottom neon): x≈30–310 (width 280), y≈10–160 (height 150)
    ///   • Face width occupies 280/341 ≈ 0.821 of PNG width
    ///   • Face height occupies 150/256 ≈ 0.586 of PNG height
    ///   • Face center: (≈170, ≈85) in PNG pixel coords
    ///   • PNG midpoint: (170.5, 128) — face center is ~0 px horizontal offset
    ///     and ~43 px ABOVE vertical midpoint (43/256 ≈ 0.168)
    ///   • Below y=160: neon under-glow + 3-D platform side, then bleed-in
    ///     of the next-row hex. The hex mask crops all of that away.
    ///
    /// Uniform scale is chosen so:
    ///   spriteW · faceFracW ≥ hexW   AND   spriteH · faceFracH ≥ hexH
    /// Taking the max satisfies both. Because the art aspect matches our hex aspect,
    /// the two constraints agree closely and uniform scaling produces a pixel-snug fit.
    private func buildSpriteTileNode(texture: SKTexture, R: CGFloat) -> SKNode? {
        // Flat-top hex geometry (MUST match TileMap.hexPath extents):
        //   W = vertex-to-vertex horizontal = 2R
        //   H = edge-to-edge vertical       = R·√3·isoSquash
        let hexW = R * 2.0                                           // 72 @ R=36
        let hexH = R * 1.7320508 * TileMap.isoSquash                 // 35.99 @ R=36, iso=0.577

        // Face coverage fractions — measured from the 2026-05 tile-sheet art,
        // EXCLUDING the bottom neon-platform-side glow so adjacent tiles read as
        // a continuous floor instead of separate floating hex platforms.
        let faceFracW: CGFloat = 0.821
        let faceFracH: CGFloat = 0.586
        // Native PNG aspect (tile sheets cells are 341×256).
        let imgAspect: CGFloat = 341.0 / 256.0                       // ≈1.333

        // Required spriteW so face width = hexW:            spriteW = hexW / faceFracW
        // Required spriteH so face height = hexH:           spriteH = hexH / faceFracH
        // With uniform scaling (spriteW = spriteH · imgAspect), take max so both satisfied.
        let spriteH_fromWidth  = (hexW / faceFracW) / imgAspect
        let spriteH_fromHeight = hexH / faceFracH
        let spriteH: CGFloat = max(spriteH_fromWidth, spriteH_fromHeight) * 1.02  // +2% safety bleed
        let spriteW: CGFloat = spriteH * imgAspect

        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: spriteW, height: spriteH)
        // Floor-region center is 43/256 ≈ 0.168 of the PNG height ABOVE the vertical
        // midpoint (image y down → SK y up; ABOVE midpoint in SK = +y). Shift sprite
        // DOWN (negative y) so the floor region lands at hex center (0,0). Horizontal
        // offset is ~0 — face is centered horizontally.
        let faceOffsetY: CGFloat = spriteH * 0.168
        let faceOffsetX: CGFloat = 0
        sprite.position = CGPoint(x: faceOffsetX, y: -faceOffsetY)
        sprite.zPosition = 0

        // Hex-shape mask — crops the oversized sprite down to the exact hex outline,
        // giving clean edges that match the programmatic hex border 1:1.
        let mask = SKShapeNode(path: TileMap.hexPath(radius: R))
        mask.fillColor = .white
        mask.strokeColor = .clear

        let crop = SKCropNode()
        crop.maskNode = mask
        crop.addChild(sprite)
        return crop
    }

    // MARK: - Hex Tile Factory

    private func createHexTile(type: TileType, x: Int, y: Int) -> SKNode {
        let tileNode = SKNode()
        let R = TileMap.hexRadius
        let hPath = TileMap.hexPath(radius: R)

        switch type {

        // ─────────────────────────────────────────── WALL (transparent, background paints it)
        case .wall:
            // Walls are transparent: the room background image is expected to
            // paint the actual wall structure (fence, concrete, machinery). The
            // engine still treats this tile as impassable for pathfinding. We
            // add a very faint dark tint just so the player can tell it from
            // floor when no background image is loaded.
            //
            // If no background loads at runtime, the board backplate (zPos -40)
            // shows through and the wall reads as a dark hex (acceptable fallback).
            let tint = SKShapeNode(path: hPath)
            tint.fillColor = UIColor.black.withAlphaComponent(0.18)
            tint.strokeColor = .clear
            tint.zPosition = 0
            tileNode.addChild(tint)

        // ─────────────────────────────────────────── FLOOR
        case .floor:
            // Floor tiles are fully transparent so the per-room background image
            // (drawn one layer below) reads through. The hex grid is implied by
            // adjacent non-floor tiles (walls, cover) and by the room background
            // art itself. Skip drawing anything here.
            //
            // If no background image is loaded, the dark board backplate at
            // zPosition -40 still provides a black floor — playable but plain.
            break

        // ─────────────────────────────────────────── COVER (transparent — props in BG)
        case .cover:
            // Cover props (crates, dumpsters, AC units) are painted into the
            // room background image. The previous version laid a heavy amber
            // fill + diagonal hatch + 6 corner pips on top, which read as
            // "weird brown hex tiles" against the BG art. Now we just draw a
            // very faint hex outline so the player can still confirm "this
            // hex is cover" by glancing — no fill, no hatch, no pips.
            //
            // EXPLOSIVE BARRELS are the exception: those cover tiles are a
            // combat mechanic (Fireball / grenade blasts detonate them for
            // 6P AoE — see GameState.detonateBarrelsNear), so the player MUST
            // be able to tell them apart from inert cover at a glance.
            // IMPORTANT: this tile's actual prop art (crate/barrel/AC unit)
            // is painted into the room BACKGROUND image — an earlier version
            // drew procedural barrel props over it, double-exposing two art
            // styles on one hex, which read as a glitch. So the explosive
            // marker is a BADGE, not art: a pulsing toxic-green outline plus
            // a small tinted ☣ glyph floated near the top of the hex.
            // TileMap.isBarrelTile is the shared deterministic rule, so the
            // badged tiles are exactly the ones combat will detonate.
            let isBarrel = TileMap.isBarrelTile(x: x, y: y)
            let outline = SKShapeNode(path: hPath)
            outline.fillColor = isBarrel
                ? UIColor(hex: "#AACC00").withAlphaComponent(0.06)
                : .clear
            outline.strokeColor = isBarrel
                ? UIColor(hex: "#AACC00").withAlphaComponent(0.6)
                : UIColor(hex: "#FF8800").withAlphaComponent(0.25)
            outline.lineWidth = isBarrel ? 1.4 : 1.0
            outline.zPosition = 1.0
            tileNode.addChild(outline)
            if isBarrel {
                // \u{FE0E} forces TEXT presentation so fontColor tints the
                // glyph (the emoji form ignores fontColor).
                let glyph = SKLabelNode(text: "☣\u{FE0E}")
                glyph.fontName = "Menlo-Bold"
                glyph.fontSize = 11
                glyph.fontColor = UIColor(hex: "#CCFF33")
                glyph.verticalAlignmentMode = .center
                glyph.horizontalAlignmentMode = .center
                // Toward the hex's top edge so it stays readable when a unit
                // stands on the tile (unit sprites anchor near center).
                glyph.position = CGPoint(x: 0, y: R * 0.42)
                glyph.zPosition = 1.2
                glyph.alpha = 0.9
                tileNode.addChild(glyph)
                outline.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.35, duration: 0.9),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.9)
                ])))
            }

        // ─────────────────────────────────────────── DOOR (transparent — door art is in BG)
        case .door:
            // Door is painted into the room background image. The tile itself is
            // transparent so the BG door art reads through. The "LOCKED" / "UNLOCKED"
            // label that appears over the door is owned by BattleScene's
            // addObjectiveMarker() and refreshed when the room is cleared.
            // We do still add a faint pulse + thin border so the player can see
            // *where* the interactive tile is even before they tap it.
            let doorPulse = SKShapeNode(path: TileMap.hexPath(radius: R))
            doorPulse.fillColor = UIColor(hex: "#FF6600").withAlphaComponent(0.12)
            doorPulse.strokeColor = UIColor(hex: "#FF7A00")
            doorPulse.lineWidth = 3.2
            doorPulse.glowWidth = 3.0
            doorPulse.zPosition = 1.5
            doorPulse.name = "doorHexPulse"
            // Hidden while the door is LOCKED — BattleScene.addObjectiveMarkers
            // reveals it once the room is cleared (door unlocked). Keeps the
            // room clean during the fight.
            doorPulse.isHidden = true
            tileNode.addChild(doorPulse)
            doorPulse.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.45, duration: 0.6),
                SKAction.fadeAlpha(to: 1.0, duration: 0.6)
            ])))

        // ─────────────────────────────────────────── EXTRACTION (transparent — H-pad in BG)
        case .extraction:
            // Helipad art is painted into the room background. The "EXTRACTION"
            // pill label is drawn by BattleScene's addObjectiveMarker(). Keep
            // a subtle green pulse here so the player can spot the tile bounds.
            let exPulse = SKShapeNode(path: TileMap.hexPath(radius: R))
            exPulse.fillColor = .clear
            exPulse.strokeColor = UIColor(hex: "#00FF88").withAlphaComponent(0.45)
            exPulse.lineWidth = 1.6
            exPulse.zPosition = 1.5
            tileNode.addChild(exPulse)
            exPulse.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.15, duration: 0.7),
                SKAction.fadeAlpha(to: 0.55, duration: 0.7)
            ])))

        // ─────────────────────────────────────────── DATA TERMINAL
        case .dataTerminal:
            // Mission 003 (mage lair) ALSO renders a dedicated TERMINAL SPRITE
            // on the tile (purple ritual computer, 6 idle frames for flicker).
            // Every terminal — M3 sprite or not — gets the cyan hex pulse so
            // the tutorial's "look for the cyan tile" holds universally and
            // terminals read consistently across all missions.
            let mid = MainActor.assumeIsolated({ RoomManager.shared.currentMission?.id })
            if mid == "run003_multi" {
                addTerminalSprite(to: tileNode, R: R)
            }
            let dtPulse = SKShapeNode(path: TileMap.hexPath(radius: R))
            dtPulse.fillColor = .clear
            dtPulse.strokeColor = UIColor(hex: "#00FFCC").withAlphaComponent(0.55)
            dtPulse.lineWidth = 1.6
            dtPulse.zPosition = 1.5
            tileNode.addChild(dtPulse)
            dtPulse.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.15, duration: 0.7),
                SKAction.fadeAlpha(to: 0.65, duration: 0.7)
            ])))
        }

        tileNode.position = TileMap.tileCenter(x: x, y: y)
        tileNode.name = "tile_\(x)_\(y)"
        // DO NOT set tileNode.zPosition here. Tile child nodes (neon borders) have local
        // zPositions up to 2.3. If tileNode.zPosition were set to e.g. 9, the effective
        // render order = 0(mapNode) + 9(tile) + 2.3(border) = 11.3, which exceeds the
        // character zPosition of 10 and causes tile borders to clip character sprites.
        // In pointy-top odd-r layout adjacent rows interlock by ~33% vertically, but
        // tile children never draw above z=2.3 and character containers render at z=10+,
        // so no per-row z-ordering is needed.
        return tileNode
    }

    // MARK: - Thin Reference-Style Border

    /// Adds a thin crisp border with a very subtle glow — matches the reference dark stone look.
    /// Used for floor and cover tiles where we want clean hex definition without heavy neon.
    /// Mage-lair–themed terminal prop: low pentagram platform + floating
    /// crystal orb. Used only on Mission 003 because that background doesn't
    /// paint a terminal where the tile sits. Other missions keep the cleaner
    /// "BG painted, hex outline only" look.
    /// Render the M3 terminal sprite on the tile — replaces the old
    /// procedural pentagram prop. Loads up to 6 idle frames from
    /// Sprites/frames/data_terminal_*.png and cycles them as a slow flicker.
    /// Falls back to the procedural pentagram if the sprite files are
    /// missing (zero-impact safety net).
    private func addTerminalSprite(to tileNode: SKNode, R: CGFloat) {
        var frames: [SKTexture] = []
        if let resourceURL = Bundle.main.resourceURL {
            for i in 0..<6 {
                let url = resourceURL.appendingPathComponent("Sprites/frames/data_terminal_\(i).png")
                guard let img = UIImage(contentsOfFile: url.path) else { break }
                frames.append(SKTexture(image: img))
            }
        }
        guard let first = frames.first else {
            // Sprite assets missing — fall back to the legacy procedural prop.
            addMagicCircleTerminalProp(to: tileNode, R: R)
            return
        }
        let spr = SKSpriteNode(texture: first)
        // Scale to ~2.42× hex radius wide so the prop is unmistakable.
        // 2026-05-10: 1.55 → 1.86 (+20%) so the M3R1 terminal reads clearly
        // as a terminal at first glance — was getting confused with the floor
        // pattern. 2026-05-13: bumped 1.86 → 2.42 (+30%) per playtest, the
        // prop still wasn't reading large enough for a "go here" cue. Anchor
        // at the bottom so base sits on tile floor.
        let targetWidth: CGFloat = R * 2.42
        let scale = targetWidth / max(1, spr.size.width)
        spr.setScale(scale)
        spr.anchorPoint = CGPoint(x: 0.5, y: 0.15)
        spr.position = .zero
        spr.zPosition = 1.6   // above the floor + faint hex but below characters (z=10+)
        spr.name = "dataTerminalSprite"
        tileNode.addChild(spr)

        // Subtle flicker: cycle through frames over ~1.4s, looping. Multiple
        // frames look like a flame/screen flicker; 1 frame is a static prop.
        if frames.count >= 2 {
            let cycle = SKAction.animate(with: frames,
                                          timePerFrame: 0.22,
                                          resize: false, restore: false)
            spr.run(SKAction.repeatForever(cycle), withKey: "terminalFlicker")
        }
    }

    private func addMagicCircleTerminalProp(to tileNode: SKNode, R: CGFloat) {
        // Outer ritual ring — magenta/purple double circle.
        let outer = SKShapeNode(circleOfRadius: R * 0.78)
        outer.fillColor = .clear
        outer.strokeColor = UIColor(hex: "#FF44CC")
        outer.lineWidth = 2.0
        outer.glowWidth = 4.0
        outer.zPosition = 1.6
        tileNode.addChild(outer)
        outer.run(SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 6.0)))

        let inner = SKShapeNode(circleOfRadius: R * 0.55)
        inner.fillColor = .clear
        inner.strokeColor = UIColor(hex: "#AA00FF").withAlphaComponent(0.85)
        inner.lineWidth = 1.4
        inner.glowWidth = 2.5
        inner.zPosition = 1.7
        tileNode.addChild(inner)
        inner.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 4.5)))

        // Pentagram inside the inner circle.
        let starPath = UIBezierPath()
        let starR = R * 0.50
        let pts = 5
        for i in 0..<pts * 2 + 1 {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * (.pi * 2 / CGFloat(pts))
            let p = CGPoint(x: cos(angle) * starR, y: sin(angle) * starR)
            if i == 0 { starPath.move(to: p) } else { starPath.addLine(to: p) }
        }
        let star = SKShapeNode(path: starPath.cgPath)
        star.fillColor = .clear
        star.strokeColor = UIColor(hex: "#FF66FF").withAlphaComponent(0.9)
        star.lineWidth = 1.4
        star.glowWidth = 3.0
        star.zPosition = 1.8
        tileNode.addChild(star)
        star.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.9),
            SKAction.fadeAlpha(to: 1.0,  duration: 0.9)
        ])))

        // 6 rune marks at outer ring positions.
        let runeGlyphs = ["⛤", "✦", "⚝", "❉", "✧", "⛧"]
        for i in 0..<6 {
            let a = CGFloat(i) * (.pi * 2 / 6) - .pi / 2
            let r = R * 0.65
            let g = SKLabelNode(fontNamed: "AvenirNext-Bold")
            g.text = runeGlyphs[i]
            g.fontSize = 9
            g.fontColor = UIColor(hex: "#FF99FF")
            g.position = CGPoint(x: cos(a) * r, y: sin(a) * r - 2)
            g.zPosition = 1.9
            tileNode.addChild(g)
        }

        // Floating crystal orb hovering above the platform.
        let orbBase = SKShapeNode(circleOfRadius: 5)
        orbBase.fillColor = UIColor(hex: "#220044").withAlphaComponent(0.6)
        orbBase.strokeColor = UIColor(hex: "#FF44CC")
        orbBase.lineWidth = 1.0
        orbBase.glowWidth = 6.0
        orbBase.zPosition = 2.4
        orbBase.position = CGPoint(x: 0, y: R * 0.10)
        tileNode.addChild(orbBase)
        // Inner highlight.
        let orbHi = SKShapeNode(circleOfRadius: 2.5)
        orbHi.fillColor = UIColor(hex: "#FFCCFF")
        orbHi.strokeColor = .clear
        orbHi.glowWidth = 3.0
        orbHi.position = CGPoint(x: -1.5, y: 1.5)
        orbHi.zPosition = 0.1
        orbBase.addChild(orbHi)
        // Float + pulse.
        orbBase.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y:  3, duration: 1.0),
            SKAction.moveBy(x: 0, y: -3, duration: 1.0)
        ])))

        // Floating "RITUAL" label so it reads as the objective.
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "RITUAL"
        label.fontSize = 9
        label.fontColor = UIColor(hex: "#FF99FF")
        label.position = CGPoint(x: 0, y: R * 0.78)
        label.zPosition = 2.8
        tileNode.addChild(label)
        label.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.8),
            SKAction.fadeAlpha(to: 1.0,  duration: 0.8)
        ])))
    }

    private func addThinBorder(to node: SKNode, R: CGFloat, borderColor: UIColor) {
        // Very faint outer halo (barely visible — just softens the edge)
        let halo = SKShapeNode(path: TileMap.hexPath(radius: R + 2))
        halo.fillColor = .clear
        halo.strokeColor = borderColor.withAlphaComponent(0.18)
        halo.lineWidth = 5
        halo.zPosition = 1.0
        node.addChild(halo)

        // Crisp 1.3px border line
        let border = SKShapeNode(path: TileMap.hexPath(radius: R))
        border.fillColor = .clear
        border.strokeColor = borderColor
        border.lineWidth = 1.3
        border.zPosition = 1.2
        node.addChild(border)
    }

    // MARK: - Neon Border (for sprite-based tiles)

    /// Adds the neon border stack (wide glow + sharp line + crisp inner) on top of a sprite tile.
    /// Used when a PNG sprite fills the hex — we overlay the neon frame so it still reads
    /// as a proper cyberpunk tile rather than a flat image.
    private func addNeonBorder(to node: SKNode, R: CGFloat, borderColor: UIColor) {
        // Subtle depth side wall below — reduced offset (was -20, now -8) to keep tiles
        // grounded and prevent the "floating platform" look that caused sprites to appear misaligned.
        let sideWall = SKShapeNode(path: TileMap.hexPath(radius: R))
        sideWall.fillColor = UIColor(hex: "#010305")
        sideWall.strokeColor = borderColor.withAlphaComponent(0.22)
        sideWall.lineWidth = 1.0
        sideWall.position = CGPoint(x: 0, y: -8)
        sideWall.zPosition = -0.2
        node.addChild(sideWall)

        // Wide soft outer glow halo
        let glow = SKShapeNode(path: TileMap.hexPath(radius: R + 5))
        glow.fillColor = .clear
        glow.strokeColor = borderColor.withAlphaComponent(0.28)
        glow.lineWidth = 10
        glow.zPosition = 2.0
        node.addChild(glow)

        // Mid glow ring
        let midGlow = SKShapeNode(path: TileMap.hexPath(radius: R + 1))
        midGlow.fillColor = .clear
        midGlow.strokeColor = borderColor.withAlphaComponent(0.60)
        midGlow.lineWidth = 3.0
        midGlow.zPosition = 2.1
        node.addChild(midGlow)

        // Crisp bright neon border
        let border = SKShapeNode(path: TileMap.hexPath(radius: R))
        border.fillColor = .clear
        border.strokeColor = borderColor
        border.lineWidth = 1.8
        border.zPosition = 2.2
        node.addChild(border)

        // Ultra-bright inner highlight (white-hot edge)
        let highlight = SKShapeNode(path: TileMap.hexPath(radius: R))
        highlight.fillColor = .clear
        highlight.strokeColor = UIColor.white.withAlphaComponent(0.20)
        highlight.lineWidth = 0.6
        highlight.zPosition = 2.3
        node.addChild(highlight)
    }

    // MARK: - Platform Builder

    /// Builds the layered neon-platform look from the reference art:
    /// 3D side wall → dark depth face → top face fill → stone texture → glow stack → crisp border.
    private func buildPlatformTile(into node: SKNode, hPath: CGPath, R: CGFloat,
                                   fillColor: UIColor, borderColor: UIColor,
                                   seed: Int, addStoneTexture: Bool) {
        // ── 1. 3D platform side wall ───────────────────────────────────────────
        // Draw the hex shifted DOWN by 8px (reduced from 20) — subtle depth without
        // the "floating platform" look that made sprites appear misaligned.
        let sideWall = SKShapeNode(path: hPath)
        sideWall.fillColor = UIColor(hex: "#010305")
        sideWall.strokeColor = borderColor.withAlphaComponent(0.22)
        sideWall.lineWidth = 1.0
        sideWall.position = CGPoint(x: 0, y: -8)
        sideWall.zPosition = -0.2
        node.addChild(sideWall)

        // A thin colored "ledge" strip between wall and top — the visible side edge
        let ledge = SKShapeNode(path: hPath)
        ledge.fillColor = borderColor.withAlphaComponent(0.07)
        ledge.strokeColor = borderColor.withAlphaComponent(0.30)
        ledge.lineWidth = 1.2
        ledge.position = CGPoint(x: 0, y: -4)
        ledge.zPosition = -0.1
        node.addChild(ledge)

        // ── 2. Top face fill ──────────────────────────────────────────────────
        let face = SKShapeNode(path: hPath)
        face.fillColor = fillColor
        face.strokeColor = .clear
        face.zPosition = 0
        node.addChild(face)

        // ── 3. Stone / cracked pavement texture ──────────────────────────────
        if addStoneTexture {
            self.addStoneTexture(to: node, R: R, seed: seed)
        }

        // ── 4. Inner concentric hex (fine accent detail) ──────────────────────
        let inner = SKShapeNode(path: TileMap.hexPath(radius: R - 7))
        inner.fillColor = .clear
        inner.strokeColor = borderColor.withAlphaComponent(0.20)
        inner.lineWidth = 0.8
        inner.zPosition = 0.8
        node.addChild(inner)

        // ── 5. Wide soft outer glow halo ─────────────────────────────────────
        let glow = SKShapeNode(path: TileMap.hexPath(radius: R + 5))
        glow.fillColor = .clear
        glow.strokeColor = borderColor.withAlphaComponent(0.22)
        glow.lineWidth = 10
        glow.zPosition = 0.9
        node.addChild(glow)

        // ── 6. Mid glow ring (sharper, more saturated) ───────────────────────
        let midGlow = SKShapeNode(path: TileMap.hexPath(radius: R + 1))
        midGlow.fillColor = .clear
        midGlow.strokeColor = borderColor.withAlphaComponent(0.55)
        midGlow.lineWidth = 3.0
        midGlow.zPosition = 1.0
        node.addChild(midGlow)

        // ── 7. Crisp bright neon border (the signature cyberpunk edge) ────────
        let border = SKShapeNode(path: hPath)
        border.fillColor = .clear
        border.strokeColor = borderColor
        border.lineWidth = 1.8
        border.zPosition = 1.2
        node.addChild(border)

        // ── 8. Ultra-bright inner highlight (thin white-hot core line) ────────
        let highlight = SKShapeNode(path: hPath)
        highlight.fillColor = .clear
        highlight.strokeColor = UIColor.white.withAlphaComponent(0.18)
        highlight.lineWidth = 0.6
        highlight.zPosition = 1.3
        node.addChild(highlight)
    }

    // MARK: - Stone Texture

    private func addStoneTexture(to node: SKNode, R: CGFloat, seed: Int) {
        // ── Irregular cobblestone blocks ──────────────────────────────────────
        // Use larger, more varied blocks with stronger contrast to match reference art.
        let blockCount = 6 + abs(seed) % 4
        for i in 0..<blockCount {
            let bs = abs(seed ^ (i &* 2654435761))
            let bx = CGFloat(bs % 100) / 100.0 * R * 1.5 - R * 0.75
            let by = CGFloat((bs >> 8) % 100) / 100.0 * R * 1.1 - R * 0.55
            let bxClamped = max(-R * 0.72, min(R * 0.72, bx))
            let byClamped = max(-R * 0.55, min(R * 0.55, by))
            // Vary block size more: range 6-18px wide, 4-10px tall
            let bw = CGFloat((bs >> 16) % 12) / 12.0 * 12 + 6
            let bh = CGFloat((bs >> 20) % 8)  /  8.0 *  6 + 4
            let cornerR: CGFloat = (abs(seed ^ i) % 3 == 0) ? 1.5 : 0.5
            let block = SKShapeNode(rectOf: CGSize(width: bw, height: bh), cornerRadius: cornerR)
            // Vary fill slightly per block for organic feel — warm brown-gray stone tones
            let lightness: CGFloat = 0.06 + CGFloat((bs >> 4) % 6) / 6.0 * 0.06
            block.fillColor = UIColor(red: lightness * 1.2, green: lightness * 0.9, blue: lightness * 0.7, alpha: 0.65)
            block.strokeColor = UIColor(hex: "#100A06").withAlphaComponent(0.80)
            block.lineWidth = 0.7
            block.position = CGPoint(x: bxClamped, y: byClamped)
            block.zPosition = 0.3
            node.addChild(block)
        }

        // ── Crack lines (~50% of tiles) ────────────────────────────────────────
        if abs(seed) % 2 == 0 {
            let cs = abs(seed ^ 0xDEADBEEF)
            let crack = SKShapeNode()
            let cp = CGMutablePath()
            let sx = CGFloat(cs % 60) / 60.0 * R * 1.0 - R * 0.5
            let sy = CGFloat((cs >> 6) % 50) / 50.0 * R * 0.8 - R * 0.4
            cp.move(to: CGPoint(x: sx, y: sy))
            let mx = sx + CGFloat((cs >> 12) % 20) - 10
            let my = sy + CGFloat((cs >> 18) % 16) - 8
            cp.addLine(to: CGPoint(x: mx, y: my))
            let ex = mx + CGFloat((cs >> 24) % 16) - 8
            let ey = my + CGFloat((cs >> 28) % 12) - 6
            cp.addLine(to: CGPoint(x: ex, y: ey))
            crack.path = cp
            crack.strokeColor = UIColor(hex: "#080502").withAlphaComponent(0.90)
            crack.lineWidth = 0.9
            crack.zPosition = 0.5
            node.addChild(crack)
        }

        // ── Grime spots / moisture stains ─────────────────────────────────────
        let dotCount = 4 + abs(seed) % 3
        for i in 0..<dotCount {
            let ds = abs(seed ^ (i &* 1234567))
            let dx = CGFloat(ds % 80) / 80.0 * R * 1.1 - R * 0.55
            let dy = CGFloat((ds >> 10) % 70) / 70.0 * R * 0.9 - R * 0.45
            let dr = CGFloat((ds >> 20) % 8) / 8.0 * 2.5 + 1.0
            let dot = SKShapeNode(circleOfRadius: dr)
            dot.fillColor = UIColor(hex: "#080503").withAlphaComponent(0.60)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: dx, y: dy)
            dot.zPosition = 0.4
            node.addChild(dot)
        }
    }

    private func floorColor(seed: Int) -> UIColor {
        // Five variants for richer visual variety — dark cyberpunk industrial palette
        switch abs(seed) % 5 {
        case 0: return UIColor(red: 0.05, green: 0.09, blue: 0.18, alpha: 1.0)  // deep blue-slate
        case 1: return UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1.0)  // near-black blue
        case 2: return UIColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1.0)  // mid blue-grey
        case 3: return UIColor(red: 0.04, green: 0.08, blue: 0.12, alpha: 1.0)  // cold dark
        default: return UIColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1.0) // steel grey-blue
        }
    }

    // MARK: - Cover Props (industrial crates / barrels)

    private func addCoverProps(to node: SKNode, R: CGFloat, seed: Int) {
        let variant = abs(seed) % 4

        if variant == 0 {
            // ── Stacked cargo crates (isometric-style with visible depth) ──
            // Bottom crate — wider base
            let crate1 = crateNode(w: R * 1.0, h: R * 0.60, color: UIColor(hex: "#1A0D04"), borderColor: UIColor(hex: "#FF8800"))
            crate1.position = CGPoint(x: 0, y: -R * 0.12)
            crate1.zPosition = 2
            node.addChild(crate1)
            // Depth side of bottom crate
            let crateDepth1 = SKShapeNode(rectOf: CGSize(width: R * 1.0, height: 8), cornerRadius: 1)
            crateDepth1.fillColor = UIColor(hex: "#0A0602")
            crateDepth1.strokeColor = UIColor(hex: "#993300").withAlphaComponent(0.5)
            crateDepth1.lineWidth = 0.8
            crateDepth1.position = CGPoint(x: 0, y: -R * 0.12 - R * 0.30 - 4)
            crateDepth1.zPosition = 1.8
            node.addChild(crateDepth1)

            // Top crate — smaller, rotated slightly
            let crate2 = crateNode(w: R * 0.72, h: R * 0.48, color: UIColor(hex: "#221005"), borderColor: UIColor(hex: "#CC5500"))
            crate2.position = CGPoint(x: R * 0.08, y: R * 0.30)
            crate2.zRotation = 0.08
            crate2.zPosition = 3
            node.addChild(crate2)

            // Amber hazard light strip — blinks
            let strip = SKShapeNode(rectOf: CGSize(width: R * 0.65, height: 3.0), cornerRadius: 1.5)
            strip.fillColor = UIColor(hex: "#FF8800")
            strip.strokeColor = UIColor(hex: "#FFAA00")
            strip.lineWidth = 0.5
            strip.glowWidth = 4.0
            strip.position = CGPoint(x: 0, y: R * 0.58)
            strip.zPosition = 4
            strip.name = "amberStrip"
            node.addChild(strip)
            strip.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.2, duration: 0.6),
                SKAction.fadeAlpha(to: 1.0, duration: 0.2),
                SKAction.wait(forDuration: 0.4)
            ])))

        } else if variant == 1 {
            // ── Chemical barrels with 3D top face ──────────────────────────
            let barrelPositions: [(CGFloat, CGFloat)] = [(-R * 0.28, -R * 0.1), (R * 0.22, R * 0.08)]
            for (bx, by) in barrelPositions {
                // Barrel body (ellipse = top-down isometric view)
                let barrel = SKShapeNode(ellipseOf: CGSize(width: R * 0.50, height: R * 0.62))
                barrel.fillColor = UIColor(hex: "#081200")
                barrel.strokeColor = UIColor(hex: "#88BB00")
                barrel.lineWidth = 2.0
                barrel.position = CGPoint(x: bx, y: by)
                barrel.zPosition = 2
                node.addChild(barrel)
                // Barrel top cap (lighter)
                let barrelTop = SKShapeNode(ellipseOf: CGSize(width: R * 0.40, height: R * 0.22))
                barrelTop.fillColor = UIColor(hex: "#112200")
                barrelTop.strokeColor = UIColor(hex: "#AACC00").withAlphaComponent(0.7)
                barrelTop.lineWidth = 1.0
                barrelTop.position = CGPoint(x: bx, y: by + R * 0.22)
                barrelTop.zPosition = 3
                node.addChild(barrelTop)
                // Biohazard dots (3 at 120° intervals)
                for j in 0..<3 {
                    let bDot = SKShapeNode(circleOfRadius: 2.5)
                    bDot.fillColor = UIColor(hex: "#AACC00")
                    bDot.strokeColor = .clear
                    bDot.glowWidth = 2.0
                    let angle = CGFloat(j) * CGFloat.pi * 2 / 3 - CGFloat.pi / 6
                    bDot.position = CGPoint(x: bx + 8 * cos(angle), y: by + 8 * sin(angle))
                    bDot.zPosition = 3.5
                    node.addChild(bDot)
                }
                // Toxic glow pulse
                let toxicGlow = SKShapeNode(ellipseOf: CGSize(width: R * 0.60, height: R * 0.72))
                toxicGlow.fillColor = UIColor(hex: "#AACC00").withAlphaComponent(0.06)
                toxicGlow.strokeColor = .clear
                toxicGlow.position = CGPoint(x: bx, y: by)
                toxicGlow.zPosition = 1.5
                node.addChild(toxicGlow)
                toxicGlow.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.02, duration: 1.2),
                    SKAction.fadeAlpha(to: 1.0, duration: 1.2)
                ])))
            }

        } else if variant == 2 {
            // ── Server rack / data terminal ─────────────────────────────────
            // Main rack body
            let rack = SKShapeNode(rectOf: CGSize(width: R * 0.80, height: R * 1.0), cornerRadius: 3)
            rack.fillColor = UIColor(hex: "#060A18")
            rack.strokeColor = UIColor(hex: "#0055CC")
            rack.lineWidth = 1.8
            rack.position = CGPoint(x: 0, y: R * 0.02)
            rack.zPosition = 2
            node.addChild(rack)
            // Depth shadow
            let rackDepth = SKShapeNode(rectOf: CGSize(width: R * 0.80, height: 10), cornerRadius: 2)
            rackDepth.fillColor = UIColor(hex: "#020408")
            rackDepth.strokeColor = UIColor(hex: "#002266").withAlphaComponent(0.5)
            rackDepth.lineWidth = 0.8
            rackDepth.position = CGPoint(x: 0, y: R * 0.02 - R * 0.50 - 5)
            rackDepth.zPosition = 1.8
            node.addChild(rackDepth)
            // LED strips (status lights, each a different color)
            let ledColors = ["#00FF88", "#0088FF", "#FF8800"]
            for i in 0..<3 {
                let led = SKShapeNode(rectOf: CGSize(width: R * 0.62, height: 2.5), cornerRadius: 1)
                led.fillColor = UIColor(hex: ledColors[i])
                led.strokeColor = .clear
                led.glowWidth = 3.0
                led.position = CGPoint(x: 0, y: -R * 0.28 + CGFloat(i) * R * 0.28)
                led.zPosition = 3
                node.addChild(led)
            }
            // Blinking indicator dot
            let blink = SKShapeNode(circleOfRadius: 2.5)
            blink.fillColor = UIColor(hex: "#FF0044")
            blink.strokeColor = .clear
            blink.glowWidth = 3.0
            blink.position = CGPoint(x: R * 0.32, y: R * 0.38)
            blink.zPosition = 3
            node.addChild(blink)
            blink.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.35),
                SKAction.fadeIn(withDuration: 0.15),
                SKAction.wait(forDuration: 0.8)
            ])))

        } else {
            // ── Low concrete barrier / sandbag wall ─────────────────────────
            // Wide low barrier
            let barrier = SKShapeNode(rectOf: CGSize(width: R * 1.10, height: R * 0.42), cornerRadius: 3)
            barrier.fillColor = UIColor(hex: "#1A1814")
            barrier.strokeColor = UIColor(hex: "#FF8800")
            barrier.lineWidth = 1.5
            barrier.position = CGPoint(x: 0, y: R * 0.05)
            barrier.zPosition = 2
            node.addChild(barrier)
            // Depth face
            let barrierDepth = SKShapeNode(rectOf: CGSize(width: R * 1.10, height: 8), cornerRadius: 2)
            barrierDepth.fillColor = UIColor(hex: "#0C0A08")
            barrierDepth.strokeColor = UIColor(hex: "#663300").withAlphaComponent(0.6)
            barrierDepth.lineWidth = 0.8
            barrierDepth.position = CGPoint(x: 0, y: R * 0.05 - R * 0.21 - 4)
            barrierDepth.zPosition = 1.8
            node.addChild(barrierDepth)
            // Diagonal warning stripes
            for i in 0..<3 {
                let stripe = SKShapeNode(rectOf: CGSize(width: 5, height: R * 0.36), cornerRadius: 1)
                stripe.fillColor = UIColor(hex: "#FF8800").withAlphaComponent(0.5)
                stripe.strokeColor = .clear
                stripe.zRotation = 0.5
                stripe.position = CGPoint(x: CGFloat(i - 1) * R * 0.38, y: R * 0.05)
                stripe.zPosition = 2.5
                node.addChild(stripe)
            }
        }
    }

    private func crateNode(w: CGFloat, h: CGFloat, color: UIColor, borderColor: UIColor) -> SKShapeNode {
        let crate = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 2)
        crate.fillColor = color
        crate.strokeColor = borderColor
        crate.lineWidth = 1.5
        // X-brace
        let xNode = SKShapeNode()
        let xp = CGMutablePath()
        xp.move(to: CGPoint(x: -w * 0.4, y: -h * 0.4))
        xp.addLine(to: CGPoint(x: w * 0.4, y: h * 0.4))
        xp.move(to: CGPoint(x: w * 0.4, y: -h * 0.4))
        xp.addLine(to: CGPoint(x: -w * 0.4, y: h * 0.4))
        xNode.path = xp
        xNode.strokeColor = borderColor.withAlphaComponent(0.4)
        xNode.lineWidth = 1
        crate.addChild(xNode)
        return crate
    }

    // MARK: - Door Props

    private func addDoorProps(to node: SKNode, R: CGFloat) {
        // ── Outer door frame ────────────────────────────────────────────────
        let frame = SKShapeNode(rectOf: CGSize(width: R * 1.05, height: R * 1.20), cornerRadius: 3)
        frame.fillColor = UIColor(hex: "#120700")
        frame.strokeColor = UIColor(hex: "#FF6600")
        frame.lineWidth = 2.5
        frame.glowWidth = 5.0
        frame.position = CGPoint(x: 0, y: R * 0.02)
        frame.zPosition = 2
        node.addChild(frame)
        // Frame depth
        let frameDepth = SKShapeNode(rectOf: CGSize(width: R * 1.05, height: 10), cornerRadius: 2)
        frameDepth.fillColor = UIColor(hex: "#080400")
        frameDepth.strokeColor = UIColor(hex: "#993300").withAlphaComponent(0.5)
        frameDepth.lineWidth = 0.8
        frameDepth.position = CGPoint(x: 0, y: R * 0.02 - R * 0.60 - 5)
        frameDepth.zPosition = 1.8
        node.addChild(frameDepth)

        // ── Two sliding door panels ─────────────────────────────────────────
        for sign: CGFloat in [-1, 1] {
            let panel = SKShapeNode(rectOf: CGSize(width: R * 0.42, height: R * 1.04), cornerRadius: 1)
            panel.fillColor = UIColor(hex: "#1E0E00")
            panel.strokeColor = UIColor(hex: "#FF7700").withAlphaComponent(0.55)
            panel.lineWidth = 1.2
            panel.position = CGPoint(x: sign * R * 0.26, y: R * 0.02)
            panel.zPosition = 2.5
            node.addChild(panel)
            // Panel grooves (horizontal lines)
            for g in 0..<3 {
                let groove = SKShapeNode(rectOf: CGSize(width: R * 0.36, height: 1.2))
                groove.fillColor = UIColor(hex: "#FF6600").withAlphaComponent(0.25)
                groove.strokeColor = .clear
                groove.position = CGPoint(x: sign * R * 0.26, y: R * 0.02 - R * 0.25 + CGFloat(g) * R * 0.26)
                groove.zPosition = 3
                node.addChild(groove)
            }
        }

        // ── Glowing center seam ─────────────────────────────────────────────
        let seam = SKShapeNode(rectOf: CGSize(width: 3, height: R * 1.04))
        seam.fillColor = UIColor(hex: "#FF8800")
        seam.strokeColor = UIColor(hex: "#FFCC44")
        seam.lineWidth = 0.5
        seam.glowWidth = 8.0
        seam.position = CGPoint(x: 0, y: R * 0.02)
        seam.zPosition = 3.5
        seam.name = "doorSeam"
        node.addChild(seam)
        seam.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.2, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])))

        // ── Security keypad (right side) ────────────────────────────────────
        let keypad = SKShapeNode(rectOf: CGSize(width: 6, height: 9), cornerRadius: 1)
        keypad.fillColor = UIColor(hex: "#0A1A2A")
        keypad.strokeColor = UIColor(hex: "#0099FF")
        keypad.lineWidth = 1.0
        keypad.position = CGPoint(x: R * 0.52, y: R * 0.08)
        keypad.zPosition = 3
        node.addChild(keypad)
        let kpDot = SKShapeNode(circleOfRadius: 1.5)
        kpDot.fillColor = UIColor(hex: "#FF0000")
        kpDot.strokeColor = .clear
        kpDot.glowWidth = 3.0
        kpDot.position = CGPoint(x: R * 0.52, y: R * 0.16)
        kpDot.zPosition = 3.5
        node.addChild(kpDot)
        kpDot.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.fadeIn(withDuration: 0.2),
            SKAction.wait(forDuration: 1.2)
        ])))

        // ── Horizontal scan line sweeping across door ───────────────────────
        let scan = SKShapeNode(rectOf: CGSize(width: R * 0.90, height: 2))
        scan.fillColor = UIColor(hex: "#FF8800").withAlphaComponent(0.65)
        scan.strokeColor = .clear
        scan.glowWidth = 6.0
        scan.position = CGPoint(x: 0, y: -R * 0.52)
        scan.zPosition = 4.5
        node.addChild(scan)
        scan.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveTo(y: R * 0.54, duration: 1.8),
            SKAction.moveTo(y: -R * 0.52, duration: 0)
        ])))
    }

    // MARK: - Extraction Props

    private func addExtractionProps(to node: SKNode, R: CGFloat) {
        // ── Landing pad (outer concentric rings) ────────────────────────────
        // Outer ring
        let outerPad = SKShapeNode(circleOfRadius: R * 0.80)
        outerPad.fillColor = UIColor(hex: "#011208")
        outerPad.strokeColor = UIColor(hex: "#00FF88").withAlphaComponent(0.45)
        outerPad.lineWidth = 2.5
        outerPad.zPosition = 2
        node.addChild(outerPad)
        // Inner ring
        let innerPad = SKShapeNode(circleOfRadius: R * 0.52)
        innerPad.fillColor = UIColor(hex: "#021A0C")
        innerPad.strokeColor = UIColor(hex: "#00FF88").withAlphaComponent(0.70)
        innerPad.lineWidth = 1.8
        innerPad.zPosition = 2.2
        node.addChild(innerPad)
        // Center glow dot
        let centerDot = SKShapeNode(circleOfRadius: R * 0.14)
        centerDot.fillColor = UIColor(hex: "#00FF88").withAlphaComponent(0.6)
        centerDot.strokeColor = UIColor(hex: "#66FFBB")
        centerDot.lineWidth = 1.0
        centerDot.glowWidth = 6.0
        centerDot.zPosition = 3.5
        node.addChild(centerDot)

        // ── Extraction "X" mark ─────────────────────────────────────────────
        let xMark = SKShapeNode()
        let xp = CGMutablePath()
        let xs: CGFloat = R * 0.26
        xp.move(to: CGPoint(x: -xs, y: -xs)); xp.addLine(to: CGPoint(x: xs, y: xs))
        xp.move(to: CGPoint(x: xs, y: -xs));  xp.addLine(to: CGPoint(x: -xs, y: xs))
        xMark.path = xp
        xMark.strokeColor = UIColor(hex: "#00FF88").withAlphaComponent(0.80)
        xMark.lineWidth = 2.0
        xMark.glowWidth = 4.0
        xMark.zPosition = 3
        node.addChild(xMark)

        // ── Spinning outer hex ring ──────────────────────────────────────────
        let hexRing = SKShapeNode(path: TileMap.hexPath(radius: R - 4))
        hexRing.fillColor = .clear
        hexRing.strokeColor = UIColor(hex: "#00FF88").withAlphaComponent(0.40)
        hexRing.lineWidth = 2.0
        hexRing.zPosition = 2.8
        node.addChild(hexRing)
        hexRing.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 4.0)))

        // ── Pulsing energy wave ──────────────────────────────────────────────
        let wave = SKShapeNode(circleOfRadius: R * 0.35)
        wave.fillColor = UIColor(hex: "#00FF88").withAlphaComponent(0.12)
        wave.strokeColor = .clear
        wave.zPosition = 1.5
        node.addChild(wave)
        wave.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.2, duration: 1.0),
                SKAction.fadeAlpha(to: 0.0, duration: 1.0)
            ]),
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.0),
                SKAction.fadeAlpha(to: 1.0, duration: 0.0)
            ])
        ])))

        // ── Directional approach arrows (pointing inward) ────────────────────
        for i in 0..<6 {
            let angle = CGFloat(i) * CGFloat.pi / 3.0
            let arrowDist: CGFloat = R * 0.90
            let arrow = SKShapeNode()
            let ap = CGMutablePath()
            ap.move(to: CGPoint(x: 0, y: 5))
            ap.addLine(to: CGPoint(x: 5, y: -5))
            ap.addLine(to: CGPoint(x: -5, y: -5))
            ap.closeSubpath()
            arrow.path = ap
            arrow.fillColor = UIColor(hex: "#00FF88").withAlphaComponent(0.55)
            arrow.strokeColor = UIColor(hex: "#00FF88").withAlphaComponent(0.85)
            arrow.lineWidth = 0.5
            arrow.position = CGPoint(x: arrowDist * cos(angle), y: arrowDist * sin(angle))
            arrow.zRotation = angle + CGFloat.pi
            arrow.zPosition = 3
            node.addChild(arrow)
        }

        // ── Whole tile slow pulse ────────────────────────────────────────────
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 1.2),
            SKAction.fadeAlpha(to: 0.70, duration: 1.2)
        ])))
    }

    // MARK: - Coordinate Helpers

    func worldPosition(tileX: Int, tileY: Int) -> CGPoint {
        return TileMap.tileCenter(x: tileX, y: tileY)
    }

    func tile(at x: Int, y: Int) -> TileType? {
        guard x >= 0, x < TileMap.mapWidth, y >= 0, y < self.mapHeight else { return nil }
        return tiles[y][x]
    }

    func isWalkable(x: Int, y: Int) -> Bool {
        guard let t = tile(at: x, y: y) else { return false }
        return t != .wall
    }

    /// Mark a data terminal tile as "hacked" — fades the prop and overlays a
    /// green checkmark to show it's been collected. The tile remains walkable.
    func markTerminalHacked(x: Int, y: Int) {
        guard x >= 0, x < TileMap.mapWidth, y >= 0, y < self.mapHeight else { return }
        guard let node = tileNodes[y][x] else { return }
        // Fade out animated children (LEDs, pulse, code lines) so the tile reads "done".
        for child in node.children {
            if child.name == "highlight" { continue }
            child.removeAllActions()
        }
        node.run(SKAction.fadeAlpha(to: 0.55, duration: 0.25))
        // Add a green check overlay
        let R = TileMap.hexRadius
        let check = SKShapeNode()
        let cp = CGMutablePath()
        cp.move(to: CGPoint(x: -R * 0.20, y: 0))
        cp.addLine(to: CGPoint(x: -R * 0.05, y: -R * 0.16))
        cp.addLine(to: CGPoint(x: R * 0.24, y: R * 0.18))
        check.path = cp
        check.strokeColor = UIColor(hex: "#00FF88")
        check.lineWidth = 3.0
        check.glowWidth = 4.0
        check.zPosition = 5.0
        check.name = "terminalCheck"
        node.addChild(check)
    }

    // MARK: - Highlights

    func highlightTile(at x: Int, y: Int, color: UIColor) {
        guard let node = tileNodes[y][x] else { return }
        let R = TileMap.hexRadius
        // Fill overlay — shows the reachable/selectable area clearly
        let overlay = SKShapeNode(path: TileMap.hexPath(radius: R - 2))
        overlay.fillColor = color.withAlphaComponent(0.20)
        overlay.strokeColor = .clear
        overlay.zPosition = 5
        overlay.name = "highlight"
        node.addChild(overlay)
        // Bright neon border ring
        let ring = SKShapeNode(path: TileMap.hexPath(radius: R + 2))
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 2.2
        ring.glowWidth = 5.0
        ring.zPosition = 5.1
        ring.name = "highlight"
        node.addChild(ring)
    }

    func clearHighlights() {
        for row in tileNodes {
            for node in row {
                // Remove ALL children named "highlight" (overlay fill + neon ring = 2 nodes per tile)
                node?.children
                    .filter { $0.name == "highlight" }
                    .forEach { $0.removeFromParent() }
            }
        }
    }

    // MARK: - Ambient Effects

    func addAmbientEffects(to container: SKNode, mapSize: CGSize) {
        for _ in 0..<6 {
            let ember = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...1.5))
            ember.fillColor = UIColor(hex: "#FF6600").withAlphaComponent(CGFloat.random(in: 0.3...0.6))
            ember.strokeColor = .clear
            ember.zPosition = -1

            let startX = CGFloat.random(in: 0...mapSize.width)
            let startY = CGFloat.random(in: 0...mapSize.height)
            ember.position = CGPoint(x: startX, y: startY)
            container.addChild(ember)

            let duration = CGFloat.random(in: 6.0...12.0)
            ember.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveTo(x: startX, duration: 0),
                SKAction.moveTo(y: startY, duration: 0),
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -20...20),
                                   y: CGFloat.random(in: 10...30), duration: duration),
                    SKAction.sequence([
                        SKAction.wait(forDuration: duration * 0.8),
                        SKAction.fadeOut(withDuration: duration * 0.2)
                    ])
                ]),
                SKAction.fadeIn(withDuration: 0.1)
            ])))
        }
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
