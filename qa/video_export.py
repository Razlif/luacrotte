"""Export a QA recording's PNG frames to GIF or MP4."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - exercised through the CLI error path
    Image = None


ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "qa" / "runtime_logs"


def read_recording(run_dir: Path) -> tuple[str, float, list[dict]]:
    path = run_dir / "video" / "video_manifest.jsonl"
    if not path.is_file():
        raise SystemExit(f"Recording metadata is missing: {path}")
    name = "qa_recording"
    fps = 30.0
    frames: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        if record.get("event") == "recording_started":
            name = str(record.get("name") or name)
            fps = float(record.get("fps") or fps)
        elif record.get("event") == "frame" and record.get("saved"):
            frames.append(record)
    if not frames:
        raise SystemExit("Recording contains no saved frames")
    return name, fps, frames


def export_gif(run_dir: Path, name: str, fps: float, frames: list[dict], width: int | None = None) -> tuple[Path, tuple[int, int]]:
    if Image is None:
        raise SystemExit("GIF export requires Pillow in the configured Python environment")
    images = []
    for record in frames:
        image_path = run_dir / "video" / record["file"]
        with Image.open(image_path) as source:
            image = source.convert("RGB")
            if width and image.width != width:
                height = round(image.height * width / image.width)
                image = image.resize((width, height), Image.Resampling.LANCZOS)
            images.append(image)
    output = run_dir / "video" / f"{name}.gif"
    images[0].save(
        output,
        save_all=True,
        append_images=images[1:],
        duration=max(1, round(1000 / fps)),
        loop=0,
        optimize=True,
    )
    for image in images:
        image.close()
    return output, images[0].size


def export_mp4(run_dir: Path, name: str, fps: float) -> Path:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("MP4 export requires ffmpeg; GIF export remains available")
    output = run_dir / "video" / f"{name}.mp4"
    command = [
        ffmpeg,
        "-y",
        "-framerate",
        str(fps),
        "-i",
        str(run_dir / "video" / "frames" / "frame_%06d.png"),
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(output),
    ]
    subprocess.run(command, check=True)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_id")
    parser.add_argument("--format", choices=("gif", "mp4"), action="append", dest="formats", required=True)
    parser.add_argument("--preview", action="store_true", help="Export GIF previews at 480px wide")
    parser.add_argument("--width", type=int, help="Resize GIF output to this width")
    args = parser.parse_args()
    run_dir = RUNS / args.run_id
    if not run_dir.is_dir():
        raise SystemExit(f"Unknown QA run: {run_dir}")
    name, fps, frames = read_recording(run_dir)
    outputs = []
    output_size = None
    gif_width = args.width or (480 if args.preview else None)
    for output_format in dict.fromkeys(args.formats):
        if output_format == "gif":
            output_name = f"{name}_preview" if gif_width else name
            output, output_size = export_gif(run_dir, output_name, fps, frames, gif_width)
            outputs.append(output)
        else:
            outputs.append(export_mp4(run_dir, name, fps))
    summary = {
        "run_id": args.run_id,
        "name": name,
        "fps": fps,
        "frame_count": len(frames),
        "size": output_size,
        "outputs": [str(path) for path in outputs],
    }
    (run_dir / "video" / "export_manifest.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
