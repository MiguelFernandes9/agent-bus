# CLAUDE.md snippet

Paste this into `~/.claude/CLAUDE.md` (all projects) or a repo's `CLAUDE.md`
so your agents know how to use the bus. The hooks inject context on their
own. This block tells agents when to **post**.

```markdown
## Session coordination (agent-bus)

Detect the bus:
`b="$(git rev-parse --path-format=absolute --git-common-dir)/agent-bus/bin"`
If `$b` exists, you MUST use it:

- Post your state at session start, on task/branch switch, when blocked,
  and when done:
  `"$b/post.sh" --status working|blocked|done --task "<one line>" [--touched "<files>"] [--note "<context>"]`
- Sibling updates arrive in your context automatically via hooks; the full
  log is `"$b/history.sh"` on demand.
- Record durable cross-session facts (locked decisions, gotchas) with
  `"$b/remember.sh" [--tag <kind>] "<fact>"`. They are shown to every
  future session at start.
- Commits auto-post via a post-commit hook, but post intentionally at the
  moments above too.

Main-session model:
- If the bus reports no live siblings at session start, you are the main
  session: work directly in the main checkout.
- Otherwise create your own worktree before touching code:
  `"$b/new-worktree.sh" <slug>` (requires `.claude/` in .gitignore), and
  stay inside it. Never touch another agent's worktree.

## Code questions (project-map)

If `$(git rev-parse --path-format=absolute --git-common-dir)/project-map/`
exists, read `<git-dir>/project-map/PROJECT_MAP.md` to find the exact
`path:line` before answering a code question, then open just that span.
Never answer from memory.
```
