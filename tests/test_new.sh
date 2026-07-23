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
# marketplace entry added + aggregate bumped
assert_eq "$(jq -r '.plugins[]|select(.name=="newplug")|.version' "$root/.claude-plugin/marketplace.json")" "0.1.0" "entry added"
assert_eq "$(jq -r '.version' "$root/.claude-plugin/marketplace.json")" "1.0.1" "aggregate bumped"

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; rm -rf "$FIX"; [[ $TESTS_FAIL -eq 0 ]]
