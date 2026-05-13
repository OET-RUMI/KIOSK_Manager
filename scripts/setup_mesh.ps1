# setup_mesh.ps1
# Installs MeshCentral agent if not already present.

# Require admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "mesh_setup.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# check if mesh agent service already exists (if so, assume already installed correctly and just start it if not running)
$service = Get-Service -Name "Mesh Agent" -ErrorAction SilentlyContinue
if ($service) {
    Log "Mesh Agent already installed (status: $($service.Status))"
    if ($service.Status -ne "Running") {
        Start-Service "Mesh Agent"
    }
    exit 0
}

$installer = "C:\rumi-kiosk\bin\meshagent64.exe"
if (-not (Test-Path $installer)) {
    Log "FATAL: Agent installer not found at $installer"
    exit 1
}

# fetch agent name from config (default to hostname if not set)
$agentName = if ($config.kiosk_name -and $config.kiosk_name.Trim()) {
    $config.kiosk_name.Trim()
} else {
    $env:COMPUTERNAME
}

Log "Installing Mesh Agent"
$proc = Start-Process -FilePath $installer -ArgumentList "-fullinstall --agentName=`"$agentName`"" -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Log "Installer exited with code $($proc.ExitCode)"
    exit 1
}

# wait a few seconds for service to register, then check it exists and start it
Start-Sleep -Seconds 3
$service = Get-Service -Name "Mesh Agent" -ErrorAction SilentlyContinue
if (-not $service) {
    Log "FATAL: Installer ran but Mesh Agent service not found"
    exit 1
}

Log "Mesh Agent installed."
exit 0