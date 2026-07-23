#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$HERE"/test_*.sh; do
  echo "▸ $(basename "$t")"
  bash "$t" || rc=1
done
exit $rc
