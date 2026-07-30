---
name: zorskill-dev
description: "Maintainer tooling for the zorskill plugin marketplace. Use when releasing a plugin update (advance its submodule pointer + bump marketplace versions), auditing version drift across all plugins, detecting plugins released in their own repo but not yet carried into the marketplace, keeping the root README Skills table in sync, or scaffolding a new plugin. Commands: /zorskill-dev:check, /zorskill-dev:release, /zorskill-dev:new, /zorskill-dev:sync, /zorskill-dev:drift."
metadata:
  version: "0.8.1"
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
  blocks this release (it prints as a warning). Works for BOTH source kinds: a SUBMODULE plugin advances
  its on-disk pointer; a REMOTE (url/github) plugin is verified against its repo tip over the GitHub API
  (`gh`) and carried into the marketplace entry with no submodule. Either way the tool only carries in a
  version the plugin's own repo already declares — it never edits a plugin's repo. Commit-only by default; `--push` pushes `main`.
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
  version that was never carried into the marketplace, across BOTH source kinds: a SUBMODULE plugin's
  tracked-branch tip is read from the initialized submodule; a REMOTE (url/github) plugin's default-branch
  tip is read over the GitHub API (`gh`, honouring `$GH_TOKEN` so private repos resolve with a read token).
  If that tip is strictly AHEAD of the marketplace entry (numeric semver compare — forward-only), it
  advances the marketplace entry (and, for a submodule, the pointer), patch-bumps the aggregate, syncs the
  README, and commits — HARD-GATED on a SCOPED check: repo-wide JSON validity, each drifted plugin's own
  consistency (submodule: plugin.json == marketplace; remote: marketplace holds a semver carried from the
  tip), and README roster sync. A structurally broken drifted tip aborts and reverts, committing nothing. A
  tip BEHIND the marketplace (revert/force-push) warns and is left unchanged — never downgraded. A submodule
  that is uninitialized, or a remote repo that can't be reached (private without a token, non-github, or
  offline), is skipped with a warning and is NON-BLOCKING for the gate — so reachable plugins still carry in
  even while an unreachable one is skipped (carry it in later once reachable, or via `/zorskill-dev:release`).
  Commit-only by default; `--push` pushes `main`; `--dry-run` previews and changes nothing. Intended for a
  scheduled drift-detector Action.

## Mixed-source marketplaces (submodule vs remote)

A marketplace plugin's `source` can be either kind — the tooling supports both:

- **Submodule-managed** — `source` is a local path string (`"./plugins/<name>"`) AND the plugin is in
  `.gitmodules`. `/plugin marketplace add` recursively clones it on **every** end user's machine, so a
  submodule plugin repo **MUST be public** — a single private submodule 404s and aborts the whole
  install for everyone. These are the tool-managed plugins: `check`/`release`/`new`/`drift` operate on
  them.
- **Remote-sourced** — `source` is an object. Prefer the explicit-URL form
  `{"source":"url","url":"https://github.com/ZorCorp/<name>.git"}` — it clones over **HTTPS** (works
  anonymously for public repos, credential-helper for private). Avoid `{"source":"github","repo":"…"}`:
  it clones over **SSH** (`git@github.com:…`), which fails at `/plugin install` for users without SSH
  keys **even for public repos** — `check` warns on it. `/plugin marketplace add` only reads
  `marketplace.json`; a remote-source plugin
  is cloned at **`/plugin install`** time with the user's own credentials, so it may be **public OR
  private** (private installs per-access — fine). Remote plugins have no submodule on disk and are NOT
  tool-managed: `check`'s version/both-format/submodule checks skip them (info line only); `release`/
  `new` refuse them; `drift` never tries to advance them. `sync` still lists them in the README (Source
  link from `source.repo`/`url`).

**Rule of thumb: a plugin that must stay private has to be REMOTE-sourced, never a submodule.**

Guardrails: `/zorskill-dev:check` flags a **private SUBMODULE** repo as an ERROR (probing
`gh api repos/<owner>/<name> --jq .visibility`), but a **private REMOTE** source is fine (noted, never
an error). `/zorskill-dev:new` refuses a private repo unless `--allow-private`. Both probes are
best-effort: if `gh` is missing or the API is unreachable, the probe is skipped with a note (never fails
on lack of network); only a **confirmed** `private` submodule is an error/refusal.

**Private labeling.** An access-gated (private) plugin's marketplace `description` is prefixed with the
marker `🔒 Private (ZorCorp members only) — ` so users see it in the listing. `check` reconciles that
label against actual repo visibility (WARN-only, never auto-edited): a private repo whose description
isn't 🔒-labeled → warn to add the marker; a public repo that still carries a stale 🔒 → warn to drop it.
`sync` shows a 🔒 on confirmed-private plugins' README rows. Both are best-effort (skipped offline).

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
