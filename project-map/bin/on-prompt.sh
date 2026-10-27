#!/usr/bin/env bash
# UserPromptSubmit hook (global): in map-enabled repos, keep the map fresh
# (rebuild only if a Python file changed since the last build) and remind the
# session to consult it before answering code questions. Silent elsewhere.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

cat >/dev/null 2>&1 || true              # drain hook stdin; unused
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || true

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || exit 0
[ -d "$common/project-map" ] || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
map="$gitdir/project-map/PROJECT_MAP.md"

# Stale if the map is absent or any non-junk source file is newer than it.
stale=1
if [ -f "$map" ]; then
  newer=$(find "$root" \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' \) \
            -not -path '*/.git/*' -not -path '*/__pycache__/*' \
            -not -path '*/.venv/*' -not -path '*/venv/*' \
            -not -path '*/node_modules/*' -not -path '*/dist/*' \
            -not -path '*/runs/*' -not -path '*/.claude/worktrees/*' \
            -newer "$map" -print -quit 2>/dev/null || true)
  [ -n "$newer" ] || stale=0
fi
[ "$stale" -eq 1 ] && python3 "$HERE/generate.py" >/dev/null 2>&1 || true

cat <<EOF
📍 Code question or edit → ALWAYS ground the answer in the map + current
source, never in recall: $map
It has the dir tree and every symbol's signature + line number. Locate the
exact file:line there, then open that span (LSP for callers/references).
This applies even if the file was already read earlier in this session —
conversation context counts as memory: siblings merge and hooks rebuild,
so code seen earlier may have changed. Re-verify before every answer.
Full search only if a symbol is missing from the map.
EOF
exit 0
