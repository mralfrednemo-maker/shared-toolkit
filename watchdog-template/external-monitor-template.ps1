param(
  [Parameter(Mandatory = $true)]
  [string]$BacklogPath,

  [int]$OverridePollSeconds = 0,

  [int]$MaxIterations = 0,

  [switch]$Once
)

$ErrorActionPreference = "Continue"
$BacklogPath = (Resolve-Path -LiteralPath $BacklogPath).Path
$BacklogDir = Split-Path -Parent $BacklogPath
$TemplateDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function ConvertTo-Hashtable {
  param([object]$InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string] -and $InputObject -isnot [pscustomobject]) {
    $array = @()
    foreach ($item in $InputObject) {
      $array += ConvertTo-Hashtable $item
    }
    return ,$array
  }
  if ($InputObject -is [pscustomobject]) {
    $hash = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
      $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
    }
    return $hash
  }
  return $InputObject
}

function Get-ConfigValue {
  param(
    [hashtable]$Hash,
    [string]$Key,
    [object]$Default
  )
  if ($Hash -and $Hash.ContainsKey($Key) -and $null -ne $Hash[$Key]) {
    return $Hash[$Key]
  }
  return $Default
}

function Resolve-MonitorPath {
  param(
    [string]$Path,
    [string]$Default
  )
  $value = $Path
  if (-not $value.Trim()) { $value = $Default }
  if (-not $value.Trim()) { return "" }
  if ([System.IO.Path]::IsPathRooted($value)) { return $value }
  return (Join-Path $BacklogDir $value)
}

function Quote-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"') + '"'
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    return ConvertTo-Hashtable ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Write-JsonFile {
  param([string]$Path, [object]$Data)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, ($Data | ConvertTo-Json -Depth 20), $utf8NoBom)
}

function Test-ProcessAlive {
  param([int]$ProcessId)
  if ($ProcessId -le 0) { return $false }
  try {
    $null = Get-Process -Id $ProcessId -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}

function Get-StringArray {
  param(
    [object]$Value,
    [string[]]$Default
  )
  if ($null -eq $Value) { return $Default }
  if ($Value -is [string]) { return @([string]$Value) }
  $result = @()
  foreach ($item in @($Value)) {
    if ($null -ne $item -and [string]$item) {
      $result += [string]$item
    }
  }
  if ($result.Count -eq 0) { return $Default }
  return $result
}

function Read-Backlog {
  return ConvertTo-Hashtable ((Get-Content -LiteralPath $BacklogPath -Raw) | ConvertFrom-Json)
}

function Get-EventLogPath {
  param([hashtable]$Config)
  return Resolve-MonitorPath ([string](Get-ConfigValue $Config "event_log" "external-monitor-events.jsonl")) "external-monitor-events.jsonl"
}

function Write-Event {
  param(
    [hashtable]$Config,
    [hashtable]$Event
  )
  $Event["ts"] = [DateTimeOffset]::UtcNow.ToString("o")
  Add-Content -LiteralPath (Get-EventLogPath $Config) -Value ($Event | ConvertTo-Json -Compress -Depth 12)
}

function Get-HeartbeatStatus {
  param(
    [string]$HeartbeatPath,
    [int]$StaleAfterSeconds
  )
  if (-not $HeartbeatPath.Trim()) {
    return @{ status = "disabled"; age_seconds = $null; reason = "heartbeat path not configured" }
  }
  if (-not (Test-Path -LiteralPath $HeartbeatPath)) {
    return @{ status = "missing"; age_seconds = $null; reason = "heartbeat file missing" }
  }
  $heartbeat = Read-JsonFile $HeartbeatPath
  if ($null -eq $heartbeat) {
    return @{ status = "invalid"; age_seconds = $null; reason = "heartbeat JSON invalid" }
  }
  $updatedAtText = [string](Get-ConfigValue $heartbeat "updated_at" "")
  if (-not $updatedAtText.Trim()) {
    return @{ status = "invalid"; age_seconds = $null; reason = "heartbeat updated_at missing" }
  }
  try {
    $updatedAt = [DateTimeOffset]::Parse($updatedAtText)
  } catch {
    return @{ status = "invalid"; age_seconds = $null; reason = "heartbeat updated_at invalid" }
  }
  $ageSeconds = [int]([DateTimeOffset]::UtcNow - $updatedAt).TotalSeconds
  if ([bool](Get-ConfigValue $heartbeat "blocked" $false)) {
    $blockedReason = [string](Get-ConfigValue $heartbeat "blocked_reason" "heartbeat blocked")
    return @{ status = "blocked"; age_seconds = $ageSeconds; reason = $blockedReason }
  }
  if ($ageSeconds -gt $StaleAfterSeconds) {
    return @{ status = "stale"; age_seconds = $ageSeconds; reason = "heartbeat age $ageSeconds seconds exceeds $StaleAfterSeconds seconds" }
  }
  return @{ status = "fresh"; age_seconds = $ageSeconds; reason = "heartbeat fresh" }
}

function Start-Supervisor {
  param(
    [hashtable]$Config,
    [string]$SupervisorScript
  )
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $SupervisorScript,
    "-BacklogPath", $BacklogPath
  )
  return Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList (($args | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " ") -PassThru
}

function Start-WakeCommand {
  param(
    [hashtable]$Config,
    [hashtable]$Backlog,
    [string]$WakeCommand
  )
  $projectRoot = [string](Get-ConfigValue $Backlog "project_root" $BacklogDir)
  $runnerPath = Resolve-MonitorPath ([string](Get-ConfigValue $Config "wake_runner_file" "external-monitor-wake-runner.ps1")) "external-monitor-wake-runner.ps1"
  $wakeLogPath = Resolve-MonitorPath ([string](Get-ConfigValue $Config "wake_log_file" "external-monitor-wake.log")) "external-monitor-wake.log"
  $wakeStatePath = Resolve-MonitorPath ([string](Get-ConfigValue $Config "wake_state_file" "external-monitor-wake-state.json")) "external-monitor-wake-state.json"
  $runner = @"
`$ErrorActionPreference = "Continue"
function Write-JsonFile {
  param([string]`$Path, [object]`$Data)
  `$utf8NoBom = New-Object System.Text.UTF8Encoding(`$false)
  [System.IO.File]::WriteAllText(`$Path, (`$Data | ConvertTo-Json -Depth 20), `$utf8NoBom)
}
`$startedAt = [DateTimeOffset]::UtcNow.ToString("o")
Write-JsonFile $(Quote-ProcessArgument $wakeStatePath) ([ordered]@{
  schema = "watchdog-external-monitor-wake-state-v1"
  status = "started"
  started_at = `$startedAt
  backlog_path = $(Quote-ProcessArgument $BacklogPath)
  log_path = $(Quote-ProcessArgument $wakeLogPath)
})
"START `$startedAt" | Out-File -LiteralPath $(Quote-ProcessArgument $wakeLogPath) -Encoding utf8 -Append
Set-Location -LiteralPath $(Quote-ProcessArgument $projectRoot)
try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $(Quote-ProcessArgument $WakeCommand) *>> $(Quote-ProcessArgument $wakeLogPath)
  `$exitCode = `$LASTEXITCODE
  if (`$null -eq `$exitCode) { `$exitCode = 0 }
} catch {
  `$exitCode = 1
  "ERROR `$(`$_.Exception.Message)" | Out-File -LiteralPath $(Quote-ProcessArgument $wakeLogPath) -Encoding utf8 -Append
}
`$finishedAt = [DateTimeOffset]::UtcNow.ToString("o")
"EXIT `$finishedAt code=`$exitCode" | Out-File -LiteralPath $(Quote-ProcessArgument $wakeLogPath) -Encoding utf8 -Append
Write-JsonFile $(Quote-ProcessArgument $wakeStatePath) ([ordered]@{
  schema = "watchdog-external-monitor-wake-state-v1"
  status = "exited"
  started_at = `$startedAt
  finished_at = `$finishedAt
  exit_code = `$exitCode
  backlog_path = $(Quote-ProcessArgument $BacklogPath)
  log_path = $(Quote-ProcessArgument $wakeLogPath)
})
exit `$exitCode
"@
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($runnerPath, $runner, $utf8NoBom)
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $runnerPath
  )
  $process = Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList (($args | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " ") -PassThru
  return @{ process = $process; runner_path = $runnerPath; log_path = $wakeLogPath; state_path = $wakeStatePath }
}

function Invoke-MonitorIteration {
  $backlog = Read-Backlog
  $config = Get-ConfigValue $backlog "external_monitor" @{}
  if (-not [bool](Get-ConfigValue $config "enabled" $true)) {
    $config["enabled"] = $false
    $statePath = Resolve-MonitorPath ([string](Get-ConfigValue $config "state_file" "external-monitor-state.json")) "external-monitor-state.json"
    $state = [ordered]@{
      schema = "watchdog-external-monitor-state-v1"
      checked_at = [DateTimeOffset]::UtcNow.ToString("o")
      backlog_path = $BacklogPath
      backlog_status = [string](Get-ConfigValue $backlog "status" "running")
      terminal = $false
      monitor_enabled = $false
      supervisor_alive = $false
      supervisor_started = $false
      controller_heartbeat_status = "disabled"
      controller_wake_started = $false
    }
    Write-JsonFile $statePath $state
    Write-Event $config @{ event = "external_monitor_disabled"; backlog_status = $state.backlog_status }
    Write-Output ($state | ConvertTo-Json -Compress -Depth 12)
    return
  }

  $statePath = Resolve-MonitorPath ([string](Get-ConfigValue $config "state_file" "external-monitor-state.json")) "external-monitor-state.json"
  $lockPath = "$BacklogPath.lock.json"
  $terminalStatuses = (Get-StringArray (Get-ConfigValue $config "terminal_statuses" @()) @("complete", "blocked", "skipped")) | ForEach-Object { $_.ToLowerInvariant() }
  $backlogStatus = ([string](Get-ConfigValue $backlog "status" "running")).ToLowerInvariant()
  $terminal = $backlogStatus -in $terminalStatuses

  $supervisorPid = 0
  $supervisorAlive = $false
  $lock = Read-JsonFile $lockPath
  if ($null -ne $lock) {
    $supervisorPid = [int](Get-ConfigValue $lock "pid" 0)
    $supervisorAlive = Test-ProcessAlive $supervisorPid
  }

  $supervisorStarted = $false
  $supervisorStartedPid = 0
  if (-not $terminal -and -not $supervisorAlive) {
    $supervisorScript = Resolve-MonitorPath ([string](Get-ConfigValue $config "supervisor_script" "")) (Join-Path $TemplateDir "supervisor-template.ps1")
    if (Test-Path -LiteralPath $supervisorScript) {
      $process = Start-Supervisor -Config $config -SupervisorScript $supervisorScript
      $supervisorStarted = $true
      $supervisorStartedPid = $process.Id
      Write-Event $config @{ event = "external_monitor_started_supervisor"; pid = $process.Id; supervisor_script = $supervisorScript; backlog_path = $BacklogPath }
    } else {
      Write-Event $config @{ event = "external_monitor_supervisor_missing"; supervisor_script = $supervisorScript; backlog_path = $BacklogPath }
    }
  }

  $heartbeatPath = Resolve-MonitorPath ([string](Get-ConfigValue $config "controller_heartbeat_file" "")) ""
  $heartbeatStaleAfter = [int](Get-ConfigValue $config "controller_heartbeat_stale_seconds" 420)
  $heartbeat = Get-HeartbeatStatus -HeartbeatPath $heartbeatPath -StaleAfterSeconds $heartbeatStaleAfter

  $wakeStarted = $false
  $wakePid = 0
  $wakeCommand = [string](Get-ConfigValue $config "controller_wake_command" "")
  $cooldownSeconds = [int](Get-ConfigValue $config "wake_cooldown_seconds" 300)
  $priorState = Read-JsonFile $statePath
  $cooldownActive = $false
  if ($null -ne $priorState -and [string](Get-ConfigValue $priorState "last_controller_wake_at" "")) {
    try {
      $lastWake = [DateTimeOffset]::Parse([string](Get-ConfigValue $priorState "last_controller_wake_at" ""))
      if (([DateTimeOffset]::UtcNow - $lastWake).TotalSeconds -lt $cooldownSeconds) {
        $cooldownActive = $true
      }
    } catch {}
  }

  if (-not $terminal -and $heartbeat.status -in @("missing", "invalid", "stale", "blocked") -and $wakeCommand.Trim() -and -not $cooldownActive) {
    $wake = Start-WakeCommand -Config $config -Backlog $backlog -WakeCommand $wakeCommand
    $wakeProcess = $wake.process
    $wakeStarted = $true
    $wakePid = $wakeProcess.Id
    Write-Event $config @{ event = "external_monitor_started_controller_wake"; pid = $wakePid; heartbeat_status = $heartbeat.status; heartbeat_reason = $heartbeat.reason; wake_runner_path = $wake.runner_path; wake_log_path = $wake.log_path; wake_state_path = $wake.state_path }
  } elseif ($heartbeat.status -in @("missing", "invalid", "stale", "blocked")) {
    Write-Event $config @{ event = "external_monitor_controller_action_required"; heartbeat_status = $heartbeat.status; heartbeat_reason = $heartbeat.reason; cooldown_active = $cooldownActive; wake_command_present = [bool]$wakeCommand.Trim() }
  }

  $state = [ordered]@{
    schema = "watchdog-external-monitor-state-v1"
    checked_at = [DateTimeOffset]::UtcNow.ToString("o")
    backlog_path = $BacklogPath
    backlog_status = $backlogStatus
    terminal = $terminal
    supervisor_lock_path = $lockPath
    supervisor_pid = $supervisorPid
    supervisor_alive = $supervisorAlive
    supervisor_started = $supervisorStarted
    supervisor_started_pid = $supervisorStartedPid
    controller_heartbeat_file = $heartbeatPath
    controller_heartbeat_status = $heartbeat.status
    controller_heartbeat_age_seconds = $heartbeat.age_seconds
    controller_heartbeat_reason = $heartbeat.reason
    controller_wake_started = $wakeStarted
    controller_wake_pid = $wakePid
  }
  if ($wakeStarted) {
    $state["controller_wake_runner_path"] = $wake.runner_path
    $state["controller_wake_log_path"] = $wake.log_path
    $state["controller_wake_state_path"] = $wake.state_path
    $state["last_controller_wake_at"] = [DateTimeOffset]::UtcNow.ToString("o")
  } elseif ($null -ne $priorState -and [string](Get-ConfigValue $priorState "last_controller_wake_at" "")) {
    $state["last_controller_wake_at"] = [string](Get-ConfigValue $priorState "last_controller_wake_at" "")
  }

  Write-JsonFile $statePath $state
  Write-Event $config @{ event = "external_monitor_poll"; backlog_status = $backlogStatus; terminal = $terminal; supervisor_alive = $supervisorAlive; supervisor_started = $supervisorStarted; controller_heartbeat_status = $heartbeat.status; controller_wake_started = $wakeStarted }
  Write-Output ($state | ConvertTo-Json -Compress -Depth 12)
}

$iteration = 0
while ($true) {
  $iteration += 1
  Invoke-MonitorIteration
  if ($Once -or ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations)) {
    break
  }
  $backlog = Read-Backlog
  $config = Get-ConfigValue $backlog "external_monitor" @{}
  $pollSeconds = if ($OverridePollSeconds -gt 0) { $OverridePollSeconds } else { [int](Get-ConfigValue $config "poll_seconds" 300) }
  Start-Sleep -Seconds ([Math]::Max(10, $pollSeconds))
}
