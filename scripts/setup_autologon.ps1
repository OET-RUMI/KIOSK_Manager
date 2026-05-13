# setup_autologon.ps1
# Configures Windows auto-login for the current user via Sysinternals Autologon.
# Assumes the kiosk account has no password.

# Require admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "autologon_setup.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# check if AutoAdminLogon is already enabled for the current user
$winlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$existing = Get-ItemProperty -Path $winlogonKey -ErrorAction SilentlyContinue
if ($existing.AutoAdminLogon -eq "1" -and $existing.DefaultUserName -eq $env:USERNAME) {
    Log "Auto-login already configured for $env:USERNAME"
    exit 0
}

$autologon = "C:\rumi-kiosk\bin\Autologon.exe"
if (-not (Test-Path $autologon)) {
    Log "FATAL: Autologon.exe not found at $autologon"
    exit 1
}

# Autologon.exe args: <username> <domain> <password>
# Empty password is fine for accounts with no password.
# /accepteula suppresses the first-run EULA dialog.
Log "Configuring auto-login for user: $env:USERNAME"
$proc = Start-Process -FilePath $autologon -ArgumentList "/accepteula", $env:USERNAME, $env:COMPUTERNAME, '""' -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Log "Autologon.exe exited with code $($proc.ExitCode)"
    exit 1
}

# Verify it took
$verify = Get-ItemProperty -Path $winlogonKey -ErrorAction SilentlyContinue
if ($verify.AutoAdminLogon -ne "1") {
    Log "FATAL: Autologon.exe ran but AutoAdminLogon registry value is not set"
    exit 1
}

Log "Auto-login configured for $env:USERNAME. Will take effect on next reboot."
exit 0