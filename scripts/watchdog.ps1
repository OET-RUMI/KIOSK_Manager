# watchdog.ps1
# Launches the UE executable, relaunches on crash.
# Reboots the machine if too many crashes occur within the watch window.
# Honors off-hours window: during off-hours, UE is not launched but heartbeats continue.

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "watchdog.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Send-Heartbeat {
    param(
        [string]$status = "up",
        [string]$msg = "OK"
    )

    if (-not $config.uptime_kuma_push_url) {
        return
    }

    try {
        $url = "$($config.uptime_kuma_push_url)?status=$status&msg=$msg"
        Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 | Out-Null
    } catch {
        Log "Failed to send heartbeat: $_"
    }
}

# Returns $true if "now" is inside the off-hours window.
# Window is defined by off_hours_start (HH:mm) and off_hours_duration_hours.
function Test-OffHours {
    if (-not $config.off_hours_start -or -not $config.off_hours_duration_hours) {
        return $false
    }

    if ($config.off_hours_start -notmatch '^\d{2}:\d{2}$') {
        Log "Invalid off_hours_start format: $($config.off_hours_start); ignoring off-hours"
        return $false
    }

    $now = Get-Date
    $parts = $config.off_hours_start.Split(':')
    $startToday = Get-Date -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0 -Millisecond 0

    # The window in progress could have started today or yesterday.
    $duration = [TimeSpan]::FromHours([double]$config.off_hours_duration_hours)

    foreach ($start in @($startToday, $startToday.AddDays(-1))) {
        $end = $start + $duration
        if ($now -ge $start -and $now -lt $end) {
            return $true
        }
    }
    return $false
}

# Find the executable in runtime folder
$exePath = Get-ChildItem -Path $config.runtime_path -Filter $config.ue_executable -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exePath) {
    Log "FATAL: Executable '$($config.ue_executable)' not found in $($config.runtime_path)"
    Log "Has stage_build.ps1 been run successfully?"
    exit 1
}

Log "Watchdog starting"
Log "Target executable: $($exePath.FullName)"
Log "Max crashes: $($config.max_crash_count) in $($config.crash_window_minutes) min will reboot"
if ($config.off_hours_start -and $config.off_hours_duration_hours) {
    Log "Off-hours: $($config.off_hours_start) for $($config.off_hours_duration_hours)h"
}

# Track recent crash times as a rolling window
$crashTimes = New-Object System.Collections.ArrayList

while ($true) {
    # off-hours gate: idle here until visitor hours, sending heartbeats so Kuma sees us
    if (Test-OffHours) {
        Log "In off-hours window, idling (will recheck in 60s)"
        Send-Heartbeat -status "up" -msg "off_hours"
        Start-Sleep -Seconds 60
        continue
    }

    Log "Launching UE"
    $startTime = Get-Date

    try {
        $process = Start-Process -FilePath $exePath.FullName -PassThru
        Log "UE started, PID: $($process.Id)"

        # loop while UE is running, sending heartbeat every 30s
        while (-not $process.HasExited) {
            Send-Heartbeat -status "up" -msg "UE running, PID: $($process.Id)"
            Start-Sleep -Seconds 30
            $process.Refresh()
        }

        $exitCode = $process.ExitCode
        $runtimeSeconds = ((Get-Date) - $startTime).TotalSeconds
        Log "UE exited with code $exitCode after $([math]::Round($runtimeSeconds, 1))s"
        Send-Heartbeat -status "down" -msg "ue_exited_$exitCode"
    }
    catch {
        Log "Failed to launch UE: $_"
        $exitCode = -1
        $runtimeSeconds = 0
        Send-Heartbeat -status "down" -msg "ue_launch_failed"
    }

    # Record this exit in the crash window
    $now = Get-Date
    [void]$crashTimes.Add($now)

    # Prune crash times outside the window
    $windowStart = $now.AddMinutes(-1 * $config.crash_window_minutes)
    $crashTimes = [System.Collections.ArrayList]@($crashTimes | Where-Object { $_ -ge $windowStart })

    Log "Crashes in last $($config.crash_window_minutes) min: $($crashTimes.Count) / $($config.max_crash_count)"

    if ($crashTimes.Count -ge $config.max_crash_count) {
        Log "Crash threshold reached. Rebooting machine in 10 seconds."
        Send-Heartbeat -status "down" -msg "crash_loop_rebooting"
        Start-Sleep -Seconds 10
        Restart-Computer -Force
        exit 0  # redundant, here so Restart-Computer can be commented out for testing without rebooting
    }

    Log "Relaunching in $($config.relaunch_delay_seconds) seconds"
    Start-Sleep -Seconds $config.relaunch_delay_seconds
}