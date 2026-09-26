"""Authenticated, intentionally narrow machine recognition endpoint."""

from __future__ import annotations

import base64
import json
import os
import re
import time
from collections import defaultdict, deque
from pathlib import Path

import httpx
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from pydantic import BaseModel

CATALOG = json.loads((Path(__file__).resolve().parent.parent / "catalog" / "exercises.json").read_text(encoding="utf-8"))
CATALOG_IDS = {item["id"] for item in CATALOG}
MAX_IMAGE_BYTES = 4 * 1024 * 1024
RATE_LIMIT = 20
REQUESTS: dict[str, deque[float]] = defaultdict(deque)
app = FastAPI(title="Athlete OS Machine Scan", docs_url=None, redoc_url=None)


class ScanResult(BaseModel):
    exercise_ids: list[str]


def valid_candidates(raw: str) -> list[str]:
    """Never return an exercise that is absent from the shared catalog."""
    match = re.search(r"\{[\s\S]*\}", raw)
    if not match:
        return []
    try:
        value = json.loads(match.group(0))
    except json.JSONDecodeError:
        return []
    ids = value.get("exercise_ids") if isinstance(value, dict) else None
    if not isinstance(ids, list):
        return []
    result: list[str] = []
    for candidate in ids:
        if isinstance(candidate, str) and candidate in CATALOG_IDS and candidate not in result:
            result.append(candidate)
        if len(result) == 3:
            break
    return result


async def authenticate(token: str, client: httpx.AsyncClient) -> str:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
    if not url or not key:
        raise HTTPException(503, "Authentication is not configured")
    try:
        response = await client.get(f"{url}/auth/v1/user", headers={
            "apikey": key, "Authorization": f"Bearer {token}"}, timeout=10)
    except httpx.HTTPError as exc:
        raise HTTPException(503, "Authentication unavailable") from exc
    if response.status_code != 200:
        raise HTTPException(401, "Invalid session")
    user_id = response.json().get("id")
    if not isinstance(user_id, str) or not user_id:
        raise HTTPException(401, "Invalid session")
    return user_id


def apply_rate_limit(user_id: str) -> None:
    now = time.monotonic()
    times = REQUESTS[user_id]
    while times and now - times[0] > 86400:
        times.popleft()
    if len(times) >= RATE_LIMIT:
        raise HTTPException(429, "Daily scan limit reached")
    times.append(now)


@app.post("/v1/machine-scan", response_model=ScanResult)
async def machine_scan(photo: UploadFile = File(...), authorization: str | None = Header(default=None)) -> ScanResult:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Authentication required")
    image = await photo.read(MAX_IMAGE_BYTES + 1)
    await photo.close()
    if not image or len(image) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Image must be smaller than 4 MB")
    if image.startswith(b"\xff\xd8\xff"):
        mime = "image/jpeg"
    elif image.startswith(b"\x89PNG\r\n\x1a\n"):
        mime = "image/png"
    elif image.startswith(b"RIFF") and image[8:12] == b"WEBP":
        mime = "image/webp"
    else:
        raise HTTPException(415, "JPEG, PNG or WebP required")
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise HTTPException(503, "Vision provider is not configured")
    async with httpx.AsyncClient() as client:
        user_id = await authenticate(authorization[7:], client)
        apply_rate_limit(user_id)
        image_url = f"data:{mime};base64,{base64.b64encode(image).decode()}"
        prompt = (
            "Identify the exercise machine in the photo. Reply with JSON only: "
            '{"exercise_ids": ["catalog_id"]}. Return up to 3 plausible IDs in best-first order. '
            "If the machine cannot be identified, return an empty list. Do not guess. "
            "Available catalog: " + json.dumps(CATALOG, ensure_ascii=False)
        )
        try:
            response = await client.post("https://api.openai.com/v1/responses", headers={
                "Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
                json={"model": os.environ.get("OPENAI_VISION_MODEL", "gpt-4o-mini"),
                    "store": False, "input": [{"role": "user", "content": [
                        {"type": "input_text", "text": prompt},
                        {"type": "input_image", "image_url": image_url, "detail": "low"}]}]},
                timeout=25)
        except httpx.HTTPError as exc:
            raise HTTPException(503, "Vision provider unavailable") from exc
    if response.status_code != 200:
        raise HTTPException(503, "Vision provider unavailable")
    payload = response.json()
    texts = [part.get("text", "") for output in payload.get("output", [])
             for part in output.get("content", []) if part.get("type") == "output_text"]
    return ScanResult(exercise_ids=valid_candidates("\n".join(texts)))
