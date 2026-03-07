#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "ERROR: TEAM_ID is required (Apple Developer Team ID)."
  exit 1
fi

if [[ -z "${SIGNING_CERTIFICATE:-}" ]]; then
  SIGNING_CERTIFICATE="Developer ID Application"
fi

SCHEME="${SCHEME:-GoveeMacController}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/release/$SCHEME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/release/export}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS_PATH:-$ROOT_DIR/release/ExportOptions.plist}"
APP_ZIP_PATH="${APP_ZIP_PATH:-$ROOT_DIR/release/$SCHEME.zip}"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$APP_ZIP_PATH"
mkdir -p "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>${SIGNING_CERTIFICATE}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

echo "==> Archiving $SCHEME"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_CERTIFICATE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

echo "==> Exporting signed app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

APP_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: Export failed; no .app found in $EXPORT_PATH"
  exit 1
fi

echo "==> Creating zip for notarization"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ZIP_PATH"

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "==> Submitting for notarization (keychain profile)"
  xcrun notarytool submit "$APP_ZIP_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  echo "==> Submitting for notarization (Apple ID + app password)"
  xcrun notarytool submit "$APP_ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
else
  echo "WARNING: Notarization credentials not provided. Skipping notarization and stapling."
  echo "Set NOTARY_KEYCHAIN_PROFILE, or APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID."
  echo "Signed app exported at: $APP_PATH"
  exit 0
fi

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

echo "==> Verifying signed + notarized app"
spctl -a -t exec -vv "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Done"
echo "App: $APP_PATH"
echo "Zip: $APP_ZIP_PATH"
