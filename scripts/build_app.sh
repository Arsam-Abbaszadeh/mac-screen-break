#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE_NAME="MacScreenBreak"
APP_BUNDLE_NAME="Screen Break"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INSTALL_DIR="/Applications/$APP_BUNDLE_NAME.app"
ICON_SOURCE="$ROOT_DIR/app image.jpeg"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_NAME="AppIcon.icns"

mkdir -p "$DIST_DIR"
swift build -c release --product "$EXECUTABLE_NAME" --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  for size in 16 32 64 128 256 512; do
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -s format png -z "$retina_size" "$retina_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_NAME"
  rm -rf "$ICONSET_DIR"
fi

codesign --force --deep --sign - "$APP_DIR"

rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

open "$INSTALL_DIR"
printf 'Built app: %s\n' "$APP_DIR"
printf 'Installed app: %s\n' "$INSTALL_DIR"
