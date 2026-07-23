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
