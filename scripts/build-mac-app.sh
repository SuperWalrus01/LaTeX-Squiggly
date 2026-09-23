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
# The mounted volume's name, which is the window title and the label under the
# disk on the desktop. Deliberately not the app's name: while it was, opening
# the image left you with two things on screen both called "LaTeX Squiggly",
# one of which you keep and one of which you eject.
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME Installer}"
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
    WRITABLE="$(mktemp -u)-rw.dmg"
    trap 'rm -rf "$STAGE" "$WRITABLE"' EXIT

    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"

    # The window dressing, both committed so this script needs no artwork.
    # Missing either one is not fatal: an unstyled image still installs.
    STYLED=1
    if [ -f "Assets/dmg-background.tiff" ]; then
        mkdir -p "$STAGE/.background"
        cp "Assets/dmg-background.tiff" "$STAGE/.background/background.tiff"
    else
        echo "warning: Assets/dmg-background.tiff is missing; run Scripts/make-icons.sh"
        STYLED=0
    fi
    # The volume icon is deliberately NOT staged here. Finder deletes a
    # .VolumeIcon.icns it finds on a volume it is opening, so anything put in
    # the staging folder is gone by the time the window has been arranged.
    # It goes on after Finder has finished, below.
    if [ ! -f "Assets/VolumeIcon.icns" ]; then
        echo "warning: Assets/VolumeIcon.icns is missing; run Scripts/make-icons.sh"
    fi

    rm -f "$IMAGE"

    if [ "$STYLED" = "0" ]; then
        # UDZO is compressed and read-only, which is what a released image
        # should be: nobody should be able to edit the copy they were sent.
        hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
            -format UDZO -ov "$IMAGE"
    else
        # Window layout lives in the volume's .DS_Store, which only Finder
        # writes and only on a volume it can write to. So: build a read-write
        # image, mount it, let Finder arrange it, then flatten the result to
        # the compressed read-only image that actually ships.
        hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
            -format UDRW -ov "$WRITABLE"

        MOUNT="$(hdiutil attach "$WRITABLE" -readwrite -noverify \
                 | grep -o '/Volumes/.*' | head -1)"
        [ -n "$MOUNT" ] || { echo "could not mount the staging image"; exit 1; }

        # Positions and window size come from Tools/make_dmg_images.swift,
        # which drew the background to match them. Change them there.
        osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 860, 560}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {178, 196}
        set position of item "Applications" of container window to {482, 196}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

        # Only now, with Finder done: it removes a .VolumeIcon.icns from a
        # volume it opens, so staging one before this point loses it. The flag
        # matters as much as the file, since .VolumeIcon.icns on its own does
        # nothing until the volume is marked as having a custom icon.
        if [ -f "Assets/VolumeIcon.icns" ]; then
            cp "Assets/VolumeIcon.icns" "$MOUNT/.VolumeIcon.icns"
            SetFile -a C "$MOUNT" 2>/dev/null || \
                echo "warning: could not set the custom-icon flag on the volume"
        fi

        sync
        hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
        hdiutil convert "$WRITABLE" -quiet -format UDZO -imagekey zlib-level=9 \
            -o "$IMAGE"
    fi

    # The image is signed too. Without this the very first thing macOS says
    # about the download is that it is damaged, rather than that it is unsigned.
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$IMAGE"
    echo "Built $IMAGE"
fi
