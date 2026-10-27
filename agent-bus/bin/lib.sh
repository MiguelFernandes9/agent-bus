#!/usr/bin/env bash
# agent-bus shared helpers. Sourced by post/read/session-start/history.
# Bus lives in the SHARED git common dir, so every worktree sees one bus.
set -euo pipefail

# Resolve absolute path of the shared bus dir for a given working directory.
# Falls back silently (empty) when not inside a git repo — callers exit 0.
bus_dir_for() {
  local wd="$1" common
  common=$(git -C "$wd" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$common" in
    /*) ;;                       # already absolute
    *)  common="$wd/$common" ;;  # make relative common dir absolute
  esac
  common=$(cd "$common" 2>/dev/null && pwd) || return 1
  printf '%s/agent-bus' "$common"
}

# Stable agent id for a working dir: env override, else worktree-root basename.
# One worktree == one agent; branch/task inside the file are the mutable bits.
agent_id_for() {
  local wd="$1" root
  if [ -n "${AGENTBUS_AGENT:-}" ]; then
    sanitize "$AGENTBUS_AGENT"; return
  fi
  root=$(git -C "$wd" rev-parse --show-toplevel 2>/dev/null) || root="$wd"
  sanitize "$(basename "$root")"
}

# Strip to [a-z0-9._-]; guards filenames + blocks path-escape via the id.
sanitize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-' | head -c 64
}

current_branch_for() {
  # On an unborn branch rev-parse prints "HEAD" AND fails; capture first so
  # the fallback replaces (not appends to) that partial output.
  local br
  br=$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null) || br=""
  printf '%s\n' "${br:-?}"
}

# Read one field from an agent's existing snapshot ("" if absent). Lets the
# commit hook preserve an intentional task/status the session already set.
snapshot_field() {  # $1=bus_dir $2=agent $3=key
  local f="$1/current/$2.md"
  [ -f "$f" ] || return 0
  sed -n "s/^$3: //p" "$f" | head -1
}

# Humanize a branch into a task label: drop the leading "kind/" prefix
# (feat/, fix/, …) by keeping the last path segment, then -/_ -> spaces.
# feat/bus-auto-write -> "bus auto write". The main-branch guard lives in the
# caller; this is pure text.
humanize_slug() {
  local b="${1##*/}"
  printf '%s' "$b" | sed 's/[_-]/ /g'
}

# In-flight (uncommitted) files for a working dir: tracked changes vs HEAD plus
# untracked files (honoring .gitignore). Sorted + deduped for a stable order
# (so idempotence checks don't false-trigger), capped at 20, comma-joined.
# The single definition of `touched`, shared by auto-post.sh and on-commit.sh.
inflight_files() {  # $1=wd
  { git -C "$1" diff --name-only HEAD 2>/dev/null
    git -C "$1" ls-files --others --exclude-standard 2>/dev/null; } \
    | sort -u | head -n 20 | paste -sd, - || true
}

# Filter stdin, dropping the volatile timestamp lines. Lets two snapshots be
# compared for *meaningful* change, ignoring updated:/updated_epoch:.
strip_volatile() {
  grep -v -e '^updated: ' -e '^updated_epoch: '
}

# Canonical snapshot serializer — the single source of the on-disk format.
# Shared by post.sh (snapshot + history) and auto-post.sh (snapshot only) so
# their bytes match and idempotence comparisons are exact.
render_snapshot() {  # name branch status task touched note ts epoch
  cat <<EOF
name: $1
branch: $2
status: $3
task: $4
touched: $5
note: $6
updated: $7
updated_epoch: $8
EOF
}

# Extract one top-level string field from a hook's JSON stdin payload.
# Uses python3 (assumed present). Echoes empty on miss.
json_field() {
  python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
v=d.get(sys.argv[1],"")
print(v if isinstance(v,str) else "")
' "$1" 2>/dev/null || true
}

ensure_layout() {
  local d="$1"
  mkdir -p "$d/current" "$d/.seen"
  [ -f "$d/history.ndjson" ] || : > "$d/history.ndjson"
}

# Drop snapshots whose `updated_epoch:` is older than STALE_SECS (default 24h).
# History is never pruned here — it is the permanent record.
STALE_SECS="${AGENTBUS_STALE_SECS:-86400}"
gc_stale() {
  local d="$1" now f age epoch
  now=$(date +%s)
  for f in "$d"/current/*.md; do
    [ -e "$f" ] || continue
    epoch=$(sed -n 's/^updated_epoch: //p' "$f" | head -1)
    [ -n "$epoch" ] || continue
    age=$(( now - epoch ))
    if [ "$age" -gt "$STALE_SECS" ]; then rm -f "$f"; fi
  done
  return 0   # never let a false test trip `set -e` in the caller
}

# Portable advisory lock (macOS has no flock). Atomic mkdir spin, ~5s cap.
bus_lock() {
  local lock="$1" tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -gt 100 ] && return 1
    sleep 0.05
  done
  return 0
}
bus_unlock() { rmdir "$1" 2>/dev/null || true; }

# ---- event log (append-only, ring-capped) ---------------------------------
# Each event carries a monotonic `seq`, so a reader's cursor survives ring
# trimming (it compares seq values, not byte/line offsets). Cap is read per
# call from the env (default 500) so it is testable.

# Last seq in a history file (0 when empty/absent).
max_seq() {  # $1=history-file
  local f="$1"
  [ -s "$f" ] || { printf '0\n'; return 0; }
  tail -1 "$f" | python3 -c 'import json,sys
try: print(int(json.load(sys.stdin).get("seq",0)))
except Exception: print(0)' 2>/dev/null || printf '0\n'
}

# Append one event under the history lock, stamping the next seq, then ring-trim
# to the cap. The single writer path shared by post.sh and auto-post.sh.
append_event() {  # d ts agent name branch status task note touched
  local d="$1"; shift
  local hist="$d/history.ndjson" lock="$d/.history.lock"
  local cap="${AGENTBUS_HISTORY_CAP:-500}"
  ensure_layout "$d"
  bus_lock "$lock" || echo "warn: history lock timeout, appending unlocked" >&2
  local seq; seq=$(( $(max_seq "$hist") + 1 ))
  python3 -c '
import json,sys
ks=["seq","ts","agent","name","branch","status","task","note","touched"]
d=dict(zip(ks,sys.argv[1:]))
d["seq"]=int(d["seq"])
print(json.dumps(d))
' "$seq" "$@" >> "$hist"
  local n; n=$(wc -l < "$hist" | tr -d ' ')
  if [ "$n" -gt "$cap" ]; then
    tail -n "$cap" "$hist" > "$hist.tmp" && mv "$hist.tmp" "$hist"
  fi
  bus_unlock "$lock"
}
