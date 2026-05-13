@echo off
setlocal EnableDelayedExpansion

REM get current timestamp for log file naming
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set timestamp=%%a

set LOGDIR=C:\rumi-kiosk\logs
set LOGFILE=%LOGDIR%\kiosk_%timestamp%.log

if not exist "%LOGDIR%" mkdir "%LOGDIR%"

echo ============================================================
echo  RUMI Kiosk Runtime
echo  Started: %date% %time%
echo  Log: %LOGFILE%
echo ============================================================

REM Rotate logs before starting watchdog (don't fail kiosk if rotation fails)
echo.
echo  Rotating logs...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rotate_logs.ps1"
echo.
if !ERRORLEVEL! NEQ 0 (
    echo [WARN] Log rotation exited with code !ERRORLEVEL!, continuing anyway
) else (
    echo [OK] Log rotation completed
)
echo.

echo.
echo  Watchdog is running. Press Ctrl+C to stop.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Transcript -Path '%LOGFILE%' -Append | Out-Null; & '%~dp0watchdog.ps1'; $code = $LASTEXITCODE; Stop-Transcript | Out-Null; exit $code"

set EXITCODE=!ERRORLEVEL!

echo.
echo ============================================================
if !EXITCODE! EQU 0 (
    echo  KIOSK STOPPED CLEANLY
) else (
    echo  KIOSK EXITED WITH CODE !EXITCODE!
)
echo  Finished: %date% %time%
echo  Full log: %LOGFILE%
echo ============================================================
echo.
pause