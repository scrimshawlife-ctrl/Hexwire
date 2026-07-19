# Build Baseline Report — WP1

**Date:** 2026-07-18
**Branch:** `stabilize/wp1-clean-build` (base: `main` @ `2d680e3`)
**Status:** All build legs directly executed. No inferred results in the gate table.

## Environment

```yaml
macos: 26.5
xcode: 26.6 (build 17F113)
ios_simulator_runtime: iOS 26.5 (26.5 - 23F77)
xcodegen: 2.45.4 (Homebrew)
iphone_simulator_used: iPhone 17
ipad_simulator_used: iPad Pro 13-inch (M5)   # packet's "M4" not installed; real installed device used
```

## Project generation

- `xcodegen generate` run from clean tracked state → regenerated `HexWire.xcodeproj`.
- **Determinism verified:** a second consecutive `xcodegen generate` produced byte-identical
  output (no additional diff).
- Regenerated project committed as `fa0bf0d`, resolving WP0-B1: `HexWireTests` bundle id
  is now `com.hexwireaaron.tests`, matching `project.yml` (canonical source).
- **Drift after commit: NONE** — regeneration from `project.yml` now reproduces the tracked
  project exactly.

## Build legs (all with fresh, isolated DerivedData)

| Leg | Command (abridged) | Exit | Warnings | Errors | Result |
|---|---|---|---|---|---|
| Debug / iPhone 17 sim | `xcodebuild -project HexWire.xcodeproj -scheme HexWire -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/HexWireDerivedData build` | 0 | 37 | 0 | **PASS** |
| Debug / iPad Pro 13" (M5) sim | same, destination `iPad Pro 13-inch (M5)`, `-derivedDataPath /tmp/HexWireDerivedDataIPad` | 0 | 37 | 0 | **PASS** |
| Release / generic iOS Simulator | same, `-configuration Release -destination 'generic/platform=iOS Simulator'`, `-derivedDataPath /tmp/HexWireDerivedDataRelease` | 0 | 66 | 0 | **PASS** |
| Unsigned archive / generic iOS device | `-configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/HexWire.xcarchive CODE_SIGNING_ALLOWED=NO archive` | 0 | 38 | 0 | **PASS** — archive contains `Info.plist`, `Products`, `dSYMs` |

- Worktree verified clean (`git status --short`) after all legs — builds do not mutate
  tracked source.
- Release warning count (66) exceeds Debug (37) because Release compiles multiple
  architecture slices, duplicating per-file warnings — no Release-only warning classes
  were observed.

## Warning classification (per packet §5.4)

| Class | Count (unique) | Detail | Disposition |
|---|---|---|---|
| OTHER (code quality) | 1 warning × 27 sites | `result of call to 'fireOverwatchShot(atEnemy:attackerId:)' is unused` | Real signal; candidate for `@discardableResult` or handling — defer to WP4 (it touches combat authority surface) |
| OTHER (dead code) | 6 sites | `will never be executed` | Candidate cleanup in WP5 decomposition |
| CONCURRENCY | ~18 sites | main-actor / `Sendable` violations around `AVAudioPlayer`, fade timers, `shared` accessors (SFX/music layer) | Real Swift-6 readiness debt; defer to a scoped pass — not build-blocking |
| DEPRECATED_API | 3 sites | `onChange(of:perform:)` deprecated in iOS 17 | Low risk; fix opportunistically |
| CONFIGURATION | 7 groups × 2 | Xcode: file references (`Game`, `UI`, `Sprites`, …) are "a member of multiple groups (\"ShadowrunGame\" and \"\") — malformed project" | Emitted by the XcodeGen-generated project (folder references also listed at top level). Harmless to builds; should be fixed in `project.yml` group layout. Tracked as WP1-B1 |
| CONFIGURATION | 1 × 2 | `Metadata extraction skipped. No AppIntents.framework dependency found.` | Benign toolchain notice |
| MISSING_RESOURCE | 0 | none observed | — |
| SIGNING | 0 | none (signing disabled by design for archive leg) | — |
| EXPECTED_PROBE | 0 in build logs | (runtime frame-probe warnings exist at app runtime, not compile time) | — |

No warnings were suppressed. No missing-resource warnings exist to suppress.

## Open items from WP1

```yaml
WP1-B1:
  item: XcodeGen group layout produces "member of multiple groups" project warnings
  severity: cosmetic (build-correct, warning noise)
  resolution_path: adjust project.yml groups; verify warning disappears; any WP
WP1-B2:
  item: 27-site unused-result warning on fireOverwatchShot
  severity: minor code-correctness signal
  resolution_path: WP4 (overwatch is an authority path; handle result or annotate)
```

## Exit gate

```yaml
WP1:
  xcodegen: PASS
  debug_build_iphone: PASS
  debug_build_ipad: PASS
  release_build: PASS
  unsigned_archive: PASS
  generated_project_drift: NONE   # regenerated project committed; regen is deterministic
```
