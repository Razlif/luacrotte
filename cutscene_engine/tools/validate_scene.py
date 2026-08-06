"""Static validator for declarative Lua cutscene scenes."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENES = ROOT / "cutscene_engine" / "scenes"
MANIFEST = ROOT / "game_data" / "asset_manifest.lua"
COMMANDS = {
    "wait", "move", "ride_trick", "face", "play_animation", "say", "camera_move",
    "camera_follow", "camera_shake", "camera_zoom", "play_effect", "play_sound",
    "play_music", "stop_music", "fade",
}


def validate(scene_id: str) -> list[str]:
    path = SCENES / f"{scene_id}.lua"
    if not path.exists():
        return [f"scene not found: {scene_id}"]
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    for required in ("id", "actors", "timeline"):
        if not re.search(rf"\b{required}\s*=", text):
            errors.append(f"missing scene field: {required}")

    commands = re.findall(r'command\s*=\s*"([^"]+)"', text)
    for command in commands:
        if command not in COMMANDS:
            errors.append(f"unknown command: {command}")

    for raw_duration in re.findall(r"duration\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)", text):
        if float(raw_duration) < 0:
            errors.append(f"negative duration: {raw_duration}")

    manifest_text = MANIFEST.read_text(encoding="utf-8")
    for asset_id in re.findall(r'asset_id\s*=\s*"([^"]+)"', text):
        if not re.search(rf"\b{re.escape(asset_id)}\s*=\s*\{{", manifest_text):
            errors.append(f"asset not found in manifest: {asset_id}")

    actor_block = re.search(r"actors\s*=\s*\{(.*?)\n\s*\},\s*\n\s*timeline", text, re.S)
    actor_ids = set(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{", actor_block.group(1), re.M)) if actor_block else set()
    for actor_id in re.findall(r'actor\s*=\s*"([^"]+)"', text):
        if actor_id not in actor_ids:
            errors.append(f"unknown actor reference: {actor_id}")

    for animation_name in re.findall(r'command\s*=\s*"play_animation".*?name\s*=\s*"([^"]+)"', text, re.S):
        if not re.search(rf'name\s*=\s*"{re.escape(animation_name)}"', manifest_text):
            errors.append(f"animation not found in manifest: {animation_name}")
    for sound_id in re.findall(r'command\s*=\s*"play_sound".*?sound_id\s*=\s*"([^"]+)"', text, re.S):
        if not re.search(rf"\b{re.escape(sound_id)}\s*=\s*\{{", manifest_text):
            errors.append(f"sound not found in manifest: {sound_id}")
    for music_id in re.findall(r'command\s*=\s*"play_music".*?music_id\s*=\s*"([^"]+)"', text, re.S):
        if not re.search(rf"\b{re.escape(music_id)}\s*=\s*\{{", manifest_text):
            errors.append(f"music not found in manifest: {music_id}")
    for raw_value in re.findall(r'(?:volume|pitch)\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)', text):
        if float(raw_value) < 0:
            errors.append(f"negative audio value: {raw_value}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a cutscene scene file.")
    parser.add_argument("scene_id", nargs="?", default="duck_slime_intro")
    args = parser.parse_args()
    errors = validate(args.scene_id)
    if errors:
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"Cutscene valid: {args.scene_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
