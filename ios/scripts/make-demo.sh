#!/bin/sh
# Records the demo video: the DemoVideo UI test types through the keyboard's
# features in a fresh simulator, and guide/make-demo.py adds the titles.
#
#   scripts/make-demo.sh
set -e
cd "$(dirname "$0")/.."
OUT=../build/demo
SIM="LS Demo"
rm -rf "$OUT" && mkdir -p "$OUT"

xcrun simctl delete "$SIM" 2>/dev/null || true
xcrun simctl create "$SIM" "iPhone 16e" >/dev/null
xcrun simctl boot "$SIM"
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4
xcodegen -q
xcodebuild build-for-testing -project LaTeXSquiggly.xcodeproj -scheme LaTeXSquiggly \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath ../build/ios-sim -quiet
xcrun simctl install "$SIM" ../build/ios-sim/Build/Products/Debug-iphonesimulator/LaTeXSquiggly.app

# The video's first frame is when the recorder says it started, which the
# scene times are measured from.
xcrun simctl io "$SIM" recordVideo --codec h264 --force "$OUT/raw.mp4" 2> "$OUT/recorder.log" &
RECORDER=$!
until grep -q "Recording started" "$OUT/recorder.log" 2>/dev/null; do sleep 0.1; done
date +%s.%N | cut -c1-14 > "$OUT/start.txt"
xcodebuild test-without-building -project LaTeXSquiggly.xcodeproj -scheme LaTeXSquiggly \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath ../build/ios-sim \
  -only-testing:LookTests/DemoVideo 2>&1 | grep -E "^SCENE " > "$OUT/scenes.txt" || true
kill -INT $RECORDER
wait $RECORDER 2>/dev/null || true
xcrun simctl delete "$SIM"
python3 guide/make-demo.py "$OUT" guide/LaTeX-Squiggly-iPhone-Demo.mp4
