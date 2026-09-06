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

APP_NAME="${APP_NAME:-LaTeXUnicode}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
TARGET="$INSTALL_DIR/$APP_NAME.app"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "The Command Line Tools are not installed. Run:"
    echo "    xcode-select --install"
    exit 1
fi

# Use the stable signing identity when it exists, so macOS keeps the
# Accessibility grant across upgrades instead of asking again every time.
IDENTITY_NAME="${SIGN_IDENTITY_NAME:-LaTeX Unicode Dev}"
if security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1; then
    export SIGN_IDENTITY="$IDENTITY_NAME"
fi

Scripts/make-app.sh

if [ -e "$TARGET" ]; then
    echo "Replacing $TARGET"
    rm -rf "$TARGET"
fi

mkdir -p "$INSTALL_DIR"
cp -R "build/$APP_NAME.app" "$TARGET"

echo
echo "Installed $TARGET"
xattr -lr "$TARGET" | grep -q quarantine \
    && echo "WARNING: the installed app is quarantined; it was not built locally." \
    || echo "Not quarantined — it will open normally."
