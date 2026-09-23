<#
    Builds and runs the Windows app, on Windows.

    scripts/build-windows.sh is the full pipeline and it only runs on macOS: its first four steps
    build the Swift engine, generate the C# tables from it, generate the icons,
    and record Swift's answers to 2,030 fragments. None of that can happen here,
    and none of it needs to: every one of those outputs is committed, so this
    machine has the generated tables, the icons and the reference file already.

    What is left is the part that matters here.

        .\windows\build.ps1            check the port, then publish one .exe
        .\windows\build.ps1 -Run       build and launch it, for testing changes
        .\windows\build.ps1 -Check     run the conformance suite and stop

    -Run is the loop worth using while chasing a bug. It builds in seconds and
    starts the app straight from bin\, where publishing a self-contained
    single-file .exe takes about a minute and produces 63 MB you do not need.
#>

[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $Check,
    [string] $Rid = "win-x64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$app = "windows\LaTeXSquiggly.App\LaTeXSquiggly.App.csproj"
$conformance = "windows\LaTeXSquiggly.Conformance"
$reference = "conformance\reference.json"

function Assert-Dotnet {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "The .NET 8 SDK is not on PATH. Get it from https://dotnet.microsoft.com/download/dotnet/8.0"
    }
}

Assert-Dotnet

# The port is checked against the Swift engine's recorded answers before
# anything is built from it, exactly as it is on the Mac. The reference file is
# committed, so this works with no Swift and no Python.
Write-Host "==> checking the port against the Swift engine's answers" -ForegroundColor Cyan
dotnet run --project $conformance -c Release -v quiet --nologo -- $reference
if ($LASTEXITCODE -ne 0) { throw "the conformance suite failed; nothing was built" }

if ($Check) { return }

if ($Run) {
    Write-Host "==> building and launching" -ForegroundColor Cyan
    # Debug, because this is the loop for watching it fail rather than shipping.
    dotnet run --project $app -c Debug -v quiet --nologo
    return
}

Write-Host "==> publishing one self-contained .exe for $Rid" -ForegroundColor Cyan
dotnet publish $app -c Release -r $Rid `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=none `
    -o "windows\dist\$Rid" -v quiet --nologo
if ($LASTEXITCODE -ne 0) { throw "publish failed" }

Get-ChildItem "windows\dist\$Rid\*.exe" | Format-Table Name, Length, LastWriteTime
Write-Host "Done." -ForegroundColor Green
