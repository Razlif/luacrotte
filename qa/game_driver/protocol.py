"""Validation helpers for the Love2D QA command protocol."""

from __future__ import annotations

from typing import Any


COMMANDS = {
    "press",
    "release",
    "hold",
    "mouse_click",
    "wait",
    "wait_until",
    "snapshot",
    "assert",
    "pause",
    "run_cutscene",
    "record_start",
    "record_stop",
}

PROTOCOL_VERSION = 1


class ProtocolError(ValueError):
    """Raised when a QA command is malformed or unsupported."""


def validate_command(command: Any) -> dict[str, Any]:
    if not isinstance(command, dict):
        raise ProtocolError("command must be an object")
    action_id = command.get("id")
    name = command.get("command")
    if not isinstance(action_id, str) or not action_id:
        raise ProtocolError("command requires a non-empty string id")
    if name not in COMMANDS:
        raise ProtocolError(f"unknown command: {name}")
    if name in {"press", "release", "hold"} and not isinstance(command.get("key"), str):
        raise ProtocolError(f"{name} requires key")
    if name == "hold" and (not isinstance(command.get("duration"), (int, float)) or command["duration"] < 0):
        raise ProtocolError("hold duration must be non-negative")
    if name == "wait" and (not isinstance(command.get("seconds"), (int, float)) or command["seconds"] < 0):
        raise ProtocolError("wait seconds must be non-negative")
    if name == "wait_until":
        if not isinstance(command.get("condition"), dict):
            raise ProtocolError("wait_until requires condition")
        if not isinstance(command.get("timeout", 0), (int, float)) or command["timeout"] < 0:
            raise ProtocolError("wait_until timeout must be non-negative")
    if name == "assert" and not isinstance(command.get("condition"), dict):
        raise ProtocolError("assert requires condition")
    if name == "mouse_click":
        for field in ("x", "y", "button"):
            if field not in command:
                raise ProtocolError(f"mouse_click requires {field}")
        if not all(isinstance(command[field], (int, float)) for field in ("x", "y", "button")):
            raise ProtocolError("mouse_click coordinates and button must be numeric")
    if name == "snapshot" and command.get("name") is not None and not isinstance(command["name"], str):
        raise ProtocolError("snapshot name must be a string")
    if name == "run_cutscene" and not isinstance(command.get("scene"), str):
        raise ProtocolError("run_cutscene requires scene")
    if name == "record_start":
        if command.get("name") is not None and not isinstance(command["name"], str):
            raise ProtocolError("record_start name must be a string")
        if command.get("fps") is not None and (not isinstance(command["fps"], (int, float)) or command["fps"] <= 0):
            raise ProtocolError("record_start fps must be positive")
    return command


def validate_commands(commands: list[Any]) -> list[dict[str, Any]]:
    """Validate a command sequence and reject duplicate action IDs."""

    validated = []
    seen_ids: set[str] = set()
    for command in commands:
        validated_command = validate_command(command)
        action_id = validated_command["id"]
        if action_id in seen_ids:
            raise ProtocolError(f"duplicate command id: {action_id}")
        seen_ids.add(action_id)
        validated.append(validated_command)
    return validated
