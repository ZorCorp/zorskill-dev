#!/usr/bin/env bash
# zorskill-dev.sh — aggregation-side release tooling for the zorskill marketplace.
#   check                 audit version drift / JSON / both-format / submodule health
#   release <name> <x.y.z> [--push] [--marketplace-version <x.y.z>]
#   new <name> [--repo-url <url>] [--create-remote]
# Operates ONLY on the monorepo aggregation side. Never pushes to a plugin's own repo.
set -uo pipefail

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

is_semver(){ [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

_is_market_root(){ [[ -f "$1/.claude-plugin/marketplace.json" ]] && jq -e '.plugins' "$1/.claude-plugin/marketplace.json" >/dev/null 2>&1; }

resolve_root(){
  if [[ -n "${ZORSKILL_ROOT:-}" ]] && _is_market_root "$ZORSKILL_ROOT"; then echo "$ZORSKILL_ROOT"; return 0; fi
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    if _is_market_root "$d"; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  local sp; sp="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$sp" ]] && _is_market_root "$sp"; then echo "$sp"; return 0; fi
  return 1
}

# Emit each plugin's name + source path, one "name<TAB>path" per line.
_plugins(){ jq -r '.plugins[] | "\(.name)\t\(.source)"' "$1/.claude-plugin/marketplace.json"; }

check_json(){
  local root="$1" fail=0 f
  for f in "$root/.claude-plugin/marketplace.json"; do
    jq -e . "$f" >/dev/null 2>&1 || { red "  ✗ invalid JSON: ${f#$root/}"; fail=1; }
  done
  while IFS=$'\t' read -r name src; do
    f="$root/${src#./}/.claude-plugin/plugin.json"
    [[ -f "$f" ]] || continue
    jq -e . "$f" >/dev/null 2>&1 || { red "  ✗ invalid JSON: plugins/$name/.claude-plugin/plugin.json"; fail=1; }
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ JSON valid"
  return $fail
}

check_versions(){
  local root="$1" fail=0 agg name src pj_ver root_ver
  agg="$(jq -r '.version // ""' "$root/.claude-plugin/marketplace.json")"
  if is_semver "$agg"; then green "  ✓ aggregate .version present ($agg)"
  else red "  ✗ aggregate top-level .version missing or not semver: '$agg'"; fail=1; fi
  while IFS=$'\t' read -r name src; do
    root_ver="$(jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version' "$root/.claude-plugin/marketplace.json")"
    local pj="$root/${src#./}/.claude-plugin/plugin.json"
    if [[ ! -f "$pj" ]]; then red "  ✗ $name: missing .claude-plugin/plugin.json"; fail=1; continue; fi
    pj_ver="$(jq -r '.version // ""' "$pj")"
    if [[ "$root_ver" == "$pj_ver" ]] && is_semver "$root_ver"; then green "  ✓ $name @ $root_ver"
    else red "  ✗ $name VERSION DRIFT — root marketplace='$root_ver' vs plugin.json='$pj_ver'"; fail=1; fi
  done < <(_plugins "$root")
  return $fail
}

check_both_format(){
  local root="$1" fail=0 name src d
  while IFS=$'\t' read -r name src; do
    d="$root/${src#./}"
    [[ -f "$d/SKILL.md" ]] || { red "  ✗ $name: missing SKILL.md (agent-skill format)"; fail=1; }
    [[ -f "$d/.claude-plugin/plugin.json" ]] || { red "  ✗ $name: missing .claude-plugin/plugin.json (Claude-plugin format)"; fail=1; }
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ every plugin has SKILL.md + .claude-plugin/plugin.json"
  return $fail
}

check_submodules(){
  local root="$1" fail=0 line flag rest path
  # Lines: " <sha> path (desc)" normal; "-<sha>" uninit; "+<sha>" moved; "U<sha>" conflict.
  while read -r line; do
    [[ -z "$line" ]] && continue
    flag="${line:0:1}"; rest="${line:1}"; path="$(echo "$rest" | awk '{print $2}')"
    case "$flag" in
      '-') red "  ✗ submodule not initialized: $path (run: git submodule update --init $path)"; fail=1;;
      'U') red "  ✗ submodule has merge conflict: $path"; fail=1;;
      '+') yellow "  ⚠ submodule pointer differs from index (uncommitted pointer move): $path";;
    esac
  done < <(git -C "$root" submodule status 2>/dev/null)
  # Dirty worktrees inside plugin submodules
  local name src d
  while IFS=$'\t' read -r name src; do
    d="$root/${src#./}"
    [[ -d "$d/.git" || -f "$d/.git" ]] || continue
    if [[ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]]; then
      yellow "  ⚠ uncommitted changes inside plugins/$name (commit/push to its own repo before releasing)"
    fi
  done < <(_plugins "$root")
  [[ $fail -eq 0 ]] && green "  ✓ submodules initialized, no conflicts"
  return $fail
}

cmd_check(){
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; exit 1; }
  local rc=0
  echo "▸ JSON validity";                        check_json        "$root" || rc=1
  echo "▸ Version consistency (per-plugin)";      check_versions    "$root" || rc=1
  echo "▸ Both-format presence";                  check_both_format "$root" || rc=1
  echo "▸ Submodule health";                      check_submodules  "$root" || rc=1
  echo
  if [[ $rc -eq 0 ]]; then green "PASS — marketplace is consistent ($root)"; else red "FAIL — fix the ✗ items above"; fi
  return $rc
}

_sub_branch(){ # $1 root, $2 name → tracking branch (from .gitmodules or remote HEAD)
  local br; br="$(git config -f "$1/.gitmodules" --get "submodule.plugins/$2.branch" 2>/dev/null || true)"
  if [[ -z "$br" ]]; then
    br="$(git -C "$1/plugins/$2" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
  fi
  echo "${br:-main}"
}

advance_pointer(){
  local root="$1" name="$2" sub="$1/plugins/$2" br
  [[ -d "$sub" ]] || { red "no such submodule: plugins/$name"; return 1; }
  git -C "$sub" -c protocol.file.allow=always fetch --quiet origin || { red "fetch failed: $name"; return 1; }
  br="$(_sub_branch "$root" "$name")"
  git -C "$sub" checkout --quiet "origin/$br" 2>/dev/null || git -C "$sub" checkout --quiet "$br" || { red "checkout failed: $name @ $br"; return 1; }
}

read_plugin_version(){ jq -r '.version // ""' "$1/plugins/$2/.claude-plugin/plugin.json"; }

_bump_patch(){ local v="$1"; IFS=. read -r a b c <<<"$v"; echo "$a.$b.$((c+1))"; }

apply_release_versions(){
  local root="$1" name="$2" ver="$3" agg="${4:-}" cur tmp mf="$1/.claude-plugin/marketplace.json"
  is_semver "$ver" || { red "version must be x.y.z: $ver" >&2; return 2; }
  cur="$(jq -r '.version' "$mf")"
  if [[ -z "$agg" ]]; then agg="$(_bump_patch "$cur")"; fi
  is_semver "$agg" || { red "aggregate must be x.y.z: $agg" >&2; return 2; }
  tmp=$(mktemp)
  jq --arg n "$name" --arg v "$ver" --arg a "$agg" \
     '.version=$a | (.plugins[]|select(.name==$n)|.version)=$v' "$mf" > "$tmp" && mv "$tmp" "$mf"
  echo "$agg"
}

cmd_release(){
  local name="${1:-}" ver="${2:-}" push=0 agg_override="" a
  shift 2 2>/dev/null || { red "usage: release <name> <x.y.z> [--push] [--marketplace-version <x.y.z>]"; return 2; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push) push=1;;
      --marketplace-version) agg_override="${2:-}"; shift;;
      *) red "unknown flag: $1"; return 2;;
    esac; shift
  done
  is_semver "$ver" || { red "version must be x.y.z: $ver"; return 2; }
  local root; root="$(resolve_root)" || { red "cannot locate zorskill root (set ZORSKILL_ROOT)"; return 1; }
  jq -e --arg n "$name" '.plugins[]|select(.name==$n)' "$root/.claude-plugin/marketplace.json" >/dev/null 2>&1 \
    || { red "not a registered plugin: $name"; return 1; }

  echo "▸ 1/5 advance submodule pointer"; advance_pointer "$root" "$name" || return 1
  local declared; declared="$(read_plugin_version "$root" "$name")"
  echo "▸ 2/5 verify plugin repo declares $ver"
  if [[ "$declared" != "$ver" ]]; then
    red "  ✗ plugins/$name declares '$declared', you asked for '$ver'."
    red "    Bump + push $name's own repo to $ver first, then re-run. (This tool never edits a plugin's repo.)"
    return 1
  fi
  echo "▸ 3/5 sync marketplace versions"; a="$(apply_release_versions "$root" "$name" "$ver" "$agg_override")" || return 1
  echo "▸ 4/5 validate"; ( cd "$root" && cmd_check ) || { red "check failed — aborting (files bumped; revert or fix)"; return 1; }
  echo "▸ 5/5 commit"
  git -C "$root" add "plugins/$name" ".claude-plugin/marketplace.json"
  git -C "$root" commit -q -m "zorskill: $name v$ver (marketplace $a)" || yellow "  (nothing to commit?)"
  if [[ $push -eq 1 ]]; then
    git -C "$root" push origin main && green "Released $name v$ver (marketplace $a) — pushed to main."
  else
    green "Released $name v$ver (marketplace $a) — committed locally."
    echo "  Push when ready:  git -C \"$root\" push origin main"
  fi
}

render_template(){
  local tmpl="$1" name="$2" desc="$3"
  # sed with a safe delimiter; escape & and the delimiter in the replacement.
  local ename edesc
  ename="$(printf '%s' "$name" | sed 's/[&|]/\\&/g')"
  edesc="$(printf '%s' "$desc" | sed 's/[&|]/\\&/g')"
  sed -e "s|{{NAME}}|$ename|g" -e "s|{{DESCRIPTION}}|$edesc|g" "$tmpl"
}

# ... (functions added in later tasks) ...

main(){
  case "${1:-check}" in
    check)   shift; cmd_check "$@";;
    release) shift; cmd_release "$@";;
    new)     shift; cmd_new "$@";;
    *) echo "usage: $0 {check|release <name> <x.y.z> [--push]|new <name> [--repo-url URL] [--create-remote]}"; exit 2;;
  esac
}

# `source zorskill-dev.sh --lib` loads functions for tests without running main.
if [[ "${1:-}" != "--lib" ]]; then main "$@"; fi
