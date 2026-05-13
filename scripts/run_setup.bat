@echo off
REM Self-elevate to admin if not already
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

setlocal EnableDelayedExpansion

REM get current timestamp for log file naming
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set timestamp=%%a

set LOGDIR=C:\rumi-kiosk\logs
set LOGFILE=%LOGDIR%\setup_%timestamp%.log

if not exist "%LOGDIR%" mkdir "%LOGDIR%"

echo ============================================================
echo  RUMI Kiosk Setup
echo  Started: %date% %time%
echo  Log: %LOGFILE%
echo ============================================================
echo.

REM list scripts that need to run in order
set SCRIPTS=setup_p4.ps1 setup_mesh.ps1 stage_build.ps1 setup_autologon.ps1 setup_startup.ps1

set FAILED=0

for %%S in (%SCRIPTS%) do (
    echo ------------------------------------------------------------
    echo  Running: %%S
    echo ------------------------------------------------------------
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Transcript -Path '%LOGFILE%' -Append | Out-Null; & '%~dp0%%S'; $code = $LASTEXITCODE; Stop-Transcript | Out-Null; exit $code"

    if !ERRORLEVEL! NEQ 0 (
        echo.
        echo [FAIL] %%S exited with code !ERRORLEVEL!
        set FAILED=1
        goto :done
    ) else (
        echo.
        echo [OK] %%S completed
    )
    echo.
)

:done
echo ============================================================
if %FAILED% EQU 1 (
    echo  SETUP FAILED - see log above
) else (
    echo  SETUP COMPLETE
)
echo  Finished: %date% %time%
echo  Full log: %LOGFILE%
echo ============================================================
echo.
pause