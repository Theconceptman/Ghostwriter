#!/bin/bash
# Builds Ghostwriter.app and installs it to /Applications, like any other Mac app.
# Re-run this after every code change to update the installed copy.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/make_app.sh

TARGET="/Applications/Ghostwriter.app"
if pkill -x Ghostwriter 2>/dev/null; then
  for _ in {1..50}; do
    pgrep -x Ghostwriter >/dev/null || break
    sleep 0.1
  done
  if pgrep -x Ghostwriter >/dev/null; then
    echo "Ghostwriter did not stop; install aborted." >&2
    exit 1
  fi
fi
if [ -d "$TARGET" ]; then
  echo "Replacing existing ${TARGET}…"
  rm -rf "$TARGET"
fi
cp -R dist/Ghostwriter.app "$TARGET"

echo "Installed: $TARGET"
open "$TARGET"
