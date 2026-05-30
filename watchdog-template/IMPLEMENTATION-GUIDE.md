# Durable Watchdog Implementation Guide

This guide is for AI agents that need to add unattended supervision to any project. It turns the reusable watchdog template plus the proven orchestration patterns into a repeatable implementation recipe.

Search terms: durable watchdog template, unattended backlog supervisor, file-backed backlog supervisor, external monitor, deadman monitor, agent heartbeat, watchdog launcher, recovery prompt, progress updater, step-gate watchdog, orchestration watchdog, Agora watchdog, GECL watchdog.

## Agent Discovery Prompt

When another agent is asked to add a watchdog, give it this instruction:

> Find `C:\Users\chris\PROJECTS\shared\watchdog-template\IMPLEMENTATION-GUIDE.md` and implement the durable watchdog pattern for the current project. Search QMD or TechLib for `durable watchdog template`, `unattended backlog supervisor`, `external monitor`, and `agent heartbeat`. Build the supervision layer from durable files, not chat memory.

## When To Use This

Use this pattern when work must continue, recover, or remain observable after the current chat turn ends.

Good fits:

- Long-running coder, validator, browser, or data pipeline work.
- Multi-agent runs with worker sessions that can go silent.
- External advisor flows where a ChatGPT, Claude, Codex, Gemini, or Kimi turn must be gated before the next step.
- Audit or repair loops that must advance one durable item at a time.
- Overnight or crash-resilient supervision.
- Any workflow where a user may later ask, "is it still running, blocked, done, or hung?"

Do not use this pattern for a quick command that finishes in the current turn, or for work that cannot be retried safely.

## Core Rule

The chat is not the supervisor. Durable files plus an external OS process are the supervisor.

Every implementation must answer these questions from disk:

- What work remains?
- Which item is running now?
- Who owns the running work?
- What was the last verified progress?
- What evidence proves done, blocked, or failed?
- What should restart after a crash?
- What should never restart without human approval?

## Building Blocks

| Component | Required | Purpose | Generic file name |
|---|---:|---|---|
| Backlog file | Yes | Durable list of required work items and commands | `watchdog-backlog.json` |
| Supervisor | Yes | Polls backlog, starts work, checks evidence, retries or blocks | `supervisor-template.ps1` or project copy |
| External monitor template | For unattended runs | Restarts missing supervisors and wakes stale controllers | `external-monitor-template.ps1` |
| Passive Ralph observer | Optional | Observes loop health without waking, launching, or owning authority | `ralph-observer-template.ps1` |
| Event log | Yes | Append-only audit trail | `watchdog-events.jsonl` |
| State file | Yes | Latest machine-readable state | `watchdog-state.json` |
| Launcher | Usually | Starts one supervisor/watchdog safely and writes config | `start_<project>_watchdog.ps1` |
| External monitor | For unattended runs | Restarts missing watchdogs/controllers and wakes recovery | `<project>_external_monitor.ps1` |
| PID/lock file | Yes | Prevents duplicate owners | `watchdog.pid` or `.lock.json` |
| Heartbeat file | For long workers | Distinguishes active work from silence | `agent-heartbeat.json` |
| Recovery command | Usually | Rebuilds context and relaunches a stuck item | `recover_<project>.ps1` |
| Progress updater | Optional | Sends short routine status when explicitly requested | `<project>_progress_update.ps1` |
| Final validation | Yes | Stops the run only when global success is proven | project-specific command |

## Choose The Right Shape

### Shape A: Backlog Supervisor Only

Use when each work item has simple `run_command`, `check_command`, and optional `recover_command`.

Implement:

- Copy `backlog-template.json`.
- Fill item commands.
- Run `supervisor-template.ps1`.
- Add a Windows Scheduled Task only if it must survive logoff/reboot.

This is the default for simple unattended work.

### Shape B: Project Watchdog Plus Launcher

Use when the project has richer state than a plain backlog: dialogue transcripts, validator verdicts, current row IDs, browser state, queue state, or per-gap recovery packets.

Implement:

- Project-specific watchdog script.
- Project-specific launcher that writes config and starts the watchdog.
- PID file and event log.
- `-Once` or dry-run mode for safe status probes.

Reference pattern:

- `C:\Users\chris\PROJECTS\agora\scripts\gecl_orchestration_watchdog.ps1`
- `C:\Users\chris\PROJECTS\agora\scripts\start_gecl_orchestration_watchdog.ps1`

### Shape C: Watchdog Plus External Monitor

Use when the watchdog itself may die, or when a controller must be woken if a worker stalls.

Implement:

- All of Shape B.
- External monitor process.
- Monitor event log.
- Cooldown rules for restart and wake-up.
- Terminal stop rules so final/done/blocked states do not relaunch work.

Reference pattern:

- `C:\Users\chris\PROJECTS\agora\scripts\gecl_orchestration_external_monitor.ps1`
- `C:\Users\chris\PROJECTS\agora\scripts\code_audit_step_gate_external_monitor.ps1`

### Shape D: Step-Gate Watchdog

Use when every step must be reviewed before the pipeline advances.

Implement:

- Step checkpoint file.
- Per-step context packet.
- Advisor call or local reviewer call.
- Controller decision with allowed actions.
- CAS or state-id check before continuing so stale approvals cannot advance new state.

Reference pattern:

- `C:\Users\chris\PROJECTS\agora\scripts\audit_loop_chatgpt_step_gate_watchdog.py`

### Shape E: Passive Ralph Observer

Use when the project must check that an orchestration loop is healthy, but the user does not want another controller/session to wake or drive the work.

Implement:

- Add a `ralph_observer` block to the backlog.
- Point it at the loop state file, controller heartbeat file, and counter/authority file.
- Run `ralph-observer-template.ps1 -Once` for a one-shot check, or on a schedule only if the user accepts passive logging.
- Treat `ACTION_REQUIRED:*` as a signal to the current human/session, not as permission to launch another agent.
- Treat `STOP_GURU_INTERACTION_FINAL_DELIVERY_RECORDED` as a quiet terminal state only when the configured loop state reports the accepted final status.

Forbidden:

- no Guru contact;
- no Codex/Ralph/session launch;
- no Telegram/native relay wake;
- no product edits;
- no counter, dashboard, or source-of-truth writes.

## Implementation Procedure For AI Agents

Follow these steps in order. Do not skip the discovery and proof steps.

### Step 1: Map The Project State

Find the durable source of truth:

- Backlog, ledger, queue, database, or run registry.
- Current item ID, gap ID, row ID, task ID, or worker role.
- Existing logs, state files, session files, and result files.
- Existing launcher or process owner.
- Existing final validation command.

Write down:

- `project_root`
- `data_dir`
- `event_log`
- `state_file`
- `pid_file`
- `config_file`
- `final_validation_command`

If there is no durable state, create it before writing a watchdog.

### Step 2: Define Terminal States

Make terminal states explicit.

Common done states:

- `done`
- `complete`
- `closed_accepted`
- `closed_accepted_with_notes`
- `completed_full_credibility_proven`
- `final_keyword_approved`

Common blocked states:

- `blocked`
- `blocked_needs_human`
- `failed`
- `failed_safely`
- `rejected`
- `manual_gate`
- `quota_exhausted`
- `permission_required`

Common running/waiting states:

- `running`
- `in_progress`
- `waiting`
- `pending`
- `queued`
- `awaiting_advisor`

The watchdog must never relaunch work for terminal done or blocked states unless the user explicitly requests it.

### Step 3: Create The Backlog Or Config

For generic backlog supervision, copy:

```powershell
Copy-Item C:\Users\chris\PROJECTS\shared\watchdog-template\backlog-template.json C:\path\to\project\watchdog-backlog.json
```

For project-specific supervision, create a config file with at least:

```json
{
  "schema": "project-watchdog-config-v1",
  "project_root": "C:\\path\\to\\project",
  "data_dir": "C:\\path\\to\\project\\data\\watchdog",
  "event_log": "C:\\path\\to\\project\\data\\watchdog\\watchdog-events.jsonl",
  "state_file": "C:\\path\\to\\project\\data\\watchdog\\watchdog-state.json",
  "pid_file": "C:\\path\\to\\project\\data\\watchdog\\watchdog.pid",
  "poll_seconds": 60,
  "status_minutes": 15,
  "stall_minutes": 25,
  "recovery_cooldown_minutes": 60,
  "telegram_mode": "ActionRequired",
  "controller_blocked": false
}
```

### Step 4: Make Commands Idempotent

Every command must be safe to run more than once.

For each item:

- `run_command` starts or resumes work.
- `check_command` exits `0` only when evidence proves done.
- `recover_command` repairs or relaunches after stale state.
- `final_validation_command` exits `0` only when the whole run can stop.

Bad check command:

```powershell
Write-Output "looks fine"
exit 0
```

Good check command:

```powershell
if (Test-Path -LiteralPath "C:\path\to\evidence.json") {
  $evidence = Get-Content -LiteralPath "C:\path\to\evidence.json" -Raw | ConvertFrom-Json
  if ($evidence.status -eq "closed_accepted" -and $evidence.proof_count -ge 1) { exit 0 }
}
exit 1
```

### Step 5: Implement Heartbeats For Long Workers

If a worker can be silent for several minutes, require a heartbeat file.

Heartbeat shape:

```json
{
  "schema": "agent-heartbeat-v1",
  "worker_id": "link-123-or-session-id",
  "agent_role": "coder",
  "task_id": "ITEM-001",
  "phase": "running_tests",
  "last_action": "Running targeted tests.",
  "blocked": false,
  "blocked_reason": "",
  "updated_at": "2026-05-17T00:00:00Z"
}
```

Rules:

- The active worker writes heartbeat at a fixed cadence.
- The supervisor treats fresh heartbeat as active progress.
- Blocked heartbeat becomes action-required.
- Stale heartbeat triggers normal check/recovery logic.
- Missing heartbeat is not proof of failure by itself.

When switching models or sessions, update worker ID and heartbeat path, then require a fresh handshake heartbeat before unattended work resumes.

### Step 6: Implement Event Logging

Every watchdog and monitor must append JSONL events.

Minimum event fields:

```json
{
  "ts": "2026-05-17T00:00:00Z",
  "event": "watchdog_poll",
  "project": "project-name",
  "item_id": "ITEM-001",
  "status": "running",
  "detail": "Fresh heartbeat observed."
}
```

Useful event names:

- `watchdog_started`
- `watchdog_poll`
- `heartbeat_fresh`
- `heartbeat_stale`
- `worker_blocked`
- `item_done`
- `item_recovery_started`
- `item_blocked`
- `watchdog_exit`
- `external_monitor_started`
- `external_monitor_started_watchdog`
- `external_monitor_controller_blocked`
- `step_gate_checkpoint_created`
- `step_gate_advisor_verdict`
- `step_gate_controller_action`

### Step 7: Add A Launcher

The launcher should:

- Resolve project paths.
- Write or refresh config.
- Check if an expected process is already alive.
- Preserve live owners by default.
- Start the watchdog hidden.
- Write a launcher event.

PowerShell launch pattern:

```powershell
function Quote-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value) { return '""' }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"') + '"'
}

$args = @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", "C:\path\to\project\scripts\project_watchdog.ps1",
  "-ConfigFile", "C:\path\to\project\data\watchdog\watchdog-config.json"
)

Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList (($args | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " ")
```

Never let a status-only probe replace a live owner.

### Step 8: Add An External Monitor When Needed

Use an external monitor if:

- The watchdog may be killed.
- The controller may need a bounded resume prompt.
- A browser or advisor loop needs restart checks.
- A scheduled task should keep the supervision system alive.

External monitor loop:

1. Read config and state.
2. If terminal done, exit or stay quiet.
3. If controller blocked, stay alive and suppress relaunch.
4. If watchdog missing and work active, start watchdog.
5. If worker stale past threshold, write recovery prompt and wake controller.
6. Enforce cooldown so it does not spam resumes.
7. Append all decisions to JSONL.

Reusable implementation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File C:\Users\chris\PROJECTS\shared\watchdog-template\external-monitor-template.ps1 `
  -BacklogPath C:\path\to\project\watchdog-backlog.json `
  -Once
```

For unattended recovery, install a scheduled owner:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File C:\Users\chris\PROJECTS\shared\watchdog-template\install-external-monitor-scheduled-task.ps1 `
  -BacklogPath C:\path\to\project\watchdog-backlog.json `
  -TaskName "Project External Monitor" `
  -IntervalMinutes 1
```

The installer registers `wscript.exe //B` with a generated hidden launcher so the monitor does not flash recurring PowerShell windows in an interactive desktop session. Configure the backlog `external_monitor` block with `controller_heartbeat_file`, `controller_heartbeat_stale_seconds`, `controller_wake_command`, `wake_cooldown_seconds`, `wake_log_file`, and `wake_state_file`. The wake command must be bounded and idempotent: it should resume the controller from durable state, not start broad work from memory. Each wake attempt must leave a human-readable log plus a machine-readable state file with `started`, `exited`, and `exit_code` evidence.

### Step 9: Add Step-Gate Review For Sensitive Pipelines

Use step-gate review when a pipeline must not advance without independent approval.

For each reviewable step:

- Create a checkpoint with step ID, item ID, state hash, and timestamp.
- Build a context packet with relevant files and latest state.
- Ask the advisor/reviewer for a verdict.
- Accept only structured verdicts.
- Re-read the current state before acting.
- Continue only if the checkpoint still matches current state.

Controller actions should be a small closed set:

```text
continue
retry_step
restart_item_clean
fix_pipeline
human_input_required
stop_pipeline_bug
```

Any ambiguous advisor response must become `manual_gate`, not `continue`.

### Step 10: Add Progress Updates Only When Asked

Routine progress messages are optional. Enable them only when the user explicitly asks for visible unattended status.

Good progress message:

```text
The validator is still running the current item. The heartbeat is fresh and the last action was "running targeted tests". No human action is needed. RUNNING AS PLANNED
```

Rules:

- Keep it short.
- Include current item, latest evidence, and whether human action is needed.
- End with a short all-caps controller verdict.
- Do not send routine Telegram messages in `ActionRequired` mode.

### Step 11: Add Tests Or Smoke Checks

Minimum checks before claiming success:

- Watchdog starts and writes `watchdog_started`.
- Duplicate launch keeps the existing owner.
- `-Once` or status probe does not claim ownership.
- Fresh heartbeat suppresses duplicate recovery.
- Stale heartbeat triggers check/recovery path.
- Blocked heartbeat creates action-required state.
- Terminal done state suppresses relaunch.
- Terminal blocked state suppresses relaunch and records reason.
- External monitor starts missing watchdog when active work exists.
- External monitor does not start watchdog when terminal or controller-blocked.
- Final validation controls global complete state.

For PowerShell scripts, at minimum run parser checks:

```powershell
[scriptblock]::Create((Get-Content -LiteralPath "C:\path\to\script.ps1" -Raw)) | Out-Null
```

For Python scripts, at minimum run:

```powershell
python -m py_compile C:\path\to\script.py
```

## Generic File Layout

Use this layout unless the project already has a stronger convention:

```text
project/
  data/
    watchdog/
      watchdog-config.json
      watchdog-state.json
      watchdog-events.jsonl
      watchdog.pid
      external-monitor-events.jsonl
      recovery-prompt.md
      agent-heartbeat.json
  scripts/
    start_project_watchdog.ps1
    project_watchdog.ps1
    project_external_monitor.ps1
    project_recover.ps1
    project_progress_update.ps1
  tests/
    test_project_watchdog.py
    test_project_external_monitor.py
```

## Recovery Prompt Contract

If the monitor wakes an AI controller, the prompt must be bounded and specific.

Include:

- Current task/item ID.
- Latest state file path.
- Latest event log path.
- Latest heartbeat status.
- What was attempted.
- What must not be repeated.
- Exact next allowed actions.
- Stop condition.

Do not ask the controller to "figure out what happened" without paths and state.

Skeleton:

```text
Resume supervised project work.

Read first:
- C:\path\to\data\watchdog\watchdog-state.json
- C:\path\to\data\watchdog\watchdog-events.jsonl
- C:\path\to\data\watchdog\agent-heartbeat.json

Current item: ITEM-001
Latest monitor event: worker_stale
Allowed actions: inspect state, recover item, mark blocked with evidence, or stop if terminal state is already present.
Do not start duplicate workers. Do not advance to the next item unless final evidence for ITEM-001 exists.
Report the action taken and the durable evidence path.
```

## Reference Implementations

Use these as examples, not as copy-paste requirements:

| Pattern | Reference |
|---|---|
| Generic durable backlog supervisor | `C:\Users\chris\PROJECTS\shared\watchdog-template\supervisor-template.ps1` |
| Generic external monitor | `C:\Users\chris\PROJECTS\shared\watchdog-template\external-monitor-template.ps1` |
| Generic passive Ralph observer | `C:\Users\chris\PROJECTS\shared\watchdog-template\ralph-observer-template.ps1` |
| Generic scheduled monitor installer | `C:\Users\chris\PROJECTS\shared\watchdog-template\install-external-monitor-scheduled-task.ps1` |
| Generic backlog schema | `C:\Users\chris\PROJECTS\shared\watchdog-template\backlog-template.json` |
| Generic smoke-test backlog | `C:\Users\chris\PROJECTS\shared\watchdog-template\examples\sample-backlog.json` |
| GECL orchestration watchdog | `C:\Users\chris\PROJECTS\agora\scripts\gecl_orchestration_watchdog.ps1` |
| GECL launcher | `C:\Users\chris\PROJECTS\agora\scripts\start_gecl_orchestration_watchdog.ps1` |
| GECL external monitor | `C:\Users\chris\PROJECTS\agora\scripts\gecl_orchestration_external_monitor.ps1` |
| Agora Code Audit Loop step-gate watchdog | `C:\Users\chris\PROJECTS\agora\scripts\audit_loop_chatgpt_step_gate_watchdog.py` |
| Agora Code Audit Loop external monitor | `C:\Users\chris\PROJECTS\agora\scripts\code_audit_step_gate_external_monitor.ps1` |

## Common Failure Modes And Required Responses

| Failure | Detection | Required response |
|---|---|---|
| Worker silent | stale heartbeat, no file changes, stale transcript | run check command, then recovery if not terminal |
| Worker explicitly blocked | heartbeat `blocked=true` or state blocked | mark blocked, alert action-required, do not relaunch |
| Watchdog dead | PID missing or wrong process | external monitor starts watchdog if work active |
| Controller blocked | config `controller_blocked=true` | monitor stays alive but suppresses watchdog/controller relaunch |
| Advisor ambiguous | no structured verdict | manual gate or human input required |
| Stale approval | checkpoint hash/state id mismatch | discard approval and re-review current state |
| Quota or permission failure | process output or heartbeat reason | mark blocked unless a deterministic fallback is configured |
| Duplicate owner | lock/PID points to live process | keep existing owner, log duplicate suppression |
| Final state reached | terminal done state or final keyword | stop watchdog/monitor or switch to quiet terminal mode |

## Agent Implementation Checklist

Before editing:

- [ ] Read this guide.
- [ ] Read `README.md` in this directory.
- [ ] Find the project root and durable source of truth.
- [ ] Identify terminal done, blocked, running, and waiting states.
- [ ] Decide Shape A, B, C, or D.

While implementing:

- [ ] Create or fill the backlog/config.
- [ ] Add event log and state file paths.
- [ ] Add PID/lock protection.
- [ ] Add heartbeat tracking for long workers.
- [ ] Add launcher if a project-specific watchdog exists.
- [ ] Add external monitor if unattended recovery is required.
- [ ] Add step-gate review if pipeline advancement is sensitive.
- [ ] Add action-required alert behavior.
- [ ] Add final validation.

Before claiming done:

- [ ] Run parser/compile checks.
- [ ] Run focused tests or smoke checks.
- [ ] Prove duplicate launch suppression.
- [ ] Prove terminal state suppression.
- [ ] Prove stale/blocked worker handling.
- [ ] Record the file paths, commands, and evidence in a durable note.

## Non-Negotiable Rules

- Do not rely on chat memory as state.
- Do not run two owners for the same supervised work.
- Do not let status probes claim ownership.
- Do not advance on ambiguous advisor output.
- Do not recover terminal blocked states automatically.
- Do not mark done without machine-readable evidence.
- Do not create noisy routine progress unless the user asked for it.
- Do not hide degraded supervision. Report missing workers, stale heartbeats, and failed health checks explicitly.
