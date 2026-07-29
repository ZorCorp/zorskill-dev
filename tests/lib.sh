#!/usr/bin/env bash
# Dependency-free assert helpers + fixture builders for zorskill-dev tests.
set -uo pipefail
TESTS_RUN=0; TESTS_FAIL=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; TESTS_FAIL=$((TESTS_FAIL+1)); }
assert_pass(){ TESTS_RUN=$((TESTS_RUN+1)); if "$@"; then _ok "pass: $*"; else _no "expected pass: $*"; fi; }
assert_fail(){ TESTS_RUN=$((TESTS_RUN+1)); if "$@"; then _no "expected fail: $*"; else _ok "fail: $*"; fi; }
assert_eq(){ TESTS_RUN=$((TESTS_RUN+1)); if [[ "$1" == "$2" ]]; then _ok "eq: $3"; else _no "eq: $3 ('$1' != '$2')"; fi; }

# Build a minimal fake marketplace root at $1 with one plugin ($2) whose
# root-entry version is $3 and whose plugin.json version is $4.
make_fake_root(){
  local root="$1" name="$2" rootver="$3" pjver="$4"
  mkdir -p "$root/.claude-plugin" "$root/plugins/$name/.claude-plugin"
  cat > "$root/.claude-plugin/marketplace.json" <<JSON
{ "name":"zorskill","version":"1.0.0","plugins":[
  {"name":"$name","version":"$rootver","source":"./plugins/$name","category":"productivity"} ]}
JSON
  cat > "$root/plugins/$name/.claude-plugin/plugin.json" <<JSON
{ "name":"$name","description":"x","version":"$pjver" }
JSON
  printf -- '---\nname: %s\ndescription: "x"\n---\n' "$name" > "$root/plugins/$name/SKILL.md"
  # Register in .gitmodules so _is_submodule classifies it as SUBMODULE-managed (not remote).
  printf '[submodule "plugins/%s"]\n\tpath = plugins/%s\n\turl = https://github.com/ZorCorp/%s.git\n' "$name" "$name" "$name" > "$root/.gitmodules"
}
