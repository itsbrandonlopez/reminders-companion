#!/bin/zsh
# Builds RemindersCompanion.app.
#
# SwiftPM produces a bare executable, but TCC will not grant Reminders access to one —
# it needs a bundled, signed app to attribute the permission to. So the binary gets
# wrapped in a minimal bundle carrying NSRemindersFullAccessUsageDescription.
set -e
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="build/RemindersCompanion.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/RemindersCompanion"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RemindersCompanion"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Reminders Companion</string>
	<key>CFBundleDisplayName</key>
	<string>Reminders Companion</string>
	<key>CFBundleExecutable</key>
	<string>RemindersCompanion</string>
	<key>CFBundleIdentifier</key>
	<string>com.brandonlopez.RemindersCompanion</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.4.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Reminders Companion overlays your calendar events on its weekly board so you can see which days are already booked. Events are only ever read, never changed.</string>
	<key>NSRemindersFullAccessUsageDescription</key>
	<string>Reminders Companion shows the reminders you already have in a weekly planning board. Your tasks stay in Reminders and your existing notifications are never changed.</string>
</dict>
PLIST
echo "</plist>" >> "$APP/Contents/Info.plist"

# Signing decides whether the sidecar syncs.
#
# iCloud entitlements are only honoured under a real identity backed by a provisioning
# profile from an enrolled Apple Developer account. Embedding them in an ad-hoc signature
# does nothing — the system ignores them — so they are only passed when there is an
# identity to authorise them, and `MetaStore` falls back to a local store when they are
# absent. Nothing breaks without them; the sidecar simply stays on this Mac.
#
#   security find-identity -v -p codesigning     # to see what you have
#   export CODESIGN_IDENTITY="Apple Development: you@example.com (ABCDE12345)"
#
# Note that ad-hoc signatures are identified by cdhash, so every rebuild reads as a new
# app to TCC and re-prompts for Reminders access. See spike/FINDINGS.md.
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
	codesign --force --sign "$CODESIGN_IDENTITY" \
		--entitlements signing/RemindersCompanion.entitlements \
		--options runtime \
		--identifier com.brandonlopez.RemindersCompanion "$APP"
	echo "signed as: $CODESIGN_IDENTITY  (iCloud sync enabled)"
else
	codesign --force --sign - --identifier com.brandonlopez.RemindersCompanion "$APP"
	echo "ad-hoc signed — the sidecar stays on this Mac. Set CODESIGN_IDENTITY to sync."
fi

echo "built: $(pwd)/$APP"
