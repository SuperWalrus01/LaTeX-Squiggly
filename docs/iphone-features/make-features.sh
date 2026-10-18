#!/bin/sh
# Prints features.html, every feature of the iPhone app, to
# LaTeX-Squiggly-iPhone-Features.pdf with Chrome, as the user guide is made.
#
#   docs/iphone-features/make-features.sh
#
# Update features.html whenever a feature is added or changed, run this, and
# commit both files.
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$PWD/LaTeX-Squiggly-iPhone-Features.pdf" "file://$PWD/features.html" 2>/dev/null
echo "Wrote docs/iphone-features/LaTeX-Squiggly-iPhone-Features.pdf"
