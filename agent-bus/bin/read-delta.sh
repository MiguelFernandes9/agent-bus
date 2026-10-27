#!/usr/bin/env bash
# UserPromptSubmit hook (read side): emit sibling EVENTS appended to the shared
# log since this session last looked. The cursor is a seq number in
# .seen/<me>; each event is surfaced exactly once and the cursor advances.
# Silent (zero tokens) when nothing new. This is the narrative feed — "what
# siblings have done" — distinct from the live snapshot board shown at
# SessionStart.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

payload=$(cat 2>/dev/null || true)
wd=$(printf '%s' "$payload" | json_field cwd)
[ -n "$wd" ] || wd=$(pwd)

d=$(bus_dir_for "$wd") || exit 0
[ -d "$d/current" ] || exit 0
gc_stale "$d"

me=$(agent_id_for "$wd")
hist="$d/history.ndjson"
marker="$d/.seen/$me"
newmax=$(max_seq "$hist")

cursor=$(cat "$marker" 2>/dev/null || true)
# First look (no cursor yet): baseline to current max so a fresh session is
# not flooded with the whole retained log. Emit nothing.
if [ -z "$cursor" ]; then
  printf '%s\n' "$newmax" > "$marker"
  exit 0
fi

out=$(python3 -c '
import json,sys
cur=int(sys.argv[1]); me=sys.argv[2]; f=sys.argv[3]
try: fh=open(f)
except Exception: sys.exit(0)
for ln in fh:
    ln=ln.strip()
    if not ln: continue
    try: r=json.loads(ln)
    except Exception: continue
    if int(r.get("seq",0))<=cur: continue
    if r.get("agent","")==me: continue
    a=r.get("agent",""); s=r.get("status",""); t=r.get("task","")
    ts=r.get("ts",""); note=r.get("note",""); tch=r.get("touched","")
    line="- "+ts+"  ["+a+"] "+s+": "+t
    if note: line+="  ("+note+")"
    if tch: line+="  ["+tch+"]"
    print(line)
' "$cursor" "$me" "$hist")

printf '%s\n' "$newmax" > "$marker"
[ -n "$out" ] || exit 0

echo "## agent-bus — sibling events since last turn"
printf '%s\n' "$out"
