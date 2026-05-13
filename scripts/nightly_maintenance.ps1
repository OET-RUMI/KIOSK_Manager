# nightly_maintenance.ps1
# Scheduled task: pull latest build, stage it, reboot.
# Reboot happens unconditionally - a hung sync should not be able to wedge a kiosk.
# The watchdog's off-hours window (configured separately) keeps UE from launching
#   until visitor hours, so this maintenance reboot is invisible to visitors.

$ErrorActionPreference = "Continue"  # we want to push through failures, not abort

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "maintenance.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Log "===== Nightly maintenance starting ====="

$scriptDir = "C:\rumi-kiosk\scripts"

# Run P4 sync. Don't bail on failure - we still want to reboot for a clean state.
Log "Running setup_p4.ps1"
try {
    & (Join-Path $scriptDir "setup_p4.ps1")
    if ($LASTEXITCODE -ne 0) {
        Log "setup_p4.ps1 exited non-zero ($LASTEXITCODE); continuing anyway"
    }
} catch {
    Log "setup_p4.ps1 threw: $_; continuing anyway"
}

# Stage whatever's in build/ to runtime/. If sync failed, this re-stages the same build,
# which is harmless. If sync brought new files, runtime gets the new build.
Log "Running stage_build.ps1"
try {
    & (Join-Path $scriptDir "stage_build.ps1")
    if ($LASTEXITCODE -ne 0) {
        Log "stage_build.ps1 exited non-zero ($LASTEXITCODE); continuing anyway"
    }
} catch {
    Log "stage_build.ps1 threw: $_; continuing anyway"
}

Log "Rebooting in 30 seconds"
Log "===== Nightly maintenance complete ====="

Start-Sleep -Seconds 30
Restart-Computer -Force