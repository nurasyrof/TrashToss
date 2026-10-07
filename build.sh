#!/bin/bash
# Builds TrashToss.app into ./build.
# Usage: ./build.sh [--run] [--universal]
#   --run        relaunch the app after building
#   --universal  build for Apple Silicon and Intel (used by release.sh)
set -euo pipefail
cd "$(dirname "$0")"

RUN=0
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --run) RUN=1 ;;
        --universal) UNIVERSAL=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

APP=build/TrashToss.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ $UNIVERSAL == 1 ]]; then
    for arch in arm64 x86_64; do
        swift build -c release --arch "$arch"
    done
    lipo -create -output "$APP/Contents/MacOS/TrashToss" \
        "$(swift build -c release --arch arm64 --show-bin-path)/TrashToss" \
        "$(swift build -c release --arch x86_64 --show-bin-path)/TrashToss"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/TrashToss" "$APP/Contents/MacOS/TrashToss"
fi

cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
if [[ $RUN == 1 ]]; then
    pkill -x TrashToss 2>/dev/null || true
    open "$APP"
fi
