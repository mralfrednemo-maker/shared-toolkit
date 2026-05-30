from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess


TEMPLATE_ROOT = Path(__file__).resolve().parents[1]
RALPH_OBSERVER = TEMPLATE_ROOT / "ralph-observer-template.ps1"


def _run_observer(backlog_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(RALPH_OBSERVER),
            "-BacklogPath",
            str(backlog_path),
            "-Once",
        ],
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )


def _write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


def _write_backlog(
    path: Path,
    project_root: Path,
    *,
    enabled: bool = True,
    loop_status: str = "ready_for_guru_loop",
    heartbeat_age_minutes: int = 1,
    active_guru_url: str = "https://chatgpt.com/c/example",
) -> tuple[Path, Path, Path]:
    loop_state = project_root / "orchestrator-loop-state.json"
    heartbeat = project_root / "orchestrator-heartbeat.json"
    counters = project_root / "orchestration-loop-counters.json"

    _write_json(loop_state, {"schema": "loop-state-v1", "status": loop_status})
    _write_json(
        heartbeat,
        {
            "schema": "heartbeat-v1",
            "updated_at": (datetime.now(timezone.utc) - timedelta(minutes=heartbeat_age_minutes)).isoformat(),
            "blocked": False,
            "blocked_reason": "",
        },
    )
    _write_json(counters, {"schema": "counters-v1", "active_guru_url": active_guru_url})

    _write_json(
        path,
        {
            "schema": "durable-watchdog-backlog-v1",
            "project_name": "Ralph Observer Test",
            "project_root": str(project_root),
            "goal": "Observe only.",
            "status": "running",
            "ralph_observer": {
                "enabled": enabled,
                "poll_seconds": 300,
                "event_log": "ralph-observer-events.jsonl",
                "state_file": "ralph-observer-state.json",
                "loop_state_file": str(loop_state),
                "controller_heartbeat_file": str(heartbeat),
                "controller_heartbeat_stale_seconds": 420,
                "authority_counter_file": str(counters),
                "active_guru_url_required": True,
                "final_keyword": "FULL_WORKING_CODE_DELIVERED",
            },
            "items": [],
        },
    )
    return loop_state, heartbeat, counters


def _read_state(root: Path) -> dict[str, object]:
    return json.loads((root / "ralph-observer-state.json").read_text(encoding="utf-8"))


def test_ralph_observer_disabled_takes_no_action(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path, enabled=False, heartbeat_age_minutes=20)

    result = _run_observer(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    state = _read_state(tmp_path)
    assert state["observer_enabled"] is False
    assert state["status"] == "PASSIVE_OBSERVER_DISABLED"
    assert state["action_taken"] == "none"
    assert "codex_launch" in state["forbidden_actions_confirmed"]


def test_ralph_observer_reports_healthy_without_wake(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path, loop_status="ready_for_guru_loop", heartbeat_age_minutes=1)

    result = _run_observer(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    state = _read_state(tmp_path)
    assert state["status"] == "PASSIVE_OBSERVER_HEALTHY"
    assert state["action_required"] is False
    assert state["terminal"] is False
    assert state["action_taken"] == "none"


def test_ralph_observer_reports_stale_heartbeat_action_required(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path, loop_status="ready_for_guru_loop", heartbeat_age_minutes=20)

    result = _run_observer(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    state = _read_state(tmp_path)
    assert state["status"] == "ACTION_REQUIRED: HEARTBEAT_STALE"
    assert state["action_required"] is True
    assert state["terminal"] is False
    assert state["action_taken"] == "none"


def test_ralph_observer_stops_on_configured_final_status(tmp_path: Path) -> None:
    backlog = tmp_path / "backlog.json"
    _write_backlog(backlog, tmp_path, loop_status="final_delivery_keyword_seen", heartbeat_age_minutes=1)

    result = _run_observer(backlog)

    assert result.returncode == 0, result.stderr + result.stdout
    state = _read_state(tmp_path)
    assert state["status"] == "STOP_GURU_INTERACTION_FINAL_DELIVERY_RECORDED"
    assert state["terminal"] is True
    assert state["action_required"] is False
    assert state["action_taken"] == "none"
