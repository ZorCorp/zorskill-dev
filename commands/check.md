---
description: Audit the zorskill marketplace for version drift, JSON validity, ref-pin consistency (source.ref == v<version>, tag exists), both-format presence, and submodule health.
---

Run the repo-wide consistency audit and report the result verbatim.

! bash "${CLAUDE_PLUGIN_ROOT}/scripts/zorskill-dev.sh" check

If it prints FAIL, summarize which plugins drifted and stop — do not attempt to fix without the user's go-ahead.
