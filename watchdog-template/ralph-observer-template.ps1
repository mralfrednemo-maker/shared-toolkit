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

function Resolve-ObserverPath {
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
    [hashtable]$Hash,
    [string[]]$Path
  )
  $current = $Hash
  foreach ($part in $Path) {
    if ($null -eq $current) { return $null }
    if ($current -isnot [hashtable] -or -not $current.ContainsKey($part)) { return $null }
    $current = $current[$part]
  }
  return $current
}

function Read-Backlog {
  return ConvertTo-Hashtable ((Get-Content -LiteralPath $BacklogPath -Raw) | ConvertFrom-Json)
}

function Get-EventLogPath {
  param([hashtable]$Config)
  return Resolve-ObserverPath ([string](Get-ConfigValue $Config "event_log" "ralph-observer-events.jsonl")) "ralph-observer-events.jsonl"
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

function Invoke-RalphObserverIteration {
  $backlog = Read-Backlog
  $config = Get-ConfigValue $backlog "ralph_observer" @{}
  $statePath = Resolve-ObserverPath ([string](Get-ConfigValue $config "state_file" "ralph-observer-state.json")) "ralph-observer-state.json"

  if (-not [bool](Get-ConfigValue $config "enabled" $false)) {
    $config["enabled"] = $false
    $state = [ordered]@{
      schema = "ralph-observer-state-v1"
      checked_at = [DateTimeOffset]::UtcNow.ToString("o")
      backlog_path = $BacklogPath
      observer_enabled = $false
      mode = "passive"
      status = "PASSIVE_OBSERVER_DISABLED"
      terminal = $false
      action_required = $false
      action_taken = "none"
      forbidden_actions_confirmed = @("guru_contact", "codex_launch", "session_wake", "product_edit", "authority_write")
    }
    Write-JsonFile $statePath $state
    Write-Event $config @{ event = "ralph_observer_disabled"; backlog_path = $BacklogPath }
    Write-Output ($state | ConvertTo-Json -Compress -Depth 12)
    return
  }

  $heartbeatPath = Resolve-ObserverPath ([string](Get-ConfigValue $config "controller_heartbeat_file" "")) ""
  $heartbeatStaleAfter = [int](Get-ConfigValue $config "controller_heartbeat_stale_seconds" 420)
  $heartbeat = Get-HeartbeatStatus -HeartbeatPath $heartbeatPath -StaleAfterSeconds $heartbeatStaleAfter

  $loopStatePath = Resolve-ObserverPath ([string](Get-ConfigValue $config "loop_state_file" "")) ""
  $loopState = Read-JsonFile $loopStatePath
  $loopStatusPath = Get-StringArray (Get-ConfigValue $config "loop_status_path" @("status")) @("status")
  $loopStatus = ""
  if ($null -ne $loopState) {
    $loopStatus = [string](Get-NestedValue $loopState $loopStatusPath)
  }
  $loopStatusLower = $loopStatus.ToLowerInvariant()

  $finalStatuses = (Get-StringArray (Get-ConfigValue $config "final_statuses" @("final_delivery_keyword_seen", "complete")) @("final_delivery_keyword_seen", "complete")) | ForEach-Object { $_.ToLowerInvariant() }
  $healthyStatuses = (Get-StringArray (Get-ConfigValue $config "healthy_statuses" @("ready_for_guru_loop", "running", "in_progress")) @("ready_for_guru_loop", "running", "in_progress")) | ForEach-Object { $_.ToLowerInvariant() }
  $actionRequiredStatuses = (Get-StringArray (Get-ConfigValue $config "action_required_statuses" @("action_required", "blocked", "blocked_pending_guru_url")) @("action_required", "blocked", "blocked_pending_guru_url")) | ForEach-Object { $_.ToLowerInvariant() }

  $counterPath = Resolve-ObserverPath ([string](Get-ConfigValue $config "authority_counter_file" "")) ""
  $counters = Read-JsonFile $counterPath
  $activeGuruUrl = ""
  if ($null -ne $counters) {
    $activeGuruUrl = [string](Get-ConfigValue $counters "active_guru_url" "")
  }

  $requiresGuruUrl = [bool](Get-ConfigValue $config "active_guru_url_required" $true)
  $status = "PASSIVE_OBSERVER_HEALTHY"
  $reason = "Ralph passive observer sees fresh controller evidence and no final status."
  $terminal = $false
  $actionRequired = $false

  if (-not $loopStatePath.Trim()) {
    $status = "ACTION_REQUIRED: LOOP_STATE_NOT_CONFIGURED"
    $reason = "Loop state file is not configured."
    $actionRequired = $true
  } elseif ($null -eq $loopState) {
    $status = "ACTION_REQUIRED: LOOP_STATE_MISSING"
    $reason = "Loop state file missing or invalid."
    $actionRequired = $true
  } elseif ($loopStatusLower -in $finalStatuses) {
    $status = "STOP_GURU_INTERACTION_FINAL_DELIVERY_RECORDED"
    $reason = "Configured loop state reports final delivery status."
    $terminal = $true
  } elseif ($loopStatusLower -in $actionRequiredStatuses) {
    $status = "ACTION_REQUIRED: LOOP_STATE_ACTION_REQUIRED"
    $reason = "Configured loop state reports action-required status: $loopStatus."
    $actionRequired = $true
  } elseif ($heartbeat.status -in @("missing", "invalid", "stale", "blocked")) {
    $status = "ACTION_REQUIRED: HEARTBEAT_STALE"
    $reason = $heartbeat.reason
    $actionRequired = $true
  } elseif ($requiresGuruUrl -and -not $activeGuruUrl.Trim()) {
    $status = "ACTION_REQUIRED: GURU_URL_MISSING"
    $reason = "Active Guru URL is missing from configured counter authority file."
    $actionRequired = $true
  } elseif ($loopStatusLower -notin $healthyStatuses) {
    $status = "ACTION_REQUIRED: LOOP_STATE_UNKNOWN"
    $reason = "Configured loop state is not final, healthy, or action-required: $loopStatus."
    $actionRequired = $true
  }

  $state = [ordered]@{
    schema = "ralph-observer-state-v1"
    checked_at = [DateTimeOffset]::UtcNow.ToString("o")
    backlog_path = $BacklogPath
    observer_enabled = $true
    mode = "passive"
    status = $status
    reason = $reason
    terminal = $terminal
    action_required = $actionRequired
    action_taken = "none"
    loop_state_file = $loopStatePath
    loop_status = $loopStatus
    controller_heartbeat_file = $heartbeatPath
    controller_heartbeat_status = $heartbeat.status
    controller_heartbeat_age_seconds = $heartbeat.age_seconds
    controller_heartbeat_reason = $heartbeat.reason
    authority_counter_file = $counterPath
    active_guru_url_present = [bool]$activeGuruUrl.Trim()
    final_keyword = [string](Get-ConfigValue $config "final_keyword" "")
    forbidden_actions_confirmed = @("guru_contact", "codex_launch", "session_wake", "product_edit", "authority_write")
  }

  Write-JsonFile $statePath $state
  Write-Event $config @{
    event = "ralph_observer_poll"
    status = $status
    terminal = $terminal
    action_required = $actionRequired
    loop_status = $loopStatus
    controller_heartbeat_status = $heartbeat.status
    action_taken = "none"
  }
  Write-Output ($state | ConvertTo-Json -Compress -Depth 12)
}

$iteration = 0
while ($true) {
  $iteration += 1
  Invoke-RalphObserverIteration
  if ($Once -or ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations)) {
    break
  }
  $backlog = Read-Backlog
  $config = Get-ConfigValue $backlog "ralph_observer" @{}
  $pollSeconds = if ($OverridePollSeconds -gt 0) { $OverridePollSeconds } else { [int](Get-ConfigValue $config "poll_seconds" 300) }
  Start-Sleep -Seconds ([Math]::Max(10, $pollSeconds))
}
