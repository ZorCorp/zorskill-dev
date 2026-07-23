#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib   # load functions without running main

assert_pass is_semver 1.2.3
assert_pass is_semver 0.7.13
assert_fail is_semver 1.2
assert_fail is_semver v1.2.3
assert_fail is_semver ""

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
