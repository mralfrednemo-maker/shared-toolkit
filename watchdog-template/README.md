# Durable Watchdog / Backlog Supervisor Template

Use this template when a project must keep working after the current agent chat stops, compacts, crashes, or is closed.

The core rule is simple: **the chat is not the supervisor**. A file-backed backlog plus an external OS process is the supervisor.

## Discovery Phrase

Tell another agent:

> Find and use the durable unattended backlog supervisor template in `C:\Users\chris\PROJECTS\shared\watchdog-template`. Search QMD/TechLib for `durable watchdog template`, `unattended backlog supervisor`, or `file-backed backlog supervisor`.

Short version:

> Use the shared durable watchdog template for unattended work. It is in `C:\Users\chris\PROJECTS\shared\watchdog-template`; search QMD for `durable watchdog template`.

For implementation work, send the agent directly to `IMPLEMENTATION-GUIDE.md` in this directory. Search terms: `durable watchdog implementation guide`, `external monitor`, `agent heartbeat`, `watchdog launcher`, `recovery prompt`, `step-gate watchdog`, `orchestration watchdog`.

## What This Solves

This pattern prevents the common failure where an agent promises to keep working but the chat turn ends, context compacts, or the agent is not re-invoked.

It does **not** make impossible guarantees. It cannot survive power loss, Windows sleep, missing credentials, quota exhaustion, or permission prompts without user action. It can reliably detect those conditions, log them, and alert.

## Required Contract

Every supervised project needs:

1. A durable backlog JSON file.
2. Idempotent `run_command`, `check_command`, and optional `recover_command` per item.
3. An external supervisor process, usually PowerShell or Windows Scheduled Task.
4. A final validation command.
5. Action-required alerts only.
6. Durable event logs.
7. Optional routine progress updates when the user explicitly asks for them.
8. Optional machine-readable external state when another tool, dialogue runner, or validator owns final verdicts.
9. Optional agent heartbeat tracking when long-running workers need to prove they are still active.

## Files

- `backlog-template.json` - copy this into the project and fill in project-specific commands.
- `supervisor-template.ps1` - generic backlog supervisor. It reads the backlog, starts pending work, checks running work, retries recovery, and stops only when all backlog items and final validation pass.
- `external-monitor-template.ps1` - generic external owner. It restarts a missing supervisor, checks controller heartbeat freshness, and starts the configured wake command when the controller is stale.
- `ralph-observer-template.ps1` - passive Ralph-style observer. It checks loop state, heartbeat freshness, Guru URL presence, and final status, then writes state/events. It never contacts Guru, launches Codex, wakes a session, edits product files, or becomes authority.
- `install-external-monitor-scheduled-task.ps1` - registers a Windows Scheduled Task that runs the external monitor in one-shot mode on a fixed cadence.
- `IMPLEMENTATION-GUIDE.md` - agent-facing implementation guide for creating project-specific watchdogs, launchers, external monitors, heartbeats, recovery prompts, progress updates, and step-gate watchdogs.
- `examples/agora-room-supervision.md` - concrete mapping for Agora Code Audit Loop rooms.
- `examples/sample-backlog.json` - runnable smoke-test backlog for proving the supervisor loop works.

## Backlog Statuses

- `pending` - ready to start.
- `running` - a command was launched and must be checked.
- `done` - check passed and evidence exists.
- `blocked` - human action required.
- `skipped` - explicitly out of scope.

The supervisor exits only when all required items are `done` or `skipped` and the final validation command passes.

## External State Tracking

Some projects have a separate durable source of truth, such as a dialogue runner writing `closed_accepted`, `rejected`, or `blocked_needs_human` into JSON. In that case, enable per-item `state_tracking` so the supervisor reads the external state before running or recovering work.

Example:

```json
"state_tracking": {
  "enabled": true,
  "state_file": "dialogue-state.json",
  "status_path": ["items", "ITEM-001", "status"],
  "done_statuses": ["closed_accepted", "closed_accepted_with_notes"],
  "blocked_statuses": ["rejected", "blocked_needs_human", "failed"],
  "running_statuses": ["running", "in_progress"],
  "waiting_statuses": ["waiting", "pending"]
}
```

If the external status is in `done_statuses`, the item is marked `done` without rerunning recovery. If it is in `blocked_statuses`, the item is marked `blocked` and the backlog status becomes `blocked`. If it is `running` or `waiting`, the supervisor records that state and avoids duplicate launches for that poll.

When `progress_updates.enabled` is true, terminal external states also produce an immediate progress message by default, independent of the normal progress interval. This prevents a completed or rejected validator/dialogue state from sitting unseen until the next periodic status update. Set `"external_terminal_updates": false` under `progress_updates` to suppress that immediate terminal progress message.

## Agent Heartbeat Tracking

For long-running coder, validator, reviewer, or browser workers, add a heartbeat file that the supervisor can read while the worker is still busy. This answers "is the worker still doing anything?" without sending another chat prompt.

Use heartbeat tracking when the main failure mode is operational ambiguity:

- the worker may be actively busy inside one long wake;
- the transcript may stay quiet for minutes at a time;
- the supervisor must distinguish "still working" from "hung, silent, or never woke".

The practical question heartbeat answers is:

> Are we waiting on real work, or are we waiting for nothing?

Heartbeat JSON shape:

```json
{
  "schema": "agora-agent-heartbeat-v1",
  "link_id": "link-...",
  "agent_role": "validator",
  "gap_id": "GAP-006",
  "phase": "running_tests",
  "last_action": "Running targeted tests.",
  "blocked": false,
  "blocked_reason": "",
  "updated_at": "2026-05-06T10:00:00Z"
}
```

Backlog item configuration:

```json
"heartbeat_tracking": {
  "enabled": true,
  "heartbeat_file": "agent-heartbeat.json",
  "stale_after_seconds": 300
}
```

Fresh heartbeat behavior: the item stays `running`, the supervisor logs `heartbeat_fresh`, and duplicate launches are suppressed for that poll. Blocked heartbeat behavior: the item becomes `blocked`, evidence is recorded, and an action-required alert is sent. Stale or missing heartbeat is not treated as proof of failure by itself; the supervisor falls back to normal check/retry/recovery rules and records `heartbeat_stale` or `heartbeat_missing`.

That gives the supervisor four useful operational states:

- `fresh`: the worker is alive and recently reported progress;
- `blocked`: the worker is alive and explicitly needs help;
- `stale`: the worker was alive before, but has stopped reporting within the allowed window;
- `missing`: the worker never produced the expected heartbeat file, so the supervisor must rely on normal recovery rules.

If the user asks "is the run hanging?", a healthy heartbeat lets you answer `no` with evidence: role, gap/task id, phase, last action, and heartbeat age. If heartbeat goes stale, you can answer `probably yes` or `needs recovery` instead of waiting blindly.

For Agora inbox workers, use:

```powershell
python C:\Users\chris\PROJECTS\agora\scripts\agora_inbox.py process-once --to-link link-... --agent-role validator --gap-id GAP-006 --heartbeat-interval 120
```

Minimum setup checklist:

1. Enable `heartbeat_tracking` on the backlog item.
2. Make the worker write a heartbeat at a fixed cadence while it is busy.
3. Include `agent_role`, a task id such as `gap_id`, `phase`, and `last_action`.
4. Pick `stale_after_seconds` shorter than the point where a human would ask whether the worker is hung.
5. Verify one fresh heartbeat, one blocked heartbeat, and one stale heartbeat case before relying on the setup unattended.

Role/backend switch checklist:

1. Treat heartbeat ownership as belonging to the worker link or session, not to the model brand.
2. If the same live link/session stays in use and only the backend command or model changes, keep the heartbeat file path and run a health-check prompt before resuming.
3. If the role moves to a new terminal, link, inbox, or session, update the supervisor item and any project launcher/config with the new worker id, transcript path, and heartbeat path.
4. Reset stale heartbeat state after a worker replacement so old timestamps cannot be mistaken for fresh progress from the new worker.
5. Require a handshake before unattended work resumes: the new worker must answer, write a fresh heartbeat with the expected `agent_role` and task id, and the supervisor must report that heartbeat as fresh.
6. Record the switch in the event log or run notes with previous worker id, new worker id, backend/model command, time, and reason.

## Passive Ralph Observer

Use the passive Ralph observer when the user wants Ralph-like loop checking without allowing a second controller session.

The observer reads configured durable evidence and writes only:

- `ralph-observer-state.json`;
- `ralph-observer-events.jsonl`.

It is deliberately weaker than the external monitor:

- it does not start the supervisor;
- it does not run a wake command;
- it does not contact Guru;
- it does not launch Codex, Ralph, workers, browser automation, or Telegram relays;
- it does not write authoritative dashboard, counter, Guru, or product state.

Its statuses are:

- `PASSIVE_OBSERVER_HEALTHY` - heartbeat and loop state are healthy;
- `ACTION_REQUIRED: HEARTBEAT_STALE` - controller heartbeat is missing, invalid, stale, or blocked;
- `ACTION_REQUIRED: LOOP_STATE_MISSING` - configured loop state is missing or invalid;
- `ACTION_REQUIRED: LOOP_STATE_ACTION_REQUIRED` - configured loop state already reports action required;
- `ACTION_REQUIRED: GURU_URL_MISSING` - configured counter file does not contain an active Guru URL;
- `STOP_GURU_INTERACTION_FINAL_DELIVERY_RECORDED` - configured loop state reports final delivery status.

Run one poll:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File C:\Users\chris\PROJECTS\shared\watchdog-template\ralph-observer-template.ps1 `
  -BacklogPath C:\path\to\project\supervisor-backlog.json `
  -Once
```

This observer can tell a human or the current hosted session that action is required. It cannot force a hosted chat thread to wake up. If a project needs autonomous restart or wake behavior, use an explicitly approved external monitor or restart harness instead.

## How To Use

1. Copy `backlog-template.json` into the project, for example:

   ```powershell
   Copy-Item C:\Users\chris\PROJECTS\shared\watchdog-template\backlog-template.json C:\path\to\project\supervisor-backlog.json
   ```

2. Edit the copied backlog:

   - set `project_root`;
   - set `goal`;
   - define one or more backlog items;
   - make every `run_command` safe to repeat;
   - make every `check_command` return exit code `0` only when the item is actually done;
   - set `final_validation_command`.

3. Start the supervisor:

   ```powershell
   function Quote-ProcessArgument {
     param([string]$Value)
     if ($null -eq $Value) { return '""' }
     return '"' + ($Value -replace '(\\*)"', '$1$1\"') + '"'
   }

   $watchdogArgs = @(
     '-NoProfile',
     '-ExecutionPolicy','Bypass',
     '-File','C:\Users\chris\PROJECTS\shared\watchdog-template\supervisor-template.ps1',
     '-BacklogPath','C:\path\to\project\supervisor-backlog.json'
   )
   Start-Process -WindowStyle Hidden -FilePath powershell.exe -ArgumentList (($watchdogArgs | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join ' ')
   ```

   On Windows PowerShell, avoid passing a raw string array directly to `Start-Process -ArgumentList` when any value can contain spaces. PowerShell can flatten the array into an unquoted command line and shift later parameters into the wrong bindings.

4. Inspect logs:

   - `supervisor-events.jsonl`
   - `supervisor-state.json`
   - the edited backlog JSON itself

5. For unattended recovery, configure `external_monitor` in the backlog and register the scheduled external owner:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass `
     -File C:\Users\chris\PROJECTS\shared\watchdog-template\install-external-monitor-scheduled-task.ps1 `
     -BacklogPath C:\path\to\project\supervisor-backlog.json `
     -TaskName "Project External Monitor" `
     -IntervalMinutes 1
   ```

   The scheduled task runs through `wscript.exe //B` with a generated hidden launcher, which avoids recurring visible PowerShell pop-ups. The launcher runs `external-monitor-template.ps1 -Once`. The monitor starts the supervisor if its lock PID is missing, checks the configured controller heartbeat, and runs `controller_wake_command` only when the heartbeat is missing, invalid, stale, or blocked and the wake cooldown has elapsed. Wake attempts write `external-monitor-wake.log` and `external-monitor-wake-state.json` by default so the next poll can show whether the wake command started, exited, and with what exit code.

6. If the user wants routine status updates, enable `progress_updates` in the backlog:

   ```json
   "progress_updates": {
     "enabled": true,
     "interval_seconds": 900,
     "summary_command": "Write-Output 'Sentence one. Sentence two. Sentence three. RUNNING AS PLANNED'",
     "state_file": "progress-state.json",
     "external_terminal_updates": true
   }
   ```

   The summary command should return exactly the human-facing status text to send, ideally three short sentences every 15 minutes. End the message with a final controller verdict in all caps, maximum three words, for example `RUNNING AS PLANNED`, `PROGRESSING WITH DELAY`, or `NOT RUNNING NORMALLY`. If the controller is not running normally, use the last sentence before the verdict to state the reason and next action briefly. External terminal updates are separate from the interval and are deduped by item/status/action.

## Status Probes And Ownership

One-shot status probes must be observers, not supervisor owners. If a project wraps this template with its own PID file, lock file, launcher, or leader-election rule, only the durable long-running supervisor should claim that ownership record.

Operational rule:

- persistent supervisor run: may claim or refresh the PID/lock owner;
- `-Once`, dry-run, status-only, or diagnostic probe: must not claim PID/lock ownership;
- launcher probe: must not replace a live owner unless the user explicitly asked to restart the supervisor;
- `NoReplaceExisting` behavior should return the live owner instead of spawning a competing supervisor.

This prevents a manual "show me status" probe from causing the real unattended supervisor to exit because it thinks it has been replaced.

## Quality Gates

Before claiming unattended supervision works, verify:

- supervisor process PID exists;
- external monitor process or scheduled task exists;
- scheduled task uses the hidden `wscript.exe //B` launcher unless the user explicitly wants a visible terminal;
- external monitor can restart a missing supervisor;
- passive Ralph observer can report healthy, action-required, and final states without taking control;
- stale controller heartbeat runs the configured wake command;
- wake attempts write a log and machine-readable wake-state file with exit code;
- fresh controller heartbeat suppresses duplicate wake commands;
- duplicate launch protection works through the `.lock.json` file;
- one-shot status probes do not replace or supersede the durable supervisor owner;
- event log receives fresh `poll` events;
- a deliberately failing check produces `blocked` or alert behavior;
- a passing check marks an item `done`;
- external state can mark an item `done` or `blocked` without duplicate recovery;
- external terminal state emits an immediate `external_terminal_progress_sent` event when progress updates are enabled;
- heartbeat tracking can distinguish `fresh`, `blocked`, and `stale` worker states for at least one supervised item;
- final validation controls the global `complete` state;
- Telegram sends only action-required messages in `ActionRequired` mode.
- If routine progress is enabled, progress text arrives at the requested cadence and stays concise.

## Smoke Test

Run the sample on a copy so the reference file stays unchanged:

```powershell
$tmp = Join-Path $env:TEMP 'watchdog-template-sample.json'
Copy-Item C:\Users\chris\PROJECTS\shared\watchdog-template\examples\sample-backlog.json $tmp -Force
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\chris\PROJECTS\shared\watchdog-template\supervisor-template.ps1 -BacklogPath $tmp -Once
Get-Content $tmp -Raw
```

Expected result: backlog status becomes `complete`, the item status becomes `done`, and a `supervisor-events.jsonl` file appears next to the copied backlog.

## Anti-Patterns

- Do not rely on chat memory.
- Do not use a checklist only in the conversation.
- Do not mark work done without a machine-checkable command or explicit evidence.
- Do not send routine Telegram progress unless the user explicitly asks. If they do ask, use `progress_updates`, keep it brief, and end with the all-caps controller verdict convention above.
- Do not auto-resolve destructive conflicts unless the rule is deterministic and logged.
