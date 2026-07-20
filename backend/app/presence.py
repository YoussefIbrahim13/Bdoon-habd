"""Global online-presence registry for cross-cutting real-time pushes.

Room sockets in websocket.py are room-scoped, but friend requests span the
whole app — a request to someone sitting in a different room (or the online
hub) still needs to reach them. This module keeps a process-wide map of
player_id → their live WebSockets, updated by the game-socket handler on
connect/disconnect, so any feature can push an event to a player wherever
they are.

A player may have more than one socket (reconnects, two tabs), hence a set.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

_online: dict[str, set[Any]] = {}


def register(player_id: str, socket: Any) -> None:
    _online.setdefault(player_id, set()).add(socket)


def unregister(player_id: str, socket: Any) -> None:
    sockets = _online.get(player_id)
    if not sockets:
        return
    sockets.discard(socket)
    if not sockets:
        _online.pop(player_id, None)


def is_online(player_id: str) -> bool:
    return player_id in _online


async def notify(player_id: str, event: dict[str, Any]) -> bool:
    """Push one event to every live socket of a player. Returns True if at
    least one delivery was attempted. Never raises — a dead socket is just
    skipped (its own disconnect handler will clean it up)."""
    sockets = list(_online.get(player_id, ()))
    delivered = False
    for socket in sockets:
        try:
            await socket.send_json(event)
            delivered = True
        except Exception:
            logger.debug("Presence push to %s dropped", player_id)
    return delivered
