# setup_startup.ps1
# Creates a Startup folder shortcut to run_kiosk.bat so the watchdog
# launches automatically on login.

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "startup_setup.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

$kioskBat = "C:\rumi-kiosk\scripts\run_kiosk.bat"
if (-not (Test-Path $kioskBat)) {
    Log "FATAL: $kioskBat not found"
    exit 1
}

# Resolve current user's Startup folder. [Environment]::GetFolderPath
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "RUMI Kiosk.lnk"

# if shortcut already points at the right target, do nothing. Otherwise create/replace it.
$shell = New-Object -ComObject WScript.Shell
if (Test-Path $shortcutPath) {
    $existing = $shell.CreateShortcut($shortcutPath)
    if ($existing.TargetPath -eq $kioskBat) {
        Log "Startup shortcut already present at $shortcutPath"
        exit 0
    }
    Log "Replacing existing shortcut (target was: $($existing.TargetPath))"
    Remove-Item $shortcutPath -Force
}

Log "Creating Startup shortcut: $shortcutPath -> $kioskBat"
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $kioskBat
$shortcut.WorkingDirectory = Split-Path $kioskBat -Parent
$shortcut.WindowStyle = 7  # 7 = minimized (cmd window won't steal focus from UE)
$shortcut.Description = "RUMI kiosk watchdog"
$shortcut.Save()

if (-not (Test-Path $shortcutPath)) {
    Log "FATAL: Shortcut was not created"
    exit 1
}

Log "Startup shortcut created. Watchdog will launch on next login."
exit 0