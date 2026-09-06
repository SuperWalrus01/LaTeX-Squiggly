#!/usr/bin/env bash
#
# Assembles a .app bundle from SwiftPM output and signs it.
#
# Deliberately does not use Xcode's build system: testers should be able to
# build from source with only the Command Line Tools installed, rather than a
# ~15 GB Xcode download. That constraint is why the bundle is assembled by hand
# here instead of being produced by an .xcodeproj.
#
#   Scripts/make-app.sh                          ad-hoc signed, into build/
#   SIGN_IDENTITY="LaTeX Unicode Dev" Scripts/make-app.sh
#   TARBALL=1 Scripts/make-app.sh                also produce a .tar.gz
#
# On the tarball: it is a convenience, NOT a Gatekeeper workaround. Tested on
# macOS 15.6 — a quarantined archive containing a .app propagates quarantine to
# the bundle's contents even through command-line `tar -xzf`. (Plain files do
# not get this; app bundles specifically do.) A downloaded build therefore still
# costs the tester a trip through System Settings -> Privacy & Security.
#
# Building from source is the only free path that is genuinely clean, because a
# locally built app is never downloaded and so never quarantined. See
# Scripts/install.sh.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-LaTeXUnicode}"
EXECUTABLE="${EXECUTABLE:-latex-unicode}"
BUNDLE_ID="${BUNDLE_ID:-com.example.latexunicode}"
VERSION="${VERSION:-0.1.0}"
MIN_MACOS="${MIN_MACOS:-13.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" means ad-hoc
OUT="${OUT:-build}"

APP="$OUT/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "Building $EXECUTABLE (release)"
swift build -c release --product "$EXECUTABLE"
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH/$EXECUTABLE" "$CONTENTS/MacOS/$APP_NAME"

# LSUIElement is what makes this a menu bar app with no Dock icon.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundleVersion</key>              <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>       <string>$MIN_MACOS</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Signing must come last: it hashes the bundle contents, so any later edit
# invalidates the signature.
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Signing ad-hoc (permissions will reset on every rebuild)"
    echo "  Run Scripts/setup-signing.sh and set SIGN_IDENTITY to avoid that."
else
    echo "Signing as: $SIGN_IDENTITY"
fi
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "Built $APP"

if [ "${TARBALL:-0}" != "0" ]; then
    ARCHIVE="$OUT/$APP_NAME-$VERSION-macos.tar.gz"
    rm -f "$ARCHIVE"
    tar -czf "$ARCHIVE" -C "$OUT" "$APP_NAME.app"
    echo "Built $ARCHIVE"
fi
