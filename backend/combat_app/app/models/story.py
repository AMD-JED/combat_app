"""
v9 — Stories.

A Story is ephemeral content (image/video/text) that expires 24h after
creation. Following the project's "lazy expiry" convention (no Celery/
background job scheduler available yet — see PROJECT_STATUS.md), expiry
is enforced purely at query time: `expires_at` is stored explicitly at
creation, and every read path filters `WHERE expires_at > now()`. Rows
are never hard-deleted by a scheduled job; they simply stop showing up
in the normal feed/view queries once expired. A user can still manually
DELETE a story before it expires (see StoryRepository / stories.py).

`content_type` and `visibility` are plain indexed VARCHAR — same
convention as `PostReaction.reaction_type` / `TrainingSession.session_type`
— so adding a new value later is a Python-only change with no ALTER TYPE
migration. Validation of the allowed values happens at the Pydantic layer
(see app/schemas/story.py).

Highlights let a user permanently pin a story to their profile past its
24h expiry. `HighlightStory` is a pure reference (story_id) — it does NOT
copy the story's content — because stories are never hard-deleted on
expiry (only filtered out), so the original row (and its media_url) stays
retrievable indefinitely once referenced by a highlight. The `ondelete=
"CASCADE"` on `HighlightStory.story_id` means: if the user manually
deletes a story that happens to be in one or more highlights, it is
automatically removed from those highlights too (confirmed decision —
no orphaned references, no blocking the delete).
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    DateTime,
    ForeignKey,
    func,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


def default_story_expiry() -> datetime:
    """24h from now, in UTC. Used as the Python-side default for
    `Story.expires_at` so it works identically on SQLite and PostgreSQL
    (no server-side function needed for a simple offset)."""
    return datetime.now(timezone.utc) + timedelta(hours=24)


class Story(Base):
    __tablename__ = "stories"

    id = Column(Integer, primary_key=True, index=True)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # image | video | text — see StoryContentType in app/schemas/story.py
    content_type = Column(String(10), nullable=False, index=True)
    media_url = Column(String(500), nullable=True)       # required for image/video
    text_content = Column(Text, nullable=True)            # required for text-only stories
    background_color = Column(String(20), nullable=True)  # optional, for text-only stories

    # public | followers — chosen by the author at posting time
    visibility = Column(String(20), nullable=False, default="public", index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=False, default=default_story_expiry, index=True)

    author = relationship("User", foreign_keys=[author_id])
    views = relationship("StoryView", back_populates="story", cascade="all, delete-orphan")
    highlight_entries = relationship("HighlightStory", back_populates="story", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<Story author={self.author_id} type={self.content_type}>"


class StoryView(Base):
    """One row per (story, viewer) — records that a user has seen a
    story, powering the 'seen by' list. Unique constraint means viewing
    the same story twice doesn't create duplicate rows."""
    __tablename__ = "story_views"
    __table_args__ = (
        UniqueConstraint("story_id", "viewer_id", name="uq_story_views_story_viewer"),
    )

    id = Column(Integer, primary_key=True, index=True)
    story_id = Column(Integer, ForeignKey("stories.id", ondelete="CASCADE"), nullable=False, index=True)
    viewer_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    viewed_at = Column(DateTime(timezone=True), server_default=func.now())

    story = relationship("Story", back_populates="views")
    viewer = relationship("User", foreign_keys=[viewer_id])

    def __repr__(self) -> str:
        return f"<StoryView story={self.story_id} viewer={self.viewer_id}>"


class Highlight(Base):
    """A named, permanent collection of stories pinned to a user's
    profile (mirrors Instagram Highlights)."""
    __tablename__ = "highlights"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String(50), nullable=False)
    cover_media_url = Column(String(500), nullable=True)  # optional custom cover; falls back to first story's media

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", foreign_keys=[user_id])
    items = relationship(
        "HighlightStory",
        back_populates="highlight",
        cascade="all, delete-orphan",
        order_by="HighlightStory.order_index",
    )

    def __repr__(self) -> str:
        return f"<Highlight user={self.user_id} title={self.title!r}>"


class HighlightStory(Base):
    """Junction row: one story pinned inside one highlight. Reference-only
    (see module docstring) — never copies story content."""
    __tablename__ = "highlight_stories"
    __table_args__ = (
        UniqueConstraint("highlight_id", "story_id", name="uq_highlight_stories_highlight_story"),
    )

    id = Column(Integer, primary_key=True, index=True)
    highlight_id = Column(Integer, ForeignKey("highlights.id", ondelete="CASCADE"), nullable=False, index=True)
    story_id = Column(Integer, ForeignKey("stories.id", ondelete="CASCADE"), nullable=False, index=True)
    order_index = Column(Integer, nullable=False, default=0)
    added_at = Column(DateTime(timezone=True), server_default=func.now())

    highlight = relationship("Highlight", back_populates="items")
    story = relationship("Story", back_populates="highlight_entries")

    def __repr__(self) -> str:
        return f"<HighlightStory highlight={self.highlight_id} story={self.story_id}>"
