#!/usr/bin/env bash
# Скачивает готовый TDLib для iOS и оставляет в xcframework только iOS-срезы.
# Запускать на macOS (нужен xcodebuild).
set -euo pipefail
VERSION="${TDLIB_VERSION:-1.8.68-4a85043f}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/ios/TDLib"
TMP="$(mktemp -d)"

curl -fL "https://github.com/Swiftgram/TDLibFramework/releases/download/${VERSION}/TDLibFramework.zip" -o "$TMP/td.zip"
unzip -q "$TMP/td.zip" 'TDLibFramework.xcframework/ios-*' 'TDLibFramework.xcframework/Info.plist' -d "$TMP"

args=()
for fw in "$TMP"/TDLibFramework.xcframework/ios-*/TDLibFramework.framework; do
  args+=(-framework "$fw")
done
rm -rf "$DEST/TDLibFramework.xcframework"
xcodebuild -create-xcframework "${args[@]}" -output "$DEST/TDLibFramework.xcframework"
rm -rf "$TMP"
echo "TDLib ${VERSION} -> $DEST/TDLibFramework.xcframework"
