#!/bin/bash
# Builds Ghostwriter.app from the SwiftPM binary (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=dist/Ghostwriter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ghostwriter "$APP/Contents/MacOS/Ghostwriter"

if [ ! -f Resources/AppIcon.icns ]; then
  ./Scripts/gen_icon.sh
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Ghostwriter</string>
    <key>CFBundleIdentifier</key><string>com.antoine.ghostwriter</string>
    <key>CFBundleName</key><string>Ghostwriter</string>
    <key>CFBundleDisplayName</key><string>Ghostwriter</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Ghostwriter listens while you hold the dictation key. Audio never leaves this Mac.</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Antoine Tramble</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${GHOSTWRITER_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-F]\{40\}\) .*/\1/p' \
    | head -1)
fi

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed with a stable Keychain identity so macOS permissions survive rebuilds."
else
  codesign --force --deep --sign - "$APP"
  echo "WARNING: No Keychain code-signing identity was found."
  echo "This ad-hoc signature will reset Accessibility permission after rebuilds."
fi

echo "Built: $APP"
