"""In-memory multiplayer room engine for بدون هبد online.

Framework-free by design: no FastAPI imports, sockets are held as opaque
handles, and every game action is a method that mutates room state under the
room's asyncio.Lock and returns the JSON events to broadcast. The WebSocket
layer (websocket.py) owns actual network I/O, so this module is fully
testable without a server.

Concurrency model: FastAPI WebSocket handlers all run on one event loop, so
"thread safety" here means task safety — every mutation happens inside
`async with room.lock`, and the manager's own lock guards the room registry.
Nothing in this module blocks the loop.

Game loop (one round):
1. Server draws a country and announces `next_turn` (whose turn + country).
2. The current player submits a fact → `fact_submitted` broadcast.
3. The AI evaluator (stub for now; later the Smart Judge / LLM gateway)
   returns a verdict → `ai_verdict` broadcast.
4. Every connected player votes accept/habd → `voting_update` after each
   vote; when all votes are in, the round resolves.
5. Tally = player votes + the AI as one extra vote ("unreliable" abstains).
   Majority-true awards the speaker a point. `round_ended` broadcast, then
   either `game_over` (target reached) or the next round begins.
"""

from __future__ import annotations

import asyncio
import logging
import os
import secrets
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

logger = logging.getLogger(__name__)

ROOM_CODE_LENGTH = 6
MAX_PLAYERS = 8

# Minimum connected players required to start a match (also the threshold
# below which a running match ends early when people disconnect).
#
# PRODUCTION default is 2. For solo development/testing of the full loop
# (lobby → fact → AI → voting → game over), override via the environment
# instead of editing code — put `MIN_PLAYERS_TO_START=1` in backend/.env.
# Deployments without the env var automatically get the safe default, so
# there is nothing to remember to switch back.
MIN_PLAYERS_TO_START = max(1, int(os.environ.get("MIN_PLAYERS_TO_START", "2")))

DEFAULT_TARGET_SCORE = 5
MAX_FACT_LENGTH = 300

# Empty rooms older than this are pruned lazily on the next create_room.
STALE_ROOM_SECONDS = 15 * 60

Event = dict[str, Any]
CountryProvider = Callable[[], dict[str, Any]]
FactEvaluator = Callable[[dict[str, Any], str], Awaitable[dict[str, Any]]]


class RoomError(Exception):
    """A rule violation by a client — relayed back as an `error` event."""


class RoomPhase(str, Enum):
    LOBBY = "lobby"
    AWAITING_FACT = "awaiting_fact"
    EVALUATING = "evaluating"
    AWAITING_VOTES = "awaiting_votes"
    FINISHED = "finished"


def _event(event_type: str, **data: Any) -> Event:
    return {"event": event_type, **data}


@dataclass
class RoomPlayer:
    id: str
    name: str
    picture: str | None
    score: int = 0
    connected: bool = True
    # Opaque transport handle (a WebSocket in production, anything in tests).
    socket: Any = None

    def public_info(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "picture": self.picture,
            "score": self.score,
            "connected": self.connected,
        }


@dataclass
class Room:
    code: str
    host_id: str
    target_score: int = DEFAULT_TARGET_SCORE
    phase: RoomPhase = RoomPhase.LOBBY
    # dict preserves insertion order == seating/turn order.
    players: dict[str, RoomPlayer] = field(default_factory=dict)
    turn_order: list[str] = field(default_factory=list)
    turn_index: int = 0
    round_number: int = 0
    current_country: dict[str, Any] | None = None
    current_fact: str | None = None
    ai_verdict: dict[str, Any] | None = None
    votes: dict[str, bool] = field(default_factory=dict)
    created_at: float = field(default_factory=time.monotonic)
    # Set by the transport layer once final stats hit the database, so a
    # game-over followed by disconnects can't double-write.
    persisted: bool = False
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    @property
    def current_player_id(self) -> str | None:
        if self.phase in (RoomPhase.LOBBY, RoomPhase.FINISHED) or not self.turn_order:
            return None
        return self.turn_order[self.turn_index % len(self.turn_order)]

    def connected_players(self) -> list[RoomPlayer]:
        return [p for p in self.players.values() if p.connected]

    def snapshot(self) -> Event:
        """Full state for a (re)joining client."""
        return _event(
            "room_state",
            room_code=self.code,
            host_id=self.host_id,
            phase=self.phase.value,
            target_score=self.target_score,
            round_number=self.round_number,
            current_player_id=self.current_player_id,
            current_country=self.current_country,
            current_fact=self.current_fact,
            ai_verdict=self.ai_verdict,
            votes_cast=len(self.votes),
            players=[p.public_info() for p in self.players.values()],
        )


class RoomManager:
    """Registry + game rules. One instance per process, stored on app.state."""

    def __init__(
        self,
        country_provider: CountryProvider,
        fact_evaluator: FactEvaluator,
    ) -> None:
        self._country_provider = country_provider
        self._fact_evaluator = fact_evaluator
        self._rooms: dict[str, Room] = {}
        self._registry_lock = asyncio.Lock()

    # -- Registry ----------------------------------------------------------

    async def create_room(
        self, host_id: str, target_score: int = DEFAULT_TARGET_SCORE
    ) -> Room:
        async with self._registry_lock:
            self._prune_stale_locked()
            for _ in range(50):
                code = "".join(
                    secrets.choice("0123456789") for _ in range(ROOM_CODE_LENGTH)
                )
                if code not in self._rooms:
                    break
            else:  # pragma: no cover - 50 collisions on a 6-digit space
                raise RoomError("Could not allocate a room code; try again.")
            room = Room(
                code=code,
                host_id=host_id,
                target_score=max(1, min(target_score, 20)),
            )
            self._rooms[code] = room
            logger.info("Room %s created by %s", code, host_id)
            return room

    def get(self, code: str) -> Room | None:
        return self._rooms.get(code)

    async def remove_if_abandoned(self, room: Room) -> bool:
        """Drop the room once nobody is connected. Returns True if removed."""
        async with self._registry_lock:
            if not room.connected_players():
                self._rooms.pop(room.code, None)
                logger.info("Room %s removed (empty)", room.code)
                return True
            return False

    def _prune_stale_locked(self) -> None:
        now = time.monotonic()
        stale = [
            code
            for code, room in self._rooms.items()
            if not room.connected_players()
            and now - room.created_at > STALE_ROOM_SECONDS
        ]
        for code in stale:
            del self._rooms[code]

    # -- Lobby actions -----------------------------------------------------

    async def join(
        self, room: Room, player_id: str, name: str, picture: str | None, socket: Any
    ) -> list[Event]:
        """Add (or reconnect) a player. Returns events to broadcast."""
        async with room.lock:
            existing = room.players.get(player_id)
            if existing is not None:
                # Reconnect: swap the socket, keep score/seat.
                existing.socket = socket
                existing.connected = True
                existing.name = name
                existing.picture = picture
                return [
                    _event("player_joined", player=existing.public_info(),
                           reconnected=True)
                ]
            if room.phase is not RoomPhase.LOBBY:
                raise RoomError("اللعبة بدأت بالفعل — استنى الجولة الجاية.")
            if len(room.players) >= MAX_PLAYERS:
                raise RoomError("الأوضة كاملة العدد.")
            player = RoomPlayer(
                id=player_id, name=name, picture=picture, socket=socket
            )
            room.players[player_id] = player
            return [_event("player_joined", player=player.public_info(),
                           reconnected=False)]

    async def start_game(self, room: Room, actor_id: str) -> list[Event]:
        async with room.lock:
            if actor_id != room.host_id:
                raise RoomError("صاحب الأوضة بس اللي يقدر يبدأ اللعب.")
            if room.phase is not RoomPhase.LOBBY:
                raise RoomError("اللعبة بدأت بالفعل.")
            connected = room.connected_players()
            if len(connected) < MIN_PLAYERS_TO_START:
                raise RoomError("محتاجين لاعبين اتنين على الأقل.")
            room.turn_order = [p.id for p in connected]
            room.turn_index = 0
            events = [
                _event(
                    "game_started",
                    turn_order=room.turn_order,
                    target_score=room.target_score,
                )
            ]
            events.extend(self._begin_round_locked(room, advance_turn=False))
            return events

    # -- Round loop --------------------------------------------------------

    def _begin_round_locked(self, room: Room, *, advance_turn: bool) -> list[Event]:
        """Draw a country and open the next turn. Caller holds room.lock."""
        if advance_turn:
            room.turn_index += 1
        # Skip disconnected players (turn_order is frozen at start for fair
        # seating; connection state decides who actually gets turns). Direct
        # index math — current_player_id is phase-gated and the phase may
        # still be LOBBY here on the very first round.
        for _ in range(len(room.turn_order)):
            candidate = room.turn_order[room.turn_index % len(room.turn_order)]
            if room.players[candidate].connected:
                break
            room.turn_index += 1
        room.round_number += 1
        room.current_country = self._country_provider()
        room.current_fact = None
        room.ai_verdict = None
        room.votes = {}
        room.phase = RoomPhase.AWAITING_FACT
        return [
            _event(
                "next_turn",
                round=room.round_number,
                player_id=room.current_player_id,
                country=room.current_country,
            )
        ]

    async def submit_fact(
        self, room: Room, actor_id: str, text: str
    ) -> list[Event]:
        """Phase 1 of a turn: the current player states their fact."""
        async with room.lock:
            if room.phase is not RoomPhase.AWAITING_FACT:
                raise RoomError("مش وقت إرسال معلومة دلوقتي.")
            if actor_id != room.current_player_id:
                raise RoomError("مش دورك — استنى دورك يا نجم.")
            fact = text.strip()
            if not fact:
                raise RoomError("اكتب المعلومة الأول.")
            room.current_fact = fact[:MAX_FACT_LENGTH]
            room.phase = RoomPhase.EVALUATING
            return [
                _event("fact_submitted", player_id=actor_id, fact=room.current_fact)
            ]

    async def evaluate_fact(self, room: Room) -> list[Event]:
        """Phase 2: run the AI evaluator (outside the lock — it may be slow)
        and open voting. Safe against phase races via a re-check."""
        country, fact = room.current_country, room.current_fact
        if country is None or fact is None:
            return []
        try:
            verdict = await self._fact_evaluator(country, fact)
        except Exception:  # evaluator must never kill the room
            logger.exception("Fact evaluator failed in room %s", room.code)
            verdict = {
                "verdict": "unreliable",
                "explanation": "الحكم الذكي مش متاح — القرار كله للتصويت!",
            }
        async with room.lock:
            if room.phase is not RoomPhase.EVALUATING:
                return []  # round was torn down (e.g. mass disconnect)
            room.ai_verdict = verdict
            room.phase = RoomPhase.AWAITING_VOTES
            return [
                _event(
                    "ai_verdict",
                    verdict=verdict.get("verdict", "unreliable"),
                    explanation=verdict.get("explanation", ""),
                    votes_needed=len(room.connected_players()),
                )
            ]

    async def submit_vote(
        self, room: Room, actor_id: str, accept: bool
    ) -> list[Event]:
        """Phase 3: everyone votes; the last vote resolves the round."""
        async with room.lock:
            if room.phase is not RoomPhase.AWAITING_VOTES:
                raise RoomError("مش وقت التصويت دلوقتي.")
            player = room.players.get(actor_id)
            if player is None or not player.connected:
                raise RoomError("انت مش في الأوضة دي.")
            if actor_id in room.votes:
                raise RoomError("انت صوّت خلاص.")
            room.votes[actor_id] = accept
            events = [
                _event(
                    "voting_update",
                    votes_cast=len(room.votes),
                    votes_needed=len(room.connected_players()),
                )
            ]
            if self._voting_complete_locked(room):
                events.extend(self._resolve_round_locked(room))
            return events

    def _voting_complete_locked(self, room: Room) -> bool:
        connected_ids = {p.id for p in room.connected_players()}
        return connected_ids.issubset(room.votes.keys())

    def _resolve_round_locked(self, room: Room) -> list[Event]:
        speaker_id = room.current_player_id
        speaker = room.players[speaker_id]  # type: ignore[index]

        true_votes = sum(1 for v in room.votes.values() if v)
        false_votes = len(room.votes) - true_votes
        # The AI counts as one extra voter; "unreliable" abstains.
        ai = (room.ai_verdict or {}).get("verdict")
        if ai == "true":
            true_votes += 1
        elif ai == "false":
            false_votes += 1

        awarded = true_votes > false_votes
        if awarded:
            speaker.score += 1

        events = [
            _event(
                "round_ended",
                player_id=speaker_id,
                awarded=awarded,
                fact=room.current_fact,
                ai_verdict=room.ai_verdict,
                votes={"true": true_votes, "false": false_votes},
                scores={p.id: p.score for p in room.players.values()},
            )
        ]

        if speaker.score >= room.target_score:
            room.phase = RoomPhase.FINISHED
            events.append(
                _event(
                    "game_over",
                    winner=speaker.public_info(),
                    scores={p.id: p.score for p in room.players.values()},
                )
            )
        else:
            events.extend(self._begin_round_locked(room, advance_turn=True))
        return events

    # -- Disconnects -------------------------------------------------------

    async def handle_disconnect(self, room: Room, player_id: str) -> list[Event]:
        """Mark a player gone and keep the game consistent: skip their turn,
        drop their pending vote requirement, transfer host, or end the game
        if fewer than two players remain mid-match."""
        async with room.lock:
            player = room.players.get(player_id)
            if player is None or not player.connected:
                return []
            player.connected = False
            player.socket = None
            events = [_event("player_left", player=player.public_info())]

            # In the lobby, drop them entirely (their seat isn't reserved).
            if room.phase is RoomPhase.LOBBY:
                del room.players[player_id]
                events[0]["player"]["connected"] = False

            # Host handover to the longest-seated connected player.
            if player_id == room.host_id:
                remaining = room.connected_players()
                if remaining:
                    room.host_id = remaining[0].id
                    events.append(_event("host_changed", host_id=room.host_id))

            if room.phase in (RoomPhase.LOBBY, RoomPhase.FINISHED):
                return events

            # Mid-match integrity:
            remaining = room.connected_players()
            if len(remaining) < MIN_PLAYERS_TO_START:
                room.phase = RoomPhase.FINISHED
                winner = max(remaining, default=None, key=lambda p: p.score)
                events.append(
                    _event(
                        "game_over",
                        reason="not_enough_players",
                        winner=winner.public_info() if winner else None,
                        scores={p.id: p.score for p in room.players.values()},
                    )
                )
                return events

            if room.current_player_id == player_id and room.phase in (
                RoomPhase.AWAITING_FACT,
                RoomPhase.EVALUATING,
            ):
                # The speaker vanished mid-turn — move on with a fresh round.
                events.extend(self._begin_round_locked(room, advance_turn=True))
            elif room.phase is RoomPhase.AWAITING_VOTES:
                room.votes.pop(player_id, None)
                if self._voting_complete_locked(room):
                    events.extend(self._resolve_round_locked(room))
            return events
