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
