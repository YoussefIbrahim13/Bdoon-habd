"""بدون هبد! (Bedoon Habd) backend — country data + on-demand Smart Judge fact checking.

Run locally:
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import logging
import os
import secrets
import time
from contextlib import asynccontextmanager
from typing import Any, Literal

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .auth import router as auth_router
from .countries import fact_sheet, find_country, load_countries
from .db import init_db
from .verifier import SmartJudge

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

RATE_LIMIT_PER_MINUTE = 20
# Server-wide ceiling on Groq-backed calls across ALL clients — the backstop
# that protects the Groq free-tier quota even against many-IP abuse. Sized for
# a real party game (a round rarely needs more than a few checks) with room
# for several simultaneous games.
GLOBAL_VERIFY_PER_MINUTE = 60
# Bounds for the in-memory stores so a long-lived instance can't grow forever.
VERDICT_CACHE_MAX = 1024
RATE_BUCKETS_MAX_IPS = 5000

# Shared secret the app sends as X-App-Token. Not real auth (an APK can be
# decompiled), but it stops drive-by scripts from burning the Groq quota.
# Empty/unset = enforcement off, so local dev and old builds keep working.
APP_TOKEN = os.environ.get("APP_TOKEN", "").strip()


class VerifyRequest(BaseModel):
    country: str = Field(..., min_length=1, description="Country name (en/ar) or ISO code")
    claim: str = Field(..., min_length=2, max_length=500)


class VerifyResponse(BaseModel):
    verdict: Literal["true", "false", "uncertain"]
    explanation: str
    source_type: Literal["objective_data", "web_search"]


class CountryOut(BaseModel):
    code: str
    name_en: str
    name_ar: str
    flag_png: str | None
    flag_svg: str | None


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()  # create the players table if missing (idempotent)
    app.state.countries = await load_countries()
    api_key = os.environ.get("GROQ_API_KEY")
    app.state.judge = SmartJudge(api_key)
    if not api_key:
        logger.warning(
            "GROQ_API_KEY is not set — /verify-fact will fail. Get a free key at "
            "https://console.groq.com/keys and put it in backend/.env."
        )
    if not APP_TOKEN:
        logger.warning(
            "APP_TOKEN is not set — /verify-fact accepts unauthenticated calls. "
            "Set the same random token in the backend env and the app build "
            "(--dart-define=APP_TOKEN=...) to protect the Groq quota."
        )
    app.state.verdict_cache = {}
    app.state.rate_buckets = {}
    app.state.global_bucket = []
    yield


app = FastAPI(title="بدون هبد! API", version="0.1.0", lifespan=lifespan)
app.include_router(auth_router)

# Dev-friendly CORS; tighten before any public deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _client_ip(request: Request) -> str:
    """Real client IP behind a reverse proxy (Render terminates TLS and puts
    the caller's address in X-Forwarded-For; request.client.host would be the
    proxy, collapsing every user into one rate-limit bucket)."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _check_rate_limit(request: Request) -> None:
    ip = _client_ip(request)
    now = time.monotonic()
    buckets: dict[str, list[float]] = app.state.rate_buckets
    bucket = [t for t in buckets.get(ip, []) if now - t < 60]
    if len(bucket) >= RATE_LIMIT_PER_MINUTE:
        raise HTTPException(status_code=429, detail="Too many requests; slow down.")
    bucket.append(now)
    # Re-inserting moves this IP to the end, so iteration order stays
    # oldest-activity-first and eviction below drops the stalest IPs.
    buckets.pop(ip, None)
    buckets[ip] = bucket
    if len(buckets) > RATE_BUCKETS_MAX_IPS:
        stale = [k for k, v in buckets.items() if now - v[-1] >= 60]
        for k in stale:
            del buckets[k]
        while len(buckets) > RATE_BUCKETS_MAX_IPS:
            del buckets[next(iter(buckets))]


def _check_app_token(request: Request) -> None:
    if not APP_TOKEN:
        return
    supplied = request.headers.get("x-app-token", "")
    if not secrets.compare_digest(supplied, APP_TOKEN):
        raise HTTPException(status_code=401, detail="Missing or invalid app token.")


def _check_global_budget() -> None:
    """One shared sliding window over every Groq-backed call, so total spend
    stays inside the free tier no matter how many IPs are calling."""
    now = time.monotonic()
    bucket = [t for t in app.state.global_bucket if now - t < 60]
    if len(bucket) >= GLOBAL_VERIFY_PER_MINUTE:
        app.state.global_bucket = bucket
        raise HTTPException(
            status_code=429,
            detail="الحكم الذكي مشغول جدًا حاليًا — جرّب بعد دقيقة، أو الحكم للبشري!",
        )
    bucket.append(now)
    app.state.global_bucket = bucket


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "countries": len(app.state.countries)}


@app.get("/countries", response_model=list[CountryOut])
async def countries() -> list[dict[str, Any]]:
    return app.state.countries


@app.post("/verify-fact", response_model=VerifyResponse)
async def verify_fact(body: VerifyRequest, request: Request) -> VerifyResponse:
    _check_app_token(request)
    _check_rate_limit(request)

    country = find_country(app.state.countries, body.country)
    if country is None:
        raise HTTPException(status_code=404, detail=f"Unknown country: {body.country!r}")

    cache_key = (country["code"], " ".join(body.claim.casefold().split()))
    cache: dict = app.state.verdict_cache
    if cached := cache.pop(cache_key, None):
        cache[cache_key] = cached  # re-insert: LRU bump to most-recently-used
        return cached

    # Only uncached claims hit Groq, so only they draw from the global budget.
    _check_global_budget()

    try:
        result = await app.state.judge.verify(country, body.claim, fact_sheet(country))
    except Exception:
        logger.exception("Smart Judge verification failed")
        raise HTTPException(
            status_code=503,
            detail="The Smart Judge is unavailable right now — the human judge decides!",
        )

    response = VerifyResponse(**result)
    cache[cache_key] = response
    while len(cache) > VERDICT_CACHE_MAX:
        del cache[next(iter(cache))]  # evict least-recently-used
    return response
