#!/usr/bin/env bash
#
# Creates a stable self-signed code-signing identity in your login keychain.
#
# Why this matters for development, not distribution: macOS TCC identifies an
# app by its code signature. Ad-hoc signing (Xcode's default) keys on the code
# directory hash, which changes on every build — so macOS treats each rebuild as
# a different app and makes you re-grant Accessibility and Input Monitoring
# every single time. A stable identity fixes that.
#
# It does NOT help distribution. Only a Developer ID certificate and
# notarization do that, and both require the paid Apple Developer Program.
#
# Verified: codesign accepts an untrusted self-signed certificate as long as its
# keychain is in the search list. Your login keychain always is, so this script
# does not modify your trust store.
#
# Alternative (Apple's documented path, no script):
#   Keychain Access -> Certificate Assistant -> Create a Certificate
#   Name: the value of NAME below, Identity Type: Self Signed Root,
#   Certificate Type: Code Signing
#
set -euo pipefail

NAME="${SIGN_IDENTITY_NAME:-LaTeX-Squiggly Dev}"
DAYS="${DAYS:-3650}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Identity \"$NAME\" already exists in your login keychain."
    echo "Delete it in Keychain Access first if you want to recreate it."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A random transport password: LibreSSL, which is what /usr/bin/openssl is on
# macOS, produces a PKCS#12 that Apple's Security framework rejects when the
# password is empty.
P12_PASSWORD="$(openssl rand -hex 16)"

echo "Generating a self-signed code-signing certificate: $NAME"
openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -name "$NAME" \
    -passout "pass:$P12_PASSWORD" 2>/dev/null

# -T /usr/bin/codesign lets codesign use the private key without prompting.
echo "Importing into your login keychain (macOS may ask for your password)."
security import "$WORK/identity.p12" \
    -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign

# Without this, macOS prompts "codesign wants to access key ..." on every build.
# It needs the login keychain password, so it is asked for interactively.
echo
echo "Allowing codesign to use the key without prompting on every build."
echo "Enter your macOS login password (input hidden, not stored):"
read -r -s LOGIN_PASSWORD
if ! security set-key-partition-list \
        -S apple-tool:,apple:,codesign: -s \
        -k "$LOGIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
    echo
    echo "Could not set the key partition list. The identity still works, but"
    echo "macOS will prompt on the first codesign run. Click 'Always Allow'."
fi
unset LOGIN_PASSWORD

echo
echo "Done. Sign with:"
echo "    codesign --force --sign \"$NAME\" YourApp.app"
echo
echo "Or point the bundle script at it:"
echo "    SIGN_IDENTITY=\"$NAME\" Scripts/make-app.sh"
echo
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
