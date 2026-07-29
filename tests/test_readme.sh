#!/usr/bin/env bash
# Tier-A static-fixture tests for README Skills-table sync (no real git).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib

# Keep sync offline by default: no gh → sync skips its 🔒 visibility probe. A dedicated test below
# overrides _have_gh/_repo_visibility to exercise the 🔒 marker.
_have_gh(){ return 1; }

BEGIN='<!-- BEGIN SKILLS (managed by zorskill-dev) -->'
END='<!-- END SKILLS -->'

# write_market <root> <name:::desc> ...  → marketplace.json + .gitmodules
write_market(){
  local root="$1"; shift
  mkdir -p "$root/.claude-plugin"
  local js='{"name":"zorskill","version":"1.0.0","plugins":[]}'
  local pair name desc
  : > "$root/.gitmodules"
  for pair in "$@"; do
    name="${pair%%:::*}"; desc="${pair#*:::}"
    js="$(printf '%s' "$js" | jq --arg n "$name" --arg d "$desc" '.plugins += [{"name":$n,"version":"1.0.0","source":("./plugins/"+$n),"description":$d}]')"
    printf '[submodule "plugins/%s"]\n\tpath = plugins/%s\n\turl = https://github.com/ZorCorp/%s.git\n' "$name" "$name" "$name" >> "$root/.gitmodules"
  done
  printf '%s\n' "$js" > "$root/.claude-plugin/marketplace.json"
}

# write_readme <root> <row-line> ...  → README with a managed block containing the rows
write_readme(){
  local root="$1"; shift
  { echo "# zorskill"; echo; echo "## Skills"; echo; echo "$BEGIN"
    echo "| Skill | Description | Source |"; echo "|-------|-------------|--------|"
    local r; for r in "$@"; do echo "$r"; done
    echo "$END"; echo; echo "footer text"; } > "$root/README.md"
}

# --- sync_readme: add missing row + preserve curated description ---
r1="$(mktemp -d)"
write_market "$r1" "demo:::Demo plugin blurb. Extra sentence." "newp:::New plugin seeded. Second sentence."
write_readme "$r1" '| `demo` | CURATED demo text | [ZorCorp/demo](https://github.com/ZorCorp/demo) |'
sync_readme "$r1" >/dev/null
assert_pass grep -qF 'CURATED demo text' "$r1/README.md"     # curated preserved
assert_fail grep -qF 'Demo plugin blurb' "$r1/README.md"      # NOT overwritten by marketplace text
assert_pass grep -qF '`newp`' "$r1/README.md"                 # new plugin row added
assert_pass grep -qF 'New plugin seeded.' "$r1/README.md"     # seeded from first sentence
assert_fail grep -qF 'Second sentence' "$r1/README.md"        # only first sentence seeded
rm -rf "$r1"

# --- sync_readme: remove delisted plugin's row ---
r2="$(mktemp -d)"
write_market "$r2" "demo:::Demo. x."
write_readme "$r2" '| `demo` | Demo curated | [ZorCorp/demo](https://github.com/ZorCorp/demo) |' '| `oldp` | Old removed | [ZorCorp/oldp](https://github.com/ZorCorp/oldp) |'
sync_readme "$r2" >/dev/null
assert_pass grep -qF '`demo`' "$r2/README.md"
assert_fail grep -qF '`oldp`' "$r2/README.md"                 # delisted row removed
rm -rf "$r2"

# --- check_readme: flags drift (missing row = ERROR) ---
r3="$(mktemp -d)"
write_market "$r3" "demo:::D. x." "newp:::N. x."
write_readme "$r3" '| `demo` | d | [ZorCorp/demo](https://github.com/ZorCorp/demo) |'
assert_fail check_readme "$r3"                                 # newp missing → ERROR
rm -rf "$r3"

# --- check_readme: flags delisted extra row = ERROR ---
r4="$(mktemp -d)"
write_market "$r4" "demo:::D. x."
write_readme "$r4" '| `demo` | d | [ZorCorp/demo](https://github.com/ZorCorp/demo) |' '| `ghost` | g | [ZorCorp/ghost](https://github.com/ZorCorp/ghost) |'
assert_fail check_readme "$r4"                                 # ghost not in marketplace → ERROR
rm -rf "$r4"

# --- check_readme: passes when in sync ---
r5="$(mktemp -d)"
write_market "$r5" "demo:::D. x."
write_readme "$r5" '| `demo` | d | [ZorCorp/demo](https://github.com/ZorCorp/demo) |'
assert_pass check_readme "$r5"
rm -rf "$r5"

# --- graceful when no markers (no crash, clear non-zero) ---
r6="$(mktemp -d)"; mkdir -p "$r6/.claude-plugin"
write_market "$r6" "demo:::D. x."
printf '# zorskill\n\nno managed markers here\n' > "$r6/README.md"
assert_fail check_readme "$r6"
assert_fail sync_readme "$r6"
rm -rf "$r6"

# --- idempotency: sync twice = no further change ---
r7="$(mktemp -d)"
write_market "$r7" "demo:::Demo. x." "newp:::New. y."
write_readme "$r7" '| `demo` | curated | [ZorCorp/demo](https://github.com/ZorCorp/demo) |'
sync_readme "$r7" >/dev/null; cp "$r7/README.md" "$r7/after1"
sync_readme "$r7" >/dev/null
assert_pass diff -q "$r7/after1" "$r7/README.md"
rm -rf "$r7"

# --- mixed source: sync emits a row for a REMOTE plugin with the link from source.repo; idempotent ---
rmx="$(mktemp -d)"; mkdir -p "$rmx/.claude-plugin"
cat > "$rmx/.claude-plugin/marketplace.json" <<'J'
{"name":"zorskill","version":"1.0.0","plugins":[
 {"name":"demo","version":"1.0.0","source":"./plugins/demo","description":"Demo. x."},
 {"name":"rem","version":"9.9.9","source":{"source":"github","repo":"ZorCorp/rem"},"description":"Remote plugin blurb. More."}]}
J
printf '[submodule "plugins/demo"]\n\tpath = plugins/demo\n\turl = https://github.com/ZorCorp/demo.git\n' > "$rmx/.gitmodules"
write_readme "$rmx"
sync_readme "$rmx" >/dev/null
assert_pass grep -qF '`rem`' "$rmx/README.md"                                         # remote plugin gets a row
assert_pass grep -qF '[ZorCorp/rem](https://github.com/ZorCorp/rem)' "$rmx/README.md" # Source link from source.repo
assert_pass grep -qF 'Remote plugin blurb.' "$rmx/README.md"                          # seeded from marketplace desc
assert_pass check_readme "$rmx"                                                        # roster in sync (submodule + remote)
# curate the remote row's description, sync again → preserved, README unchanged (idempotent)
sed -i.bak 's/Remote plugin blurb./CURATED remote text/' "$rmx/README.md"; rm -f "$rmx/README.md.bak"
cp "$rmx/README.md" "$rmx/after1"; sync_readme "$rmx" >/dev/null
assert_pass diff -q "$rmx/after1" "$rmx/README.md"
assert_pass grep -qF 'CURATED remote text' "$rmx/README.md"
rm -rf "$rmx"

# --- sync marks a confirmed-private plugin's row with 🔒 (best-effort, gated on gh); idempotent ---
lk="$(mktemp -d)"; mkdir -p "$lk/.claude-plugin"
cat > "$lk/.claude-plugin/marketplace.json" <<'J'
{"name":"zorskill","version":"1.0.0","plugins":[
 {"name":"pubp","version":"1.0.0","source":{"source":"github","repo":"ZorCorp/pubp"},"description":"Public plugin. x."},
 {"name":"privp","version":"1.0.0","source":{"source":"github","repo":"ZorCorp/privp"},"description":"Private plugin. x."}]}
J
: > "$lk/.gitmodules"
write_readme "$lk"
_have_gh(){ return 0; }; _repo_visibility(){ case "$1" in */privp) echo private;; *) echo public;; esac; }
sync_readme "$lk" >/dev/null
assert_pass grep -qF '| `privp` | 🔒 ' "$lk/README.md"     # confirmed-private row marked with 🔒
assert_fail grep -qF '| `pubp` | 🔒'  "$lk/README.md"      # public row NOT marked
# idempotent: a second sync doesn't add a second 🔒
cp "$lk/README.md" "$lk/a1"; sync_readme "$lk" >/dev/null
assert_pass diff -q "$lk/a1" "$lk/README.md"
_have_gh(){ return 1; }   # restore offline default
rm -rf "$lk"

echo "  ($TESTS_RUN run, $TESTS_FAIL failed)"; [[ $TESTS_FAIL -eq 0 ]]
