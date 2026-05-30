# Enable hang diagnostics on Windows.
# Run ONCE as Administrator (right-click -> Run as admin, or in elevated PowerShell).
#
# Effect:
#   1. CrashDumpEnabled = 7 (Automatic memory dump — kernel-level, good for hang analysis)
#   2. CrashOnCtrlScroll = 1 on USB (kbdhid) and PS/2 (i8042prt) keyboards
#      -> Force a bugcheck with: Right-Ctrl (held) + Scroll-Lock Scroll-Lock
#      -> Next time the laptop freezes, force a dump INSTEAD of hard-power-off.
#   3. Ensures pagefile is system-managed so dump has room.
#
# Requires reboot for CrashOnCtrlScroll to take effect.

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Must run as Administrator."
    exit 1
}

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'CrashDumpEnabled' -Value 7 -Type DWord
Write-Host "[OK] CrashDumpEnabled = 7 (automatic kernel dump)"

foreach ($svc in @('kbdhid','i8042prt')) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc\Parameters"
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    Set-ItemProperty -Path $p -Name 'CrashOnCtrlScroll' -Value 1 -Type DWord
    Write-Host "[OK] CrashOnCtrlScroll enabled on $svc"
}

Write-Host ""
Write-Host "REBOOT REQUIRED for CrashOnCtrlScroll to activate."
Write-Host "After reboot, if the laptop freezes again:"
Write-Host "  Hold RIGHT-Ctrl, press Scroll-Lock twice -> forces BSOD + dump."
Write-Host "  Dump location: C:\Windows\MEMORY.DMP"
