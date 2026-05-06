from __future__ import annotations

import json
import subprocess
from pathlib import Path


TEMPLATE_ROOT = Path("C:/Users/chris/PROJECTS/shared/watchdog-template")
SUPERVISOR = TEMPLATE_ROOT / "supervisor-template.ps1"


def _run_supervisor(backlog_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(SUPERVISOR),
            "-BacklogPath",
            str(backlog_path),
            "-Once",
        ],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )


def test_external_closed_state_marks_item_done_without_running_command(tmp_path: Path) -> None:
    state_path = tmp_path / "dialogue-state.json"
    marker_path = tmp_path / "should-not-run.txt"
    backlog_path = tmp_path / "backlog.json"
    state_path.write_text(
        json.dumps(
            {
                "schema": "generic-state-v1",
                "items": {
                    "ITEM-001": {
                        "status": "closed_accepted",
                        "terminal_verdict": "ACCEPT",
                        "conversation_id": "dialogue-123",
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    backlog_path.write_text(
        json.dumps(
            {
                "schema": "durable-watchdog-backlog-v1",
                "project_name": "External State Test",
                "project_root": str(tmp_path),
                "goal": "Prove terminal state prevents duplicate recovery.",
                "status": "running",
                "notification": {"mode": "None", "telegram_bridge": "", "repeat_alert_minutes": 120},
                "supervisor": {
                    "interval_seconds": 300,
                    "max_retries_per_item": 3,
                    "event_log": "events.jsonl",
                    "state_file": "supervisor-state.json",
                },
                "final_validation_command": "exit 0",
                "items": [
                    {
                        "id": "ITEM-001",
                        "description": "Already accepted externally.",
                        "required": True,
                        "status": "pending",
                        "attempts": 0,
                        "run_command": f"Set-Content -LiteralPath '{marker_path}' -Value 'ran'",
                        "check_command": "exit 1",
                        "recover_command": "",
                        "state_tracking": {
                            "enabled": True,
                            "state_file": str(state_path),
                            "status_path": ["items", "ITEM-001", "status"],
                            "done_statuses": ["closed_accepted"],
                            "blocked_statuses": ["rejected", "blocked_needs_human"],
                        },
                        "evidence": [],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    result = _run_supervisor(backlog_path)

    assert result.returncode == 0, result.stderr + result.stdout
    updated = json.loads(backlog_path.read_text(encoding="utf-8"))
    assert updated["status"] == "complete"
    assert updated["items"][0]["status"] == "done"
    assert updated["items"][0]["evidence"][-1]["type"] == "external_state_terminal"
    assert not marker_path.exists()


def test_external_rejected_state_marks_item_blocked(tmp_path: Path) -> None:
    state_path = tmp_path / "dialogue-state.json"
    backlog_path = tmp_path / "backlog.json"
    state_path.write_text(
        json.dumps({"items": {"ITEM-001": {"status": "rejected", "terminal_verdict": "REJECT_P1_INCOMPLETE"}}}),
        encoding="utf-8",
    )
    backlog_path.write_text(
        json.dumps(
            {
                "schema": "durable-watchdog-backlog-v1",
                "project_name": "External Blocked Test",
                "project_root": str(tmp_path),
                "goal": "Prove rejected external state blocks item.",
                "status": "running",
                "notification": {"mode": "None", "telegram_bridge": "", "repeat_alert_minutes": 120},
                "supervisor": {
                    "interval_seconds": 300,
                    "max_retries_per_item": 3,
                    "event_log": "events.jsonl",
                    "state_file": "supervisor-state.json",
                },
                "final_validation_command": "exit 0",
                "items": [
                    {
                        "id": "ITEM-001",
                        "description": "Rejected externally.",
                        "required": True,
                        "status": "pending",
                        "attempts": 0,
                        "run_command": "Write-Output 'should not run'",
                        "check_command": "exit 1",
                        "recover_command": "",
                        "state_tracking": {
                            "enabled": True,
                            "state_file": str(state_path),
                            "status_path": ["items", "ITEM-001", "status"],
                            "done_statuses": ["closed_accepted"],
                            "blocked_statuses": ["rejected"],
                        },
                        "evidence": [],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    result = _run_supervisor(backlog_path)

    assert result.returncode == 0, result.stderr + result.stdout
    updated = json.loads(backlog_path.read_text(encoding="utf-8"))
    assert updated["status"] == "blocked"
    assert updated["items"][0]["status"] == "blocked"
    assert "external state" in updated["items"][0]["last_error"]
