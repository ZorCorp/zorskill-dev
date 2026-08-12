#!/usr/bin/env bash
# Ref-pinned remote sources: check_refs, apply_release_versions ref advance, drift tag guard.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/../scripts/zorskill-dev.sh" --lib

# Fixture: a marketplace whose single plugin is REMOTE-sourced (url object) and ref-pinned.
# $1 root, $2 name, $3 version, $4 ref
make_remote_root(){
  local root="$1" name="$2" ver="$3" ref="$4"
  mkdir -p "$root/.claude-plugin"
  cat > "$root/.claude-plugin/marketplace.json" <<JSON
{ "name":"zorskill","version":"1.0.0","plugins":[
  {"name":"$name","version":"$ver","source":{"source":"url","url":"https://github.com/ZorCorp/$name.git","ref":"$ref"},"category":"productivity"} ]}
JSON
  : > "$root/.gitmodules"
}

FIX="$(mktemp -d)"

# --- check_refs ---
_have_gh(){ return 0; }

make_remote_root "$FIX/ok" demo 1.2.0 v1.2.0
_remote_tag_exists(){ return 0; }                       # tag exists
assert_pass check_refs "$FIX/ok"

_remote_tag_exists(){ return 1; }                       # tag confirmed missing → ERROR
assert_fail check_refs "$FIX/ok"

_remote_tag_exists(){ return 2; }                       # unreachable → note only, still passes
assert_pass check_refs "$FIX/ok"

make_remote_root "$FIX/mismatch" demo 1.2.0 v9.9.9      # ref contradicts version → ERROR (no network needed)
_remote_tag_exists(){ return 0; }
assert_fail check_refs "$FIX/mismatch"

# A string-source plugin has no ref — check_refs ignores it entirely.
make_fake_root "$FIX/strsrc" demo 0.1.0 0.1.0
assert_pass check_refs "$FIX/strsrc"

# --- apply_release_versions advances version AND ref together ---
make_remote_root "$FIX/rel" demo 1.2.0 v1.2.0
agg="$(apply_release_versions "$FIX/rel" demo 1.3.0 "" v1.3.0)"
assert_eq "$agg" "1.0.1" "aggregate patch-bumped"
assert_eq "$(jq -r '.plugins[0].version' "$FIX/rel/.claude-plugin/marketplace.json")" "1.3.0" "entry version advanced"
assert_eq "$(jq -r '.plugins[0].source.ref' "$FIX/rel/.claude-plugin/marketplace.json")" "v1.3.0" "entry ref advanced with it"

# Omitting the ref arg leaves .source.ref untouched (submodule/refless callers).
make_remote_root "$FIX/rel2" demo 1.2.0 v1.2.0
apply_release_versions "$FIX/rel2" demo 1.3.0 >/dev/null
assert_eq "$(jq -r '.plugins[0].source.ref' "$FIX/rel2/.claude-plugin/marketplace.json")" "v1.2.0" "ref untouched without ref arg"

# --- drift (dry-run): tag guard on ref-pinned remote entries ---
_remote_tip_version(){ echo 2.0.0; }                    # repo tip released 2.0.0

make_remote_root "$FIX/drift1" demo 1.2.0 v1.2.0
_remote_tag_exists(){ return 0; }                       # tag v2.0.0 exists → drift detected
cd "$FIX/drift1"
out="$(ZORSKILL_ROOT="$FIX/drift1" cmd_drift --dry-run)"
assert_eq 0 $? "drift dry-run runs"
case "$out" in *"DRIFT (remote)"*) _ok "ref-pinned drift detected when tag exists";; *) _no "expected remote DRIFT, got: $out";; esac

make_remote_root "$FIX/drift2" demo 1.2.0 v1.2.0
_remote_tag_exists(){ return 1; }                       # released but UNTAGGED → skipped, no drift
out="$(ZORSKILL_ROOT="$FIX/drift2" cmd_drift --dry-run)"
case "$out" in *"released but untagged"*) _ok "untagged tip skipped with warning";; *) _no "expected untagged skip, got: $out";; esac
case "$out" in *"no drift"*) _ok "untagged tip not counted as drift";; *) _no "untagged tip wrongly counted as drift: $out";; esac
cd "$HERE"

rm -rf "$FIX"
echo "test_refs: $TESTS_RUN run, $TESTS_FAIL failed"
exit $((TESTS_FAIL > 0))
