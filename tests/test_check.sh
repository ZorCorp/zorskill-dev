#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib   # load functions without running main

assert_pass is_semver 1.2.3
assert_pass is_semver 0.7.13
assert_fail is_semver 1.2
assert_fail is_semver v1.2.3
assert_fail is_semver ""

# --- resolve_root (Task 1.2) ---
# env override wins
tmpr="$(mktemp -d)"; make_fake_root "$tmpr" demo 0.1.0 0.1.0
assert_eq "$(ZORSKILL_ROOT="$tmpr" resolve_root)" "$tmpr" "env override"
# walk up from a nested cwd
assert_eq "$(cd "$tmpr/plugins/demo" && ZORSKILL_ROOT="" resolve_root)" "$tmpr" "walk-up"
# fails when nothing matches — isolate a script copy OUTSIDE any git repo so the
# git-superproject fallback (which keys off the script's own location) cannot fire.
iso="$(mktemp -d)"; cp "$(cd "$HERE/.." && pwd)/scripts/zorskill-dev.sh" "$iso/zsd.sh"
assert_fail bash -c 'cd "'"$iso"'"; ZORSKILL_ROOT=""; source "'"$iso"'/zsd.sh" --lib; resolve_root'
rm -rf "$tmpr" "$iso"

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
