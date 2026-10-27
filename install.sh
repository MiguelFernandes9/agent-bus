#!/usr/bin/env bash
# Install agent-bus + project-map for Claude Code.
#
#   ./install.sh            link both tools into ~/.claude (backs up anything there)
#   ./install.sh --hooks    also merge hooks/settings.hooks.json into
#                           ~/.claude/settings.json (a timestamped backup is kept)
#
# The hook commands and bus-init.sh expect the tools at ~/.claude/agent-bus and
# ~/.claude/project-map, so this links those paths to this checkout. Updating is
# then just `git pull` here. Nothing is installed into any project until you run
# bus-init.sh / map-init.sh inside it.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
want_hooks=0

for arg in "$@"; do
  case "$arg" in
    --hooks) want_hooks=1 ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# --- requirements -----------------------------------------------------------
missing=0
for cmd in bash git python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required: $cmd" >&2; missing=1; }
done
[ "$missing" -eq 0 ] || exit 1
command -v node >/dev/null 2>&1 \
  || echo "note: node not found; project-map will list TypeScript files without symbols"

# --- link the tools ---------------------------------------------------------
stamp=$(date +%Y%m%d-%H%M%S)
link() {  # $1=source dir in repo, $2=target path
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    mv "$dst" "$dst.bak.$stamp"
    echo "backed up existing $dst -> $dst.bak.$stamp"
  fi
  ln -s "$src" "$dst"
  echo "linked $dst -> $src"
}

mkdir -p "$CLAUDE_DIR"
chmod +x "$REPO"/agent-bus/bin/*.sh "$REPO"/project-map/bin/*.sh
link "$REPO/agent-bus" "$CLAUDE_DIR/agent-bus"
link "$REPO/project-map" "$CLAUDE_DIR/project-map"

# --- optional: merge hooks into settings.json --------------------------------
if [ "$want_hooks" -eq 1 ]; then
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$stamp"
    echo "backed up $SETTINGS -> $SETTINGS.bak.$stamp"
  fi
  python3 - "$SETTINGS" "$REPO/hooks/settings.hooks.json" <<'PY'
import json, os, sys

settings_path, hooks_path = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
with open(hooks_path) as f:
    wanted = json.load(f)["hooks"]

hooks = settings.setdefault("hooks", {})
added = 0
for event, groups in wanted.items():
    existing = hooks.setdefault(event, [])
    present = {h.get("command") for g in existing for h in g.get("hooks", [])}
    for group in groups:
        new = [h for h in group["hooks"] if h["command"] not in present]
        if new:
            existing.append({**{k: v for k, v in group.items() if k != "hooks"},
                             "hooks": new})
            added += len(new)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"merged {added} hook(s) into {settings_path} (existing ones left untouched)")
PY
else
  echo
  echo "Hooks not installed. Either re-run with --hooks, or merge"
  echo "  $REPO/hooks/settings.hooks.json"
  echo "into the \"hooks\" section of $SETTINGS by hand."
fi

cat <<EOF

Next, inside each repo you want to coordinate:
  bash ~/.claude/agent-bus/bin/bus-init.sh      # enable the agent bus
  bash ~/.claude/project-map/bin/map-init.sh    # enable the code map (optional)
EOF
