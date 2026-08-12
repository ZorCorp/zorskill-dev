---
description: Detect plugins whose own repo was released to a new version that was never carried into the marketplace, advance them, and (hard-gated on check) commit. Commit-only by default; --push to push main; --dry-run to preview.
---

Usage: `/zorskill-dev:drift [--dry-run] [--push]`

Catches the case where a teammate pushed a new version to a plugin's OWN repo but forgot to carry it
into the marketplace via `/zorskill-dev:release`. For each plugin it fetches the plugin repo, reads the
version declared at its tracked-branch tip, and if that's a valid semver different from the marketplace
entry, advances the submodule pointer + syncs the marketplace entry. If anything drifted, it patch-bumps
the aggregate, syncs the README, and runs `check` as a HARD GATE — it commits only if `check` PASSES; if a
drifted plugin's tip is structurally broken, it reverts and commits nothing.

`--dry-run` prints pinned-vs-repo versions and what would advance, changing nothing. Without `--push` it
commits locally; `--push` pushes `main` (outward-facing — only when the user explicitly asks).

For a ref-pinned remote entry, drift advances `version` and `source.ref` together, and only when the
repo's `v<tip>` tag exists — a bumped-but-untagged tip is skipped with a "released but untagged" warning.

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" drift $ARGUMENTS

Relay the output verbatim. If it aborted, report which plugin's tip broke the check and do not retry blindly.
