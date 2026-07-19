# Repository Weight and Asset Report — WP8

**Date:** 2026-07-19
**Branch:** `stabilize/wp8-repository-hygiene`

## Sizes (measured)

```yaml
git_object_store_local: 772 MiB packed (~1.0 GiB .git incl. legacy objects not yet GC'd)
working_checkout: ~0.9 GiB
main_reachable_blobs: 923 MiB (WP0 measurement; all legitimate assets)
asset_weights:
  Sprites/frames: 401 MiB      # the single largest tree
  Assets.xcassets: 240 MiB
  Sounds/music: 129 MiB (~25 tracks, 3.2–4.8 MiB each)
  Sprites/backgrounds: 71 MiB
  Missions JSON: 88 KiB
```

## Actions taken this WP

1. **Legacy remote branches deleted (owner-approved, 2026-07-19):** all 16
   pre-rewrite refs — `legacy-shadowrune`, 9 `codex/*` audit branches,
   `claude/silly-joliot-e95762`, `chore/add-gitignore`,
   `feat/half-missions-and-playtest-fixes`, 3 `fix/*` branches.
   - Effect: fresh clones no longer download the old 87-commit history or its
     ~250 MiB of committed build artifacts (`build/ModuleCache` .pcm files,
     .app products, debug dylibs). GitHub will drop the unreachable objects at
     its next GC.
   - ⚠️ The pre-rewrite Shadowrune history is now unrecoverable **from GitHub**.
     Local copies survive on this machine (`backup/pre-hexwire-local-edits`,
     `checkpoint/m5-boss-room-enemy-variety`, plus the owner's
     `~/Desktop/ShadowrunGame.zip` snapshot from 2026-06).
2. **Screenshot evidence removed from the source tree** (packet-mandated):
   `screenshots/` (112 files, several 3–4 MiB), `screenshot-title.png`,
   `enemy_preview.png`, and scratch file `enemyPhase_new.txt` — 1,318 → 1,224
   tracked files. Verified unreferenced by code/config/CI before removal;
   `project.yml` already excluded them from the app target, so the app bundle
   is unchanged. They remain retrievable from git history.
   `.gitignore` now blocks `screenshots/` and `*.log` from returning.
3. **Verified clean (re-confirmed from WP0):** no tracked build products, no
   user-specific Xcode state, no backup projects, single canonical
   XcodeGen path — and the WP3 CI hygiene job enforces all of it per PR.

## Classifications

| Asset group | Classification | Notes |
|---|---|---|
| `Sprites/frames`, `Sprites/backgrounds`, `Sprites/{tiles,effects,vfx,helicopter,sfx?}` | RUNTIME_ASSET | bundled via folder references |
| `Assets.xcassets` | RUNTIME_ASSET (compiled to Assets.car) | |
| `Sounds/**` | RUNTIME_ASSET | |
| `Missions/*.json` | SOURCE_ASSET | authored content, CI-validated |
| `screenshots/*`, `screenshot-title.png`, `enemy_preview.png` | SCREENSHOT_EVIDENCE | **removed** this WP |
| `enemyPhase_new.txt` | UNUSED (scratch code dump) | **removed** this WP |
| `build/`, DerivedData, xcuserdata | BUILD_ARTIFACT | not tracked; CI-enforced |
| 38 identical-content sprite pairs (e.g. `face_idle_0/2`, `mech_idle_1/3`) | RUNTIME_ASSET (intentional) | animation loops reuse identical frames; deduping would need code changes for ~trivial savings — leave |
| Loose root dev scripts (`capture_build_errors.sh`, `cleanup_stale.sh`, `diagnose_xcode_vs_cli.sh`, `fix_and_verify.sh`, `nuke_sourcekit_index.sh`, `regenerate_xcodeproj.sh`) | GENERATED_DERIVATIVE/dev tooling | excluded from app target; candidates to fold into `scripts/` during WP9's doc pass (kept for now — some are referenced by older docs) |

## Git LFS evaluation (decision: RECORDED — deferred, owner undecided)

**Candidates:** `Sprites/**/*.png` (472 MiB), `Assets.xcassets/**/*.png`
(240 MiB), `Sounds/**` (~130 MiB) — ~840 MiB of the 923 MiB total.

**For:** clones drop to tens of MiB of git data + on-demand LFS pulls; future
asset churn stops compounding pack size (every art iteration currently adds
its full size to history forever).

**Against / costs:** GitHub LFS bandwidth-and-storage quotas (free tier:
1 GiB storage / 1 GiB-month bandwidth — this repo would exceed it immediately;
paid data packs ~$5/50 GiB), migration rewrites history (all current PRs/SHAs
change — best done at a quiet moment right after the stabilization PRs land),
and every clone/CI runner needs `git lfs` installed (GitHub-hosted runners
have it preinstalled).

**Recommendation:** adopt LFS for `Sounds/**` + `Sprites/**` +
`Assets.xcassets/**/*.png` in a single migration commit immediately after WP9
lands, IF the owner accepts the LFS quota cost. Otherwise: accept the ~1 GiB
clone — it is stable (assets rarely churn now) and CI cold-checkout time
(~2–3 min) is tolerable. **No history rewrite of `main` is recommended in
either case** — its 17-commit history is artifact-clean; a rewrite buys
nothing unless LFS migration happens (which implies it).

## Exit gate

```yaml
WP8:
  active_duplicate_workspace: NONE
  tracked_build_artifacts: NONE
  tracked_user_state: NONE
  backup_projects: NONE
  asset_policy: DOCUMENTED    # evidence stays out of the tree; .gitignore + CI enforce
  lfs_decision: RECORDED      # deferred by owner; recommendation + costs documented above
  legacy_branches: DELETED    # 16 refs, owner-approved 2026-07-19
```
