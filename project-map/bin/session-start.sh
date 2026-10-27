#!/usr/bin/env bash
# SessionStart hook (global): if this repo is map-enabled, rebuild the map and
# inject the compact index so the session knows the layout and where to look
# before answering code questions. Silent no-op in unmapped repos.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

cat >/dev/null 2>&1 || true              # drain hook stdin; unused
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || true

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || exit 0
[ -d "$common/project-map" ] || exit 0

python3 "$HERE/generate.py" >/dev/null 2>&1 || exit 0

gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
summary="$gitdir/project-map/summary.md"
[ -f "$summary" ] && cat "$summary"
exit 0
