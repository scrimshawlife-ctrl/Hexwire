# HexWire codebase analysis — round 2 (2026-06-10)

Coverage: app shell (HexwireApp.swift), missions/flow (Missions/, ExtractionController, OutcomePipeline, ConsequenceEngine, ReinforcementService, MissionStatsStore), progression/entities (Character, Weapon/Armor/Spell, loot, damage model), plus an adversarial review of the round-1 fixes.

## Fix review verdict (round-1 changes)

Sound overall. One genuine regression found and **patched same day**: `fireOverwatchShot` consumed the overwatch even when the target (or the shooter) was already dead — with multiple overwatchers on one mover, the first kill wasted everyone else's shot. Fixed with an `enemy.isAlive, attacker.isAlive` guard (GameState.swift, fireOverwatchShot), which also kills a pre-existing corpse-shot double-kill-count. Cosmetic patch alongside: computed `isDefending` now keys off `activeCharacterId` first to match the HUD's StatusDisplay lookup.

Everything else verified: defend survives into the enemy phase (beginRound runs after the phase completes), initiative order exists from round one (MissionSetupService calls beginRound), fireball loses no mana/turn on the no-target return, observer/recognizer lifecycles correct, contract-script failures all pre-existing.

Known cosmetic change: overwatch misses now render like deliberate-attack misses (flinch + "MISS" text) instead of nothing.

## HIGH

1. **M1 softlock — barriers return permanently on room re-entry.** `removeOnFirstKill` barrier drops only mutate live tiles; re-entering room_1 re-derives tiles from JSON and there are no enemies left to re-trigger the drop — door to room_2 permanently unreachable (Mission001_multi.json + BattleScene.swift:1305 + CombatFlowController.swift:1237-1252). Fix: track dropped-barrier rooms in RoomManager (mirror `bossDeployedRoomIds`) and re-apply on load.
2. **M4 boss fight skippable.** Boss door-lock checks `bossmage|bossmech|bossagi` but omits `bosscorp` (Vera Koss) — walk out, re-enter (boss never rebuilds), re-clear regulars, mission completes bossless (RoomManager.swift:202). Fix: `arch.hasPrefix("boss")`.
3. **Permanent stun-lock exploit.** AI stun recovery sets `.wounded` without venting `currentStun`; any subsequent hit re-stuns instantly (`takeDamage`'s `currentStun >= maxStun` check). One Shock + ordinary attacks locks a boss out indefinitely (EnemyAI.swift:135-138 + TurnManager.swift:342-343). Fix: vent the track on recovery, or only set `.stunned` when stun damage was applied.
4. **Heal crit-glitch still kills the mage without the death pipeline** (SpellResolver.swift castHeal crit-glitch branch — fireball/single-target have the guard, heal doesn't). Fix: add the same `if !mage.isAlive { handlePlayerKilled }`.
5. **Shop consumables never deplete.** Purchases live in `runner.inventory`; `seedLootFromRoster` re-seeds them into combat loot every mission; consumption only drains the loot pool. One ¥1,500 medkit = infinite supply. `Item.uses` is never read; seed bonuses (10/5/7) contradict item descriptions (HexwireApp.swift:699 + MissionSetupService.swift:612-625).
6. **Mission unlock gating disabled** — leftover `devUnlockAllMissions = true` (HexwireApp.swift:1611); the entire unlock rule is dead code on fresh installs.
7. **Victory/briefing economy is pre-rebalance fiction.** "RUN COMPLETE" overlay reports ¥15k–¥500k vs actual 9k–80k payouts and appends the bonus line even on missed objectives ("✗ DATA MISSED (+¥7,500 bonus)"); BriefingView quotes the same stale numbers (HexwireApp.swift:2191-2215, 1944-1953). Fix: derive both from MissionStatsStore like DebriefView.rewardText already does.

## MEDIUM

- **Kill-path room clear ignores `pendingSpawns`** — authored delayed enemies silently never spawn if you kill the last visible enemy first (GameState.swift:1408 etc.; the enemy-phase path checks correctly).
- **Reinforcement wave can vanish** — queued into an already-cleared room, leaving during the ETA wipes it while `markReinforcementsDeployed` stays set (ReinforcementService.swift:36-101).
- **Locked-extraction tap desyncs sprite from model** — sprite commits the move before `requestExtraction`'s guards reject it; enemies then target the old tile (BattleScene.swift:3525-3531).
- **M6 AGI boss can spawn after you leave the room** (or after defeat) — 2.5s deferred deploy has no current-room/combat-ended guard (GameState.swift:1946-1950).
- **Uncleared-room re-entry respawns enemies at full HP** — re-kills double-count score/XP; door-hopping farms the debrief stats (BattleScene.swift:1209-1259).
- **Multi-room extraction ignores `pendingSpawns`** (single-room checks it) — extract while authored spawns are still due (CombatFlowController.swift:1569-1596).
- **ITM quick-action eats Frag Grenades and Mana Focus as HP heals** — Frag Grenade mistyped `.consumable` in the loot table; no full-HP guard; the picker sheet has the correct logic, the raw button path doesn't (CombatFlowController.swift:1440-1450 + GameState.swift:306-307).
- **Single-target spells have no range/LOS check** — Mana Bolt/Shock snipe through walls map-wide while Fireball now enforces range 6 + LOS (SpellResolver.swift:104-114). Fix: same candidate filter as fireball; nearest-enemy fallback.
- **Loot drop weights are dead** — `randomElement()` ignores the `chance` column; permanent gear drops as often as medkits (GameState.swift:303-322).
- **M3 boss Sato's Bloodbolt is stun damage** — typed `.unarmed` so `isStunDamage` infers stun; the finale boss's opener can't kill (TurnManager.swift:411-412).
- **Enemy stun not in CodingKeys** — save/load wipes enemy stun progress; saved-stunned enemies reload recovered (TurnManager.swift:268-273).
- **Replays display "¥X earned" but credit ¥0** (pay-once-per-campaign is correct, the display isn't); **end-of-run RANK shows historical best, not this run's** (HexwireApp.swift:2944-2947). Fix both by passing actuals from OutcomePipeline.
- **BriefingView has no back button** — ACCEPT CONTRACT is the only exit (HexwireApp.swift:1985-2122).
- **Weapon purchases destroy the displaced gun** — no owned-gear list; switching back costs full price (HexwireApp.swift:658-688).

## LOW

- Room re-entry enemy factory skips `applyEnemyArchetype` (Watcher/Enforcer tweaks lost on re-entry).
- `MissionRecord.attempts` only counts victories.
- Reinforcement tile picker accepts tiles the spawner rejects → BFS relocation can land next to players.
- Weapon-mod loot landed while the SHT sidearm is equipped bypasses the damage-14 cap on carryover.
- Dead content: `Character.spells` legacy strings (Sable's three uncastable spells); TurnManager instance machinery (latent `% 0` crash, drops cyberInitiative if revived).
- Healthy characters' status is `.wounded` (no healthy case exists).
- AK-97 strictly dominated by Monofilament Katana as displayed (real differentiator — firearms vs blades — never surfaced in shop UI).
- `showMatrixMiniGame` never reset by mission setup/abort → can strand the overlay + park menu music.
- FPS display link runs at 60Hz all combat with diagnostics hidden.
- Mission JSON decoded twice per start (MissionSetupService → RoomManager); `setupMultiRoomMission` double-calls `resetCombatOutcomeFlagsForNewMission` and double-sets `traceEscalationLevel`.
- M5 room_2 `_obstacleNote` says bottom entry; JSON routes top (cosmetic).

## Verified clean

All six mission JSONs pass reachability/spawn/door-pairing/extraction tracing. gainXP multi-level loop, derived-stat math, cyberware install dedupe, fireball burn refresh, stun-overflow boundaries: all correct. PhaseManager has no reachable dead-ends; shop double-tap purchase is guarded; Coordinator scene re-presentation check is correct.
