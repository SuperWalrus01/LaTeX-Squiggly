<#
    Drives the renderer window on a real Windows machine: opens it with the
    global shortcut, types an equation, presses Ctrl+Enter, and checks that an
    image came out on the clipboard at the resolution that makes it paste at
    its previewed size.

    Windows PowerShell 5.1, not pwsh: the clipboard needs a single-threaded
    apartment, which is 5.1's default.

        powershell -File windows\renderer-test.ps1 -Exe "windows\dist\win-x64\LaTeX Squiggly.exe"

    Exits non-zero if any step fails. Screenshots and the copied image go to -OutDir.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Exe,
    [string] $OutDir = "smoke-results\renderer"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Keys {
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static void Chord(params byte[] keys) {
        foreach (var k in keys) keybd_event(k, 0, 0, UIntPtr.Zero);
        for (int i = keys.Length - 1; i >= 0; i--) keybd_event(keys[i], 0, 2, UIntPtr.Zero);
    }
}
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$data = Join-Path $env:APPDATA "LaTeXSquiggly"
$log = Join-Path $data "log.txt"
$failures = @()

function Save-Screenshot([string] $name) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save((Join-Path $OutDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
}

function Wait-Log([string] $text, [int] $seconds) {
    for ($i = 0; $i -lt $seconds * 2; $i++) {
        if ((Test-Path $log) -and (Select-String -Path $log -SimpleMatch $text -Quiet)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

Get-Process -Name "LaTeX Squiggly" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
if (Test-Path $data) { Remove-Item -Recurse -Force $data }
# Not a first run, so no welcome message sits in front of the renderer.
New-Item -ItemType Directory -Force -Path $data | Out-Null
Set-Content -Path (Join-Path $data "settings.json") -Value '{ "ConversionEnabled": true }'

[System.Windows.Forms.Clipboard]::Clear()
$process = Start-Process -FilePath $Exe -PassThru
if (-not (Wait-Log "keyboard hook installed" 20)) { $failures += "the app did not start" }
Start-Sleep -Seconds 2

Write-Host "==> Win+Alt+L"
[Keys]::Chord(0x5B, 0x12, 0x4C)   # left Windows, Alt, L
$opened = Get-Date
# The first open starts the WebView2 runtime and makes its profile, which on a
# freshly booted runner has taken 37 s; on a desktop it is a second or two.
if (Wait-Log "renderer: page loaded" 90) {
    Write-Host ("   ok: the page loaded, {0:N1} s after the shortcut" -f ((Get-Date) - $opened).TotalSeconds) -ForegroundColor Green
} else {
    Write-Host "   FAIL: the page did not load" -ForegroundColor Red
    $failures += "the renderer page did not load"
}
# MathJax loads after the page does.
Start-Sleep -Seconds 6
Save-Screenshot "renderer-open"

Write-Host "==> typing an equation, then Ctrl+Enter"
[System.Windows.Forms.SendKeys]::SendWait("^a")
# SendKeys spelling: {^} is a caret, {{} and {}} are braces.
[System.Windows.Forms.SendKeys]::SendWait("\int_0{^}1 x{^}2 dx = \frac{{}1{}}{{}3{}}")
Start-Sleep -Seconds 3
Save-Screenshot "renderer-typed"
[System.Windows.Forms.SendKeys]::SendWait("^{ENTER}")
Start-Sleep -Seconds 3
Save-Screenshot "renderer-after-copy"

$png = [System.Windows.Forms.Clipboard]::GetData("PNG")
if ($png -is [System.IO.MemoryStream]) {
    $image = [System.Drawing.Image]::FromStream($png)
    $path = Join-Path $OutDir "clipboard.png"
    $image.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("   ok: PNG on the clipboard, {0} x {1} pixels at {2} dpi" -f $image.Width, $image.Height, $image.HorizontalResolution) -ForegroundColor Green
    if ($image.HorizontalResolution -le 96) {
        $failures += "the PNG says $($image.HorizontalResolution) dpi, so it would paste at its full pixel size"
    }
} else {
    Write-Host "   FAIL: no PNG on the clipboard" -ForegroundColor Red
    $failures += "no PNG on the clipboard"
}
if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    Write-Host "   ok: a bitmap too, for apps that take only that" -ForegroundColor Green
} else {
    $failures += "no bitmap on the clipboard"
}

if ($process.HasExited) { $failures += "the app exited, code $($process.ExitCode)" }

Write-Host "   --- log.txt"
Get-Content $log | ForEach-Object { Write-Host "   | $_" }
foreach ($file in "renderer-local.json", "crash.log") {
    $path = Join-Path $data $file
    if (Test-Path $path) {
        Write-Host "   --- $file"
        Get-Content $path | ForEach-Object { Write-Host "   | $_" }
    }
}

Get-Process -Name "LaTeX Squiggly" -ErrorAction SilentlyContinue | Stop-Process -Force

if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: the renderer opened, rendered and copied." -ForegroundColor Green
