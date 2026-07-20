#!/bin/bash
# Runs the test suite with Command Line Tools only (no Xcode).
# CLT ships Testing.framework but SwiftPM does not add its search path — we do.
set -euo pipefail
cd "$(dirname "$0")/.."
FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$@"
