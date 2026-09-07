#!/usr/bin/env bash
#
# Builds from source and installs to /Applications.
#
# This is the primary distribution path, not a fallback. An app built on the
# machine it runs on is never downloaded, so it never carries
# com.apple.quarantine and Gatekeeper never blocks it — no System Settings
# detour, and nobody has to disable a security protection to run code that
# reads their keystrokes.
#
# Requires the Command Line Tools (`xcode-select --install`). Xcode is not
# needed: the .app bundle is assembled by Scripts/make-app.sh rather than by
# Xcode's build system.
#
#   ./Scripts/install.sh
#   INSTALL_DIR=~/Applications ./Scripts/install.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-LaTeX Squiggly}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
TARGET="$INSTALL_DIR/$APP_NAME.app"

# The app was called LaTeX-Squiggly until the rename. Left in place, the old
# bundle keeps running from the menu bar and shows up a second time in System
# Settings, which looks exactly like the new one failing to install.
LEGACY_TARGET="$INSTALL_DIR/LaTeX-Squiggly.app"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "The Command Line Tools are not installed. Run:"
    echo "    xcode-select --install"
    exit 1
fi

# Use the stable signing identity when it exists, so macOS keeps the
# Accessibility grant across upgrades instead of asking again every time.
IDENTITY_NAME="${SIGN_IDENTITY_NAME:-LaTeX-Squiggly Dev}"
if security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1; then
    export SIGN_IDENTITY="$IDENTITY_NAME"
else
    # Falling back to ad-hoc silently is how you end up re-granting
    # Accessibility on every single build and blaming the app.
    echo
    echo "  No signing identity named \"$IDENTITY_NAME\" was found."
    echo "  Falling back to ad-hoc signing, which means macOS will forget the"
    echo "  Accessibility and Input Monitoring grants every time you rebuild."
    echo
    echo "  Fix it before granting permissions, not after:"
    echo "      Scripts/setup-signing.sh && Scripts/install.sh"
    echo
fi

Scripts/make-app.sh

# Copying over a running app leaves the old executable live in memory, still
# holding its status item and its event tap. Quitting first is the difference
# between an upgrade and two copies fighting over your keystrokes.
for RUNNING in "$TARGET" "$LEGACY_TARGET"; do
    if pgrep -f "$RUNNING/Contents/MacOS/" >/dev/null 2>&1; then
        echo "Quitting the running copy at $RUNNING"
        pkill -f "$RUNNING/Contents/MacOS/" || true
        sleep 1
    fi
done

for OLD in "$TARGET" "$LEGACY_TARGET"; do
    if [ -e "$OLD" ]; then
        echo "Removing $OLD"
        rm -rf "$OLD"
    fi
done

mkdir -p "$INSTALL_DIR"
cp -R "build/$APP_NAME.app" "$TARGET"

echo
echo "Installed $TARGET"
xattr -lr "$TARGET" | grep -q quarantine \
    && echo "WARNING: the installed app is quarantined; it was not built locally." \
    || echo "Not quarantined — it will open normally."
