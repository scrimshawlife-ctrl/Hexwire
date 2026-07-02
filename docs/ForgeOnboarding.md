# Forge Onboarding

Short pointer doc for Forge (Codex Cloud) picking up HexWire from the prabu-openclaw side of the handoff. Read in this order:

1. `../AGENTS.md` — branch naming, commit format, validation ladder.
2. `../plans.md` — active priorities and decision history.
3. `TurnAuthorityReport.md` + `TraceSystem.md` — core gameplay invariants. Touch these before editing combat or escalation code.
4. `legacy/pre-handoff-*.md` — historical design notes authored before the extraction/trace overhaul. Context only, not authority.

## Repo facts

- Canonical remote: `https://github.com/scrimshawlife-ctrl/HexWire`. The prabu-openclaw URL redirects here.
- Default branch: `main`. Feature work lands via `codex/<topic>` or `feature/<scope>` branches + PR.
- Xcode 26.4 (Swift 6 toolchain) is the local build target. `project.yml` drives `HexWire.xcodeproj` via xcodegen.

## Local build recipe (for the prabu-openclaw mini)

```
cd /Users/prabu/.openclaw/workspace/workspace-coding/HexWire
xcodegen generate
xcodebuild -project HexWire.xcodeproj \
  -scheme HexWire \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

`BUILD SUCCEEDED` as of commit `3c67b3c`.

## What just landed (commits `c49fd8f…3c67b3c`)

- `docs/legacy/` archive of the pre-handoff overhaul + spec notes.
- `project.yml` sources narrowed to Swift tree + `Sprites/`; `build/`, `.git/`, `docs/`, `scripts/`, `tests/`, `screenshots/`, and recursive `*.md` / `*.DS_Store` are now excluded.
- Unterminated string literal in `Game/CombatFlowController.swift:129`.
- `@MainActor` on five helper structs that touch the `@MainActor`-isolated `GameState`: `CombatFlowController`, `ExtractionController`, `MissionSetupService`, `OutcomePipeline`, `PathingAndAIHelpers`.
- `BattleScene.placeCharacter` / `placeEnemy` reordered to match `SpriteManager.createCharacter(type:team:...)`.

## Known cleanup items (good first picks)

- No `.gitignore` in the repo. `build/` and multiple `HexWire.xcodeproj.backup-*` directories are committed. A `chore(repo)` PR to add a Swift/Xcode `.gitignore` and stop tracking these would be high-value.
- `tests/test_consequence_engine.swift` uses `XCTest` but there's no test target — currently excluded from the app target. A real `HexWireTests` target in `project.yml` would unlock CI validation.
- `screenshots/` ships a lot of PNGs; not referenced at runtime but not gitignored either.

## Validation before PR

Per `AGENTS.md`, if full iOS build is not available mark `NOT_COMPUTABLE`. From the mini, the xcodebuild command above is the authoritative check.
