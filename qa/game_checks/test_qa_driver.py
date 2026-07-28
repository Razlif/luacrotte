import json
import tempfile
import unittest
from pathlib import Path

from qa.game_driver.protocol import ProtocolError, validate_command, validate_commands
from qa.game_driver.session import JsonlCursor, append_jsonl, new_run_dir


class QaDriverTests(unittest.TestCase):
    def test_protocol_accepts_supported_command(self) -> None:
        command = validate_command({"id": "a1", "command": "press", "key": "right"})
        self.assertEqual(command["id"], "a1")

    def test_protocol_rejects_unknown_command(self) -> None:
        with self.assertRaises(ProtocolError):
            validate_command({"id": "a1", "command": "teleport"})

    def test_protocol_rejects_invalid_wait_until(self) -> None:
        with self.assertRaises(ProtocolError):
            validate_command({"id": "a1", "command": "wait_until", "timeout": 1})

    def test_protocol_rejects_non_numeric_mouse_click(self) -> None:
        with self.assertRaises(ProtocolError):
            validate_command({"id": "a1", "command": "mouse_click", "x": "10", "y": 20, "button": 1})

    def test_protocol_accepts_recording_commands(self) -> None:
        command = validate_command({"id": "record", "command": "record_start", "name": "cutscene", "fps": 15})
        self.assertEqual(command["name"], "cutscene")
        self.assertEqual(validate_command({"id": "stop", "command": "record_stop"})["command"], "record_stop")

    def test_protocol_rejects_invalid_recording_fps(self) -> None:
        with self.assertRaises(ProtocolError):
            validate_command({"id": "record", "command": "record_start", "fps": 0})

    def test_protocol_rejects_duplicate_command_ids(self) -> None:
        with self.assertRaisesRegex(ProtocolError, "duplicate command id"):
            validate_commands([
                {"id": "a1", "command": "press", "key": "right"},
                {"id": "a1", "command": "release", "key": "right"},
            ])

    def test_jsonl_cursor_reads_only_new_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.jsonl"
            append_jsonl(path, {"id": 1})
            cursor = JsonlCursor(path)
            self.assertEqual(cursor.read_new(), [{"id": 1}])
            self.assertEqual(cursor.read_new(), [])
            append_jsonl(path, {"id": 2})
            self.assertEqual(cursor.read_new(), [{"id": 2}])

    def test_run_directory_has_isolated_artifact_folders(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = new_run_dir(Path(directory), "run-1")
            self.assertTrue((run_dir / "snapshots").is_dir())
            self.assertTrue((run_dir / "screenshots").is_dir())
