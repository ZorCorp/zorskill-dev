---
description: Advance a plugin's submodule pointer to its repo's latest, bump the marketplace version to match, validate, and commit. Commit-only by default; add --push to push main.
---

Usage: `/zorskill-dev:release <name> <x.y.z> [--push]`

Preconditions the user must have done first (this tool is aggregation-side only and will NOT do them):
1. The plugin's own repo (`ZorCorp/<name>`) already has version `<x.y.z>` committed AND pushed — its `.claude-plugin/plugin.json` `.version` is `<x.y.z>`.
2. For a ref-pinned entry (the zorskill standard): the release tag `v<x.y.z>` exists on that repo — the plugin's own `Release` workflow (`gh workflow run release.yml -f version=<x.y.z>`) creates it.

Run the release. Relay its output verbatim. For a ref-pinned remote entry it verifies tag `v<x.y.z>` exists and declares `<x.y.z>`, then advances the entry's `version` + `source.ref` together (and best-effort advances any on-disk submodule checkout); for a submodule entry it advances the pointer and verifies the repo declares `<x.y.z>`. Either way it then syncs `marketplace.json`, runs the scoped check, and commits.

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" release $ARGUMENTS

Pushing to shared `main` is outward-facing: only pass `--push` when the user explicitly asks. Otherwise report that it is committed locally and show the push command.
