"""Behavioral coverage for file-tool checkpoint path resolution."""

from types import SimpleNamespace
from pathlib import PurePosixPath

from agent.tool_executor import _ensure_file_checkpoint
from tools.checkpoint_manager import CheckpointManager


def test_relative_file_checkpoint_uses_task_workspace(tmp_path, monkeypatch):
    """Checkpoint lookup must use the same cwd as a relative file mutation."""
    process_cwd = tmp_path / "opt" / "hermes"
    workspace_cwd = tmp_path / "opt" / "data" / "workspace"
    process_cwd.mkdir(parents=True)
    workspace_cwd.mkdir(parents=True)

    # Both directories contain content so checkpointing the wrong one would
    # still succeed and remain observable as the regression did in Docker.
    (process_cwd / "pyproject.toml").write_text("[project]\nname = 'hermes'\n")
    (workspace_cwd / "pyproject.toml").write_text("[project]\nname = 'workspace'\n")
    (workspace_cwd / "existing.txt").write_text("before\n")

    monkeypatch.chdir(process_cwd)
    monkeypatch.setenv("TERMINAL_CWD", str(workspace_cwd))
    monkeypatch.setattr(
        "tools.checkpoint_manager.CHECKPOINT_BASE",
        tmp_path / "checkpoints",
    )

    manager = CheckpointManager(enabled=True)
    agent = SimpleNamespace(_checkpoint_mgr=manager)

    _ensure_file_checkpoint(
        agent,
        "write_file",
        {"path": "test_permissions2.txt"},
        "gateway-session",
    )

    assert manager.list_checkpoints(str(workspace_cwd))
    assert manager.list_checkpoints(str(process_cwd)) == []


def test_docker_file_checkpoint_maps_explicit_workspace_bind(tmp_path, monkeypatch):
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "existing.txt").write_text("before\n")

    monkeypatch.setattr(
        "tools.checkpoint_manager.CHECKPOINT_BASE",
        tmp_path / "checkpoints",
    )
    monkeypatch.setattr(
        "tools.file_tools._resolve_path_for_task",
        lambda path, task_id: PurePosixPath("/workspace/new.txt"),
    )
    monkeypatch.setattr(
        "tools.terminal_tool._get_env_config",
        lambda: {
            "env_type": "docker",
            "docker_volumes": [f"{workspace}:/workspace"],
        },
    )

    manager = CheckpointManager(enabled=True)
    agent = SimpleNamespace(_checkpoint_mgr=manager)
    _ensure_file_checkpoint(agent, "write_file", {"path": "/workspace/new.txt"}, "task")

    assert manager.list_checkpoints(str(workspace))
    assert manager.list_checkpoints("/workspace") == []
