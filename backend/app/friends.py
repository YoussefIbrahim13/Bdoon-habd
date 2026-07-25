"""Friend request system — REST endpoints over the app JWT.

Relationship model (see db.Friendship): one directed row per request. A pair
is "friends" once any row between them is ACCEPTED. Endpoints:

    POST /api/friends/request   {receiver_id}          → send (or resurrect a
                                                          prior REJECTED row)
    POST /api/friends/respond   {request_id, action}   → ACCEPT | REJECT
    GET  /api/friends                                   → accepted friends
    GET  /api/friends/pending                           → incoming pending

When the receiver is online, a `friend_request_received` event is pushed over
their live socket via the presence registry.
"""

from __future__ import annotations

import logging
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from . import presence
from .auth import get_current_player
from .db import FriendStatus, Friendship, Player, get_db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/friends", tags=["friends"])


# --------------------------------------------------------------------------
# Schemas
# --------------------------------------------------------------------------


class SendRequestBody(BaseModel):
    receiver_id: str = Field(..., min_length=1)


class RespondBody(BaseModel):
    request_id: str = Field(..., min_length=1)
    action: Literal["ACCEPT", "REJECT"]


class FriendOut(BaseModel):
    """A person + how you relate to them (for the add-friend button state)."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    picture: str | None
    # True when this friend has a live socket somewhere (invitable). Only
    # meaningful in the friends list; defaults False elsewhere.
    online: bool = False


class RequestOut(BaseModel):
    request_id: str
    sender: FriendOut


class StatusOut(BaseModel):
    # none | pending_outgoing | pending_incoming | friends
    relationship: str
    request_id: str | None = None


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


def _between(a: str, b: str):
    """Filter matching any row between two players, either direction."""
    return or_(
        and_(Friendship.sender_id == a, Friendship.receiver_id == b),
        and_(Friendship.sender_id == b, Friendship.receiver_id == a),
    )


def _person(db: Session, player_id: str, *, online: bool = False) -> FriendOut:
    p = db.get(Player, player_id)
    return FriendOut(
        id=player_id,
        name=p.name if p else "لاعب",
        picture=p.picture if p else None,
        online=online,
    )


def are_friends(db: Session, a: str, b: str) -> bool:
    """True iff an ACCEPTED friendship exists between a and b (either way)."""
    row = db.execute(
        select(Friendship).where(
            and_(Friendship.status == FriendStatus.ACCEPTED, _between(a, b))
        )
    ).scalars().first()
    return row is not None


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------


@router.post("/request", response_model=StatusOut)
async def send_friend_request(
    body: SendRequestBody,
    me: Annotated[Player, Depends(get_current_player)],
    db: Annotated[Session, Depends(get_db)],
) -> StatusOut:
    receiver_id = body.receiver_id
    if receiver_id == me.id:
        raise HTTPException(status_code=400, detail="مش هتضيف نفسك 😅")

    receiver = db.get(Player, receiver_id)
    if receiver is None or receiver.deleted_at is not None:
        raise HTTPException(status_code=404, detail="اللاعب ده مش موجود.")

    existing = db.execute(
        select(Friendship).where(_between(me.id, receiver_id))
    ).scalars().all()

    for row in existing:
        if row.status is FriendStatus.ACCEPTED:
            raise HTTPException(status_code=409, detail="انتوا أصحاب بالفعل 🤝")
        if row.status is FriendStatus.PENDING:
            # They already asked ME → accepting-by-requesting-back is friendly,
            # but keep it explicit: tell the client to use the pending request.
            if row.receiver_id == me.id:
                raise HTTPException(
                    status_code=409,
                    detail="عندك طلب صداقة منه بالفعل — اقبله من الطلبات.",
                )
            raise HTTPException(status_code=409, detail="الطلب اتبعت خلاص.")

    # No active row (or only REJECTED ones): (re)create a pending request.
    # Reuse a prior REJECTED row in the same direction to respect the unique
    # constraint; otherwise insert fresh.
    same_dir = next(
        (r for r in existing
         if r.sender_id == me.id and r.receiver_id == receiver_id),
        None,
    )
    if same_dir is not None:
        same_dir.status = FriendStatus.PENDING
        request_id = same_dir.id
    else:
        row = Friendship(sender_id=me.id, receiver_id=receiver_id)
        db.add(row)
        db.flush()
        request_id = row.id
    db.commit()

    # Real-time nudge if they're connected anywhere.
    await presence.notify(receiver_id, {
        "event": "friend_request_received",
        "request_id": request_id,
        "sender": {"id": me.id, "name": me.name, "picture": me.picture},
    })

    return StatusOut(relationship="pending_outgoing", request_id=request_id)


@router.post("/respond", response_model=StatusOut)
async def respond_to_friend_request(
    body: RespondBody,
    me: Annotated[Player, Depends(get_current_player)],
    db: Annotated[Session, Depends(get_db)],
) -> StatusOut:
    row = db.get(Friendship, body.request_id)
    if row is None:
        raise HTTPException(status_code=404, detail="الطلب ده مش موجود.")
    if row.receiver_id != me.id:
        # Only the receiver may accept/reject — never the sender or a stranger.
        raise HTTPException(status_code=403, detail="مش من حقك ترد على الطلب ده.")
    if row.status is not FriendStatus.PENDING:
        raise HTTPException(status_code=409, detail="تم الرد على الطلب ده قبل كده.")

    if body.action == "ACCEPT":
        row.status = FriendStatus.ACCEPTED
        db.commit()
        await presence.notify(row.sender_id, {
            "event": "friend_request_accepted",
            "by": {"id": me.id, "name": me.name, "picture": me.picture},
        })
        return StatusOut(relationship="friends", request_id=row.id)

    row.status = FriendStatus.REJECTED
    db.commit()
    return StatusOut(relationship="none")


@router.get("", response_model=list[FriendOut])
def get_friends_list(
    me: Annotated[Player, Depends(get_current_player)],
    db: Annotated[Session, Depends(get_db)],
) -> list[FriendOut]:
    rows = db.execute(
        select(Friendship).where(
            and_(
                Friendship.status == FriendStatus.ACCEPTED,
                or_(
                    Friendship.sender_id == me.id,
                    Friendship.receiver_id == me.id,
                ),
            )
        )
    ).scalars().all()
    friends = []
    for r in rows:
        other = r.receiver_id if r.sender_id == me.id else r.sender_id
        friends.append(_person(db, other, online=presence.is_online(other)))
    return friends


@router.get("/pending", response_model=list[RequestOut])
def get_pending_requests(
    me: Annotated[Player, Depends(get_current_player)],
    db: Annotated[Session, Depends(get_db)],
) -> list[RequestOut]:
    """Incoming requests awaiting MY response."""
    rows = db.execute(
        select(Friendship).where(
            and_(
                Friendship.receiver_id == me.id,
                Friendship.status == FriendStatus.PENDING,
            )
        ).order_by(Friendship.created_at.desc())
    ).scalars().all()
    return [
        RequestOut(request_id=r.id, sender=_person(db, r.sender_id))
        for r in rows
    ]
