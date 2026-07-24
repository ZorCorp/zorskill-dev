---
description: Regenerate the managed Skills table in the root README.md from marketplace.json (add missing plugins, drop delisted ones, preserve curated descriptions), then re-validate.
---

Fix root-README roster drift without cutting a release. Regenerates only the block between
`<!-- BEGIN SKILLS (managed by zorskill-dev) -->` and `<!-- END SKILLS -->`: the roster is taken from
`marketplace.json`, Source links from `.gitmodules`, and existing curated descriptions are preserved
(new plugins are seeded from their marketplace description's first sentence). Then it re-runs `check`.

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" sync

Relay the output. It stages nothing and commits nothing — review the README diff and commit yourself.
