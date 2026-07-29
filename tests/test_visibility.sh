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
echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
