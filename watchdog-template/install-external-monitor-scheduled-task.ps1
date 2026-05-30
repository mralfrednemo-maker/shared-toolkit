param(
  [Parameter(Mandatory = $true)]
  [string]$BacklogPath,

  [string]$TaskName = "",

  [int]$IntervalMinutes = 1,

  [string]$MonitorScriptPath = "",

  [string]$HiddenLauncherPath = "",

  [switch]$Uninstall,

  [switch]$WhatIfOnly
)

$ErrorActionPreference = "Stop"
$BacklogPath = (Resolve-Path -LiteralPath $BacklogPath).Path
$TemplateDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $MonitorScriptPath.Trim()) {
  $MonitorScriptPath = Join-Path $TemplateDir "external-monitor-template.ps1"
}
$MonitorScriptPath = (Resolve-Path -LiteralPath $MonitorScriptPath).Path

function Quote-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"') + '"'
}

function ConvertTo-VbsString {
  param([string]$Value)
  return '"' + ($Value -replace '"', '""') + '"'
}

$backlog = Get-Content -LiteralPath $BacklogPath -Raw | ConvertFrom-Json
if (-not $TaskName.Trim()) {
  $projectName = [string]$backlog.project_name
  if (-not $projectName.Trim()) {
    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($BacklogPath)
  }
  $TaskName = ($projectName -replace "[^\w\- ]", "").Trim()
  if (-not $TaskName) { $TaskName = "Project Watchdog External Monitor" }
  $TaskName = "$TaskName External Monitor"
}

if (-not $HiddenLauncherPath.Trim()) {
  $safeTaskName = (($TaskName -replace "[^\w\-]+", "-").Trim("-")).ToLowerInvariant()
  if (-not $safeTaskName) { $safeTaskName = "project-watchdog-external-monitor" }
  $HiddenLauncherPath = Join-Path (Split-Path -Parent $BacklogPath) "$safeTaskName-hidden-launcher.vbs"
}

if ($Uninstall) {
  if ($WhatIfOnly) {
    Write-Output "WHAT_IF_UNREGISTER_TASK $TaskName"
    exit 0
  }
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Output "UNREGISTERED_TASK $TaskName"
  exit 0
}

$arguments = @(
  "-WindowStyle", "Hidden",
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $MonitorScriptPath,
  "-BacklogPath", $BacklogPath,
  "-Once"
)
$argumentLine = ($arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
$powershellCommand = "powershell.exe $argumentLine"
$vbs = @"
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = $(ConvertTo-VbsString (Split-Path -Parent $BacklogPath))
shell.Run $(ConvertTo-VbsString $powershellCommand), 0, False
"@
$taskArguments = "//B $(Quote-ProcessArgument $HiddenLauncherPath)"

if ($WhatIfOnly) {
  [ordered]@{
    task_name = $TaskName
    execute = "wscript.exe"
    arguments = $taskArguments
    interval_minutes = $IntervalMinutes
    backlog_path = $BacklogPath
    monitor_script_path = $MonitorScriptPath
    hidden_launcher_path = $HiddenLauncherPath
    hidden_launcher_preview = $vbs
    powershell_command = $powershellCommand
  } | ConvertTo-Json -Depth 6
  exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($HiddenLauncherPath, $vbs, $utf8NoBom)

$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument $taskArguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Project watchdog external monitor for $BacklogPath" -Force | Out-Null
Write-Output "REGISTERED_TASK $TaskName"
