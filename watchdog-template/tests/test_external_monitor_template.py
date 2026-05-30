from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import time


TEMPLATE_ROOT = Path(__file__).resolve().parents[1]
EXTERNAL_MONITOR = TEMPLATE_ROOT / "external-monitor-template.ps1"
INSTALLER = TEMPLATE_ROOT / "install-external-monitor-scheduled-task.ps1"


def _run_monitor(backlog_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(EXTERNAL_MONITOR),
            "-BacklogPath",
            str(backlog_path),
            "-Once",
        ],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )


def _write_backlog(
    path: Path,
    project_root: Path,
    *,
    supervisor_script: Path | None = None,
    heartbeat_file: Path | None = None,
    wake_marker: Path | None = None,
    status: str = "running",
) -> None:
    external_monitor: dict[str, object] = {
        "enabled": True,
        "event_log": "external-monitor-events.jsonl",
        "state_file": "external-monitor-state.json",
        "poll_seconds": 300,
        "supervisor_script": str(supervisor_script or TEMPLATE_ROOT / "supervisor-template.ps1"),
    }
    if heartbeat_file is not None:
        external_monitor.update(
            {
                "controller_heartbeat_file": str(heartbeat_file),
                "controller_heartbeat_stale_seconds": 420,
                "wake_cooldown_seconds": 1,
            }
        )
    if wake_marker is not None:
        external_monitor["controller_wake_command"] = (
            f"Set-Content -LiteralPath '{wake_marker}' -Value 'woke'"
        )

    path.write_text(
        json.dumps(
            {
                "schema": "durable-watchdog-backlog-v1",
                "project_name": "External Monitor Test",
                "project_root": str(project_root),
                "goal": "Prove external monitor ownership.",
                "status": status,
                "notification": {"mode": "None", "telegram_bridge": "", "repeat_alert_minutes": 120},
                "external_monitor": external_monitor,
                "supervisor": {
                    "interval_seconds": 300,
                    "max_retries_per_item": 1,
                    "event_log": "supervisor-events.jsonl",
                    "state_file": "supervisor-state.json",
                },
                "final_validation_command": "exit 0",
                "items": [
                    {
                        "id": "ITEM-001",
                        "description": "placeholder",
                        "required": True,
                        "status": "pending",
                        "attempts": 0,
                        "run_command": "Write-Output 'started'",
                        "check_command": "exit 1",
                        "recover_command": "",
                        "evidence": [],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )


def test_external_monitor_starts_missing_supervisor(tmp_path: Path) -> None:
    marker = tmp_path / "supervisor-started.txt"
    fake_supervisor = tmp_path / "fake-supervisor.ps1"
    fake_supervisor.write_text(
        "param([string]$BacklogPath)\n"
        f"Set-Content -LiteralPath '{marker}' -Value $BacklogPath\n",
        encoding="utf-8",
    )
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path, supervisor_script=fake_supervisor)

    result = _run_monitor(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    for _ in range(30):
        if marker.exists():
            break
        time.sleep(0.1)
    assert marker.exists()
    state = json.loads((tmp_path / "external-monitor-state.json").read_text(encoding="utf-8"))
    assert state["supervisor_started"] is True
    events = [
        json.loads(line)
        for line in (tmp_path / "external-monitor-events.jsonl").read_text(encoding="utf-8").splitlines()
    ]
    assert any(event["event"] == "external_monitor_started_supervisor" for event in events)


def test_external_monitor_does_not_start_when_supervisor_lock_pid_is_alive(tmp_path: Path) -> None:
    marker = tmp_path / "supervisor-started.txt"
    fake_supervisor = tmp_path / "fake-supervisor.ps1"
    fake_supervisor.write_text(
        f"Set-Content -LiteralPath '{marker}' -Value 'should-not-start'\n",
        encoding="utf-8",
    )
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path, supervisor_script=fake_supervisor)
    (tmp_path / "backlog.json.lock.json").write_text(
        json.dumps({"pid": os.getpid(), "backlog_path": str(backlog)}),
        encoding="utf-8",
    )

    result = _run_monitor(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    assert not marker.exists()
    state = json.loads((tmp_path / "external-monitor-state.json").read_text(encoding="utf-8"))
    assert state["supervisor_alive"] is True
    assert state["supervisor_started"] is False


def test_external_monitor_wakes_controller_when_heartbeat_is_stale(tmp_path: Path) -> None:
    heartbeat = tmp_path / "controller-heartbeat.json"
    wake_marker = tmp_path / "woke.txt"
    fake_supervisor = tmp_path / "fake-supervisor.ps1"
    fake_supervisor.write_text("param([string]$BacklogPath)\n", encoding="utf-8")
    heartbeat.write_text(
        json.dumps(
            {
                "schema": "agent-heartbeat-v1",
                "updated_at": (datetime.now(timezone.utc) - timedelta(minutes=20)).isoformat(),
                "phase": "old",
                "last_action": "stale",
                "blocked": False,
                "blocked_reason": "",
            }
        ),
        encoding="utf-8",
    )
    backlog = tmp_path / "backlog.json"
    _write_backlog(
        backlog,
        tmp_path,
        supervisor_script=fake_supervisor,
        heartbeat_file=heartbeat,
        wake_marker=wake_marker,
    )

    result = _run_monitor(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    for _ in range(30):
        if wake_marker.exists():
            break
        time.sleep(0.1)
    assert wake_marker.read_text(encoding="utf-8").strip() == "woke"
    state = json.loads((tmp_path / "external-monitor-state.json").read_text(encoding="utf-8"))
    assert state["controller_heartbeat_status"] == "stale"
    assert state["controller_wake_started"] is True
    wake_state_path = Path(state["controller_wake_state_path"])
    for _ in range(30):
        if wake_state_path.exists():
            wake_state = json.loads(wake_state_path.read_text(encoding="utf-8"))
            if wake_state["status"] == "exited":
                break
        time.sleep(0.1)
    wake_state = json.loads(wake_state_path.read_text(encoding="utf-8"))
    assert wake_state["status"] == "exited"
    assert wake_state["exit_code"] == 0
    assert Path(state["controller_wake_log_path"]).exists()


def test_external_monitor_does_not_wake_when_heartbeat_is_fresh(tmp_path: Path) -> None:
    heartbeat = tmp_path / "controller-heartbeat.json"
    wake_marker = tmp_path / "woke.txt"
    fake_supervisor = tmp_path / "fake-supervisor.ps1"
    fake_supervisor.write_text("param([string]$BacklogPath)\n", encoding="utf-8")
    heartbeat.write_text(
        json.dumps(
            {
                "schema": "agent-heartbeat-v1",
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "phase": "active",
                "last_action": "working",
                "blocked": False,
                "blocked_reason": "",
            }
        ),
        encoding="utf-8",
    )
    backlog = tmp_path / "backlog.json"
    _write_backlog(
        backlog,
        tmp_path,
        supervisor_script=fake_supervisor,
        heartbeat_file=heartbeat,
        wake_marker=wake_marker,
    )

    result = _run_monitor(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    assert not wake_marker.exists()
    state = json.loads((tmp_path / "external-monitor-state.json").read_text(encoding="utf-8"))
    assert state["controller_heartbeat_status"] == "fresh"
    assert state["controller_wake_started"] is False


def test_external_monitor_disabled_does_not_start_supervisor_or_wake(tmp_path: Path) -> None:
    marker = tmp_path / "supervisor-started.txt"
    wake_marker = tmp_path / "woke.txt"
    heartbeat = tmp_path / "controller-heartbeat.json"
    fake_supervisor = tmp_path / "fake-supervisor.ps1"
    fake_supervisor.write_text(
        f"Set-Content -LiteralPath '{marker}' -Value 'should-not-start'\n",
        encoding="utf-8",
    )
    heartbeat.write_text(
        json.dumps(
            {
                "schema": "agent-heartbeat-v1",
                "updated_at": (datetime.now(timezone.utc) - timedelta(minutes=20)).isoformat(),
                "blocked": False,
            }
        ),
        encoding="utf-8",
    )
    backlog = tmp_path / "backlog.json"
    _write_backlog(
        backlog,
        tmp_path,
        supervisor_script=fake_supervisor,
        heartbeat_file=heartbeat,
        wake_marker=wake_marker,
    )
    data = json.loads(backlog.read_text(encoding="utf-8"))
    data["external_monitor"]["enabled"] = False
    backlog.write_text(json.dumps(data), encoding="utf-8")

    result = _run_monitor(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    assert not marker.exists()
    assert not wake_marker.exists()
    state = json.loads((tmp_path / "external-monitor-state.json").read_text(encoding="utf-8"))
    assert state["monitor_enabled"] is False
    assert state["controller_heartbeat_status"] == "disabled"


def test_scheduled_task_installer_whatif_outputs_monitor_command(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path)

    result = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(INSTALLER),
            "-BacklogPath",
            str(backlog),
            "-TaskName",
            "Unit Test External Monitor",
            "-IntervalMinutes",
            "2",
            "-WhatIfOnly",
        ],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, result.stderr + result.stdout
    payload = json.loads(result.stdout)
    assert payload["task_name"] == "Unit Test External Monitor"
    assert payload["execute"] == "wscript.exe"
    assert payload["interval_minutes"] == 2
    assert "//B" in payload["arguments"]
    assert payload["hidden_launcher_path"].endswith("unit-test-external-monitor-hidden-launcher.vbs")
    assert str(EXTERNAL_MONITOR) in payload["powershell_command"]
    assert str(backlog) in payload["powershell_command"]
    assert "-Once" in payload["powershell_command"]
    assert "shell.Run" in payload["hidden_launcher_preview"]
    assert ", 0, False" in payload["hidden_launcher_preview"]
