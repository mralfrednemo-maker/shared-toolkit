# Agora Room Supervision Example

Agora already has project-specific watchdogs:

- `C:\Users\chris\PROJECTS\agora\scripts\watch_code_audit_loop.ps1`
- `C:\Users\chris\PROJECTS\agora\scripts\agora_watchdog.ps1`
- `C:\Users\chris\PROJECTS\agora\scripts\agora_watchdog_cadence_gate.ps1`
- `C:\Users\chris\PROJECTS\agora\scripts\agora_recovery_agent.ps1`

Use the generic template when building the same pattern into another project.

These examples use the quoted-launch pattern because room ids, paths, and subjects often contain characters that must stay bound to a single parameter.

```powershell
function Quote-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"') + '"'
}
```

## Current Agora Pattern

Dense monitor:

```powershell
$denseArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass',
  '-File','C:\Users\chris\PROJECTS\agora\scripts\watch_code_audit_loop.ps1',
  '-RoomId','<ROOM_ID>',
  '-IntervalSeconds','300',
  '-Iterations','96',
  '-Gateway','http://127.0.0.1:8890'
)
Start-Process -WindowStyle Hidden -FilePath powershell.exe -ArgumentList (($denseArgs | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
```

Action-required watchdog:

```powershell
$watchdogArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass',
  '-File','C:\Users\chris\PROJECTS\agora\scripts\agora_watchdog.ps1',
  '-RoomId','<ROOM_ID>',
  '-Gateway','http://127.0.0.1:8890',
  '-IntervalSeconds','300',
  '-StallMinutes','45',
  '-RepeatAlertMinutes','120',
  '-TelegramMode','ActionRequired',
  '-RecoveryScript','C:\Users\chris\PROJECTS\agora\scripts\agora_recovery_agent.ps1'
)
Start-Process -WindowStyle Hidden -FilePath powershell.exe -ArgumentList (($watchdogArgs | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
```

Cadence gate:

```powershell
$gateArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass',
  '-File','C:\Users\chris\PROJECTS\agora\scripts\agora_watchdog_cadence_gate.ps1',
  '-RoomId','<ROOM_ID>',
  '-Gateway','http://127.0.0.1:8890',
  '-TargetRepo','C:\path\to\target\repo',
  '-DenseIntervalSeconds','300',
  '-RelaxedIntervalSeconds','900',
  '-CheckIntervalSeconds','300',
  '-Iterations','96',
  '-RecoveryScript','C:\Users\chris\PROJECTS\agora\scripts\agora_recovery_agent.ps1',
  '-TelegramMode','ActionRequired'
)
Start-Process -WindowStyle Hidden -FilePath powershell.exe -ArgumentList (($gateArgs | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
```

## What To Copy To Other Projects

Copy the generic template:

- `C:\Users\chris\PROJECTS\shared\watchdog-template\backlog-template.json`
- `C:\Users\chris\PROJECTS\shared\watchdog-template\supervisor-template.ps1`

Then replace the item commands with project-specific commands:

- `run_command` starts or resumes work;
- `check_command` proves the item is done;
- `recover_command` handles safe retry;
- `final_validation_command` proves the whole backlog is complete.

## Minimal Ask To Another Agent

> Use the durable unattended backlog supervisor template in `C:\Users\chris\PROJECTS\shared\watchdog-template`. Build a project-specific backlog JSON and supervisor launch command. The supervisor must persist state to disk, run outside the chat, alert only on action-required blockers, and stop only when every required backlog item is done and final validation passes.
