#!/usr/bin/env bash
#
# Runs every check the repository has, in the order they depend on each other.
# This is what CI runs, so a green run here is a green run there.
#
#   scripts/check-all.sh
#
# The steps:
#
#   1. versions       every file carrying a version agrees with VERSION
#   2. engine         the Swift engine builds and passes its own suite
#   3. generated      every generated file is exactly what its generator makes
#   4. windows        the C# port gives the Swift engine's answer, every time
#   5. chrome         the extension's engine does too, and its copy of
#                     MathJax is the one scripts/fetch-mathjax.sh wrote
#
# Step 3 is the one that catches the likeliest mistake: a generated table
# edited by hand. It regenerates everything from the Swift engine and fails if
# the result differs from what is committed, so the fix is always to edit the
# generator, never its output.
#
# Step 4 needs the .NET 8 SDK. Without it the step is skipped with a warning
# rather than failing, so the rest can be checked on a machine that only builds
# the Mac app. CI always has it.
#
set -euo pipefail

cd "$(dirname "$0")/.."

export DOTNET_CLI_TELEMETRY_OPTOUT=1
if [ -z "${DOTNET_ROOT:-}" ] && [ -x "$HOME/.dotnet/dotnet" ]; then
    export DOTNET_ROOT="$HOME/.dotnet"
    export PATH="$DOTNET_ROOT:$PATH"
fi

# Files that generators write. Kept in one place so the drift check and the
# list in CONTRIBUTING.md can be compared at a glance.
GENERATED=(
    Sources/LaTeXUnicode/SymbolTableData.swift
    Sources/LaTeXUnicode/ScriptTables.swift
    Sources/LaTeXUnicodeChecks/GeneratedCodepointChecks.swift
    chrome/engine/tables.js
    windows/LaTeXSquiggly.Core/Engine
    conformance/reference.json
    conformance/windows-result.json
    site/assets/data.js
    site/index.html
)

echo "==> 1/5  versions"
python3 scripts/check-version.py

echo "==> 2/5  engine"
swift build
swift run latex-squiggly-check

echo "==> 3/5  generated files"
python3 scripts/generate-swift-tables.py >/dev/null
swift build >/dev/null
python3 scripts/generate-js-tables.py >/dev/null
python3 scripts/generate-csharp-tables.py >/dev/null
python3 scripts/generate-conformance-reference.py >/dev/null
python3 scripts/make-site.py >/dev/null
if ! git diff --quiet -- "${GENERATED[@]}"; then
    echo
    echo "These generated files differ from what their generators produce:"
    git diff --stat -- "${GENERATED[@]}"
    echo
    echo "Edit the generator, not its output, then run this again."
    exit 1
fi
echo "every generated file matches its generator"

echo "==> 4/5  windows"
if command -v dotnet >/dev/null; then
    dotnet run --project windows/LaTeXSquiggly.Conformance -v quiet -- conformance/reference.json
    git diff --quiet -- conformance/windows-result.json || {
        echo "conformance/windows-result.json changed; commit it with this change"
        exit 1
    }
else
    echo "warning: skipped, the .NET 8 SDK is not installed"
fi

echo "==> 5/5  chrome"
node chrome/test/conformance.mjs
(cd chrome/renderer/mathjax && shasum -a 256 --check --quiet SHA256SUMS)
echo "MathJax matches its checksums"

echo
echo "All checks passed."
