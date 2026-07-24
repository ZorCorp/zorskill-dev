# Changelog

All notable changes to `zorskill-dev` are documented here. Versioning is semver;
new capability → minor, fix/docs → patch.

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
