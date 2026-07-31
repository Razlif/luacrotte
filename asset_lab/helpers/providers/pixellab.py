from __future__ import annotations

import base64
import io
import os
import time
from pathlib import Path
from typing import Any

from PIL import Image

from common import append_trace, redact, request_json


STATIC_URL = "https://api.pixellab.ai/v2/create-image-pixflux"
ANIMATION_URL = "https://api.pixellab.ai/v2/animate-with-text-v3"
ROTATIONS_URL = "https://api.pixellab.ai/v2/generate-8-rotations-v3"
JOB_URL = "https://api.pixellab.ai/v2/background-jobs/{job_id}"


def static_payload(
    prompt: str,
    width: int,
    height: int,
    with_background: bool,
    source_image_path: Path | None = None,
    init_image_strength: int | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "description": prompt,
        "image_size": {"width": width, "height": height},
        "no_background": not with_background,
    }
    if source_image_path is not None:
        source = Image.open(source_image_path).convert("RGBA")
        if source.size != (width, height):
            source.thumbnail((width, height), Image.Resampling.LANCZOS)
            fitted = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            fitted.paste(source, ((width - source.width) // 2, (height - source.height) // 2), source)
            buffer = io.BytesIO()
            fitted.save(buffer, format="PNG")
            reference_bytes = buffer.getvalue()
        else:
            reference_bytes = source_image_path.read_bytes()
        encoded = base64.b64encode(reference_bytes).decode("ascii")
        payload["init_image"] = {"type": "base64", "base64": encoded}
        payload["init_image_strength"] = init_image_strength or 500
    return payload


def animation_payload(
    *,
    input_image: Path,
    action: str,
    frame_count: int,
    seed: int | None,
) -> dict[str, Any]:
    base64_image = "data:image/png;base64," + __import__("base64").b64encode(
        input_image.read_bytes()
    ).decode("ascii")
    payload: dict[str, Any] = {
        "action": action,
        "first_frame": {"base64": base64_image},
        "frame_count": frame_count,
        "no_background": True,
    }
    if seed is not None:
        payload["seed"] = seed
    return payload


def redacted_animation_payload(payload: dict[str, Any]) -> dict[str, Any]:
    clean = dict(payload)
    clean["first_frame"] = {"base64": "[base64 omitted]"}
    return clean


def generate_static(
    *,
    api_key: str,
    prompt: str,
    width: int,
    height: int,
    with_background: bool,
    trace_path: Path,
    source_image_path: Path | None = None,
    init_image_strength: int | None = None,
    **_: Any,
) -> dict[str, Any]:
    payload = static_payload(prompt, width, height, with_background, source_image_path, init_image_strength)
    payload_for_log = dict(payload)
    if "init_image" in payload_for_log:
        payload_for_log["init_image"] = {"type": "base64", "base64": "[base64 omitted]"}
    append_trace(
        trace_path,
        "provider_request",
        {"provider": "pixellab", "method": "POST", "url": STATIC_URL, "api_key": redact(api_key), "payload": payload_for_log},
    )
    status, data = request_json(
        "POST",
        STATIC_URL,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        payload=payload,
        timeout=120,
    )
    append_trace(trace_path, "provider_response", {"provider": "pixellab", "status": status, "body_keys": sorted(data.keys())})
    if status >= 400:
        detail = data.get("detail")
        raise RuntimeError(f"PixelLab static generation failed with HTTP {status}: {detail}")

    image = data.get("image", {})
    image_base64 = image.get("base64")
    if not image_base64:
        raise RuntimeError("PixelLab static response did not include image.base64.")
    return {"kind": "image", "image_base64": image_base64, "response": data}


def generate_animation(
    *,
    api_key: str,
    input_image: Path,
    action: str,
    frame_count: int,
    seed: int | None,
    trace_path: Path,
    poll_interval_seconds: int = 3,
    max_poll_attempts: int = 60,
    **_: Any,
) -> dict[str, Any]:
    payload = animation_payload(input_image=input_image, action=action, frame_count=frame_count, seed=seed)
    append_trace(
        trace_path,
        "provider_request",
        {
            "provider": "pixellab",
            "method": "POST",
            "url": ANIMATION_URL,
            "api_key": redact(api_key),
            "payload": redacted_animation_payload(payload),
        },
    )
    status, job = request_json(
        "POST",
        ANIMATION_URL,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        payload=payload,
        timeout=120,
    )
    append_trace(trace_path, "provider_job", {"provider": "pixellab", "status": status, "body_keys": sorted(job.keys())})
    if status >= 400:
        raise RuntimeError(f"PixelLab animation request failed with HTTP {status}.")

    job_id = job.get("background_job_id")
    if not job_id:
        raise RuntimeError("PixelLab animation response did not include background_job_id.")

    result: dict[str, Any] = {}
    for attempt in range(1, max_poll_attempts + 1):
        time.sleep(poll_interval_seconds)
        poll_status, result = request_json(
            "GET",
            JOB_URL.format(job_id=job_id),
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=60,
        )
        append_trace(
            trace_path,
            "provider_poll",
            {"provider": "pixellab", "attempt": attempt, "http_status": poll_status, "job_status": result.get("status")},
        )
        if result.get("status") in {"completed", "failed"}:
            break

    if result.get("status") != "completed":
        raise RuntimeError(f"PixelLab animation job did not complete. Status: {result.get('status')}")

    images = result.get("last_response", {}).get("images", [])
    frame_images_base64 = [image.get("base64") for image in images if image.get("base64")]
    if not frame_images_base64:
        raise RuntimeError("PixelLab animation result did not include frame images.")

    return {
        "kind": "animation",
        "frame_images_base64": frame_images_base64,
        "response": result,
    }


def generate_rotations(
    *,
    api_key: str,
    input_image: Path,
    seed: int | None,
    trace_path: Path,
    poll_interval_seconds: int = 3,
    max_poll_attempts: int = 60,
    **_: Any,
) -> dict[str, Any]:
    source = Image.open(input_image).convert("RGBA")
    source.thumbnail((256, 256), Image.Resampling.LANCZOS)
    fitted = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    fitted.paste(source, ((256 - source.width) // 2, (256 - source.height) // 2), source)
    buffer = io.BytesIO()
    fitted.save(buffer, format="PNG")
    encoded = "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")
    payload: dict[str, Any] = {
        "first_frame": {"base64": encoded},
        "no_background": True,
    }
    if seed is not None:
        payload["seed"] = seed
    append_trace(
        trace_path,
        "provider_request",
        {
            "provider": "pixellab",
            "method": "POST",
            "url": ROTATIONS_URL,
            "api_key": redact(api_key),
            "payload": {**payload, "first_frame": {"base64": "[base64 omitted]"}},
        },
    )
    status, job = request_json(
        "POST",
        ROTATIONS_URL,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        payload=payload,
        timeout=120,
    )
    append_trace(trace_path, "provider_job", {"provider": "pixellab", "status": status, "body_keys": sorted(job.keys())})
    if status >= 400:
        raise RuntimeError(f"PixelLab rotations request failed with HTTP {status}: {job.get('detail')}")
    job_id = job.get("background_job_id")
    if not job_id:
        raise RuntimeError("PixelLab rotations response did not include background_job_id.")

    result: dict[str, Any] = {}
    for attempt in range(1, max_poll_attempts + 1):
        time.sleep(poll_interval_seconds)
        poll_status, result = request_json(
            "GET",
            JOB_URL.format(job_id=job_id),
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=60,
        )
        append_trace(
            trace_path,
            "provider_poll",
            {"provider": "pixellab", "attempt": attempt, "http_status": poll_status, "job_status": result.get("status")},
        )
        if result.get("status") in {"completed", "failed"}:
            break
    if result.get("status") != "completed":
        raise RuntimeError(f"PixelLab rotations job did not complete. Status: {result.get('status')}")
    images = result.get("last_response", {}).get("images", [])
    frame_images_base64 = [image.get("base64") for image in images if image.get("base64")]
    if len(frame_images_base64) != 8:
        raise RuntimeError(f"PixelLab rotations result returned {len(frame_images_base64)} frames; expected 8.")
    return {"kind": "animation", "frame_images_base64": frame_images_base64, "response": result}


def api_key_from_env() -> str:
    key = os.environ.get("PIXELLAB_API_KEY")
    if not key:
        raise RuntimeError("Missing PIXELLAB_API_KEY in .env or environment.")
    return key
