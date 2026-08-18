#!/bin/zsh
# Builds the Phase 0 probe as a real .app bundle.
# TCC will not prompt for a bare command-line tool — it needs a bundled, signed
# app to attribute the Reminders permission request to.
set -e
cd "$(dirname "$0")"
APP="Probe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -parse-as-library -o "$APP/Contents/MacOS/probe" Probe.swift -framework EventKit
codesign --force --sign - --identifier com.brandonlopez.RemindersCompanion.Probe "$APP"
echo "built: $(pwd)/$APP"
