#!/usr/bin/env bash
#
# Builds the Windows app, from a Mac.
#
# The whole pipeline in order, because the steps depend on each other and
# skipping one silently ships a port that has drifted:
#
#   1. build the Swift engine        the source of truth for every table
#   2. generate the C# tables        from the Swift engine's own dump
#   3. generate the icons            trimmed from the same artwork as the Mac's
#   4. generate the reference        Swift's answer to 2,000 fragments
#   5. run the conformance suite     prove the C# engine gives the same answers
#   6. publish                       one self-contained .exe, no installer
#
# Step 5 is the point of the whole arrangement. The app cannot be run on this
# machine, so agreement with the Swift engine is the only evidence available
# that the port is faithful, and it is checked before anything is published.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

RID="${1:-win-x64}"

echo "==> 1/6  building the Swift engine"
swift build

echo "==> 2/6  generating the C# tables from it"
python3 Tools/generate_csharp_tables.py

echo "==> 3/6  generating the icons"
python3 Tools/make_windows_icons.py

echo "==> 4/6  recording Swift's answers"
python3 Tools/generate_conformance_corpus.py

echo "==> 5/6  checking the port against them"
dotnet run --project windows/LaTeXSquiggly.Conformance -v quiet --property:WarningLevel=0

echo "==> 6/6  publishing for $RID"
dotnet publish windows/LaTeXSquiggly.App/LaTeXSquiggly.App.csproj \
    -c Release -r "$RID" \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:EnableCompressionInSingleFile=true \
    -p:DebugType=none \
    -o "windows/dist/$RID" \
    -v quiet --nologo

echo
ls -lh "windows/dist/$RID"
echo
echo "Done. Copy the .exe to a Windows machine and double-click it."
