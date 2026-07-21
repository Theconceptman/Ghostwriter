#!/bin/bash
# Runs the test suite with Command Line Tools only (no Xcode).
# CLT ships Testing.framework but SwiftPM does not add its search path — we do.
set -euo pipefail
cd "$(dirname "$0")/.."
FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
# -disable-cross-import-overlays: CLT ships _Testing_Foundation.framework without
# its Swift module, so the implicit Foundation+Testing overlay import fails.
exec swift test \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$@"
