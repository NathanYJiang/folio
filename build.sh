#!/usr/bin/env bash
# Build Folio.app. Usage: ./build.sh [install | defaults [ext ...]]
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [ "${1:-}" = "defaults" ]; then
  shift
  swift scripts/set-defaults.swift "/Applications/Folio.app" "$@"
  exit
fi

APP_NAME="Folio"
BUILD="build"
APP="$BUILD/$APP_NAME.app"

[ -d node_modules ] || npm install

mkdir -p "$BUILD/web"
npx esbuild src/web/main.js --bundle --minify --format=iife --target=safari16 --outfile="$BUILD/web/app.js" --log-level=warning
cp src/web/index.html src/web/styles.css "$BUILD/web/"
cp node_modules/katex/dist/katex.min.css "$BUILD/web/"
mkdir -p "$BUILD/web/fonts"
cp node_modules/katex/dist/fonts/*.woff2 "$BUILD/web/fonts/"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  src/mac/main.swift -o "$BUILD/$APP_NAME" -framework Cocoa -framework WebKit

if [ ! -f "$BUILD/AppIcon.icns" ] || [ scripts/make-icon.swift -nt "$BUILD/AppIcon.icns" ]; then
  swift scripts/make-icon.swift "$BUILD/icon_1024.png"
  ICONSET="$BUILD/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp src/mac/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/"
rsync -a --delete "$BUILD/web/" "$APP/Contents/Resources/web/"
codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
  mkdir -p "/Applications/$APP_NAME.app"
  rsync -a --delete "$APP/" "/Applications/$APP_NAME.app/"
  "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "/Applications/$APP_NAME.app"
  echo "Installed /Applications/$APP_NAME.app"
fi
