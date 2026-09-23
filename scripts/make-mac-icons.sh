#!/usr/bin/env bash
#
# Regenerates the icons from the artwork in assets/. Run this after changing
# assets/menu-icon.png, assets/app-icon.png or assets/dmg-image.png; the
# outputs are committed, so a normal build does not need it.
#
#   scripts/make-mac-icons.sh
#
# Produces:
#   Sources/LaTeXSquigglyApp/MenuBarIconData.swift   the menu bar mark
#   assets/app-icon.icns                             the bundle icon
#   assets/volume-icon.icns                          the mounted disk's icon
#   assets/dmg-background.tiff                       behind the two icons
#
set -euo pipefail

cd "$(dirname "$0")/.."

swift scripts/make-app-icons.swift

iconutil --convert icns --output assets/app-icon.icns assets/app-icon.iconset
rm -rf assets/app-icon.iconset

echo "Built assets/app-icon.icns"

# The disk image's two pictures. Separate script because they are built from
# different artwork and one of them is drawn rather than resized.
swift scripts/make-dmg-images.swift

iconutil --convert icns --output assets/volume-icon.icns assets/volume-icon.iconset
rm -rf assets/volume-icon.iconset

echo "Built assets/volume-icon.icns"
