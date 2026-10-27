#!/usr/bin/env bash
# UserPromptSubmit hook (write side). Keeps THIS agent's snapshot live without
# polluting siblings:
#   - mechanical fields (branch, touched, ts) recomputed from git each fire;
#   - semantic fields (task, status, note) the session set are PRESERVED;
#   - task/status auto-filled ONLY when the branch changes (= a new task);
#   - the snapshot is written ONLY when a meaningful field actually changed
#     (idempotent), so a no-op turn never bumps mtime and never re-triggers a
#     sibling's read-delta hook.
# Never appends to history — that stays event-worthy (commits + explicit posts).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

# Hook payload may carry cwd; fall back to $PWD.
payload=$(cat 2>/dev/null || true)
wd=$(printf '%s' "$payload" | json_field cwd)
[ -n "$wd" ] || wd=$(pwd)

d=$(bus_dir_for "$wd") || exit 0
[ -d "$d/current" ] || exit 0      # bus not initialized here -> nothing to do

aid=$(agent_id_for "$wd")
snap="$d/current/$aid.md"
branch=$(current_branch_for "$wd")

# Preserve semantic fields + name from the existing snapshot.
name=$(snapshot_field "$d" "$aid" name);   [ -n "$name" ] || name="$aid"
task=$(snapshot_field "$d" "$aid" task)
status=$(snapshot_field "$d" "$aid" status)
note=$(snapshot_field "$d" "$aid" note)
old_branch=$(snapshot_field "$d" "$aid" branch)

# Mechanical: in-flight files (shared definition; includes untracked).
touched=$(inflight_files "$wd")

# Task-start = branch changed (or first ever) — a transition we log to the feed.
# Auto-author a task label ONLY from a task-kind branch (conventional-commit
# prefixes). main/master, harness worktree branches (claude/…), and
# bare/detached HEAD get no invented task — their task fills in from the first
# commit subject (on-commit.sh) or an explicit post. One rule, no per-branch
# special-casing.
transition=0
if [ "$branch" != "$old_branch" ]; then
  transition=1
  case "$branch" in
    feat/*|fix/*|chore/*|refactor/*|docs/*|perf/*|test/*|style/*|build/*|ci/*)
      task=$(humanize_slug "$branch"); status="working" ;;
  esac
fi
[ -n "$status" ] || status="working"

ts=$(date +%Y-%m-%dT%H:%M)
epoch=$(date +%s)
candidate=$(render_snapshot "$name" "$branch" "$status" "$task" \
            "$touched" "$note" "$ts" "$epoch")

# Idempotent: write only when meaningful content changed (timestamp excluded).
if [ -f "$snap" ] && \
   [ "$(printf '%s\n' "$candidate" | strip_volatile)" = "$(strip_volatile < "$snap")" ]; then
  exit 0
fi

printf '%s\n' "$candidate" > "$snap"

# Log the transition to the shared feed (snapshot = live state, log = narrative
# of what each sibling did). Touched-only churn is NOT a transition, so the feed
# stays a readable record of task starts rather than per-edit noise.
if [ "$transition" = 1 ]; then
  append_event "$d" "$ts" "$aid" "$name" "$branch" "$status" "$task" "$note" "$touched"
fi
