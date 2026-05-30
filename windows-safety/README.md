# Windows Safety — Hang Prevention & Diagnostics

Purpose: prevent ein-mdp-loop (and similar multi-browser pipelines) from freezing the whole laptop, and diagnose it when it does.

## Files

### `enable-hang-diagnostics.ps1`
Run ONCE as Administrator. Then reboot.

Enables:
- Automatic kernel memory dump (`CrashDumpEnabled = 7`)
- Right-Ctrl + Scroll-Lock × 2 → forced bugcheck (dumps the kernel even while frozen)

After enabling, if the laptop freezes again, do NOT hard-power-off. Press **Right-Ctrl + Scroll-Lock twice**. Windows BSODs intentionally, writes `C:\Windows\MEMORY.DMP`, and reboots. The dump can then be analyzed with WinDbg to see what deadlocked.

### `run-capped.ps1`
Wrapper that runs a command inside a Windows Job Object with hard resource caps.

Defaults:
- RAM: 48 GB (leaves 16 GB for Windows)
- CPU: 70% (leaves 30% for Windows)
- Priority: BelowNormal
- Kill-on-close: yes (Ctrl+C kills the whole tree)

Usage:
```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\chris\PROJECTS\shared\windows-safety\run-capped.ps1 -- python.exe <script> <args...>
```

Override caps:
```powershell
.\run-capped.ps1 -RamGB 32 -CpuPct 50 -- python.exe my-script.py
```

## Scope limits — honest read

| Failure mode | Caught by this? |
|---|---|
| Python or Chrome tree goes to 60GB RAM | YES — kernel kills it at 48 GB |
| CPU burn 100% across all cores | YES — capped at 70% |
| GPU/WDDM driver hang (DWM deadlock) | NO — GPU not capped by Job Objects |
| Disk queue saturation | Partial — BelowNormal priority helps; no hard I/O cap on consumer Windows |
| Handle/thread exhaustion | NO — kernel object limits are system-wide |

For the failure modes that Job Objects can't cover (GPU, disk I/O), the next step is running ein-mdp inside WSL (systemd cgroups cover all three) or on a separate machine.
