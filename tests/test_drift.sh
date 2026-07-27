#!/usr/bin/env bash
# Tier-B integration tests for `drift` against local bare-repo fixtures.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib

GB='<!-- BEGIN SKILLS (managed by zorskill-dev) -->'
GE='<!-- END SKILLS -->'

# build_fixture → sets FIX, bare, work, root. demo submodule pinned at 0.1.0, README in-sync.
build_fixture(){
  FIX="$(mktemp -d)"
  bare="$FIX/demo.git"; work="$FIX/demo-work"; root="$FIX/root"
  git init --quiet --bare "$bare"; git -C "$bare" symbolic-ref HEAD refs/heads/main
  git clone --quiet "$bare" "$work"; mkdir -p "$work/.claude-plugin"
  printf '{ "name":"demo","description":"Demo plugin. Extra.","version":"0.1.0" }\n' > "$work/.claude-plugin/plugin.json"
  printf -- '---\nname: demo\ndescription: "x"\n---\n' > "$work/SKILL.md"
  git -C "$work" add -A && git -C "$work" -c user.email=t@t -c user.name=t commit --quiet -m v0.1.0
  git -C "$work" push --quiet origin HEAD:refs/heads/main
  git init --quiet "$root"; mkdir -p "$root/.claude-plugin"
  cat > "$root/.claude-plugin/marketplace.json" <<JSON
{ "name":"zorskill","version":"1.0.0","plugins":[
  {"name":"demo","version":"0.1.0","source":"./plugins/demo","description":"Demo plugin. Extra.","category":"productivity"} ]}
JSON
  printf '# t\n\n## Skills\n\n%s\n| Skill | Description | Source |\n|-------|-------------|--------|\n%s\n' "$GB" "$GE" > "$root/README.md"
  git -C "$root" -c protocol.file.allow=always submodule add --quiet "$bare" plugins/demo
  sync_readme "$root" >/dev/null
  git -C "$root" -c user.email=t@t -c user.name=t add -A
  git -C "$root" -c user.email=t@t -c user.name=t commit --quiet -m init
}
# push_tip <version> [garbage] → push a new demo commit bumping version (garbage = malformed json)
push_tip(){
  if [ -n "${2:-}" ]; then printf '{ "name":"demo","version":"%s" } %s' "$1" "$2" > "$work/.claude-plugin/plugin.json"
  else printf '{ "name":"demo","description":"Demo plugin. Extra.","version":"%s" }\n' "$1" > "$work/.claude-plugin/plugin.json"; fi
  git -C "$work" add -A && git -C "$work" -c user.email=t@t -c user.name=t commit --quiet -m "v$1"
  git -C "$work" push --quiet origin HEAD:refs/heads/main
}

# === 1. detects drift, advances pointer, sets marketplace, syncs README, commits ===
build_fixture; push_tip 0.2.0
head0="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$root/.claude-plugin/marketplace.json")" "0.2.0" "marketplace entry advanced"
assert_eq "$(jq -r '.version' "$root/.claude-plugin/marketplace.json")" "1.0.1" "aggregate bumped"
assert_eq "$(read_plugin_version "$root" demo)" "0.2.0" "submodule pointer advanced"
assert_pass bash -c 'git -C "'"$root"'" log -1 --pretty=%s | grep -q "chore(drift): advance demo"'
assert_pass bash -c '[ "$(git -C "'"$root"'" rev-parse HEAD)" != "'"$head0"'" ]'  # a new commit exists
rm -rf "$FIX"

# === 2. idempotent: second run finds no drift, no commit ===
build_fixture; push_tip 0.2.0
( source "$HERE/../scripts/zorskill-dev.sh" --lib; ZORSKILL_ROOT="$root" cmd_drift >/dev/null 2>&1 )
head1="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'   # exit 0
assert_eq "$(git -C "$root" rev-parse HEAD)" "$head1" "no new commit on second run"
rm -rf "$FIX"

# === 3. broken tip: version bumped but plugin.json malformed → ABORT on check gate, clean ===
build_fixture; push_tip 0.2.0 'GARBAGE_BROKEN'
head0="$(git -C "$root" rev-parse HEAD)"
assert_fail bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'   # aborts non-zero
assert_eq "$(git -C "$root" rev-parse HEAD)" "$head0" "no commit made on abort"
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$root/.claude-plugin/marketplace.json")" "0.1.0" "marketplace reverted"
assert_eq "$(git -C "$root" status --porcelain | wc -l | tr -d ' ')" "0" "working tree clean after abort"
rm -rf "$FIX"

# === 3b. BEHIND tip (repo behind marketplace) → WARN, advance nothing, no commit, exit 0, clean ===
build_fixture   # repo tip + pinned + marketplace all 0.1.0
# manually push the marketplace entry AHEAD to 0.2.0 (simulates a revert/force-push on the plugin repo)
tmp=$(mktemp); jq '(.plugins[]|select(.name=="demo")|.version)="0.2.0"' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
git -C "$root" -c user.email=t@t -c user.name=t commit -aqm "manually bump marketplace ahead"
head0="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'   # exit 0 despite behind
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift 2>&1 | grep -q "BEHIND"'   # prints warning
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$root/.claude-plugin/marketplace.json")" "0.2.0" "behind: marketplace NOT downgraded"
assert_eq "$(git -C "$root" rev-parse HEAD)" "$head0" "behind: no commit"
assert_eq "$(git -C "$root" status --porcelain | grep -c 'plugins/demo\|marketplace')" "0" "behind: working tree clean"
rm -rf "$FIX"

# === 4. no drift → exit 0, no commit ===
build_fixture   # tip == pinned 0.1.0
head0="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'
assert_eq "$(git -C "$root" rev-parse HEAD)" "$head0" "no commit when no drift"
rm -rf "$FIX"

# === 5. --dry-run changes nothing ===
build_fixture; push_tip 0.2.0
head0="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift --dry-run'
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$root/.claude-plugin/marketplace.json")" "0.1.0" "dry-run left marketplace untouched"
assert_eq "$(git -C "$root" rev-parse HEAD)" "$head0" "dry-run made no commit"
assert_eq "$(git -C "$root" status --porcelain | grep -c 'plugins/demo\|marketplace')" "0" "dry-run left working tree clean"
rm -rf "$FIX"

# === 6. uninitialized/unreachable submodule → WARN + SKIP, process reachable, exit 0, no commit ===
build_fixture   # demo reachable, tip == marketplace 0.1.0 (no drift)
# register a 'ghost' plugin in marketplace + .gitmodules but leave it UNINITIALIZED (empty dir, no .git)
tmp=$(mktemp); jq '.plugins += [{"name":"ghost","version":"0.1.0","source":"./plugins/ghost","description":"G. x.","category":"productivity"}]' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
printf '[submodule "plugins/ghost"]\n\tpath = plugins/ghost\n\turl = https://github.com/ZorCorp/ghost.git\n' >> "$root/.gitmodules"
mkdir -p "$root/plugins/ghost"
git -C "$root" -c user.email=t@t -c user.name=t add -A
git -C "$root" -c user.email=t@t -c user.name=t commit -qm "register uninitialized ghost"
head0="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'   # exit 0 despite uninitialized ghost
# capture-then-grep via here-string: `... | grep -q` would SIGPIPE the producer under pipefail (141)
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; out="$(ZORSKILL_ROOT="'"$root"'" cmd_drift 2>&1)"; grep -q "ghost: submodule not initialized or unreachable — skipped" <<<"$out"'
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; out="$(ZORSKILL_ROOT="'"$root"'" cmd_drift 2>&1)"; grep -q "demo: marketplace=" <<<"$out"'   # reachable one still processed
assert_eq "$(git -C "$root" rev-parse HEAD)" "$head0" "uninitialized: no commit"
assert_eq "$(jq -r '.plugins[]|select(.name=="ghost")|.version' "$root/.claude-plugin/marketplace.json")" "0.1.0" "uninitialized: ghost entry unchanged"
rm -rf "$FIX"

# === 7. SCOPED GATE: a PUBLIC plugin drifts WHILE another is uninitialized → carries in + commits, exit 0 ===
build_fixture; push_tip 0.2.0    # demo drifts 0.1.0 → 0.2.0
# register an uninitialized 'ghost' alongside (empty dir, no .git) — must NOT block demo's carry-in
tmp=$(mktemp); jq '.plugins += [{"name":"ghost","version":"0.1.0","source":"./plugins/ghost","description":"G. x.","category":"productivity"}]' "$root/.claude-plugin/marketplace.json" > "$tmp" && mv "$tmp" "$root/.claude-plugin/marketplace.json"
printf '[submodule "plugins/ghost"]\n\tpath = plugins/ghost\n\turl = https://github.com/ZorCorp/ghost.git\n' >> "$root/.gitmodules"
mkdir -p "$root/plugins/ghost"
git -C "$root" -c user.email=t@t -c user.name=t add -A
git -C "$root" -c user.email=t@t -c user.name=t commit -qm "register uninitialized ghost"
head0="$(git -C "$root" rev-parse HEAD)"
assert_pass bash -c 'source '"$HERE"'/../scripts/zorskill-dev.sh --lib; ZORSKILL_ROOT="'"$root"'" cmd_drift'   # exit 0 — carries in demo despite uninitialized ghost
assert_eq "$(jq -r '.plugins[]|select(.name=="demo")|.version' "$root/.claude-plugin/marketplace.json")" "0.2.0" "scoped gate: demo carried in"
assert_eq "$(read_plugin_version "$root" demo)" "0.2.0" "scoped gate: demo pointer advanced"
assert_pass bash -c '[ "$(git -C "'"$root"'" rev-parse HEAD)" != "'"$head0"'" ]'   # a commit was made
assert_pass bash -c 'git -C "'"$root"'" log -1 --pretty=%s | grep -q "chore(drift): advance demo"'
assert_eq "$(jq -r '.plugins[]|select(.name=="ghost")|.version' "$root/.claude-plugin/marketplace.json")" "0.1.0" "scoped gate: uninitialized ghost untouched"
rm -rf "$FIX"

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
