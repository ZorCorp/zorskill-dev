---
name: zorskill-dev
description: "Maintainer tooling for the zorskill plugin marketplace. Use when releasing a plugin update (advance its submodule pointer + bump marketplace versions), auditing version drift across all plugins, detecting plugins released in their own repo but not yet carried into the marketplace, keeping the root README Skills table in sync, or scaffolding a new plugin. Commands: /zorskill-dev:check, /zorskill-dev:release, /zorskill-dev:new, /zorskill-dev:sync, /zorskill-dev:drift."
metadata:
  version: "0.7.3"
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
  still listed) is an ERROR. It also flags any plugin whose repo is **private** as an ERROR (a private
  plugin repo breaks `/plugin marketplace add` for every end user — see below). `check` exits non-zero
  only on ERRORs.
- `/zorskill-dev:release <name> <x.y.z> [--push]` — advance `<name>`'s submodule pointer to its repo's
  latest, verify the plugin repo actually declares `<x.y.z>`, sync the marketplace versions, sync the
  README Skills table, validate, and commit. The validate step is SCOPED — it hard-fails only on repo-wide
  JSON validity and the target plugin's own consistency, so another plugin's pre-existing drift never
  blocks this release (it prints as a warning). Commit-only by default; `--push` pushes `main`.
- `/zorskill-dev:new <name> [--create-remote] [--allow-private]` — clone `ZorCorp/<name>` as a submodule
  and scaffold four things into the plugin's own working tree: `plugin.json`, `SKILL.md`, the tag-driven
  `.github/workflows/release.yml`, and a managed **release rule in `CLAUDE.md`** (created if absent;
  appended non-destructively if a `CLAUDE.md` already exists without the block). Then register the
  marketplace entry, sync the README Skills table, and stage. **Refuses a confirmed-private repo** (which
  would break end-user install — see below) unless `--allow-private` is passed for a private marketplace.
- `/zorskill-dev:sync` — regenerate the managed Skills table in the root `README.md` from
  `marketplace.json` (add missing plugins, drop delisted ones), then re-validate. Use it to fix README
  drift without cutting a release.
- `/zorskill-dev:drift [--dry-run] [--push]` — detect plugins whose OWN repo was released to a new
  version that was never carried into the marketplace: for each plugin it fetches the repo, reads the
  version at its tracked-branch tip, and if that tip is strictly AHEAD of the marketplace entry (numeric
  semver compare — forward-only), advances the submodule pointer + marketplace entry, patch-bumps the
  aggregate, syncs the README, and commits — HARD-GATED on a SCOPED check: repo-wide JSON validity, each
  drifted plugin's own consistency (plugin.json == marketplace), and README roster sync. A structurally
  broken drifted tip aborts and reverts, committing nothing. A tip BEHIND the marketplace (revert/
  force-push) warns and is left unchanged — never downgraded. A submodule that is uninitialized or whose
  remote can't be fetched (e.g. a private repo the runner has no token for) is skipped with a warning and
  is NON-BLOCKING for the gate — so PUBLIC plugins still carry in even while a private/uninitialized one
  is skipped; the skipped plugin is carried in manually via `/zorskill-dev:release`. Commit-only by default;
  `--push` pushes `main`; `--dry-run` previews and changes nothing. Intended for a scheduled
  drift-detector Action.

## Plugin repos must be PUBLIC

Every plugin in the marketplace is a git submodule, and `/plugin marketplace add ZorCorp/zorskill`
recursively clones **every** plugin repo on the end user's machine. A single **private** plugin repo
makes that clone 404 and **aborts the whole install for every user**. So marketplace plugin repos must
be public. Guardrails: `/zorskill-dev:check` flags any plugin whose repo is private as an ERROR, and
`/zorskill-dev:new` refuses a private repo unless `--allow-private` is passed. Both probe visibility via
`gh api repos/<owner>/<name> --jq .visibility` — best-effort: if `gh` is missing or the API is
unreachable, the probe is skipped with a note (it never fails on lack of network); only a **confirmed**
`private` is an error/refusal. A repo that must stay private is delisted and carried in manually via
`/zorskill-dev:release` into a private marketplace, or added with `new --allow-private`.

## README Skills table (managed block)

The root `README.md` carries a human-facing Skills table wrapped in
`<!-- BEGIN SKILLS (managed by zorskill-dev) -->` … `<!-- END SKILLS -->`. Only that block is
tool-managed: the **roster** is authoritative from `marketplace.json` (every plugin gets exactly one
row; delisted plugins are removed), the **Source** link comes from each submodule's `.gitmodules` URL,
and **curated descriptions are preserved** — a plugin already in the table keeps its hand-written text;
a newly added plugin is seeded from the first sentence of its `marketplace.json` description, ready to
refine. `release`, `new`, and `sync` all regenerate this block; edits outside the markers are untouched.

## Release flows

There are two ways to ship a plugin update. Both start the same way: edit the plugin and push to
its own repo `ZorCorp/<name>`.

**Tag-driven, self-service (default — you never touch the monorepo).**
Every plugin repo carries a `Release` GitHub Action (`.github/workflows/release.yml`, scaffolded by
`/zorskill-dev:new` from `templates/release.yml`). To cut a version, from the plugin repo run:

```
gh workflow run release.yml -f version=<x.y.z>     # no leading v
```

That workflow — entirely within the plugin's own repo — bumps its `.claude-plugin/plugin.json`
`.version`, commits, tags `v<x.y.z>` at the bump commit, and pushes branch + tag. The monorepo
**drift-detector Action then carries it into the marketplace within ~30 minutes** (it runs every
30 min): forward-only, check-gated, advancing the submodule pointer + marketplace versions + README.
You never touch `ZorCorp/zorskill`.

**Manual / instant (no wait).**
When you don't want to wait for the drift cron:

1. Push the plugin's `.claude-plugin/plugin.json` `.version` bump to `ZorCorp/<name>` (or use the
   Release workflow above).
2. `/zorskill-dev:release <name> <x.y.z>` — advances the pointer + marketplace + README, commits.
3. Review, then `git push origin main` (or pass `--push`).

## Env

- `ZORSKILL_ROOT` — override the monorepo root (otherwise resolved by walking up to the
  `.claude-plugin/marketplace.json` that has a `.plugins` array).
