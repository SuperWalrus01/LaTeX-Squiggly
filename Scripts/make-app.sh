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
#   SIGN_IDENTITY="LaTeX-Squiggly Dev" Scripts/make-app.sh   (the identity name
#                                                            keeps its hyphen)
#   DMG=1 Scripts/make-app.sh                    also produce a .dmg
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

# The display name has a space; anything that becomes a file name off the
# machine (the tarball) uses the hyphenated slug instead.
APP_NAME="${APP_NAME:-LaTeX Squiggly}"
APP_SLUG="${APP_SLUG:-${APP_NAME// /-}}"
EXECUTABLE="${EXECUTABLE:-LaTeXSquigglyApp}"
BUNDLE_ID="${BUNDLE_ID:-com.keenanjusak.latex-squiggly}"
# Read from the VERSION file, never defaulted to a literal here: this line
# used to say 0.1.0, so a release built without setting the variable was
# stamped with the previous version and nothing caught it.
VERSION="${VERSION:-$(cat VERSION)}"
MIN_MACOS="${MIN_MACOS:-13.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" means ad-hoc
OUT="${OUT:-build}"

APP="$OUT/$APP_NAME.app"
CONTENTS="$APP/Contents"

python3 Tools/check_version.py

echo "Building $EXECUTABLE $VERSION (release)"
swift build -c release --product "$EXECUTABLE"
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH/$EXECUTABLE" "$CONTENTS/MacOS/$APP_NAME"

# The icon is generated ahead of time and committed, so building the app needs
# neither the artwork nor iconutil. Scripts/make-icons.sh rebuilds it from
# Assets/ after the artwork changes.
ICON_NAME="AppIcon"
if [ -f "Assets/$ICON_NAME.icns" ]; then
    cp "Assets/$ICON_NAME.icns" "$CONTENTS/Resources/$ICON_NAME.icns"
else
    echo "warning: Assets/$ICON_NAME.icns is missing; run Scripts/make-icons.sh"
    ICON_NAME=""
fi

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
    <key>CFBundleIconFile</key>             <string>$ICON_NAME</string>
    <key>CFBundleIconName</key>             <string>$ICON_NAME</string>
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
    ARCHIVE="$OUT/$APP_SLUG-$VERSION-macos.tar.gz"
    rm -f "$ARCHIVE"
    tar -czf "$ARCHIVE" -C "$OUT" "$APP_NAME.app"
    echo "Built $ARCHIVE"
fi

# A disk image is what a Mac user expects a Mac app to arrive in, and the
# Applications symlink turns "where do I put this" into a drag. It buys no
# Gatekeeper relief whatsoever — see the quarantine table in the README, where
# a downloaded .dmg fares exactly as badly as a downloaded .tar.gz. This is
# about the twenty seconds after the download, not about the warning.
if [ "${DMG:-0}" != "0" ]; then
    IMAGE="$OUT/$APP_SLUG-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT

    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"

    rm -f "$IMAGE"
    # UDZO is compressed and read-only, which is what a released image should
    # be: nobody should be able to edit the copy they were sent.
    hdiutil create -quiet \
        -volname "$APP_NAME" \
        -srcfolder "$STAGE" \
        -format UDZO \
        -ov "$IMAGE"

    # The image is signed too. Without this the very first thing macOS says
    # about the download is that it is damaged, rather than that it is unsigned.
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$IMAGE"
    echo "Built $IMAGE"
fi
