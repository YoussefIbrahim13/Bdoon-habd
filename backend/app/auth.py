"""Google Sign-In → application JWT.

Flow:
1. The Flutter app completes Google Sign-In on-device and POSTs the Google
   **ID token** to /api/auth/google.
2. We verify it with Google's official library (signature against Google's
   rotating public keys, expiry, issuer, and audience == our GOOGLE_CLIENT_ID).
3. We upsert the player by Google's stable `sub` identifier — new players get
   their initial stats provisioned; returning players get last_login bumped.
4. We mint OUR OWN JWT (HS256, JWT_SECRET) that the app uses for all
   subsequent authenticated calls — the Google token is never stored and
   never used again.

Env:
    GOOGLE_CLIENT_ID  required — the OAuth client ID the Flutter app signs in
                      with (Web application client ID, the `serverClientId`).
    JWT_SECRET        required in production — signing key for our JWTs.
                      If unset, an ephemeral key is generated (dev only:
                      every restart invalidates all sessions).
"""

from __future__ import annotations

import logging
import os
import secrets
import time
from datetime import timedelta
from typing import Annotated, Any

import jwt as pyjwt
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import Player, get_db, utcnow

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["auth"])

GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "").strip()

JWT_ALGORITHM = "HS256"
JWT_TTL = timedelta(days=7)
JWT_ISSUER = "bedoon-habd"
_JWT_SECRET = os.environ.get("JWT_SECRET", "").strip()
if not _JWT_SECRET:
    # Dev fallback: sessions die on restart. Production must set JWT_SECRET.
    _JWT_SECRET = secrets.token_urlsafe(48)
    logger.warning(
        "JWT_SECRET is not set — generated an ephemeral signing key. "
        "All issued tokens become invalid on restart; set JWT_SECRET in prod."
    )

# Light per-IP limiter: sign-in bursts are small, and this endpoint triggers
# outbound calls (Google cert fetch) + DB writes, so keep abuse cheap to shed.
AUTH_RATE_PER_MINUTE = 10
_AUTH_BUCKETS_MAX = 5000
_auth_buckets: dict[str, list[float]] = {}

_bearer = HTTPBearer(auto_error=False)


# --------------------------------------------------------------------------
# Schemas
# --------------------------------------------------------------------------


class GoogleAuthRequest(BaseModel):
    # The Flutter client sends {"idToken": "..."} — snake_case accepted too.
    model_config = ConfigDict(populate_by_name=True)

    id_token: str = Field(..., alias="idToken", min_length=20)


class PlayerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: str
    name: str
    picture: str | None
    matches_played: int
    wins: int
    total_points: int


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: int  # unix seconds
    user: PlayerOut


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _check_auth_rate(request: Request) -> None:
    ip = _client_ip(request)
    now = time.monotonic()
    bucket = [t for t in _auth_buckets.get(ip, []) if now - t < 60]
    if len(bucket) >= AUTH_RATE_PER_MINUTE:
        raise HTTPException(status_code=429, detail="Too many sign-in attempts.")
    bucket.append(now)
    _auth_buckets.pop(ip, None)
    _auth_buckets[ip] = bucket
    while len(_auth_buckets) > _AUTH_BUCKETS_MAX:
        del _auth_buckets[next(iter(_auth_buckets))]


def _verify_google_token(raw_token: str) -> dict[str, Any]:
    """Validate the Google ID token and return its claims.

    verify_oauth2_token checks the signature against Google's current public
    keys, the `exp` expiry, and that `aud` equals our client ID. We re-check
    the issuer explicitly (belt and braces) and require a verified email.
    Raises HTTPException with the right status for every failure mode.
    """
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=503,
            detail="Google Sign-In is not configured on this server.",
        )
    try:
        claims = google_id_token.verify_oauth2_token(
            raw_token, google_requests.Request(), audience=GOOGLE_CLIENT_ID
        )
    except ValueError as exc:
        # Covers: bad signature, expired token, wrong audience, malformed JWT.
        logger.info("Rejected Google ID token: %s", exc)
        raise HTTPException(
            status_code=401, detail="Invalid or expired Google token."
        ) from exc

    if claims.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
        raise HTTPException(status_code=401, detail="Invalid token issuer.")
    if not claims.get("sub"):
        raise HTTPException(status_code=401, detail="Token missing subject.")
    if not claims.get("email") or not claims.get("email_verified", False):
        raise HTTPException(
            status_code=403, detail="A verified Google email is required."
        )
    return claims


def _issue_app_jwt(player: Player) -> tuple[str, int]:
    """Mint our application JWT. Returns (token, expires_at_unix)."""
    now = int(time.time())
    expires_at = now + int(JWT_TTL.total_seconds())
    token = pyjwt.encode(
        {
            "iss": JWT_ISSUER,
            "sub": player.id,
            "email": player.email,
            "name": player.name,
            "iat": now,
            "exp": expires_at,
        },
        _JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )
    return token, expires_at


def resolve_player_by_token(token: str, db: Session) -> Player:
    """Validate one of OUR JWTs and return the live player.

    Shared by the HTTP bearer dependency and the WebSocket handshake (which
    carries the token as a query param — browsers/Flutter WS clients cannot
    set headers). Raises HTTPException with the right status on any failure.
    """
    try:
        claims = pyjwt.decode(
            token,
            _JWT_SECRET,
            algorithms=[JWT_ALGORITHM],
            issuer=JWT_ISSUER,
            options={"require": ["exp", "sub", "iss"]},
        )
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Session expired — sign in again.")
    except pyjwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid session token.")

    player = db.get(Player, claims["sub"])
    if player is None:
        raise HTTPException(status_code=401, detail="Unknown player.")
    if player.deleted_at is not None:
        # Soft-deleted mid-session: their still-valid JWT dies right here.
        raise HTTPException(status_code=403, detail="Account disabled.")
    return player


def get_current_player(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    db: Annotated[Session, Depends(get_db)],
) -> Player:
    """Dependency for protected endpoints: Authorization: Bearer <our JWT>."""
    if creds is None:
        raise HTTPException(status_code=401, detail="Missing bearer token.")
    return resolve_player_by_token(creds.credentials, db)


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------


@router.post("/google", response_model=AuthResponse)
def google_sign_in(
    body: GoogleAuthRequest,
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> AuthResponse:
    """Exchange a Google ID token for an application JWT (sync endpoint —
    FastAPI runs it in the threadpool, so the blocking cert fetch and DB
    round-trips never stall the event loop)."""
    _check_auth_rate(request)
    claims = _verify_google_token(body.id_token)

    sub = claims["sub"]
    player = db.execute(
        select(Player).where(Player.google_sub == sub)
    ).scalar_one_or_none()

    if player is not None and player.deleted_at is not None:
        # Soft-deleted accounts stay disabled — a fresh Google sign-in must
        # not silently resurrect a banned/removed player.
        raise HTTPException(status_code=403, detail="Account disabled.")

    if player is None:
        # First sign-in: provision the account with fresh stats.
        player = Player(
            google_sub=sub,
            email=claims["email"],
            name=claims.get("name") or claims["email"].split("@")[0],
            picture=claims.get("picture"),
        )
        db.add(player)
        logger.info("Provisioned new player for sub=%s", sub[:8])
    else:
        # Returning player: refresh profile bits Google may have changed.
        player.email = claims["email"]
        player.name = claims.get("name") or player.name
        player.picture = claims.get("picture") or player.picture

    player.last_login_at = utcnow()
    db.commit()

    token, expires_at = _issue_app_jwt(player)
    return AuthResponse(
        access_token=token,
        expires_at=expires_at,
        user=PlayerOut.model_validate(player),
    )


@router.get("/me", response_model=PlayerOut)
def me(player: Annotated[Player, Depends(get_current_player)]) -> Player:
    """The signed-in player's profile — also the template for every future
    protected online-mode endpoint (just depend on get_current_player)."""
    return player
