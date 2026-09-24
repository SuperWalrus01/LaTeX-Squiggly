#!/bin/bash
# Downloads the pinned MathJax release from npm and copies the components the
# extension's renderer uses into chrome/renderer/mathjax/, with MathJax's
# licence and a SHA256SUMS file that scripts/check-all.sh verifies.
#
# Manifest V3 forbids remotely hosted code, so MathJax is committed rather than
# loaded from a CDN. The tarball is checked against npm's published integrity
# hash before anything is copied, so a changed download fails here.
#
# Run:  scripts/fetch-mathjax.sh
#
# To move to another release, change VERSION and INTEGRITY together: the
# integrity is `npm view mathjax@<version> dist.integrity`.
set -euo pipefail

VERSION="3.2.2"
INTEGRITY="sha512-Bt+SSVU8eBG27zChVewOicYs7Xsdt40qm4+UpHyX7k0/O9NliPc+x77k1/FEsPsjKPZGJvtRZM1vO+geW0OhGw=="

# The startup component loads the rest on demand, from the same folder. These
# are all it asks for with the configuration in chrome/renderer/render.js;
# tex-full already contains every TeX package, physics included.
FILES=(
    startup.js
    core.js
    input/tex-full.js
    output/svg.js
    output/svg/fonts/tex.js
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/chrome/renderer/mathjax"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "https://registry.npmjs.org/mathjax/-/mathjax-$VERSION.tgz" -o "$WORK/mathjax.tgz"

GOT="sha512-$(openssl dgst -sha512 -binary "$WORK/mathjax.tgz" | openssl base64 -A)"
if [ "$GOT" != "$INTEGRITY" ]; then
    echo "mathjax-$VERSION.tgz does not match its pinned integrity hash" >&2
    echo "  want $INTEGRITY" >&2
    echo "  got  $GOT" >&2
    exit 1
fi

tar -xzf "$WORK/mathjax.tgz" -C "$WORK"

rm -rf "$DEST"
for file in "${FILES[@]}"; do
    mkdir -p "$DEST/$(dirname "$file")"
    cp "$WORK/package/es5/$file" "$DEST/$file"
done
cp "$WORK/package/LICENSE" "$DEST/LICENSE"
echo "$VERSION" > "$DEST/VERSION"

cd "$DEST"
find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | xargs shasum -a 256 > SHA256SUMS

echo "copied MathJax $VERSION into ${DEST#$ROOT/}"
