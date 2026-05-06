from __future__ import annotations

from datetime import datetime, timezone
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import subprocess
from threading import Thread
from pathlib import Path


TEMPLATE_ROOT = Path(__file__).resolve().parents[1]
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


def _capture_server() -> tuple[ThreadingHTTPServer, list[str]]:
    received: list[str] = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            received.append(str(payload.get("text", "")))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"{}")

        def log_message(self, format: str, *args: object) -> None:
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, received


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


def test_external_terminal_state_sends_immediate_progress_update(tmp_path: Path) -> None:
    server, received = _capture_server()
    try:
        state_path = tmp_path / "dialogue-state.json"
        backlog_path = tmp_path / "backlog.json"
        event_log = tmp_path / "events.jsonl"
        state_path.write_text(
            json.dumps(
                {
                    "items": {
                        "ITEM-001": {
                            "status": "closed_accepted",
                            "terminal_verdict": "ACCEPT",
                            "conversation_id": "dialogue-123",
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        backlog_path.write_text(
            json.dumps(
                {
                    "schema": "durable-watchdog-backlog-v1",
                    "project_name": "Immediate Terminal Test",
                    "project_root": str(tmp_path),
                    "goal": "Prove terminal external state is visible immediately.",
                    "status": "running",
                    "notification": {
                        "mode": "ActionRequired",
                        "telegram_bridge": f"http://127.0.0.1:{server.server_port}/send",
                        "repeat_alert_minutes": 120,
                    },
                    "progress_updates": {
                        "enabled": True,
                        "interval_seconds": 900,
                        "summary_command": "Write-Output 'periodic only'",
                        "state_file": "progress-state.json",
                        "external_terminal_updates": True,
                    },
                    "supervisor": {
                        "interval_seconds": 300,
                        "max_retries_per_item": 3,
                        "event_log": str(event_log),
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
        assert any(
            "ITEM-001 reached external terminal state closed_accepted" in text
            for text in received
        )
        events = [json.loads(line) for line in event_log.read_text(encoding="utf-8").splitlines()]
        assert any(event["event"] == "external_terminal_progress_sent" for event in events)
    finally:
        server.shutdown()


def test_fresh_agent_heartbeat_keeps_item_running_without_duplicate_launch(tmp_path: Path) -> None:
    heartbeat_path = tmp_path / "agent-heartbeat.json"
    marker_path = tmp_path / "should-not-run.txt"
    backlog_path = tmp_path / "backlog.json"
    heartbeat_path.write_text(
        json.dumps(
            {
                "schema": "agora-agent-heartbeat-v1",
                "link_id": "link-worker",
                "agent_role": "coder",
                "gap_id": "ITEM-001",
                "phase": "running_tests",
                "last_action": "Running targeted tests.",
                "blocked": False,
                "blocked_reason": "",
                "updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        ),
        encoding="utf-8",
    )
    backlog_path.write_text(
        json.dumps(
            {
                "schema": "durable-watchdog-backlog-v1",
                "project_name": "Heartbeat Fresh Test",
                "project_root": str(tmp_path),
                "goal": "Fresh worker heartbeat suppresses duplicate launch.",
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
                        "description": "Worker is already active.",
                        "required": True,
                        "status": "running",
                        "attempts": 1,
                        "run_command": f"Set-Content -LiteralPath '{marker_path}' -Value 'ran'",
                        "check_command": "exit 1",
                        "recover_command": "",
                        "heartbeat_tracking": {
                            "enabled": True,
                            "heartbeat_file": str(heartbeat_path),
                            "stale_after_seconds": 300,
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
    assert updated["status"] == "running"
    assert updated["items"][0]["status"] == "running"
    assert updated["items"][0]["last_heartbeat_phase"] == "running_tests"
    assert not marker_path.exists()
    events = [json.loads(line) for line in (tmp_path / "events.jsonl").read_text(encoding="utf-8").splitlines()]
    assert any(event["event"] == "heartbeat_fresh" for event in events)


def test_blocked_agent_heartbeat_marks_item_blocked(tmp_path: Path) -> None:
    heartbeat_path = tmp_path / "agent-heartbeat.json"
    backlog_path = tmp_path / "backlog.json"
    heartbeat_path.write_text(
        json.dumps(
            {
                "schema": "agora-agent-heartbeat-v1",
                "link_id": "link-worker",
                "agent_role": "validator",
                "gap_id": "ITEM-001",
                "phase": "blocked",
                "last_action": "Cannot read the diff.",
                "blocked": True,
                "blocked_reason": "diff file missing",
                "updated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        ),
        encoding="utf-8",
    )
    backlog_path.write_text(
        json.dumps(
            {
                "schema": "durable-watchdog-backlog-v1",
                "project_name": "Heartbeat Blocked Test",
                "project_root": str(tmp_path),
                "goal": "Blocked worker heartbeat blocks item.",
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
                        "description": "Worker reports blocked.",
                        "required": True,
                        "status": "running",
                        "attempts": 1,
                        "run_command": "Write-Output 'should not run'",
                        "check_command": "exit 1",
                        "recover_command": "",
                        "heartbeat_tracking": {
                            "enabled": True,
                            "heartbeat_file": str(heartbeat_path),
                            "stale_after_seconds": 300,
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
    assert "diff file missing" in updated["items"][0]["last_error"]
    assert updated["items"][0]["evidence"][-1]["type"] == "agent_heartbeat_blocked"
