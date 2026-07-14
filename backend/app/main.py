"""بدون هبد! (Bedoon Habd) backend — country data + on-demand Smart Judge fact checking.

Run locally:
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any, Literal

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .countries import fact_sheet, find_country, load_countries
from .verifier import SmartJudge

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

RATE_LIMIT_PER_MINUTE = 20


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
    app.state.countries = await load_countries()
    api_key = os.environ.get("GROQ_API_KEY")
    app.state.judge = SmartJudge(api_key)
    if not api_key:
        logger.warning(
            "GROQ_API_KEY is not set — /verify-fact will fail. Get a free key at "
            "https://console.groq.com/keys and put it in backend/.env."
        )
    app.state.verdict_cache = {}
    app.state.rate_buckets = {}
    yield


app = FastAPI(title="بدون هبد! API", version="0.1.0", lifespan=lifespan)

# Dev-friendly CORS; tighten before any public deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _check_rate_limit(request: Request) -> None:
    ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    bucket = [t for t in app.state.rate_buckets.get(ip, []) if now - t < 60]
    if len(bucket) >= RATE_LIMIT_PER_MINUTE:
        raise HTTPException(status_code=429, detail="Too many requests; slow down.")
    bucket.append(now)
    app.state.rate_buckets[ip] = bucket


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "countries": len(app.state.countries)}


@app.get("/countries", response_model=list[CountryOut])
async def countries() -> list[dict[str, Any]]:
    return app.state.countries


@app.post("/verify-fact", response_model=VerifyResponse)
async def verify_fact(body: VerifyRequest, request: Request) -> VerifyResponse:
    _check_rate_limit(request)

    country = find_country(app.state.countries, body.country)
    if country is None:
        raise HTTPException(status_code=404, detail=f"Unknown country: {body.country!r}")

    cache_key = (country["code"], " ".join(body.claim.casefold().split()))
    if cached := app.state.verdict_cache.get(cache_key):
        return cached

    try:
        result = await app.state.judge.verify(country, body.claim, fact_sheet(country))
    except Exception:
        logger.exception("Smart Judge verification failed")
        raise HTTPException(
            status_code=503,
            detail="The Smart Judge is unavailable right now — the human judge decides!",
        )

    response = VerifyResponse(**result)
    app.state.verdict_cache[cache_key] = response
    return response
