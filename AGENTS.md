# AGENTS.md

How to work in this repository — humans and coding agents alike.
Last reset: 2026-07-19 (stabilization WP9). If something here contradicts
observed reality, fix THIS file in the same PR.

## Architecture invariants (non-negotiable)

- `GameState` is the single gameplay authority. Rendering (`Rendering/`) and
  UI (`UI/`) are projections: they READ state and emit intents — they never
  assign authority properties directly. Intent surface: `Game/GameIntents.swift`
  (`requestEndTurn`, `requestMove`, `requestAttack`, `requestTargetSelection`,
  `requestObjectiveDataAcquired`, extraction intents, `applyRoomEntry`).
  Ledger + rationale: `docs/audit/GameStateAuthorityMutationLedger.md`.
- Preserve the pressure loop: Signal → Power → Trace → Escalation → Lay Low →
  Tempo Tradeoff. Roles modify shared systems; don't build parallel mechanics.
- Randomness must accept a reproducible seed (see `DiceEngine.roll(pool:tn:using:)`
  and the SplitMix64 reroll seeding in `MissionSetupService`).
- Persistence decoding must be tolerant: missing fields default, corrupt blobs
  fall back to `.lastGood`, then to safe defaults — never crash, never
  silently overwrite inspectable data. (WP7 fixed a real veteran-save wipe;
  don't reintroduce the pattern with synthesized Codable on persisted types.)

## Build / test workflow

- The Xcode project is GENERATED: `project.yml` + XcodeGen 2.46.0 →
  `HexWire.xcodeproj`. After adding/removing/renaming files:
  `xcodegen generate` and commit the regenerated project. CI fails on drift.
- Build: `xcodebuild -project HexWire.xcodeproj -scheme HexWire
  -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Test: same with `test`. Pre-boot the sim for repeated runs
  (`xcrun simctl boot <udid> && xcrun simctl bootstatus <udid> -b`) — cold-sim
  launches intermittently fail before tests execute.
- Debug autostart: `SIMCTL_CHILD_SR_AUTOSTART_MISSION_ID=Mission00N
  xcrun simctl launch <udid> com.hexwireaaron.game` (DEBUG builds only).
- Device installs/sideloading: the OWNER does these from Xcode. Build for
  simulator to verify; don't push builds to physical devices.
- Tests-first for behavior changes; every intent path keeps its
  accepted / rejected / duplicate / invalid-input / exactly-once coverage.

## PR rules

- Branch from `main`; small, single-scope PRs; conventional commit style
  (`fix:`, `test:`, `chore:`, `refactor:`, `ci:`, `docs:`).
- Nothing merges without green `hexwire-ci` (hygiene, drift gate + 94-test
  suite, Debug/Release × iPhone/iPad, unsigned archive).
- Merging stacked PRs: merge bottom-up and do NOT delete the base branch
  until its dependents are retargeted (a mid-stack branch deletion closes
  dependent PRs).
- Report validation honestly using: PASS / FAIL / BLOCKED / NOT_COMPUTABLE /
  INFERRED. Never upgrade NOT_COMPUTABLE or INFERRED to PASS.

## Repository policy

- No build products, DerivedData, `.xcuserstate`, backup projects, or
  screenshots in the tree (CI-enforced; evidence goes outside the repo).
- Mission JSON must stay well-formed with unique ids and known enemy types —
  CI validates; `tests/MissionCertificationTests.swift` certifies the deeper
  graph rules.
- `docs/archive/` is history, not guidance.

## Ship checklist (release candidate)

1. Flip `devUnlockAllMissions` to `false` (HexwireApp.swift).
2. Verify Release build carries no debug autostart behavior (it's
   `#if DEBUG`-gated — confirm in the archive).
3. WP10 gate report green (`docs/audit/` evidence current).
4. Owner device pass complete (list in MissionCertificationMatrix.md).
