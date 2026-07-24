# zorskill-dev

Maintainer tooling for the [ZorCorp/zorskill](https://github.com/ZorCorp/zorskill) Claude Code plugin marketplace.

Install via the marketplace: `/plugin install zorskill-dev`, then drive with `/zorskill-dev:check`, `/zorskill-dev:release`, `/zorskill-dev:new`, `/zorskill-dev:sync`, `/zorskill-dev:drift`.

See `SKILL.md` for the full command reference. Aggregation-side only: it advances submodule pointers, syncs `marketplace.json`, and keeps the root `README.md` Skills table in sync (a managed block — roster from `marketplace.json`, curated descriptions preserved); it never pushes to a plugin's own repo.
