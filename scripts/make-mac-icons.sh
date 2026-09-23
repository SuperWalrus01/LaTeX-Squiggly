#!/usr/bin/env bash
#
# Regenerates the icons from the artwork in Assets/. Run this after changing
# Assets/menu-icon.png, Assets/app-icon.png or Assets/dmg_image.png; the
# outputs are committed, so a normal build does not need it.
#
#   Scripts/make-icons.sh
#
# Produces:
#   Sources/LaTeXSquigglyApp/MenuBarIconData.swift   the menu bar mark
#   Assets/AppIcon.icns                              the bundle icon
#   Assets/VolumeIcon.icns                           the mounted disk's icon
#   Assets/dmg-background.tiff                       behind the two icons
#
set -euo pipefail

cd "$(dirname "$0")/.."

swift Tools/make_icons.swift

iconutil --convert icns --output Assets/AppIcon.icns Assets/AppIcon.iconset
rm -rf Assets/AppIcon.iconset

echo "Built Assets/AppIcon.icns"

# The disk image's two pictures. Separate script because they are built from
# different artwork and one of them is drawn rather than resized.
swift Tools/make_dmg_images.swift

iconutil --convert icns --output Assets/VolumeIcon.icns Assets/VolumeIcon.iconset
rm -rf Assets/VolumeIcon.iconset

echo "Built Assets/VolumeIcon.icns"
