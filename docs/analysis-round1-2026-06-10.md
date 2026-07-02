# ShadowRune codebase analysis — round 1 (2026-06-10)

42 verified findings from four parallel sweeps: game mechanics, graphics/rendering, game feel, performance.

## The big ones

1. **Overwatch is wildly overpowered and invisible.** One Overwatch action is never consumed — `fireOverwatchShot` (Game/GameState.swift:1767) never removes the entry from `overwatchers`, and EnemyAI triggers it on every movement step of every enemy, so one action can fire 10+ free attacks per phase. A melee weapon gets `effectiveRange 99`, so Raze's katana becomes a no-falloff sniper rifle. It also posts no `.gunfireEffect` and an outcome-less `.enemyHit` — no muzzle flash, no sound; enemies just spontaneously lose HP. Fix: consume the entry after one shot, substitute a sidearm for melee, post proper effect notifications.

2. **Defend/Lay Low barely works.** The +3 defense is wiped the moment the next teammate's turn starts (Game/CombatFlowController.swift:1178) — it only survives into the enemy phase for the last character to act; for the other three runners it's a silent no-op. Single slot, so two defenders can't coexist. Fix: per-round `Set<UUID>` cleared in `beginRound`, like `overwatchers`.

3. **Initiative is completely dead — including paid cyberware.** `TurnManager`'s initiative machinery (Game/TurnManager.swift:57-100) has zero runtime callers; turn order is fixed roster order. "+N init" implants sold in the shop do nothing. Either drive ordering from initiative or repurpose the implants. (Also: `upcomingActors` would crash `% 0` if ever activated with an empty order.)

4. **Fireball is the dominant strategy.** Hits all living enemies anywhere on the map, no LOS or range check, `max(1,…)` guarantees chip damage through any soak, plus a stacking 2-round burn — ~40+ damage per 4-mana cast vs. Mana Bolt's 3-mana single target (Game/SpellResolver.swift:8-68). Also spams N× sounds/shakes/projectiles from random directions per cast (SpellResolver.swift:57-62). Fix: blast radius around a chosen tile + LOS (grenade code at GameState.swift:1566 has the pattern); single shake/SFX per cast.

5. **BattleScene leaks every mission.** `setupLongPressRecognizer` (Rendering/BattleScene.swift:204) adds a recognizer to the reused SKView and never removes it; the recognizer retains the scene, so `deinit` never runs and each stale scene keeps ~50 live notification observers reacting to combat events — duplicate effects, stacked long-press handlers, memory growth per mission. Fix: store it and remove in `willMove(from:)`.

6. **Screen shake is broken game-wide** (found independently by two agents). Rendering/EffectsManager.swift:159 uses `SKAction.group` instead of `.sequence`, so every shake collapses into a single ~40ms twitch regardless of requested duration. Overlapping shakes can also permanently drift the camera off-center (origin captured mid-shake, no action key). Fix: `.sequence`, run with a key, restore to a stored true origin.

## Mechanics & balance

- **Rigger = infinite XP faucet** — summons a free drone every turn fewer than 3 are alive, no lifetime cap (contrast Vera's `corpBossSummons < 2`); each kill pays maxHP/2 XP + loot (Game/EnemyAI.swift:850-854). Fix: lifetime cap, cooldown, or zero XP for summons.
- **Heal crit-glitch can kill the mage without the death pipeline** — drain branch never calls `handlePlayerKilled`; dead mage keeps sprite and turn slot, TPK via backfire skips `checkCombatEnd` (Game/SpellResolver.swift:188-196).
- **Glitch math punishes lucky rolls** — exploding-6 rerolls add their 1s to the glitch count but compare against the original pool (Game/DiceEngine.swift:42-91). Count first-roll ones only, or compare vs `allRolls.count`.
- **Drones at optimal range skip their attack 55% of the time** — "reposition before firing" strafe early-returns instead of firing (Game/EnemyAI.swift:156-184).
- **Full-stun enemies wake after one turn** regardless of remaining stun, then re-stun on any 1-point hit — flip-flop (Game/EnemyAI.swift:135-139). Only auto-recover when `currentStun < maxStun`; give the Decker hack-lock its own flag.
- **Failed hacks still spike TRACE** — `applySignalAction()` runs before the mana/no-target guards (Game/CombatFlowController.swift:686-695).
- **Hit preview lies on long shots** — `computeHitPreview` omits the −1d/tile range penalty and SIGNAL dice that `performAttack` applies (Game/DiceEngine.swift:235-277 vs CombatFlowController.swift:338-362). Share one pool-builder.
- **Enemy mage has guaranteed chip damage** (`max(1, …)` where every other enemy uses `max(0, …)`, EnemyAI.swift:1406); single-target spell fallback is array-order, not nearest (SpellResolver.swift:77).
- **Test gap:** tests/CombatMathTests.swift covers only clamping/cover basics. Cheapest high-value regression tests: glitch probability, defend persistence, overwatch consumption — inject a seeded RNG into `DiceEngine.rollDice`.

## Feel & presentation

- **Enemy phase locks input ~5s/round with no skip** — flat 0.7s per enemy + 0.65s trailing window, even for enemies that do nothing visible (Game/CombatFlowController.swift:1332, 1343). Shorten no-op slots to ~0.25s and/or tap-to-2x (`scene.speed = 2` + halved stagger).
- **Misses look identical to hits** — 14 sparks + shake on a dodge; only the floating text differs (Rendering/BattleScene.swift:3935-3961). `HapticsManager.attackMiss()` has zero call sites.
- **All ambient mission VFX are dead** — `VFXManager.isEnabled = false` (Rendering/VFXManager.swift:28) kills every mood effect and burst across all six missions. Known kill switch, but a large standing polish hole.
- **Enemy-phase red tint can stick on screen forever** — the 16s safety timeout never calls `fadeOutEnemyPhaseTint()`; duplicate `.enemyPhaseBegan` orphans tint nodes (Rendering/BattleScene.swift:3838-3854, 3899-3910).
- **Rain spawns from a single point at the left edge** — emitter positioned for a center-anchored scene but the scene anchor is (0,0); no `particlePositionRange` (Rendering/EffectsManager.swift:435-456). Parent to camera, set position range.
- **z-order broken during room transitions** — combat text z=1500 and helicopters z=1100 draw above the z=500 fade overlay (EffectsManager.swift:275, BattleScene.swift:376/463/2905). Define one z-table constant.
- **Defend and Overwatch are the only combat actions with no sound** — no observers for `.characterDefend` / `.characterOverwatch` (Game/SFXManager.swift:358-409).
- **All six mini-games share one identical 3.2s chiptune loop** (~19 repeats/min) that hard-cuts mid-note on the result screen (UI/ChiptunePlayer.swift:36-54, 135-144). ≥2 patterns + 0.3s fade before stop.
- **First combat dumps four queued tutorial cards**, one ~25 lines long, before the first tap (UI/CombatUI.swift:2356-2376, TutorialCoach.swift:46-68). Split into progressive triggers.
- **Loss-exit delays differ 2× between mini-games** (`success ? 1.5 : 0.9` in 3 of them, flat 1.6s in LaneRunner/AGIFaceoff). Hoverbike SMG uses the light `buttonTap` haptic instead of `combatInput()`. Insufficient-mana hack plays neutral tap where the SIGNAL gate uses `error()`. Unused: `moveConfirm()`, `menuOpen()`.
- **VN scenes double-compensate for the Dynamic Island** — `.padding(.top, 56)` on top of safe-area, SKIP lands ~110pt down (DropIntroScene.swift:199 + 4 siblings).
- **Combat-text shadow pops instead of fading** — label's action group zeroes the shadow's alpha mid-flight (EffectsManager.swift:301-325).
- **BasementBrawl assumes a perfect 60Hz tick** (`dt = 1/60` from a Timer) — runs in slow motion under load; ColdTrace/Mirrorline already do clamped real-dt correctly (BasementBrawlScene.swift:197, 673).
- **Post-attack idle resume re-animates frozen, non-active runners** against the "only active runner animates" rule (Rendering/SpriteManager.swift:2491, 2325).

## Performance

- **Worst offender: character-sheet portrait** — disk read + flood-fill over ~600K pixels inside SwiftUI `body`, uncached, on the main thread, re-run on every re-render (UI/CharacterInfoSheet.swift:108-161 → BasementBrawlScene.swift:1203-1291). The needed cache (`BasementBrawlSpriteCache.shared.image(named:)`) already exists. One-line fix.
- **SFX hitches** — fresh `AVAudioPlayer` + `prepareToPlay()` per sound; cache miss does synchronous disk IO exactly on the first gunshot/hit/death of a mission (Game/SFXManager.swift:44-61, 141-153). Preload common clips at mission start; pool prepared players.
- **Whole-HUD re-renders** — `GameState` has 40+ `@Published`, and `addLog` fires `objectWillChange` twice per log line (GameState.swift:2040-2044). Every dice roll re-renders ~10 CombatUI subviews + `BattleSceneView.updateUIView`. Delete the redundant `send()`; longer term split hot/cold state.
- **Mini-games burn ~50 body-evaluations/sec** from 3-4 stacked cosmetic timers at 14-20 Hz (MatrixMiniGame.swift:979-1007 + 4 siblings). Replace pulse/glitch timers with `TimelineView(.animation)`.
- **ChiptunePlayer synthesizes PCM sample-by-sample on the main actor 10×/sec** — up to 3 fresh buffers/tick, ~4,000-iteration fill loops, while the UI re-renders at 50 Hz (ChiptunePlayer.swift:259-350). The note set is static — precompute ~15 buffers.
- **Unbounded image caches** — brawl + hoverbike caches hold tens of MB of decompressed 768×768 frames forever (BasementBrawlScene.swift:1175-1196, HoverbikeChase.swift:253-264). Use `NSCache` or flush on disappear.
- **`BattleSceneView.Coordinator` leaks a notification observer per mission** — block-observer token discarded, no `deinit` (ShadowrunGameApp.swift:2876-2896). BattleScene itself does this correctly.
- **Mission JSON parsed 2-3× per mission start, synchronously** — MissionSetupService, RoomManager, and BattleSceneView each re-parse; `MissionLoader` has no cache and the miss path does directory listings (MissionSetupService.swift:14, RoomManager.swift:78, ShadowrunGameApp.swift:2834/2861, MissionLoader.swift:172-211). Memoize per mission id.
- **~270 SKShapeNode scanlines + per-tile glowWidth stacks** — `glowWidth` shapes each force an offscreen blur pass; doors/extraction/terminals also run `repeatForever` pulses (BattleScene.swift:177-198, 2431-2444; TileMap.swift:560-682). Bake static overlays to one texture via `SKView.texture(from:)`.
- **Per-load disk decodes bypass every cache; no texture atlases anywhere** — `loadHeliTexture` does `UIImage(contentsOfFile:)` per call (4/room + 26/extraction); terminal sprites decode 6 PNGs per tile per room build (BattleScene.swift:968-988, 427-432, 494-500; TileMap.swift:405-413). Memoize in SpriteManager; move frame sets to atlases.
- **Shop rows load icon PNGs from disk inside `body`** per row per re-render (ShadowrunGameApp.swift:212-222, 770).
- **Title-screen Matrix rain** redraws the whole Canvas at 20 Hz and calls `UIScreen.main.bounds` per element per tick while the menu idles (ShadowrunGameApp.swift:1243-1254).
- **Pathfinding nits (low — board is only 7×14):** string keys allocated per BFS node, walkability scans rosters linearly, boss AI re-runs full BFS per movement step, three near-identical BFS copies (Game/PathingAndAIHelpers.swift:28-38, 138-253; EnemyAI.swift:486-498). Int keys + occupied-set + one path per turn.
- **Latent trap:** `loadTileTexture` (no cache, would re-decode a 1024×1536 sheet per call) is currently dead code — delete or cache before reviving (SpriteManager.swift:579-606, TileMap.swift:84-114, 180).
- **Extraction safety timer never cancelled; `playerInputLocked` only reset by the 17s timer** ~3.6s after the animation ends — the door/ladder/rooftop variants do it correctly (BattleScene.swift:721-729, 757-762).

## Verified non-issues (don't "fix" these)

- `BattleScene.update()` per-frame work is cheap and guarded (trace visuals early-return).
- Room background textures are cached and deliberately bounded (SpriteManager.swift:53-68).
- BattleScene's own notification observers are correctly removed in `deinit`.
- `combatLog` capped at 50 entries; `SFXManager.cache` bounded by shipped clip count.
- `dlog` compiles out in Release.
- VN scene visual style is deliberately mirrored and consistent.

## Quick wins (under ~5 lines each)

1. Portrait: use the existing `BasementBrawlSpriteCache` — fixes the worst hitch in the game
2. Delete the redundant `objectWillChange.send()` in `addLog`
3. `SKAction.group` → `.sequence` in `screenShake`
4. `overwatchers.removeValue(forKey:)` after a reaction shot
5. Move `applySignalAction()` below the hack guards
6. Call `fadeOutEnemyPhaseTint()` in the 16s timeout branch
