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
