---
name: zorskill-dev
description: "Maintainer tooling for the zorskill plugin marketplace. Use when releasing a plugin update (advance its submodule pointer + bump marketplace versions), auditing version drift across all plugins, detecting plugins released in their own repo but not yet carried into the marketplace, keeping the root README Skills table in sync, or scaffolding a new plugin. Commands: /zorskill-dev:check, /zorskill-dev:release, /zorskill-dev:new, /zorskill-dev:sync, /zorskill-dev:drift."
metadata:
  version: "0.5.0"
---

# zorskill-dev

Aggregation-side maintainer tooling for the `ZorCorp/zorskill` Claude Code plugin marketplace.
Every plugin is a git submodule pointing at `ZorCorp/<name>`; the root `.claude-plugin/marketplace.json`
lists them all with a per-plugin `version` and a top-level aggregate `version`.

**Scope:** this tool only touches the monorepo aggregation side — it advances a submodule pointer,
syncs `marketplace.json`, and commits to zorskill. It NEVER pushes commits into a plugin's own repo;
that stays each repo's own concern.

## Commands

- `/zorskill-dev:check` — audit version drift (root entry vs each plugin's `plugin.json`), JSON validity,
  format presence, README roster sync, and submodule health. Severity: a missing `.claude-plugin/plugin.json`
  is an ERROR (fails); a missing `SKILL.md` is a WARNING (some plugins are intentionally Claude-only).
  README roster drift (a marketplace plugin missing from the managed Skills table, or a delisted plugin
  still listed) is an ERROR. `check` exits non-zero only on ERRORs.
- `/zorskill-dev:release <name> <x.y.z> [--push]` — advance `<name>`'s submodule pointer to its repo's
  latest, verify the plugin repo actually declares `<x.y.z>`, sync the marketplace versions, sync the
  README Skills table, validate, and commit. The validate step is SCOPED — it hard-fails only on repo-wide
  JSON validity and the target plugin's own consistency, so another plugin's pre-existing drift never
  blocks this release (it prints as a warning). Commit-only by default; `--push` pushes `main`.
- `/zorskill-dev:new <name> [--create-remote]` — clone `ZorCorp/<name>` as a submodule, scaffold
  `plugin.json` + `SKILL.md`, register the marketplace entry, sync the README Skills table, and stage.
- `/zorskill-dev:sync` — regenerate the managed Skills table in the root `README.md` from
  `marketplace.json` (add missing plugins, drop delisted ones), then re-validate. Use it to fix README
  drift without cutting a release.
- `/zorskill-dev:drift [--dry-run] [--push]` — detect plugins whose OWN repo was released to a new
  version that was never carried into the marketplace: for each plugin it fetches the repo, reads the
  version at its tracked-branch tip, and if that's a valid semver different from the marketplace entry,
  advances the submodule pointer + marketplace entry, patch-bumps the aggregate, syncs the README, and
  commits — HARD-GATED on `check` (a structurally broken drifted tip aborts and reverts, committing
  nothing). Commit-only by default; `--push` pushes `main`; `--dry-run` previews and changes nothing.
  Intended for a scheduled drift-detector Action.

## README Skills table (managed block)

The root `README.md` carries a human-facing Skills table wrapped in
`<!-- BEGIN SKILLS (managed by zorskill-dev) -->` … `<!-- END SKILLS -->`. Only that block is
tool-managed: the **roster** is authoritative from `marketplace.json` (every plugin gets exactly one
row; delisted plugins are removed), the **Source** link comes from each submodule's `.gitmodules` URL,
and **curated descriptions are preserved** — a plugin already in the table keeps its hand-written text;
a newly added plugin is seeded from the first sentence of its `marketplace.json` description, ready to
refine. `release`, `new`, and `sync` all regenerate this block; edits outside the markers are untouched.

## Everyday release flow

1. Edit the plugin in `plugins/<name>/`, commit + push to `ZorCorp/<name>`, bumping its
   `.claude-plugin/plugin.json` `.version` to `<x.y.z>`.
2. `/zorskill-dev:release <name> <x.y.z>` — pointer + marketplace bump + commit.
3. Review, then `git push origin main` (or pass `--push`).

## Env

- `ZORSKILL_ROOT` — override the monorepo root (otherwise resolved by walking up to the
  `.claude-plugin/marketplace.json` that has a `.plugins` array).
