# setup_scheduled_tasks.ps1
# Registers the nightly maintenance Scheduled Task.

# Require admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "scheduled_tasks_setup.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

$taskName = "RUMI Nightly Maintenance"
$scriptPath = "C:\rumi-kiosk\scripts\nightly_maintenance.ps1"

if (-not (Test-Path $scriptPath)) {
    Log "FATAL: $scriptPath not found"
    exit 1
}

# Pull schedule from config. Default to 02:00.
$rebootTime = if ($config.nightly_reboot_time) { $config.nightly_reboot_time } else { "02:00" }

# Sanity-check the format - we want HH:mm 
if ($rebootTime -notmatch '^\d{2}:\d{2}$') {
    Log "FATAL: nightly_reboot_time must be HH:mm (got '$rebootTime')"
    exit 1
}

Log "Registering scheduled task '$taskName' for $rebootTime daily"

# Remove existing task if present so re-running this script updates the schedule
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Log "Removing existing task to recreate with current settings"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Daily -At $rebootTime

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

# StartWhenAvailable: if the machine was off at trigger time, run as soon as it's up.
# DontStopOnIdleEnd / AllowStartIfOnBatteries: kiosks are wall-powered but be explicit.
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings | Out-Null

# Verify
$verify = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $verify) {
    Log "FATAL: task did not register"
    exit 1
}

Log "Task registered. Next run: $((Get-ScheduledTaskInfo -TaskName $taskName).NextRunTime)"

# For testing to immediately run the task
# Start-ScheduledTask -TaskName $taskName

exit 0