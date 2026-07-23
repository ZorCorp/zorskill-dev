---
description: Scaffold and register a new marketplace plugin — clone its (already-created) repo as a submodule, drop plugin.json + SKILL.md skeletons, add the marketplace entry, and stage.
---

Usage: `/zorskill-dev:new <name> [--description "..."] [--create-remote]`

By default this expects `ZorCorp/<name>` to already exist on GitHub (empty is fine). It clones it as a submodule, scaffolds `plugin.json` + `SKILL.md` locally, registers the marketplace entry, and stages the change in zorskill. It does NOT push anything to `ZorCorp/<name>` — that stays the user's step.

`--create-remote` additionally creates the empty GitHub repo via `gh` — only pass it when the user explicitly asks, since it is an outward-facing action.

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" new $ARGUMENTS

Relay the "Next:" steps verbatim so the user knows to fill and push the plugin repo.
