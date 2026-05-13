# offhours_display.ps1
# Fullscreen image display for off-hours.
# Reads images from offhours_image_dir in config; if multiple, cycles every
# offhours_slide_seconds. If just one, shows it statically. If zero, exits.

$ErrorActionPreference = "Stop"

$config = Get-Content C:\rumi-kiosk\config.json -Raw | ConvertFrom-Json

$logFile = Join-Path $config.log_path "offhours_display.log"
function Log($msg) {
    $line = "$(Get-Date -Format o) [$env:COMPUTERNAME] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

$imageDir = if ($config.offhours_path) { $config.offhours_path }     else { "C:\rumi-kiosk\offhours" }
$slideSeconds = if ($config.offhours_slide_seconds) { [int]$config.offhours_slide_seconds } else { 10 }

if (-not (Test-Path $imageDir)) {
    Log "Image dir $imageDir not found; nothing to display"
    exit 0
}

# Gather images.
$images = @(Get-ChildItem -Path $imageDir -File -Include *.jpg, *.jpeg, *.png, *.bmp, *.gif -Recurse |
    Sort-Object Name)

if ($images.Count -eq 0) {
    Log "No images in $imageDir; nothing to display"
    exit 0
}

Log "Starting display: $($images.Count) image(s), slide=${slideSeconds}s"

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$window = New-Object System.Windows.Window
$window.WindowStyle = "None"
$window.WindowState = "Maximized"
$window.ResizeMode = "NoResize"
$window.Topmost = $true
$window.Background = [System.Windows.Media.Brushes]::Black
$window.Cursor = [System.Windows.Input.Cursors]::None

# Single Image control filled to window.
$imgControl = New-Object System.Windows.Controls.Image
$imgControl.Stretch = "Uniform"  # preserve aspect ratio, letterbox on black
$window.Content = $imgControl

# Helper: build a BitmapImage with caching off so we can swap files without leaking.
function New-Bitmap($path) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.UriSource = New-Object System.Uri($path.FullName, [System.UriKind]::Absolute)
    $bmp.EndInit()
    $bmp.Freeze()
    return $bmp
}

$script:idx = 0
$imgControl.Source = New-Bitmap $images[0]

# Only run a timer if there's more than one image.
if ($images.Count -gt 1) {
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($slideSeconds)
    $timer.Add_Tick({
        $script:idx = ($script:idx + 1) % $images.Count
        try {
            $imgControl.Source = New-Bitmap $images[$script:idx]
        } catch {
            Log "Failed to load $($images[$script:idx].FullName): $_"
        }
    })
    $timer.Start()
}

# Esc closes the window.
# Esc will be disabled on kiosks from AHK, useful when testing
$window.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
        $window.Close()
    }
})

[void]$window.ShowDialog()

Log "Display window closed"
exit 0