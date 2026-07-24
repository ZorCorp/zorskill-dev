# Changelog

All notable changes to `zorskill-dev` are documented here. Versioning is semver;
new capability → minor, fix/docs → patch.

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
