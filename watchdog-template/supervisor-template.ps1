param(
  [Parameter(Mandatory = $true)]
  [string]$BacklogPath,

  [int]$OverrideIntervalSeconds = 0,

  [int]$MaxIterations = 0,

  [switch]$Once
)

$ErrorActionPreference = "Continue"
$BacklogPath = (Resolve-Path -LiteralPath $BacklogPath).Path
$BacklogDir = Split-Path -Parent $BacklogPath
$LockPath = "$BacklogPath.lock.json"

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

if (Test-Path -LiteralPath $LockPath) {
  try {
    $existingLock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
    $existingPid = [int]$existingLock.pid
    if ($existingPid -ne $PID -and (Test-ProcessAlive $existingPid)) {
      Write-Host "Supervisor already running for $BacklogPath as PID $existingPid"
      exit 2
    }
  } catch {}
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $LockPath,
  (@{ pid = $PID; backlog_path = $BacklogPath; started_at = [DateTimeOffset]::UtcNow.ToString("o") } | ConvertTo-Json -Depth 4),
  $utf8NoBom
)

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

function Read-Backlog {
  $raw = Get-Content -LiteralPath $BacklogPath -Raw
  return ConvertTo-Hashtable ($raw | ConvertFrom-Json)
}

function Write-Backlog {
  param([hashtable]$Backlog)
  $Backlog["updated_at"] = [DateTimeOffset]::UtcNow.ToString("o")
  $json = $Backlog | ConvertTo-Json -Depth 20
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($BacklogPath, $json, $utf8NoBom)
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

function Get-EventLogPath {
  param([hashtable]$Backlog)
  $supervisor = Get-ConfigValue $Backlog "supervisor" @{}
  $name = Get-ConfigValue $supervisor "event_log" "supervisor-events.jsonl"
  if ([System.IO.Path]::IsPathRooted([string]$name)) { return [string]$name }
  return (Join-Path $BacklogDir ([string]$name))
}

function Write-Event {
  param(
    [hashtable]$Backlog,
    [hashtable]$Event
  )
  $Event["ts"] = [DateTimeOffset]::UtcNow.ToString("o")
  Add-Content -LiteralPath (Get-EventLogPath $Backlog) -Value ($Event | ConvertTo-Json -Compress -Depth 12)
}

function Send-Alert {
  param(
    [hashtable]$Backlog,
    [string]$Severity,
    [string]$Message,
    [string]$Key
  )
  $notification = Get-ConfigValue $Backlog "notification" @{}
  $mode = [string](Get-ConfigValue $notification "mode" "ActionRequired")
  $bridge = [string](Get-ConfigValue $notification "telegram_bridge" "")
  $repeatMinutes = [int](Get-ConfigValue $notification "repeat_alert_minutes" 120)
  $actionRequired = @("action_required", "critical")

  if (-not $bridge.Trim() -or $mode -eq "None" -or ($mode -eq "ActionRequired" -and $Severity -notin $actionRequired)) {
    Write-Event $Backlog @{ event = "alert_suppressed"; severity = $Severity; key = $Key; mode = $mode; message = $Message }
    return
  }

  $supervisor = Get-ConfigValue $Backlog "supervisor" @{}
  $stateFile = [string](Get-ConfigValue $supervisor "state_file" "supervisor-state.json")
  $statePath = if ([System.IO.Path]::IsPathRooted($stateFile)) { $stateFile } else { Join-Path $BacklogDir $stateFile }
  $state = @{}
  if (Test-Path -LiteralPath $statePath) {
    try {
      $obj = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      foreach ($prop in $obj.PSObject.Properties) { $state[$prop.Name] = $prop.Value }
    } catch {}
  }

  $now = [DateTimeOffset]::UtcNow
  if ([string](Get-ConfigValue $state "last_alert_key" "") -eq $Key) {
    $last = [string](Get-ConfigValue $state "last_alert_at" "")
    if ($last) {
      try {
        if (($now - [DateTimeOffset]::Parse($last)).TotalMinutes -lt $repeatMinutes) {
          Write-Event $Backlog @{ event = "alert_deduped"; severity = $Severity; key = $Key; message = $Message }
          return
        }
      } catch {}
    }
  }

  try {
    $text = "[Supervisor][$Severity] $($Backlog.project_name): $Message"
    Invoke-RestMethod -Uri $bridge -Method Post -ContentType "application/json" -Body (@{ text = $text } | ConvertTo-Json) -TimeoutSec 10 | Out-Null
    $state["last_alert_key"] = $Key
    $state["last_alert_at"] = $now.ToString("o")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 8), $utf8NoBom)
    Write-Event $Backlog @{ event = "alert_sent"; severity = $Severity; key = $Key; message = $Message }
  } catch {
    Write-Event $Backlog @{ event = "alert_failed"; severity = $Severity; key = $Key; error = $_.Exception.Message; message = $Message }
  }
}

function Send-ProgressUpdate {
  param([hashtable]$Backlog)
  $progress = Get-ConfigValue $Backlog "progress_updates" @{}
  if (-not [bool](Get-ConfigValue $progress "enabled" $false)) {
    return
  }

  $notification = Get-ConfigValue $Backlog "notification" @{}
  $bridge = [string](Get-ConfigValue $notification "telegram_bridge" "")
  if (-not $bridge.Trim()) {
    Write-Event $Backlog @{ event = "progress_suppressed"; reason = "missing_bridge" }
    return
  }

  $intervalSeconds = [int](Get-ConfigValue $progress "interval_seconds" 900)
  $stateFile = [string](Get-ConfigValue $progress "state_file" "progress-state.json")
  $statePath = if ([System.IO.Path]::IsPathRooted($stateFile)) { $stateFile } else { Join-Path $BacklogDir $stateFile }
  $summaryCommand = [string](Get-ConfigValue $progress "summary_command" "")
  if (-not $summaryCommand.Trim()) {
    Write-Event $Backlog @{ event = "progress_suppressed"; reason = "missing_summary_command" }
    return
  }

  $state = @{}
  if (Test-Path -LiteralPath $statePath) {
    try {
      $obj = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      foreach ($prop in $obj.PSObject.Properties) { $state[$prop.Name] = $prop.Value }
    } catch {}
  }

  $now = [DateTimeOffset]::UtcNow
  $lastSentAt = [string](Get-ConfigValue $state "last_progress_at" "")
  if ($lastSentAt) {
    try {
      if (($now - [DateTimeOffset]::Parse($lastSentAt)).TotalSeconds -lt $intervalSeconds) {
        return
      }
    } catch {}
  }

  $result = Invoke-BacklogCommand -Backlog $Backlog -Command $summaryCommand -Kind "progress" -ItemId "PROGRESS"
  if ($result.exit_code -ne 0) {
    Write-Event $Backlog @{ event = "progress_failed"; output = ([string]$result.output) }
    return
  }

  $text = ([string]$result.output).Trim()
  if (-not $text) {
    Write-Event $Backlog @{ event = "progress_suppressed"; reason = "empty_text" }
    return
  }

  try {
    Invoke-RestMethod -Uri $bridge -Method Post -ContentType "application/json" -Body (@{ text = $text } | ConvertTo-Json) -TimeoutSec 10 | Out-Null
    $state["last_progress_at"] = $now.ToString("o")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 8), $utf8NoBom)
    Write-Event $Backlog @{ event = "progress_sent"; text = $text }
  } catch {
    Write-Event $Backlog @{ event = "progress_failed"; error = $_.Exception.Message; text = $text }
  }
}

function Invoke-BacklogCommand {
  param(
    [hashtable]$Backlog,
    [string]$Command,
    [string]$Kind,
    [string]$ItemId
  )
  if (-not $Command.Trim()) {
    return @{ exit_code = 0; output = ""; skipped = $true }
  }
  $projectRoot = [string](Get-ConfigValue $Backlog "project_root" $BacklogDir)
  $started = [DateTimeOffset]::UtcNow
  try {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '$projectRoot'; $Command" 2>&1
    $exit = $LASTEXITCODE
    if ($null -eq $exit) { $exit = 0 }
    return @{
      exit_code = [int]$exit
      output = (($output | Out-String).Trim())
      elapsed_ms = [int](([DateTimeOffset]::UtcNow - $started).TotalMilliseconds)
      skipped = $false
    }
  } catch {
    return @{
      exit_code = 1
      output = $_.Exception.Message
      elapsed_ms = [int](([DateTimeOffset]::UtcNow - $started).TotalMilliseconds)
      skipped = $false
    }
  }
}

function Test-ItemDone {
  param(
    [hashtable]$Backlog,
    [hashtable]$Item
  )
  $checkCommand = [string](Get-ConfigValue $Item "check_command" "")
  $result = Invoke-BacklogCommand -Backlog $Backlog -Command $checkCommand -Kind "check" -ItemId ([string]$Item.id)
  $Item["last_checked_at"] = [DateTimeOffset]::UtcNow.ToString("o")
  if ($result.exit_code -eq 0) {
    $Item["status"] = "done"
    $Item["last_finished_at"] = [DateTimeOffset]::UtcNow.ToString("o")
    $evidence = @($Item["evidence"])
    $evidence += @{
      ts = [DateTimeOffset]::UtcNow.ToString("o")
      type = "check_passed"
      command = $checkCommand
      output = ([string]$result.output)
    }
    $Item["evidence"] = $evidence
    return $true
  }
  $Item["last_error"] = ([string]$result.output)
  return $false
}

function Get-BacklogItemById {
  param(
    [hashtable]$Backlog,
    [string]$ItemId
  )
  foreach ($candidate in @($Backlog.items)) {
    if ([string]$candidate.id -eq $ItemId) {
      return $candidate
    }
  }
  return $null
}

function Get-MissingDependencies {
  param(
    [hashtable]$Backlog,
    [hashtable]$Item
  )
  $missing = @()
  $dependencies = @($Item["depends_on"])
  foreach ($dependencyId in $dependencies) {
    $dependencyId = [string]$dependencyId
    if (-not $dependencyId.Trim()) { continue }
    $dependency = Get-BacklogItemById -Backlog $Backlog -ItemId $dependencyId
    if ($null -eq $dependency -or [string]$dependency.status -notin @("done", "skipped")) {
      $missing += $dependencyId
    }
  }
  return $missing
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

function Get-NestedValue {
  param(
    [object]$Root,
    [object]$Path
  )
  $current = $Root
  foreach ($partObject in @($Path)) {
    $part = [string]$partObject
    if ($null -eq $current -or -not $part.Trim()) {
      return $null
    }
    if ($current -is [hashtable]) {
      if (-not $current.ContainsKey($part)) { return $null }
      $current = $current[$part]
      continue
    }
    if ($current -is [pscustomobject]) {
      $property = $current.PSObject.Properties[$part]
      if ($null -eq $property) { return $null }
      $current = $property.Value
      continue
    }
    return $null
  }
  return $current
}

function Get-StateFilePath {
  param(
    [hashtable]$Tracking
  )
  $stateFile = [string](Get-ConfigValue $Tracking "state_file" "")
  if (-not $stateFile.Trim()) { return "" }
  if ([System.IO.Path]::IsPathRooted($stateFile)) { return $stateFile }
  return (Join-Path $BacklogDir $stateFile)
}

function Invoke-ExternalStateTracking {
  param(
    [hashtable]$Backlog,
    [hashtable]$Item
  )
  $tracking = Get-ConfigValue $Item "state_tracking" @{}
  if (-not [bool](Get-ConfigValue $tracking "enabled" $false)) {
    return @{ handled = $false; action = "disabled" }
  }

  $statePath = Get-StateFilePath $tracking
  if (-not $statePath.Trim() -or -not (Test-Path -LiteralPath $statePath)) {
    Write-Event $Backlog @{ event = "external_state_missing"; item_id = $Item.id; state_file = $statePath }
    return @{ handled = $false; action = "missing" }
  }

  try {
    $state = ConvertTo-Hashtable ((Get-Content -LiteralPath $statePath -Raw) | ConvertFrom-Json)
  } catch {
    Write-Event $Backlog @{ event = "external_state_invalid"; item_id = $Item.id; state_file = $statePath; error = $_.Exception.Message }
    return @{ handled = $false; action = "invalid" }
  }

  $statusPath = Get-ConfigValue $tracking "status_path" @("items", [string]$Item.id, "status")
  $status = [string](Get-NestedValue -Root $state -Path $statusPath)
  if (-not $status.Trim()) {
    Write-Event $Backlog @{ event = "external_state_no_status"; item_id = $Item.id; state_file = $statePath }
    return @{ handled = $false; action = "no_status" }
  }

  $normalized = $status.ToLowerInvariant()
  $doneStatuses = (Get-StringArray (Get-ConfigValue $tracking "done_statuses" @()) @("done", "closed_accepted", "closed_accepted_with_notes", "accepted")) | ForEach-Object { $_.ToLowerInvariant() }
  $blockedStatuses = (Get-StringArray (Get-ConfigValue $tracking "blocked_statuses" @()) @("blocked", "blocked_needs_human", "rejected", "failed", "failed_safely")) | ForEach-Object { $_.ToLowerInvariant() }
  $runningStatuses = (Get-StringArray (Get-ConfigValue $tracking "running_statuses" @()) @("running", "in_progress")) | ForEach-Object { $_.ToLowerInvariant() }
  $waitingStatuses = (Get-StringArray (Get-ConfigValue $tracking "waiting_statuses" @()) @("waiting", "pending", "queued")) | ForEach-Object { $_.ToLowerInvariant() }

  $evidence = @($Item["evidence"])
  $externalEvidence = @{
    ts = [DateTimeOffset]::UtcNow.ToString("o")
    type = "external_state_terminal"
    state_file = $statePath
    status = $status
  }

  if ($normalized -in $doneStatuses) {
    $Item["status"] = "done"
    $Item["last_finished_at"] = [DateTimeOffset]::UtcNow.ToString("o")
    $evidence += $externalEvidence
    $Item["evidence"] = $evidence
    return @{ handled = $true; action = "done"; status = $status }
  }

  if ($normalized -in $blockedStatuses) {
    $Item["status"] = "blocked"
    $Item["last_error"] = "blocked by external state '$status'"
    $evidence += $externalEvidence
    $Item["evidence"] = $evidence
    return @{ handled = $true; action = "blocked"; status = $status }
  }

  if ($normalized -in $runningStatuses) {
    $Item["status"] = "running"
    $Item["last_external_state"] = $status
    return @{ handled = $true; action = "running"; status = $status }
  }

  if ($normalized -in $waitingStatuses) {
    $Item["status"] = "waiting"
    $Item["last_external_state"] = $status
    return @{ handled = $true; action = "waiting"; status = $status }
  }

  $Item["last_external_state"] = $status
  return @{ handled = $false; action = "unknown"; status = $status }
}

function Invoke-SupervisorIteration {
  $backlog = Read-Backlog
  if (-not $backlog.ContainsKey("created_at") -or -not $backlog.created_at) {
    $backlog["created_at"] = [DateTimeOffset]::UtcNow.ToString("o")
  }

  Write-Event $backlog @{ event = "poll"; status = $backlog.status }
  Send-ProgressUpdate $backlog

  $requiredOpen = 0
  foreach ($item in @($backlog.items)) {
    if (-not [bool](Get-ConfigValue $item "required" $true)) { continue }
    if ([string]$item.status -in @("done", "skipped")) { continue }
    $requiredOpen += 1

    if ([string]$item.status -eq "blocked") {
      Send-Alert $backlog "action_required" "Backlog item $($item.id) is blocked: $($item.last_error)" "blocked-$($item.id)"
      continue
    }

    $missingDependencies = @(Get-MissingDependencies -Backlog $backlog -Item $item)
    if ($missingDependencies.Count -gt 0) {
      $item["status"] = "waiting"
      $item["waiting_on"] = $missingDependencies
      $item["last_waiting_at"] = [DateTimeOffset]::UtcNow.ToString("o")
      Write-Event $backlog @{ event = "item_waiting"; item_id = $item.id; waiting_on = $missingDependencies }
      continue
    }
    if ([string]$item.status -eq "waiting") {
      $item["status"] = "pending"
      $item.Remove("waiting_on")
    }

    $external = Invoke-ExternalStateTracking -Backlog $backlog -Item $item
    if ([bool]$external.handled) {
      Write-Event $backlog @{ event = "external_state_applied"; item_id = $item.id; action = $external.action; status = $external.status }
      if ([string]$external.action -eq "blocked") {
        Send-Alert $backlog "action_required" "Backlog item $($item.id) is blocked by external state: $($external.status)" "external-blocked-$($item.id)"
      }
      continue
    }

    if (Test-ItemDone $backlog $item) {
      Write-Event $backlog @{ event = "item_done"; item_id = $item.id }
      continue
    }

    $supervisor = Get-ConfigValue $backlog "supervisor" @{}
    $maxRetries = [int](Get-ConfigValue $supervisor "max_retries_per_item" 3)
    $maxRetries = [int](Get-ConfigValue $item "max_retries" $maxRetries)
    $attempts = [int](Get-ConfigValue $item "attempts" 0)
    if ([string]$item.status -eq "running") {
      $retryAfterSeconds = [int](Get-ConfigValue $item "retry_running_after_seconds" 0)
      $lastStartedText = [string](Get-ConfigValue $item "last_started_at" "")
      if ($retryAfterSeconds -gt 0 -and $lastStartedText.Trim()) {
        try {
          $lastStarted = [DateTimeOffset]::Parse($lastStartedText)
          $elapsedSeconds = ([DateTimeOffset]::UtcNow - $lastStarted).TotalSeconds
          if ($elapsedSeconds -lt $retryAfterSeconds) {
            Write-Event $backlog @{
              event = "item_running_wait"
              item_id = $item.id
              retry_after_seconds = $retryAfterSeconds
              elapsed_seconds = [int]$elapsedSeconds
            }
            continue
          }
        } catch {}
      }
    }

    if ($attempts -ge $maxRetries) {
      $item["status"] = "blocked"
      $item["last_error"] = "max retries reached; last check did not pass"
      Send-Alert $backlog "action_required" "Backlog item $($item.id) reached max retries." "max-retries-$($item.id)"
      continue
    }

    $recoverCommand = [string](Get-ConfigValue $item "recover_command" "")
    if ([string]$item.status -eq "running" -and $recoverCommand.Trim()) {
      $recover = Invoke-BacklogCommand -Backlog $backlog -Command $recoverCommand -Kind "recover" -ItemId ([string]$item.id)
      Write-Event $backlog @{ event = "item_recover"; item_id = $item.id; exit_code = $recover.exit_code; output = ([string]$recover.output) }
    }

    $runCommand = [string](Get-ConfigValue $item "run_command" "")
    $item["status"] = "running"
    $item["attempts"] = $attempts + 1
    $item["last_started_at"] = [DateTimeOffset]::UtcNow.ToString("o")
    $run = Invoke-BacklogCommand -Backlog $backlog -Command $runCommand -Kind "run" -ItemId ([string]$item.id)
    Write-Event $backlog @{ event = "item_run"; item_id = $item.id; attempt = $item.attempts; exit_code = $run.exit_code; output = ([string]$run.output) }
    if ($run.exit_code -ne 0) {
      $item["last_error"] = [string]$run.output
    }
  }

  $allRequiredClosed = $true
  $anyRequiredBlocked = $false
  foreach ($item in @($backlog.items)) {
    if ([bool](Get-ConfigValue $item "required" $true) -and [string]$item.status -eq "blocked") {
      $anyRequiredBlocked = $true
    }
    if ([bool](Get-ConfigValue $item "required" $true) -and [string]$item.status -notin @("done", "skipped")) {
      $allRequiredClosed = $false
    }
  }

  if ($anyRequiredBlocked) {
    $backlog["status"] = "blocked"
  } elseif ($allRequiredClosed) {
    $finalCommand = [string](Get-ConfigValue $backlog "final_validation_command" "")
    $final = Invoke-BacklogCommand -Backlog $backlog -Command $finalCommand -Kind "final" -ItemId "FINAL"
    Write-Event $backlog @{ event = "final_validation"; exit_code = $final.exit_code; output = ([string]$final.output) }
    if ($final.exit_code -eq 0) {
      $backlog["status"] = "complete"
      $backlog["completed_at"] = [DateTimeOffset]::UtcNow.ToString("o")
    } else {
      $backlog["status"] = "blocked"
      Send-Alert $backlog "action_required" "All backlog items closed, but final validation failed." "final-validation-failed"
    }
  } else {
    $backlog["status"] = "running"
  }

  Write-Backlog $backlog
  return $backlog
}

try {
  $iteration = 0
  while ($true) {
    $iteration += 1
    $backlog = Invoke-SupervisorIteration
    if ([string]$backlog.status -eq "complete") {
      Write-Event $backlog @{ event = "supervisor_complete" }
      break
    }
    if ($Once -or ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations)) {
      Write-Event $backlog @{ event = "supervisor_exit"; reason = "iteration_limit"; iteration = $iteration }
      break
    }
    $supervisor = Get-ConfigValue $backlog "supervisor" @{}
    $interval = if ($OverrideIntervalSeconds -gt 0) { $OverrideIntervalSeconds } else { [int](Get-ConfigValue $supervisor "interval_seconds" 300) }
    Start-Sleep -Seconds ([Math]::Max(10, $interval))
  }
} finally {
  try {
    if (Test-Path -LiteralPath $LockPath) {
      $existingLock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
      if ([int]$existingLock.pid -eq $PID) {
        Remove-Item -LiteralPath $LockPath -Force
      }
    }
  } catch {}
}
