from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Any

from common import append_trace, redact, request_json


ACCOUNT_URL = "https://www.autosprite.io/api/v1/account"
CHARACTERS_URL = "https://www.autosprite.io/api/v1/characters"
JOBS_URL = "https://www.autosprite.io/api/v1/jobs/{job_id}"
SPRITESHEETS_URL = "https://www.autosprite.io/api/v1/characters/{character_id}/spritesheets"
SPRITESHEET_URL = "https://www.autosprite.io/api/v1/spritesheets/{spritesheet_id}"


def api_key_from_env() -> str:
    key = os.environ.get("AUTOSPRITE_API_KEY")
    if not key:
        raise RuntimeError("Missing AUTOSPRITE_API_KEY in .env or environment.")
    return key


def check_account(*, api_key: str, trace_path: Path) -> dict[str, Any]:
    append_trace(
        trace_path,
        "provider_request",
        {"provider": "autosprite", "method": "GET", "url": ACCOUNT_URL, "api_key": redact(api_key)},
    )
    status, data = request_json("GET", ACCOUNT_URL, headers={"x-api-key": api_key}, timeout=30)
    append_trace(trace_path, "provider_response", {"provider": "autosprite", "status": status, "body_keys": sorted(data.keys())})
    if status >= 400:
        raise RuntimeError(f"AutoSprite account check failed with HTTP {status}.")
    return data


def create_character_from_image(
    *,
    api_key: str,
    name: str,
    image_path: Path,
    character_description: str,
    is_humanoid: bool,
    trace_path: Path,
) -> dict[str, Any]:
    import mimetypes
    import uuid

    if not image_path.exists():
        raise FileNotFoundError(f"AutoSprite source image missing: {image_path}")

    boundary = f"----assetlab{uuid.uuid4().hex}"
    mime_type = mimetypes.guess_type(image_path.name)[0] or "image/png"
    fields = {
        "name": name,
        "characterDescription": character_description,
        "isHumanoid": "true" if is_humanoid else "false",
    }

    parts: list[bytes] = []
    for key, value in fields.items():
        parts.append(f"--{boundary}\r\n".encode("utf-8"))
        parts.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"))
        parts.append(str(value).encode("utf-8"))
        parts.append(b"\r\n")
    parts.append(f"--{boundary}\r\n".encode("utf-8"))
    parts.append(
        f'Content-Disposition: form-data; name="image"; filename="{image_path.name}"\r\n'
        f"Content-Type: {mime_type}\r\n\r\n".encode("utf-8")
    )
    parts.append(image_path.read_bytes())
    parts.append(b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    body = b"".join(parts)

    headers = {
        "x-api-key": api_key,
        "Content-Type": f"multipart/form-data; boundary={boundary}",
    }
    append_trace(
        trace_path,
        "provider_request",
        {
            "provider": "autosprite",
            "method": "POST",
            "url": CHARACTERS_URL,
            "api_key": redact(api_key),
            "fields": {**fields, "image": str(image_path)},
        },
    )

    import json
    import urllib.error
    import urllib.request

    req = urllib.request.Request(CHARACTERS_URL, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            raw = response.read().decode("utf-8")
            data = json.loads(raw) if raw else {}
            status = response.status
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {"raw": raw}
        status = exc.code

    append_trace(trace_path, "provider_response", {"provider": "autosprite", "status": status, "body_keys": sorted(data.keys())})
    if status >= 400:
        raise RuntimeError(f"AutoSprite character upload failed with HTTP {status}: {data.get('error', data.get('message', data.get('code')))}")
    if not data.get("id"):
        raise RuntimeError("AutoSprite character upload response did not include id.")
    return data


def generate_spritesheet(
    *,
    api_key: str,
    character_id: str,
    animation_name: str,
    prompt: str,
    video_tier: str,
    duration_sec: int,
    frame_count: int,
    frame_size: int,
    remove_bg: str,
    trace_path: Path,
    poll_interval_seconds: int = 5,
    max_poll_attempts: int = 72,
) -> dict[str, Any]:
    payload = {
        "animations": [{"kind": "custom", "name": animation_name, "prompt": prompt}],
        "videoTier": video_tier,
        "durationSec": duration_sec,
        "frameCount": frame_count,
        "frameSize": frame_size,
        "withSound": False,
        "removeBg": remove_bg,
    }
    append_trace(trace_path, "provider_request", {
        "provider": "autosprite",
        "method": "POST",
        "url": SPRITESHEETS_URL.format(character_id=character_id),
        "api_key": redact(api_key),
        "payload": payload,
        "character_id": character_id,
    })
    status, data = request_json(
        "POST",
        SPRITESHEETS_URL.format(character_id=character_id),
        headers={"x-api-key": api_key, "Content-Type": "application/json"},
        payload=payload,
        timeout=120,
    )
    append_trace(trace_path, "provider_response", {"provider": "autosprite", "status": status, "body_keys": sorted(data.keys())})
    if status >= 400:
        raise RuntimeError(f"AutoSprite spritesheet request failed with HTTP {status}: {data.get('error', data.get('message'))}")
    workflows = data.get("workflows", [])
    if not workflows or not workflows[0].get("jobId"):
        raise RuntimeError("AutoSprite spritesheet response did not include a workflow jobId.")
    job_id = workflows[0]["jobId"]
    append_trace(trace_path, "provider_job", {"provider": "autosprite", "job_id": job_id, "status": "queued"})

    result: dict[str, Any] = {}
    for attempt in range(1, max_poll_attempts + 1):
        time.sleep(poll_interval_seconds)
        poll_status, result = request_json(
            "GET",
            JOBS_URL.format(job_id=job_id),
            headers={"x-api-key": api_key},
            timeout=60,
        )
        append_trace(trace_path, "provider_poll", {"provider": "autosprite", "job_id": job_id, "attempt": attempt, "http_status": poll_status, "job_status": result.get("status")})
        if result.get("status") in {"succeeded", "completed", "failed", "error"}:
            break
    if result.get("status") not in {"succeeded", "completed"}:
        raise RuntimeError(f"AutoSprite spritesheet job did not complete: {result.get('status')}")

    spritesheet_id = result.get("spritesheetId") or result.get("spritesheet_id")
    nested = result.get("result", {}) if isinstance(result.get("result"), dict) else {}
    spritesheet_id = spritesheet_id or nested.get("spritesheetId") or nested.get("spritesheet_id")
    if not spritesheet_id:
        raise RuntimeError("AutoSprite job completed without a spritesheet ID.")
    detail_status, detail = request_json(
        "GET",
        SPRITESHEET_URL.format(spritesheet_id=spritesheet_id),
        headers={"x-api-key": api_key},
        timeout=60,
    )
    if detail_status >= 400:
        raise RuntimeError(f"AutoSprite spritesheet lookup failed with HTTP {detail_status}.")
    append_trace(trace_path, "spritesheet_detail", {"provider": "autosprite", "spritesheet_id": spritesheet_id, "status": detail.get("status")})
    return {"job_id": job_id, "spritesheet_id": spritesheet_id, "detail": detail, "credits_used": data.get("creditsUsed")}


def download_file(*, url: str, destination: Path, api_key: str) -> None:
    import urllib.request

    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"x-api-key": api_key})
    with urllib.request.urlopen(request, timeout=120) as response:
        destination.write_bytes(response.read())


def generate_static(**_: Any) -> dict[str, Any]:
    raise NotImplementedError("AutoSprite generation is not implemented in the Asset Lab creator yet.")


def generate_animation(**_: Any) -> dict[str, Any]:
    raise NotImplementedError("AutoSprite animation is not implemented in the Asset Lab creator yet.")
