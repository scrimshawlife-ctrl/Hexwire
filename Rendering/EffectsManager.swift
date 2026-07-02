import SpriteKit

// MARK: - Combat Particle Effects

/// Adds satisfying visual feedback to combat: sparks, blood splatter, screen shake, etc.
@MainActor
final class EffectsManager {

    static let shared = EffectsManager()

    private init() {}

    // MARK: - Spark Burst

    /// Emit a burst of cyan/white sparks at a world position with mixed square shapes for pixel-art style.
    func emitSparks(at position: CGPoint, in scene: SKScene, count: Int = 12) {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = count + 6
        emitter.particleLifetime = 0.3
        emitter.particleLifetimeRange = 0.15
        emitter.particleSpeed = 120
        emitter.particleSpeedRange = 80
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -3.0
        emitter.particleScale = 0.8
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.5
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [
                UIColor.white,
                UIColor(hex: "#00FFFF"),
                UIColor(hex: "#FF9900"),
                UIColor(hex: "#FFFF00")
            ] as [UIColor],
            times: [0, 0.25, 0.6, 1.0]
        )
        emitter.position = position
        emitter.zPosition = 50
        scene.addChild(emitter)

        let wait = SKAction.wait(forDuration: 0.6)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))

        // Add small square particle shapes for pixel-art style
        for i in 0..<6 {
            let delay = CGFloat(i) * 0.02
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let square = SKShapeNode(rectOf: CGSize(width: 3, height: 3))
                square.fillColor = [
                    UIColor(hex: "#00FFFF"),
                    UIColor(hex: "#FF9900"),
                    UIColor(hex: "#FFFF00"),
                    UIColor.white
                ].randomElement() ?? .white
                square.strokeColor = .clear

                let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
                let speed: CGFloat = CGFloat.random(in: 80...150)
                let distance = speed * 0.3
                let targetX = position.x + distance * cos(angle)
                let targetY = position.y + distance * sin(angle)

                square.position = position
                square.zPosition = 50
                square.alpha = 0.8
                scene.addChild(square)

                let move = SKAction.move(to: CGPoint(x: targetX, y: targetY), duration: 0.3)
                move.timingMode = .easeOut
                let fade = SKAction.fadeOut(withDuration: 0.3)
                let removeSquare = SKAction.removeFromParent()
                square.run(SKAction.group([move, fade, removeSquare]))
            }
        }
    }

    // MARK: - Blood Splatter

    /// Emit a red blood splatter effect at world position with multiple red shades and ground splatter decals.
    func emitBlood(at position: CGPoint, in scene: SKScene, count: Int = 10) {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = count
        emitter.particleLifetime = 0.4
        emitter.particleLifetimeRange = 0.2
        emitter.particleSpeed = 80
        emitter.particleSpeedRange = 50
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -2.5
        emitter.particleScale = 1.0
        emitter.particleScaleSpeed = -2.0
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [
                UIColor(hex: "#FF0000"),
                UIColor(hex: "#CC0000"),
                UIColor(hex: "#990000")
            ] as [UIColor],
            times: [0, 0.5, 1.0]
        )
        emitter.position = position
        emitter.zPosition = 49
        scene.addChild(emitter)

        let wait = SKAction.wait(forDuration: 0.7)
        let remove = SKAction.removeFromParent()
        emitter.run(SKAction.sequence([wait, remove]))

        // Add ground splatter decals
        for i in 0..<4 {
            let splatterDelay = CGFloat(i) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + splatterDelay) {
                let splatter = SKShapeNode(circleOfRadius: CGFloat.random(in: 4...8))
                splatter.fillColor = [
                    UIColor(hex: "#CC0000"),
                    UIColor(hex: "#990000"),
                    UIColor(hex: "#660000")
                ].randomElement() ?? UIColor(hex: "#CC0000")
                splatter.strokeColor = .clear

                let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
                let distance = CGFloat.random(in: 15...45)
                splatter.position = CGPoint(
                    x: position.x + distance * cos(angle),
                    y: position.y + distance * sin(angle)
                )
                splatter.zPosition = 25
                splatter.alpha = 0.6
                scene.addChild(splatter)

                // Fade and remove after 2 seconds
                let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                let waitTwo = SKAction.wait(forDuration: 1.5)
                let removeSplatter = SKAction.removeFromParent()
                splatter.run(SKAction.sequence([
                    waitTwo,
                    fadeOut,
                    removeSplatter
                ]))
            }
        }
    }

    // MARK: - Screen Shake

    /// True camera origin while a shake is in flight, so overlapping shakes
    /// don't capture a displaced position as "home" and drift the camera.
    private var shakeOrigin: CGPoint?

    /// Apply a camera shake effect to the scene with brief red/orange tint flash overlay.
    func screenShake(on scene: SKScene, intensity: CGFloat = 8, duration: TimeInterval = 0.25) {
        guard let camera = scene.camera else { return }

        if camera.action(forKey: "screenShake") != nil {
            camera.removeAction(forKey: "screenShake")
            if let origin = shakeOrigin {
                camera.position = origin
            }
        }

        let originalPos = camera.position
        shakeOrigin = originalPos
        let shakeCount = max(1, Int(duration / 0.04))
        var actions: [SKAction] = []

        for _ in 0..<shakeCount {
            let dx = CGFloat.random(in: -intensity...intensity)
            let dy = CGFloat.random(in: -intensity...intensity)
            let move = SKAction.move(to: CGPoint(x: originalPos.x + dx, y: originalPos.y + dy), duration: 0.04)
            actions.append(move)
        }

        let returnToOrigin = SKAction.move(to: originalPos, duration: 0.1)
        let clearOrigin = SKAction.run { [weak self] in self?.shakeOrigin = nil }
        camera.run(SKAction.sequence([SKAction.sequence(actions), returnToOrigin, clearOrigin]), withKey: "screenShake")

        // Add brief red/orange overlay flash
        let flashRect = SKShapeNode(rectOf: CGSize(width: scene.size.width * 2, height: scene.size.height * 2))
        flashRect.fillColor = UIColor(hex: "#FF4400").withAlphaComponent(0)
        flashRect.strokeColor = .clear
        flashRect.position = camera.position
        flashRect.zPosition = 150
        scene.addChild(flashRect)

        let flashIn = SKAction.fadeIn(withDuration: 0.05)
        let flashOut = SKAction.fadeOut(withDuration: 0.15)
        let removeFlash = SKAction.removeFromParent()
        flashRect.run(SKAction.sequence([flashIn, flashOut, removeFlash]))
    }

    // MARK: - Level Up Burst

    /// Golden expanding ring effect for level ups with ascending sparkle particles and dramatic ring expansion.
    func emitLevelUp(at position: CGPoint, in scene: SKScene) {
        let ring = SKShapeNode(circleOfRadius: 15)
        ring.strokeColor = UIColor(hex: "#FFD700")
        ring.lineWidth = 3
        ring.fillColor = UIColor(hex: "#FFD700").withAlphaComponent(0.15)
        ring.position = position
        ring.zPosition = 60
        scene.addChild(ring)

        let expand = SKAction.scale(to: 7.0, duration: 0.6)
        expand.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 0.6)
        let remove = SKAction.removeFromParent()
        ring.run(SKAction.group([expand, fade, remove]))

        // Upward floating level-up text
        let label = SKLabelNode(text: "▲ LEVEL UP ▲")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 14
        label.fontColor = UIColor(hex: "#FFD700")
        label.position = CGPoint(x: position.x, y: position.y + 20)
        label.zPosition = 61
        label.alpha = 0
        scene.addChild(label)

        let floatUp = SKAction.moveBy(x: 0, y: 40, duration: 1.2)
        let fadeIn = SKAction.fadeIn(withDuration: 0.15)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let removeLabel = SKAction.removeFromParent()
        label.run(SKAction.sequence([
            fadeIn,
            SKAction.group([
                floatUp,
                SKAction.sequence([SKAction.wait(forDuration: 0.8), fadeOut])
            ]),
            removeLabel
        ]))

        // Add ascending golden sparkle particles in spiral pattern
        for i in 0..<12 {
            let angle = (CGFloat(i) / 12.0) * (CGFloat.pi * 2)
            let spiralDelay = CGFloat(i) * 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + spiralDelay) {
                let sparkle = SKShapeNode(circleOfRadius: 2)
                sparkle.fillColor = UIColor(hex: "#FFD700")
                sparkle.strokeColor = .clear
                sparkle.position = position
                sparkle.zPosition = 59
                sparkle.alpha = 0.9
                scene.addChild(sparkle)

                let radius: CGFloat = 60
                let targetX = position.x + radius * cos(angle)
                let targetY = position.y + radius * sin(angle) + 60

                let move = SKAction.move(to: CGPoint(x: targetX, y: targetY), duration: 0.8)
                move.timingMode = .easeOut
                let fade = SKAction.fadeOut(withDuration: 0.6)
                let removeSparkle = SKAction.removeFromParent()
                sparkle.run(SKAction.group([move, fade, removeSparkle]))
            }
        }
    }

    // MARK: - Floating Damage Text

    /// Show a floating damage number at a world position with optional customizable color and font size.
    ///
    /// Z-ordering: 200/199 (label/shadow). Scanlines sit at z=85–100 and the
    /// vignette ring at z=90 — the previous z=70 put damage popups BEHIND
    /// both of those, which was the "sometimes the number doesn't show"
    /// playtest report. Bumping to z=200 puts the popup above every
    /// passive overlay but below the room-fade overlay (z=500).
    ///
    /// Font size also bumped on the assumption the popup was getting lost
    /// in scene-glare; small numbers were too easy to miss next to the
    /// flash + spark effect.
    func showCombatText(_ text: String, at position: CGPoint, in scene: SKScene, color: UIColor = .white, fontSize: CGFloat = 18) {
        let label = SKLabelNode(text: text)
        label.fontName = "Helvetica-Bold"
        label.fontSize = fontSize
        label.fontColor = color
        label.position = position
        // Must sit above the active-runner / targeted-enemy sprite z-bump.
        // BattleScene lifts the selected runner and the targeted enemy to
        // `depthZ (~40-46) + 1000` (≈1050) so they always read foreground.
        // At the old z=200 the floating MISS/SOAK/damage text rendered
        // *behind* whichever unit was bumped (most visibly the enemy you
        // just shot). 1500 clears the bump with headroom.
        label.zPosition = 1500
        label.alpha = 0
        scene.addChild(label)

        // Dark shadow/outline behind text for better readability against
        // bright sprites + sparks. Sits one z below the label.
        let shadow = SKLabelNode(text: text)
        shadow.fontName = "Helvetica-Bold"
        shadow.fontSize = fontSize
        shadow.fontColor = UIColor.black.withAlphaComponent(0.85)
        shadow.position = CGPoint(x: position.x + 1, y: position.y - 1)
        shadow.zPosition = 1499   // directly under the label (see note above)
        shadow.alpha = 0
        scene.addChild(shadow)

        // Slight bounce-up before float-up movement
        let bounceUp = SKAction.moveBy(x: 0, y: 5, duration: 0.1)
        bounceUp.timingMode = .easeOut
        let bounceDown = SKAction.moveBy(x: 0, y: -5, duration: 0.1)
        bounceDown.timingMode = .easeIn
        let floatUp = SKAction.moveBy(x: 0, y: 30, duration: 0.8)
        floatUp.timingMode = .easeOut
        let fadeIn = SKAction.fadeIn(withDuration: 0.1)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let remove = SKAction.removeFromParent()

        label.run(SKAction.sequence([
            fadeIn,
            SKAction.group([
                SKAction.sequence([bounceUp, bounceDown, floatUp]),
                SKAction.group([
                    SKAction.sequence([SKAction.wait(forDuration: 0.4), fadeOut]),
                    SKAction.sequence([SKAction.wait(forDuration: 0.4), SKAction.sequence([
                        SKAction.run { shadow.alpha = 0 },
                        SKAction.fadeOut(withDuration: 0.4)
                    ])])
                ])
            ]),
            remove
        ]))
        let moveUp = SKAction.moveBy(x: 0, y: 35, duration: 0.8)
        moveUp.timingMode = .easeOut
        shadow.run(SKAction.sequence([
            SKAction.run { shadow.alpha = 0.8 },
            SKAction.wait(forDuration: 0.2),
            SKAction.group([
                moveUp,
                SKAction.sequence([SKAction.wait(forDuration: 0.4), SKAction.fadeOut(withDuration: 0.4)])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    /// Show a floating damage number at a world position.
    func showFloatingText(_ text: String, at position: CGPoint, in scene: SKScene, color: UIColor = .white) {
        showCombatText(text, at: position, in: scene, color: color, fontSize: 18)
    }

    /// Show a damage burst (red) at position. Shows larger font and "CRIT!" prefix for critical hits (damage > 10).
    /// Damage popups now spawn ABOVE the unit instead of dead-center on it
    /// so they're not occluded by the unit's HP bar / sprite. Slight upward
    /// offset (32pt) lets the rise animation read as "damage popping off
    /// the head" rather than "number appearing on chest".
    func showDamageNumber(_ damage: Int, at position: CGPoint, in scene: SKScene) {
        let spawnAt = CGPoint(x: position.x, y: position.y + 32)
        if damage > 10 {
            let text = "CRIT! \(damage)"
            showCombatText(text, at: spawnAt, in: scene, color: UIColor(hex: "#FF0000"), fontSize: 28)
        } else {
            showCombatText("-\(damage)", at: spawnAt, in: scene, color: UIColor(hex: "#FF3333"), fontSize: 24)
        }
    }

    /// Show a heal number (green) at position.
    func showHealNumber(_ amount: Int, at position: CGPoint, in scene: SKScene) {
        showFloatingText("+\(amount)", at: position, in: scene, color: UIColor(hex: "#00FF88"))
    }

    // MARK: - Scanlines

    /// Animated scan lines for atmosphere with dual moving scanlines for more atmospheric effect.
    func addScanlines(to scene: SKScene) {
        // Size scanline to fit the actual scene — works on any device/orientation.
        // With resizeFill the scene fills the screen, so use scene size directly.
        let scanWidth: CGFloat  = scene.size.width
        let scanHeight: CGFloat = scene.size.height

        // First scanline moving downward
        let scanline = SKShapeNode(rectOf: CGSize(width: scanWidth * 1.2, height: 2))
        scanline.fillColor = UIColor.white.withAlphaComponent(0.03)
        scanline.strokeColor = .clear
        scanline.position = CGPoint(x: 0, y: scanHeight + 20)
        scanline.zPosition = 100
        scanline.name = "scanline"

        let totalDistance = scanHeight + 40  // from top+20 back to below bottom
        scanline.run(SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: -totalDistance, duration: 3.5),
                SKAction.run { scanline.position.y = scanHeight + 20 }
            ])
        ))
        scene.addChild(scanline)

        // Second scanline moving upward (opposite direction) at slower speed
        let scanline2 = SKShapeNode(rectOf: CGSize(width: scanWidth * 1.2, height: 2))
        scanline2.fillColor = UIColor.white.withAlphaComponent(0.03)
        scanline2.strokeColor = .clear
        scanline2.position = CGPoint(x: 0, y: -scanHeight - 20)
        scanline2.zPosition = 100
        scanline2.name = "scanline2"

        scanline2.run(SKAction.repeatForever(
            SKAction.sequence([
                SKAction.moveBy(x: 0, y: totalDistance, duration: 5.0),
                SKAction.run { scanline2.position.y = -scanHeight - 20 }
            ])
        ))
        scene.addChild(scanline2)
    }

    // MARK: - Cyber Glitch

    /// Digital dissolution effect — small colored rectangles appearing/disappearing rapidly for 0.5s.
    func emitCyberGlitch(at position: CGPoint, in scene: SKScene) {
        let glitchColors = [
            UIColor(hex: "#FF0080"),
            UIColor(hex: "#00FFFF"),
            UIColor(hex: "#00FF00"),
            UIColor(hex: "#FF00FF")
        ]

        let totalDuration: TimeInterval = 0.5
        let iterations = 10

        for iteration in 0..<iterations {
            let delay = Double(iteration) * (totalDuration / Double(iterations))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let rect = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 6...12), height: CGFloat.random(in: 6...12)))
                rect.fillColor = glitchColors.randomElement() ?? .white
                rect.strokeColor = .clear

                let offsetX = CGFloat.random(in: -20...20)
                let offsetY = CGFloat.random(in: -20...20)
                rect.position = CGPoint(x: position.x + offsetX, y: position.y + offsetY)
                rect.zPosition = 85
                rect.alpha = 0.8
                scene.addChild(rect)

                let duration = Double.random(in: 0.05...0.15)
                let fadeOut = SKAction.fadeOut(withDuration: duration)
                let remove = SKAction.removeFromParent()
                rect.run(SKAction.sequence([fadeOut, remove]))
            }
        }
    }

    // MARK: - Rain Effect

    /// Very subtle diagonal rain streaks covering the full scene area. Repeats forever.
    func addRainEffect(to scene: SKScene) {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 15
        emitter.particleLifetime = 2.0
        emitter.particleSpeed = 60
        emitter.particleSpeedRange = 20
        emitter.emissionAngle = CGFloat.pi * 0.75  // Diagonal downward
        emitter.emissionAngleRange = CGFloat.pi * 0.1
        emitter.particleAlpha = 0.4
        emitter.particleAlphaRange = 0.1
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleColor = UIColor.white
        emitter.particleColorBlendFactor = 1.0

        // Position emitter above the scene to rain down
        emitter.position = CGPoint(x: 0, y: scene.size.height / 2 + 50)
        emitter.zPosition = 10
        emitter.name = "rainEffect"

        scene.addChild(emitter)
    }

    // MARK: - Extraction Beacon

    /// Pulsing extraction zone indicator.
    func pulseNode(_ node: SKNode) {
        let pulseUp = SKAction.scale(to: 1.15, duration: 0.6)
        pulseUp.timingMode = .easeInEaseOut
        let pulseDown = SKAction.scale(to: 1.0, duration: 0.6)
        pulseDown.timingMode = .easeInEaseOut
        node.run(SKAction.repeatForever(SKAction.sequence([pulseUp, pulseDown])))
    }

    // MARK: - Spell / skill effects

    /// Green particle bloom + rising "+N HP" text for the HEAL spell.
    func emitHeal(at position: CGPoint, in scene: SKScene, amount: Int) {
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = 18
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.3
        emitter.particleSpeed = 60
        emitter.particleSpeedRange = 30
        emitter.emissionAngle = -.pi / 2          // upward
        emitter.emissionAngleRange = .pi / 3
        emitter.particleAlpha = 0.95
        emitter.particleAlphaSpeed = -1.2
        emitter.particleScale = 0.6
        emitter.particleScaleRange = 0.3
        emitter.particleScaleSpeed = -0.4
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [
                UIColor(hex: "#88FFAA"),
                UIColor(hex: "#44FF88"),
                UIColor(hex: "#00CC55"),
                UIColor.white
            ] as [UIColor],
            times: [0, 0.4, 0.7, 1.0]
        )
        emitter.position = position
        emitter.zPosition = 50
        scene.addChild(emitter)
        emitter.run(SKAction.sequence([SKAction.wait(forDuration: 1.2),
                                       SKAction.removeFromParent()]))

        // Pulsing green ring
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.strokeColor = UIColor(hex: "#44FF88")
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.glowWidth = 4
        ring.position = position
        ring.zPosition = 49
        scene.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 4.0, duration: 0.55),
                SKAction.fadeOut(withDuration: 0.55)
            ]),
            SKAction.removeFromParent()
        ]))

        if amount > 0 {
            showFloatingText("+\(amount) HP", at: position, in: scene,
                             color: UIColor(hex: "#44FF88"))
        }
    }

    /// Orange explosion + spark burst for FIREBALL — multi-tile AoE.
    /// Beefier than before: an INCOMING flame ball travels in from a
    /// random off-screen direction, then detonates with an expanding shock
    /// ring + heavy particle splatter + screen shake.
    func emitFireball(at position: CGPoint, from thrower: CGPoint? = nil, in scene: SKScene) {
        // Phase 1 — projectile arcs toward the impact point. A mage's fireball
        // streaks in from a random mystical angle; a thrown grenade (thrower !=
        // nil) arcs from the attacker's actual tile so it visibly comes FROM
        // the grenadier rather than a random side of the screen.
        let origin: CGPoint
        if let thrower = thrower {
            origin = thrower
        } else {
            let originAngle = CGFloat.random(in: 0..<(2 * .pi))
            let originDist: CGFloat = 220
            origin = CGPoint(x: position.x + cos(originAngle) * originDist,
                             y: position.y + sin(originAngle) * originDist)
        }
        let ball = SKShapeNode(circleOfRadius: 14)
        ball.fillColor = UIColor(hex: "#FF8822")
        ball.strokeColor = UIColor(hex: "#FFEE88")
        ball.lineWidth = 2
        ball.glowWidth = 10
        ball.position = origin
        ball.zPosition = 52
        scene.addChild(ball)
        // Trailing ember emitter follows the ball
        let trail = SKEmitterNode()
        trail.particleBirthRate = 90
        trail.particleLifetime = 0.4
        trail.particleSpeed = 30
        trail.particleSpeedRange = 20
        trail.emissionAngleRange = .pi * 2
        trail.particleAlpha = 0.8
        trail.particleAlphaSpeed = -2.5
        trail.particleScale = 0.5
        trail.particleScaleSpeed = -1.2
        trail.particleColorBlendFactor = 1.0
        trail.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor(hex: "#FFEE88"), UIColor(hex: "#FF6600"), UIColor(hex: "#440000")] as [UIColor],
            times: [0, 0.5, 1.0]
        )
        trail.zPosition = 51
        ball.addChild(trail)

        let arrive = SKAction.move(to: position, duration: 0.32)
        arrive.timingMode = .easeIn
        ball.run(SKAction.sequence([arrive, SKAction.run { [weak self] in
            // Phase 2 — detonation at impact.
            self?.detonateFireballAt(position, in: scene)
            ball.removeFromParent()
        }]))
    }

    /// The actual explosion at the impact site (shared so both the arrived-
    /// ball and any tile-only call can trigger it).
    private func detonateFireballAt(_ position: CGPoint, in scene: SKScene) {
        // Bright core flash
        let core = SKShapeNode(circleOfRadius: 8)
        core.fillColor = UIColor.white
        core.strokeColor = .clear
        core.position = position
        core.zPosition = 50
        scene.addChild(core)
        core.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 8.0, duration: 0.30),
                SKAction.fadeOut(withDuration: 0.30)
            ]),
            SKAction.removeFromParent()
        ]))

        // Outer shock ring (expanding outward)
        let ring = SKShapeNode(circleOfRadius: 14)
        ring.strokeColor = UIColor(hex: "#FF6600")
        ring.fillColor = .clear
        ring.lineWidth = 4
        ring.glowWidth = 12
        ring.position = position
        ring.zPosition = 49
        scene.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 11.0, duration: 0.55),
                SKAction.fadeOut(withDuration: 0.55)
            ]),
            SKAction.removeFromParent()
        ]))

        // Inner burning cloud — slower expanding for a billowing look
        let cloud = SKShapeNode(circleOfRadius: 18)
        cloud.fillColor = UIColor(hex: "#FF6600").withAlphaComponent(0.6)
        cloud.strokeColor = .clear
        cloud.position = position
        cloud.zPosition = 48
        scene.addChild(cloud)
        cloud.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 4.5, duration: 0.7),
                SKAction.fadeOut(withDuration: 0.7)
            ]),
            SKAction.removeFromParent()
        ]))

        // Heavy particle splatter — embers + sparks
        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = 50      // was 28 — bigger blast
        emitter.particleLifetime = 0.85
        emitter.particleLifetimeRange = 0.4
        emitter.particleSpeed = 260
        emitter.particleSpeedRange = 130
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 1.0
        emitter.particleAlphaSpeed = -1.4
        emitter.particleScale = 0.9
        emitter.particleScaleRange = 0.5
        emitter.particleScaleSpeed = -0.9
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [
                UIColor.white,
                UIColor(hex: "#FFEE00"),
                UIColor(hex: "#FF6600"),
                UIColor(hex: "#440000")
            ] as [UIColor],
            times: [0, 0.2, 0.6, 1.0]
        )
        emitter.position = position
        emitter.zPosition = 51
        scene.addChild(emitter)
        emitter.run(SKAction.sequence([SKAction.wait(forDuration: 1.2),
                                       SKAction.removeFromParent()]))

        screenShake(on: scene, intensity: 12, duration: 0.30)
    }

    /// A coloured bolt drawn from caster → target (used for MANABOLT).
    /// Beefed up — three layered bolts (outer halo, mid stroke, bright
    /// inner core) animate sequentially to give a "manabolt streak" look,
    /// each with random control-point wobble. Plus a charge-up spark at
    /// the caster, plus impact splatter at the target.
    func emitMagicBolt(from origin: CGPoint, to target: CGPoint,
                       color: UIColor, in scene: SKScene) {
        // Charge-up halo at caster
        let charge = SKShapeNode(circleOfRadius: 12)
        charge.fillColor = color.withAlphaComponent(0.6)
        charge.strokeColor = color
        charge.lineWidth = 2
        charge.glowWidth = 8
        charge.position = origin
        charge.zPosition = 51
        scene.addChild(charge)
        charge.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.3, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18)
            ]),
            SKAction.removeFromParent()
        ]))

        // Three layered bolts — outer wide halo, mid stroke, inner bright
        // core. Each gets a slightly different mid-point so they read as
        // intertwined streaks rather than a single line.
        for (i, layer) in [(8, color.withAlphaComponent(0.35), 14.0),
                           (4, color, 10.0),
                           (2, UIColor.white, 6.0)].enumerated() {
            let mid = CGPoint(x: (origin.x + target.x) / 2 + CGFloat.random(in: -12...12),
                              y: (origin.y + target.y) / 2 + CGFloat.random(in: -12...12))
            let cgPath = UIBezierPath()
            cgPath.move(to: origin)
            cgPath.addQuadCurve(to: target, controlPoint: mid)
            let bolt = SKShapeNode(path: cgPath.cgPath)
            bolt.strokeColor = layer.1
            bolt.lineWidth = CGFloat(layer.0)
            bolt.glowWidth = CGFloat(layer.2)
            bolt.fillColor = .clear
            bolt.zPosition = CGFloat(52 + i)
            bolt.alpha = 0
            scene.addChild(bolt)
            let appear = SKAction.fadeIn(withDuration: 0.05)
            let dwell  = SKAction.wait(forDuration: 0.12)
            let fade   = SKAction.fadeOut(withDuration: 0.30)
            bolt.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.18 + Double(i) * 0.04),  // staggered
                appear, dwell, fade,
                SKAction.removeFromParent()
            ]))
        }

        // Impact splatter at target (delayed so it lines up with bolt arrival)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self = self else { return }
            // Coloured impact ring
            let ring = SKShapeNode(circleOfRadius: 10)
            ring.strokeColor = color
            ring.fillColor = .clear
            ring.lineWidth = 2.5
            ring.glowWidth = 8
            ring.position = target
            ring.zPosition = 50
            scene.addChild(ring)
            ring.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 4.0, duration: 0.4),
                    SKAction.fadeOut(withDuration: 0.4)
                ]),
                SKAction.removeFromParent()
            ]))
            self.emitSparks(at: target, in: scene, count: 14)
        }
    }

    /// Yellow zigzag lightning for the SHOCK spell.
    /// Beefed up — 3 forked lightning strikes flash in rapid succession
    /// (each with its own randomised zigzag), plus a bright impact flash
    /// at the target and an electrified spark splatter.
    func emitShockBolt(from origin: CGPoint, to target: CGPoint, in scene: SKScene) {
        // Helper to build a single zigzag bolt path.
        func makeBoltPath() -> CGPath {
            let segments = 7
            let dx = (target.x - origin.x) / CGFloat(segments)
            let dy = (target.y - origin.y) / CGFloat(segments)
            let normalLen = hypot(dx, dy)
            let nx = -dy / max(0.01, normalLen)
            let ny = dx / max(0.01, normalLen)
            let path = UIBezierPath()
            path.move(to: origin)
            for i in 1..<segments {
                let baseX = origin.x + dx * CGFloat(i)
                let baseY = origin.y + dy * CGFloat(i)
                let jitter: CGFloat = CGFloat.random(in: -16...16)
                path.addLine(to: CGPoint(x: baseX + nx * jitter, y: baseY + ny * jitter))
            }
            path.addLine(to: target)
            return path.cgPath
        }

        // Main strike: outer glow + bright inner core.
        for (i, layer) in [(6, UIColor(hex: "#FFEE00").withAlphaComponent(0.4), 14.0),
                           (3, UIColor(hex: "#FFEE00"), 10.0),
                           (1.5, UIColor.white, 4.0)].enumerated() {
            let bolt = SKShapeNode(path: makeBoltPath())
            bolt.strokeColor = layer.1
            bolt.lineWidth = CGFloat(layer.0)
            bolt.glowWidth = CGFloat(layer.2)
            bolt.fillColor = .clear
            bolt.zPosition = CGFloat(52 + i)
            bolt.alpha = 0
            scene.addChild(bolt)
            bolt.run(SKAction.sequence([
                SKAction.fadeIn(withDuration: 0.04),
                SKAction.wait(forDuration: 0.10),
                SKAction.fadeOut(withDuration: 0.18),
                SKAction.removeFromParent()
            ]))
        }

        // Two "aftershock" forked bolts that flash slightly after the main
        // strike — gives the shock a stuttering, electrical-arc rhythm.
        for delay in [0.18, 0.32] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let bolt = SKShapeNode(path: makeBoltPath())
                bolt.strokeColor = UIColor(hex: "#FFEE00")
                bolt.lineWidth = 2
                bolt.glowWidth = 6
                bolt.fillColor = .clear
                bolt.zPosition = 52
                bolt.alpha = 0
                scene.addChild(bolt)
                bolt.run(SKAction.sequence([
                    SKAction.fadeIn(withDuration: 0.03),
                    SKAction.wait(forDuration: 0.06),
                    SKAction.fadeOut(withDuration: 0.10),
                    SKAction.removeFromParent()
                ]))
            }
        }

        // Bright white impact flash at the target.
        let flash = SKShapeNode(circleOfRadius: 12)
        flash.fillColor = UIColor.white
        flash.strokeColor = UIColor(hex: "#FFEE00")
        flash.lineWidth = 2
        flash.glowWidth = 14
        flash.position = target
        flash.zPosition = 51
        scene.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.5, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.20)
            ]),
            SKAction.removeFromParent()
        ]))

        emitSparks(at: target, in: scene, count: 16)
    }

    /// Red slash-arc burst at the samurai's tile for BLITZ.
    func emitSlashArc(at position: CGPoint, in scene: SKScene) {
        // Multiple slash strokes rotated around the centre.
        let radius: CGFloat = 30
        for i in 0..<3 {
            let angle = -CGFloat.pi/4 + CGFloat(i) * (.pi / 4.5)
            let path = UIBezierPath()
            let dx = cos(angle) * radius
            let dy = sin(angle) * radius
            path.move(to: CGPoint(x: position.x - dx, y: position.y - dy))
            path.addLine(to: CGPoint(x: position.x + dx, y: position.y + dy))
            let slash = SKShapeNode(path: path.cgPath)
            slash.strokeColor = UIColor(hex: "#FF3322")
            slash.lineWidth = 4
            slash.glowWidth = 10
            slash.lineCap = .round
            slash.zPosition = 52
            slash.alpha = 0
            scene.addChild(slash)
            let delay = SKAction.wait(forDuration: TimeInterval(i) * 0.05)
            let appear = SKAction.fadeIn(withDuration: 0.04)
            let dwell = SKAction.wait(forDuration: 0.10)
            let fade = SKAction.fadeOut(withDuration: 0.18)
            slash.run(SKAction.sequence([delay, appear, dwell, fade,
                                         SKAction.removeFromParent()]))
        }
        screenShake(on: scene, intensity: 4, duration: 0.18)
    }

    /// Gun fire — muzzle flash at shooter + bullet tracer line shooter→target.
    /// Quick, snappy, used every time a player shoots so it has to feel
    /// punchy without being expensive.
    func emitGunfire(from origin: CGPoint, to target: CGPoint, in scene: SKScene, archetype: String = "") {
        // Per-archetype styling so each boss's attack reads as its OWN thing:
        //   mech  — heavy orange autocannon + concussive impact ring
        //   agi   — magenta/cyan reality-glitch + scattered data shards
        //   mage  — dark-red bloodbolt + crimson burst
        //   else  — the standard yellow tracer
        let flashHex: String, tracerHex: String, impactHex: String?
        let tracerWidth: CGFloat, tracerGlow: CGFloat, flashScale: CGFloat
        let smoke: Bool, glitch: Bool
        switch archetype {
        case "bossmech":
            flashHex = "#FFAA55"; tracerHex = "#FF8844"; impactHex = "#FF7733"
            tracerWidth = 4.0; tracerGlow = 9; flashScale = 3.2; smoke = true;  glitch = false
        case "bossagi":
            flashHex = "#FF66E0"; tracerHex = "#FF44CC"; impactHex = "#66F0FF"
            tracerWidth = 2.6; tracerGlow = 8; flashScale = 2.6; smoke = false; glitch = true
        case "bossmage":
            flashHex = "#FF4455"; tracerHex = "#CC1133"; impactHex = "#FF2A2A"
            tracerWidth = 3.2; tracerGlow = 7; flashScale = 2.8; smoke = false; glitch = false
        case "bosscorp":
            // Vera Koss — precise cyan smartlink burst + clean impact ring.
            flashHex = "#66ECFF"; tracerHex = "#33D0FF"; impactHex = "#66F0FF"
            tracerWidth = 2.4; tracerGlow = 7; flashScale = 2.5; smoke = true;  glitch = false
        default:
            flashHex = "#FFCC44"; tracerHex = "#FFEEAA"; impactHex = nil
            tracerWidth = 1.8; tracerGlow = 4; flashScale = 2.4; smoke = true;  glitch = false
        }

        // Muzzle flash — bright burst at the shooter, fades fast.
        let flash = SKShapeNode(circleOfRadius: 8)
        flash.fillColor = UIColor.white
        flash.strokeColor = UIColor(hex: flashHex)
        flash.lineWidth = 2
        flash.glowWidth = 12
        flash.position = origin
        flash.zPosition = 51
        scene.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: flashScale, duration: 0.10),
                SKAction.fadeOut(withDuration: 0.12)
            ]),
            SKAction.removeFromParent()
        ]))

        // Tracer line — streak from shooter to target, fast (supersonic feel).
        let path = UIBezierPath()
        path.move(to: origin)
        path.addLine(to: target)
        let tracer = SKShapeNode(path: path.cgPath)
        tracer.strokeColor = UIColor(hex: tracerHex)
        tracer.lineWidth = tracerWidth
        tracer.glowWidth = tracerGlow
        tracer.lineCap = .round
        tracer.fillColor = .clear
        tracer.zPosition = 50
        tracer.alpha = 0
        scene.addChild(tracer)
        tracer.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.04),
            SKAction.wait(forDuration: 0.08),
            SKAction.fadeOut(withDuration: 0.10),
            SKAction.removeFromParent()
        ]))

        // A small kick of cordite-style smoke at the muzzle (ballistic weapons).
        if smoke {
            let smokeNode = SKEmitterNode()
            smokeNode.particleBirthRate = 0
            smokeNode.numParticlesToEmit = 6
            smokeNode.particleLifetime = 0.5
            smokeNode.particleSpeed = 40
            smokeNode.particleSpeedRange = 20
            smokeNode.emissionAngleRange = .pi / 2
            smokeNode.emissionAngle = atan2(target.y - origin.y, target.x - origin.x)
            smokeNode.particleAlpha = 0.6
            smokeNode.particleAlphaSpeed = -1.4
            smokeNode.particleScale = 0.6
            smokeNode.particleScaleSpeed = -0.7
            smokeNode.particleColor = UIColor(white: 0.85, alpha: 1.0)
            smokeNode.particleColorBlendFactor = 1.0
            smokeNode.position = origin
            smokeNode.zPosition = 49
            scene.addChild(smokeNode)
            smokeNode.run(SKAction.sequence([SKAction.wait(forDuration: 0.6),
                                             SKAction.removeFromParent()]))
        }

        // Impact flourish at the target — an expanding colored ring (boss-class
        // weapons), and for the AGI a scatter of glitch "data shards".
        if let impactHex = impactHex {
            let ring = SKShapeNode(circleOfRadius: 6)
            ring.position = target
            ring.fillColor = .clear
            ring.strokeColor = UIColor(hex: impactHex)
            ring.lineWidth = 3
            ring.glowWidth = 6
            ring.zPosition = 52
            scene.addChild(ring)
            ring.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 3.4, duration: 0.22),
                    SKAction.fadeOut(withDuration: 0.24)
                ]),
                SKAction.removeFromParent()
            ]))
            if glitch {
                for i in 0..<5 {
                    let shard = SKShapeNode(rectOf: CGSize(width: 9, height: 3))
                    shard.position = target
                    shard.fillColor = UIColor(hex: i % 2 == 0 ? tracerHex : impactHex)
                    shard.strokeColor = .clear
                    shard.zPosition = 53
                    shard.zRotation = CGFloat(i) * 1.3
                    scene.addChild(shard)
                    let ang = CGFloat(i) / 5 * .pi * 2
                    let dx = cos(ang) * 26, dy = sin(ang) * 26
                    shard.run(SKAction.sequence([
                        SKAction.group([
                            SKAction.moveBy(x: dx, y: dy, duration: 0.22),
                            SKAction.fadeOut(withDuration: 0.24)
                        ]),
                        SKAction.removeFromParent()
                    ]))
                }
            }
        }
    }

    /// Melee strike — quick red slash arc at the target's tile + impact spark.
    /// Used by the basic ATK action so a melee swing reads visually distinct
    /// from a ranged shot.
    func emitMeleeStrike(at position: CGPoint, in scene: SKScene) {
        // Single bold slash drawn at a random angle.
        let radius: CGFloat = 24
        let angle = CGFloat.random(in: -.pi/3 ... .pi/3) - .pi/6
        let path = UIBezierPath()
        let dx = cos(angle) * radius
        let dy = sin(angle) * radius
        path.move(to: CGPoint(x: position.x - dx, y: position.y - dy))
        path.addLine(to: CGPoint(x: position.x + dx, y: position.y + dy))
        let slash = SKShapeNode(path: path.cgPath)
        slash.strokeColor = UIColor(hex: "#FF5544")
        slash.lineWidth = 4
        slash.glowWidth = 9
        slash.lineCap = .round
        slash.zPosition = 52
        slash.alpha = 0
        scene.addChild(slash)
        slash.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.04),
            SKAction.wait(forDuration: 0.08),
            SKAction.fadeOut(withDuration: 0.16),
            SKAction.removeFromParent()
        ]))
        emitSparks(at: position, in: scene, count: 8)
    }

    /// HACK — Decker → target ICE intrusion. A stream of "0/1" binary
    /// glyphs flies from decker to target along a curved path, the target
    /// briefly flashes with a circuit-pattern overlay, and electric sparks
    /// burst at the impact point.
    func emitHack(from origin: CGPoint, to target: CGPoint, in scene: SKScene) {
        // Curved path of binary glyphs — they travel along the curve from
        // origin → target with a stagger so they read as a moving stream.
        let mid = CGPoint(x: (origin.x + target.x) / 2 + CGFloat.random(in: -10...10),
                          y: (origin.y + target.y) / 2 - 16)   // slight upward arc
        let glyphs = ["0", "1", "0", "1", "F", "7", "1", "0"]
        for (i, g) in glyphs.enumerated() {
            let label = SKLabelNode(text: g)
            label.fontName = "Menlo-Bold"
            label.fontSize = 13
            label.fontColor = UIColor(hex: "#00FFCC")
            label.position = origin
            label.zPosition = 52
            label.alpha = 0
            scene.addChild(label)
            // Bezier-ish travel: split path into 12 sub-points and animate
            // through them.
            let steps = 10
            var actions: [SKAction] = [
                SKAction.wait(forDuration: TimeInterval(i) * 0.05),
                SKAction.fadeIn(withDuration: 0.04)
            ]
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                // Quadratic bezier interpolation
                let omt = 1 - t
                let x = omt * omt * origin.x + 2 * omt * t * mid.x + t * t * target.x
                let y = omt * omt * origin.y + 2 * omt * t * mid.y + t * t * target.y
                actions.append(SKAction.move(to: CGPoint(x: x, y: y), duration: 0.04))
            }
            actions.append(SKAction.fadeOut(withDuration: 0.1))
            actions.append(SKAction.removeFromParent())
            label.run(SKAction.sequence(actions))
        }

        // Circuit-pattern impact at the target — a cyan ring + cross-hairs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            let ring = SKShapeNode(circleOfRadius: 14)
            ring.strokeColor = UIColor(hex: "#00FFCC")
            ring.fillColor = .clear
            ring.lineWidth = 3
            ring.glowWidth = 10
            ring.position = target
            ring.zPosition = 51
            scene.addChild(ring)
            ring.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 3.2, duration: 0.40),
                    SKAction.fadeOut(withDuration: 0.40)
                ]),
                SKAction.removeFromParent()
            ]))

            // Cross-hair lines flashing on top (the "system breach" feel).
            for angle in [0.0, .pi/2] as [CGFloat] {
                let line = SKShapeNode(rectOf: CGSize(width: 36, height: 2))
                line.fillColor = UIColor(hex: "#00FFCC")
                line.strokeColor = .clear
                line.glowWidth = 6
                line.position = target
                line.zRotation = angle
                line.zPosition = 52
                line.alpha = 0
                scene.addChild(line)
                line.run(SKAction.sequence([
                    SKAction.fadeIn(withDuration: 0.04),
                    SKAction.wait(forDuration: 0.10),
                    SKAction.fadeOut(withDuration: 0.20),
                    SKAction.removeFromParent()
                ]))
            }
        }
    }

    // MARK: - Triggered VFX (one-shot, scoped to specific events)
    //
    // Lightweight transient effects that fire on actions, not ambient. Each
    // is procedural (SKShapeNode + SKAction) so it composites cleanly with
    // the existing scene without sprite-atlas blending issues.

    /// 0.4s glitch flash + downward scan-line over an enemy node when hit by
    /// a HACK. Wraps the enemy in a cyan haze, runs a horizontal scan-line
    /// from top to bottom, and ticks 3 alpha-flicker pulses.
    func emitHackGlitch(on enemyNode: SKNode) {
        let bounds = enemyNode.calculateAccumulatedFrame().size
        let w = max(bounds.width, 60)
        let h = max(bounds.height, 90)

        // Cyan tint over the enemy's bounding box
        let tint = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 4)
        tint.fillColor = UIColor(hex: "#00FFCC").withAlphaComponent(0.30)
        tint.strokeColor = UIColor(hex: "#00FFCC")
        tint.lineWidth = 1.0
        tint.glowWidth = 3.0
        tint.blendMode = .add
        tint.alpha = 0.0
        tint.zPosition = 50
        tint.name = "hackGlitch_tint"
        enemyNode.addChild(tint)

        // Three quick alpha pulses then fade
        tint.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: 0.05),
            SKAction.fadeAlpha(to: 0.20, duration: 0.05),
            SKAction.fadeAlpha(to: 0.75, duration: 0.05),
            SKAction.fadeAlpha(to: 0.10, duration: 0.05),
            SKAction.fadeAlpha(to: 0.65, duration: 0.05),
            SKAction.fadeOut(withDuration: 0.15),
            SKAction.removeFromParent()
        ]))

        // Scan-line band that sweeps top→bottom
        let scan = SKShapeNode(rectOf: CGSize(width: w, height: 2.5))
        scan.fillColor = UIColor(hex: "#00FFCC")
        scan.strokeColor = .clear
        scan.glowWidth = 4.0
        scan.blendMode = .add
        scan.alpha = 0.0
        scan.position = CGPoint(x: 0, y: h / 2)
        scan.zPosition = 51
        scan.name = "hackGlitch_scan"
        enemyNode.addChild(scan)
        scan.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.04),
            SKAction.moveBy(x: 0, y: -h, duration: 0.32),
            SKAction.fadeOut(withDuration: 0.04),
            SKAction.removeFromParent()
        ]))
    }

    /// ~1s falling-glyph code-rain burst centered behind a chopper. Spawns
    /// a column of cyan glyphs that fall and fade. Used during extraction.
    func emitChopperCodeRain(behind chopperNode: SKNode, in scene: SKScene) {
        let chopperPos = chopperNode.position
        // Spawn 3 columns slightly behind & beneath the chopper
        let columnOffsets: [CGFloat] = [-32, 0, 32]
        let glyphChars = ["0", "1", "ア", "イ", "ウ", "エ", "ナ", "ノ", "ル", "·"]
        for col in columnOffsets {
            // 6 glyphs per column, each delayed slightly so they stagger
            for i in 0..<6 {
                let label = SKLabelNode(fontNamed: "Menlo-Bold")
                label.text = glyphChars.randomElement() ?? "0"
                label.fontSize = 11
                label.fontColor = UIColor(hex: "#00FFCC")
                label.alpha = 0.0
                label.blendMode = .add
                label.position = CGPoint(x: chopperPos.x + col + CGFloat.random(in: -4...4),
                                         y: chopperPos.y + 30)
                label.zPosition = 58  // behind chopper at z=60
                scene.addChild(label)
                let delay = SKAction.wait(forDuration: TimeInterval(i) * 0.08)
                let fall = SKAction.group([
                    SKAction.moveBy(x: 0, y: -90, duration: 0.85),
                    SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.85, duration: 0.18),
                        SKAction.wait(forDuration: 0.40),
                        SKAction.fadeOut(withDuration: 0.27)
                    ])
                ])
                label.run(SKAction.sequence([delay, fall, SKAction.removeFromParent()]))
            }
        }
    }

    /// Single expanding floor ring at an objective tile (extraction or data
    /// terminal) when a runner steps onto it. ~0.6s, fades out as it grows.
    func emitObjectivePulse(at position: CGPoint,
                            in scene: SKScene,
                            color: UIColor = UIColor(hex: "#00FFCC")) {
        for i in 0..<2 {
            let ring = SKShapeNode(circleOfRadius: 14)
            ring.strokeColor = color
            ring.fillColor = .clear
            ring.lineWidth = 2.0
            ring.glowWidth = 5.0
            ring.alpha = 0.85
            ring.position = position
            ring.zPosition = 4   // floor-level — under characters (z=10+)
            scene.addChild(ring)
            let delay = SKAction.wait(forDuration: TimeInterval(i) * 0.15)
            let pulse = SKAction.group([
                SKAction.scale(to: 4.0, duration: 0.6),
                SKAction.fadeOut(withDuration: 0.6)
            ])
            ring.run(SKAction.sequence([delay, pulse, SKAction.removeFromParent()]))
        }
    }

    /// Expanding red shockwave at Face's tile for INTIMIDATE.
    func emitIntimidateWave(at position: CGPoint, in scene: SKScene) {
        for i in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: 12)
            ring.strokeColor = UIColor(hex: "#FF2244")
            ring.fillColor = .clear
            ring.lineWidth = 2
            ring.glowWidth = 5
            ring.position = position
            ring.zPosition = 49
            scene.addChild(ring)
            let delay = SKAction.wait(forDuration: TimeInterval(i) * 0.10)
            let group = SKAction.group([
                SKAction.scale(to: 5.5, duration: 0.55),
                SKAction.fadeOut(withDuration: 0.55)
            ])
            ring.run(SKAction.sequence([delay, group,
                                        SKAction.removeFromParent()]))
        }
    }
}
