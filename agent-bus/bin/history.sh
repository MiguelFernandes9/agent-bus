#!/usr/bin/env bash
# On-demand history query. NOT a hook — run by the model when it wants the
# fuller record (kept out of per-turn context to avoid token bloat).
#
# Usage:
#   tools/agent-bus/history.sh                 # last 20 events, pretty
#   tools/agent-bus/history.sh -n 50           # last 50
#   tools/agent-bus/history.sh --branch feat/x # filter by branch substring
#   tools/agent-bus/history.sh --agent plot    # filter by agent/name substring
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

n=20 fbranch="" fagent=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n)        n="$2"; shift 2 ;;
    --branch)  fbranch="$2"; shift 2 ;;
    --agent)   fagent="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

d=$(bus_dir_for "$(pwd)") || { echo "not in a git repo" >&2; exit 1; }
[ -s "$d/history.ndjson" ] || { echo "(no history yet)"; exit 0; }

python3 -c '
import json,sys
n=int(sys.argv[1]); fb=sys.argv[2]; fa=sys.argv[3]
rows=[]
for ln in open(sys.argv[4]):
    ln=ln.strip()
    if not ln: continue
    try: r=json.loads(ln)
    except Exception: continue
    if fb and fb not in r.get("branch",""): continue
    if fa and fa not in (r.get("agent","")+r.get("name","")): continue
    rows.append(r)
for r in rows[-n:]:
    print(f'"'"'{r.get("ts","?"):16} {r.get("agent",""):14} {r.get("branch",""):24} '"'"'
          f'"'"'{r.get("status",""):8} {r.get("task","")}'"'"'
          + (f'"'"'  [{r["note"]}]'"'"' if r.get("note") else ""))
' "$n" "$fbranch" "$fagent" "$d/history.ndjson"
