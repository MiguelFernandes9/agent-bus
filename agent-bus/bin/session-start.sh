#!/usr/bin/env bash
# SessionStart hook: warm context for a fresh session.
#   - shared memory (durable cross-worktree facts)
#   - all LIVE sibling snapshots (current work)
#   - last N history lines (recently-done work)
# Resets this agent's delta marker so read-delta only shows future changes.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

HIST_N="${AGENTBUS_HISTORY_LINES:-10}"

payload=$(cat 2>/dev/null || true)
wd=$(printf '%s' "$payload" | json_field cwd)
[ -n "$wd" ] || wd=$(pwd)

d=$(bus_dir_for "$wd") || exit 0
ensure_layout "$d"
gc_stale "$d"

me=$(agent_id_for "$wd")
# baseline the event cursor to the current max seq: per-prompt read-delta then
# surfaces only events appended after this session started (no flood of the
# retained log).
printf '%s\n' "$(max_seq "$d/history.ndjson")" > "$d/.seen/$me"

shopt -s nullglob
siblings=()
for f in "$d"/current/*.md; do
  [ "$(basename "$f" .md)" = "$me" ] && continue
  siblings+=("$f")
done

hist=""
[ -s "$d/history.ndjson" ] && hist=$(tail -n "$HIST_N" "$d/history.ndjson")

mem=""
[ -f "$d/memory.md" ] && mem=$(grep '^- ' "$d/memory.md" || true)

# Nothing to say at all -> stay silent.
[ ${#siblings[@]} -eq 0 ] && [ -z "$hist" ] && [ -z "$mem" ] && exit 0

echo "## agent-bus context"

if [ -n "$mem" ]; then
  echo "### shared memory (.git/agent-bus/memory.md)"
  printf '%s\n' "$mem"
  echo
fi

if [ ${#siblings[@]} -gt 0 ]; then
  echo "### live siblings (current work)"
  for f in "${siblings[@]}"; do
    echo "#### $(basename "$f" .md)"
    grep -v '^updated_epoch:' "$f"   # epoch is GC-only, not for the model
    echo
  done
else
  echo "### no live siblings — you are the main session (work in the main checkout)"
fi

if [ -n "$hist" ]; then
  echo "### recent history (last $HIST_N events)"
  echo '```'
  printf '%s\n' "$hist"
  echo '```'
fi
