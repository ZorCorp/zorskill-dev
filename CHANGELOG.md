# Changelog

All notable changes to `zorskill-dev` are documented here. Versioning is semver;
new capability → minor, fix/docs → patch.

## [0.8.0] - 2026-07-29
- Mixed-source marketplace support. A plugin is SUBMODULE-managed iff its `source` is a local `./`
  path string AND it's in `.gitmodules`; otherwise it's REMOTE-sourced (object `source`:
  github/url/git-subdir/npm), cloned at `/plugin install` with the user's creds (so it may be public
  OR private). Changes:
  - `check`: version-consistency, both-format, and submodule-health run only for submodule plugins;
    remote plugins get an info line, not a "missing plugin.json" error. `check_visibility` flags a
    private SUBMODULE as an ERROR but treats a private REMOTE source as fine (noted). Roster/README
    check expects all plugins (submodule + remote).
  - `sync`: emits a README row for every plugin incl. remote-sourced, with the Source link derived
    from `source.repo` (github) / `source.url` (not `.gitmodules`). Curated descriptions preserved.
  - `release` / `new`: refuse a remote-sourced plugin name with a clear message, BEFORE any git op,
    so no orphan `plugins/<name>` gitlink is created.
  - `drift`: never treats a remote-sourced entry as a missing submodule or tries to advance it.
  - Private-label reconciliation. Convention: an access-gated plugin's marketplace `description` is
    prefixed with `🔒 Private (ZorCorp members only) — `. `check` reconciles that label against actual
    repo visibility (best-effort, needs gh): a private repo without the 🔒 label, or a public repo that
    still carries a stale 🔒 label, is a WARNING (never auto-edited, never fails). `sync` shows a 🔒
    marker on confirmed-private plugins' README rows (best-effort; skipped offline; idempotent).

## [0.7.3] - 2026-07-29
- Private-repo guardrail. A private plugin repo breaks `/plugin marketplace add` for every end user
  (Claude Code recursively clones each plugin submodule and 404s on any it can't reach). `check` now
  probes each plugin repo's visibility (`gh api repos/<owner>/<name> --jq .visibility`) and flags a
  confirmed-private repo as an ERROR; `new` refuses a confirmed-private repo unless `--allow-private`
  is passed. Best-effort + graceful: if `gh` is absent or the API is unreachable, the probe is skipped
  with a note (never fails on lack of network) — only a confirmed `private` is an error/refusal.

## [0.7.2] - 2026-07-27
- Scope `drift`'s validate gate (mirrors `check_release` for `release`, applied to the DRIFTED SET):
  hard-fails ONLY on repo-wide JSON validity, each drifted plugin's own consistency (plugin.json ==
  marketplace == carried-in version), and README roster sync. Uninitialized/unreachable submodules
  (skipped by the scan) and other plugins' pre-existing drift are non-blocking warnings — so a PUBLIC
  plugin carries in AND commits even while a private one (e.g. `gcp-bq`) is uninitialized. A
  structurally broken drifted tip still aborts + reverts (repo-wide JSON check catches it).
  Supersedes 0.7.1.

## [0.7.1] - 2026-07-27
- `drift` now skips a submodule that is uninitialized or whose remote can't be fetched (e.g. a
  private plugin repo the scheduled Action's default token can't clone) — warns, non-fatal, never
  counted as drift, nothing mutated — instead of failing the run. General: any unreachable/
  uninitialized submodule is skipped the same way. A private plugin (currently `gcp-bq`) is carried
  in manually via `/zorskill-dev:release`. Forward-only compare, check-gate, scoped revert,
  `--push`/`--dry-run` unchanged.

## [0.7.0] - 2026-07-24
- Add `templates/claude-release-block.md` — a managed CLAUDE.md block (wrapped in
  `<!-- BEGIN zorskill-release -->` … `<!-- END zorskill-release -->`) that tells Claude Code,
  when developing inside a plugin repo, to release via `gh workflow run release.yml` and never
  hand-edit the version or the marketplace.
- `/zorskill-dev:new` now also scaffolds that block into the new plugin's `CLAUDE.md`: creates the
  file if absent; if a `CLAUDE.md` exists without the marker, appends the block (preceded by a blank
  line) preserving existing content; if the marker is already present, leaves it untouched.

## [0.6.0] - 2026-07-24
- Add `templates/release.yml` — a tag-driven `Release` GitHub Action (workflow_dispatch with a
  `version` input) that bumps a plugin repo's own `plugin.json`, commits, tags `v<version>` at the
  bump, and pushes; the monorepo drift Action (every 30 min) carries it into the marketplace.
- `/zorskill-dev:new` now also scaffolds `.github/workflows/release.yml` into the new plugin's
  working tree (uncommitted, like plugin.json/SKILL.md — the user pushes it to the plugin repo).
- SKILL.md documents the tag-driven self-service flow (`gh workflow run release.yml -f version=x.y.z`
  → drift carries in within ~30 min, never touching the monorepo) alongside the instant
  `/zorskill-dev:release` path.

## [0.5.1] - 2026-07-24
- Forward-only drift guard: `drift` now advances a plugin ONLY when its repo tip is strictly
  ahead of the marketplace, using a numeric per-component semver comparison (0.10.0 > 0.9.0).
  A repo tip that is BEHIND the marketplace (revert/force-push, or marketplace manually ahead)
  warns and is left unchanged — never downgraded — and does not fail the run.

## [0.5.0] - 2026-07-24
- Add `drift` command (`/zorskill-dev:drift [--dry-run] [--push]`): detect plugins whose own
  repo was released to a new version never carried into the marketplace, advance the submodule
  pointer + marketplace entry, patch-bump the aggregate, sync the README, and commit — HARD-GATED
  on `check` (a structurally broken drifted tip aborts and reverts, committing nothing). Reads the
  repo-tip version tolerantly so a version bump still triggers even if that commit's `plugin.json`
  is malformed; the strict check gate then catches the breakage. Aborts are scoped — they revert
  only what drift touched. Meant to be called by a scheduled drift-detector Action.

## [0.4.0] - 2026-07-24
- README Skills-table sync: `sync_readme` + `/zorskill-dev:sync`; `release`/`new` regenerate the
  managed block; `check` flags README roster drift as an ERROR. Roster authoritative from
  `marketplace.json`; curated descriptions preserved.

## [0.3.1] - 2026-07-24
- Explicit command registration via `commands: ["./commands/"]` (directory form — keeps
  auto-discovery for future commands).

## [0.3.0] - 2026-07-23
- Scoped `release` validate gate (target plugin + repo-wide JSON only; other plugins' drift is a
  non-blocking warning). `check` severity: missing `plugin.json` = ERROR, missing `SKILL.md` =
  WARNING. Fix `check_json` local var leak.

## [0.2.1] - 2026-07-23
- Harden `resolve_root` to require a top-level semver `.version`, skipping versionless per-plugin
  `marketplace.json` outliers.

## [0.2.0] - 2026-07-23
- First working `check` / `release` / `new` commands + README.
