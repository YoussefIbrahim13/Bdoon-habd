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

Match structure: a fixed number of rounds (host-configurable `total_rounds`),
one fact per round, highest score at the end wins (tie → no sole winner).
Countries are drawn per-round by the host-chosen `difficulty`:
- 'easy'        → famous flags only
- 'hard'        → obscure flags only
- 'progressive' → early rounds famous, sliding to obscure as rounds advance

Game loop (one round):
1. Server draws a country for (difficulty, round, total) and announces
   `next_turn` (whose turn + country).
2. The current player submits a fact → `fact_submitted` broadcast.
3. The AI evaluator returns a verdict → `ai_verdict` broadcast.
4. Every connected player EXCEPT the speaker votes accept/habd (no judging
   your own fact) → `voting_update` after each vote; when all eligible votes
   are in, the round resolves. With zero eligible voters (solo testing) the
   AI verdict alone resolves it immediately.
5. Tally = eligible votes + the AI as one extra vote ("unreliable" abstains).
   Majority-true awards the speaker a point → `round_ended`, then either
   `game_over` (last round done) or the next round begins.
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

DEFAULT_TOTAL_ROUNDS = 5
MAX_TOTAL_ROUNDS = 20
VALID_DIFFICULTIES = ("easy", "hard", "progressive")
DEFAULT_DIFFICULTY = "progressive"
MAX_FACT_LENGTH = 300

# Strict per-turn limit for AWAITING_FACT (seconds). The SERVER owns this
# clock: when it expires the speaker forfeits the round (0 points), a
# `turn_timed_out` broadcast goes out, and play advances. Env-overridable so
# tests can shrink it.
TURN_SECONDS = max(3, int(os.environ.get("TURN_SECONDS", "30")))

# Empty rooms older than this are pruned lazily on the next create_room.
STALE_ROOM_SECONDS = 15 * 60

Event = dict[str, Any]
# (difficulty, round_number, total_rounds) -> country dict
CountryProvider = Callable[[str, int, int], dict[str, Any]]
FactEvaluator = Callable[[dict[str, Any], str], Awaitable[dict[str, Any]]]
# Async sink the manager uses to push timer-driven events (the transport
# layer's broadcast function). None = timer events are dropped (bare tests).
Broadcaster = Callable[["Room", list[Event]], Awaitable[None]]


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
    total_rounds: int = DEFAULT_TOTAL_ROUNDS
    difficulty: str = DEFAULT_DIFFICULTY
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
    # --- Turn timer plumbing (managed exclusively under `lock`) ---
    # Monotonic deadline for the current AWAITING_FACT turn (None otherwise).
    turn_deadline: float | None = None
    # Generation token: bumped on every arm/cancel, so a timer task that
    # already woke up can detect it belongs to a dead round and do nothing.
    turn_token: int = 0
    turn_timer_task: Any = field(default=None, repr=False)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    @property
    def current_player_id(self) -> str | None:
        if self.phase in (RoomPhase.LOBBY, RoomPhase.FINISHED) or not self.turn_order:
            return None
        return self.turn_order[self.turn_index % len(self.turn_order)]

    def connected_players(self) -> list[RoomPlayer]:
        return [p for p in self.players.values() if p.connected]

    def eligible_voters(self) -> list[RoomPlayer]:
        """Connected players minus the current speaker — no self-voting."""
        return [
            p for p in self.connected_players() if p.id != self.current_player_id
        ]

    def snapshot(self) -> Event:
        """Full state for a (re)joining client."""
        seconds_left = None
        if self.phase is RoomPhase.AWAITING_FACT and self.turn_deadline:
            seconds_left = max(0, int(self.turn_deadline - time.monotonic()))
        return _event(
            "room_state",
            room_code=self.code,
            host_id=self.host_id,
            phase=self.phase.value,
            total_rounds=self.total_rounds,
            difficulty=self.difficulty,
            round_number=self.round_number,
            turn_seconds=TURN_SECONDS,
            turn_seconds_left=seconds_left,
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
        broadcaster: Broadcaster | None = None,
    ) -> None:
        self._country_provider = country_provider
        self._fact_evaluator = fact_evaluator
        self._broadcaster = broadcaster
        self._rooms: dict[str, Room] = {}
        self._registry_lock = asyncio.Lock()

    # -- Registry ----------------------------------------------------------

    async def create_room(
        self,
        host_id: str,
        total_rounds: int = DEFAULT_TOTAL_ROUNDS,
        difficulty: str = DEFAULT_DIFFICULTY,
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
                total_rounds=max(1, min(total_rounds, MAX_TOTAL_ROUNDS)),
                difficulty=(
                    difficulty if difficulty in VALID_DIFFICULTIES
                    else DEFAULT_DIFFICULTY
                ),
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
                self._cancel_turn_timer_locked(room)  # no task may outlive it
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

    async def update_settings(
        self,
        room: Room,
        actor_id: str,
        total_rounds: int | None = None,
        difficulty: str | None = None,
    ) -> list[Event]:
        """Host-only lobby knobs; broadcast so guests' UIs sync live."""
        async with room.lock:
            if actor_id != room.host_id:
                raise RoomError("صاحب الأوضة بس اللي يغيّر الإعدادات.")
            if room.phase is not RoomPhase.LOBBY:
                raise RoomError("الإعدادات بتتغير قبل ما اللعب يبدأ بس.")
            if total_rounds is not None:
                if not 1 <= total_rounds <= MAX_TOTAL_ROUNDS:
                    raise RoomError("عدد الجولات لازم يكون من 1 لـ 20.")
                room.total_rounds = total_rounds
            if difficulty is not None:
                if difficulty not in VALID_DIFFICULTIES:
                    raise RoomError("مستوى الصعوبة ده مش معروف.")
                room.difficulty = difficulty
            return [
                _event(
                    "settings_updated",
                    total_rounds=room.total_rounds,
                    difficulty=room.difficulty,
                )
            ]

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
                    total_rounds=room.total_rounds,
                    difficulty=room.difficulty,
                )
            ]
            events.extend(self._begin_round_locked(room, advance_turn=False))
            return events

    # -- Turn timer --------------------------------------------------------
    # All three helpers require room.lock to be held by the caller. The token
    # dance makes cancellation airtight: any arm/cancel bumps the token, so a
    # timer task that already slept through its cancel() wakes up, sees a
    # foreign token, and exits without touching the room.

    def _cancel_turn_timer_locked(self, room: Room) -> None:
        room.turn_token += 1
        room.turn_deadline = None
        task = room.turn_timer_task
        room.turn_timer_task = None
        if task is not None and not task.done():
            task.cancel()

    def _arm_turn_timer_locked(self, room: Room) -> None:
        self._cancel_turn_timer_locked(room)
        room.turn_deadline = time.monotonic() + TURN_SECONDS
        token = room.turn_token
        room.turn_timer_task = asyncio.create_task(
            self._turn_timeout(room, token)
        )

    async def _turn_timeout(self, room: Room, token: int) -> None:
        """Fires when the speaker's clock runs out: forfeit the round (0
        points), announce it, and advance — or end the match if it was the
        last round. Pushes events through the broadcaster since no client
        request is in flight to carry them."""
        try:
            await asyncio.sleep(TURN_SECONDS)
        except asyncio.CancelledError:
            return
        async with room.lock:
            if room.turn_token != token or room.phase is not RoomPhase.AWAITING_FACT:
                return  # the round moved on while we slept
            speaker_id = room.current_player_id
            events = [
                _event(
                    "turn_timed_out",
                    player_id=speaker_id,
                    round=room.round_number,
                )
            ]
            if room.round_number >= room.total_rounds:
                events.append(self._finish_match_locked(room))
            else:
                events.extend(self._begin_round_locked(room, advance_turn=True))
        if self._broadcaster is not None:
            try:
                await self._broadcaster(room, events)
            except Exception:  # a broken socket must not kill the timer chain
                logger.exception("Timer broadcast failed in room %s", room.code)

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
        room.current_country = self._country_provider(
            room.difficulty, room.round_number, room.total_rounds
        )
        room.current_fact = None
        room.ai_verdict = None
        room.votes = {}
        room.phase = RoomPhase.AWAITING_FACT
        self._arm_turn_timer_locked(room)
        return [
            _event(
                "next_turn",
                round=room.round_number,
                total_rounds=room.total_rounds,
                player_id=room.current_player_id,
                country=room.current_country,
                turn_seconds=TURN_SECONDS,
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
            self._cancel_turn_timer_locked(room)  # the fact beat the clock
            return [
                _event("fact_submitted", player_id=actor_id, fact=room.current_fact)
            ]

    async def evaluate_fact(self, room: Room) -> list[Event]:
        """Phase 2: run the AI evaluator (outside the lock — it may be slow)
        and open voting. Safe against phase races via a re-check. With zero
        eligible voters (solo testing) the AI verdict resolves immediately."""
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
            events = [
                _event(
                    "ai_verdict",
                    verdict=verdict.get("verdict", "unreliable"),
                    explanation=verdict.get("explanation", ""),
                    votes_needed=len(room.eligible_voters()),
                )
            ]
            if self._voting_complete_locked(room):
                events.extend(self._resolve_round_locked(room))
            return events

    async def submit_vote(
        self, room: Room, actor_id: str, accept: bool
    ) -> list[Event]:
        """Phase 3: eligible players vote; the last vote resolves the round."""
        async with room.lock:
            if room.phase is not RoomPhase.AWAITING_VOTES:
                raise RoomError("مش وقت التصويت دلوقتي.")
            if actor_id == room.current_player_id:
                raise RoomError("ممنوع تحكم على معلومتك بنفسك 😉")
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
                    votes_needed=len(room.eligible_voters()),
                )
            ]
            if self._voting_complete_locked(room):
                events.extend(self._resolve_round_locked(room))
            return events

    def _voting_complete_locked(self, room: Room) -> bool:
        eligible_ids = {p.id for p in room.eligible_voters()}
        return eligible_ids.issubset(room.votes.keys())

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

        if room.round_number >= room.total_rounds:
            events.append(self._finish_match_locked(room))
        else:
            events.extend(self._begin_round_locked(room, advance_turn=True))
        return events

    def _finish_match_locked(self, room: Room) -> Event:
        """All rounds played: highest score wins; a tie has no sole winner."""
        self._cancel_turn_timer_locked(room)
        room.phase = RoomPhase.FINISHED
        top = max((p.score for p in room.players.values()), default=0)
        leaders = [p for p in room.players.values() if p.score == top]
        sole_winner = leaders[0] if len(leaders) == 1 else None
        return _event(
            "game_over",
            reason="rounds_complete" if sole_winner else "tie",
            winner=sole_winner.public_info() if sole_winner else None,
            scores={p.id: p.score for p in room.players.values()},
        )

    # -- Disconnects -------------------------------------------------------

    async def handle_disconnect(self, room: Room, player_id: str) -> list[Event]:
        """Mark a player gone and keep the game consistent: skip their turn,
        drop their pending vote requirement, transfer host, or end the game
        if fewer than the minimum players remain mid-match."""
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
                self._cancel_turn_timer_locked(room)
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
                # The speaker vanished mid-turn — the round is forfeited but
                # still consumed, so the match can't loop past total_rounds.
                if room.round_number >= room.total_rounds:
                    events.append(self._finish_match_locked(room))
                else:
                    events.extend(
                        self._begin_round_locked(room, advance_turn=True)
                    )
            elif room.phase is RoomPhase.AWAITING_VOTES:
                room.votes.pop(player_id, None)
                if self._voting_complete_locked(room):
                    events.extend(self._resolve_round_locked(room))
            return events
