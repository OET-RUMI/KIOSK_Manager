# setup_lockdown.ps1
# Installs AutoHotkey v2, deploys lockdown.ahk, applies the
# DisableTaskMgr registry policy, and creates a Startup shortcut so
# the lockdown runs on login.

# require admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "lockdown_setup.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# install AHK if not present
$ahkExe = $null

$candidates = @(
    "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
    "C:\Program Files\AutoHotkey\AutoHotkey64.exe"
)
foreach ($c in $candidates) {
    if (Test-Path $c) { $ahkExe = $c; break }
}
if (-not $ahkExe) {
    $cmd = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($cmd) { $ahkExe = $cmd.Source }
}

if (-not $ahkExe) {
    Log "AutoHotkey v2 not found - installing via winget"
    & winget install --id AutoHotkey.AutoHotkey --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Log "FATAL: winget install AutoHotkey failed with code $LASTEXITCODE"
        exit 1
    }
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ahkExe = $c; break }
    }
    if (-not $ahkExe) {
        Log "FATAL: AutoHotkey installed but AutoHotkey64.exe not found in expected paths"
        exit 1
    }
}
Log "AutoHotkey interpreter: $ahkExe"

# make sure script exists in expected location
$ahkScript = "C:\rumi-kiosk\scripts\lockdown.ahk"
if (-not (Test-Path $ahkScript)) {
    Log "FATAL: $ahkScript not found. Make sure lockdown.ahk is in the scripts folder."
    exit 1
}
Log "Lockdown script: $ahkScript"

# disable task manager, Ctrl+Shift+Esc can't be intercepted by AHK because the OS handles it before
# user-mode hooks. The policy makes the launched taskmgr show "Task Manager has been disabled by your administrator"
# instead, which is good enough
Log "Setting DisableTaskMgr policy"
$polKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $polKey)) {
    New-Item -Path $polKey -Force | Out-Null
}
New-ItemProperty -Path $polKey -Name "DisableTaskMgr" -Value 1 -PropertyType DWord -Force | Out-Null

# add shortcut to Startup so lockdown runs on login. If the shortcut already exists and points to the right place, do nothing.
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "RUMI Lockdown.lnk"
 
$shell = New-Object -ComObject WScript.Shell
if (Test-Path $shortcutPath) {
    $existing = $shell.CreateShortcut($shortcutPath)
    if ($existing.TargetPath -eq $ahkExe -and $existing.Arguments -eq "`"$ahkScript`"") {
        Log "Startup shortcut already present at $shortcutPath"
        exit 0
    }
    Log "Replacing existing shortcut (target was: $($existing.TargetPath))"
    Remove-Item $shortcutPath -Force
}
 
Log "Creating Startup shortcut: $shortcutPath -> $ahkExe $ahkScript"
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $ahkExe
$shortcut.Arguments = "`"$ahkScript`""
$shortcut.WorkingDirectory = Split-Path $ahkScript -Parent
$shortcut.WindowStyle = 7  # minimized
$shortcut.Description = "RUMI kiosk keyboard lockdown"
$shortcut.Save()
 
if (-not (Test-Path $shortcutPath)) {
    Log "FATAL: Shortcut was not created"
    exit 1
}
 
# Launch now, skip if already running.
$existing = Get-Process -Name "AutoHotkey64" -ErrorAction SilentlyContinue
if ($existing) {
    Log "AutoHotkey64 already running (PID: $($existing.Id -join ',')) - skipping launch"
} else {
    Log "Launching lockdown for current session"
    Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkScript`""
}
 
Log "Lockdown configured."
Log "To disable: delete C:\rumi-kiosk\LOCK  OR  Stop-Process -Name AutoHotkey64 -Force"
exit 0