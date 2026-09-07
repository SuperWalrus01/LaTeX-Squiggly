#!/usr/bin/env bash
#
# Regenerates the icons from the artwork in Assets/. Run this after changing
# Assets/menu-icon.png or Assets/app-icon.png; the outputs are committed, so a
# normal build does not need it.
#
#   Scripts/make-icons.sh
#
# Produces:
#   Sources/LaTeXSquigglyApp/MenuBarIconData.swift   the menu bar mark
#   Assets/AppIcon.icns                              the bundle icon
#
set -euo pipefail

cd "$(dirname "$0")/.."

swift Tools/make_icons.swift

iconutil --convert icns --output Assets/AppIcon.icns Assets/AppIcon.iconset
rm -rf Assets/AppIcon.iconset

echo "Built Assets/AppIcon.icns"
