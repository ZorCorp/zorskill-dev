---
description: Mirror the marketplace manifest into the private org-sync companion repo (claude.ai "Sync from GitHub" requires a private repo), via the GitHub Contents API. No-op when already up to date.
---

Usage: `/zorskill-dev:mirror [owner/repo]`

Claude's organization plugin sync on claude.ai only accepts a PRIVATE repository, while the zorskill
marketplace repo is public. The companion repo (default: set `ZORSKILL_MIRROR_REPO`, or pass it as the
argument — for zorskill this is `mcailab/zorskill-org`) holds a single file, `.claude-plugin/marketplace.json`,
kept identical to this marketplace's manifest. Because every plugin source is a url+ref object, that one
file is self-contained — no submodules, no plugin content.

Run the mirror and relay its output verbatim:

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" mirror $ARGUMENTS

Run this AFTER the marketplace change is pushed to `main` (mirror what users see, not local-only state).
If it fails, check `gh auth status` and that the account can write to the companion repo.
