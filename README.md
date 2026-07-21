# HexWire

> Tactical cyberpunk hex-grid RPG for iOS — SwiftUI + SpriteKit.
> A pressure-driven combat loop where every action trades power for exposure:
> **Signal → Power → Trace → Escalation → Lay Low → Tempo Tradeoff.**

## Current state

```yaml
product_name: HexWire
platform: iOS (iPhone + iPad)
minimum_os: iOS 17.0
current_state: STABILIZED_VERTICAL_SLICE   # was ADVANCED_PLAYABLE_PROTOTYPE pre-2026-07
latest_verified_commit: see the latest green hexwire-ci run on main
latest_build_result: PASS — Debug+Release × iPhone+iPad + unsigned archive, hosted CI on every PR
latest_test_result: PASS — 94 deterministic tests, 0 flaky (unit + per-mission certification)
mission_certification: docs/audit/MissionCertificationMatrix.md (all 6 missions machine-certified;
  touch-layer items listed for device pass)
supported_devices: iPhone (portrait, compact) + iPad (regular); verified on
  iPhone 17 and iPad Pro 13-inch (M5) simulators, iOS 26.5
known_release_blockers:
  - owner device pass for touch-layer items (see certification matrix)
  - devUnlockAllMissions=true must be flipped OFF for a ship build (HexwireApp.swift)
  - App Store signing/metadata (outside stabilization scope)
```

## Working on this repo

- **Project generation:** `HexWire.xcodeproj` is generated from `project.yml` by
  **XcodeGen 2.46.0**. After adding/removing files: `xcodegen generate` and commit
  the regenerated project — CI fails on drift.
- **Build:** `xcodebuild -project HexWire.xcodeproj -scheme HexWire -destination
  'platform=iOS Simulator,name=iPhone 17' build`
- **Test:** same command with `test`. If running repeatedly, pre-boot the
  simulator (`xcrun simctl boot <udid> && xcrun simctl bootstatus <udid> -b`) —
  cold-sim launches flake before tests run.
- **CI:** `.github/workflows/hexwire-ci.yml` runs hygiene checks, the XcodeGen
  drift gate + tests, a Debug/Release × iPhone/iPad build matrix, and an
  unsigned archive on every PR.
- **Architecture rule:** `GameState` is the single gameplay authority. UI and
  SpriteKit layers emit intents (`Game/GameIntents.swift`) and render from
  state — never mutate authority state directly. See
  `docs/audit/GameStateAuthorityMutationLedger.md`.
- **Debug autostart:** DEBUG builds honor the `SR_AUTOSTART_MISSION_ID`
  environment variable (e.g. `Mission003`) to launch straight into a mission.

## The game

Four runners (street samurai, mage, decker, face) run six authored multi-room
missions plus interstitial scene-missions, with a persistent economy (nuyen,
black market, cyberware), faction heat that carries between missions, seeded
replay rerolls, an endless gauntlet, and New Game+ scaling. The trace/heat
pressure loop is documented in `docs/TraceSystem.md`.

![Loop](docs/assets/hexwire-loop.svg)

## Documentation map

| Doc | What it is |
|---|---|
| `plans.md` | Current mission, verified baseline, next actions |
| `AGENTS.md` | Contributor/agent workflow rules |
| `docs/audit/` | Stabilization evidence: repo baseline, build baseline, test coverage map, authority ledger, mission certification, persistence certification, repo/asset report |
| `docs/architecture/StabilizationExtractionMap.md` | Decomposition status + deferred candidates |
| `docs/TraceSystem.md` | Trace/heat pressure-loop design |
| `docs/archive/` | Historical audits and handoffs (superseded — do not act on) |
