#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/ClipNest.app"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/module-cache"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

if [[ -d "$COMPATIBLE_SDK" ]]; then
  SDK_PATH="$COMPATIBLE_SDK"
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE_DIR"

xcrun swiftc \
  -O \
  -parse-as-library \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macos13.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$PROJECT_DIR/ClipNest.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Carbon \
  -o "$APP_DIR/Contents/MacOS/ClipNest"

install -m 644 "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "com.clipnest.native"' \
  "$APP_DIR"

echo "Built $APP_DIR"
