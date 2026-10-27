#!/usr/bin/env bash
# Install the agent-bus git post-commit hook into the shared hooks dir.
# Worktrees share one hooks dir, so this runs once and covers every worktree.
# Idempotent + chain-safe: if a post-commit hook already exists and isn't
# ours, we append our call rather than clobbering it.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

hooks_dir=$(git rev-parse --git-path hooks 2>/dev/null) || {
  echo "not in a git repo" >&2; exit 1; }
case "$hooks_dir" in /*) ;; *) hooks_dir="$(pwd)/$hooks_dir" ;; esac
mkdir -p "$hooks_dir"
target="$hooks_dir/post-commit"
marker="# >>> agent-bus post-commit >>>"
call="$marker
bash \"\$(git rev-parse --path-format=absolute --git-common-dir)/agent-bus/bin/on-commit.sh\" || true
# <<< agent-bus post-commit <<<"

if [ ! -e "$target" ]; then
  printf '#!/usr/bin/env bash\n%s\n' "$call" > "$target"
  chmod +x "$target"
  echo "installed: $target"
elif grep -qF "$marker" "$target"; then
  echo "already installed: $target"
else
  printf '\n%s\n' "$call" >> "$target"   # chain onto existing hook
  chmod +x "$target"
  echo "appended agent-bus call to existing: $target"
fi
