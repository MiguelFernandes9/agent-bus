#!/usr/bin/env bash
# Invoked by the git post-commit hook. Guarantees a bus post on every commit,
# even if the session forgot to call post.sh. Preserves any intentional
# task/status the session already set; always refreshes branch + history.
# Never fails the commit (git ignores our exit, but we stay quiet on error).
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh" 2>/dev/null || exit 0

wd=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
d=$(bus_dir_for "$wd") || exit 0
aid=$(agent_id_for "$wd")

subject=$(git -C "$wd" log -1 --format=%s 2>/dev/null)
# touched = in-flight (uncommitted) files — one definition shared with
# auto-post.sh. Right after a commit this is usually empty; the commit identity
# lives in --note below. Avoids two meanings of `touched` fighting each other.
files=$(inflight_files "$wd")

# Preserve intentional fields when present; else seed sensible defaults.
status=$(snapshot_field "$d" "$aid" status); [ -n "$status" ] || status="working"
task=$(snapshot_field "$d" "$aid" task);     [ -n "$task" ]   || task="$subject"

bash "$HERE/post.sh" \
  --status "$status" \
  --task "$task" \
  --touched "${files:-}" \
  --note "commit: ${subject:-}" >/dev/null 2>&1 || true
exit 0
