# Current Repository Baseline — WP0

**Date:** 2026-07-18
**Auditor:** Claude (stabilization agent), local macOS environment
**Environment:** macOS 26.5, Xcode 26.6, XcodeGen 2.45.4 (Homebrew)

All findings below are from direct command execution against a synchronized
checkout at `/Users/galadriel/.openclaw/workspace/ShadowrunGame`, unless
labeled `INFERRED`.

---

## Baseline summary

```yaml
repository: https://github.com/scrimshawlife-ctrl/ShadowrunGame.git
branch: main (audit work performed on stabilize/wp0-repository-baseline)
head_sha: 2d680e3f005cc8ffff2995fdbd320f40f850a68c
working_tree: CLEAN (verified via `git status --short` before and after audit)
default_branch: main (origin/HEAD -> origin/main)
project_generator: XcodeGen (project.yml at repo root; regenerate_xcodeproj.sh helper)
canonical_project: HexWire.xcodeproj (sole .xcodeproj in tree)
duplicate_workspace_status: NONE (only HexWire.xcodeproj/project.xcworkspace, which is the
  standard embedded workspace every .xcodeproj contains — not a duplicate)
backup_project_status: NONE tracked. (An untracked local husk Shadowrune.xcodeproj/ and
  ShadowrunGame.xcodeproj.backup-20260420-104412/ existed on this machine from the
  pre-rewrite checkout; both were deleted locally on 2026-07-18. They were never
  tracked in the current main history.)
tracked_build_artifacts: NONE (verified: `git ls-files` has no build/, DerivedData/,
  or *.xcuserstate matches)
tracked_user_state: NONE (no xcuserdata/ or *.xcuserstate tracked)
largest_git_objects: see "Repository weight" below
open_blockers: see "Open blockers" below
```

---

## Repository identity and history shape

- `main` is a **rewritten history of only 17 commits** (force-pushed 2026-07-18;
  old 87+-commit history preserved at `origin/legacy-shadowrune`).
- Local checkout is byte-identical to `origin/main` (`git fetch --all --prune`
  run; HEAD == origin/main == `2d680e3`).
- Nested `.git` directories: only `./.git`. No submodules, no nested repos.
- 1318 tracked files.
- Notable stale remote branches (all pre-rewrite era): 9 `codex/*` audit branches,
  `claude/silly-joliot-e95762`, `chore/add-gitignore`, several `fix/*` and `feat/*`
  branches, `legacy-shadowrune`. None are needed for main; cleanup decision belongs
  to WP8/owner.

## Canonical project generation

- `project.yml` (XcodeGen) is the canonical source; `HexWire.xcodeproj` is committed
  alongside it. Targets: `HexWire` (app), `HexWireTests`. Scheme: `HexWire`.
- **Drift check (executed):** `xcodegen generate` with XcodeGen 2.45.4 produces a large
  textual diff against the committed pbxproj (~7k lines) that is almost entirely
  UUID regeneration and element reordering, **plus exactly one semantic difference**:
  - committed pbxproj: `PRODUCT_BUNDLE_IDENTIFIER = com.hexwire.tests` (HexWireTests)
  - project.yml / regenerated: `PRODUCT_BUNDLE_IDENTIFIER = com.hexwireaaron.tests`
  - App target matches in both: `com.hexwireaaron.game`.
- Conclusion: the committed project was generated from an **older project.yml**
  (or older XcodeGen) and not regenerated after the tests bundle id changed.
  Drift status: **DOCUMENTED, minor, semantic scope = tests bundle id only.**
- The regenerated project was **not** committed; worktree was restored to the
  committed state after the check (verified clean).
- Resolution belongs to WP1 (regenerate + commit, establishing zero-drift baseline).

## Hygiene scan results

| Check | Result |
|---|---|
| Nested `.git` dirs | PASS — none beyond root |
| Tracked build products | PASS — none |
| Tracked DerivedData | PASS — none |
| Tracked `.xcuserstate` / `xcuserdata` | PASS — none |
| Tracked `.xcodeproj.backup-*` | PASS — none |
| Duplicate workspaces | PASS — none |
| `.gitignore` | Present: `.DS_Store`, `*.xcuserstate`, `xcuserdata/`, `build/`, `DerivedData/`, `*.ipa`, `*.dSYM.zip` |

### Tracked content that needs classification in WP8

- `screenshots/` — **112 tracked files** (playtest/QA evidence PNGs + a few JSON),
  multi-MB each in some cases. Classification: SCREENSHOT_EVIDENCE; candidate for
  relocation out of active source paths.
- Loose top-level dev-tooling scripts: `capture_build_errors.sh`, `cleanup_stale.sh`,
  `diagnose_xcode_vs_cli.sh`, `fix_and_verify.sh`, `nuke_sourcekit_index.sh`,
  `regenerate_xcodeproj.sh` — candidates to consolidate under `scripts/`.
- Loose files: `enemyPhase_new.txt` (looks like a scratch/WIP code dump),
  `enemy_preview.png`, `screenshot-title.png`. Candidates: UNUSED / SCREENSHOT_EVIDENCE.
- `docs/` — 38 files incl. many dated audit/handoff docs from the legacy era;
  WP9 will archive stale ones.

## Repository weight

```yaml
git_object_store: 772 MiB packed + 279 MiB loose (~1.0 GiB .git total, local)
working_checkout: ~0.9 GiB (1.9 GiB including .git)
main_reachable_blobs: 1381 blobs, 923.2 MiB   # measured via rev-list origin/main
```

- **Main's history is asset-heavy but artifact-clean:** the 923 MiB reachable from
  `main` is real game content (music `.mp3` ~4–5 MiB × ~25, sprite/background PNGs
  ~3–4 MiB each, `Assets.xcassets`). No build products are reachable from `main`
  (verified: `git log origin/main -- build/` is empty).
- Build artifacts found in the top-100 all-refs object list (`build/ModuleCache/*.pcm`,
  `.app` products, debug dylibs) are reachable **only via legacy refs**
  (`origin/legacy-shadowrune` and pre-rewrite local branches), not via `main`.
- Top objects, all refs (abridged; full 100-row list reproducible via the
  rev-list/cat-file pipeline in the WP0 packet):

```text
10.3 MB  build/ModuleCache.noindex/UIKit-*.pcm            (legacy refs only)
 5.6 MB  build/ModuleCache.noindex/Foundation-*.pcm       (legacy refs only)
 5.3 MB  build/.../ShadowrunGame.debug.dylib              (legacy refs only)
 4.8 MB  Sounds/music/m6_b.mp3                            (main)
 4.8 MB  Sounds/music/m6_boss_b.mp3                       (main)
 4.8 MB  Sounds/music/intro_m5_music.mp3                  (main)
 ... (~25 music tracks at 3.2–4.8 MB each, all on main)
 3.8 MB  screenshots/hud_fix_initial.png                  (main)
 3.6 MB  Sprites/backgrounds/Mission005_room_3.png        (main)
 3.4 MB  Assets.xcassets/chase_barrier.imageset/...png    (main)
```

- INFERRED: clone cost is dominated by legitimate runtime assets → the WP8 lever is
  **Git LFS (or asset-slimming) for `Sounds/music` + large PNGs**, plus deletion of
  legacy refs on the remote (owner decision), not a history rewrite of `main`
  (main's 17-commit history is already clean).

## Mission/content structure (orientation only, no changes)

- `Missions/` contains `Mission001_multi.json` … `Mission006_multi.json` plus
  loader code (`MissionLoader.swift`, `Room.swift`, `RoomManager.swift`).
- Top-level domains: `Game/` (21 files), `UI/` (22), `Rendering/` (5), `Entities/` (4),
  `Sprites/` (727), `Sounds/` (119), `Assets.xcassets` (228), `tests/` (2).
- `tests/` containing only 2 files vs. this gameplay surface confirms packet risk #7
  (thin automated coverage) — WP2 scope.

## Build sanity (pre-WP1 evidence)

- `xcodebuild -project HexWire.xcodeproj -scheme HexWire -destination
  'generic/platform=iOS Simulator' -configuration Debug build` → **BUILD SUCCEEDED**
  (executed 2026-07-18 on this machine, default DerivedData). This is *not* the WP1
  clean-baseline receipt (no fresh DerivedData path, no Release/iPad/archive legs) —
  it only establishes that WP1 can begin immediately.

## Open blockers

```yaml
open_blockers:
  - id: WP0-B1
    item: XcodeGen drift (tests bundle id com.hexwire.tests vs com.hexwireaaron.tests)
    severity: minor
    owner_decision_needed: false
    resolution_path: WP1 regenerates and commits; pick project.yml value as truth
      (com.hexwireaaron.tests) unless owner objects.
  - id: WP0-B2
    item: Remote legacy refs (legacy-shadowrune, 9 codex/*, misc fix/feat branches)
      keep ~250+ MB of build artifacts and old history alive in fresh clones
    severity: moderate (clone cost), zero (correctness)
    owner_decision_needed: true (branch deletion is destructive on the remote)
    resolution_path: WP8 recommendation doc; do nothing until owner approves.
  - id: WP0-B3
    item: screenshots/ (112 files) tracked inside active source tree
    severity: minor
    owner_decision_needed: false
    resolution_path: WP8 classification + relocation.
```

## WP0 exit gate

```yaml
WP0:
  repository_identity: VERIFIED
  canonical_workspace: VERIFIED
  head_sha: RECORDED   # 2d680e3f005cc8ffff2995fdbd320f40f850a68c
  workspace_ambiguity: RESOLVED   # single canonical HexWire.xcodeproj; no duplicates
```
