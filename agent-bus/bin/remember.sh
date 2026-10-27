#!/usr/bin/env bash
# Append a fact to the shared agent-bus memory (.git/agent-bus/memory.md).
# The file lives in the git common dir, so it is shared LIVE across every
# worktree of this clone — no commit, no push, no merge. It is surfaced into
# every session at SessionStart.
#
# Usage:
#   <bus>/bin/remember.sh "canonical result family is d64_v3"
#   <bus>/bin/remember.sh --tag decision "report mean ± std across 10 runs"
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="$2"; shift 2 ;;
    --)    shift; break ;;
    -*)    echo "unknown arg: $1" >&2; exit 2 ;;
    *)     break ;;
  esac
done
fact="$*"
[ -n "$fact" ] || { echo "usage: remember.sh [--tag <kind>] \"<fact>\"" >&2; exit 2; }

d=$(bus_dir_for "$(pwd)") || { echo "not in a git repo" >&2; exit 1; }
ensure_layout "$d"
mem="$d/memory.md"

if [ ! -f "$mem" ]; then
  cat > "$mem" <<'EOF'
# agent-bus shared memory

<!-- Shared across all worktrees of this clone via the .git common dir.
     Append with the bus remember.sh. Not tracked, not pushed.
     Surfaced into every session at SessionStart. -->

EOF
fi

aid=$(agent_id_for "$(pwd)")
ts=$(date +%Y-%m-%dT%H:%M)
prefix="- $ts [$aid]"
[ -n "$tag" ] && prefix="$prefix ($tag)"

lock="$d/.memory.lock"
bus_lock "$lock" || echo "warn: memory lock timeout, appending unlocked" >&2
trap 'bus_unlock "$lock"' EXIT
printf '%s %s\n' "$prefix" "$fact" >> "$mem"
bus_unlock "$lock"
trap - EXIT

echo "remembered: $fact"
