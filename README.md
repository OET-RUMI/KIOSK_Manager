# RUMI Kiosk

Scripts and config for deploying [RUMI](https://nautiluslive.org/) (Realtime Underwater Modeling and Immersion) Unreal Engine as kiosks.

RUMI is developed by [Ocean Exploration Trust](https://nautiluslive.org/).

## What this repo is

The contents of `C:\rumi-kiosk\scripts\` on each kiosk. P4 setup, Mesh agent install, build staging, the watchdog that runs UE, log rotation, lockdown, scheduled maintenance, and the off-hours image display.

It is not the Unreal project - that lives in Perforce. Kiosks pull cooked builds from `//RUMI/RUMI_packaged`.

## How a kiosk runs

```
run_setup.bat   (once, on first boot)
  └─ setup_p4.ps1            login + workspace + sync to build/
  └─ setup_mesh.ps1          install MeshCentral agent
  └─ stage_build.ps1         copy build/ -> runtime/
  └─ setup_startup.ps1       startup shortcut -> run_kiosk.bat
  └─ setup_scheduled_tasks.ps1   register nightly maintenance task
  └─ setup_lockdown.ps1      AHK + DisableTaskMgr policy + startup shortcut

run_kiosk.bat   (every login, via startup shortcut)
  └─ rotate_logs.ps1         age and size-based log cleanup
  └─ watchdog.ps1            launch UE, heartbeat to Kuma, relaunch on crash,
                             reboot on crash loop, show off-hours images
                             outside visitor hours

nightly_maintenance.ps1   (scheduled, default 02:00)
  └─ setup_p4.ps1            re-sync
  └─ stage_build.ps1         re-stage
  └─ Restart-Computer
```

The runtime folder is separate from the build folder so `p4 sync` can update `build/` while UE is running from `runtime/`. Staging copies one to the other on demand.

## Server side

- **Perforce** - Three streams: `RUMI_main` (dev), `release` (vetted source), `RUMI_packaged` (cooked builds, what kiosks pull).
- **MeshCentral** - Kiosks auto-enroll on first run. 
- **[Uptime Kuma](https://kiosk.wildtechnology.org/status/rumi/)** - Push-based, one monitor per kiosk. Heartbeats every 5s while UE is up; statuses include `up`/`down`/`degraded` plus a `msg=` field (`running`, `off_hours`, `ue_exited_<code>`, `crash_loop_rebooting`, etc).

## Configuration

Each kiosk has its own `C:\rumi-kiosk\config.json`. Template is `config.example.json`. The important fields:

| Field | Notes |
|---|---|
| `kiosk_name` | Canonical identity. Used as P4 workspace name and Mesh agent name. Unique per kiosk. |
| `p4_port`, `p4_user`, `p4_stream` | `rumi_kiosk` user, `//RUMI/RUMI_packaged` stream. |
| `build_path`, `runtime_path`, `log_path` | Standard layout under `C:\rumi-kiosk\`. |
| `ue_executable` | The UE exe name (e.g. `RUMI_HercSim.exe`). Found recursively under `build_path`. |
| `uptime_kuma_push_url` | Generated per-kiosk on the Kuma dashboard. |
| `max_crash_count`, `crash_window_minutes` | N crashes within the window causes kiosk to reboot. |
| `relaunch_delay_seconds` | Delay between UE exit and relaunch. |
| `nightly_reboot_time` | `HH:mm`, when the maintenance task fires. |
| `off_hours_start`, `off_hours_duration_hours` | Window when UE doesn't launch. |
| `offhours_path`, `offhours_slide_seconds` | Folder of images and per-slide duration for the off-hours display. |
| `log_retention_days`, `log_max_size_mb` | Log rotation knobs. |
| `enable_ahk_lock` | Toggle for AHK lockdown (useful for dev VMs). |

No passwords in config. Kiosks use tickets after initial setup.

## Base image

VirtualBox VM, Win 11 Pro, 8 GB RAM, 4 CPUs, 80 GB disk, EFI + TPM 2.0 + Secure Boot. Updates, sleep, notifications, widgets, search, task view, chat, and fast startup all disabled.

The MeshCentral agent is **not** installed on the base image - it stores a unique NodeId per machine, so every clone would show up as the same node. `setup_mesh.ps1` installs it on each kiosk on first run.

## Outstanding

- [x] AutoHotkey lockdown (Win key, Alt+Tab, etc.)
- [x] Auto-start watchdog (Startup shortcut)
- [x] Scheduled nightly reboot + sync
- [x] Log rotation
- [ ] In-UE heartbeat (Blueprint timer to a second Kuma push URL) to detect render hangs while the process is still alive
- [ ] Sysprep + Clonezilla imaging

## Unlocking a locked kiosk

Over MeshCentral, either:

```powershell
Remove-Item C:\rumi-kiosk\LOCK
```

(AHK polls for that sentinel every 2 seconds and exits when it disappears.)

Or just:

```powershell
Stop-Process -Name AutoHotkey64 -Force
```

Reboot or re-run the Startup shortcut to re-lock.
