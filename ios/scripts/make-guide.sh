#!/bin/sh
# Screenshots every screen the user guide shows, then builds the guide PDF.
#
#   scripts/make-guide.sh
#
# Uses a fresh simulator, "LS Guide", made and deleted here. Screens that need
# taps or held keys come from the GuideShots UI test; the rest are opened
# directly with the app's debug screens (see App/DebugScreens.swift).
set -e
cd "$(dirname "$0")/.."
SHOTS=../build/guide/shots
FRAMES=../build/guide/frames
SIM="LS Guide"
APP=com.keenanjusak.latex-squiggly.ios
rm -rf ../build/guide && mkdir -p "$SHOTS" "$FRAMES"

xcrun simctl delete "$SIM" 2>/dev/null || true
xcrun simctl create "$SIM" "iPhone 16e" >/dev/null
xcrun simctl boot "$SIM"
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4
xcodegen -q
xcodebuild build-for-testing -project LaTeXSquiggly.xcodeproj -scheme LaTeXSquiggly \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath ../build/ios-sim -quiet
xcrun simctl install "$SIM" ../build/ios-sim/Build/Products/Debug-iphonesimulator/LaTeXSquiggly.app

# One screen opened directly: name, then launch arguments; PREVIEW_* settings
# come from the environment.
screen() {
  name=$1; shift
  xcrun simctl launch --terminate-running-process "$SIM" $APP "$@" >/dev/null
  sleep 5
  xcrun simctl io "$SIM" screenshot "$SHOTS/$name.png" >/dev/null 2>&1
  # Settings given before a shell function outlive it, so clear them.
  unset SIMCTL_CHILD_PREVIEW_TEXT SIMCTL_CHILD_PREVIEW_PANEL SIMCTL_CHILD_PREVIEW_PAGE SIMCTL_CHILD_PREVIEW_SELECT
}
ROOTS='The roots are $x = \frac{-b \pm \sqrt{\Delta}}{2a}$ when $a \neq 0$.'
FORMULA='The answer is $x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$'

screen app-setup
screen app-render -renderTab
SIMCTL_CHILD_PREVIEW_TEXT='' screen kb-quick -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT='The angle \al' screen kb-suggest -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT='The angle \alpha' screen kb-before -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT='The angle α ' screen kb-after -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$FORMULA" screen kb-dollar -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$FORMULA" SIMCTL_CHILD_PREVIEW_PANEL=1 screen kb-preview -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT='' screen kb-latex-mode -keyboardPreview -output latex
SIMCTL_CHILD_PREVIEW_TEXT='\int_0^1 x^2 \, dx = \frac{1}{3}' screen kb-latex-long -keyboardPreview -output latex
SIMCTL_CHILD_PREVIEW_TEXT='' SIMCTL_CHILD_PREVIEW_PAGE=math screen kb-math-page -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT='I like teh' screen kb-words -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$ROOTS" SIMCTL_CHILD_PREVIEW_SELECT=1 screen kb-selection -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT='$\foo + x$' screen kb-error -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$ROOTS" screen share -shareSheet
screen messages-drawer -messagesDrawer -recent '("x^2 + y^2 = z^2", "e^{i\\pi} + 1 = 0", "\\frac{a}{b}")'
SIMCTL_CHILD_PREVIEW_TEXT='\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}' screen messages-editor -messagesEditor
xcrun simctl terminate "$SIM" $APP 2>/dev/null || true

# The UI test, with a screenshot every few tenths of a second throughout.
( while :; do xcrun simctl io "$SIM" screenshot "$FRAMES/$(date +%s.%N | cut -c1-14).png" >/dev/null 2>&1; done ) &
SHOOTER=$!
trap 'kill $SHOOTER 2>/dev/null' EXIT
xcodebuild test-without-building -project LaTeXSquiggly.xcodeproj -scheme LaTeXSquiggly \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath ../build/ios-sim \
  -only-testing:LookTests/GuideShots 2>&1 | grep -E "^(SHOT|HOLD) " > ../build/guide/marks.txt || true
kill $SHOOTER 2>/dev/null || true

python3 guide/pick-frames.py ../build/guide
xcrun simctl delete "$SIM"
python3 guide/make-guide.py ../build/guide/shots guide/LaTeX-Squiggly-iPhone-Guide.pdf
