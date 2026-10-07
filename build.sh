#!/bin/bash
# Builds TrashToss.app into ./build. Usage: ./build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TrashToss"

APP=build/TrashToss.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrashToss"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
    pkill -x TrashToss 2>/dev/null || true
    open "$APP"
fi
