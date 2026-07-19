# HexWire codebase analysis — round 4 (2026-06-10)

Coverage: audio stack (MusicManager/SFXManager/HapticsManager/ChiptunePlayer), SpriteManager animation system (~2,700 lines), persistence layer (RosterStore/NGPlusStore/MissionStatsStore, Character Codable, UserDefaults).

## Audio (findings 1–4 FIXED same-day; 5–10 open)

1. **FIXED — fade() silently cancelled in-flight fade completions.** Completions are load-bearing (start-next-track after crossfade, teardown after stop). Now: `pendingFadeCompletion` is delivered (jump-to-end) when superseded; explicit `stop()` drops it via `discardPendingFade()`; fade timers self-invalidate when their player is replaced; the start functions (`startTrack`/`startLoopingTrack`/boss path) defer to `deferredResumeKind` when a duck landed mid-crossfade; `DeferredKind.loop` now carries `loopEnd`.
2. **FIXED — wall-clock track-end timers died across ducks (permanent silence) or cut tracks short.** `scheduleEndObserver` + new `scheduleBossHandoff` now schedule from remaining *playback* time, flag `endObserverNeedsRearm` when firing against a paused player, re-check live position when playback lags wall-clock, and `unduck()`/`resumeForeground()` re-arm via `rearmEndObserverIfNeeded()`.
3. **FIXED — no route-change handling.** `AVAudioSession.routeChangeNotification` (.oldDeviceUnavailable) now triggers the same resume path, so unplugging headphones no longer silences the game until app cycle.
4. **FIXED — interruption recovery only covered the music player.** `resumeForeground()` now also resumes `SFXManager.loopPlayers` (new `resumeLoops()`); ChiptunePlayer observes interruption-end + route change and restarts its engine (`restartEngineIfNeeded()`, observers removed in stop()/deinit); interruption `.began` finishes the active fade deterministically; `.ended` respects `.shouldResume` when options are provided.

Open (5–10): mini-games permanently flip the audio session to `.mixWithOthers` (ChiptunePlayer sets category per open, never restores — configure session once at app start); missing chain file = unrecoverable silence (`currentTrackId` committed before load succeeds — commit after, fall back to other slot); `unduck()` drops per-track volume boost (M2 ~25% quieter after any mini-game); `loopEnd` custom looping dies across backgrounding (wall-clock re-arm chain with isPlaying guard); missing SFX file re-runs full bundle search + log per call (negative-cache); mix bookkeeping scattered (per-clip gain table; chiptune 0.397 hardcoded to mirror targetVolume).

## SpriteManager (all open)

- **HIGH — hit flash restores stale HP-bar color** (SM:2266-2278): flash captures fillColor before updateHP sets the new band color, then writes the old color back 0.15s later — bar lies until next damage event. Fix: skip hpBar nodes in flash loop or re-apply updateHP after.
- **HIGH — death doesn't cancel in-flight actions** (SM:2519): overwatch kills mid-move produce a sliding corpse that resumes idle. Fix: removeAction(forKey:"move") + clear anim keys at top of animateDeath.
- **MED-HIGH — unkeyed color flashes stack/re-enter** — second flash mid-flash captures white as the "base" color; rings/hexes stick white until rebuild. Fix: fixed action key + stash true base color in userData.
- **MED** — animate* entry points don't clear all cross-state keys (hit-pose resume fires mid-attack, two texture loops fight); fallback resumes use absolute scale(to:) on scaled/mirrored child (samurai un-mirrors if a frame set is short); `bossmage` sized 130pt but missing from BattleScene's boss HP-bar list (bar across torso, BS:2753); enemy depth-z never refreshed after movement (wrong occlusion until rebuild).
- **MED-LOW** — sprite outline is 4 static idle_0 copies → ghost afterimage on every non-idle pose (known for bruiser, still on for everyone else); player frames force-filtered .nearest via the enemy texture factory (edge shimmer; the other path uses .linear).
- **LOW** — unknown archetypes silently render as guards (no log); 1-frame idle sets freeze silently; enemy walk falls through to the container bounce which pulses the HP bar; dead API (cropToCharacterBounds with a latent byte-order bug, updateHP's ignored level/isPlayer params, write-only currentState, unused emoji maps); HP-bar stagger keyed to mutable enemies-array index.
- Verified clean: shared-archetype texture caches, UUID-suffixed HP-bar children, node renaming neutralizes name collisions.

## Persistence (all open)

- **HIGH — no save versioning; any roster decode failure silently wipes progression then overwrites the blob** (MissionStatsStore.swift:303-318 `try?` → `Character.allRunners` fallback; 12 required decode keys in Character). Fix: versioned envelope, do/catch + log, last-good backup key before overwrite, decodeIfPresent for new fields.
- **HIGH/MED — factionAttention (world-reaction layer) never persisted** and Fresh Start doesn't reset the live value — force-quit between missions = amnesia (GameState.swift:922, consumed by MissionSetupService:753).
- **MED** — MissionStatsStore.load() swallows corruption → ¥0 wallet, then next save overwrites; `consumeRosterItem` depletes by name in team order → can remove the WRONG runner's purchase (tag GameState.Item with owner UUID when seeding); `Item.uses` persisted but dead (2-use medkit is 1-use).
- **LOW** — victory save serializes mid-combat residue (dead status/0 HP) into the canonical roster — TEAM screen shows 0/22 HP between missions via loadCanonical (freshen before saving); ColdTrace mutates GameState.shared.dataAcquired between missions; chase backfill marks M3.5 completed but not paid.
- Verified safe: shop purchases save immediately (kill-app-safe); Character CodingKeys currently complete; Fresh Start coherent (except live factionAttention); no profiles → no cross-save leakage; corruption never crashes launch.
