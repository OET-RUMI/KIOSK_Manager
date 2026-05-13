; lockdown.ahk
; Kiosk keyboard lockdown for RUMI exhibits.
; AutoHotkey v2.
;
; ============================================================
;  HOW TO UNLOCK (for remote admin via MeshCentral)
; ============================================================
;
;  Delete:  C:\rumi-kiosk\LOCK
;
;  The script polls for that file every 2 seconds and exits cleanly
;  when it's gone. Reboot or re-run the Startup shortcut to re-lock
;
;  OR
;
;  Stop-Process -Name AutoHotkey64 -Force
;
; ============================================================

#SingleInstance Force
#Warn All, Off
Persistent

lockFile := "C:\rumi-kiosk\LOCK"
logFile := "C:\rumi-kiosk\logs\lockdown.log"
config   := "C:\rumi-kiosk\config.json"

; Make sure log dir exists (watchdog usually creates it, but be safe)
try DirCreate("C:\rumi-kiosk\logs")

Log(msg) {
    global logFile
    line := FormatTime(, "yyyy-MM-ddTHH:mm:ss") . " [" . A_ComputerName . "] " . msg
    try FileAppend(line . "`n", logFile)
}

; Check enable_ahk_lock in config.json
enabled := true
try {
    configText := FileRead(config)
    if RegExMatch(configText, 'i)"enable_ahk_lock"\s*:\s*(true|false)', &m) {
        enabled := (m[1] = "true")
    }
}
if !enabled {
    Log("enable_ahk_lock=false in config - exiting without applying lockdown")
    ExitApp(0)
}

; Create the LOCK sentinel if it's not there. Deleting this file is the
; unlock signal, so the script needs to put it in place on startup -
; otherwise a reboot after an unlock would leave the kiosk unlocked.
if !FileExist(lockFile) {
    try FileAppend("", lockFile)
}

Log("Lockdown started. PID: " . ProcessExist())
Log("Unlock: delete " . lockFile . " | Stop-Process AutoHotkey64")

;  Sentinel file watcher
; Poll for the lock file. Exit when it disappears. SetTimer is non-blocking
; so hotkeys still fire.
CheckLockFile() {
    global lockFile
    if !FileExist(lockFile) {
        Log("Lock file removed - exiting")
        ExitApp(0)
    }
}
SetTimer(CheckLockFile, 2000)

; Key blocks 
; Single-key blocks
LWin::return
RWin::return
AppsKey::return

; Alt combos
!Tab::return
!Esc::return
!F4::return 
!Space::return

; Ctrl combos
^Esc::return
; NOTE: ^+Esc (Ctrl+Shift+Esc, Task Manager) is NOT blockable here.
; Handled by registry policy in setup_lockdown.ps1.

; Win combos
#a::return
#d::return
#e::return
#l::return 
#r::return
#x::return
#Tab::return

; Browser/media keys some USB keyboards send
Browser_Home::return
Browser_Back::return
Browser_Forward::return
Browser_Refresh::return
Browser_Search::return
Launch_App1::return
Launch_App2::return
Launch_Mail::return