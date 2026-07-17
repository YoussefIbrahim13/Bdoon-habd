"""Player persistence for authenticated (online) features.

Environments:
- Local dev (zero-config): no DATABASE_URL → SQLite file next to backend/.
- Production: set DATABASE_URL to a hosted PostgreSQL URL (Neon/Supabase/
  Render Postgres). This is REQUIRED on Render — its free-tier disk is
  ephemeral, so a SQLite file silently resets on every deploy/restart.

Render/Heroku-style URLs may arrive as `postgres://...`, which SQLAlchemy
2.0 refuses (it wants `postgresql://`); the prefix is normalized here.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, String, create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


def _database_url() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        # Safe local fallback: zero-config SQLite for development.
        return "sqlite:///./players.db"
    # SQLAlchemy 2.0 dropped the legacy `postgres://` scheme that Render/
    # Heroku still emit — normalize it (first occurrence only).
    return url.replace("postgres://", "postgresql://", 1)


DATABASE_URL = _database_url()
_IS_SQLITE = DATABASE_URL.startswith("sqlite")

_engine = create_engine(
    DATABASE_URL,
    # SQLite: FastAPI runs sync endpoints in a threadpool, so the connection
    # hops threads; this flag only exists (and is needed) there.
    connect_args={"check_same_thread": False} if _IS_SQLITE else {},
    # Hosted Postgres (Neon/Supabase) drops idle connections; pre-ping
    # replaces dead ones transparently instead of failing the request, and
    # recycling keeps pooled connections younger than typical idle cutoffs.
    pool_pre_ping=not _IS_SQLITE,
    pool_recycle=300 if not _IS_SQLITE else -1,
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

    # Soft delete: set instead of removing the row, so stats/history survive
    # and accidental deletions are recoverable. Non-null ⇒ the account is
    # disabled: hidden from admin listings and rejected by every auth guard.
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )


def init_db() -> None:
    """Create tables on startup (idempotent), plus micro-migrations.

    create_all only creates MISSING tables — it never alters existing ones —
    so columns added after a table first shipped need explicit ADD COLUMN
    guards. The SQLAlchemy inspector makes the column check dialect-agnostic;
    only the ALTER's type syntax differs per dialect.
    """
    Base.metadata.create_all(_engine)

    existing = {col["name"] for col in inspect(_engine).get_columns("players")}
    if "deleted_at" not in existing:
        column_type = "TIMESTAMP" if _IS_SQLITE else "TIMESTAMP WITH TIME ZONE"
        with _engine.begin() as conn:
            conn.execute(
                text(f"ALTER TABLE players ADD COLUMN deleted_at {column_type} NULL")
            )


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request, always closed."""
    session = _SessionLocal()
    try:
        yield session
    finally:
        session.close()
