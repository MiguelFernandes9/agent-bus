#!/usr/bin/env bash
# TDD harness for agent-bus event-log layer (seq, ring cap, tail reader).
set -uo pipefail
BIN="${AGENTBUS_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)}"
source "$BIN/lib.sh"

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n    expected: [%s]\n    got:      [%s]\n' "$1" "$3" "$2"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }   # eq name actual expected

newrepo() {
  local r; r=$(mktemp -d "${TMPDIR:-/tmp}/busev.XXXXXX")
  git -C "$r" init -q; git -C "$r" config user.email t@t.t; git -C "$r" config user.name t
  ( cd "$r" && git commit -q --allow-empty -m init )
  local d; d=$(bus_dir_for "$r"); ensure_layout "$d"
  printf '%s\n' "$r"
}
hist() { printf '%s/history.ndjson' "$(bus_dir_for "$1")"; }
seqof() { tail -1 "$(hist "$1")" | python3 -c 'import json,sys;print(int(json.load(sys.stdin).get("seq",0)))'; }

echo "== max_seq =="
R=$(newrepo); H=$(hist "$R")
eq "empty history -> 0" "$(max_seq "$H")" "0"
append_event "$(bus_dir_for "$R")" 2026-01-01T00:00 other other feat/x working "task one" "" ""
eq "after 1 append -> 1" "$(max_seq "$H")" "1"

echo "== append_event increments seq + records fields =="
append_event "$(bus_dir_for "$R")" 2026-01-01T00:01 other other feat/x working "task two" "note!" "a.txt"
eq "seq increments to 2"     "$(max_seq "$H")" "2"
line=$(tail -1 "$H")
eq "task recorded"  "$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["task"])')" "task two"
eq "note recorded"  "$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["note"])')" "note!"

echo "== ring cap keeps last N, seq keeps growing =="
R2=$(newrepo); H2=$(hist "$R2")
for i in 1 2 3 4 5 6 7 8; do
  AGENTBUS_HISTORY_CAP=5 append_event "$(bus_dir_for "$R2")" 2026-01-01T00:00 a a feat/x working "t$i" "" ""
done
eq "file trimmed to cap=5" "$(wc -l < "$H2" | tr -d ' ')" "5"
eq "max seq still 8"       "$(max_seq "$H2")" "8"
eq "oldest retained is t4" "$(head -1 "$H2" | python3 -c 'import json,sys;print(json.load(sys.stdin)["task"])')" "t4"

echo "== event reader: tail since cursor, siblings only, advance =="
R3=$(newrepo); D=$(bus_dir_for "$R3"); me=reader
# seed: two sibling events + one of my own
append_event "$D" 2026-01-01T00:00 sib sib feat/x working "sib task A" "" ""
append_event "$D" 2026-01-01T00:01 sib sib feat/x working "sib task B" "" ""
append_event "$D" 2026-01-01T00:02 reader reader feat/y working "my own" "" ""
# first look with empty cursor -> baseline to max, emit NOTHING (no flood)
out1=$( cd "$R3" && AGENTBUS_AGENT="$me" bash "$BIN/read-delta.sh" </dev/null 2>/dev/null )
eq "empty cursor = baseline, no flood" "$out1" ""
eq "cursor set to max (3)" "$(cat "$D/.seen/$me")" "3"
# sibling does something new -> appears once
append_event "$D" 2026-01-01T00:03 sib sib feat/x done "sib task B" "wrapped up" ""
out2=$( cd "$R3" && AGENTBUS_AGENT="$me" bash "$BIN/read-delta.sh" </dev/null 2>/dev/null )
eq "new sibling event surfaced"  "$(printf '%s' "$out2" | grep -c 'wrapped up')" "1"
# read again, nothing new
out3=$( cd "$R3" && AGENTBUS_AGENT="$me" bash "$BIN/read-delta.sh" </dev/null 2>/dev/null )
eq "no repeat of already-read event" "$(printf '%s' "$out3" | grep -c 'wrapped up')" "0"
# my own event must never surface to me
append_event "$D" 2026-01-01T00:04 reader reader feat/y blocked "my own" "stuck" ""
out4=$( cd "$R3" && AGENTBUS_AGENT="$me" bash "$BIN/read-delta.sh" </dev/null 2>/dev/null )
eq "own events not echoed back" "$(printf '%s' "$out4" | grep -c 'stuck')" "0"

echo "== auto-post logs a transition only on task-start (branch change) =="
R4=$(newrepo); D4=$(bus_dir_for "$R4"); A=worker
( cd "$R4" && git switch -qc feat/cool-thing )
printf '1\n' > "$R4/f.txt"
( cd "$R4" && AGENTBUS_AGENT="$A" bash "$BIN/auto-post.sh" </dev/null )
eq "task-start appended 1 event" "$(wc -l < "$(hist "$R4")" | tr -d ' ')" "1"
# same branch, just more files touched -> snapshot updates, NO new event
printf '2\n' > "$R4/g.txt"
( cd "$R4" && AGENTBUS_AGENT="$A" bash "$BIN/auto-post.sh" </dev/null )
eq "touched-only change logs no event" "$(wc -l < "$(hist "$R4")" | tr -d ' ')" "1"
# switch branch -> new task-start event
( cd "$R4" && git switch -qc feat/next-thing )
( cd "$R4" && AGENTBUS_AGENT="$A" bash "$BIN/auto-post.sh" </dev/null )
eq "branch switch logs a 2nd event" "$(wc -l < "$(hist "$R4")" | tr -d ' ')" "2"

echo "== session-start baselines the cursor to max seq =="
R5=$(newrepo); D5=$(bus_dir_for "$R5"); S=starter
append_event "$D5" 2026-01-01T00:00 sib sib feat/x working "earlier work" "" ""
append_event "$D5" 2026-01-01T00:01 sib sib feat/x working "more work" "" ""
( cd "$R5" && AGENTBUS_AGENT="$S" bash "$BIN/session-start.sh" </dev/null >/dev/null 2>&1 )
eq "cursor baselined to max (2)" "$(cat "$D5/.seen/$S")" "2"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
