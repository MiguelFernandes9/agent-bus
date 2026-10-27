#!/usr/bin/env bash
# Wire the agent-bus into the current repo. Run once per repo; idempotent.
#
#   bash ~/.claude/agent-bus/bin/bus-init.sh
#
# What it does:
#   - .git/agent-bus/bin -> symlink to the canonical ~/.claude/agent-bus/bin
#     (one code source for every repo; updates propagate, no drift)
#   - installs the post-commit hook (chain-safe, covers all worktrees)
# Data (current/, history.ndjson, memory.md, .seen/) stays per-repo next to
# the symlink — projects never share state, only code.
set -euo pipefail
MASTER="${AGENTBUS_MASTER:-$HOME/.claude/agent-bus/bin}"
[ -d "$MASTER" ] || { echo "canonical bin not found: $MASTER" >&2; exit 1; }

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || { echo "not in a git repo" >&2; exit 1; }
d="$common/agent-bus"
mkdir -p "$d"

# Preserve a pre-existing real bin dir (old per-repo copy) before linking.
if [ -e "$d/bin" ] && [ ! -L "$d/bin" ]; then
  mv "$d/bin" "$d/bin.pre-symlink"
  echo "kept old copy: $d/bin.pre-symlink"
fi
ln -sfn "$MASTER" "$d/bin"

bash "$d/bin/install-hooks.sh"
echo "agent-bus ready: $d"
echo "  bin -> $MASTER"
