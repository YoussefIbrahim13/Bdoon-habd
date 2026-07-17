"""Player persistence for authenticated (online) features.

SQLite by default — zero-config for local dev. Set DATABASE_URL to a
Postgres URL in production for durability (on Render's free tier the local
disk is ephemeral: a SQLite file resets on every deploy/restart, which is
acceptable for testing the auth flow but not for real player stats).
"""

from __future__ import annotations

import os
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./players.db")

# check_same_thread only exists (and is needed) for SQLite: FastAPI runs sync
# endpoints in a threadpool, so the connection hops threads.
_engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {},
)
_SessionLocal = sessionmaker(bind=_engine, expire_on_commit=False)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Player(Base):
    """One authenticated player (Google account)."""

    __tablename__ = "players"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    # Google's stable unique user identifier (the ID token's `sub` claim).
    # THE identity key — email can change on a Google account, sub cannot.
    google_sub: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    email: Mapped[str] = mapped_column(String(320), index=True)
    name: Mapped[str] = mapped_column(String(200))
    picture: Mapped[str | None] = mapped_column(String(600), nullable=True)

    # Initial game stats provisioned at first sign-in.
    matches_played: Mapped[int] = mapped_column(Integer, default=0)
    wins: Mapped[int] = mapped_column(Integer, default=0)
    total_points: Mapped[int] = mapped_column(Integer, default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )
    last_login_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow
    )


def init_db() -> None:
    """Create tables on startup (idempotent)."""
    Base.metadata.create_all(_engine)


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request, always closed."""
    session = _SessionLocal()
    try:
        yield session
    finally:
        session.close()
