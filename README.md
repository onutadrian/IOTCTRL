# GoveeMacController

Native SwiftUI macOS desktop app for Govee devices with LAN-first control and cloud fallback.

## Implemented MVP
- API key onboarding and secure storage in Keychain
- Hybrid device discovery (cloud list + LAN scan)
- Transport-aware command routing (`LAN` preferred, `Cloud` fallback)
- Controls: power and brightness
- Cloud command queue with coalescing for rapid slider updates and 429 retry handling
- Device list + detail controls + optimistic UI updates with rollback on failure

## Build and run
```bash
cd /Users/adrian/Documents/Codex/HomeIoT/GoveeMacController
swift build --target GoveeMacController
swift run GoveeMacController
```

## Test
```bash
cd /Users/adrian/Documents/Codex/HomeIoT/GoveeMacController
swift test
```

## Release (signed + notarized)
Script: `scripts/release-macos.sh`

1. Export required signing vars:
```bash
export TEAM_ID="YOUR_TEAM_ID"
export SIGNING_CERTIFICATE="Developer ID Application"
```

2. Choose one notarization auth mode:

Keychain profile (recommended):
```bash
xcrun notarytool store-credentials "govee-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
export NOTARY_KEYCHAIN_PROFILE="govee-notary"
```

Or direct environment variables:
```bash
export APPLE_ID="YOUR_APPLE_ID"
export APPLE_APP_PASSWORD="YOUR_APP_SPECIFIC_PASSWORD"
export APPLE_TEAM_ID="YOUR_TEAM_ID"
```

3. Run release pipeline:
```bash
cd /Users/adrian/Documents/Codex/HomeIoT/GoveeMacController
./scripts/release-macos.sh
```

The script will:
- Archive with `xcodebuild`
- Export a Developer ID-signed `.app`
- Zip, notarize, staple, and validate

## Notes
- Enable LAN control per device in the Govee Home app.
- Keep the Mac and devices on the same LAN for local control.
- This build intentionally limits controls to power and brightness only.
