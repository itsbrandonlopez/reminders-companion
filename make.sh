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
	<string>0.1</string>
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

# Ad-hoc: there is no signing identity on this machine. Note that ad-hoc signatures are
# identified by cdhash, so every rebuild reads as a new app to TCC and re-prompts for
# Reminders access. See spike/FINDINGS.md.
codesign --force --sign - --identifier com.brandonlopez.RemindersCompanion "$APP"

echo "built: $(pwd)/$APP"
