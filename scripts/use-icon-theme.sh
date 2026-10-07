#!/bin/sh
# Puts a holiday logo into the extension's icons, or the everyday one back.
#
#   scripts/use-icon-theme.sh halloween    (any folder in chrome/store/holidays/)
#   scripts/use-icon-theme.sh default
#
# It replaces chrome/icons/icon-{16,32,48,128}.png, which the toolbar, the
# popup, the settings page and the extensions page all show. The grey paused
# icons (icon-off-*) stay as they are. Reload the unpacked extension to see the
# change; users get it only with the next package uploaded to the Web Store.
# The Web Store listing's own icon is separate: upload the theme's
# logo/icon-128.png in the dashboard instead (see chrome/store/holidays/README.md).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOLIDAYS="$ROOT/chrome/store/holidays"
THEME="$1"

if [ -z "$THEME" ]; then
  echo "usage: $0 <theme|default>, where theme is one of:"
  ls "$HOLIDAYS" | grep -v README
  exit 1
fi

if [ "$THEME" = default ]; then
  git -C "$ROOT" checkout -- chrome/icons
  echo "chrome/icons has the everyday logo again"
  exit 0
fi

SRC="$HOLIDAYS/$THEME/logo"
if [ ! -d "$SRC" ]; then
  echo "no theme called $THEME. Choose one of:"
  ls "$HOLIDAYS" | grep -v README
  exit 1
fi

for size in 16 32 48 128; do
  cp "$SRC/icon-$size.png" "$ROOT/chrome/icons/icon-$size.png"
done
echo "chrome/icons now has the $THEME logo. Run '$0 default' to put the everyday one back."
