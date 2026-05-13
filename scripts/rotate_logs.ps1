# rotate_logs.ps1
# Log housekeeping. Run once at kiosk start before the watchdog.
# - Timestamped logs (setup_*.log, kiosk_*.log): delete if older than log_retention_days
# - Append-only logs (watchdog.log, *_setup.log, stage.log): if over log_max_size_mb,
#   cull lines from the top until the file is under 50% of its pre-cull size

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

# Config with sensible defaults
$retentionDays = if ($config.log_retention_days) { [int]$config.log_retention_days } else { 30 }
$maxSizeMb = if ($config.log_max_size_mb) { [int]$config.log_max_size_mb } else { 100 }
$maxSizeBytes  = $maxSizeMb * 1MB

$logDir = $config.log_path
if (-not (Test-Path $logDir)) {
    exit 0
}

# Log our own activity to a dedicated file (which is itself subject to size-based rotation)
$logFile = Join-Path $logDir "rotate.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Log "Rotation starting (retention: ${retentionDays}d, max size: ${maxSizeMb}MB)"

# --- Age-based deletion: timestamped transcripts ---
# These files have names like setup_20260513_143022.log and kiosk_20260513_143022.log
# When they go past their retention window, just delete them
$cutoff = (Get-Date).AddDays(-1 * $retentionDays)
$timestampedPatterns = @("setup_*.log", "kiosk_*.log")

$deleted = 0
foreach ($pattern in $timestampedPatterns) {
    $files = Get-ChildItem -Path $logDir -Filter $pattern -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($f.LastWriteTime -lt $cutoff) {
            try {
                Remove-Item $f.FullName -Force
                $deleted++
            } catch {
                Log "Failed to delete $($f.Name): $_"
            }
        }
    }
}
if ($deleted -gt 0) {
    Log "Deleted $deleted timestamped log(s) older than $retentionDays days"
}

# --- Size-based truncation: append-only logs ---
# These grow forever. When one passes the threshold, drop the oldest half.
# Whole file goes into memory; at ~10MB that's fine.
$appendOnly = Get-ChildItem -Path $logDir -Filter "*.log" -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notlike "setup_*.log" -and $_.Name -notlike "kiosk_*.log"
}

foreach ($f in $appendOnly) {
    if ($f.Length -le $maxSizeBytes) { continue }

    $originalSizeMb = [math]::Round($f.Length / 1MB, 2)
    Log "Truncating $($f.Name) (${originalSizeMb}MB > ${maxSizeMb}MB)"

    try {
        $lines = Get-Content $f.FullName
        $keepFrom = [math]::Floor($lines.Count / 2)
        $kept = $lines[$keepFrom..($lines.Count - 1)]

        $marker = "=== log truncated $(Get-Date -Format o) (kept newest 50%, dropped $keepFrom lines) ==="
        $newContent = @($marker) + $kept

        # Write to a temp file first then move, so a crash mid-write doesn't lose the log
        $tmp = "$($f.FullName).tmp"
        Set-Content -Path $tmp -Value $newContent -Encoding UTF8
        Move-Item -Path $tmp -Destination $f.FullName -Force

        $newSizeMb = [math]::Round((Get-Item $f.FullName).Length / 1MB, 2)
        Log "  $($f.Name): ${originalSizeMb}MB -> ${newSizeMb}MB ($($lines.Count) -> $($kept.Count) lines)"
    } catch {
        Log "Failed to truncate $($f.Name): $_"
    }
}

Log "Rotation complete"
exit 0