#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib

FIX="$(mktemp -d)"
bare="$FIX/newplug.git"; root="$FIX/root"
git init --quiet --bare "$bare"       # empty plugin repo already exists (human made it)
# minimal superproject with a marketplace.json
git init --quiet "$root"; mkdir -p "$root/.claude-plugin"
printf '{ "name":"zorskill","version":"1.0.0","plugins":[] }\n' > "$root/.claude-plugin/marketplace.json"
git -C "$root" -c user.email=t@t -c user.name=t add -A && git -C "$root" -c user.email=t@t -c user.name=t commit --quiet -m init

assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib;
  ZORSKILL_ROOT="'"$root"'" GIT_ALLOW_PROTOCOL=file cmd_new newplug --repo-url "'"$bare"'" --description "a: b desc"'
# submodule scaffolded locally
assert_eq "$(jq -r .name "$root/plugins/newplug/.claude-plugin/plugin.json")" "newplug" "plugin.json scaffolded"
assert_pass test -f "$root/plugins/newplug/SKILL.md"
# tag-driven Release workflow scaffolded into the plugin working tree, from the template
assert_pass test -f "$root/plugins/newplug/.github/workflows/release.yml"
assert_pass grep -q "name: Release" "$root/plugins/newplug/.github/workflows/release.yml"
assert_pass grep -q "gh workflow run release.yml -f version=" "$root/plugins/newplug/.github/workflows/release.yml"
assert_pass diff -q "$(cd "$HERE/.." && pwd)/templates/release.yml" "$root/plugins/newplug/.github/workflows/release.yml"
# CLAUDE.md release rule scaffolded (CREATE case — empty repo had no CLAUDE.md)
assert_pass test -f "$root/plugins/newplug/CLAUDE.md"
assert_pass grep -qF "<!-- BEGIN zorskill-release" "$root/plugins/newplug/CLAUDE.md"
assert_pass grep -q "gh workflow run release.yml -f version=" "$root/plugins/newplug/CLAUDE.md"
# marketplace entry added + aggregate bumped
assert_eq "$(jq -r '.plugins[]|select(.name=="newplug")|.version' "$root/.claude-plugin/marketplace.json")" "0.1.0" "entry added"
assert_eq "$(jq -r '.version' "$root/.claude-plugin/marketplace.json")" "1.0.1" "aggregate bumped"

TDIR="$(cd "$HERE/.." && pwd)/templates"
# --- APPEND case: existing CLAUDE.md WITHOUT the marker → block appended once, original preserved ---
bare2="$FIX/appendplug.git"; work2="$FIX/appendplug-work"
git init --quiet --bare "$bare2"; git -C "$bare2" symbolic-ref HEAD refs/heads/main
git clone --quiet "$bare2" "$work2"; mkdir -p "$work2/.claude-plugin"
printf '{ "name":"appendplug","description":"x","version":"0.1.0" }\n' > "$work2/.claude-plugin/plugin.json"
printf -- '---\nname: appendplug\ndescription: "x"\n---\n' > "$work2/SKILL.md"
printf '# appendplug\n\nORIGINAL CLAUDE CONTENT keep me.\n' > "$work2/CLAUDE.md"
git -C "$work2" add -A && git -C "$work2" -c user.email=t@t -c user.name=t commit --quiet -m init
git -C "$work2" push --quiet origin HEAD:refs/heads/main
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_new appendplug --repo-url "'"$bare2"'"'
assert_pass grep -qF "ORIGINAL CLAUDE CONTENT keep me." "$root/plugins/appendplug/CLAUDE.md"   # original preserved
assert_eq "$(grep -cF '<!-- BEGIN zorskill-release' "$root/plugins/appendplug/CLAUDE.md")" "1" "append: block added exactly once"

# --- ALREADY-MANAGED case: CLAUDE.md already has the marker → new leaves it untouched (idempotent) ---
bare3="$FIX/managedplug.git"; work3="$FIX/managedplug-work"
git init --quiet --bare "$bare3"; git -C "$bare3" symbolic-ref HEAD refs/heads/main
git clone --quiet "$bare3" "$work3"; mkdir -p "$work3/.claude-plugin"
printf '{ "name":"managedplug","description":"x","version":"0.1.0" }\n' > "$work3/.claude-plugin/plugin.json"
printf -- '---\nname: managedplug\ndescription: "x"\n---\n' > "$work3/SKILL.md"
{ printf '# managedplug\n\nPRE-EXISTING content.\n\n'; cat "$TDIR/claude-release-block.md"; } > "$work3/CLAUDE.md"
git -C "$work3" add -A && git -C "$work3" -c user.email=t@t -c user.name=t commit --quiet -m init
git -C "$work3" push --quiet origin HEAD:refs/heads/main
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_new managedplug --repo-url "'"$bare3"'"'
assert_eq "$(grep -cF '<!-- BEGIN zorskill-release' "$root/plugins/managedplug/CLAUDE.md")" "1" "already-managed: still exactly one block (no duplicate)"
assert_pass grep -qF "PRE-EXISTING content." "$root/plugins/managedplug/CLAUDE.md"   # untouched

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; rm -rf "$FIX"; [[ $TESTS_FAIL -eq 0 ]]
