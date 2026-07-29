#!/usr/bin/env bash
# Tier-A tests for the repo-visibility guardrail. The gh probe (_have_gh / _repo_visibility) is
# stubbed by redefining those functions — no network is touched.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib

r="$(mktemp -d)"; make_fake_root "$r" demo 0.1.0 0.1.0

# CONFIRMED private → ERROR
_have_gh(){ return 0; }; _repo_visibility(){ echo private; }
assert_fail check_visibility "$r"

# public → ok
_repo_visibility(){ echo public; }
assert_pass check_visibility "$r"

# gh not installed → gracefully SKIPPED (non-fatal, exit 0)
_have_gh(){ return 1; }
assert_pass check_visibility "$r"

# gh present but API fails / offline (empty output) → gracefully SKIPPED (non-fatal)
_have_gh(){ return 0; }; _repo_visibility(){ return 1; }
assert_pass check_visibility "$r"

rm -rf "$r"

# --- MIXED SOURCE (the key correctness fix) ---
# root with a SUBMODULE plugin (demo) + a REMOTE github plugin (rem, not in .gitmodules).
m="$(mktemp -d)"; make_fake_root "$m" demo 1.0.0 1.0.0
tmp=$(mktemp); jq '.plugins += [{"name":"rem","description":"Remote. x.","version":"9.9.9","source":{"source":"github","repo":"ZorCorp/rem"}}]' "$m/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$m/.claude-plugin/marketplace.json"
assert_pass _is_submodule "$m" demo    # demo = submodule-managed
assert_fail _is_submodule "$m" rem     # rem  = remote-sourced

# submodule demo PUBLIC + remote rem PRIVATE → check PASSES (a private REMOTE source is fine)
_have_gh(){ return 0; }; _repo_visibility(){ case "$1" in */rem) echo private;; *) echo public;; esac; }
assert_pass check_visibility "$m"
# but a PRIVATE SUBMODULE is still an ERROR (side-by-side with the above)
_repo_visibility(){ echo private; }    # demo (submodule) now private too
assert_fail check_visibility "$m"
rm -rf "$m"

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
