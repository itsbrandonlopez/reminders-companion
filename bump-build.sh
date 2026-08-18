#!/bin/zsh
# Increments CURRENT_PROJECT_VERSION in project.yml and regenerates the Xcode project.
#
# App Store Connect rejects an upload whose build number isn't higher than the last one
# it received for the current marketing version, so this has to happen before every
# archive — not just when the marketing version (1.0, 1.1, ...) changes.
set -e
cd "$(dirname "$0")"

current=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | grep -oE '[0-9]+')
next=$((current + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml

echo "build number: $current -> $next"
xcodegen generate
