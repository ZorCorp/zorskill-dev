#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib

# Build a local bare "plugin" repo declaring version 0.2.0, and a superproject
# fixture that mounts it as a submodule pinned at 0.1.0 with a matching root entry.
FIX="$(mktemp -d)"
bare="$FIX/demo.git"; work="$FIX/demo-work"; root="$FIX/root"
git init --quiet --bare "$bare"
git -C "$bare" symbolic-ref HEAD refs/heads/main   # pin default branch to main (git may default to master)
git clone --quiet "$bare" "$work"
mkdir -p "$work/.claude-plugin"
printf '{ "name":"demo","description":"x","version":"0.1.0" }\n' > "$work/.claude-plugin/plugin.json"
printf -- '---\nname: demo\ndescription: "x"\n---\n' > "$work/SKILL.md"
git -C "$work" add -A && git -C "$work" -c user.email=t@t -c user.name=t commit --quiet -m v0.1.0
git -C "$work" push --quiet origin HEAD:refs/heads/main
# superproject
git init --quiet "$root"; mkdir -p "$root/.claude-plugin"
cat > "$root/.claude-plugin/marketplace.json" <<JSON
{ "name":"zorskill","version":"1.0.0","plugins":[
  {"name":"demo","version":"0.1.0","source":"./plugins/demo","category":"productivity"} ]}
JSON
git -C "$root" -c protocol.file.allow=always submodule add --quiet "$bare" plugins/demo
git -C "$root" -c user.email=t@t -c user.name=t commit --quiet -m init
# now push a 0.2.0 to the plugin repo (simulates the human's plugin-side release)
printf '{ "name":"demo","description":"x","version":"0.2.0" }\n' > "$work/.claude-plugin/plugin.json"
git -C "$work" add -A && git -C "$work" -c user.email=t@t -c user.name=t commit --quiet -m v0.2.0
git -C "$work" push --quiet origin HEAD:refs/heads/main

# advance_pointer should move demo to the 0.2.0 tip
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; advance_pointer "'"$root"'" demo'
assert_eq "$(read_plugin_version "$root" demo)" "0.2.0" "pointer advanced to 0.2.0"

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; rm -rf "$FIX"; [[ $TESTS_FAIL -eq 0 ]]
