#!/usr/bin/env bash
# Rebuild the project map for the current repo by hand.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python3 "$HERE/generate.py"
