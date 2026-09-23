#!/bin/bash
# Builds the zip the Chrome Web Store takes, after the checks that must pass
# before anything is uploaded.
#
# The zip is the chrome/ folder minus its tests, with manifest.json at the top
# level, which is where the store looks for it.
#
# Run:  Tools/package_chrome.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT="$ROOT/build/LaTeX-Squiggly-$VERSION-chrome.zip"

python3 "$ROOT/Tools/check_version.py"
node "$ROOT/chrome/test/conformance.mjs"

mkdir -p "$ROOT/build"
rm -f "$OUT"
cd "$ROOT/chrome"
zip -qr -X "$OUT" . -x 'test/*' -x 'store/*' -x '*.md' -x '.DS_Store' -x '*/.DS_Store'

echo "packaged $(unzip -Z1 "$OUT" | wc -l | tr -d ' ') files into ${OUT#$ROOT/}"
