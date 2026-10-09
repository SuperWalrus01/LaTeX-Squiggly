#!/bin/sh
# Makes the App Store screenshots: screens from the app's debug screens on a
# 6.9-inch iPhone, then store/make-store.py puts each in an iPhone under an
# orange banner with its headline.
#
#   scripts/make-store-shots.sh
#
# Uses a fresh simulator, "LS Store", made and deleted here. The iPhone 17
# Pro Max screen is 1320 by 2868 pixels, the size App Store Connect asks for.
set -e
cd "$(dirname "$0")/.."
RAW=../build/store/raw
SIM="LS Store"
APP=com.keenanjusak.latex-squiggly.ios
rm -rf ../build/store && mkdir -p "$RAW"

xcrun simctl delete "$SIM" 2>/dev/null || true
xcrun simctl create "$SIM" "iPhone 17 Pro Max" >/dev/null
xcrun simctl bootstatus "$SIM" -b >/dev/null
# A 12-hour clock, so the status bar says 9:41 as Apple's own images do,
# not 09:41. It takes a restart to show.
xcrun simctl spawn "$SIM" defaults write -g AppleLocale -string en_US
xcrun simctl shutdown "$SIM"
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl ui "$SIM" appearance light
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState discharging --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4
xcodegen -q
xcodebuild build -project LaTeXSquiggly.xcodeproj -scheme LaTeXSquiggly \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath ../build/ios-sim -quiet
xcrun simctl install "$SIM" ../build/ios-sim/Build/Products/Debug-iphonesimulator/LaTeXSquiggly.app

# One screen: name, then launch arguments; PREVIEW_* settings come from the
# environment, as in make-guide.sh.
screen() {
  name=$1; shift
  xcrun simctl launch --terminate-running-process "$SIM" $APP "$@" >/dev/null
  sleep 5
  xcrun simctl io "$SIM" screenshot "$RAW/$name.png" >/dev/null 2>&1
  unset SIMCTL_CHILD_PREVIEW_TEXT SIMCTL_CHILD_PREVIEW_PANEL SIMCTL_CHILD_PREVIEW_PAGE SIMCTL_CHILD_PREVIEW_SELECT
}
# Notes, so the keyboard shots look like real use rather than an empty page.
NOTES=$(printf '%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s' \
  'Analysis, week 3' \
  'Sequences: aₙ → L if for every ε > 0 there is an N ∈ ℕ with |aₙ − L| < ε for all n ≥ N.' \
  'Every convergent sequence is bounded, and the limit is unique.' \
  'f is continuous at a if for every ε > 0 there is a δ > 0 with |f(x) − f(a)| < ε whenever |x − a| < δ.' \
  'Example: f(x) = x² is continuous on ℝ. Take δ = min(1, ε/(2|a| + 1)).' \
  'A limit: for every ε > 0 there is a δ > 0 such that |f(x) − L| < ε whenever 0 < |x − a| < ')
QUADRATIC=$(printf '%s\n\n%s\n\n%s\n\n%s\n\n%s' \
  'Quadratics' \
  'Any ax² + bx + c = 0 with a ≠ 0 can be solved by completing the square.' \
  'Divide by a, then add (b/2a)² to both sides: (x + b/2a)² = (b² − 4ac)/4a².' \
  'The discriminant Δ = b² − 4ac decides it: two real roots if Δ > 0, one if Δ = 0, none if Δ < 0.' \
  'The roots are $x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$')
SYMBOLS=$(printf '%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s\n\n%s' \
  'Symbols' \
  'Sets: ℕ ⊂ ℤ ⊂ ℚ ⊂ ℝ ⊂ ℂ, A ∩ B, A ∪ B, x ∉ ∅' \
  'Logic: ∀x ∃y (x < y), p ⇒ q, ¬p ∨ q' \
  'Calculus: ∫ f dx, ∑ aₙ, ∂f/∂x, ∇ · F' \
  'Relations: ≤ ≥ ≠ ≈ ≡ ∝' \
  'Arrows: → ← ↔ ⇒ ⇔ ↦' \
  'Greek: α β γ δ θ λ π ')
ROOTS='The roots are $x = \frac{-b \pm \sqrt{\Delta}}{2a}$ when $a \neq 0$.'

SIMCTL_CHILD_PREVIEW_TEXT="$NOTES\del" screen convert -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$QUADRATIC" screen dollar -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$QUADRATIC" SIMCTL_CHILD_PREVIEW_PANEL=1 screen copy -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$SYMBOLS" SIMCTL_CHILD_PREVIEW_PAGE=math screen symbols -keyboardPreview -output unicode
SIMCTL_CHILD_PREVIEW_TEXT="$ROOTS" screen share -shareSheet
SIMCTL_CHILD_PREVIEW_TEXT='\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}' screen messages-editor -messagesEditor
screen setup
xcrun simctl terminate "$SIM" $APP 2>/dev/null || true
xcrun simctl delete "$SIM"

python3 store/make-store.py "$RAW" store
