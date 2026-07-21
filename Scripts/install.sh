#!/bin/bash
# Builds Ghostwriter.app and installs it to /Applications, like any other Mac app.
# Re-run this after every code change to update the installed copy.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/make_app.sh

TARGET="/Applications/Ghostwriter.app"
if [ -d "$TARGET" ]; then
  echo "Replacing existing $TARGET…"
  rm -rf "$TARGET"
fi
cp -R dist/Ghostwriter.app "$TARGET"

echo "Installed: $TARGET"
echo "NOTE: ad-hoc signature — each install resets Accessibility permission;"
echo "re-grant it in System Settings > Privacy & Security > Accessibility."
open "$TARGET"
