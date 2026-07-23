---
name: zorskill-dev
description: "Maintainer tooling for the zorskill plugin marketplace. Use when releasing a plugin update (advance its submodule pointer + bump marketplace versions), auditing version drift across all plugins, or scaffolding a new plugin. Commands: /zorskill-dev:check, /zorskill-dev:release, /zorskill-dev:new."
metadata:
  version: "0.3.1"
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
  format presence, and submodule health. Severity: a missing `.claude-plugin/plugin.json` is an ERROR
  (fails); a missing `SKILL.md` is a WARNING (some plugins are intentionally Claude-only). `check` exits
  non-zero only on ERRORs.
- `/zorskill-dev:release <name> <x.y.z> [--push]` — advance `<name>`'s submodule pointer to its repo's
  latest, verify the plugin repo actually declares `<x.y.z>`, sync the marketplace versions, validate,
  and commit. The validate step is SCOPED — it hard-fails only on repo-wide JSON validity and the target
  plugin's own consistency, so another plugin's pre-existing drift never blocks this release (it prints
  as a warning). Commit-only by default; `--push` pushes `main`.
- `/zorskill-dev:new <name> [--create-remote]` — clone `ZorCorp/<name>` as a submodule, scaffold
  `plugin.json` + `SKILL.md`, register the marketplace entry, and stage.

## Everyday release flow

1. Edit the plugin in `plugins/<name>/`, commit + push to `ZorCorp/<name>`, bumping its
   `.claude-plugin/plugin.json` `.version` to `<x.y.z>`.
2. `/zorskill-dev:release <name> <x.y.z>` — pointer + marketplace bump + commit.
3. Review, then `git push origin main` (or pass `--push`).

## Env

- `ZORSKILL_ROOT` — override the monorepo root (otherwise resolved by walking up to the
  `.claude-plugin/marketplace.json` that has a `.plugins` array).
