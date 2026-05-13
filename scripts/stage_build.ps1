# stage_build.ps1
# Copies the synced P4 build to the runtime folder.
# Runtime folder is what the watchdog actually launches from,
# so p4 sync can update build/ while UE is running from runtime/.

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "stage.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

try {
    Log "Staging build from $($config.build_path) to $($config.runtime_path)"

    if (-not (Test-Path $config.build_path)) {
        throw "Build path does not exist: $($config.build_path)"
    }

    # Check that the executable actually exists in the build
    $sourceExe = Get-ChildItem -Path $config.build_path -Filter $config.ue_executable -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sourceExe) {
        throw "Executable '$($config.ue_executable)' not found anywhere under $($config.build_path)"
    }
    Log "Source executable found: $($sourceExe.FullName)"

    # Wipe runtime folder and recreate
    if (Test-Path $config.runtime_path) {
        Log "Removing old runtime folder"
        Remove-Item -Path $config.runtime_path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $config.runtime_path -Force | Out-Null

    # Robust copy with robocopy (handles large files, retries, etc.)
    Log "Copying build (this may take a few minutes)"
    $rcArgs = @(
        $config.build_path,
        $config.runtime_path,
        "/E",       # copy subdirectories including empty ones
        "/R:3",     # retry 3 times on failure
        "/W:5",     # wait 5s between retries
        "/NFL",     # no file list (quieter log)
        "/NDL",     # no directory list
        "/NJH",     # no job header
        "/NJS",     # no job summary
        "/NP"       # no progress percentage
    )
    & robocopy @rcArgs | Out-Null

    # Robocopy exit codes 0-7 are success, anything 8 or above is a failure
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed with exit code $LASTEXITCODE"
    }

    Log "Staging complete. Exit code: $LASTEXITCODE (0-7 = success)"
    exit 0
}
catch {
    Log "STAGING FAILED: $_"
    exit 1
}