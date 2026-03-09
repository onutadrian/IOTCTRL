#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PRODUCT_NAME="${PRODUCT_NAME:-GoveeMacController}"
BUNDLE_ID="${BUNDLE_ID:-com.local.$PRODUCT_NAME}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"
RELEASE_DIR="$ROOT_DIR/release"
APP_PATH="$RELEASE_DIR/$PRODUCT_NAME.app"
DMG_PATH="$RELEASE_DIR/$PRODUCT_NAME.dmg"
STAGING_DIR="$RELEASE_DIR/dmg-staging"
ICONSET_DIR="$RELEASE_DIR/AppIcon.iconset"
ICON_ICNS_PATH="$RELEASE_DIR/AppIcon.icns"

# Optional icon inputs
APP_ICON_ICNS="${APP_ICON_ICNS:-}"
APP_ICON_PNG="${APP_ICON_PNG:-$ROOT_DIR/Sources/GoveeMacController/Assets/appIcon.png}"

mkdir -p "$RELEASE_DIR"
rm -rf "$APP_PATH" "$DMG_PATH" "$STAGING_DIR" "$ICONSET_DIR" "$ICON_ICNS_PATH"

echo "==> Building release binary"
swift build -c release --product "$PRODUCT_NAME"

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$PRODUCT_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "ERROR: missing executable at $BIN_PATH"
  exit 1
fi

RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -name "${PRODUCT_NAME}_*.bundle" | head -n 1 || true)"

echo "==> Creating app bundle"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/$PRODUCT_NAME"

if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/"
fi

ICON_PLIST_KEYS=""

if [[ -n "$APP_ICON_ICNS" && -f "$APP_ICON_ICNS" ]]; then
  cp "$APP_ICON_ICNS" "$ICON_ICNS_PATH"
fi

if [[ ! -f "$ICON_ICNS_PATH" && -n "$APP_ICON_PNG" && -f "$APP_ICON_PNG" ]]; then
  echo "==> Generating AppIcon.icns from PNG"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS_PATH"
fi

if [[ -f "$ICON_ICNS_PATH" ]]; then
  cp "$ICON_ICNS_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"
  ICON_PLIST_KEYS=$(cat <<PLIST
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
PLIST
)
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
$ICON_PLIST_KEYS
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing app"
codesign --force --deep --sign - "$APP_PATH"

echo "==> Creating DMG"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR" "$ICONSET_DIR"

echo "Done"
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
