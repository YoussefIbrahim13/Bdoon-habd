"""WebSocket transport + room REST for بدون هبد online multiplayer.

Protocol:
- `POST /api/rooms` (bearer JWT) → `{room_code}`; the creator is the host.
- `WS /ws/game/{room_code}?token=<app JWT>` — the token rides a query param
  because WS clients can't set headers. On connect the server sends a full
  `room_state` snapshot, then streams events.

Client → server messages: `{"action": "start_game"}`,
`{"action": "submit_fact", "text": "..."}`,
`{"action": "submit_vote", "accept": true|false}`.

Server → client events (all `{"event": ..., ...}`): room_state,
player_joined, player_left, host_changed, game_started, next_turn,
fact_submitted, ai_verdict, voting_update, round_ended, game_over, error.

The game rules live in rooms.py; this module only authenticates, routes
actions, broadcasts the returned events, and persists final results.
"""

from __future__ import annotations

import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import HTTPException
from pydantic import BaseModel, Field

from .auth import get_current_player, resolve_player_by_token
from .db import Player, get_db, _SessionLocal  # noqa: PLC2701 - session factory
from .rooms import Room, RoomError, RoomManager, RoomPhase

logger = logging.getLogger(__name__)

router = APIRouter()

# WS close codes (4000+ = application-defined).
WS_UNAUTHORIZED = 4401
WS_ROOM_NOT_FOUND = 4404
WS_ROOM_FULL = 4409

_manager: RoomManager | None = None


def init_room_manager(
    country_provider: Any, fact_evaluator: Any | None = None
) -> RoomManager:
    """Called once from the app lifespan, after countries are loaded."""
    global _manager
    _manager = RoomManager(
        country_provider=country_provider,
        fact_evaluator=fact_evaluator or stub_fact_evaluator,
    )
    return _manager


def get_room_manager() -> RoomManager:
    assert _manager is not None, "init_room_manager() not called at startup"
    return _manager


# --------------------------------------------------------------------------
# AI evaluation stub — the seam for the Smart Judge / LLM gateway.
# --------------------------------------------------------------------------


async def stub_fact_evaluator(
    country: dict[str, Any], fact: str
) -> dict[str, Any]:
    """Placeholder verdict until this is wired to the LLM gateway.

    Contract (keep when swapping in the real judge):
    returns {"verdict": "true" | "false" | "unreliable", "explanation": str}.
    The real implementation will call app.state.judge.verify(...) with the
    same country dict + fact and map its verdict onto this shape.
    """
    return {
        "verdict": "unreliable",
        "explanation": "الحكم الذكي للأونلاين لسه في الفرن — القرار للتصويت!",
    }


# --------------------------------------------------------------------------
# Room creation (REST, authenticated)
# --------------------------------------------------------------------------


class CreateRoomRequest(BaseModel):
    target_score: int = Field(default=5, ge=1, le=20)


class CreateRoomResponse(BaseModel):
    room_code: str
    target_score: int


@router.post("/api/rooms", response_model=CreateRoomResponse)
async def create_room(
    body: CreateRoomRequest,
    player: Annotated[Player, Depends(get_current_player)],
) -> CreateRoomResponse:
    """Reserve a room; the host then joins it over the WebSocket like
    everyone else (one join path = one set of bugs)."""
    room = await get_room_manager().create_room(
        player.id, target_score=body.target_score
    )
    return CreateRoomResponse(room_code=room.code, target_score=room.target_score)


# --------------------------------------------------------------------------
# The WebSocket endpoint
# --------------------------------------------------------------------------


async def _broadcast(room: Room, events: list[dict[str, Any]]) -> None:
    """Send events to every connected player, dropping dead sockets."""
    for event in events:
        for p in room.players.values():
            if not p.connected or p.socket is None:
                continue
            try:
                await p.socket.send_json(event)
            except Exception:
                # The disconnect handler will formally clean this player up.
                logger.debug("Dropped send to %s in %s", p.id, room.code)


def _persist_results(room: Room) -> None:
    """Write final stats into Postgres via the normal session pattern."""
    winner_ids = set()
    top = max((p.score for p in room.players.values()), default=0)
    if top >= room.target_score:
        winner_ids = {p.id for p in room.players.values() if p.score == top}
    db = _SessionLocal()
    try:
        for rp in room.players.values():
            player = db.get(Player, rp.id)
            if player is None:
                continue
            player.matches_played += 1
            player.total_points += rp.score
            if rp.id in winner_ids:
                player.wins += 1
        db.commit()
    finally:
        db.close()


@router.websocket("/ws/game/{room_code}")
async def game_socket(websocket: WebSocket, room_code: str) -> None:
    manager = get_room_manager()
    await websocket.accept()

    # -- Handshake: authenticate, find the room, take a seat. --------------
    token = websocket.query_params.get("token", "")
    try:
        db = next(get_db())
        try:
            player = await run_in_threadpool(resolve_player_by_token, token, db)
        finally:
            db.close()
    except HTTPException as exc:
        await websocket.send_json({"event": "error", "detail": exc.detail})
        await websocket.close(code=WS_UNAUTHORIZED)
        return

    room = manager.get(room_code)
    if room is None:
        await websocket.send_json(
            {"event": "error", "detail": "الأوضة دي مش موجودة — اتأكد من الكود."}
        )
        await websocket.close(code=WS_ROOM_NOT_FOUND)
        return

    try:
        join_events = await manager.join(
            room, player.id, player.name, player.picture, websocket
        )
    except RoomError as exc:
        await websocket.send_json({"event": "error", "detail": str(exc)})
        await websocket.close(code=WS_ROOM_FULL)
        return

    # Snapshot to the newcomer first, then announce them to the room.
    await websocket.send_json(room.snapshot())
    await _broadcast(room, join_events)

    # -- Action loop -------------------------------------------------------
    try:
        while True:
            message = await websocket.receive_json()
            action = message.get("action")
            try:
                if action == "start_game":
                    events = await manager.start_game(room, player.id)
                    await _broadcast(room, events)
                elif action == "submit_fact":
                    events = await manager.submit_fact(
                        room, player.id, str(message.get("text", ""))
                    )
                    await _broadcast(room, events)
                    # AI evaluation runs outside the room lock (may be slow);
                    # its verdict opens the voting phase.
                    await _broadcast(room, await manager.evaluate_fact(room))
                elif action == "submit_vote":
                    events = await manager.submit_vote(
                        room, player.id, bool(message.get("accept"))
                    )
                    await _broadcast(room, events)
                    await _maybe_persist(room)
                else:
                    raise RoomError(f"Unknown action: {action!r}")
            except RoomError as exc:
                # Rule violations go only to the offender.
                await websocket.send_json(
                    {"event": "error", "detail": str(exc)}
                )
    except WebSocketDisconnect:
        pass
    finally:
        events = await manager.handle_disconnect(room, player.id)
        await _broadcast(room, events)
        await _maybe_persist(room)
        await manager.remove_if_abandoned(room)


async def _maybe_persist(room: Room) -> None:
    """Persist stats exactly once, right after the room finishes."""
    if room.phase is RoomPhase.FINISHED and not room.persisted:
        room.persisted = True
        await run_in_threadpool(_persist_results, room)
