#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib
_have_gh(){ return 1; }   # keep fixture sync offline (no gh probe)

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
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; _have_gh(){ return 1; }; advance_pointer "'"$root"'" demo'
assert_eq "$(read_plugin_version "$root" demo)" "0.2.0" "pointer advanced to 0.2.0"

# --- cmd_release end-to-end + guard (Task 2.3) ---
# Register a NON-UNIFORM second plugin (no plugins/brokenplug dir at all) to prove the
# scoped gate lets demo's release through despite another plugin's pre-existing debt.
tmp=$(mktemp); jq '.plugins += [{"name":"brokenplug","version":"9.9.9","source":"./plugins/brokenplug","category":"productivity"}]' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
git -C "$root" -c user.email=t@t -c user.name=t commit -aqm "add non-uniform brokenplug entry"
# end-to-end release 0.2.0 (commit-only, no --push) — MUST succeed despite brokenplug
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; _have_gh(){ return 1; }; ZORSKILL_ROOT="'"$root"'" cmd_release demo 0.2.0'
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$root/.claude-plugin/marketplace.json")" "0.2.0" "root entry after release"
assert_eq "$(jq -r '.version' "$root/.claude-plugin/marketplace.json")" "1.0.1" "aggregate after release"
assert_pass bash -c 'git -C "'"$root"'" log -1 --pretty=%s | grep -q "zorskill: demo v0.2.0"'
# guard: asking for a version the plugin repo does NOT declare must abort
assert_fail bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; _have_gh(){ return 1; }; ZORSKILL_ROOT="'"$root"'" cmd_release demo 9.9.9'

# --- mixed source: remote-sourced (url) release path — verifies the repo tip via the GitHub
#     API (stubbed here as _remote_tip_version) and carries the version into the marketplace
#     WITHOUT a submodule pointer, so no orphan plugins/<name> gitlink is ever created. ---
tmp=$(mktemp); jq '.plugins += [{"name":"rem","version":"1.0.0","source":{"source":"url","url":"https://github.com/ZorCorp/rem.git"},"description":"R. x.","category":"productivity"}]' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
git -C "$root" -c user.email=t@t -c user.name=t commit -aqm "add remote rem"
# (a) remote unreachable (no gh / private without token) → abort cleanly, NO orphan gitlink
assert_fail bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; _have_gh(){ return 1; }; _remote_tip_version(){ return 0; }; ZORSKILL_ROOT="'"$root"'" cmd_release rem 1.1.0'
assert_pass bash -c '! test -e "'"$root"'/plugins/rem"'
# (b) remote repo declares a DIFFERENT version than requested → abort (never edits the plugin repo)
assert_fail bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; _have_gh(){ return 1; }; _remote_tip_version(){ echo 1.0.0; }; ZORSKILL_ROOT="'"$root"'" cmd_release rem 1.1.0'
# (c) remote repo declares the requested version → carry into marketplace, commit, still no orphan
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; _have_gh(){ return 1; }; _remote_tip_version(){ echo 1.1.0; }; ZORSKILL_ROOT="'"$root"'" cmd_release rem 1.1.0'
assert_eq "$(jq -r '.plugins[]|select(.name=="rem")|.version' "$root/.claude-plugin/marketplace.json")" "1.1.0" "remote release: marketplace entry advanced"
assert_pass bash -c '! test -e "'"$root"'/plugins/rem"'
assert_pass bash -c 'git -C "'"$root"'" log -1 --pretty=%s | grep -q "zorskill: rem v1.1.0"'

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; rm -rf "$FIX"; [[ $TESTS_FAIL -eq 0 ]]
