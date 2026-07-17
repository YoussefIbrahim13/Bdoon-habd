"""Administrative player endpoints, driven from Swagger UI (/docs).

Security: everything here requires the X-Admin-Token header to equal the
ADMIN_TOKEN env var. With ADMIN_TOKEN unset the whole surface is disabled
(503) — these endpoints expose player emails and allow deletion, so they
must never be silently open on a public URL.

In /docs: click Authorize → paste the token into "X-Admin-Token".
"""

from __future__ import annotations

import logging
import os
import secrets
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import Player, get_db, utcnow

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin", tags=["admin"])

ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "").strip()

# APIKeyHeader (not HTTPBearer) so Swagger's Authorize dialog offers a
# dedicated field, separate from the player-JWT bearer scheme.
_admin_header = APIKeyHeader(name="X-Admin-Token", auto_error=False)


def require_admin(
    supplied: Annotated[str | None, Depends(_admin_header)],
) -> None:
    if not ADMIN_TOKEN:
        raise HTTPException(
            status_code=503,
            detail="Admin API is disabled: set ADMIN_TOKEN on the server.",
        )
    if not supplied or not secrets.compare_digest(supplied, ADMIN_TOKEN):
        raise HTTPException(
            status_code=401, detail="Missing or invalid admin token."
        )


# --------------------------------------------------------------------------
# Schemas
# --------------------------------------------------------------------------


class AdminPlayerOut(BaseModel):
    """Full player view for administration: profile + game stats."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    email: str
    picture: str | None
    matches_played: int
    wins: int
    total_points: int
    created_at: datetime
    last_login_at: datetime


class DeleteConfirmation(BaseModel):
    detail: str
    player_id: str


# --------------------------------------------------------------------------
# Endpoints (sync — FastAPI runs them in the threadpool, matching the rest
# of the DB-touching endpoints)
# --------------------------------------------------------------------------


@router.get(
    "/players",
    response_model=list[AdminPlayerOut],
    dependencies=[Depends(require_admin)],
)
def list_players(db: Annotated[Session, Depends(get_db)]) -> list[Player]:
    """All ACTIVE players (soft-deleted excluded), most recently active first."""
    return list(
        db.execute(
            select(Player)
            .where(Player.deleted_at.is_(None))
            .order_by(Player.last_login_at.desc())
        ).scalars()
    )


@router.delete(
    "/players/{player_id}",
    response_model=DeleteConfirmation,
    dependencies=[Depends(require_admin)],
)
def delete_player(
    player_id: str, db: Annotated[Session, Depends(get_db)]
) -> DeleteConfirmation:
    """SOFT-delete one player by UUID: the row survives (stats/history are
    recoverable) but the account is disabled everywhere — hidden from
    listings and instantly rejected by the auth guards."""
    player = db.get(Player, player_id)
    if player is None or player.deleted_at is not None:
        # Already-soft-deleted reads as gone, consistent with the listing.
        raise HTTPException(
            status_code=404, detail=f"No active player with id {player_id!r}."
        )
    player.deleted_at = utcnow()
    db.commit()
    logger.info("Admin soft-deleted player %s (%s)", player_id, player.email)
    return DeleteConfirmation(
        detail=(
            f"Player {player.name!r} soft-deleted: account disabled, "
            "row retained for recovery."
        ),
        player_id=player_id,
    )
