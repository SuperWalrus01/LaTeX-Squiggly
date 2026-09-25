<#
    Starts a built .exe on a real Windows machine and checks that it stays running.

    Made for CI, where nobody can double-click anything: it launches the app the
    way a user would, waits, and reports whether the process is still there,
    what it wrote to %APPDATA%\LaTeXSquiggly, and a screenshot of the desktop.
    Keystrokes cannot be tested this way. Anything this script types is
    injected input, which the app deliberately ignores.

        .\windows\smoke-test.ps1 -Exe "windows\dist\win-x64\LaTeX Squiggly.exe" -Label current

    Exits non-zero if the app did not stay up in any scenario.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Exe,
    [string] $Label = "app",
    [int] $WaitSeconds = 20,
    [string] $OutDir = "smoke-results"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

$data = Join-Path $env:APPDATA "LaTeXSquiggly"
$out = Join-Path $OutDir $Label
New-Item -ItemType Directory -Force -Path $out | Out-Null
$failures = @()

function Save-Screenshot([string] $name) {
    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save((Join-Path $out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose(); $bitmap.Dispose()
    } catch {
        Write-Host "   (no screenshot: $($_.Exception.Message))"
    }
}

function Stop-App {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Exe)
    Get-Process -Name $name, "LaTeX Squiggly", "LaTeX-Squiggly*" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Show-Files([string] $name) {
    foreach ($file in "log.txt", "crash.log") {
        $path = Join-Path $data $file
        if (Test-Path $path) {
            Copy-Item $path (Join-Path $out "$name-$file")
            Write-Host "   --- $file"
            Get-Content $path | ForEach-Object { Write-Host "   | $_" }
        }
    }
}

function Test-Launch([string] $name, [switch] $Fresh) {
    Write-Host "==> [$Label] $name" -ForegroundColor Cyan
    Stop-App
    if ($Fresh -and (Test-Path $data)) { Remove-Item -Recurse -Force $data }

    $process = Start-Process -FilePath $Exe -PassThru
    Start-Sleep -Seconds $WaitSeconds
    Save-Screenshot $name

    if ($process.HasExited) {
        $code = $process.ExitCode
        Write-Host ("   FAIL: exited after start, code {0} (0x{0:X8})" -f $code) -ForegroundColor Red
        $script:failures += "$name exited with code $code"
    } else {
        $memory = [math]::Round($process.WorkingSet64 / 1MB)
        Write-Host "   ok: still running after $WaitSeconds s, $memory MB, responding: $($process.Responding)" -ForegroundColor Green
    }
    Show-Files $name
    return $process
}

Test-Launch "first-run" -Fresh | Out-Null
Test-Launch "second-run" | Out-Null

# A second copy must say "already running" and leave the first one alone.
Write-Host "==> [$Label] second-copy" -ForegroundColor Cyan
Stop-App
$first = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 8
$second = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 8
Save-Screenshot "second-copy"
if ($first.HasExited) {
    Write-Host "   FAIL: the first copy exited when a second was started" -ForegroundColor Red
    $failures += "first copy exited when a second started"
} else {
    Write-Host "   ok: the first copy is still running" -ForegroundColor Green
}
Write-Host "   second copy exited: $($second.HasExited)"
Show-Files "second-copy"

Stop-App

# Anything Windows itself recorded about the process ending badly.
Write-Host "==> [$Label] Application event log" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = (Get-Date).AddMinutes(-15) } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match "Squiggly|\.NET Runtime|Application Error" } |
    ForEach-Object { Write-Host "   $($_.TimeCreated) $($_.ProviderName): $($_.Message)" }

if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "PASSED: $Label stayed up in every scenario." -ForegroundColor Green
