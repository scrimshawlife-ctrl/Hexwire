# Release Candidate Gate Report — WP10

**Date:** 2026-07-19
**Gate evaluated at:** `main` @ `77c5dad` (WP0–WP9 merged)
**Final local receipt:** full suite from fresh DerivedData on this exact sha —
94 tests, 0 failures. Hosted CI: every WP PR (#19–#29) ran the full 7-job
`hexwire-ci` pipeline green; a main-push run executes the same jobs on merges.

## Mandatory gate

| Gate item | Status | Evidence |
|---|---|---|
| clean_checkout_build | **PASS** | every CI job builds from a fresh checkout; WP1 local baseline from clean DerivedData |
| xcodegen_regeneration | **PASS** | pinned XcodeGen 2.45.4 drift gate green on every PR since WP3 |
| unit_tests | **PASS** | 94/94, 0 flaky; re-verified on `77c5dad` with fresh DerivedData |
| hosted_ci | **PASS** | `.github/workflows/hexwire-ci.yml`, 7 jobs, green on PRs #19–#29 |
| debug_iphone | **PASS** | CI matrix (Debug/iPhone) + WP1 local receipt |
| debug_ipad | **PASS** | CI matrix (Debug/iPad) + WP1 local receipt |
| release_build | **PASS** | CI matrix (Release × both device classes) |
| archive_validation | **PASS_OR_SIGNING_ONLY_BLOCKER → PASS unsigned** | unsigned generic-iOS archive green in CI every PR; signing is an owner/App Store step outside stabilization scope |
| all_missions_certified | **PASS** (automated surface) | WP6: all 6 missions machine-certified end-to-end at authority level + 12/12 sim launch smoke on both device classes; touch-layer items explicitly listed for owner device pass |
| save_migration | **PASS** | WP7: all 10 packet cases incl. legacy-install upgrade simulation; veteran-save decode bug found and fixed with regression tests |
| duplicate_reward_protection | **PASS** | paidThisRun latch + exactly-once finalize, tested per-mission |
| authority_high_risk_paths | **STABILIZED** | WP4 intent facade; zero direct GameState mutations from Rendering/UI (scan-verified); safeguard tests per path |
| repository_hygiene | **PASS** | WP8 + CI-enforced; 16 legacy branches deleted; evidence out of tree |
| documentation_current | **PASS** | WP9; docs point at live evidence, stale handoffs archived |

## §5.5 debug-leakage check (Release builds)

- `SR_AUTOSTART_MISSION_ID` debug autostart: **compile-gated** (`#if DEBUG`) — absent from Release. PASS.
- Debug overlays/diagnostics toggles: gated or dev-menu scoped. PASS.
- `devUnlockAllMissions = true` (HexwireApp.swift): **NOT compile-gated — ships in Release,
  unlocking every mission.** This is intentional owner policy during the playtest phase
  (kept ON to jump to late missions; flip OFF only for an actual ship build). It is the
  single §5.5 item that blocks RC eligibility and is a one-line change when the owner
  calls the ship build.

## Verdict

```yaml
verdict: STABILIZED_VERTICAL_SLICE
release_candidate: CONDITIONAL
```

`RELEASE_CANDIDATE_ELIGIBLE` is **not** claimed, per the no-phantom-validation rule,
because two items lack direct evidence or are deliberately deferred:

1. **Owner device pass** (touch-driven combat feel, VN/mini-game scenes end-to-end,
   on-screen ranged damage numbers, device audio mix) — machine-unverifiable surface,
   listed in `MissionCertificationMatrix.md`.
2. **Ship-build config:** flip `devUnlockAllMissions` to `false` (and ideally gate it
   `#if DEBUG`), then re-run CI + archive. One line + one green run.

(Signing/App Store metadata are additionally required for an actual submission but sit
outside the packet's scope by its own `PASS_OR_SIGNING_ONLY_BLOCKER` definition.)

**Path to RELEASE_CANDIDATE_ELIGIBLE:** complete the device pass (file/fix any findings),
flip the unlock flag, one green CI run + unsigned archive on the resulting sha. Nothing
else is outstanding.

## Campaign definition-of-done — status

- clean clone regenerates and builds ✅ (CI, every PR)
- tests pass in hosted CI ✅ (94/94)
- all missions certified ✅ (automated surface; device-pass list explicit)
- save and migration behavior tested ✅ (incl. a fixed real data-loss bug)
- high-risk authority mutations routed through intent APIs ✅
- repository-generated artifacts controlled ✅ (drift gate + hygiene job)
- iPhone and iPad behavior verified ✅ (build matrix + launch smoke + screenshots)
- release configuration clean ✅ except the documented owner-held unlock flag
- documentation reflects actual state ✅
- final release-candidate gate report exists ✅ (this document)

The repository now repeatedly proves that it is playable, deterministic,
recoverable, and buildable — which is the campaign's definition of complete.
