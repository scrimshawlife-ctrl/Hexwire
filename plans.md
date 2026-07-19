# Current Mission

Ship-readiness: the stabilization campaign (WP0–WP10) is complete through WP9.
The repo is a **stabilized vertical slice** — reproducible builds, hosted CI,
94 deterministic tests, machine-certified missions, certified persistence,
tightened authority seams, and a hygienic repository. Remaining work is the
WP10 release-candidate gate plus the owner's device pass.

# Current Verified Baseline

- Every PR runs `hexwire-ci`: hygiene, XcodeGen 2.45.4 drift gate + full test
  suite (pre-booted simulator), Debug/Release × iPhone/iPad builds, unsigned
  archive. `main` is only advanced through green PRs.
- 94 tests / 0 flaky: dice determinism (seed-injectable RNG), turn/authority
  exactly-once guards, economy math, persistence + migrations (incl. the fixed
  veteran-save decode bug), seeded replay rerolls, spawn placement, per-mission
  end-to-end certification (all 6 missions: setup → every room → clear →
  extract → payout → persist → defeat path).
- Runtime smoke: all 6 missions autostart and render on iPhone 17 + iPad Pro
  13" (M5) sims (`SR_AUTOSTART_MISSION_ID`).
- Evidence lives in `docs/audit/` — start with `CurrentRepositoryBaseline.md`
  and `MissionCertificationMatrix.md`.

# Active Work Package

WP9 — Documentation Reset (this change). Then WP10: Release Candidate Gate.

# Completed Work Packages

| WP | Deliverable | Evidence |
|---|---|---|
| WP0 repo truth | canonical workspace, weight analysis | docs/audit/CurrentRepositoryBaseline.md, PR #19 |
| WP1 clean build | 4 build legs from fresh DerivedData, zero-drift project | docs/audit/BuildBaselineReport.md, PR #20 |
| WP2 test baseline | 43 new tests, DiceEngine seed seam, spawn-spread fix | docs/audit/TestCoverageMap.md, PR #21/#24 |
| WP3 hosted CI | hexwire-ci workflow, 7 jobs green | .github/workflows/hexwire-ci.yml, PR #22/#24 |
| WP4 authority seams | intent facade, zero direct mutations from presentation | docs/audit/GameStateAuthorityMutationLedger.md, PR #23/#24 |
| WP5 decomposition | GameState −497 / CombatUI −1,775 lines, pure moves | docs/architecture/StabilizationExtractionMap.md, PR #26 |
| WP6 mission certification | all 6 missions machine-certified + sim smoke | docs/audit/MissionCertificationMatrix.md, PR #25 |
| WP7 persistence | upgrade data-loss bug found+fixed, 10/10 cases | docs/audit/PersistenceCertificationReport.md, PR #27 |
| WP8 repo hygiene | 16 legacy branches deleted, evidence out of tree, LFS decision recorded | docs/audit/RepositoryWeightAndAssetReport.md, PR #28 |

# Open Blockers

- Owner device pass (touch combat feel, VN/mini-game scenes, on-screen ranged
  damage numbers, audio mix) — listed in MissionCertificationMatrix.md.
- Ship-build config: flip `devUnlockAllMissions` to false (HexwireApp.swift)
  when cutting a release candidate.
- Git LFS adoption: deferred owner decision (costs in RepositoryWeightAndAssetReport.md).

# Next Three Actions

1. Run WP10: assemble the release-candidate gate report from the WP0–WP9
   evidence and issue the verdict.
2. Owner device pass on real iPad; file findings as issues.
3. Decide LFS (or explicitly accept the ~1 GiB clone) before the next asset push.

# Validation Receipt

Latest full validation: 94/94 tests green + all CI jobs green on every WP PR
(#19–#28); see the hexwire-ci history on GitHub Actions for per-run receipts.

# Handoff

Read `AGENTS.md` for workflow rules. The most important invariants: GameState
is the only authority (presentation emits intents via `Game/GameIntents.swift`),
run `xcodegen generate` after any file add/remove, and nothing merges without
green CI. Historical handoffs live in `docs/archive/` — they describe past
states; do not act on them.
