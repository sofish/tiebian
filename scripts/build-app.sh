#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
cd "$ROOT"

swift build -c "$CONFIG" --product EdgePeek
swift build -c "$CONFIG" --product edgepeek-mcp
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/dist/贴边.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/EdgePeek" "$APP/Contents/MacOS/EdgePeek"
cp "$BIN_DIR/edgepeek-mcp" "$APP/Contents/MacOS/edgepeek-mcp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$ROOT/Resources/KingHwaOldSong.ttf" "$APP/Contents/Resources/KingHwaOldSong.ttf"
cp "$ROOT/Resources/KingHwaOldSong-LICENSE.txt" "$APP/Contents/Resources/KingHwaOldSong-LICENSE.txt"
printf 'APPL????' > "$APP/Contents/PkgInfo"

xattr -cr "$APP"
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/edgepeek-mcp" >/dev/null 2>&1
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "Built $APP"
