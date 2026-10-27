#!/usr/bin/env bash
# TDD harness for agent-bus auto-post. Run: bash ~/.claude/agent-bus/tests/auto-post.test.sh
# Sources the live lib.sh, exercises new helpers + auto-post.sh in temp repos.
set -uo pipefail

BIN="${AGENTBUS_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
source "$BIN/lib.sh"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n    expected: [%s]\n    got:      [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$3" "$2"; }   # eq name actual expected

echo "== unit: humanize_slug =="
eq "feat/ prefix stripped, dashes->spaces" "$(humanize_slug feat/bus-auto-write)" "bus auto write"
eq "fix/ prefix + underscore"              "$(humanize_slug fix/x_y)"             "x y"
eq "bare branch unchanged"                 "$(humanize_slug main)"                "main"
eq "nested prefix takes last segment"      "$(humanize_slug feat/sub/thing-a)"    "thing a"

echo "== unit: strip_volatile =="
snap=$'name: a\nbranch: feat/x\nstatus: working\ntask: t\ntouched: f.sh\nnote: n\nupdated: 2026-01-01T00:00\nupdated_epoch: 123'
got=$(printf '%s\n' "$snap" | strip_volatile)
want=$'name: a\nbranch: feat/x\nstatus: working\ntask: t\ntouched: f.sh\nnote: n'
eq "drops updated + updated_epoch lines" "$got" "$want"

echo "== unit: render_snapshot field order =="
got=$(render_snapshot a feat/x working "my task" "f.sh" "" 2026-01-01T00:00 123)
want=$'name: a\nbranch: feat/x\nstatus: working\ntask: my task\ntouched: f.sh\nnote: \nupdated: 2026-01-01T00:00\nupdated_epoch: 123'
eq "render matches canonical snapshot bytes" "$got" "$want"

# ---- integration helpers ----
mkrepo() {  # echoes path to a fresh initialized bus repo
  local r; r=$(mktemp -d "${TMPDIR:-/tmp}/busrepo.XXXXXX")
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t; git -C "$r" config user.name t
  ( cd "$r" && git commit -q --allow-empty -m init )
  # wire a minimal bus layout (no symlink needed; auto-post resolves common dir)
  local d; d=$(bus_dir_for "$r"); ensure_layout "$d"
  printf '%s\n' "$r"
}
run_autopost() { ( cd "$1" && AGENTBUS_AGENT="$2" bash "$BIN/auto-post.sh" >/dev/null 2>&1 ); }
snapf() { local d; d=$(bus_dir_for "$1"); printf '%s/current/%s.md' "$d" "$2"; }
field() { sed -n "s/^$3: //p" "$(snapf "$1" "$2")" | head -1; }

echo "== integration: task-start on feature branch =="
R=$(mkrepo); A=agt1
( cd "$R" && git switch -qc feat/foo-bar )
printf 'x\n' > "$R/work.txt"
run_autopost "$R" "$A"
eq "task <- humanized slug"      "$(field "$R" "$A" task)"    "foo bar"
eq "status <- working"           "$(field "$R" "$A" status)"  "working"
eq "branch recorded"             "$(field "$R" "$A" branch)"  "feat/foo-bar"
eq "touched = in-flight file"    "$(field "$R" "$A" touched)" "work.txt"

echo "== integration: idempotent no-op (no mtime bump) =="
before=$(stat -f %m "$(snapf "$R" "$A")")
sleep 1
run_autopost "$R" "$A"
after=$(stat -f %m "$(snapf "$R" "$A")")
eq "unchanged state -> snapshot not rewritten" "$after" "$before"

echo "== integration: touched clears after commit (in-flight everywhere) =="
( cd "$R" && git add work.txt && git commit -q -m "add work" )
run_autopost "$R" "$A"
eq "post-commit in-flight is empty" "$(field "$R" "$A" touched)" ""
eq "task preserved across commit"   "$(field "$R" "$A" task)"    "foo bar"

echo "== integration: main branch gets no auto-task =="
R2=$(mkrepo); B=agt2
printf 'y\n' > "$R2/m.txt"
run_autopost "$R2" "$B"
eq "no auto-task on main" "$(field "$R2" "$B" task)" ""

echo "== integration: non-task branch (harness worktree) gets no auto-task =="
R3=$(mkrepo); C=agt3
( cd "$R3" && git switch -qc claude/jolly-dewdney-4a5d63 )
printf 'z\n' > "$R3/w.txt"
run_autopost "$R3" "$C"
eq "no auto-task on claude/* branch" "$(field "$R3" "$C" task)" ""
eq "but touched still recorded"      "$(field "$R3" "$C" touched)" "w.txt"
eq "and status still working"        "$(field "$R3" "$C" status)" "working"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
