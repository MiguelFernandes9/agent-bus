#!/usr/bin/env bash
# Post agent state to the bus: overwrite live snapshot + append to history.
# Run by the session whenever its state changes.
#
# Usage:
#   tools/agent-bus/post.sh --status working --task "regen bars" \
#       [--note "blocked on x"] [--name plot-redo] [--touched "a.py,b.py"]
#
# --name defaults to the agent id (worktree basename). --branch is auto.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WD=$(pwd)
status="" task="" note="" name="" touched=""
while [ $# -gt 0 ]; do
  case "$1" in
    --status)  status="$2"; shift 2 ;;
    --task)    task="$2"; shift 2 ;;
    --note)    note="$2"; shift 2 ;;
    --name)    name="$2"; shift 2 ;;
    --touched) touched="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

d=$(bus_dir_for "$WD") || { echo "not in a git repo" >&2; exit 1; }
ensure_layout "$d"

aid=$(agent_id_for "$WD")
branch=$(current_branch_for "$WD")
[ -n "$name" ] || name="$aid"
ts=$(date +%Y-%m-%dT%H:%M)
epoch=$(date +%s)

# 1) live snapshot — overwritten each post (shared serializer)
render_snapshot "$name" "$branch" "${status:-working}" "${task:-}" \
  "${touched:-}" "${note:-}" "$ts" "$epoch" > "$d/current/$aid.md"

# 2) permanent history — seq-stamped, lock-guarded, ring-capped append
append_event "$d" "$ts" "$aid" "$name" "$branch" \
  "${status:-working}" "${task:-}" "${note:-}" "${touched:-}"

echo "posted: $aid ($branch) status=${status:-working}"
