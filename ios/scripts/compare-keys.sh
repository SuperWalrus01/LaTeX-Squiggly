#!/bin/sh
# Screenshots Apple's keyboard and ours with keys held down, to compare the
# pop-ups. Needs a simulator named "LS Compare"; the frames land in $1.
#
#   xcrun simctl create "LS Compare" "iPhone 16e"
#   scripts/compare-keys.sh /tmp/keys
set -e
OUT="${1:?usage: compare-keys.sh <output folder>}"
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
xcrun simctl boot "LS Compare" 2>/dev/null || true

# Screenshots every few tenths of a second while the test holds keys.
( while :; do xcrun simctl io "LS Compare" screenshot "$OUT/$(date +%s.%N | cut -c1-14).png" >/dev/null 2>&1; done ) &
SHOOTER=$!
trap 'kill $SHOOTER 2>/dev/null' EXIT

xcodebuild test -project LaTeXSquiggly.xcodeproj -scheme LaTeXSquiggly \
  -destination 'platform=iOS Simulator,name=LS Compare' -derivedDataPath ../build/ios-sim \
  -only-testing:LookTests 2>&1 | grep "LOOK " | tee "$OUT/holds.txt"
