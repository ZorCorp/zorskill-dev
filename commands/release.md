---
description: Advance a plugin's submodule pointer to its repo's latest, bump the marketplace version to match, validate, and commit. Commit-only by default; add --push to push main.
---

Usage: `/zorskill-dev:release <name> <x.y.z> [--push]`

Preconditions the user must have done first (this tool is aggregation-side only and will NOT do them):
1. The plugin's own repo (`ZorCorp/<name>`) already has version `<x.y.z>` committed AND pushed — its `.claude-plugin/plugin.json` `.version` is `<x.y.z>`.

Run the release. Relay its output verbatim. It advances the pointer, verifies the plugin repo actually declares `<x.y.z>` (aborts if not), syncs `marketplace.json`, runs `check`, and commits.

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" release $ARGUMENTS

Pushing to shared `main` is outward-facing: only pass `--push` when the user explicitly asks. Otherwise report that it is committed locally and show the push command.
