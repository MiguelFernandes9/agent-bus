#!/usr/bin/env bash
# PostToolUse hook (global, Edit|Write|MultiEdit|NotebookEdit): in map-enabled
# repos, rebuild the map when a Python file was edited, so it always matches
# the code. No-op otherwise.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat 2>/dev/null || true)
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || true

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || exit 0
[ -d "$common/project-map" ] || exit 0

path=$(printf '%s' "$payload" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
ti = d.get("tool_input") or {}
p = ti.get("file_path") or ti.get("notebook_path") or ""
print(p if isinstance(p, str) else "")
' 2>/dev/null || true)

case "$path" in
  *.py|*.pyi|*.ts|*.tsx) python3 "$HERE/generate.py" >/dev/null 2>&1 || true ;;
esac
exit 0
