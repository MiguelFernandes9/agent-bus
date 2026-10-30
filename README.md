# agent-bus

[![CI](https://github.com/MiguelFernandes9/agent-bus/actions/workflows/ci.yml/badge.svg)](https://github.com/MiguelFernandes9/agent-bus/actions/workflows/ci.yml)

**Let several Claude Code sessions work on one repository at the same time, and know about each other.**

When you run several [Claude Code](https://claude.com/claude-code) agents in
parallel on the same codebase, each in its own git worktree, they can't see
each other. One agent refactors a module while another edits it, decisions made
in one session are forgotten in the next, and you end up as the copy-paste
messenger between terminals.

This repo has two small tools that fix that with plain files, Bash and Claude
Code hooks. There is no server, no daemon and no network.

- **agent-bus** is a shared coordination layer. Every session posts what it is
  working on, and Claude Code hooks put the live status of sibling sessions,
  a feed of what they did, and durable project facts into each agent's context
  automatically.
- **project-map** is context engineering for code questions. It keeps an
  auto-refreshing map of the repo (directory tree plus every class and
  function, with signature, line number and docstring, for Python and
  TypeScript) and injects a compact index at session start, so agents look up
  the real `file:line` instead of answering from memory.

Both keep all state inside the repo's `.git` directory. Nothing lands in your
working tree and nothing can ever be committed or pushed.

## How it works

```
             repo/.git/  (shared by every worktree of the clone)
             └── agent-bus/
                 ├── current/<agent>.md   live snapshot per session (status, task, branch, touched files)
                 ├── history.ndjson       append-only event log (seq-stamped, ring-capped)
                 ├── memory.md            durable facts, shown to every new session
                 └── .seen/<agent>        per-session read cursor

  session A (main checkout)        session B (.claude/worktrees/b)        session C (...)
        │  post.sh / git commit          │                                       │
        └──────────────► writes snapshot + event ◄───────────────────────────────┘
                                         │
        Claude Code hooks ───────────────┘
        SessionStart      → memory + live siblings + recent history
        UserPromptSubmit  → only the events that are new since this session last looked (silent when nothing changed)
        post-commit (git) → every commit is posted automatically
        SessionEnd        → the session retires itself from the board
```

Because the bus lives in the **git common dir**, every worktree of a clone sees
the same bus, while different repos never share state. The scripts live once
in `~/.claude/agent-bus/bin`, and each repo's `.git/agent-bus/bin` is a symlink
to them, so an update reaches every repo at once.

Token cost is kept low on purpose:
- the per-prompt hook prints nothing unless a sibling did something new, and
  each event is shown exactly once;
- the snapshot hook only rewrites a file when a meaningful field changed;
- the full history is fetched on demand (`history.sh`), never injected
  wholesale.

## Requirements

- macOS (tested) or Linux (should work, untested) with `bash`, `git` (2.31+,
  for `--path-format`) and `python3`
- [Claude Code](https://claude.com/claude-code)
- optional: `node` plus a `typescript` package in the target repo, so
  project-map can extract TypeScript symbols

## Install

```bash
git clone https://github.com/MiguelFernandes9/agent-bus.git
cd agent-bus
./install.sh --hooks
```

`install.sh` does two things:
- It links `~/.claude/agent-bus` and `~/.claude/project-map` to this checkout.
  Anything already at those paths is renamed to `*.bak.<timestamp>`. To update
  later, just `git pull`.
- With `--hooks`, it merges [`hooks/settings.hooks.json`](hooks/settings.hooks.json)
  into `~/.claude/settings.json`. It saves a timestamped backup first, adds only
  hooks that are missing, and leaves your other settings untouched.

Without `--hooks`, merge that file into the `"hooks"` section of your settings
by hand.

The hooks are global, but they **do nothing in repos you haven't enabled**.
Enable each repo once:

```bash
cd your-repo
bash ~/.claude/agent-bus/bin/bus-init.sh                 # agent bus + git post-commit hook
bash ~/.claude/project-map/bin/map-init.sh node_modules  # code map; args = top-level dirs to skip
```

`bus-init.sh` chains onto an existing `post-commit` hook instead of replacing
it.

## Tell your agents how to use it

The hooks deliver context automatically. Posting status is something the
agents do themselves, so add a short block to your `~/.claude/CLAUDE.md`. A
ready-to-paste version is in [docs/CLAUDE-snippet.md](docs/CLAUDE-snippet.md).
The core of it:

```bash
b="$(git rev-parse --path-format=absolute --git-common-dir)/agent-bus/bin"
"$b/post.sh" --status working|blocked|done --task "<one line>" [--touched "<files>"] [--note "<context>"]
"$b/remember.sh" [--tag decision] "<durable fact for every future session>"
"$b/new-worktree.sh" <slug>        # sibling sessions: own worktree + feat/<slug> branch
"$b/history.sh" -n 50              # full log, on demand
```

The suggested workflow: the first session works in the main checkout, and
every later session creates its own worktree with `new-worktree.sh`. That
script creates `.claude/worktrees/<slug>` on a new branch and copies untracked
local context such as `CLAUDE.local.md` into it. It refuses to run unless
`.claude/` is git-ignored.

## Commands

| script | what it does |
|---|---|
| `bus-init.sh` | enable the bus in the current repo (idempotent) |
| `post.sh` | overwrite this session's live snapshot and append an event |
| `remember.sh` | append a durable fact to the shared `memory.md` |
| `history.sh` | query the event log (`-n`, `--branch`, `--agent` filters) |
| `new-worktree.sh` | create a sibling worktree and branch, copying local context |
| `retire.sh` | remove this session from the live board (also runs on SessionEnd) |
| `session-start.sh`, `read-delta.sh`, `auto-post.sh`, `on-commit.sh` | hook entry points; you don't call these |
| `map-init.sh` / `refresh.sh` | enable / rebuild the project map |

## Configuration

| env var | default | meaning |
|---|---|---|
| `AGENTBUS_AGENT` | worktree folder name | override this session's agent id |
| `AGENTBUS_HISTORY_LINES` | `10` | history events shown at session start |
| `AGENTBUS_HISTORY_CAP` | `500` | max events kept in `history.ndjson` (oldest dropped) |
| `AGENTBUS_STALE_SECS` | `86400` | snapshots older than this are garbage-collected |
| `AGENTBUS_MASTER` | `~/.claude/agent-bus/bin` | where `bus-init.sh` points the per-repo symlink |

## Security and privacy

- **Everything is local.** No network calls and no telemetry. State lives in
  `.git/agent-bus/` and `.git/project-map/`, which git never commits or pushes.
- **Hooks run shell scripts** on every session start, prompt and file edit.
  Read the scripts before installing; they're short.
- **What one agent posts becomes context for its siblings.** Treat bus notes
  like any other prompt input: a session working on untrusted content
  (for example, a cloned third-party repo) could write misleading notes. Use
  the bus only in repos where you trust all the sessions involved.
- Agent ids are sanitised to `[a-z0-9._-]`, so an id can't escape the bus
  directory.

## Tests

```bash
bash agent-bus/tests/events.test.sh      # event log: seq, ring cap, read cursor
bash agent-bus/tests/auto-post.test.sh   # snapshot hook: idempotence, field preservation
```

CI runs both suites, plus a syntax check of every script, on macOS and Linux.

## Uninstall

Remove the hook entries from `~/.claude/settings.json`. If you installed with
`--hooks`, restore the `.bak` copy. Then delete the `~/.claude/agent-bus` and
`~/.claude/project-map` symlinks. Per repo, `rm -rf .git/agent-bus .git/project-map`
and delete the agent-bus block from `.git/hooks/post-commit`.

## License

[MIT](LICENSE) © 2026 Miguel Fernandes
