#!/usr/bin/env bash
# Create a worktree + branch for a feature session, and copy untracked
# local context (CLAUDE.local.md) into it — git worktree add alone
# won't, since that file is deliberately not tracked.
#
# Worktrees live INSIDE the repo at .claude/worktrees/<slug> so everything
# about a project stays under one folder. That path must be git-ignored
# (a `.claude/` line in .gitignore) — the script refuses to nest an
# unignored worktree, which would show up as untracked noise in every
# sibling's `git status`.
#
# Usage: .git/agent-bus/bin/new-worktree.sh <slug> [<branch>]
#   branch defaults to feat/<slug>; based off origin/main when a remote
#   exists, else local main.
set -euo pipefail
slug="${1:?usage: new-worktree.sh <slug> [branch]}"
branch="${2:-feat/$slug}"

root=$(git rev-parse --show-toplevel)
dest="$root/.claude/worktrees/$slug"

if ! git -C "$root" check-ignore -q ".claude/worktrees/$slug"; then
  printf '\n# Claude/agent machinery (worktrees, config; never committed)\n.claude/\n' \
    >> "$root/.gitignore"
  echo "note: added '.claude/' to .gitignore (commit it when convenient)"
fi

base=origin/main
git rev-parse -q --verify origin/main >/dev/null 2>&1 || base=main

mkdir -p "$root/.claude/worktrees"
git worktree add "$dest" -b "$branch" "$base"
[ -f "$root/CLAUDE.local.md" ] && cp "$root/CLAUDE.local.md" "$dest/CLAUDE.local.md"

echo "worktree: $dest"
echo "branch:   $branch (off $base)"
