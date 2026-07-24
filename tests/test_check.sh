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
# skip a nested per-plugin marketplace.json that has .plugins but NO top-level semver
# .version (e.g. kf-cli's stray outlier) and walk up to the true aggregate root.
tv="$(mktemp -d)"; make_fake_root "$tv" kf-cli 0.7.3 0.7.3
printf '{ "metadata":{"version":"0.7.3"}, "plugins":[{"name":"kf-cli"}] }\n' > "$tv/plugins/kf-cli/.claude-plugin/marketplace.json"
assert_eq "$(cd "$tv/plugins/kf-cli" && ZORSKILL_ROOT="" resolve_root)" "$tv" "skip versionless nested marketplace"
rm -rf "$tv"

# --- check_json + check_versions (Task 1.3) ---
# check_versions: PASS when root entry matches plugin.json
r1="$(mktemp -d)"; make_fake_root "$r1" demo 0.3.0 0.3.0
assert_pass check_versions "$r1"
# check_versions: FAIL on drift (the historical bug: root entry behind plugin.json)
r2="$(mktemp -d)"; make_fake_root "$r2" demo 0.5.13 0.7.1
assert_fail check_versions "$r2"
# check_versions: FAIL when aggregate .version missing
r3="$(mktemp -d)"; make_fake_root "$r3" demo 0.1.0 0.1.0
tmp=$(mktemp); jq 'del(.version)' "$r3/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$r3/.claude-plugin/marketplace.json"
assert_fail check_versions "$r3"
# check_json: FAIL on malformed plugin.json
r4="$(mktemp -d)"; make_fake_root "$r4" demo 0.1.0 0.1.0
echo '{ bad json' > "$r4/plugins/demo/.claude-plugin/plugin.json"
assert_fail check_json "$r4"
rm -rf "$r1" "$r2" "$r3" "$r4"

# --- check_both_format (Task 1.4; severity refined per option-b) ---
# PASS when both files present
b1="$(mktemp -d)"; make_fake_root "$b1" demo 0.1.0 0.1.0
assert_pass check_both_format "$b1"
# missing SKILL.md is now a WARNING (Claude-only plugin), not an ERROR → still PASS
b2="$(mktemp -d)"; make_fake_root "$b2" demo 0.1.0 0.1.0; rm "$b2/plugins/demo/SKILL.md"
assert_pass check_both_format "$b2"
# missing plugin.json is an ERROR → FAIL
b3="$(mktemp -d)"; make_fake_root "$b3" demo 0.1.0 0.1.0; rm "$b3/plugins/demo/.claude-plugin/plugin.json"
assert_fail check_both_format "$b3"
rm -rf "$b1" "$b2" "$b3"

# --- apply_release_versions (Task 2.2) ---
# sets plugin entry + auto patch-bumps aggregate
a1="$(mktemp -d)"; make_fake_root "$a1" demo 0.1.0 0.2.0
newagg="$(apply_release_versions "$a1" demo 0.2.0)"
assert_eq "$newagg" "1.0.1" "aggregate auto patch-bump"
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$a1/.claude-plugin/marketplace.json")" "0.2.0" "root entry updated"
# explicit aggregate override
a2="$(mktemp -d)"; make_fake_root "$a2" demo 0.1.0 0.2.0
assert_eq "$(apply_release_versions "$a2" demo 0.2.0 2.0.0)" "2.0.0" "aggregate override"
rm -rf "$a1" "$a2"

# --- render_template (Task 3.1) ---
rt="$(render_template "$(cd "$HERE/.." && pwd)/templates/plugin.json.tmpl" foo "a: b desc")"
assert_eq "$(echo "$rt" | jq -r .name)" "foo" "template NAME"
assert_eq "$(echo "$rt" | jq -r .description)" "a: b desc" "template DESCRIPTION"

# --- _semver_gt: numeric per-component comparison (forward-only drift) ---
assert_pass _semver_gt 0.10.0 0.9.0     # numeric, not string (10 > 9)
assert_fail _semver_gt 0.9.0 0.10.0
assert_pass _semver_gt 1.0.0 0.99.99
assert_fail _semver_gt 1.2.3 1.2.3      # equal is NOT greater
assert_pass _semver_gt 0.2.1 0.2.0
assert_fail _semver_gt 0.2.0 0.2.1

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
