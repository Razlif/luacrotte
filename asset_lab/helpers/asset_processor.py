from __future__ import annotations

from io import BytesIO
from pathlib import Path
from typing import Any

from common import decode_base64_image


def image_metadata(path: Path) -> dict[str, Any]:
    from PIL import Image

    with Image.open(path) as image:
        return {
            "path": str(path),
            "width": image.width,
            "height": image.height,
            "mode": image.mode,
        }


def write_sheet_and_gif(
    *,
    frame_images_base64: list[str],
    sheet_path: Path,
    gif_path: Path,
    fps: int,
) -> dict[str, Any]:
    from PIL import Image

    if not frame_images_base64:
        raise ValueError("No animation frames were returned.")

    frames = [
        Image.open(BytesIO(decode_base64_image(frame))).convert("RGBA")
        for frame in frame_images_base64
    ]
    width, height = frames[0].size
    if any(frame.size != (width, height) for frame in frames):
        raise ValueError("Animation frame sizes do not match.")

    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    gif_path.parent.mkdir(parents=True, exist_ok=True)

    sheet = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * width, 0))
    sheet.save(sheet_path)

    duration_ms = max(1, round(1000 / max(1, fps)))
    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
    )

    return {
        "frame_count": len(frames),
        "frame_width": width,
        "frame_height": height,
        "sheet_width": sheet.width,
        "sheet_height": sheet.height,
        "fps": fps,
    }


def write_gif_from_sheet(*, sheet_path: Path, gif_path: Path, frame_count: int, frame_width: int, frame_height: int, columns: int, fps: int) -> dict[str, Any]:
    from PIL import Image

    with Image.open(sheet_path) as sheet:
        frames = []
        for index in range(frame_count):
            x = (index % columns) * frame_width
            y = (index // columns) * frame_height
            frames.append(sheet.crop((x, y, x + frame_width, y + frame_height)).convert("RGBA"))
    if not frames:
        raise ValueError("AutoSprite sheet contains no frames.")
    gif_path.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(gif_path, save_all=True, append_images=frames[1:], duration=max(1, round(1000 / max(1, fps))), loop=0, disposal=2)
    return {"frame_count": frame_count, "frame_width": frame_width, "frame_height": frame_height, "fps": fps}
