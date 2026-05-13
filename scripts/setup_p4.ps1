# setup_p4.ps1
# First-run + recurring P4 setup/sync for kiosk
# - Reads config.json
# - Logs in if no valid ticket exists (interactive prompt or env var P4PASSWD)
# - Creates/updates workspace
# - Syncs the stream to build_path

$ErrorActionPreference = "Stop"

$configPath = "C:\rumi-kiosk\config.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Config not found at $configPath"
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Validate required fields
$required = @("p4_port", "p4_user", "kiosk_name", "p4_stream", "build_path", "log_path")
foreach ($field in $required) {
    if (-not $config.$field) {
        Write-Error "Missing required config field: $field"
        exit 1
    }
}

# Ensure directories exist
New-Item -ItemType Directory -Path $config.build_path -Force | Out-Null
New-Item -ItemType Directory -Path $config.log_path -Force | Out-Null

$logFile = Join-Path $config.log_path "p4_setup.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# Set P4 environment for this session
$env:P4PORT = $config.p4_port
$env:P4USER = $config.p4_user
$env:P4CLIENT = $config.kiosk_name

# Verify p4.exe is available
$p4 = Get-Command p4.exe -ErrorAction SilentlyContinue
if (-not $p4) {
    Log "ERROR: p4.exe not on PATH. Install Helix CLI or add Program Files\Perforce to PATH."
    exit 1
}

try {
    Log "Starting P4 setup for stream $($config.p4_stream)"

    # Trust SSL fingerprint on first run (succeeds silently if already trusted)
    # Doesn't run if not using SSL, so safe to run every time
    if ($config.p4_port -like "ssl:*") {
        & p4 trust -y 2>&1 | Out-Null
    }

    # Check ticket status - suppress error action because non-zero exit is expected when no ticket
    $loginStatus = $null
    $needsLogin = $false
    try {
        $ErrorActionPreference = "Continue"
        $loginStatus = & p4 login -s 2>&1
        $needsLogin = ($LASTEXITCODE -ne 0)
    }
    finally {
        $ErrorActionPreference = "Stop"
    }

    if ($needsLogin) {
        Log "No valid ticket - performing login"

        # Try env var first - avoids storing password on kiosks
        if ($env:P4PASSWD) {
            Log "Using P4PASSWD env var for login"
            $env:P4PASSWD | & p4 login -a | Out-Null
        }
        # If P4PASSWD not set, fall back to interactive prompt. 
        #   This is expected to only be used on first setup, so password is stored as a ticket after successful login
        #   Kiosk user group tickets do not expire until revoked.
        else {
            Log "Prompting for password interactively"
            $securePass = Read-Host "Enter Perforce password for $($config.p4_user)" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
            $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            
            $plainPass | & p4 login -a | Out-Null
            $plainPass = $null  # clear from memory
        }

        if ($LASTEXITCODE -ne 0) {
            throw "p4 login failed"
        }
        Log "Login successful, ticket stored"
    }

    # Create or update workspace
    Log "Creating/updating workspace: $($config.kiosk_name)"
    $clientSpec = @"
Client: $($config.kiosk_name)
Owner:  $($config.p4_user)
Host:
Root:   $($config.build_path)
Stream: $($config.p4_stream)
Options: noallwrite noclobber nocompress unlocked nomodtime normdir
LineEnd: local
SubmitOptions: submitunchanged
"@

    $clientSpec | & p4 client -i
    if ($LASTEXITCODE -ne 0) { 
        throw "Failed to create/update workspace"
    }

    # Sync
    Log "Running p4 sync (this may take a while on first run)"
    & p4 sync
    if ($LASTEXITCODE -ne 0) {
        throw "p4 sync failed"
    }

    Log "Setup complete. Build synced to $($config.build_path)"
    exit 0
}
catch {
    Log "FAILED: $_"
    exit 1
}