#!/usr/bin/env bash
# Enable the project map for the current repo. Run once per clone; idempotent.
#
#   bash ~/.claude/project-map/bin/map-init.sh [exclude-dir ...]
#
# Creates <git-common-dir>/project-map/ (the enable marker the global hooks
# check) and writes optional top-level dir excludes. Then builds the first
# map. All state lives inside .git — nothing in the working tree.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "not in a git repo" >&2; exit 1; }
d="$common/project-map"
mkdir -p "$d"

if [ $# -gt 0 ]; then
  printf '%s\n' "$@" > "$d/exclude"
  echo "excluding top-level dirs: $*"
fi

python3 "$HERE/generate.py"
