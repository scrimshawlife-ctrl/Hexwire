# ShadowRune codebase analysis — round 3 (2026-06-10)

Coverage: mini-game gameplay logic, concurrency/timing in combat flow, adversarial review of the day's six big fixes (all HOLD; three adjacent drain-death gaps found and fixed same-day: hack/blitz/grenade crit-glitches now route through handlePlayerKilled).

## Concurrency (combat flow)

**Root cause for the top findings:** `GameState.shared` is a singleton, so `[weak gameState]` in deferred closures never nils across abort/restart, `combatEnded` is reset by setup, there is no mission-generation token, and no deferred work is ever cancelled. Recommended shared fix: a `missionAttemptId` bumped in setupMission, captured and checked by every deferred closure.

- **CRITICAL — stale extraction finalize timers auto-win the NEXT mission.** The 14s (CombatFlowController.swift:1629) and 17s (BattleScene.swift:774) timers survive an abort; their `!combatEnded` guards pass against the new mission → instant EXTRACTION SUCCESS, persisted payout/XP, even NG+ advance from M6. The 17s one has no guard at all and also misfires without an abort if the player taps through debrief into the next mission within ~3.6s. Fix: generation token or cancellable DispatchWorkItems cancelled in setup/abort/onComplete.
- **HIGH — aborted enemy-phase stagger closures attack the next mission's roster** (CombatFlowController.swift:1371-1415). Ghost enemies from the dead mission damage/kill the new team before round 1; group.notify then runs beginRound into mid-setup. Fix: token check at top of each closure + group.notify, plus `guard enemy.isAlive, !combatEnded`.
- **HIGH — the 3s force-unblock timer (CombatFlowController.swift:1407) can fire during the NEXT enemy phase** (single-survivor turns are fast), force-opening input mid-phase. Fix: `guard !isEnemyPhaseRunning`.
- **MED-HIGH — no phase guard on endTurn/performAttack** — a queued double-tap on the 4th runner's attack yields a free extra attack during .enemyResolving and double-increments roundNumber/enemyPhaseCount (delayed spawns arrive a phase early). Fix: `guard combatPhase == .playerInput` at top of every perform*, idempotency latch in endTurn.
- **MED — deferred AGI boss spawn (GameState.swift:1970) survives abort/restart** — AGI-PRIME + intro + boss music land in whatever mission is active 2.5s later. Fix: token or current-mission/room guard in the closure.
- **MED — M3 Sato phase 2: room marked cleared BEFORE the deferred boss spawn** (sync onRoomCleared vs async .enemyDied observer) — boss fight happens in a "cleared" room with the door open; nothing re-locks it. Fix: check mageBossPhase2 synchronously in kill paths, or have spawnSatoBoss call unmarkCurrentRoomCleared.
- **MED-LOW — enemies killed by overwatch keep walking** — no isAlive re-check after overwatch volleys in any EnemyAI movement branch; corpse model position changes post-mortem. Fix: `if !enemy.isAlive { return }` after each volley.
- **LOW** — 16s input watchdog can trip during a legitimately long (23+ enemies) phase; extraction adjudicated from group.notify falls through to beginRound and re-enables CombatUI buttons during the heli animation; snapshot-equality auto-clear timers (bossIntro 30s, transient warnings) can dismiss a re-presented overlay from a previous attempt.
- Verified sound: DispatchGroup enter/leave balance, extraction double-start latch, overwatchers value-copy iteration, BattleScene observer teardown.

## Mini-game logic

- **HIGH — PacketRouter shields never protect** (PacketRouterMiniGame.swift:703): `|| $0 == packetNodeId` explicitly lets ICE hop onto a shielded node exactly when the player rests there — the advertised core mechanic doesn't exist. Fix: drop the clause.
- **HIGH — Mirrorline: a WRONG sigil still banishes the spirit** (MirrorlineScene.swift:1446) — `banished += 0.15` is treated as "fading, cull" everywhere. Fix: separate hit-flash field.
- **HIGH — LaneRunner infinite mid-air jump** (LaneRunnerMiniGame.swift:903): no grounded check; airborne players are immune to all hazards. Fix: guard on `playerJumpY == 0 && playerJumpVel == 0`.
- **HIGH — GlyphPattern input stays live during the wrong-tap replay window** (GlyphPatternMiniGame.swift:475-495): finish from a stale index, stack strikes, and overlap concurrent playbacks. Fix: flip phase immediately + generation counter on replay closures.
- **MED — Mirrorline lose-after-win**: boss attack machine keeps running during the 1.6s death beat — a pending P3 timeout can kill a 1-HP player after the boss died; defeat is recorded, victory swallowed, recordVictory skipped (MirrorlineScene.swift:1112-1186). Fix: resetBossAttack() + guard on bossDefeated.
- **MED — Hoverbike i-frames stale within one collision pass** (HoverbikeChase.swift:1552): rammer+mine+tracer in one frame = 3 hits = instant death. Fix: re-check/early-return inside takeHit().
- **MED — Matrix stage-1 spawn is inside a wall** (MatrixMiniGame.swift:41 vs 158): player starts unkillable in a wall block. Fix: spawn or map row.
- **MED — ColdTrace boss casts eat all tool taps** (ColdTraceScene.swift:1300): processes expiring during P1/P2 casts are uncounterable; matching taps are punished as wrong deflects. Fix: fall through to triage when the tap matches a live process.
- **MED — AGIFaceoff punishes taps near INVISIBLE dormant zones** (AGIFaceoffMiniGame.swift:904-951 vs 608). Fix: no penalty for .dormant.
- **LOW** — GlyphPattern finishGame lacks the reentry guard every sibling has (BAIL can fire onComplete twice); AGIFaceoff wave pacing silently capped at 2.0s by the despawn rule (tuned 2.6s base never applies; dead waveSpawnTimer); CypherCracker score deducts only final-level misses despite "LIFETIME" comment.
- Wiring verified: router games → onComplete → resolveMatrixMiniGame (single path); standalone scenes record via guarded finishGame/endGame (single-fire) except the Mirrorline #5 path.

## Fix review (today's six fixes)

All HOLD under adversarial review — details: M1 barrier set is reset on load+unload, currentRoom is correct at both re-apply sites, no marker desync (only M1 defines removeOnFirstKill, plain walls); no archetype falsely matches hasPrefix("boss"); stun vent arithmetic verified for wil 2-6 (Shock can still double-stun, Decker hack lock intact); all three loot-removal sites call consumeRosterItem, grenade fail path re-inserts identical struct, nothing compares Item with ==; half-missions route through DebriefView and have real store entries; handlePlayerKilled is idempotent and the dead-active-character span is safe.

Follow-ups noted:
- Replay payout overclaim remains: victoryText/rewardText show full amounts while recordVictory pays ¥0 on replays (needs OutcomePipeline to stash the actual credited amount).
- Roster (and thus consumable depletion) persists only on victory — defeat/abort restores used stims. Coherent, but worth a design decision.
- FIXED same-day: hack (GameState.swift ~1648), blitz (~1721), grenade (~1578) crit-glitch self-damage now routes through handlePlayerKilled, matching heal/fireball/single-target.
