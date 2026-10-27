#!/usr/bin/env bash
# Retire this agent from the bus: append a final history event and remove its
# live snapshot, so siblings see it gone on their next prompt (delta) and it
# stops appearing in the live-siblings list. History keeps the record.
#
# Runs as a SessionEnd hook (reads the {cwd, reason} JSON payload on stdin)
# so ANY claude session that ends — deck kill/delete, terminal exit, app —
# retires itself. Also runnable by hand from inside an agent's checkout:
#   .git/agent-bus/bin/retire.sh
#
# No-ops when the agent has no live snapshot (e.g. `agent kill` already
# retired it), so kill + SessionEnd never double-post.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

payload=$(cat 2>/dev/null || true)
wd=$(printf '%s' "$payload" | json_field cwd)
[ -n "$wd" ] || wd=$(pwd)
reason=$(printf '%s' "$payload" | json_field reason)
[ -n "$reason" ] || reason="exit"

d=$(bus_dir_for "$wd") || exit 0
aid=$(agent_id_for "$wd")
[ -f "$d/current/$aid.md" ] || exit 0     # already retired / never posted

(cd "$wd" && bash "$HERE/post.sh" --status ended \
   --note "session ended ($reason)") >/dev/null 2>&1 || true
rm -f "$d/current/$aid.md"
exit 0
