"""Lotus.ai Cortex — wellness screening session gateway (Phase 2 API; Phase 1 embed URL)."""

from __future__ import annotations

import os
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException, Query

router = APIRouter(prefix="/v1/health", tags=["Wellness"])

LOTUS_KEY = (os.environ.get("LOTUS_CORTEX_API_KEY") or "").strip()
LOTUS_API_URL = (os.environ.get("LOTUS_CORTEX_API_BASE_URL") or "").strip().rstrip("/")
LOTUS_WEB_FALLBACK = (os.environ.get("LOTUS_CORTEX_WEB_BASE_URL") or "https://lotus.ai/cortex/auth").strip()


def _verify_middleware_api_key(x_api_key: str | None) -> None:
    expected = (os.environ.get("ROUTE_OPTIMIZATION_API_KEY") or "").strip()
    if expected and (not x_api_key or x_api_key.strip() != expected):
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key")


@router.post("/screening-session")
async def initiate_cortex_session(
    driver_id: str = Query(..., min_length=1, description="Supabase auth user UUID"),
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> dict[str, Any]:
    """
    Creates a short-lived Lotus Cortex session for the iOS WKWebView embed.
    Secrets stay on the server (.env); the app only receives embed_url + expires_at.
    """
    _verify_middleware_api_key(x_api_key)

    if not LOTUS_KEY or not LOTUS_API_URL:
        # Phase 1 fallback: web embed without server-side Lotus contract yet
        return {
            "embed_url": f"{LOTUS_WEB_FALLBACK}?driver={driver_id}",
            "session_token": None,
            "expires_at": None,
            "source": "web_fallback",
            "configured": False,
        }

    payload = {
        "driver_id": driver_id,
        "app_context": "TruckerEasy_Fleet",
    }
    headers = {
        "Authorization": f"Bearer {LOTUS_KEY}",
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{LOTUS_API_URL}/sessions",
                json=payload,
                headers=headers,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Lotus API unreachable: {exc}") from exc

    if response.status_code >= 400:
        raise HTTPException(
            status_code=response.status_code,
            detail=f"Lotus API error: {response.text[:500]}",
        )

    data = response.json()
    embed_url = (
        data.get("embed_url")
        or data.get("url")
        or f"{LOTUS_WEB_FALLBACK}?driver={driver_id}&session={data.get('session_token', '')}"
    )
    return {
        "embed_url": embed_url,
        "session_token": data.get("session_token") or data.get("token"),
        "expires_at": data.get("expires_at"),
        "source": "lotus_api",
        "configured": True,
    }
