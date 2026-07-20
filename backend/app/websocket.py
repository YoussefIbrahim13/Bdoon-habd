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
import random
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import HTTPException
from pydantic import BaseModel, Field

from . import presence
from .auth import get_current_player, resolve_player_by_token
from .countries import difficulty_of
from .db import Player, get_db, _SessionLocal  # noqa: PLC2701 - session factory
from .llm_judge import llm_fact_evaluator
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
    """Called once from the app lifespan, after countries are loaded.

    The default evaluator is the real LLM Smart Judge (llm_judge.py);
    tests inject deterministic fakes here.
    """
    global _manager
    _manager = RoomManager(
        country_provider=country_provider,
        fact_evaluator=fact_evaluator or llm_fact_evaluator,
        broadcaster=_timer_broadcaster,
    )
    return _manager


async def _timer_broadcaster(room: Room, events: list[dict[str, Any]]) -> None:
    """Sink for server-initiated (turn-timer) events. A timeout can END the
    match with no client request in flight, so persistence rides here too."""
    await _broadcast(room, events)
    await _maybe_persist(room)


def get_room_manager() -> RoomManager:
    assert _manager is not None, "init_room_manager() not called at startup"
    return _manager


# --------------------------------------------------------------------------
# Country drawing for the room engine (AI judging lives in llm_judge.py).
# --------------------------------------------------------------------------


def make_country_provider(countries: list[dict[str, Any]]):
    """Difficulty-aware country drawer for the room engine.

    Tiers are precomputed once. 'easy' and 'hard' pull from their pool;
    'progressive' slides across easy → medium → hard as the match advances
    (round 1 of N is famous, round N is obscure). Thin pools fall back to
    the full list so a match can never stall on an empty tier.
    """
    pools: dict[str, list[dict[str, Any]]] = {"easy": [], "medium": [], "hard": []}
    for c in countries:
        pools[difficulty_of(c["code"])].append(c)

    def provider(
        difficulty: str, round_number: int, total_rounds: int
    ) -> dict[str, Any]:
        if difficulty in ("easy", "hard"):
            tier = difficulty
        else:  # progressive: 0..1 across the match → easy/medium/hard thirds
            progress = (round_number - 1) / max(1, total_rounds - 1)
            tier = "easy" if progress < 1 / 3 else (
                "medium" if progress < 2 / 3 else "hard"
            )
        pool = pools.get(tier) or countries
        return random.choice(pool)

    return provider


# --------------------------------------------------------------------------
# Room creation (REST, authenticated)
# --------------------------------------------------------------------------


class CreateRoomRequest(BaseModel):
    total_rounds: int = Field(default=5, ge=1, le=20)
    difficulty: Literal["easy", "hard", "progressive"] = "progressive"


class CreateRoomResponse(BaseModel):
    room_code: str
    total_rounds: int
    difficulty: str


@router.post("/api/rooms", response_model=CreateRoomResponse)
async def create_room(
    body: CreateRoomRequest,
    player: Annotated[Player, Depends(get_current_player)],
) -> CreateRoomResponse:
    """Reserve a room; the host then joins it over the WebSocket like
    everyone else (one join path = one set of bugs)."""
    room = await get_room_manager().create_room(
        player.id,
        total_rounds=body.total_rounds,
        difficulty=body.difficulty,
    )
    return CreateRoomResponse(
        room_code=room.code,
        total_rounds=room.total_rounds,
        difficulty=room.difficulty,
    )


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
    # Mirror the match rule: a SOLE top scorer gets the win; ties get none.
    winner_ids: set[str] = set()
    top = max((p.score for p in room.players.values()), default=0)
    leaders = [p.id for p in room.players.values() if p.score == top]
    if top > 0 and len(leaders) == 1:
        winner_ids = {leaders[0]}
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

    # Mark the player online app-wide so friend requests can reach them here.
    presence.register(player.id, websocket)

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
                elif action == "update_settings":
                    events = await manager.update_settings(
                        room,
                        player.id,
                        total_rounds=(
                            int(message["total_rounds"])
                            if "total_rounds" in message
                            else None
                        ),
                        difficulty=message.get("difficulty"),
                    )
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
        presence.unregister(player.id, websocket)
        events = await manager.handle_disconnect(room, player.id)
        await _broadcast(room, events)
        await _maybe_persist(room)
        await manager.remove_if_abandoned(room)


async def _maybe_persist(room: Room) -> None:
    """Persist stats exactly once, right after the room finishes."""
    if room.phase is RoomPhase.FINISHED and not room.persisted:
        room.persisted = True
        await run_in_threadpool(_persist_results, room)
